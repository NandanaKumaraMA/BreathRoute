import SwiftUI
import Observation
import MapKit

@MainActor @Observable
final class AppModel {
    var section: AppSection = .today
    var symptoms: [SymptomEntry] = []
    var trips: [TripEntry] = []
    var routes: [WalkRoute] = []
    var selectedRoute: UUID?
    var air: AirReading?
    var error: String?
    var busy = false
    var demo = false
    var name: String { didSet { UserDefaults.standard.set(name, forKey: "displayName") } }
    var intensity: WalkingIntensity { didSet { UserDefaults.standard.set(intensity.rawValue, forKey: "intensity") } }
    let location = LocationService()
    let voice = VoiceService()
    let health = HealthService()
    private var repository: LocalStore?
    var persistenceAvailable: Bool { repository != nil }
    var activeRoute: WalkRoute?
    var walkStarted: Date?
    var trackedMetres = 0.0
    var trackedSeconds = 0.0
    var trackedSegments: [ExposureSegment] = []
    var trackingMessage = "Waiting for accurate location updates."
    private var lastLocation: CLLocation?
    private var lastRefresh: Date?
    private var refreshing = false
    private var destinationName = "Walk"
    private var foreground = true
    var activeEstimate: ExposureEstimate { ExposureCalculator.estimate(trackedSegments, ventilation: intensity.ventilation) }

    init() {
        name = UserDefaults.standard.string(forKey: "displayName") ?? ""
        intensity = WalkingIntensity(rawValue: UserDefaults.standard.string(forKey: "intensity") ?? "") ?? .easy
        do {
            repository = try LocalStore()
            symptoms = try repository!.read("symptom", as: SymptomEntry.self).sorted { $0.date > $1.date }
            trips = try repository!.read("trip", as: TripEntry.self).sorted { $0.date > $1.date }
        } catch { self.error = "Local storage could not be opened. Your existing data has not been reset. \(error.localizedDescription)" }
        location.onUpdate = { [weak self] in self?.recordLocation($0) }
    }
    func save(_ entry: SymptomEntry) -> Bool {
        guard let repository else { error = "Local storage is unavailable. Your note has not been saved."; return false }
        do {
            try repository.save(entry, id: entry.id, kind: "symptom")
            symptoms.removeAll { $0.id == entry.id }; symptoms.append(entry); symptoms.sort { $0.date > $1.date }; return true
        } catch { self.error = "Could not save the symptom: \(error.localizedDescription)"; return false }
    }
    func deleteSymptom(_ entry: SymptomEntry) {
        do { try repository?.delete(id: entry.id); symptoms.removeAll { $0.id == entry.id } }
        catch { self.error = error.localizedDescription }
    }
    func deleteTrip(_ entry: TripEntry) {
        // Linked notes are preserved; the UI treats a deleted trip as unavailable.
        do { try repository?.delete(id: entry.id); trips.removeAll { $0.id == entry.id } }
        catch { self.error = error.localizedDescription }
    }
    func loadDemo() {
        guard activeRoute == nil else { return }
        demo = true
        air = AirReading(pm25: 14, aqi: 2, date: Date(), demo: true)
        routes = RouteService.demoRoutes(intensity: intensity); selectedRoute = routes.first?.id
        section = .routes
    }
    func leaveDemo() { guard activeRoute == nil else { return }; demo = false; air = nil; routes = []; selectedRoute = nil }
    func refreshAir() async {
        guard !demo else { return }
        guard let coordinate = location.location?.coordinate else {
            location.request(); error = "Allow location and wait for a fix, then refresh. Manual route search is also available in Explore."; return
        }
        busy = true; defer { busy = false }
        do { air = try await AirService().fetch(at: coordinate, key: KeyStore.read("openweather")) }
        catch { self.error = error.localizedDescription }
    }
    func plan(start: CLLocationCoordinate2D, destination: MKMapItem) async {
        busy = true; routes = []; selectedRoute = nil; demo = false; air = nil
        defer { busy = false }
        do {
            routes = try await RouteService().routes(from: start, to: destination, intensity: intensity, key: KeyStore.read("openweather"))
            selectedRoute = routes.first?.id
            destinationName = destination.name ?? "Destination"
        } catch { self.error = error.localizedDescription }
    }
    func start(_ route: WalkRoute) {
        activeRoute = route; walkStarted = Date(); trackedMetres = 0; trackedSeconds = 0; trackedSegments = []; lastLocation = nil; lastRefresh = nil
        trackingMessage = route.demo ? "Demo session: no live movement or exposure is recorded." : "Foreground tracking. Keep the app open; background intervals are excluded."
        if !route.demo { location.request() }
    }
    func setForeground(_ active: Bool) {
        foreground = active
        if !active { lastLocation = nil }
        if active && activeRoute != nil { trackingMessage = "Tracking resumed. Any background gap is excluded." }
    }
    private func recordLocation(_ current: CLLocation) {
        guard foreground, let route = activeRoute, !route.demo else { return }
        defer { lastLocation = current }
        if let previous = lastLocation {
            let seconds = current.timestamp.timeIntervalSince(previous.timestamp)
            let metres = current.distance(from: previous)
            if seconds > 0 && seconds <= 30 && metres / seconds < 4 {
                trackedSeconds += seconds; trackedMetres += metres
                let reading = air
                let pm = reading?.demo == false && reading?.isFresh == true ? reading?.pm25 : nil
                trackedSegments.append(.init(minutes: seconds / 60, pm25: pm))
                trackingMessage = pm == nil ? "GPS active. Pollution data unavailable for this interval." : "GPS active. Dose uses the latest available modelled pollution reading."
            } else { trackingMessage = "A tracking gap or inaccurate jump was excluded." }
        }
        if !refreshing && (lastRefresh == nil || Date().timeIntervalSince(lastRefresh!) > 60) {
            refreshing = true; lastRefresh = Date()
            Task {
                defer { refreshing = false }
                do { air = try await AirService().fetch(at: current.coordinate, key: KeyStore.read("openweather")) }
                catch { air = nil; trackingMessage = "GPS active. Air-quality update failed; exposure coverage is incomplete." }
            }
        }
    }
    func finish() {
        guard let route = activeRoute, let start = walkStarted, let repository else { error = "No active walk or storage unavailable."; return }
        let estimate = activeEstimate
        let entry = TripEntry(date: start, destination: route.demo ? "Demo · \(route.name)" : destinationName,
                              metres: trackedMetres, seconds: max(0, Date().timeIntervalSince(start)),
                              dose: estimate.observedDose, coverage: trackedSeconds > 0 ? min(1, estimate.coverage * trackedSeconds / max(1, Date().timeIntervalSince(start))) : 0,
                              demo: route.demo, complete: false)
        do {
            try repository.save(entry, id: entry.id, kind: "trip")
            trips.insert(entry, at: 0); activeRoute = nil; walkStarted = nil; location.stop(); voice.stop(); section = .journal
        } catch { self.error = "Walk remains open because saving failed: \(error.localizedDescription)" }
    }
    var selected: WalkRoute? { routes.first { $0.id == selectedRoute } }
    var bestRouteID: UUID? {
        guard routes.count > 1, routes.allSatisfy({ $0.estimate.isComplete && $0.estimate.observedDose != nil }) else { return nil }
        let sorted = routes.sorted { $0.estimate.observedDose! < $1.estimate.observedDose! }
        guard sorted[1].estimate.observedDose! - sorted[0].estimate.observedDose! > 0.1 else { return nil }
        return sorted[0].id
    }
}
