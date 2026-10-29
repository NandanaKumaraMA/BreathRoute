import Foundation
import Observation
import CoreLocation
import AVFoundation
import LocalAuthentication
import UserNotifications
import Security

/// Provider keys supplied by AppConfig.xcconfig and the ignored local build file.
enum APIConfig {
    static let openWeatherKey: String = {
        if let env = ProcessInfo.processInfo.environment["OPENWEATHER_API_KEY"], !env.isEmpty { return env }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "OPENWEATHER_API_KEY") as? String, !plist.isEmpty { return plist }
        return "YOUR_OPENWEATHER_API_KEY"
    }()

    static let openRouteServiceKey: String = {
        if let env = ProcessInfo.processInfo.environment["OPENROUTESERVICE_API_KEY"], !env.isEmpty { return env }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "OPENROUTESERVICE_API_KEY") as? String, !plist.isEmpty { return plist }
        return "YOUR_OPENROUTESERVICE_API_KEY"
    }()

    static let geoapifyKey: String = {
        if let env = ProcessInfo.processInfo.environment["GEOAPIFY_API_KEY"], !env.isEmpty { return env }
        return Bundle.main.object(forInfoDictionaryKey: "GEOAPIFY_API_KEY") as? String ?? ""
    }()

    static func resolved(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("YOUR_") || trimmed.hasPrefix("$(") { return "" }
        return trimmed
    }
}

enum KeyStore {
    static func read(_ key: String) -> String {
        switch key {
        case "openweather": return APIConfig.resolved(APIConfig.openWeatherKey)
        case "openrouteservice": return APIConfig.resolved(APIConfig.openRouteServiceKey)
        case "geoapify": return APIConfig.resolved(APIConfig.geoapifyKey)
        default: return ""
        }
    }
}

@MainActor @Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @ObservationIgnored private var simulationTask: Task<Void, Never>?
    var location: CLLocation?
    var headingDegrees: Double = 0
    var speedMetersPerSecond: Double = 0
    var altitudeMeters: Double = 0
    var isSimulatingRun = false
    var message = "Location is optional. You can search for a start point instead."
    var onUpdate: ((CLLocation) -> Void)?

    var hasAuthorization: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }
    var currentLocation: CLLocation? {
        guard let location, abs(location.timestamp.timeIntervalSinceNow) < 60 else { return nil }
        return location
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5
        manager.headingFilter = 2
    }

    /// Switches Core Location between standard exploration and high-frequency navigation tracking for live running/walking.
    func setNavigationMode(_ active: Bool) {
        manager.desiredAccuracy = active ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyBest
        manager.distanceFilter = active ? 2 : 8
        if active && CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        } else {
            manager.stopUpdatingHeading()
        }
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if currentLocation == nil { manager.stopUpdatingLocation() }
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        default:
            message = "Location access is unavailable. Use a manual start or change access in Settings."
        }
    }

    func stop() {
        stopSimulation()
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// Real-time GPS + heading stream along a route for testing live 3D running/walking navigation in Simulator or demo mode.
    func startSimulatedRun(along coordinates: [CLLocationCoordinate2D], speedMps: Double = 2.8) {
        stopSimulation()
        guard coordinates.count > 1 else { return }
        isSimulatingRun = true
        let interpolated = Self.interpolate(coordinates: coordinates, stepMeters: speedMps)
        simulationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for index in 0..<interpolated.count {
                if Task.isCancelled { break }
                let coord = interpolated[index]
                let nextCoord = interpolated[min(index + 1, interpolated.count - 1)]
                let course = Self.bearing(from: coord, to: nextCoord)
                self.headingDegrees = course
                self.speedMetersPerSecond = speedMps
                let simulated = CLLocation(
                    coordinate: coord,
                    altitude: 12.0,
                    horizontalAccuracy: 4.0,
                    verticalAccuracy: 4.0,
                    course: course,
                    speed: speedMps,
                    timestamp: Date()
                )
                self.location = simulated
                self.message = "Live navigation active"
                self.onUpdate?(simulated)
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
            self.isSimulatingRun = false
            self.speedMetersPerSecond = 0
        }
    }

    func stopSimulation() {
        simulationTask?.cancel()
        simulationTask = nil
        isSimulatingRun = false
        speedMetersPerSecond = 0
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        } else if manager.authorizationStatus == .denied {
            message = "Location denied. Manual route search still works."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard !isSimulatingRun else { return }
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        if heading >= 0 { headingDegrees = heading }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !isSimulatingRun, let latest = locations.last, latest.horizontalAccuracy >= 0,
              latest.horizontalAccuracy <= 100, abs(latest.timestamp.timeIntervalSinceNow) < 30 else { return }
        location = latest
        if latest.speed >= 0 { speedMetersPerSecond = latest.speed }
        if latest.course >= 0 { headingDegrees = latest.course }
        altitudeMeters = latest.altitude
        message = "Location available"
        onUpdate?(latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        message = error.localizedDescription
    }

    private static func interpolate(coordinates: [CLLocationCoordinate2D], stepMeters: Double) -> [CLLocationCoordinate2D] {
        var result: [CLLocationCoordinate2D] = []
        for i in 0..<(coordinates.count - 1) {
            let a = coordinates[i], b = coordinates[i + 1]
            let dist = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            let steps = max(1, Int(ceil(dist / max(1.0, stepMeters))))
            for s in 0..<steps {
                let t = Double(s) / Double(steps)
                result.append(CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                                     longitude: a.longitude + (b.longitude - a.longitude) * t))
            }
        }
        if let last = coordinates.last { result.append(last) }
        return result
    }

    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180, lon2 = b.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        return (radians * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
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
