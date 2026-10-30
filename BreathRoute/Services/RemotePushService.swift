import Foundation
import Observation
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseCore
import FirebaseMessaging
import FirebaseFirestore

@MainActor @Observable
final class RemotePushService: NSObject, MessagingDelegate {
    static let shared = RemotePushService()
    private let preferences: UserDefaults
    private let environment: RemotePushEnvironment
    private var configured = false
    private var generation = 0
    private var apnsReady = false
    private var fetchingToken = false
    private var timeoutTask: Task<Void, Never>?
    private var resetTask: Task<Bool, Never>?
    private var userID: String?
    private var registeredToken: String?
    private var pendingOpen: PushEnvelope?
    private(set) var enabled = false
    private(set) var connected = false
    private(set) var working = false
    private(set) var status = "Sign in to enable cloud notifications."
    private(set) var lastReceived: Date?
    private var lastTestReceived: Date?
    var onOpen: ((PushDestination) -> Void)?
    var signedIn: Bool { userID != nil }
    var supportsRemoteTest: Bool { environment.remoteTestSupported() }
    var automaticJournalAlerts: Bool { Self.usesFunctions }
    fileprivate static var usesFunctions: Bool { Bundle.main.object(forInfoDictionaryKey: "PUSH_BACKEND") as? String == "functions" }
    var available: Bool { configured && environment.available() }
    init(preferences: UserDefaults = .standard, environment: RemotePushEnvironment? = nil) {
        self.preferences = preferences; self.environment = environment ?? .live; super.init()
    }
    var installationID: String {
        if let value = preferences.string(forKey: "push.installationID"), UUID(uuidString: value) != nil { return value.lowercased() }
        let value = UUID().uuidString.lowercased(); preferences.set(value, forKey: "push.installationID"); return value
    }
    private func consentKey(_ uid: String) -> String { "push.consent.\(uid)" }
    func configure() {
        guard !configured, environment.available() else { return }
        configured = true
        // Explicit token requests only, after the signed-in user opts in. Never log either delivery token.
        environment.configure(self)
    }
    func setAccount(_ identity: AccountIdentity?) {
        let next = identity?.environment == .firebase ? identity?.userID : nil
        guard next != userID || userID == nil else { return }
        generation += 1; timeoutTask?.cancel(); connected = false; registeredToken = nil; fetchingToken = false; working = false
        lastReceived = nil; lastTestReceived = nil
        let previous = preferences.string(forKey: "push.owner")
        if let previous, previous != next {
            preferences.set(false, forKey: consentKey(previous)); preferences.set(true, forKey: "push.resetRequired")
            environment.unregisterAPNs(); apnsReady = false
        }
        userID = next
        enabled = next.map { preferences.bool(forKey: consentKey($0)) } ?? false
        status = next == nil ? "Sign in to enable cloud notifications." : "Cloud notifications are off."
        if enabled { Task { await reconnect() } }
        else if available && preferences.bool(forKey: "push.resetRequired") { Task { _ = await resetDeliveryToken() } }
        consumePendingOpen()
    }
    func reconnect() async {
        guard available, enabled, let userID, environment.currentUID() == userID, !working else { return }
        let ticket = generation
        working = true; connected = false
        let authorization = await environment.authorization()
        guard ticket == generation, enabled else { return }
        guard [.authorized, .provisional, .ephemeral].contains(authorization) else {
            await disable(); status = "Notifications are off in device Settings."; return
        }
        if preferences.bool(forKey: "push.resetRequired"), !(await resetDeliveryToken()) {
            guard ticket == generation else { return }
            working = false; status = "Reconnect to the internet before enabling cloud alerts."; return
        }
        guard ticket == generation, enabled else { return }
        status = "Connecting cloud notifications…"
        startConnectionTimeout(ticket: ticket)
        if apnsReady { await finishRegistration(ticket: ticket) }
        else {
            environment.registerAPNs()

        }
    }
    private func startConnectionTimeout(ticket: Int) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(25)); try Task.checkCancellation() } catch { return }
            guard let self, self.generation == ticket, !self.connected, self.working else { return }
            self.generation += 1; self.working = false; self.fetchingToken = false
            self.status = "Cloud notifications did not connect. Check the service setup and try again."
        }
    }
    func enable() async {
        guard available, let userID, environment.currentUID() == userID, !working else { return }
        let ticket = generation
        working = true
        do {
            let allowed = try await environment.requestPermission()
            guard ticket == generation else { return }
            working = false
            guard allowed else { status = "Notifications are off in device Settings."; return }
            enabled = true; preferences.set(true, forKey: consentKey(userID)); preferences.set(userID, forKey: "push.owner")
            await reconnect()
        } catch { if ticket == generation { working = false; status = "Notification permission could not be checked. Please try again." } }
    }
    func disable() async {
        let oldUser = userID
        generation += 1; let ticket = generation
        enabled = false; connected = false; working = true; fetchingToken = false; registeredToken = nil
        timeoutTask?.cancel(); environment.unregisterAPNs(); apnsReady = false
        if let oldUser { preferences.set(false, forKey: consentKey(oldUser)) }
        preferences.set(true, forKey: "push.resetRequired")
        await environment.removeDelivered(oldUser)
        if available, let oldUser { _ = try? await call("unregisterPushDevice", data: ["installationID": installationID], uid: oldUser) }
        let reset = await resetDeliveryToken()
        guard ticket == generation else { return }
        working = false
        status = reset ? "Cloud notifications are off." : "Cloud alerts are stopped on this device. Reconnect before enabling them again."
    }
    func prepareForSignOut() async {
        guard available, enabled || preferences.string(forKey: "push.owner") != nil else { return }
        await disable()
        preferences.removeObject(forKey: "push.owner"); pendingOpen = nil
    }
    private func resetDeliveryToken() async -> Bool {
        guard available else { return false }
        if let resetTask { return await resetTask.value }
        let task = Task { @MainActor in
            do { try await environment.deleteToken(); return true } catch { return false }
        }
        resetTask = task
        let reset = await task.value; resetTask = nil
        if reset { preferences.set(false, forKey: "push.resetRequired") }
        return reset
    }
    func didRegisterAPNs(_ token: Data) {
        guard available, enabled, let userID, environment.currentUID() == userID else { return }
        environment.associateAPNs(token); apnsReady = true
        let ticket = generation
        Task { await finishRegistration(ticket: ticket) }
    }
    func didFailAPNs() {
        guard enabled else { return }
        generation += 1; timeoutTask?.cancel(); apnsReady = false; working = false; connected = false; fetchingToken = false
        status = "Push notifications are not connected on this device. Check the notification service setup and try again."
    }
    private func finishRegistration(ticket: Int) async {
        guard ticket == generation, enabled, apnsReady, !fetchingToken, let uid = userID,
              environment.currentUID() == uid, !preferences.bool(forKey: "push.resetRequired"), resetTask == nil else { return }
        fetchingToken = true; working = true; connected = false
        startConnectionTimeout(ticket: ticket)
        defer { if ticket == generation { fetchingToken = false; working = false; timeoutTask?.cancel() } }
        do {
            let token = try await environment.fetchToken()
            guard ticket == generation, enabled, uid == userID else { return }
            _ = try await call("registerPushDevice", data: ["installationID": installationID, "token": token], uid: uid)
            guard ticket == generation, enabled, uid == userID else { return }
            registeredToken = token; connected = true; status = "Cloud notifications are on."
        } catch {
            guard ticket == generation else { return }
            connected = false; status = Self.explain(error)
        }
    }
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor [weak self] in
            guard let self, self.enabled, self.apnsReady, !self.fetchingToken, self.registeredToken != fcmToken else { return }
            await self.finishRegistration(ticket: self.generation)
        }
    }
    func sendConnectionTest() async {
        guard enabled, connected, !working, let uid = userID, environment.currentUID() == uid else { return }
        let ticket = generation, requestedAt = Date(); working = true
        defer { if ticket == generation { working = false } }
        do {
            _ = try await call("sendPushConnectionTest", data: ["installationID": installationID], uid: uid)
            if ticket == generation {
                status = lastTestReceived.map { $0 >= requestedAt } == true ? "Cloud notification received on this device." : "Test accepted by the delivery service. Waiting for this device to receive it…"
            }
        } catch { if ticket == generation { status = Self.explain(error) } }
    }
    func received(_ envelope: PushEnvelope) -> Bool {
        guard environment.currentUID() == userID, envelope.destination(userID: userID, installation: installationID, enabled: enabled) != nil else { return false }
        lastReceived = Date(); if envelope.kind == "connection_test" { lastTestReceived = lastReceived }
        status = "Cloud notification received on this device."; return true
    }
    func open(_ envelope: PushEnvelope) { pendingOpen = envelope; consumePendingOpen() }
    func consumePendingOpen() {
        if let pendingOpen, userID != nil, (!enabled || pendingOpen.recipientUID != userID) { self.pendingOpen = nil }
        guard environment.currentUID() == userID, let pendingOpen, let destination = pendingOpen.destination(userID: userID, installation: installationID, enabled: enabled), let onOpen else { return }
        _ = received(pendingOpen)
        self.pendingOpen = nil; onOpen(destination)
    }
    func refreshAuthorization() async {
        guard enabled, !working else { return }
        let authorization = await environment.authorization()
        if ![.authorized, .provisional, .ephemeral].contains(authorization) { await disable(); status = "Notifications are off in device Settings." }
        else { await reconnect() }
    }
    private func call(_ function: String, data: [String: String], uid: String) async throws -> [String: Any] {
        try await environment.call(function, data, uid)
    }
    fileprivate static func liveCall(_ function: String, data: [String: String], uid: String) async throws -> [String: Any] {
        guard let app = FirebaseBootstrap.app, FirebaseBootstrap.environment == .firebase,
              let project = app.options.projectID, project.range(of: "^[a-z][a-z0-9-]{4,62}$", options: .regularExpression) != nil,
              let user = Auth.auth(app: app).currentUser, user.uid == uid else { throw PushConnectionError.account }
        if !usesFunctions {
            guard let installation = data["installationID"], UUID(uuidString: installation) != nil else { throw PushConnectionError.service }
            let identity = AccountIdentity(userID: uid, projectID: project, email: user.email, emailVerified: user.isEmailVerified, environment: .firebase)
            let database = try CloudJournalService.connection(for: identity)
            let reference = database.collection("users").document(uid).collection("pushDevices").document(installation.lowercased())
            switch function {
            case "registerPushDevice":
                guard let token = data["token"], (20...4096).contains(token.count) else { throw PushConnectionError.service }
                try await reference.setData(["schemaVersion": 1, "uid": uid, "installationID": installation.lowercased(),
                    "token": token, "enabled": true, "updatedAt": FieldValue.serverTimestamp()])
                guard Auth.auth(app: app).currentUser?.uid == uid else { throw PushConnectionError.account }
                return ["registered": true]
            case "unregisterPushDevice":
                try await reference.delete(); return ["removed": true]
            default: throw PushConnectionError.manualSender
            }
        }
        let idToken = try await user.getIDToken()
        guard Auth.auth(app: app).currentUser?.uid == uid else { throw PushConnectionError.account }
        let url = URL(string: "https://asia-south1-\(project).cloudfunctions.net/\(function)")!
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": data])
        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard Auth.auth(app: app).currentUser?.uid == uid else { throw PushConnectionError.account }
        guard let http = response as? HTTPURLResponse else { throw PushConnectionError.service }
        if http.statusCode == 404 { throw PushConnectionError.setup }
        guard let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else { throw PushConnectionError.service }
        if let error = object["error"] as? [String: Any] {
            if error["status"] as? String == "RESOURCE_EXHAUSTED" { throw PushConnectionError.rateLimit }
            throw PushConnectionError.service
        }
        guard http.statusCode == 200, let result = (object["data"] ?? object["result"]) as? [String: Any] else { throw PushConnectionError.service }
        return result
    }
    private static func explain(_ error: Error) -> String {
        if let error = error as? PushConnectionError { return error.localizedDescription }
        if (error as NSError).domain == FirestoreErrorDomain && (error as NSError).code == FirestoreErrorCode.permissionDenied.rawValue {
            return "Device registration is not permitted yet. Publish the private notification rules, then retry."
        }
        return "Cloud notifications could not connect. Check your internet connection and notification service setup, then try again."
    }
}
private enum PushConnectionError: LocalizedError {
    case account, setup, service, rateLimit, manualSender
    var errorDescription: String? {
        switch self {
        case .manualSender: "Send a connection test from the Firebase console or the trusted sender tool."
        case .account: "Sign in again before connecting cloud notifications."
        case .setup: "Cloud notification service is not deployed yet. Your local reminders still work."
        case .service: "The cloud notification service could not complete this request. Please try again."
        case .rateLimit: "Wait a minute before sending another test notification."
        }
    }
}


