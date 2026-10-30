#if DEBUG
import Foundation
import UserNotifications

@MainActor enum RemotePushQA {
    private static var started = false
    static func runIfRequested() async {
        guard !started, AppModel.usesSimulator, ProcessInfo.processInfo.arguments.contains("--remote-push-qa") else { return }
        started = true
        let suite = "BreatheRoute.pushQA.\(UUID().uuidString)"
        guard let preferences = UserDefaults(suiteName: suite) else { return }
        defer { preferences.removePersistentDomain(forName: suite) }
        var checks: [String] = [], failure: String?
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure.check(message) }; checks.append(message)
        }
        func settle() async { try? await Task.sleep(for: .milliseconds(100)) }
        let probe = Probe()
        let environment = RemotePushEnvironment(available: { true }, configure: { _ in }, currentUID: { probe.uid }, remoteTestSupported: { true },
            authorization: { probe.authorization }, requestPermission: { probe.permission },
            registerAPNs: { probe.events.append("apns-register") }, unregisterAPNs: { probe.events.append("apns-unregister") },
            associateAPNs: { _ in probe.events.append("apns-associated") }, removeDelivered: { _ in },
            fetchToken: { probe.events.append("token-fetch"); return "placeholder-test-token-never-sent-to-fcm" },
            deleteToken: {
                probe.events.append("token-revoke")
                if probe.deleteFails { throw Failure.check("offline revoke") }
                if probe.holdRevocation { await withCheckedContinuation { probe.heldRevocation = $0 } }
            },
            call: { function, data, uid in
                probe.events.append(function); probe.owners.append(uid)
                if function == "registerPushDevice", probe.holdRegistration {
                    await withCheckedContinuation { probe.heldRegistration = $0 }
                }
                return function == "registerPushDevice" ? ["registered": true] : ["accepted": true, "removed": true]
            })
        let service = RemotePushService(preferences: preferences, environment: environment)
        func identity(_ uid: String) -> AccountIdentity {
            AccountIdentity(userID: uid, projectID: "push-qa-local", email: nil, emailVerified: false, environment: .firebase, providerIDs: ["google.com"])
        }
        do {
            service.configure(); await service.enable()
            try check(probe.events.isEmpty && !service.enabled, "guest cannot register a device or request notification permission")
            probe.uid = "account-a"; service.setAccount(identity("account-a")); await service.enable()
            try check(service.enabled && !service.connected && probe.events == ["apns-register"], "opt-in waits for APNs before requesting a delivery token")
            service.didRegisterAPNs(Data([1, 2])); await settle()
            try check(service.connected && probe.events.contains("registerPushDevice") && probe.owners.allSatisfy { $0 == "account-a" }, "APNs token is associated before owner-bound backend registration")
            let fields = ["kind": "connection_test", "recipientUID": "account-a", "installationID": service.installationID, "version": "1"]
            guard let envelope = PushEnvelope(fields: fields) else { throw Failure.check("payload") }
            var opened: PushDestination?
            service.onOpen = { opened = $0 }; service.open(envelope)
            try check(opened == .settings, "a matching notification tap opens only its typed destination")
            try check(service.received(envelope) && service.lastReceived != nil, "received state is set only after a matching device notification")
            probe.uid = "account-b"
            opened = nil; service.open(envelope)
            try check(opened == nil, "a notification tap cannot open the previous account after Auth changes")
            try check(!service.received(envelope), "an Auth identity change immediately suppresses the old account's notification")
            probe.uid = "account-a"; await service.sendConnectionTest()
            try check(service.status.contains("accepted") && probe.events.contains("sendPushConnectionTest"), "FCM acceptance is described separately from delivery")
            await service.disable()
            try check(!service.enabled && !service.connected && probe.events.suffix(3) == ["apns-unregister", "unregisterPushDevice", "token-revoke"], "opt-out unregisters APNs, removes the server mapping and revokes the FCM token")
            try check(!service.received(envelope), "notifications cannot open or present after opt-out")
            probe.permission = false; let before = probe.events.count; await service.enable()
            try check(!service.enabled && probe.events.count == before, "denied permission creates no token or server registration")
            probe.permission = true; probe.holdRegistration = true; await service.enable(); service.didRegisterAPNs(Data([3])); await settle()
            try check(probe.heldRegistration != nil && service.working, "registration can be held in flight for account-race verification")
            await service.prepareForSignOut(); probe.uid = nil; service.setAccount(nil)
            probe.heldRegistration?.resume(); probe.heldRegistration = nil; await settle()
            try check(!service.connected && !service.enabled && !service.working, "a late registration cannot reconnect a signed-out account")
            probe.uid = "account-b"; probe.holdRegistration = false; service.setAccount(identity("account-b")); await service.enable(); service.didRegisterAPNs(Data([4])); await settle()
            try check(service.connected && probe.owners.last == "account-b", "a different account connects with its own backend identity")
            service.didFailAPNs()
            try check(!service.connected && !service.working, "APNs failure is reported without claiming a connection")
            await service.disable(); probe.deleteFails = true
            await service.enable(); service.didRegisterAPNs(Data([5])); await settle(); await service.prepareForSignOut()
            probe.uid = nil; service.setAccount(nil); await settle()
            probe.uid = "account-c"; service.setAccount(identity("account-c")); let fetches = probe.events.filter { $0 == "token-fetch" }.count
            await service.enable(); await settle()
            try check(!service.connected && probe.events.filter { $0 == "token-fetch" }.count == fetches, "failed token revocation blocks another account from reusing the old delivery connection")
            probe.deleteFails = false; probe.holdRevocation = true
            let reconnect = Task { await service.reconnect() }; await settle()
            service.didRegisterAPNs(Data([6])); await settle()
            try check(probe.heldRevocation != nil && probe.events.filter { $0 == "token-fetch" }.count == fetches,
                      "a late APNs callback cannot fetch or register while token cleanup is still in flight")
            probe.heldRevocation?.resume(); probe.heldRevocation = nil
            await reconnect.value; await settle()
            try check(service.connected && probe.owners.last == "account-c", "reconnection resumes only after old-token cleanup succeeds")
        } catch { failure = String(describing: error) }
        let result: [String: Any] = ["success": failure == nil, "passed": checks, "failure": failure ?? NSNull(),
                                   "realFCMCalls": false, "systemPermissionPrompts": false, "isolatedPreferences": true]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("remote-push-qa.json"), options: .atomic)
        }
    }
    private enum Failure: Error { case check(String) }
    private final class Probe {
        var uid: String?; var permission = true; var authorization: UNAuthorizationStatus = .authorized
        var events: [String] = [], owners: [String] = []; var deleteFails = false; var holdRegistration = false
        var heldRegistration: CheckedContinuation<Void, Never>?
        var holdRevocation = false; var heldRevocation: CheckedContinuation<Void, Never>?
    }
}
#endif
