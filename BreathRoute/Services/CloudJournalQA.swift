#if DEBUG
import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Explicit, emulator-only integration checks. Never connects this workflow to a real project.
@MainActor enum CloudJournalQA {
    private static var started = false
    static func runIfRequested(model: AppModel) async {
        guard !started, ProcessInfo.processInfo.arguments.contains("--journal-sync-qa"),
              FirebaseBootstrap.environment == .emulator, let app = FirebaseBootstrap.app,
              app.options.projectID == "demo-breatheroute" else { return }
        started = true
        var passed: [String] = []
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw NSError(domain: "CloudJournalQA", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
            passed.append(name)
        }
        let auth = Auth.auth(app: app)
        var failure: String?
        do {
            try auth.signOut()
            let user = try await auth.signInAnonymously().user
            for _ in 0..<100 {
                if model.account.identity?.userID == user.uid && model.canSyncJournal { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let identity = AccountIdentity(userID: user.uid, projectID: "demo-breatheroute", email: nil, emailVerified: false, environment: .emulator)
            try check(model.canSyncJournal && model.symptoms.isEmpty && !model.cloudState.enabled, "fresh account defaults to local-only")
            let note = SymptomEntry(notes: "Synthetic emulator journal fixture")
            try check(model.save(note), "local note saved before consent")
            model.setCloudSyncEnabled(true)
            try check(model.cloudState.enabled && model.cloudState.lastSyncedAt == nil, "enable is local and does not sync")
            await model.syncJournal()
            try check(model.cloudState.lastSyncedAt != nil && model.cloudState.base.notes.count == 1, "native SDK upload and durable acknowledgement")
            let base = model.cloudState.base
            var remote = base; remote.notes[0].notes = "Synthetic remote edit"
            let peer = CloudJournalService()
            _ = try await peer.synchronize(local: remote, base: base, identity: identity)
            var local = note; local.notes = "Synthetic local edit"
            try check(model.save(local), "local edit saved")
            await model.syncJournal()
            try check(model.symptoms.count == 2 && model.symptoms.contains { $0.conflictCopyOf == note.id }, "native conflicting edits keep both versions")
            let reader = CloudJournalService()
            let restored = try await reader.synchronize(local: .init(), base: .init(), identity: identity)
            try check(restored.snapshot.notes.count == 2, "empty device restores cloud snapshot")
            let copy = try model.symptoms.first(where: { $0.conflictCopyOf != nil }).unwrap()
            model.deleteSymptom(copy); await model.syncJournal()
            let afterDelete = try await reader.synchronize(local: .init(), base: .init(), identity: identity)
            try check(afterDelete.snapshot.notes.count == 1, "native entry deletion propagates")
            let db = Firestore.firestore(app: app)
            try await db.disableNetwork()
            var offline = model.symptoms[0]; offline.notes = "Synthetic offline edit"
            _ = model.save(offline)
            let previousRevision = model.cloudState.revision
            await model.syncJournal()
            try check(model.symptoms.first?.notes == offline.notes && model.cloudState.revision == previousRevision && model.cloudHasLocalChanges,
                      "offline failure keeps local edit and previous baseline")
            try await db.enableNetwork(); await model.syncJournal()
            try check(!model.cloudHasLocalChanges && model.cloudState.revision != previousRevision, "manual retry acknowledges offline changes")
            model.setCloudSyncEnabled(false)
            try check(!model.cloudState.enabled, "pause keeps local journal")
            try auth.signOut()
            let second = try await auth.signInAnonymously().user
            do {
                _ = try await reader.synchronize(local: .init(), base: .init(), identity: identity)
                throw NSError(domain: "CloudJournalQA", code: 2)
            } catch JournalSyncError.wrongAccount { passed.append("old account request rejected after sign-out") }
            for _ in 0..<100 {
                if model.account.identity?.userID == second.uid { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            try check(model.symptoms.isEmpty && !model.cloudState.enabled, "second account has separate local journal and consent")
            let secondIdentity = AccountIdentity(userID: second.uid, projectID: "demo-breatheroute", email: nil, emailVerified: false, environment: .emulator)
            let left = CloudJournalService(), right = CloudJournalService()
            let firstWrite = Task { @MainActor in try await left.synchronize(local: .init(notes: [SymptomEntry(notes: "Concurrent left")]), base: .init(), identity: secondIdentity) }
            let secondWrite = Task { @MainActor in try await right.synchronize(local: .init(notes: [SymptomEntry(notes: "Concurrent right")]), base: .init(), identity: secondIdentity) }
            _ = try await firstWrite.value; _ = try await secondWrite.value
            let combined = try await reader.synchronize(local: .init(), base: .init(), identity: secondIdentity)
            try check(Set(combined.snapshot.notes.map(\.notes)) == ["Concurrent left", "Concurrent right"], "concurrent SDK writers retain independent entries")
        } catch { failure = (error as NSError).domain == "CloudJournalQA" ? error.localizedDescription : CloudJournalService.explain(error) }
        if let app = FirebaseBootstrap.app { try? await Firestore.firestore(app: app).enableNetwork() }
        let report: [String: Any] = ["passed": passed, "failure": failure ?? NSNull(), "emulatorOnly": true]
        let url = URL.documentsDirectory.appendingPathComponent("cloud-journal-qa.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
    }
}
private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let self else { throw NSError(domain: "CloudJournalQA", code: 3) }; return self
    }
}
#endif
