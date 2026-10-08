import Foundation
import Observation
import CoreLocation
import AVFoundation
import LocalAuthentication
import UserNotifications
import HealthKit
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

@MainActor @Observable
final class HealthService {
    private let store = HKHealthStore()
    var summary = "Optional health context. No readings imported."
    var heartRate: Double?
    var respiratoryRate: Double?
    func connect() async {
        guard HKHealthStore.isHealthDataAvailable(),
              let heart = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let respiration = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else {
            summary = "Apple Health is unavailable on this device."; return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [heart, respiration])
            heartRate = try await latest(heart)
            respiratoryRate = try await latest(respiration)
            // HealthKit does not disclose whether read permission was denied.
            summary = heartRate == nil && respiratoryRate == nil ? "No recent readable samples. Your walking-intensity estimate remains available." : "Recent samples from the past hour. Stored only on this device; not used to infer lung volume."
        } catch { summary = "Health data could not be read: \(error.localizedDescription)" }
    }
    private func latest(_ type: HKQuantityType) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-3600), end: Date(), options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}

@MainActor
final class ReminderService {
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
