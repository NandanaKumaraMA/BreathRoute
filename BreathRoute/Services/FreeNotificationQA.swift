#if DEBUG
import Foundation
import FirebaseAuth
import FirebaseCore

@MainActor enum FreeNotificationQA {
    private static var started = false
    private static var emulatorStarted = false
    static func runIfRequested() async {
        guard !started, AppModel.usesSimulator, ProcessInfo.processInfo.arguments.contains("--free-notification-qa") else { return }
        started = true
        let suite = "BreatheRoute.freeNotificationsQA.\(UUID().uuidString)", probe = Probe()
        guard let preferences = UserDefaults(suiteName: suite) else { return }
        defer { preferences.removePersistentDomain(forName: suite) }
        var checks: [String] = [], failure: String?
        func check(_ value: Bool, _ name: String) throws { if !value { throw Failure.check(name) }; checks.append(name) }
        func settle() async { try? await Task.sleep(for: .milliseconds(100)) }
        func waitFor(_ condition: () -> Bool) async {
            for _ in 0..<100 { if condition() { return }; try? await Task.sleep(for: .milliseconds(30)) }
        }
        func account(_ uid: String) -> AccountIdentity { .init(userID: uid, projectID: "free-notification-qa", email: nil, emailVerified: false, environment: .firebase) }
        let environment = FreeNotificationEnvironment(currentScope: { probe.scope }, listen: { _, callback in
            probe.callbacks.append(callback); return { probe.cancelled += 1 }
        }, permission: { probe.onPermission?(); return probe.allowed }, schedule: { probe.alerts.append($0) },
        remove: { probe.removed.append(contentsOf: $0) }, clearOwnedAlerts: { _ in })
        let service = FreeNotificationService(preferences: preferences, environment: environment)
        do {
            service.setForeground(true); service.setEnabled(true)
            try check(probe.callbacks.isEmpty && !service.enabled, "guest cannot start a cloud listener")
            let a = account("a"); probe.scope = a.journalNamespace; service.setAccount(a); service.setEnabled(true)
            let callback = probe.callbacks[0], first = UUID().uuidString, second = UUID().uuidString
            callback(.init(exists: true, revision: first, fromCache: true), nil); await settle()
            try check(!service.connected && !service.hasUpdate, "cached state never claims a server connection or new update")
            callback(.init(exists: true, revision: first), nil); await settle()
            try check(service.connected && !service.hasUpdate, "the initial server snapshot establishes a quiet baseline")
            await service.setBanners(true)
            callback(.init(exists: true, revision: second), nil)
            await waitFor { service.hasUpdate && probe.alerts.count == 1 }
            try check(service.hasUpdate && probe.alerts.count == 1 && probe.alerts[0].body.contains("Sync now"), "a committed cloud revision creates an in-app update and generic local banner")
            let alert = probe.alerts[0]
            try check(Set(alert.fields.keys) == ["freeVersion", "freeSource", "freeKind", "accountScope", "installationID"], "notification fields exclude journal content, symptoms and GPS")
            var opened: PushDestination?; service.onOpen = { opened = $0 }
            service.open(FreeAlertEnvelope(fields: alert.fields)!, remote: false)
            try check(opened == .journal, "a matching cloud-update alert opens Journal")
            callback(.init(exists: true, revision: second), nil); await settle()
            try check(probe.alerts.count == 1, "duplicate snapshots do not repeat alerts")
            service.dismissUpdate(); let own = UUID().uuidString; service.rememberLocalRevision(own)
            callback(.init(exists: true, revision: own), nil); await settle()
            try check(!service.hasUpdate && probe.alerts.count == 1, "this device's sync acknowledgement stays quiet even after the sync ends")
            service.setForeground(false); callback(.init(exists: true, revision: UUID().uuidString), nil); await settle()
            try check(probe.cancelled == 1 && !service.connected && !service.hasUpdate, "backgrounding detaches the listener and rejects late callbacks")
            service.setForeground(true); let resumed = probe.callbacks.last!
            resumed(.init(exists: true, revision: UUID().uuidString), nil); await settle()
            try check(service.connected && service.hasUpdate && probe.alerts.count == 2, "resuming checks the next authoritative revision without polling")
            service.prepareForSignOut(); opened = nil; service.open(FreeAlertEnvelope(fields: alert.fields)!, remote: false)
            try check(opened == nil && !service.hasUpdate, "starting sign-out immediately blocks old alert actions")
            let b = account("b"); probe.scope = b.journalNamespace; service.setAccount(b)
            callback(.init(exists: true, revision: UUID().uuidString), nil); await settle()
            try check(!service.enabled && !service.hasUpdate && service.lastUpdate == nil, "another account has separate consent and cannot receive late updates")
            service.setEnabled(true); let bCallback = probe.callbacks.last!
            bCallback(.init(exists: false, revision: nil), nil); await settle()
            probe.allowed = false; await service.setBanners(true)
            bCallback(.init(exists: true, revision: UUID().uuidString), nil); await settle()
            try check(service.hasUpdate && !service.banners && probe.alerts.count == 2, "denied notification permission preserves live in-app updates")
            probe.allowed = true; probe.onPermission = { service.setForeground(false); service.setForeground(true) }
            await service.sendLocalTest()
            try check(probe.alerts.last?.fields["freeSource"] == "local", "OS permission interruptions do not cancel a local test for the same account")
            opened = nil; service.open(FreeAlertEnvelope(fields: alert.fields)!, remote: false)
            try check(opened == nil, "cross-account local alert taps are rejected")
            probe.onPermission = nil
            await service.prepareSimulatorCheck()
            let file = try Data(contentsOf: URL.documentsDirectory.appendingPathComponent("notification-check.apns"))
            let object = try JSONSerialization.jsonObject(with: file) as! [String: Any]
            let fields = object.compactMapValues { $0 as? String }
            let simulated = FreeAlertEnvelope(fields: fields)!
            try check(service.accepts(simulated, remote: true), "a simulator payload is accepted only after an explicit check is armed")
            let restored = FreeNotificationService(preferences: preferences, environment: environment)
            restored.setAccount(b)
            try check(restored.accepts(simulated, remote: true), "a prepared account check survives Firebase account restoration on cold start")
            var forged = fields; forged["testSession"] = UUID().uuidString
            try check(!service.accepts(FreeAlertEnvelope(fields: forged)!, remote: true) && !service.accepts(simulated, remote: false), "unarmed simulator sessions and wrong delivery channels are rejected")
            preferences.set(Date().addingTimeInterval(-1).timeIntervalSince1970, forKey: "free.simulatorExpiry")
            try check(!service.accepts(simulated, remote: true), "the simulator check expires instead of becoming a permanent bypass")
            service.prepareForSignOut()
            try check(!FileManager.default.fileExists(atPath: URL.documentsDirectory.appendingPathComponent("notification-check.apns").path), "sign-out removes the simulator fixture and private notification checks")
        } catch { failure = String(describing: error) }
        service.prepareForSignOut()
        write(["success": failure == nil, "passed": checks, "failure": failure ?? NSNull(), "productionWrites": false,
               "realAPNsCalls": false, "systemPermissionPrompts": false], file: "free-notification-qa.json")
    }

