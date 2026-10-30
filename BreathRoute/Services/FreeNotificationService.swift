import Foundation
import Observation
import UserNotifications
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

@MainActor @Observable
final class FreeNotificationService {
    static let shared = FreeNotificationService()
    private let preferences: UserDefaults
    private let environment: FreeNotificationEnvironment
    private var identity: AccountIdentity?
    private var foreground = false
    private var generation = 0
    private var accountGeneration = 0
    private var ownRevisions: [String] = []
    private var sessionAllowed = true
    private var cancelListener: (() -> Void)?
    private var tracker = JournalUpdateTracker()
    private var pendingOpen: (FreeAlertEnvelope, Bool)?
    private var localIDs: Set<String> = []
    private(set) var enabled = false
    private(set) var banners = false
    private(set) var connected = false
    private(set) var hasUpdate = false
    private(set) var lastUpdate: Date?
    private(set) var status = "Sign in to receive journal updates while the app is open."
    private(set) var checkStatus: String?
    private(set) var checking = false
    private(set) var simulatorPrepared = false
    private(set) var navigationRequest = UUID()
    var onOpen: ((PushDestination) -> Void)?
    var suppressOwnSync: (() -> Bool)?
    var signedIn: Bool { identity != nil }
    var scope: String { identity?.journalNamespace ?? "guest" }
    var installationID: String {
        if let saved = preferences.string(forKey: "free.installation"), UUID(uuidString: saved) != nil { return saved.lowercased() }
        let value = UUID().uuidString.lowercased(); preferences.set(value, forKey: "free.installation"); return value
    }
    static var supportsSimulatorPush: Bool {
        #if DEBUG && targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    init(preferences: UserDefaults = .standard, environment: FreeNotificationEnvironment? = nil) {
        self.preferences = preferences; self.environment = environment ?? .live
    }
    private func key(_ value: String) -> String { "free.\(scope).\(value)" }
    private var currentAccountMatches: Bool { sessionAllowed && environment.currentScope() == scope }

    func setAccount(_ next: AccountIdentity?) {
        sessionAllowed = true
        guard next?.journalNamespace != identity?.journalNamespace else { startIfNeeded(); consumePendingOpen(); return }
        accountGeneration += 1
        let restoringPreparedCheck = identity == nil && next != nil
            && preferences.string(forKey: "free.simulatorScope") == next?.journalNamespace
            && environment.currentScope() == next?.journalNamespace
        stop(); clearLocalAlerts()
        if !restoringPreparedCheck { invalidateSimulatorCheck() }
        identity = next; tracker = JournalUpdateTracker(); ownRevisions = []; hasUpdate = false; lastUpdate = nil; checkStatus = nil
        enabled = next != nil && preferences.bool(forKey: key("enabled"))
        banners = next != nil && preferences.bool(forKey: key("banners"))
        status = next == nil ? "Sign in to receive journal updates while the app is open." : "Live journal updates are off."
        startIfNeeded(); consumePendingOpen()
    }
    func setForeground(_ active: Bool) {
        foreground = active
        if active { startIfNeeded() }
        else { stop(); if enabled { status = "Paused while the app is closed or locked." } }
    }
    func setEnabled(_ value: Bool) {
        guard signedIn, currentAccountMatches else { return }
        enabled = value; preferences.set(value, forKey: key("enabled"))
        if value { startIfNeeded() }
        else { stop(); tracker = JournalUpdateTracker(); hasUpdate = false; status = "Live journal updates are off."; clearLocalAlerts() }
    }
    func setBanners(_ value: Bool) async {
        guard signedIn, currentAccountMatches, !checking else { return }
        let ticket = accountGeneration, owner = scope
        if !value { banners = false; preferences.set(false, forKey: key("banners")); clearLocalAlerts(); return }
        checking = true; defer { checking = false }
        do {
            let allowed = try await environment.permission()
            guard ticket == accountGeneration, owner == scope, currentAccountMatches else { return }
            banners = allowed; preferences.set(allowed, forKey: key("banners"))
            if !allowed { checkStatus = "Notifications are off in device Settings. In-app updates still work." }
        } catch { if ticket == accountGeneration { checkStatus = "Notification permission could not be checked. Try again." } }
    }
    func retry() { stop(); startIfNeeded() }
    func dismissUpdate() { hasUpdate = false }
    func rememberLocalRevision(_ revision: String) {
        ownRevisions.append(revision.lowercased()); if ownRevisions.count > 64 { ownRevisions.removeFirst() }
    }
    func didSynchronize(revision: String?) { if tracker.revision == revision?.lowercased() { hasUpdate = false } }
    func prepareForSignOut() { sessionAllowed = false; accountGeneration += 1; stop(); hasUpdate = false; lastUpdate = nil; pendingOpen = nil; clearLocalAlerts(); invalidateSimulatorCheck() }

