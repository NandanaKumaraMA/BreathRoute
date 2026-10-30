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
    private(set) var preview: WalkingPreviewPlayback?
    private var simulationGeneration = 0
    private var deviceLocation: CLLocation?
    var isSimulatingRun: Bool { preview?.state == .playing }
    var isPreviewLocation: Bool { preview != nil }
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

    /// Synthetic location is kept separate from the device location and resumes at the same point.
    @discardableResult func prepareSimulation(along coordinates: [CLLocationCoordinate2D], speedMps: Double,
                                              startingMetres: Double = 0, movingSeconds: Double = 0) -> Bool {
        guard let player = try? WalkingPreviewPlayback(coordinates: coordinates.map(GeoCoordinate.init), speed: speedMps,
                                                       startingMetres: startingMetres, movingSeconds: movingSeconds) else { return false }
        stopSimulation(); preview = player; publishPreview(); return true
    }
    func resumeSimulation() {
        guard preview != nil, preview?.state != .completed, !isSimulatingRun else { return }
        simulationGeneration += 1; let ticket = simulationGeneration
        preview?.play(); publishPreview()
        simulationTask = Task { @MainActor [weak self] in
            var lastTick = Date()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, self.simulationGeneration == ticket, self.isSimulatingRun else { return }
                let now = Date(), elapsed = min(1.5, max(0, now.timeIntervalSince(lastTick)))
                lastTick = now; self.preview?.advance(seconds: elapsed); self.publishPreview()
                if self.preview?.state == .completed { return }
            }
        }
    }
    func pauseSimulation() {
        simulationGeneration += 1; simulationTask?.cancel(); simulationTask = nil
        preview?.pause(); speedMetersPerSecond = 0
        message = preview?.state == .completed ? "Destination reached." : "Walk preview paused."
    }
    func stopSimulation() {
        simulationGeneration += 1; simulationTask?.cancel(); simulationTask = nil
        let wasPreview = preview != nil
        preview = nil; speedMetersPerSecond = 0
        if wasPreview { location = deviceLocation }
    }
    private func publishPreview() {
        guard let preview else { return }
        let coordinate = preview.coordinate.mapCoordinate
        let speed = preview.state == .playing ? preview.speed : 0
        headingDegrees = Self.bearing(from: coordinate, to: preview.nextCoordinate.mapCoordinate)
        speedMetersPerSecond = speed
        let fix = CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 4, verticalAccuracy: -1,
                             course: headingDegrees, speed: speed, timestamp: Date())
        location = fix
        message = preview.state == .completed ? "Destination reached." : "Route preview location."
        onUpdate?(fix)
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
        guard !isPreviewLocation else { return }
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        if heading >= 0 { headingDegrees = heading }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0,
              latest.horizontalAccuracy <= 100, abs(latest.timestamp.timeIntervalSinceNow) < 30 else { return }
        let previous = deviceLocation; deviceLocation = latest
        guard !isPreviewLocation else { return }
        location = latest
        if latest.speed.isFinite && latest.speed >= 0 { speedMetersPerSecond = latest.speed }
        else if let previous {
            speedMetersPerSecond = GPSWalkingSpeed.estimate(metres: latest.distance(from: previous),
                seconds: latest.timestamp.timeIntervalSince(previous.timestamp), previousAccuracy: previous.horizontalAccuracy,
                accuracy: latest.horizontalAccuracy) ?? 0
        } else { speedMetersPerSecond = 0 }
        if latest.course >= 0 { headingDegrees = latest.course }
        altitudeMeters = latest.altitude; message = "Location available"; onUpdate?(latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        message = error.localizedDescription
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
