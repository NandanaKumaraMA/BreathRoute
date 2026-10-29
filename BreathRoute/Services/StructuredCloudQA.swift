#if DEBUG
import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Explicit migration/seed acceptance. Production use requires the already signed-in
/// user; demo fixtures stay separate from that user's journal and activity totals.
@MainActor enum StructuredCloudQA {
    private static var started = false
    static func runIfRequested(model: AppModel) async {
        guard !started, ProcessInfo.processInfo.arguments.contains("--structured-cloud-qa"),
              FirebaseBootstrap.environment == .emulator, let app = FirebaseBootstrap.app, app.options.projectID == "demo-breatheroute" else { return }
        started = true
        var passed: [String] = [], failure: String?
        var walks = 0, notes = 0
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw QAError.failed(label) }; passed.append(label)
        }
        do {
            if FirebaseBootstrap.environment == .emulator, Auth.auth(app: app).currentUser == nil {
                _ = try await Auth.auth(app: app).signInAnonymously()
            }
            for _ in 0..<100 {
                if !model.account.initializing && model.canSyncJournal { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard let identity = model.account.identity, model.canSyncJournal else { throw QAError.failed("existing signed-in journal required") }
            do { _ = try await model.cloud.loadDemonstration(identity: identity) }
            catch CloudDemoReadError.notReady { }
            try check(true, "read-only example access initializes safely before journal sync")
            model.setCloudSyncEnabled(true)
            await model.syncJournal()
            try check(!model.cloudHasLocalChanges && model.cloudState.consentVersion == 2, "expanded consent and structured sync acknowledged")
            let beforeIDs = Set(model.trips.map(\.id) + model.symptoms.map(\.id))
            guard let revision = model.cloudState.revision else { throw QAError.failed("missing server revision") }
            let db = Firestore.firestore(app: app), user = db.collection("users").document(identity.userID)
            let profile = try await user.getDocument(source: .server)
            try check(profile.exists && profile.data()?["journalRevision"] as? String == revision, "parent user document exists with completed projection revision")
            let preferences = try await user.collection("preferences").document("current").getDocument(source: .server)
            try check(preferences.data()?["walkingPace"] as? String == model.intensity.rawValue, "typed walking preferences match this account")
            let tripRecords = try await user.collection("walks").getDocuments(source: .server)
            let noteRecords = try await user.collection("symptoms").getDocuments(source: .server)
            walks = tripRecords.documents.count; notes = noteRecords.documents.count
            try check(walks == model.trips.count && notes == model.symptoms.count, "structured collection counts match the local journal")
            try check((tripRecords.documents + noteRecords.documents).allSatisfy {
                $0.data()["date"] is Timestamp && $0.data()["journalRevision"] as? String == revision
            }, "structured dates and revisions use native Firestore fields")
            let before = try model.cloudState.base.encoded()
            try await CloudDemoSeeder.seed(database: db, userID: identity.userID, revision: revision)
            let demo = user.collection("demoDatasets").document(CloudDemoFixtures.datasetID)
            let exampleWalks = try await demo.collection("walks").getDocuments(source: .server)
            let exampleNotes = try await demo.collection("symptoms").getDocuments(source: .server)
            try check(exampleWalks.documents.count == CloudDemoFixtures.walkCount && exampleNotes.documents.count == CloudDemoFixtures.noteCount &&
                      (exampleWalks.documents + exampleNotes.documents).allSatisfy { $0.data()["synthetic"] as? Bool == true },
                      "separate demo dataset contains 30 labelled synthetic walks and 45 notes")
            try await CloudDemoSeeder.seed(database: db, userID: identity.userID, revision: revision)
            let repeated = try await demo.collection("walks").getDocuments(source: .server)
            try check(repeated.documents.count == CloudDemoFixtures.walkCount, "seeding again keeps stable IDs without duplicate examples")
            let loaded = try await model.cloud.loadDemonstration(identity: identity)
            try check(loaded.snapshot == (try CloudDemoFixtures.snapshot()), "app cloud reader restores all example fields and native dates")
            let foreign = AccountIdentity(userID: "wrong-account", projectID: identity.projectID, email: nil, emailVerified: false, environment: identity.environment)
            do {
                _ = try await model.cloud.loadDemonstration(identity: foreign)
                throw QAError.failed("reader accepted a different account")
            } catch JournalSyncError.wrongAccount { passed.append("example reader rejects a stale or different account") }
            let week = DemoJournalWindow(snapshot: loaded.snapshot, days: 7)
            try check(week.trips.count == 7 && week.notes.count == 11, "example week filter works independently of the current date")
            let after = try await user.collection("journal").document("current").getDocument(source: .server)
            let payload = try (after.data()?["payload"] as? String).unwrap()
            try check(Data(payload.utf8) == before && Set(model.trips.map(\.id) + model.symptoms.map(\.id)) == beforeIDs,
                      "demo data does not alter the real journal or local activity totals")
            if FirebaseBootstrap.environment == .emulator {
                if let document = noteRecords.documents.first {
                    try await document.reference.delete()
                    await model.syncJournal()
                    let repaired = try await document.reference.getDocument(source: .server)
                    try check(repaired.exists && model.cloudState.revision == revision,
                              "retry repairs an incomplete projection without changing the canonical journal")
                }
                var bulk = model.cloudState.base
                bulk.notes += (0..<81).map { SymptomEntry(notes: "[SYNTHETIC EMULATOR] Projection chunk \($0)") }
                let result = try await CloudJournalService().synchronize(local: bulk, base: model.cloudState.base, identity: identity)
                let rows = try await user.collection("symptoms").getDocuments(source: .server)
                let completed = try await user.getDocument(source: .server)
                try check(rows.documents.count == bulk.notes.count && completed.data()?["journalRevision"] as? String == result.revision,
                          "multi-chunk projection completes before its parent revision is acknowledged")
            }
        } catch let error as QAError { failure = String(describing: error) }
        catch { failure = CloudJournalService.explain(error) }
        let report: [String: Any] = ["workflow": "structured private cloud migration and separate synthetic demo dataset",
            "production": FirebaseBootstrap.environment == .firebase, "success": failure == nil, "passed": passed,
            "passedCount": passed.count, "failure": failure ?? NSNull(), "journalWalks": walks, "journalNotes": notes,
            "demoWalks": CloudDemoFixtures.walkCount, "demoNotes": CloudDemoFixtures.noteCount]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("structured-cloud-qa.json"), options: .atomic)
        }
    }
    private enum QAError: Error { case failed(String) }
}
private extension Optional {
    func unwrap() throws -> Wrapped {
        guard let self else { throw NSError(domain: "StructuredCloudQA", code: 1) }; return self
    }
}
#endif
