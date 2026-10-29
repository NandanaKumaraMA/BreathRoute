#if DEBUG
import Foundation
import FirebaseCore

/// Explicit real-server restore verification for an account whose records the user
/// has confirmed are synthetic. Never uploads, edits or deletes the source journal.
@MainActor enum LiveJournalQA {
    private static var started = false
    static func runIfRequested(model: AppModel) async {
        guard !started, ProcessInfo.processInfo.arguments.contains("--synthetic-live-journal-qa"),
              FirebaseBootstrap.environment == .firebase,
              FirebaseBootstrap.app?.options.projectID == "breathe-route-75d07" else { return }
        started = true
        var passed: [String] = []
        var failure: String?
        var count = 0
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw VerificationError.failed(label) }; passed.append(label)
        }
        do {
            for _ in 0..<100 {
                if !model.account.initializing { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard let identity = model.account.identity, model.canSyncJournal, model.cloudState.enabled else { throw VerificationError.failed("signed-in enabled journal required") }
            let before = try JournalCloudSnapshot(trips: model.trips.map(CloudTripSummary.init), notes: model.symptoms).encoded()
            // Empty baseline/local inputs treat all server records as additions. The
            // sync service's unchanged-remote branch performs a server read, no write.
            let result = try await CloudJournalService().synchronize(local: .init(), base: .init(), identity: identity, materialize: false)
            count = result.snapshot.trips.count + result.snapshot.notes.count
            try check(count > 0, "authenticated production server returned actual synthetic records")
            let payload = try result.snapshot.encoded()
            try check(payload == model.cloudState.base.encoded(), "server snapshot matches the acknowledged manual upload")
            let emptyStore = try LocalStore(inMemory: true)
            let emptyNotes = try emptyStore.read("symptom", as: SymptomEntry.self)
            let emptyTrips = try emptyStore.read("trip", as: TripEntry.self)
            try check(emptyNotes.isEmpty && emptyTrips.isEmpty, "restoration starts with an empty isolated Core Data store")
            let encoder = JSONEncoder()
            let trips = result.snapshot.trips.map { $0.restored(preserving: nil) }
            var state = JournalCloudState(); state.base = result.snapshot; state.revision = result.revision
            try emptyStore.replaceJournal(trips: trips.map { ($0.id, try encoder.encode($0)) },
                                          notes: result.snapshot.notes.map { ($0.id, try encoder.encode($0)) },
                                          state: (JournalCloudState.storageID, try encoder.encode(state)))
            let restored = try JournalCloudSnapshot(trips: emptyStore.read("trip", as: TripEntry.self).map(CloudTripSummary.init),
                                                   notes: emptyStore.read("symptom", as: SymptomEntry.self),
                                                   profile: state.base.profile, preferences: state.base.preferences).encoded()
            try check(restored == payload, "actual server records restore through production Core Data storage")
            let after = try JournalCloudSnapshot(trips: model.trips.map(CloudTripSummary.init), notes: model.symptoms).encoded()
            try check(before == after && model.account.identity == identity, "source account and local journal remain unchanged")
        } catch let error as VerificationError { failure = String(describing: error) }
        catch { failure = CloudJournalService.explain(error) }
        let report: [String: Any] = ["workflow": "user-confirmed synthetic production journal read and isolated restore",
                                     "passed": passed, "passedCount": passed.count, "recordCount": count,
                                     "success": failure == nil, "failure": failure ?? NSNull(),
                                     "secondRealDeviceTest": false, "sourceJournalModified": false]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("live-journal-restore-qa.json"), options: .atomic)
        }
    }
    private enum VerificationError: Error { case failed(String) }
}
#endif
