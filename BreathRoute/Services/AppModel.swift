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
    let cloud = CloudJournalService()
    let remotePush = RemotePushService.shared
    let notifications = FreeNotificationService.shared
    private(set) var syncInFlight = false
    private(set) var cloudState = JournalCloudState()
    private(set) var journalReadableForSync = false
    var canSyncJournal: Bool { account.identity != nil && journalReadableForSync && canChangeAccount }
    var cloudHasLocalChanges: Bool { (try? cloudSnapshot()) != cloudState.base }
    var canChangeAccount: Bool { activeRoute == nil && pendingRecovery == nil && !unreadableRecovery && !busy && !remainingBusy && !account.working && !syncInFlight && !cloud.working && !health.isReadingActivity && !health.isReadingVitals }
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
    var extraMinutes = 10.0 { didSet { UserDefaults.standard.set(extraMinutes, forKey: profileKey("extraMinutes")) } }
    private var remainingTask: Task<Void, Never>?
    private var remainingGeneration = 0
    private var remainingOrigin: CLLocation?
    private var remainingCreatedAt: Date?
    private var deviationMonitor = RouteDeviationMonitor()
    private var rerouteGate = AutomaticRerouteGate()
    var automaticRouteChecks = true
    private(set) var routeCheckMessage = "Route checks start with your walk."
    private var liveAirArea: WatchArea?
    typealias WalkingRoutes = @MainActor (CLLocationCoordinate2D, MKMapItem, WalkingIntensity, [WatchArea]) async throws -> [WalkRoute]
    private let walkingRoutes: WalkingRoutes
    func openWalkPlanner() { section = .routes }
    var previewMetrics: WalkPreviewMetrics? {
        guard let values = location.preview?.exampleMetrics else { return nil }
        return WalkPreviewMetrics(steps: Int(trackedMetres / 0.75), heartRate: values.heartRate, respiratoryRate: values.respiratoryRate)
    }
    private var plannedStart: CLLocationCoordinate2D?
    private var plannedDestination: MKMapItem?
    typealias PreviewAirRequest = @MainActor (CLLocationCoordinate2D) async throws -> AirReading
    private let previewAirRequest: PreviewAirRequest
    private(set) var previewAirMessage: String?
    var isRefreshingPreviewAir: Bool { refreshing }
    private let journalOverride: LocalStore?
    private var repository: LocalStore?
    var persistenceAvailable: Bool { repository != nil }
    var isIsolatedPreview: Bool { journalOverride != nil }
    func closeIsolatedPreview() {
        guard isIsolatedPreview, activeRoute?.demo == true else { return }
        stopRecording()
    }
    var activeRoute: WalkRoute?
    var walkStarted: Date?
    private var recorder = WalkRecorder()
    private var routeStartRecordedMetres = 0.0
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
        if location.isPreviewLocation && !location.isSimulatingRun { return 0 }
        if location.currentLocation != nil, location.speedMetersPerSecond > 0.2 {
            return location.speedMetersPerSecond * 3.6
        }
        if activeRoute?.demo != true, let pace = motion.currentPace, pace > 0 {
            return 60.0 / pace
        }
        return 0
    }

    /// Pace comes from fresh phone motion or a recent GPS speed; previews have an explicit source.
    var livePaceLabel: String {
        if activeRoute?.demo == true, !location.isSimulatingRun {
            return location.preview?.state == .completed ? "Completed" : "Paused"
        }
        var minutes: Double?
        if activeRoute?.demo != true, let pace = motion.currentPace, pace > 0, pace < 60 { minutes = pace }
        else if liveSpeedKmh > 0.3 { minutes = 60 / liveSpeedKmh }
        guard let minutes else { return location.currentLocation == nil ? "Waiting for GPS" : "Stationary" }
        let seconds = Int((minutes * 60).rounded())
        return String(format: "%d:%02d min/km", seconds / 60, seconds % 60)
    }
    static var usesSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    var previewSpeed: Double { switch intensity { case .easy: 1.35; case .brisk: 1.7; case .fast: 2.7 } }
    /// Actual route/air data retain their provider; only movement and body values become examples.
    func startForCurrentEnvironment(_ route: WalkRoute) {
        if Self.usesSimulator || route.demo {
            var previewRoute = WalkRoute(name: route.name, coordinates: route.coordinates, metres: route.metres,
                seconds: route.seconds, estimate: route.estimate, demo: true, airSamples: route.airSamples,
                source: route.source, avoidedAreaCount: route.avoidedAreaCount, excludedAreas: route.excludedAreas, steps: route.steps)
            // A new route ID ensures the active map and its selected route refer to the same preview.
            if route.demo { previewRoute = route }
            start(previewRoute)
        } else { start(route) }
    }

    /// True when the user's live speed or motion state indicates running/jogging.
    var isRunningLive: Bool {
        location.speedMetersPerSecond >= 2.1 || (motion.currentCadence ?? 0) >= 135 || intensity == .fast
    }

    /// Remaining distance in metres along the active route.
    var remainingDistanceMetres: Double {
        guard let route = activeRoute else { return 0 }
        if route.demo, let preview = location.preview { return max(0, preview.totalMetres - preview.metres) }
        if let current = location.currentLocation ?? location.location, let end = route.coordinates.last {
            let direct = current.distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
            return max(0, min(route.metres, max(direct, route.metres - (trackedMetres - routeStartRecordedMetres))))
        }
        return max(0, route.metres - (trackedMetres - routeStartRecordedMetres))
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

    init(journal: LocalStore? = nil, walkingRoutes: @escaping WalkingRoutes = { start, end, intensity, areas in
        try await RouteService().routes(from: start, to: end, intensity: intensity, key: KeyStore.read("openweather"), avoiding: areas)
    }, previewAirRequest: @escaping PreviewAirRequest = { coordinate in
        try await AirService().fetch(at: coordinate, key: KeyStore.read("openweather"))
    }) {
        journalOverride = journal; self.previewAirRequest = previewAirRequest; self.walkingRoutes = walkingRoutes
        name = UserDefaults.standard.string(forKey: "displayName") ?? ""
        intensity = WalkingIntensity(rawValue: UserDefaults.standard.string(forKey: "intensity") ?? "") ?? .easy
        extraMinutes = UserDefaults.standard.object(forKey: "extraMinutes") as? Double ?? 10
        motionTrackingEnabled = UserDefaults.standard.bool(forKey: "motionTrackingEnabled")
        openJournal(accountNamespace: nil)
        location.onUpdate = { [weak self] location in
            guard let self else { return }
            self.recordLocation(location)
            self.evaluateWalkAwareness(location)
        }
        geofences.onEntry = { [weak self] _ in
            self?.requestAutomaticReroute(reason: "Entered a higher-AQI sample area. Comparing the remaining walk…")
        }
    }
    func startAccountObservation() {
        if journalOverride == nil {
            remotePush.onOpen = { [weak self] destination in self?.section = destination == .journal ? .journal : .profile }
            remotePush.consumePendingOpen()
            notifications.onOpen = { [weak self] destination in self?.section = destination == .journal ? .journal : .profile }
            notifications.suppressOwnSync = { [weak self] in self?.cloud.working == true }
            cloud.onLocalRevision = { [weak self] in self?.notifications.rememberLocalRevision($0) }
            notifications.consumePendingOpen()
        }
        account.onIdentityChange = { [weak self] identity in
            guard let self else { return }
            self.changeAccount(to: identity)
            if self.journalOverride == nil { self.remotePush.setAccount(identity); self.notifications.setAccount(identity) }
        }
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
        accountScopeKey = next; health.resetForAccountChange(); forecasts.clearForAccountChange(); cloud.resetForAccountChange()
        name = UserDefaults.standard.string(forKey: profileKey("displayName")) ?? ""
        intensity = WalkingIntensity(rawValue: UserDefaults.standard.string(forKey: profileKey("intensity")) ?? "") ?? .easy
        extraMinutes = UserDefaults.standard.object(forKey: profileKey("extraMinutes")) as? Double ?? 10
        openJournal(accountNamespace: identity?.journalNamespace); section = .profile
        if interrupted { error = "The account session changed. The unfinished walk remains saved in its original journal. Sign back into that account to recover it." }
    }
    private func openJournal(accountNamespace: String?) {
        journalReadableForSync = false; cloudState = JournalCloudState()
        do { repository = try journalOverride ?? LocalStore(accountNamespace: accountNamespace) }
        catch { self.error = "This journal could not be opened. Existing data has not been reset."; return }
        guard let repository else { return }
        var readable = true
        do { symptoms = try repository.read("symptom", as: SymptomEntry.self).sorted { $0.date > $1.date } }
        catch { readable = false; self.error = "Symptom records could not be read. They have not been reset." }
        do { trips = try repository.read("trip", as: TripEntry.self).sorted { $0.date > $1.date } }
        catch { readable = false; self.error = "Walk records could not be read. They have not been reset." }
        do {
            let states = try repository.read("cloud-state", as: JournalCloudState.self)
            guard states.count <= 1 else { throw JournalSyncError.invalid }
            if let state = states.first { _ = try state.base.encoded(); cloudState = state }
        } catch { readable = false; cloud.message = "Cloud state could not be read. Sync is disabled to protect existing records." }
        journalReadableForSync = readable
        do {
            let drafts = try repository.read("active-walk", as: ActiveWalkCheckpoint.self)
            if let draft = drafts.first {
                guard drafts.count == 1, draft.isValid else { throw CocoaError(.coderReadCorrupt) }
                pendingRecovery = draft; section = .routes
            }
        } catch { unreadableRecovery = true; checkpointMessage = "An unfinished walk could not be read. It remains stored; discard it explicitly before starting another walk." }
    }
    func save(_ entry: SymptomEntry) -> Bool {
        guard !syncInFlight && !cloud.working else { error = "Wait for cloud sync to finish before editing the journal."; return false }
        guard let repository else { error = "Local storage is unavailable. Your note has not been saved."; return false }
        do {
            try repository.save(entry, id: entry.id, kind: "symptom")
            symptoms.removeAll { $0.id == entry.id }; symptoms.append(entry); symptoms.sort { $0.date > $1.date }; return true
        } catch { self.error = "Could not save the symptom: \(error.localizedDescription)"; return false }
    }
    func deleteSymptom(_ entry: SymptomEntry) {
        guard !syncInFlight && !cloud.working else { error = "Wait for cloud sync to finish before editing the journal."; return }
        guard let repository else { error = "Local storage is unavailable. The note has not been deleted."; return }
        do { try repository.delete(id: entry.id); symptoms.removeAll { $0.id == entry.id } }
        catch { self.error = error.localizedDescription }
    }
    func deleteTrip(_ entry: TripEntry) {
        guard !syncInFlight && !cloud.working else { error = "Wait for cloud sync to finish before editing the journal."; return }
        // Linked notes are preserved; the UI treats a deleted trip as unavailable.
        guard let repository else { error = "Local storage is unavailable. The walk has not been deleted."; return }
        do { try repository.delete(id: entry.id); trips.removeAll { $0.id == entry.id } }
        catch { self.error = error.localizedDescription }
    }
    private func cloudSnapshot() throws -> JournalCloudSnapshot {
        try JournalCloudSnapshot(trips: trips.map(CloudTripSummary.init), notes: symptoms,
                                 profile: CloudUserProfile(displayName: name),
                                 preferences: CloudPreferences(walkingPace: intensity.rawValue, extraMinutes: extraMinutes)).validated()
    }
    func setCloudSyncEnabled(_ enabled: Bool) {
        guard canSyncJournal, let repository else { return }
        var next = cloudState; next.enabled = enabled
        if enabled { next.consentVersion = 2 }
        do {
            try repository.save(next, id: JournalCloudState.storageID, kind: "cloud-state")
            cloudState = next
            cloud.message = enabled ? "Cloud sync enabled. Use Sync now to upload or restore your journal." : "Cloud sync paused. Existing cloud records have not been deleted."
        } catch { cloud.message = "The sync preference could not be saved. Its previous setting is unchanged." }
    }
    func syncJournal() async {
        guard canSyncJournal, cloudState.enabled, cloudState.consentVersion == 2, let repository, let identity = account.identity else { return }
        let scope = accountScopeKey
        syncInFlight = true
        defer { syncInFlight = false }
        do {
            let local = try cloudSnapshot()
            let result = try await cloud.synchronize(local: local, base: cloudState.base, identity: identity)
            guard accountScopeKey == scope else { return }
            let existing = Dictionary(uniqueKeysWithValues: trips.map { ($0.id, $0) })
            let mergedTrips = result.snapshot.trips.map { $0.restored(preserving: existing[$0.id]) }
            var next = cloudState; next.base = result.snapshot; next.revision = result.revision; next.lastSyncedAt = Date()
            let encoder = JSONEncoder()
            let tripWrites = try mergedTrips.map { ($0.id, try encoder.encode($0)) }
            let noteWrites = try result.snapshot.notes.map { ($0.id, try encoder.encode($0)) }
            try repository.replaceJournal(trips: tripWrites, notes: noteWrites,
                                          state: (JournalCloudState.storageID, try encoder.encode(next)))
            trips = mergedTrips.sorted { $0.date > $1.date }
            symptoms = result.snapshot.notes.sorted { $0.date > $1.date }; cloudState = next
            if journalOverride == nil { notifications.didSynchronize(revision: result.revision) }
            // Keep edits made while the request was running as unsynced local changes.
            if name == local.profile?.displayName, let profile = result.snapshot.profile { name = profile.displayName }
            if intensity.rawValue == local.preferences?.walkingPace, let pace = result.snapshot.preferences?.walkingPace,
               let restored = WalkingIntensity(rawValue: pace) { intensity = restored }
            if extraMinutes == local.preferences?.extraMinutes, let minutes = result.snapshot.preferences?.extraMinutes { extraMinutes = minutes }
            let count = trips.count + symptoms.count
            cloud.message = result.conflictCount == 0 ? "Sync complete. \(count) journal \(count == 1 ? "entry" : "entries") checked." :
                "Sync complete. Both versions were kept for \(result.conflictCount) conflicting changes; copies are labelled in your journal."
            if result.settingsConflictCount > 0 { cloud.message = (cloud.message ?? "") + " Existing cloud profile/preferences were kept after competing edits. Review them in You before changing and syncing again." }
        } catch {
            guard accountScopeKey == scope else { return }
            cloud.message = CloudJournalService.explain(error)
        }
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
            let planned = try await walkingRoutes(start, destination, intensity, [])
            try Task.checkCancellation()
            guard ticket == planGeneration else { return }
            routes = planned
            plannedStart = start; plannedDestination = destination
            selectedRoute = displayedRoutes.first?.id ?? routes.first?.id
            destinationName = destination.name ?? "Destination"
            if hasAvoidableAreas && !routes.contains(where: { $0.avoidedAreaCount > 0 }) {
                await addAvoidanceOption()
                guard ticket == planGeneration else { return }
            }
            if let bestRouteID { selectedRoute = bestRouteID }
            if routes.count == 1 && routeNotice == nil { routeNotice = "The provider returned one walking option. Alternative paths are not available for every request." }
        } catch is CancellationError { }
        catch { if ticket == planGeneration { self.error = error.localizedDescription } }
    }
    func cancelPlanning() { planGeneration += 1; busy = false }
    func start(_ route: WalkRoute) {
        guard !syncInFlight && !cloud.working else { error = "Wait for cloud sync to finish before starting a walk."; return }
        guard !busy, activeRoute == nil, pendingRecovery == nil, !unreadableRecovery, let repository else {
            error = "Resolve the unfinished walk first, or check that local storage is available."; return
        }
        let now = Date(), id = UUID()
        let initial = ActiveWalkCheckpoint(sessionID: id, startedAt: now, savedAt: now, destination: destinationName,
                                           route: route.snapshot, recorder: WalkRecorder(), ventilation: intensity.ventilation,
                                           activity: nil, recovered: false)
        guard initial.isValid else { error = "The route could not be prepared for a recoverable walk."; return }
        do { try repository.save(initial, id: ActiveWalkCheckpoint.storageID, kind: "active-walk") }
        catch { self.error = "The walk could not start because its recovery record could not be saved."; return }
        cancelRemaining(); geofences.stop()
        deviationMonitor = RouteDeviationMonitor(); rerouteGate = AutomaticRerouteGate()
        liveAirArea = nil
        routeCheckMessage = "Watching for route departures and higher-AQI area entries."
        activeRoute = route; air = nil; previewAirMessage = nil
        if route.demo { routes = [route]; selectedRoute = route.id; demo = true }
        followCamera = true
        walkStarted = now; recorder = WalkRecorder(); routeStartRecordedMetres = 0; lastRefresh = nil
        sessionID = id; sessionVentilation = intensity.ventilation; recoveredSession = false
        lastCheckpoint = now; checkpointMessage = nil; startCheckpointTimer()
        activateWalkAwareness()
        location.setNavigationMode(true)
        trackingMessage = route.demo ? "Your route is ready. Follow progress on the map." : "Waiting for movement. Keep the app open to record GPS."
        if !route.demo {
            motion.beginSession(at: walkStarted!, enabled: motionTrackingEnabled, foreground: foreground)
            location.request()
        } else {
            motion.endSession()
            if location.prepareSimulation(along: route.coordinates, speedMps: previewSpeed) {
                location.resumeSimulation()
                if route.source != "Illustrative demo" { Task { await refreshPreviewAir() } }
            }
            else { error = "This path could not be opened. Choose another route and try again." }
        }
    }
    /// Provider air data can be requested for the synthetic position; body values stay fictional.
    func refreshPreviewAir() async {
        guard let route = activeRoute, route.demo, route.source != "Illustrative demo", !refreshing,
              let coordinate = location.location?.coordinate else { return }
        let ticket = sessionID
        refreshing = true; previewAirMessage = "Loading OpenWeather data for the preview position…"
        defer { if sessionID == ticket { refreshing = false } }
        do {
            let reading = try await previewAirRequest(coordinate)
            guard sessionID == ticket, activeRoute?.demo == true else { return }
            guard !reading.demo, reading.isFresh, reading.pm25.isFinite, reading.pm25 >= 0, (1...5).contains(reading.aqi) else { throw ServiceError.noReading }
            air = reading; updateLiveWatchArea(reading, at: coordinate)
            previewAirMessage = "OpenWeather · PM2.5 \(reading.pm25.formatted(.number.precision(.fractionLength(1)))) µg/m³ · updated \(reading.date.formatted(.dateTime.hour().minute()))."
        } catch {
            guard sessionID == ticket else { return }
            if air?.isFresh != true { air = nil }
            previewAirMessage = "Fresh air data could not be loaded. Missing intervals remain unknown; tap Refresh live air data to retry."
        }
    }
    func toggleSimulatedRun() {
        guard let route = activeRoute, route.demo else { return }
        if location.isSimulatingRun {
            location.pauseSimulation(); recorder.breakPath(); trackingMessage = "Walk paused. Resume when you are ready."
        } else {
            if location.preview == nil {
                _ = location.prepareSimulation(along: route.coordinates, speedMps: previewSpeed,
                                               startingMetres: trackedMetres, movingSeconds: trackedSeconds)
            }
            location.resumeSimulation(); trackingMessage = "Following your selected route."
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
        if !active {
            recorder.breakPath()
            if activeRoute?.demo == true { location.pauseSimulation() }
        }
        if active && journalOverride == nil { Task { await remotePush.refreshAuthorization() } }
        if active && activeRoute?.demo == false { trackingMessage = "Tracking resumed. Any background gap is excluded." }
        checkpoint()
    }
    func setNotificationAccess(_ allowed: Bool) { if journalOverride == nil { notifications.setForeground(allowed) } }
    private func recordLocation(_ current: CLLocation) {
        guard foreground, let route = activeRoute, (!route.demo || location.isPreviewLocation), let started = walkStarted, current.timestamp >= started, current.timestamp <= Date().addingTimeInterval(2) else { return }
        let distance = recorder.previous.map { current.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) }
        if route.demo, route.source == "Illustrative demo" || air?.isFresh != true {
            let nearest = route.airSamples.min {
                current.distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)) <
                current.distance(from: CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude))
            }?.reading
            air = route.source == "Illustrative demo" || nearest?.demo == false ? nearest : nil
        }
        let pm = air?.isFresh == true ? air?.pm25 : nil
        let result = recorder.record(coordinate: GeoCoordinate(current.coordinate), date: current.timestamp,
                                     accuracy: current.horizontalAccuracy, metresFromPrevious: distance, pm25: pm)
        switch result {
        case .recorded: trackingMessage = pm == nil ? "GPS active. Pollution data unavailable for this interval." : "Live GPS active · tracking speed, heading & clean-air exposure."
        case .gap: trackingMessage = "A tracking gap or inaccurate jump was excluded. A new recorded path section begins here."
        case .started: trackingMessage = "Recording live GPS path. Unobserved gaps remain excluded."
        case .ignored: return
        }
        if route.demo { trackingMessage = "Following your selected route." }
        if !route.demo { checkpoint() }
        if !route.demo && !refreshing && (lastRefresh == nil || Date().timeIntervalSince(lastRefresh!) > 60) {
            refreshing = true; lastRefresh = Date()
            let ticket = sessionID
            Task {
                defer { if sessionID == ticket { refreshing = false } }
                do {
                    let reading = try await AirService().fetch(at: current.coordinate, key: KeyStore.read("openweather"))
                    guard sessionID == ticket, activeRoute != nil else { return }
                    air = reading; updateLiveWatchArea(reading, at: current.coordinate)
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
        guard !syncInFlight && !cloud.working else { error = "Wait for cloud sync to finish before resuming a walk."; return }
        guard let draft = pendingRecovery, draft.isValid, activeRoute == nil, Date() >= draft.savedAt else {
            error = "This recovery record is invalid or the device clock is earlier than its last save. It has not been discarded."; return
        }
        let route = draft.route.walkRoute
        activeRoute = route; routes = [route]; selectedRoute = route.id; demo = route.demo; followCamera = true
        walkStarted = draft.startedAt; destinationName = draft.destination; sessionID = draft.sessionID
        sessionVentilation = draft.ventilation; recoveredSession = true; recorder = draft.recorder; recorder.breakPath()
        routeStartRecordedMetres = draft.routeStartRecordedMetres ?? 0
        plannedStart = route.coordinates.first
        if let end = route.coordinates.last { plannedDestination = MKMapItem(placemark: MKPlacemark(coordinate: end)); plannedDestination?.name = draft.destination }
        air = nil; liveAirArea = nil; lastRefresh = nil; cancelRemaining(); pendingRecovery = nil
        deviationMonitor = RouteDeviationMonitor(); rerouteGate = AutomaticRerouteGate()
        activateWalkAwareness()
        routeCheckMessage = "Watching for route departures and higher-AQI area entries."
        location.setNavigationMode(true)
        trackingMessage = route.demo ? "Walk preview restored. Continue from where you left off." : "Walk recovered. Recorded portions are retained; the closed-app gap remains unobserved."
        if !route.demo { motion.beginSession(at: draft.startedAt, enabled: motionTrackingEnabled, foreground: foreground, restoring: draft.activity, checkpointedAt: draft.savedAt); location.request() }
        else { _ = location.prepareSimulation(along: route.coordinates, speedMps: previewSpeed, startingMetres: draft.previewMetres ?? trackedMetres, movingSeconds: draft.previewMovingSeconds ?? trackedSeconds) }
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
                                    activity: route.demo ? nil : motion.summary(at: date), recovered: recoveredSession,
                                    previewMetres: location.preview?.metres, previewMovingSeconds: location.preview?.movingSeconds,
                                    routeStartRecordedMetres: routeStartRecordedMetres)
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
        location.setNavigationMode(false); location.stop(); motion.endSession(); voice.stop(); geofences.stop(); cancelRemaining(); liveAirArea = nil
        checkpointMessage = nil; lastCheckpoint = nil; recorder = WalkRecorder(); routeStartRecordedMetres = 0; air = nil; refreshing = false; previewAirMessage = nil
    }
    var selected: WalkRoute? { routes.first { $0.id == selectedRoute } }
    var bestRouteID: UUID? {
        guard routes.allSatisfy(Self.freshForRecommendation) else { return nil }
        return RouteChoicePolicy.recommended(routes.map { RouteChoice(id: $0.id.uuidString, seconds: $0.seconds, dose: $0.estimate.observedDose, complete: $0.estimate.isComplete) }, extraMinutes: extraMinutes).flatMap(UUID.init(uuidString:))
    }
    var watchSamples: [WatchArea] {
        let route = activeRoute ?? selected
        var samples = route?.airSamples.compactMap { sample -> WatchArea? in
            guard let reading = sample.reading, !reading.demo || route?.source == "Illustrative demo" else { return nil }
            return WatchArea(id: sample.id.uuidString, latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude, pm25: reading.pm25, aqi: reading.aqi, sampledAt: reading.date)
        } ?? []
        if let liveAirArea { samples.append(liveAirArea) }
        return samples
    }
    var plannedWatchAreaCount: Int { WatchAreaPolicy.select(watchSamples, now: Date()).count }
    private func activateWalkAwareness() {
        geofences.startForeground(samples: watchSamples, simulated: activeRoute?.demo == true)
    }
    private func updateLiveWatchArea(_ reading: AirReading, at coordinate: CLLocationCoordinate2D) {
        liveAirArea = WatchArea(id: "current-air-sample", latitude: coordinate.latitude, longitude: coordinate.longitude,
                                pm25: reading.pm25, aqi: reading.aqi, sampledAt: reading.date)
        geofences.replace(samples: watchSamples)
        if let current = location.currentLocation { geofences.evaluate(current) }
    }
    func evaluateWalkAwareness(_ current: CLLocation) {
        guard foreground, let route = activeRoute, !route.demo || location.isPreviewLocation else { return }
        geofences.evaluate(current, source: route.demo ? "Preview location" : "Foreground location")
        if deviationMonitor.update(coordinate: GeoCoordinate(current.coordinate), accuracy: current.horizontalAccuracy,
                                   date: current.timestamp, now: Date(), path: route.coordinates.map(GeoCoordinate.init)) {
            requestAutomaticReroute(reason: "You appear to have left the path. Comparing routes from here…")
        }
    }
    private func requestAutomaticReroute(reason: String) {
        guard automaticRouteChecks, !remainingBusy, remainingOptions.isEmpty, rerouteGate.accept(now: Date()) else { return }
        routeCheckMessage = reason
        compareRemaining(avoidAreas: true)
    }
    private func cancelRemaining() {
        remainingGeneration += 1; remainingTask?.cancel(); remainingTask = nil
        remainingBusy = false; remainingOptions = []; remainingNotice = nil; remainingOrigin = nil; remainingCreatedAt = nil
    }
    /// A paused synthetic position is still known; it is never presented as a fresh GPS fix.
    private var routingLocation: CLLocation? {
        if activeRoute?.demo == true, let point = location.preview?.coordinate {
            return CLLocation(coordinate: point.mapCoordinate, altitude: 0, horizontalAccuracy: 4, verticalAccuracy: -1, timestamp: Date())
        }
        return location.currentLocation
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
            let options = try await walkingRoutes(start, destination, intensity, areas)
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
        guard let route = activeRoute else { return }
        guard let current = routingLocation, (0...100).contains(current.horizontalAccuracy) else {
            routeCheckMessage = "Waiting for a recent accurate position to compare remaining routes."; return
        }
        let destination = plannedDestination ?? route.coordinates.last.map { MKMapItem(placemark: MKPlacemark(coordinate: $0)) }
        guard let destination else { return }
        cancelRemaining(); let ticket = remainingGeneration, session = sessionID, scope = accountScopeKey
        remainingBusy = true
        let isFixture = route.source == "Illustrative demo", intensity = intensity
        let areas = avoidableAreas(from: current.coordinate, to: destination.placemark.coordinate)
        remainingTask = Task {
            defer { if ticket == remainingGeneration { remainingBusy = false } }
            do {
                var options: [WalkRoute]
                var notice: String?
                if isFixture {
                    // Offline example paths are cut at the current walker position, never sent to a provider.
                    options = RouteService.demoRoutes(intensity: intensity).map { option in
                        let nearest = option.coordinates.indices.min {
                            current.distance(from: CLLocation(latitude: option.coordinates[$0].latitude, longitude: option.coordinates[$0].longitude)) <
                            current.distance(from: CLLocation(latitude: option.coordinates[$1].latitude, longitude: option.coordinates[$1].longitude))
                        } ?? 0
                        let points = [current.coordinate] + Array(option.coordinates.dropFirst(min(nearest + 1, option.coordinates.count - 1)))
                        let metres = zip(points, points.dropFirst()).reduce(0.0) { $0 + CLLocation(latitude: $1.0.latitude, longitude: $1.0.longitude).distance(from: CLLocation(latitude: $1.1.latitude, longitude: $1.1.longitude)) }
                        let seconds = max(1, metres / previewSpeed)
                        let mean = option.airSamples.compactMap(\.reading).map(\.pm25).reduce(0, +) / Double(max(1, option.airSamples.count))
                        return WalkRoute(name: option.name, coordinates: points, metres: metres, seconds: seconds,
                            estimate: ExposureCalculator.estimate([.init(minutes: seconds / 60, pm25: mean)], ventilation: intensity.ventilation),
                            demo: true, airSamples: option.airSamples, source: option.source)
                    }
                    notice = "Sample routes and air readings. Walking access and area avoidance have not been verified."
                } else {
                    options = try await walkingRoutes(current.coordinate, destination, intensity, [])
                    if avoidAreas && !areas.isEmpty {
                        do {
                            let detours = try await walkingRoutes(current.coordinate, destination, intensity, areas)
                            for detour in detours where !options.contains(where: { Self.samePath($0, detour) }) { options.insert(detour, at: 0) }
                        } catch is CancellationError { throw CancellationError() }
                        catch { notice = error.localizedDescription + " Baseline options remain available." }
                    } else { notice = "No fresh higher-AQI areas can be excluded between these endpoints. Areas containing your current position or destination are omitted." }
                    if route.demo { options = options.map { $0.asPreview } }
                }
                try Task.checkCancellation()
                guard ticket == remainingGeneration, sessionID == session, accountScopeKey == scope, activeRoute?.id == route.id else { return }
                remainingOptions = options; remainingOrigin = current; remainingCreatedAt = Date(); remainingNotice = notice
                routeCheckMessage = options.isEmpty ? "No alternative returned. Your selected path remains active." : "Routes ready below. Choose one to change the remaining path."
            } catch is CancellationError { }
            catch {
                guard ticket == remainingGeneration, sessionID == session else { return }
                remainingNotice = error.localizedDescription
                routeCheckMessage = "Route comparison unavailable. Your selected path remains active."
            }
        }
    }
    func dismissRemainingOptions() {
        cancelRemaining(); routeCheckMessage = "Continuing on your selected path. Automatic checks remain available."
    }
    func switchRemaining(to route: WalkRoute) {
        guard let previous = activeRoute, remainingOptions.contains(where: { $0.id == route.id }),
              let created = remainingCreatedAt, Date().timeIntervalSince(created) < 300,
              let origin = remainingOrigin, let current = routingLocation, (0...100).contains(current.horizontalAccuracy), current.distance(from: origin) <= 100,
              previous.demo == route.demo, route.snapshot.isValid else {
            cancelRemaining(); routeCheckMessage = "These alternatives are out of date. Compare again from your current position."; return
        }
        let wasPlaying = location.isSimulatingRun, movingSeconds = location.preview?.movingSeconds ?? trackedSeconds
        if route.demo {
            location.pauseSimulation(); recorder.breakPath()
            guard location.prepareSimulation(along: route.coordinates, speedMps: previewSpeed, movingSeconds: movingSeconds) else { return }
        }
        activeRoute = route; routes = [route]; selectedRoute = route.id; routeStartRecordedMetres = trackedMetres; cancelRemaining()
        deviationMonitor = RouteDeviationMonitor()
        geofences.replace(samples: watchSamples); geofences.clearEntry()
        routeCheckMessage = "Remaining path updated. Area and route monitoring continue."
        trackingMessage = "Remaining route updated. Completed time, distance and exposure are preserved."
        if route.demo && wasPlaying { location.resumeSimulation() }
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
        (route.demo && route.source == "Illustrative demo") ||
        (!route.airSamples.isEmpty && route.airSamples.allSatisfy { $0.reading?.isFresh == true && $0.reading?.demo == false })
    }
}
