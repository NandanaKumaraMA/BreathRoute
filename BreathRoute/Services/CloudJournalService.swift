import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

struct CloudJournalResult {
    let snapshot: JournalCloudSnapshot
    let revision: String?
    let conflictCount: Int
    var settingsConflictCount = 0
}

struct CloudDemoReadResult {
    let snapshot: JournalCloudSnapshot
    let updatedAt: Date
}

enum CloudDemoReadError: String, LocalizedError {
    case notReady = "The expanded cloud examples are not available for this account yet. The bundled examples remain available."
    case changed = "The examples changed while loading. Try loading them again."
    var errorDescription: String? { rawValue }
}

@MainActor @Observable
final class CloudJournalService {
    private(set) var working = false
    var message: String?
    var onLocalRevision: ((String) -> Void)?
    @ObservationIgnored private var database: Firestore?
    private static var configuredDatabase: Firestore?
    private var generation = 0

    func resetForAccountChange() { generation += 1; working = false; message = nil }

    func synchronize(local: JournalCloudSnapshot, base: JournalCloudSnapshot, identity: AccountIdentity, materialize: Bool = true) async throws -> CloudJournalResult {
        guard !working else { throw JournalSyncError.unavailable }
        try checkAccount(identity)
        working = true; message = nil; let ticket = generation
        defer { if ticket == generation { working = false } }
        if database == nil { database = try Self.connection(for: identity) }
        guard let database else { throw JournalSyncError.unavailable }
        let reference = database.collection("users").document(identity.userID).collection("journal").document("current")
        for attempt in 0..<3 {
            try checkAccount(identity); try Task.checkCancellation()
            guard ticket == generation else { throw JournalSyncError.wrongAccount }
            let document = try await reference.getDocument(source: .server)
            let remote: JournalCloudSnapshot, revision: String?
            if document.exists {
                guard let fields = document.data(), Set(fields.keys) == ["schemaVersion", "revision", "updatedAt", "payload"],
                      [1, 2].contains(fields["schemaVersion"] as? Int ?? 0), fields["updatedAt"] is Timestamp,
                      let version = fields["revision"] as? String, UUID(uuidString: version) != nil,
                      let payload = fields["payload"] as? String, let data = payload.data(using: .utf8) else { throw JournalSyncError.invalid }
                remote = try JournalCloudSnapshot.decoded(data); revision = version
            } else { remote = JournalCloudSnapshot(); revision = nil }
            let merged = try JournalCloudMerge.merge(base: base, local: local, remote: remote)
            try checkAccount(identity)
            guard ticket == generation else { throw JournalSyncError.wrongAccount }
            if merged.snapshot == remote {
                if materialize, let revision {
                    do { try await project(database, identity: identity, snapshot: remote, revision: revision, ticket: ticket) }
                    catch JournalSyncError.changed { if attempt < 2 { continue }; throw JournalSyncError.changed }
                }
                return CloudJournalResult(snapshot: remote, revision: revision, conflictCount: merged.conflictCount, settingsConflictCount: merged.settingsConflictCount)
            }
            let data = try merged.snapshot.encoded()
            guard let payload = String(data: data, encoding: .utf8) else { throw JournalSyncError.invalid }
            let nextRevision = UUID().uuidString
            onLocalRevision?(nextRevision)
            do {
                _ = try await database.runTransaction { transaction, errorPointer -> Any? in
                    do {
                        let current = try transaction.getDocument(reference)
                        let currentRevision = current.data()?["revision"] as? String
                        guard current.exists == (revision != nil), currentRevision == revision else {
                            errorPointer?.pointee = NSError(domain: "BreatheRouteJournalSync", code: 1); return nil
                        }
                        transaction.setData(["schemaVersion": 2, "revision": nextRevision,
                                             "updatedAt": FieldValue.serverTimestamp(), "payload": payload], forDocument: reference)
                        return nextRevision
                    } catch { errorPointer?.pointee = error as NSError; return nil }
                }
            } catch {
                let failure = error as NSError
                if failure.domain == "BreatheRouteJournalSync" && failure.code == 1 {
                    if attempt < 2 { continue }; throw JournalSyncError.changed
                }
                throw error
            }
            try checkAccount(identity)
            guard ticket == generation else { throw JournalSyncError.wrongAccount }
            if materialize {
                do { try await project(database, identity: identity, snapshot: merged.snapshot, revision: nextRevision, ticket: ticket) }
                catch JournalSyncError.changed { if attempt < 2 { continue }; throw JournalSyncError.changed }
            }
            return CloudJournalResult(snapshot: merged.snapshot, revision: nextRevision, conflictCount: merged.conflictCount, settingsConflictCount: merged.settingsConflictCount)
        }
        throw JournalSyncError.changed
    }