    private func stop() { generation += 1; cancelListener?(); cancelListener = nil; connected = false }
    private func startIfNeeded() {
        guard foreground, enabled, let identity, currentAccountMatches, cancelListener == nil else { return }
        let ticket = generation
        status = "Connecting to your cloud journal…"
        do {
            cancelListener = try environment.listen(identity) { [weak self] event, failure in
                Task { @MainActor in self?.handle(event, failure: failure, ticket: ticket) }
            }
        } catch { status = "Journal updates could not connect. Check your account and try again." }
    }
    private func handle(_ event: JournalRevisionEvent?, failure: String?, ticket: Int) {
        guard ticket == generation, foreground, enabled, currentAccountMatches else { return }
        if let failure { stop(); status = failure; return }
        guard let event else { return }
        if event.fromCache { connected = false; status = "Waiting for a server connection…"; return }
        guard !event.pendingWrites else { return }
        guard event.valid else { stop(); status = "The cloud journal summary could not be read. Try Sync now, then reconnect."; return }
        connected = true; status = event.exists ? "Listening while BreatheRoute is open." : "Connected. No cloud journal has been saved yet."
        guard tracker.accept(event, suppressAlert: suppressOwnSync?() == true || ownRevisions.contains(event.revision?.lowercased() ?? "")) else { return }
        hasUpdate = true; lastUpdate = Date()
        if banners {
            Task { [weak self] in
                guard let self, ticket == self.generation, self.foreground, self.banners, self.currentAccountMatches else { return }
                do { try await self.post(source: "firestore", kind: "journal_updated", ticket: ticket) }
                catch { if ticket == self.generation { self.checkStatus = "The update is available in-app. Its notification banner could not be shown." } }
            }
        }
    }
    func sendLocalTest() async {
        guard !checking, currentAccountMatches else { return }
        checking = true; let ticket = accountGeneration
        defer { checking = false }
        do {
            guard try await environment.permission() else { checkStatus = "Notifications are off in device Settings."; return }
            guard ticket == accountGeneration, currentAccountMatches else { return }
            try await post(source: "local", kind: "local_test", ticket: ticket, delay: 3)
            if ticket == accountGeneration { checkStatus = "Local alert scheduled for three seconds from now. It is generated on this device." }
        } catch { if ticket == accountGeneration { checkStatus = "The local alert could not be scheduled. Check notification Settings and try again." } }
    }
    private func fields(source: String, kind: String) -> [String: String] {
        ["freeVersion": "1", "freeSource": source, "freeKind": kind, "accountScope": scope, "installationID": installationID]
    }
    private func post(source: String, kind: String, ticket: Int, delay: TimeInterval = 1) async throws {
        guard ticket == (source == "firestore" ? generation : accountGeneration), currentAccountMatches else { return }
        if source == "firestore" { guard enabled, foreground, banners else { return } }
        let id = "breatheroute-free-\(UUID().uuidString)"; localIDs.insert(id)
        let value = FreeLocalAlert(id: id, fields: fields(source: source, kind: kind),
            title: source == "firestore" ? "Your cloud journal changed" : "Your notifications are ready",
            body: source == "firestore" ? "Open Journal and choose Sync now to review the update." : "This is a local notification check from BreatheRoute.", delay: delay)
        try await environment.schedule(value)
        if ticket != (source == "firestore" ? generation : accountGeneration) || !currentAccountMatches || (source == "firestore" && (!enabled || !foreground || !banners)) {
            environment.remove([id]); localIDs.remove(id)
        }
    }
    private func clearLocalAlerts() {
        environment.remove(Array(localIDs)); localIDs = []
        environment.clearOwnedAlerts(scope)
    }
    private func invalidateSimulatorCheck() {
        preferences.removeObject(forKey: "free.simulatorSession"); preferences.removeObject(forKey: "free.simulatorScope")
        preferences.removeObject(forKey: "free.simulatorExpiry"); simulatorPrepared = false
        #if DEBUG && targetEnvironment(simulator)
        try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("notification-check.apns"))
        #endif
    }
    func prepareSimulatorCheck() async {
        #if DEBUG && targetEnvironment(simulator)
        guard !checking, currentAccountMatches else { return }
        checking = true; let ticket = accountGeneration
        defer { checking = false }
        do {
            guard try await environment.permission() else { checkStatus = "Notifications are off in device Settings."; return }
            guard ticket == accountGeneration, currentAccountMatches else { return }
            let session = UUID().uuidString, expires = Date().addingTimeInterval(900)
            var payload: [String: Any] = fields(source: "simulator", kind: "simulator_test")
            payload["testSession"] = session; payload["checkExpiresAt"] = expires.timeIntervalSince1970
            payload["Simulator Target Bundle"] = Bundle.main.bundleIdentifier
            payload["aps"] = ["alert": ["title": "BreatheRoute notification check", "body": "A simulated push arrived. Tap to open notification settings."], "sound": "default"]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL.documentsDirectory.appendingPathComponent("notification-check.apns"), options: .atomic)
            preferences.set(session, forKey: "free.simulatorSession"); preferences.set(scope, forKey: "free.simulatorScope")
            preferences.set(expires.timeIntervalSince1970, forKey: "free.simulatorExpiry"); simulatorPrepared = true
            checkStatus = "Simulator push prepared for 15 minutes. Run the Mac helper to inject it. This check does not use APNs or the internet."
        } catch { if ticket == accountGeneration { checkStatus = "The simulator notification check could not be prepared. Try again." } }
        #endif
    }
    func accepts(_ envelope: FreeAlertEnvelope, remote: Bool) -> Bool {
        guard currentAccountMatches, envelope.matches(scope: scope, installation: installationID) else { return false }
        if remote {
            #if DEBUG && targetEnvironment(simulator)
            return envelope.source == "simulator" && envelope.testSession == preferences.string(forKey: "free.simulatorSession")
                && scope == preferences.string(forKey: "free.simulatorScope")
                && preferences.double(forKey: "free.simulatorExpiry") > Date().timeIntervalSince1970
            #else
            return false
            #endif
        }
        return envelope.source == "local" || (envelope.source == "firestore" && enabled && banners)
    }
    func received(_ envelope: FreeAlertEnvelope, remote: Bool) -> Bool {
        guard accepts(envelope, remote: remote) else { return false }
        if envelope.source == "simulator" { checkStatus = "Simulated push received. APNs delivery was not used." }
        else if envelope.source == "local" { checkStatus = "Local alert received on this device." }
        return true
    }
    func open(_ envelope: FreeAlertEnvelope, remote: Bool) { pendingOpen = (envelope, remote); consumePendingOpen() }
    func consumePendingOpen() {
        guard let (envelope, remote) = pendingOpen else { return }
        guard accepts(envelope, remote: remote) else {
            // Retain a cold-start account alert only until Firebase restores that account.
            if identity != nil || envelope.scope == "guest" { pendingOpen = nil }
            return
        }
        guard let onOpen else { return }
        pendingOpen = nil; _ = received(envelope, remote: remote); navigationRequest = UUID(); onOpen(envelope.destination)
    }
}

