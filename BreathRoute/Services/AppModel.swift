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
    private var planGeneration = 0
    var demo = false
    var name: String { didSet { UserDefaults.standard.set(name, forKey: "displayName") } }
    var intensity: WalkingIntensity { didSet { UserDefaults.standard.set(intensity.rawValue, forKey: "intensity") } }
    let location = LocationService()
    let voice = VoiceService()
    let health = HealthService()
    let geofences = GeofenceService()
    var remainingOptions: [WalkRoute] = []
    var remainingBusy = false
    var remainingNotice: String?
    var routeNotice: String?
    var extraMinutes = 10.0
    private var remainingTask: Task<Void, Never>?
    private var plannedStart: CLLocationCoordinate2D?
    private var plannedDestination: MKMapItem?
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
        location.onUpdate = { [weak self] location in
            guard let self else { return }
            self.recordLocation(location)
            if self.activeRoute != nil { self.geofences.evaluate(location) }
        }
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
        planGeneration += 1; let ticket = planGeneration
        busy = true; routes = []; selectedRoute = nil; demo = false; air = nil; routeNotice = nil
        defer { if ticket == planGeneration { busy = false } }
        do {
            let planned = try await RouteService().routes(from: start, to: destination, intensity: intensity, key: KeyStore.read("openweather"))
            try Task.checkCancellation()
            guard ticket == planGeneration else { return }
            routes = planned
            plannedStart = start; plannedDestination = destination
            selectedRoute = routes.first?.id
            destinationName = destination.name ?? "Destination"
            if routes.count == 1 { routeNotice = "The provider returned one walking option. Alternative paths are not available for every request." }
        } catch is CancellationError { }
        catch { if ticket == planGeneration { self.error = error.localizedDescription } }
    }
    func cancelPlanning() { planGeneration += 1; busy = false }
    func start(_ route: WalkRoute) {
        remainingOptions = []; geofences.stop()
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
            trips.insert(entry, at: 0); activeRoute = nil; walkStarted = nil; location.stop(); voice.stop(); geofences.stop(); remainingTask?.cancel(); remainingOptions = []; section = .journal
        } catch { self.error = "Walk remains open because saving failed: \(error.localizedDescription)" }
    }
    var selected: WalkRoute? { routes.first { $0.id == selectedRoute } }
    var bestRouteID: UUID? {
        guard routes.allSatisfy(Self.freshForRecommendation) else { return nil }
        return RouteChoicePolicy.recommended(routes.map { RouteChoice(id: $0.id.uuidString, seconds: $0.seconds, dose: $0.estimate.observedDose, complete: $0.estimate.isComplete) }, extraMinutes: extraMinutes).flatMap(UUID.init(uuidString:))
    }
    var watchSamples: [WatchArea] {
        (activeRoute ?? selected)?.airSamples.compactMap { sample in
            guard let reading = sample.reading, !reading.demo else { return nil }
            return WatchArea(id: sample.id.uuidString, latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude, pm25: reading.pm25, aqi: reading.aqi, sampledAt: reading.date)
        } ?? []
    }
    var bestRemainingRouteID: String? {
        guard remainingOptions.allSatisfy(Self.freshForRecommendation) else { return nil }
        return RouteChoicePolicy.recommended(remainingOptions.map { RouteChoice(id: $0.id.uuidString, seconds: $0.seconds, dose: $0.estimate.observedDose, complete: $0.estimate.isComplete) }, extraMinutes: extraMinutes)
    }
    func addAvoidanceOption() async {
        guard activeRoute == nil, let start = plannedStart, let destination = plannedDestination else { return }
        let ticket = planGeneration; routeNotice = nil
        busy = true; defer { if ticket == planGeneration { busy = false } }
        do {
            let areas = avoidableAreas(from: start, to: destination.placemark.coordinate)
            guard !areas.isEmpty else { throw ServiceError.noAvoidableAreas }
            let options = try await RouteService().routes(from: start, to: destination, intensity: intensity, key: KeyStore.read("openweather"), avoiding: areas)
            try Task.checkCancellation()
            guard ticket == planGeneration, activeRoute == nil else { return }
            let previousCount = routes.count
            for option in options {
                if !routes.contains(where: { Self.samePath($0, option) }) { routes.append(option) }
            }
            if routes.count == previousCount { routeNotice = "The provider returned an existing path. No distinct avoidance option was added." }
        } catch is CancellationError { }
        catch { if ticket == planGeneration { self.error = error.localizedDescription } }
    }
    func compareRemaining(avoidAreas: Bool) {
        guard let route = activeRoute, !route.demo else { return }
        guard let current = location.currentLocation else { location.request(); error = "A recent accurate location is needed. Try Compare from here after a new location update."; return }
        let destination = plannedDestination ?? route.coordinates.last.map { MKMapItem(placemark: MKPlacemark(coordinate: $0)) }
        guard let destination else { return }
        remainingTask?.cancel(); remainingBusy = true; remainingOptions = []; remainingNotice = nil
        remainingTask = Task {
            defer { remainingBusy = false }
            do {
                var options = try await RouteService().routes(from: current.coordinate, to: destination, intensity: intensity, key: KeyStore.read("openweather"))
                if avoidAreas {
                    let areas = avoidableAreas(from: current.coordinate, to: destination.placemark.coordinate)
                    if !areas.isEmpty {
                        do {
                            let detours = try await RouteService().routes(from: current.coordinate, to: destination, intensity: intensity, key: KeyStore.read("openweather"), avoiding: areas)
                            for detour in detours where !options.contains(where: { Self.samePath($0, detour) }) { options.append(detour) }
                        } catch is CancellationError { throw CancellationError() }
                        catch { remainingNotice = error.localizedDescription + " The available baseline options remain below." }
                    } else { remainingNotice = "No eligible fresh areas can be excluded from this journey. Available walking options were compared." }
                }
                try Task.checkCancellation()
                guard activeRoute != nil else { return }
                remainingOptions = options
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    func switchRemaining(to route: WalkRoute) {
        guard activeRoute != nil, !route.demo else { return }
        // Keep elapsed session, recorded movement and completed exposure intervals intact.
        activeRoute = route; routes = [route]; selectedRoute = route.id; remainingOptions = []
        remainingNotice = nil
        geofences.replace(samples: watchSamples); geofences.clearEntry()
        trackingMessage = "Remaining route changed. Completed recorded intervals are preserved."
    }
    private func avoidableAreas(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> [WatchArea] {
        WatchAreaPolicy.select(watchSamples, now: Date()).filter {
            !$0.contains(latitude: start.latitude, longitude: start.longitude) && !$0.contains(latitude: end.latitude, longitude: end.longitude)
        }
    }
    private static func samePath(_ a: WalkRoute, _ b: WalkRoute) -> Bool {
        a.coordinates.count == b.coordinates.count && zip(a.coordinates, b.coordinates).allSatisfy { abs($0.latitude - $1.latitude) < 0.00001 && abs($0.longitude - $1.longitude) < 0.00001 }
    }
    private static func freshForRecommendation(_ route: WalkRoute) -> Bool {
        route.demo || (!route.airSamples.isEmpty && route.airSamples.allSatisfy { $0.reading?.isFresh == true })
    }
}
