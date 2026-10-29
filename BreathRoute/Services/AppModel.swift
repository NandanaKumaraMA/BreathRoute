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
    var cleanAirOnly = false
    var followCamera = true
    var pitch3D = true
    var air: AirReading?
    private(set) var airNotice: String?
    var error: String?
    var busy = false
    private var planGeneration = 0
    var demo = false
    private(set) var accountScopeKey = "guest"
    var name: String { didSet { UserDefaults.standard.set(name, forKey: profileKey("displayName")) } }
    var intensity: WalkingIntensity { didSet { UserDefaults.standard.set(intensity.rawValue, forKey: profileKey("intensity")) } }
    let account = AccountService()
    var canChangeAccount: Bool { activeRoute == nil && pendingRecovery == nil && !unreadableRecovery && !busy && !remainingBusy && !account.working && !health.isReadingActivity && !health.isReadingVitals }
    let location = LocationService()
    let voice = VoiceService()
    let health = HealthService()
    let forecasts = ForecastService()
    let motion = MotionService()
    private(set) var motionTrackingEnabled: Bool
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
    private var recorder = WalkRecorder()
    var trackedMetres: Double { recorder.metres }
    var trackedSeconds: Double { recorder.recordedSeconds }
    var trackedSegments: [ExposureSegment] { recorder.segments }
    var recordedPath: [RecordedPathPoint] { recorder.path }
    private(set) var pendingRecovery: ActiveWalkCheckpoint?
    private(set) var unreadableRecovery = false
    private(set) var lastCheckpoint: Date?
    private(set) var checkpointMessage: String?
    private var sessionID: UUID?
    private var sessionVentilation: Double?
    private var recoveredSession = false
    @ObservationIgnored private var checkpointTimer: Timer?
    var trackingMessage = "Waiting for accurate location updates."
    private var lastRefresh: Date?
    private var refreshing = false
    private var destinationName = "Walk"
    private var foreground = true
    var activeEstimate: ExposureEstimate { ExposureCalculator.estimate(trackedSegments, ventilation: sessionVentilation ?? intensity.ventilation) }

    /// Routes filtered by the user's "Clean-air paths only" preference when clean paths exist.
    var displayedRoutes: [WalkRoute] {
        guard cleanAirOnly else { return routes }
        let clean = routes.filter(\.isCleanAirPath)
        return clean.isEmpty ? routes : clean
    }

    /// Live running/walking speed in km/h from Core Location or Core Motion pace.
    var liveSpeedKmh: Double {
        if location.speedMetersPerSecond > 0.2 {
            return location.speedMetersPerSecond * 3.6
        }
        if let pace = motion.currentPace, pace > 0 {
            return 60.0 / pace
        }
        return 0
    }

    /// Formatted live pace (min/km) for the real-time running/walking HUD.
    var livePaceLabel: String {
        if let pace = motion.currentPace, pace > 0, pace < 35 {
            let mins = Int(pace)
            let secs = Int((pace - Double(mins)) * 60)
            return String(format: "%d'%02d\"/km", mins, secs)
        }
        let speed = location.speedMetersPerSecond
        if speed > 0.3 {
            let paceMinPerKm = (1000.0 / speed) / 60.0
            let mins = Int(paceMinPerKm)
            let secs = Int((paceMinPerKm - Double(mins)) * 60)
            return String(format: "%d'%02d\"/km", mins, secs)
        }
        return "—/km"
    }

    /// True when the user's live speed or motion state indicates running/jogging.
    var isRunningLive: Bool {
        location.speedMetersPerSecond >= 2.1 || (motion.currentCadence ?? 0) >= 135 || intensity == .fast
    }

    /// Remaining distance in metres along the active route.
    var remainingDistanceMetres: Double {
        guard let route = activeRoute else { return 0 }
        if let current = location.currentLocation ?? location.location, let end = route.coordinates.last {
            let direct = current.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
            return max(0, min(route.metres, max(direct, route.metres - trackedMetres)))
        }
        return max(0, route.metres - trackedMetres)
    }

    /// Next turn-by-turn navigation instruction along the active route.
    var nextRouteStep: RouteStep? {
        guard let route = activeRoute, !route.steps.isEmpty else { return nil }
        guard let current = location.currentLocation ?? location.location else { return route.steps.first }
        return route.steps.min { a, b in
            let da = current.distance(from: CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude))
            let db = current.distance(from: CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude))
            return da < db
        }
    }

    init() {
        name = UserDefaults.standard.string(forKey: "displayName") ?? ""
        intensity = WalkingIntensity(rawValue: UserDefaults.standard.string(forKey: "intensity") ?? "") ?? .easy
        motionTrackingEnabled = UserDefaults.standard.bool(forKey: "motionTrackingEnabled")
        openJournal(accountNamespace: nil)
        location.onUpdate = { [weak self] location in
            guard let self else { return }
            self.recordLocation(location)
            if self.activeRoute != nil { self.geofences.evaluate(location) }
        }
    }
    func startAccountObservation() {
        account.onIdentityChange = { [weak self] identity in self?.changeAccount(to: identity) }
        account.start()
    }
    private func profileKey(_ key: String) -> String { accountScopeKey == "guest" ? key : "\(accountScopeKey).\(key)" }
    private func changeAccount(to identity: AccountIdentity?) {
        let next = identity?.journalNamespace ?? "guest"
        guard next != accountScopeKey else { return }
        let interrupted = activeRoute != nil
        if interrupted { checkpoint() }
        stopRecording(); cancelPlanning(); remainingTask?.cancel()
        routes = []; selectedRoute = nil; demo = false; air = nil; airNotice = nil; plannedStart = nil; plannedDestination = nil
        routeNotice = nil; remainingNotice = nil; remainingBusy = false; refreshing = false
        symptoms = []; trips = []; pendingRecovery = nil; unreadableRecovery = false; repository = nil
        accountScopeKey = next; health.resetForAccountChange(); forecasts.clearForAccountChange()
        name = UserDefaults.standard.string(forKey: profileKey("displayName")) ?? ""
        intensity = WalkingIntensity(rawValue: UserDefaults.standard.string(forKey: profileKey("intensity")) ?? "") ?? .easy
        openJournal(accountNamespace: identity?.journalNamespace); section = .profile
        if interrupted { error = "The account session changed. The unfinished walk remains saved in its original journal. Sign back into that account to recover it." }
    }
    private func openJournal(accountNamespace: String?) {
        do { repository = try LocalStore(accountNamespace: accountNamespace) }
        catch { self.error = "This journal could not be opened. Existing data has not been reset."; return }
        guard let repository else { return }
        do { symptoms = try repository.read("symptom", as: SymptomEntry.self).sorted { $0.date > $1.date } }
        catch { self.error = "Symptom records could not be read. They have not been reset." }
        do { trips = try repository.read("trip", as: TripEntry.self).sorted { $0.date > $1.date } }
        catch { self.error = "Walk records could not be read. They have not been reset." }
        do {
            let drafts = try repository.read("active-walk", as: ActiveWalkCheckpoint.self)
            if let draft = drafts.first {
                guard drafts.count == 1, draft.isValid else { throw CocoaError(.coderReadCorrupt) }
                pendingRecovery = draft; section = .routes
            }
        } catch { unreadableRecovery = true; checkpointMessage = "An unfinished walk could not be read. It remains stored; discard it explicitly before starting another walk." }
    }
    func save(_ entry: SymptomEntry) -> Bool {
        guard let repository else { error = "Local storage is unavailable. Your note has not been saved."; return false }
        do {
            try repository.save(entry, id: entry.id, kind: "symptom")
            symptoms.removeAll { $0.id == entry.id }; symptoms.append(entry); symptoms.sort { $0.date > $1.date }; return true
        } catch { self.error = "Could not save the symptom: \(error.localizedDescription)"; return false }
    }
    func deleteSymptom(_ entry: SymptomEntry) {
        guard let repository else { error = "Local storage is unavailable. The note has not been deleted."; return }
        do { try repository.delete(id: entry.id); symptoms.removeAll { $0.id == entry.id } }
        catch { self.error = error.localizedDescription }
    }
    func deleteTrip(_ entry: TripEntry) {
        guard let repository else { error = "Local storage is unavailable. The walk has not been deleted."; return }
        do { try repository.delete(id: entry.id); trips.removeAll { $0.id == entry.id } }
        catch { self.error = error.localizedDescription }
    }
    func loadDemo() {
        guard activeRoute == nil else { return }
        demo = true
        air = AirReading(pm25: 10.2, aqi: 1, date: Date(), demo: true)
        routes = RouteService.demoRoutes(intensity: intensity); selectedRoute = routes.first?.id
        section = .routes
    }
    func leaveDemo() { guard activeRoute == nil else { return }; demo = false; air = nil; airNotice = nil; routes = []; selectedRoute = nil }
    func refreshAir(reportErrors: Bool = true) async {
        guard !demo, !busy else { return }
        guard let coordinate = location.currentLocation?.coordinate else {
            airNotice = "Waiting for your location. You can also choose a start in Explore."
            if reportErrors || location.hasAuthorization { location.request() }
            return
        }
        let scope = accountScopeKey
        busy = true; airNotice = nil; defer { if accountScopeKey == scope { busy = false } }
        do {
            let reading = try await AirService().fetch(at: coordinate, key: KeyStore.read("openweather"))
            guard accountScopeKey == scope else { return }; air = reading
        } catch {
            if accountScopeKey == scope {
                airNotice = error.localizedDescription
                if reportErrors { self.error = error.localizedDescription }
            }
        }
    }
    func plan(start: CLLocationCoordinate2D, destination: MKMapItem) async {
        guard activeRoute == nil, pendingRecovery == nil, !unreadableRecovery else { error = "Resolve the unfinished walk before planning a new one."; return }
        planGeneration += 1; let ticket = planGeneration
        busy = true; routes = []; selectedRoute = nil; demo = false; air = nil; airNotice = nil; routeNotice = nil
        defer { if ticket == planGeneration { busy = false } }
        do {
            let planned = try await RouteService().routes(from: start, to: destination, intensity: intensity, key: KeyStore.read("openweather"))
            try Task.checkCancellation()
            guard ticket == planGeneration else { return }
            routes = planned
            plannedStart = start; plannedDestination = destination
            selectedRoute = displayedRoutes.first?.id ?? routes.first?.id
            destinationName = destination.name ?? "Destination"
            if routes.count == 1 { routeNotice = "The provider returned one walking option. Alternative paths are not available for every request." }
        } catch is CancellationError { }
        catch { if ticket == planGeneration { self.error = error.localizedDescription } }
    }
    func cancelPlanning() { planGeneration += 1; busy = false }
    func start(_ route: WalkRoute) {
        guard activeRoute == nil, pendingRecovery == nil, !unreadableRecovery, let repository else {
            error = "Resolve the unfinished walk first, or check that local storage is available."; return
        }
        let now = Date(), id = UUID()
        let initial = ActiveWalkCheckpoint(sessionID: id, startedAt: now, savedAt: now, destination: destinationName,
                                           route: route.snapshot, recorder: WalkRecorder(), ventilation: intensity.ventilation,
                                           activity: nil, recovered: false)
        guard initial.isValid else { error = "The route could not be prepared for a recoverable walk."; return }
        do { try repository.save(initial, id: ActiveWalkCheckpoint.storageID, kind: "active-walk") }
        catch { self.error = "The walk could not start because its recovery record could not be saved."; return }
        remainingOptions = []; geofences.stop()
        activeRoute = route; walkStarted = now; recorder = WalkRecorder(); lastRefresh = nil
        sessionID = id; sessionVentilation = intensity.ventilation; recoveredSession = false
        lastCheckpoint = now; checkpointMessage = nil; startCheckpointTimer()
        location.setNavigationMode(true)
        trackingMessage = route.demo ? "Demo session: tap Simulate live run on map to preview real-time 3D tracking." : "Live GPS & heading active. Following clean-air corridor."
        if !route.demo {
            motion.beginSession(at: walkStarted!, enabled: motionTrackingEnabled, foreground: foreground)
            location.request()
        } else { motion.endSession() }
    }
    func toggleSimulatedRun() {
        guard let route = activeRoute else { return }
        if location.isSimulatingRun {
            location.stopSimulation()
            trackingMessage = "Live simulation paused."
        } else {
            if air == nil {
                air = route.airSamples.first?.reading ?? AirReading(pm25: 10.5, aqi: 1, date: Date(), demo: route.demo)
            }
            location.startSimulatedRun(along: route.coordinates, speedMps: intensity == .fast ? 3.2 : (intensity == .brisk ? 2.4 : 1.6))
            trackingMessage = "Live real-time running/walking navigation active along \(route.name)."
        }
    }
    func setMotionTracking(_ enabled: Bool) {
        motionTrackingEnabled = enabled; UserDefaults.standard.set(enabled, forKey: "motionTrackingEnabled")
        motion.setEnabled(enabled)
        checkpoint()
    }
    func setForeground(_ active: Bool) {
        foreground = active
        motion.setForeground(active)
        if !active { recorder.breakPath() }
        if active && activeRoute?.demo == false { trackingMessage = "Tracking resumed. Any background gap is excluded." }
        checkpoint()
    }
    private func recordLocation(_ current: CLLocation) {
        guard foreground, let route = activeRoute, (!route.demo || location.isSimulatingRun), let started = walkStarted, current.timestamp >= started, current.timestamp <= Date().addingTimeInterval(2) else { return }
        let distance = recorder.previous.map { current.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) }
        let samplePM = route.airSamples.first?.reading?.pm25
        let pm = (air?.isFresh == true ? air?.pm25 : nil) ?? (location.isSimulatingRun ? samplePM : nil)
        let result = recorder.record(coordinate: GeoCoordinate(current.coordinate), date: current.timestamp,
                                     accuracy: current.horizontalAccuracy, metresFromPrevious: distance, pm25: pm)
        switch result {
        case .recorded: trackingMessage = pm == nil ? "GPS active. Pollution data unavailable for this interval." : "Live GPS active · tracking speed, heading & clean-air exposure."
        case .gap: trackingMessage = "A tracking gap or inaccurate jump was excluded. A new recorded path section begins here."
        case .started: trackingMessage = "Recording live GPS path. Unobserved gaps remain excluded."
        case .ignored: return
        }
        if !route.demo { checkpoint() }
        if !route.demo && !refreshing && (lastRefresh == nil || Date().timeIntervalSince(lastRefresh!) > 60) {
            refreshing = true; lastRefresh = Date()
            let ticket = sessionID
            Task {
                defer { refreshing = false }
                do {
                    let reading = try await AirService().fetch(at: current.coordinate, key: KeyStore.read("openweather"))
                    guard sessionID == ticket, activeRoute != nil else { return }; air = reading
                } catch {
                    guard sessionID == ticket, activeRoute != nil else { return }
                    air = nil; trackingMessage = "GPS active. Air-quality update failed; exposure coverage is incomplete."
                }
            }
        }
    }
    func finish() {
        guard activeRoute != nil, let repository else { error = "No active walk or storage unavailable."; return }
        location.stopSimulation()
        let end = Date()
        guard let draft = makeCheckpoint(at: end), draft.isValid else { error = "The active walk could not be prepared for saving. Check the device clock and try again."; return }
        let entry = draft.trip(endedAt: end)
        do {
            try repository.finish(entry, tripID: entry.id, draftID: ActiveWalkCheckpoint.storageID)
            trips.removeAll { $0.id == entry.id }; trips.insert(entry, at: 0)
            stopRecording(); section = .journal
        } catch { self.error = "Walk remains open because saving failed: \(error.localizedDescription)" }
    }
    func resumeRecovery() {
        guard let draft = pendingRecovery, draft.isValid, activeRoute == nil, Date() >= draft.savedAt else {
            error = "This recovery record is invalid or the device clock is earlier than its last save. It has not been discarded."; return
        }
        let route = draft.route.walkRoute
        activeRoute = route; routes = [route]; selectedRoute = route.id; demo = route.demo
        walkStarted = draft.startedAt; destinationName = draft.destination; sessionID = draft.sessionID
        sessionVentilation = draft.ventilation; recoveredSession = true; recorder = draft.recorder; recorder.breakPath()
        plannedStart = route.coordinates.first
        if let end = route.coordinates.last { plannedDestination = MKMapItem(placemark: MKPlacemark(coordinate: end)); plannedDestination?.name = draft.destination }
        air = nil; lastRefresh = nil; remainingOptions = []; pendingRecovery = nil
        location.setNavigationMode(true)
        trackingMessage = route.demo ? "Recovered demo: no actual movement or exposure was recorded." : "Walk recovered. Recorded portions are retained; the closed-app gap remains unobserved."
        if !route.demo { motion.beginSession(at: draft.startedAt, enabled: motionTrackingEnabled, foreground: foreground, restoring: draft.activity, checkpointedAt: draft.savedAt); location.request() }
        startCheckpointTimer(); checkpoint(); section = .routes
    }
    func saveRecoveryPortion() {
        guard let draft = pendingRecovery, let repository else { return }
        let entry = draft.trip(endedAt: draft.savedAt)
        do {
            try repository.finish(entry, tripID: entry.id, draftID: ActiveWalkCheckpoint.storageID)
            trips.removeAll { $0.id == entry.id }; trips.insert(entry, at: 0); pendingRecovery = nil; checkpointMessage = nil; section = .journal
        } catch { self.error = "The recovery record remains available because saving failed." }
    }
    func discardRecovery() {
        guard activeRoute == nil, let repository else { return }
        do { try repository.delete(id: ActiveWalkCheckpoint.storageID); pendingRecovery = nil; unreadableRecovery = false; checkpointMessage = nil }
        catch { self.error = "The unfinished walk could not be discarded." }
    }
    private func makeCheckpoint(at date: Date) -> ActiveWalkCheckpoint? {
        guard let route = activeRoute, let started = walkStarted, let sessionID, let sessionVentilation else { return nil }
        return ActiveWalkCheckpoint(sessionID: sessionID, startedAt: started, savedAt: date, destination: destinationName,
                                    route: route.snapshot, recorder: recorder, ventilation: sessionVentilation,
                                    activity: route.demo ? nil : motion.summary(at: date), recovered: recoveredSession)
    }
    private func checkpoint() {
        let now = Date()
        guard let draft = makeCheckpoint(at: now), let repository else { return }
        guard draft.isValid else { checkpointMessage = "Recovery could not be updated. Check the device clock; the previous saved portion remains available."; return }
        do { try repository.save(draft, id: ActiveWalkCheckpoint.storageID, kind: "active-walk"); lastCheckpoint = now; checkpointMessage = nil }
        catch { checkpointMessage = "Recovery save failed. Keep this walk open and retry finishing before closing the app." }
    }
    private func startCheckpointTimer() {
        checkpointTimer?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.checkpoint() } }
        checkpointTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func stopRecording() {
        checkpointTimer?.invalidate(); checkpointTimer = nil
        activeRoute = nil; walkStarted = nil; sessionID = nil; sessionVentilation = nil
        location.setNavigationMode(false); location.stop(); motion.endSession(); voice.stop(); geofences.stop(); remainingTask?.cancel(); remainingOptions = []
        checkpointMessage = nil; lastCheckpoint = nil; recorder = WalkRecorder(); air = nil
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
    var hasAvoidableAreas: Bool {
        guard let start = plannedStart, let destination = plannedDestination else { return false }
        return !avoidableAreas(from: start, to: destination.placemark.coordinate).isEmpty
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
                if !routes.contains(where: { Self.samePath($0, option) }) {
                    routes.insert(option, at: 0)
                    selectedRoute = option.id
                }
            }
            if routes.count == previousCount { routeNotice = "The provider returned an existing path. No distinct avoidance option was added." }
        } catch is CancellationError { }
        catch { if ticket == planGeneration { self.routeNotice = error.localizedDescription } }
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
                            for detour in detours where !options.contains(where: { Self.samePath($0, detour) }) { options.insert(detour, at: 0) }
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
        activeRoute = route; routes = [route]; selectedRoute = route.id; remainingOptions = []
        remainingNotice = nil
        geofences.replace(samples: watchSamples); geofences.clearEntry()
        trackingMessage = "Switched to clean-air remaining route. Completed intervals are preserved."
        checkpoint()
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