    static func runEmulatorIfRequested() async {
        guard !emulatorStarted, AppModel.usesSimulator, ProcessInfo.processInfo.arguments.contains("--free-notification-emulator-qa"),
              FirebaseBootstrap.environment == .emulator, let app = FirebaseBootstrap.app,
              app.options.projectID == "demo-breatheroute" else { return }
        emulatorStarted = true
        var checks: [String] = [], failure: String?
        let suite = "BreatheRoute.liveListenerQA.\(UUID().uuidString)"
        guard let preferences = UserDefaults(suiteName: suite) else { return }
        defer { preferences.removePersistentDomain(forName: suite) }
        let service = FreeNotificationService(preferences: preferences)
        func waitUntil(_ value: () -> Bool) async throws {
            for _ in 0..<160 { if value() { return }; try await Task.sleep(for: .milliseconds(100)) }
            throw Failure.check("Timed out waiting for the native Firestore listener")
        }
        do {
            let auth = Auth.auth(app: app); try auth.signOut()
            let user = try await auth.signInAnonymously().user
            let identity = AccountIdentity(userID: user.uid, projectID: "demo-breatheroute", email: nil, emailVerified: false, environment: .emulator)
            let writer = CloudJournalService()
            let initial = JournalCloudSnapshot(notes: [SymptomEntry(notes: "Isolated notification listener fixture")])
            _ = try await writer.synchronize(local: initial, base: .init(), identity: identity)
            service.setAccount(identity); service.setForeground(true); service.setEnabled(true)
            try await waitUntil { service.connected }
            guard !service.hasUpdate else { throw Failure.check("Initial snapshot should be quiet") }
            checks.append("native SDK listener reads the owner's server summary with no initial alert")
            var updated = initial; updated.notes.append(SymptomEntry(notes: "Isolated peer update"))
            _ = try await writer.synchronize(local: updated, base: initial, identity: identity)
            try await waitUntil { service.hasUpdate }
            checks.append("a separate Firestore writer causes a real SDK listener update")
            service.dismissUpdate(); service.setForeground(false)
            var background = updated; background.notes.append(SymptomEntry(notes: "Isolated paused update"))
            _ = try await writer.synchronize(local: background, base: updated, identity: identity)
            try await Task.sleep(for: .milliseconds(300))
            guard !service.hasUpdate && !service.connected else { throw Failure.check("Paused listener changed state") }
            checks.append("background pause does not receive or claim cloud delivery")
            service.setForeground(true); try await waitUntil { service.hasUpdate && service.connected }
            checks.append("foreground resume notices the next server revision")
            service.prepareForSignOut(); try auth.signOut()
            _ = try await auth.signInAnonymously()
            service.setAccount(nil)
            guard !service.hasUpdate && !service.enabled else { throw Failure.check("Previous account leaked state") }
            checks.append("sign-out removes the listener and isolates the next account")
            try auth.signOut()
        } catch { failure = String(describing: error) }
        service.prepareForSignOut()
        write(["success": failure == nil, "passed": checks, "failure": failure ?? NSNull(), "emulatorOnly": true,
               "productionWrites": false, "realAPNsCalls": false], file: "free-notification-emulator-qa.json")
    }
    private static func write(_ report: [String: Any], file: String) {
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent(file), options: .atomic)
        }
    }
    private enum Failure: Error { case check(String) }
    private final class Probe {
        var scope = "guest", allowed = true, cancelled = 0
        var callbacks: [@Sendable (JournalRevisionEvent?, String?) -> Void] = []
        var alerts: [FreeLocalAlert] = [], removed: [String] = []
        var onPermission: (() -> Void)?
    }
}
#endif