/// Platform boundaries are injectable so account/permission races can be checked without real tokens or consent prompts.
@MainActor struct RemotePushEnvironment {
    var available: () -> Bool
    var configure: (MessagingDelegate) -> Void
    var currentUID: () -> String?
    var remoteTestSupported: () -> Bool
    var authorization: () async -> UNAuthorizationStatus
    var requestPermission: () async throws -> Bool
    var registerAPNs: () -> Void
    var unregisterAPNs: () -> Void
    var associateAPNs: (Data) -> Void
    var removeDelivered: (String?) async -> Void
    var fetchToken: () async throws -> String
    var deleteToken: () async throws -> Void
    var call: (String, [String: String], String) async throws -> [String: Any]
    static var live: Self {
        Self(available: { FirebaseBootstrap.environment == .firebase && FirebaseBootstrap.app != nil },
             configure: { delegate in Messaging.messaging().isAutoInitEnabled = false; Messaging.messaging().delegate = delegate },
             currentUID: { FirebaseBootstrap.app.flatMap { Auth.auth(app: $0).currentUser?.uid } },
             remoteTestSupported: { RemotePushService.usesFunctions },
             authorization: { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
             requestPermission: { try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) },
             registerAPNs: { UIApplication.shared.registerForRemoteNotifications() },
             unregisterAPNs: { UIApplication.shared.unregisterForRemoteNotifications() },
             associateAPNs: { Messaging.messaging().apnsToken = $0 },
             removeDelivered: { uid in
                 guard let uid else { return }
                 let center = UNUserNotificationCenter.current()
                 let notifications = await center.deliveredNotifications()
                 let ids = notifications.filter {
                     let data = $0.request.content.userInfo
                     return data["recipientUID"] as? String == uid && ["journal_updated", "connection_test"].contains(data["kind"] as? String ?? "")
                 }.map { $0.request.identifier }
                 center.removeDeliveredNotifications(withIdentifiers: ids)
             },
             fetchToken: { try await Messaging.messaging().token() },
             deleteToken: { try await Messaging.messaging().deleteToken() },
             call: { try await RemotePushService.liveCall($0, data: $1, uid: $2) })
    }
}
