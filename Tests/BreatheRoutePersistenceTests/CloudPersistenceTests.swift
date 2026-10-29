import Foundation
import Testing
@testable import BreatheRouteCore
@testable import BreatheRoutePersistence

@MainActor @Test func journalAndBaselineReplaceAtomicallyAndSurviveReopen() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BreatheRouteCloud-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("journal.sqlite"), encoder = JSONEncoder()
    let old = SymptomEntry(notes: "Old synthetic entry"), next = SymptomEntry(notes: "Merged synthetic entry")
    let checkpointID = UUID()
    let snapshot = try JournalCloudSnapshot(notes: [next]).validated()
    var state = JournalCloudState(); state.enabled = true; state.base = snapshot; state.revision = UUID().uuidString
    do {
        let store = try LocalStore(storeURL: url)
        try store.save(old, id: old.id, kind: "symptom")
        try store.save("Unrelated recovery marker", id: checkpointID, kind: "active-walk")
        try store.replaceJournal(trips: [], notes: [(next.id, try encoder.encode(next))], state: (JournalCloudState.storageID, try encoder.encode(state)))
    }
    let reopened = try LocalStore(storeURL: url)
    #expect(try reopened.read("symptom", as: SymptomEntry.self) == [next])
    #expect(try reopened.read("cloud-state", as: JournalCloudState.self).first?.base == snapshot)
    #expect(try reopened.read("active-walk", as: String.self) == ["Unrelated recovery marker"])
    // Force a uniqueness violation at save, after deletion and insertion have begun.
    do {
        try reopened.replaceJournal(trips: [], notes: [(checkpointID, try encoder.encode(next))], state: (JournalCloudState.storageID, try encoder.encode(JournalCloudState())))
        Issue.record("A conflicting record ID must fail atomically")
    } catch { }
    let afterFailure = try LocalStore(storeURL: url)
    #expect(try afterFailure.read("symptom", as: SymptomEntry.self) == [next])
    #expect(try afterFailure.read("cloud-state", as: JournalCloudState.self).first?.revision == state.revision)
    #expect(try afterFailure.read("active-walk", as: String.self).count == 1)
}
