import Foundation
import Observation
import CoreLocation
import AVFoundation
import LocalAuthentication
import UserNotifications
import Security

@MainActor @Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var location: CLLocation?
    var message = "Location is optional. You can search for a start point instead."
    var onUpdate: ((CLLocation) -> Void)?
    var hasAuthorization: Bool { manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways }
    var currentLocation: CLLocation? {
        guard let location, abs(location.timestamp.timeIntervalSinceNow) < 60 else { return nil }
        return location
    }
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest; manager.distanceFilter = 10 }
    func request() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if currentLocation == nil { manager.stopUpdatingLocation() }
            manager.startUpdatingLocation()
        default: message = "Location access is unavailable. Use a manual start or change access in Settings."
        }
    }
    func stop() { manager.stopUpdatingLocation() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        } else if manager.authorizationStatus == .denied { message = "Location denied. Manual route search still works." }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0,
              latest.horizontalAccuracy <= 100, abs(latest.timestamp.timeIntervalSinceNow) < 30 else { return }
        location = latest; message = "Location available"; onUpdate?(latest)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { message = error.localizedDescription }
}

@MainActor
final class VoiceService {
    private let synthesizer = AVSpeechSynthesizer()
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

enum KeyStore {
    static func save(_ value: String, key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "BreatheRoute", kSecAttrAccount as String: key]
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
        } else if status != errSecSuccess { throw CocoaError(.fileWriteUnknown) }
    }
    static func read(_ key: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "BreatheRoute", kSecAttrAccount as String: key,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

@MainActor
final class ReminderService {
    func setDeparture(at date: Date) async throws -> Bool {
        guard date.timeIntervalSinceNow >= 30 else { throw CocoaError(.coderInvalidValue) }
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
        guard date.timeIntervalSinceNow >= 1 else { throw CocoaError(.coderInvalidValue) }
        let content = UNMutableNotificationContent()
        content.title = "Time to review your walk"
        content.body = "Check current routes and air quality before leaving. Forecast conditions may have changed."
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: "departure-plan", content: content,
                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)))
        return true
    }
    func cancelDeparture() { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["departure-plan"]) }
    func setDaily(enabled: Bool, at date: Date) async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["daily-check-in"])
        guard enabled else { return false }
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
        let content = UNMutableNotificationContent()
        content.title = "A moment for your daily check-in"
        content.body = "Review your walks or add a symptom note in BreatheRoute."
        content.sound = .default
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        try await center.add(UNNotificationRequest(identifier: "daily-check-in", content: content,
                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
        return true
    }
}
