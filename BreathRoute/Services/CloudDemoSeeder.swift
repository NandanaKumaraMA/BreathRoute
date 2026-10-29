import Foundation
import FirebaseFirestore

@MainActor enum CloudDemoSeeder {
    static func seed(database: Firestore, userID: String, revision: String) async throws {
        let snapshot = try CloudDemoFixtures.snapshot()
        let dataset = database.collection("users").document(userID).collection("demoDatasets").document(CloudDemoFixtures.datasetID)
        let batch = database.batch(), encoder = JournalCloudSnapshot.encoder()
        batch.setData(["schemaVersion": 1, "label": CloudDemoFixtures.label, "synthetic": true,
                       "walkCount": CloudDemoFixtures.walkCount, "symptomCount": CloudDemoFixtures.noteCount, "updatedAt": FieldValue.serverTimestamp(),
                       "profile": ["displayName": "Demo Walker"],
                       "preferences": ["walkingPace": "Easy", "extraMinutes": 10]], forDocument: dataset)
        for (collection, values) in [("walks", try snapshot.trips.map { ($0.id, try encoder.encode($0)) }),
                                     ("symptoms", try snapshot.notes.map { ($0.id, try encoder.encode($0)) })] {
            for (id, data) in values {
                var fields = try StructuredCloudStore.recordFields(data, revision: revision)
                fields["synthetic"] = true; fields["datasetID"] = CloudDemoFixtures.datasetID
                batch.setData(fields, forDocument: dataset.collection(collection).document(id.uuidString))
            }
        }
        try await batch.commit()
    }
}
