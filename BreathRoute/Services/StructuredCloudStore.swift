import Foundation
import FirebaseFirestore

/// Readable records are derived from the conflict-safe journal snapshot. Each
/// chunk checks its revision; the parent marks completion only after every chunk.
@MainActor enum StructuredCloudStore {
    private struct Change {
        let reference: DocumentReference
        let fields: [String: Any]?
    }
    static func project(database: Firestore, userID: String, snapshot: JournalCloudSnapshot, revision: String,
                        check: @MainActor () throws -> Void) async throws {
        try check()
        let user = database.collection("users").document(userID)
        let journal = user.collection("journal").document("current")
        var changes: [Change] = []
        let encoder = JournalCloudSnapshot.encoder()
        for (collection, records) in [
            ("walks", try snapshot.trips.map { ($0.id.uuidString, try encoder.encode($0)) }),
            ("symptoms", try snapshot.notes.map { ($0.id.uuidString, try encoder.encode($0)) })
        ] {
            let reference = user.collection(collection)
            let existing = try await reference.limit(to: 1001).getDocuments(source: .server)
            try check()
            guard existing.documents.count <= 1000 else { throw JournalSyncError.tooLarge }
            let desiredIDs = Set(records.map(\.0))
            let actual = Dictionary(uniqueKeysWithValues: existing.documents.map { ($0.documentID, $0.data()) })
            for (id, data) in records {
                let fields = try recordFields(data, revision: revision)
                if let old = actual[id], NSDictionary(dictionary: old).isEqual(to: fields) { continue }
                changes.append(Change(reference: reference.document(id), fields: fields))
            }
            for document in existing.documents where !desiredIDs.contains(document.documentID) {
                changes.append(Change(reference: document.reference, fields: nil))
            }
        }
        // Small bounded chunks leave room for rules checks and SDK write limits.
        for offset in stride(from: 0, to: changes.count, by: 40) {
            try check()
            let chunk = Array(changes[offset..<min(offset + 40, changes.count)])
            _ = try await database.runTransaction { transaction, errorPointer -> Any? in
                do {
                    guard try transaction.getDocument(journal).data()?["revision"] as? String == revision else {
                        errorPointer?.pointee = changed(); return nil
                    }
                    for change in chunk {
                        if let fields = change.fields { transaction.setData(fields, forDocument: change.reference) }
                        else { transaction.deleteDocument(change.reference) }
                    }
                    return revision
                } catch { errorPointer?.pointee = error as NSError; return nil }
            }
            try check()
        }
        let profile = snapshot.profile ?? CloudUserProfile(displayName: "")
        let preferences = snapshot.preferences ?? CloudPreferences(walkingPace: "Easy", extraMinutes: 10)
        try check()
        _ = try await database.runTransaction { transaction, errorPointer -> Any? in
            do {
                guard try transaction.getDocument(journal).data()?["revision"] as? String == revision else {
                    errorPointer?.pointee = changed(); return nil
                }
                transaction.setData(["schemaVersion": 1, "displayName": profile.displayName,
                                     "walkCount": snapshot.trips.count, "symptomCount": snapshot.notes.count,
                                     "journalRevision": revision, "updatedAt": FieldValue.serverTimestamp()], forDocument: user)
                transaction.setData(["schemaVersion": 1, "walkingPace": preferences.walkingPace,
                                     "extraMinutes": preferences.extraMinutes, "journalRevision": revision,
                                     "updatedAt": FieldValue.serverTimestamp()], forDocument: user.collection("preferences").document("current"))
                return revision
            } catch { errorPointer?.pointee = error as NSError; return nil }
        }
        try check()
    }
    static func recordFields(_ data: Data, revision: String? = nil) throws -> [String: Any] {
        guard var fields = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let date = fields["date"] as? Double else { throw JournalSyncError.invalid }
        fields["date"] = Timestamp(date: Date(timeIntervalSince1970: date / 1000))
        fields["schemaVersion"] = 1
        if let revision { fields["journalRevision"] = revision }
        return fields
    }
    nonisolated private static func changed() -> NSError { NSError(domain: "BreatheRouteJournalSync", code: 1) }
}