struct FreeLocalAlert: Sendable {
    let id: String
    let fields: [String: String]
    let title: String
    let body: String
    let delay: TimeInterval
}

@MainActor struct FreeNotificationEnvironment {
    var currentScope: () -> String
    var listen: (AccountIdentity, @escaping @Sendable (JournalRevisionEvent?, String?) -> Void) throws -> (() -> Void)
    var permission: () async throws -> Bool
    var schedule: (FreeLocalAlert) async throws -> Void
    var remove: ([String]) -> Void
    var clearOwnedAlerts: (String) -> Void
    static var live: Self {
        Self(currentScope: {
            guard let app = FirebaseBootstrap.app, let user = Auth.auth(app: app).currentUser, let project = app.options.projectID else { return "guest" }
            return AccountIdentity(userID: user.uid, projectID: project, email: nil, emailVerified: false, environment: FirebaseBootstrap.environment).journalNamespace
        }, listen: { identity, callback in
            let db = try CloudJournalService.connection(for: identity)
            let listener = db.collection("users").document(identity.userID).addSnapshotListener(includeMetadataChanges: true) { document, error in
                if let error {
                    let issue = error as NSError
                    callback(nil, issue.code == FirestoreErrorCode.permissionDenied.rawValue ? "Journal access was denied. Sign in again or check your private rules." : "Journal updates disconnected. Check your connection and retry.")
                    return
                }
                guard let document else { return }
                let fields = document.data(), revision = fields?["journalRevision"] as? String
                let valid = !document.exists || (fields?["schemaVersion"] as? Int == 1 && fields?["updatedAt"] is Timestamp && revision.flatMap(UUID.init(uuidString:)) != nil)
                callback(JournalRevisionEvent(exists: document.exists, revision: revision, fromCache: document.metadata.isFromCache,
                    pendingWrites: document.metadata.hasPendingWrites, valid: valid), nil)
            }
            return { listener.remove() }
        }, permission: { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) },
        schedule: { alert in
            let content = UNMutableNotificationContent(); content.title = alert.title; content.body = alert.body
            content.sound = .default; content.userInfo = alert.fields
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: alert.id, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: alert.delay, repeats: false)))
        }, remove: { ids in
            let center = UNUserNotificationCenter.current(); center.removePendingNotificationRequests(withIdentifiers: ids)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }, clearOwnedAlerts: { scope in
            Task {
                let center = UNUserNotificationCenter.current()
                let delivered = await center.deliveredNotifications().filter { $0.request.content.userInfo["freeVersion"] as? String == "1" && $0.request.content.userInfo["accountScope"] as? String == scope }.map { $0.request.identifier }
                let pending = await center.pendingNotificationRequests().filter { $0.content.userInfo["freeVersion"] as? String == "1" && $0.content.userInfo["accountScope"] as? String == scope }.map(\.identifier)
                center.removeDeliveredNotifications(withIdentifiers: delivered); center.removePendingNotificationRequests(withIdentifiers: pending)
            }
        })
    }
}