    /// Read-only and explicitly requested. Does not seed, upload or merge any journal entries.
    func loadDemonstration(identity: AccountIdentity) async throws -> CloudDemoReadResult {
        let db = try Self.connection(for: identity), ticket = generation
        func check() throws {
            try checkAccount(identity); try Task.checkCancellation()
            guard ticket == generation else { throw JournalSyncError.wrongAccount }
        }
        try check()
        let reference = db.collection("users").document(identity.userID).collection("demoDatasets").document(CloudDemoFixtures.datasetID)
        let manifest = try await reference.getDocument(source: .server)
        try check()
        guard let fields = manifest.data(), fields["schemaVersion"] as? Int == 1,
              fields["synthetic"] as? Bool == true, fields["label"] as? String == CloudDemoFixtures.label,
              fields["walkCount"] as? Int == CloudDemoFixtures.walkCount, fields["symptomCount"] as? Int == CloudDemoFixtures.noteCount,
              let timestamp = fields["updatedAt"] as? Timestamp,
              (fields["profile"] as? [String: String]) == ["displayName": "Demo Walker"],
              let preferences = fields["preferences"] as? [String: Any],
              preferences["walkingPace"] as? String == "Easy", (preferences["extraMinutes"] as? NSNumber)?.doubleValue == 10
        else { throw CloudDemoReadError.notReady }
        async let walkQuery = reference.collection("walks").limit(to: CloudDemoFixtures.walkCount + 1).getDocuments(source: .server)
        async let noteQuery = reference.collection("symptoms").limit(to: CloudDemoFixtures.noteCount + 1).getDocuments(source: .server)
        let (walks, notes) = try await (walkQuery, noteQuery)
        try check()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let trips = try walks.documents.map { try decoder.decode(CloudTripSummary.self, from: Self.demoRecord($0, walk: true)) }
        let symptoms = try notes.documents.map { try decoder.decode(SymptomEntry.self, from: Self.demoRecord($0, walk: false)) }
        let final = try await reference.getDocument(source: .server)
        try check()
        // The seed is one batch. Reject a mixed read if it was replaced between queries.
        guard let finalFields = final.data(), NSDictionary(dictionary: fields).isEqual(to: finalFields) else { throw CloudDemoReadError.changed }
        let snapshot = try CloudDemoFixtures.validate(.init(trips: trips, notes: symptoms, profile: .init(displayName: "Demo Walker"),
                                                           preferences: .init(walkingPace: "Easy", extraMinutes: 10)))
        return CloudDemoReadResult(snapshot: snapshot, updatedAt: timestamp.dateValue())
    }

    private static func demoRecord(_ document: QueryDocumentSnapshot, walk: Bool) throws -> Data {
        var fields = document.data()
        let allowed: Set<String> = walk
            ? ["schemaVersion", "id", "date", "destination", "metres", "seconds", "dose", "coverage", "demo", "complete", "ventilation", "routeSource", "conflictCopyOf", "journalRevision", "synthetic", "datasetID"]
            : ["schemaVersion", "id", "date", "kind", "severity", "notes", "tripID", "conflictCopyOf", "journalRevision", "synthetic", "datasetID"]
        guard Set(fields.keys).isSubset(of: allowed), fields["schemaVersion"] as? Int == 1,
              fields["synthetic"] as? Bool == true, fields["datasetID"] as? String == CloudDemoFixtures.datasetID,
              fields["id"] as? String == document.documentID, UUID(uuidString: document.documentID) != nil,
              let revision = fields["journalRevision"] as? String, UUID(uuidString: revision) != nil,
              let date = fields["date"] as? Timestamp else { throw JournalSyncError.invalid }
        fields["date"] = date.dateValue().timeIntervalSince1970 * 1000
        for key in ["schemaVersion", "synthetic", "datasetID", "journalRevision"] { fields.removeValue(forKey: key) }
        return try JSONSerialization.data(withJSONObject: fields)
    }

    static func connection(for identity: AccountIdentity) throws -> Firestore {
        guard let app = FirebaseBootstrap.app, app.options.projectID == identity.projectID,
              FirebaseBootstrap.environment == identity.environment,
              Auth.auth(app: app).currentUser?.uid == identity.userID else { throw JournalSyncError.wrongAccount }
        if let configuredDatabase { return configuredDatabase }
        let db = Firestore.firestore(app: app), settings = db.settings
        // Configure the shared SDK instance once, before journal reads or private notification registration.
        settings.cacheSettings = MemoryCacheSettings()
        #if DEBUG
        if identity.environment == .emulator { settings.host = "127.0.0.1:8080"; settings.isSSLEnabled = false }
        #endif
        db.settings = settings; configuredDatabase = db
        return db
    }

    private func project(_ database: Firestore, identity: AccountIdentity, snapshot: JournalCloudSnapshot, revision: String, ticket: Int) async throws {
        do {
            try await StructuredCloudStore.project(database: database, userID: identity.userID, snapshot: snapshot, revision: revision) {
                try self.checkAccount(identity); try Task.checkCancellation()
                guard ticket == self.generation else { throw JournalSyncError.wrongAccount }
            }
        } catch {
            let issue = error as NSError
            if issue.domain == "BreatheRouteJournalSync" && issue.code == 1 { throw JournalSyncError.changed }
            throw error
        }
    }

    private func checkAccount(_ identity: AccountIdentity) throws {
        guard let app = FirebaseBootstrap.app, app.options.projectID == identity.projectID,
              FirebaseBootstrap.environment == identity.environment,
              Auth.auth(app: app).currentUser?.uid == identity.userID else { throw JournalSyncError.wrongAccount }
    }

    static func explain(_ error: Error) -> String {
        if let sync = error as? JournalSyncError { return sync.rawValue }
        let failure = error as NSError
        guard failure.domain == FirestoreErrorDomain else {
            return "Sync could not finish. Local records remain saved. Please try Sync now again."
        }
        let code = FirestoreErrorCode.Code(rawValue: failure.code)
        switch code {
        case .permissionDenied: return "Cloud access was denied. Your local journal is safe. Check this account's access and the project's private journal rules."
        case .unauthenticated: return "Your account needs to sign in again before syncing. Your local journal is safe."
        case .unavailable, .deadlineExceeded: return "The cloud could not be reached. Your local changes are saved; use Sync now again when connected."
        case .resourceExhausted: return "The project's cloud quota has been reached. Local records remain available. Try again later."
        case .notFound, .failedPrecondition: return "The cloud journal connection needs setup. Your local records have not been changed."
        default: return "Sync could not finish. Local records remain saved. Please try Sync now again."
        }
    }
}
