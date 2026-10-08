import CoreLocation
import UserNotifications
import Observation

@MainActor @Observable
final class GeofenceService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var gate = AreaEntryGate()
    private var expiryTask: Task<Void, Never>?
    private var lastLocation: CLLocation?
    private var generation = 0
    private let prefix = "BreatheRoute.air."
    private(set) var enabled = false
    private(set) var areas: [WatchArea] = []
    private(set) var message = "Area alerts are off."
    private(set) var entry: WatchArea?
    private(set) var entryTime: Date?
    private(set) var notificationAllowed = false
    var hasAlwaysAccess: Bool { manager.authorizationStatus == .authorizedAlways }
    override init() {
        super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest
        // The current app does not recover active sessions after relaunch. Remove their obsolete registrations.
        removeRegions()
    }
    func enable(samples: [WatchArea]) async {
        stop(); let ticket = generation; enabled = true; areas = WatchAreaPolicy.select(samples, now: Date())
        guard !areas.isEmpty else { register(); return }
        let centre = UNUserNotificationCenter.current()
        let allowed = (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        guard enabled, ticket == generation else { return }
        notificationAllowed = allowed
        register()
        expiryTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)); try Task.checkCancellation() } catch { return }
                guard let self, self.enabled else { return }
                self.areas = self.areas.filter { $0.isUsable(at: Date()) }; self.register()
            }
        }
    }
    func replace(samples: [WatchArea]) {
        guard enabled else { return }
        areas = WatchAreaPolicy.select(samples, now: Date()); register()
    }
    func requestBackgroundAwareness() {
        guard enabled else { return }
        manager.requestAlwaysAuthorization()
    }
    func evaluate(_ location: CLLocation, source: String = "Foreground location") {
        guard enabled, abs(location.timestamp.timeIntervalSinceNow) < 60 else { return }
        lastLocation = location
        guard let area = gate.update(areas: areas, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy, now: Date()) else { return }
        entry = area; entryTime = Date()
        message = "Entered a sampled monitoring area · \(source)."
        guard notificationAllowed else { return }
        let content = UNMutableNotificationContent()
        content.title = "Air-quality awareness"
        content.body = "You are inside a sampled AQI \(area.aqi)/5 area. Open BreatheRoute to review data and compare your remaining walk. The circle is approximate."
        content.sound = .default
        Task { try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: prefix + "entry", content: content, trigger: nil)) }
    }
    func clearEntry() { entry = nil; entryTime = nil }
    func stop() {
        generation += 1
        enabled = false; expiryTask?.cancel(); expiryTask = nil; removeRegions()
        areas = []; gate = AreaEntryGate(); clearEntry(); lastLocation = nil
        message = "Area alerts are off."
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [prefix + "entry"])
    }
    private func removeRegions() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(prefix) { manager.stopMonitoring(for: region) }
    }
    private func register() {
        removeRegions()
        guard enabled else { return }
        guard !areas.isEmpty else { message = "No fresh AQI 3–5 sample areas to monitor. Missing or low-category readings do not create watch areas."; return }
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            message = "Location access is unavailable. Area entries cannot be verified; the route and sample details remain available."
            return
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self), hasAlwaysAccess else {
            message = "\(areas.count) sample areas · awareness while the app is open. Always location access is needed for native region events."
            return
        }
        let room = max(0, 20 - manager.monitoredRegions.filter { !$0.identifier.hasPrefix(prefix) }.count)
        for area in areas.prefix(room) {
            let radius = min(area.radius, manager.maximumRegionMonitoringDistance)
            guard radius > 0 else { continue }
            let region = CLCircularRegion(center: .init(latitude: area.latitude, longitude: area.longitude), radius: radius, identifier: prefix + area.id)
            region.notifyOnEntry = true; region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
        message = "\(min(room, areas.count)) native monitoring areas requested. Region events can be delayed; foreground checks remain available."
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if enabled { register() } }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard enabled, areas.contains(where: { prefix + $0.id == region.identifier && $0.isUsable(at: Date()) }) else { return }
        if let lastLocation, abs(lastLocation.timestamp.timeIntervalSinceNow) < 60 {
            evaluate(lastLocation, source: "Core Location region event")
        } else { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let latest = locations.last { evaluate(latest, source: "Core Location region event") }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if enabled { message = "Region event could not be verified with a recent accurate location. Foreground checks continue." }
    }
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if enabled { message = "Native monitoring is unavailable for an area. Awareness remains available while the app is open." }
    }
}
