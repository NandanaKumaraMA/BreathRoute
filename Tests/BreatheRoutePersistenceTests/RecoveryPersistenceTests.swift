import Foundation
import Testing
@testable import BreatheRouteCore
@testable import BreatheRoutePersistence

private func recoveryFixture() -> ActiveWalkCheckpoint {
    let start = Date(timeIntervalSince1970: 1000), point = GeoCoordinate(latitude: 6.9178, longitude: 79.8637)
    var recorder = WalkRecorder()
    recorder.record(coordinate: point, date: start, accuracy: 5, metresFromPrevious: nil, pm25: nil)
    recorder.record(coordinate: point, date: start.addingTimeInterval(10), accuracy: 5, metresFromPrevious: 12, pm25: 20)
    let route = SavedRoute(name: "Recovery test", coordinates: [point, .init(latitude: 6.9165, longitude: 79.8626)], metres: 220, seconds: 180,
                           estimate: ExposureCalculator.estimate([.init(minutes: 3, pm25: 20)], ventilation: 0.015), demo: false,
                           airSamples: [], source: "Synthetic persistence fixture", avoidedAreaCount: 0)
    return ActiveWalkCheckpoint(sessionID: UUID(), startedAt: start, savedAt: start.addingTimeInterval(10), destination: "Recovery test",
                                route: route, recorder: recorder, ventilation: 0.015, activity: nil, recovered: false)
}
@MainActor @Test func sqliteRecoveryFinishIsAtomicAndDoesNotDuplicateTrips() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BreatheRouteRecovery-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("walks.sqlite"), draft = recoveryFixture()
    let existing = TripEntry(destination: "Existing journal", metres: 50, seconds: 60, dose: nil, coverage: 0, demo: false, complete: false)
    do {
        let store = try LocalStore(storeURL: url)
        try store.save(existing, id: existing.id, kind: "trip")
        try store.save(draft, id: ActiveWalkCheckpoint.storageID, kind: "active-walk")
    }
    do {
        let store = try LocalStore(storeURL: url)
        let restored = try #require(store.read("active-walk", as: ActiveWalkCheckpoint.self).first)
        #expect(restored.isValid && restored.recorder.path.count == 2 && restored.recorder.metres == 12)
        let trip = restored.trip(endedAt: restored.savedAt)
        try store.finish(trip, tripID: trip.id, draftID: ActiveWalkCheckpoint.storageID)
        try store.finish(trip, tripID: trip.id, draftID: ActiveWalkCheckpoint.storageID)
    }
    let reopened = try LocalStore(storeURL: url)
    let trips = try reopened.read("trip", as: TripEntry.self)
    let drafts = try reopened.read("active-walk", as: ActiveWalkCheckpoint.self)
    #expect(drafts.isEmpty && trips.count == 2 && trips.contains { $0.id == existing.id })
    #expect(trips.first { $0.id == draft.sessionID }?.recordedPath?.count == 2)
}
private struct InvalidFinishPayload: Encodable {
    func encode(to encoder: Encoder) throws { throw CocoaError(.coderInvalidValue) }
}
@MainActor @Test func failedFinishPreservesUnfinishedRecordingForRetry() throws {
    let store = try LocalStore(inMemory: true), draft = recoveryFixture()
    try store.save(draft, id: ActiveWalkCheckpoint.storageID, kind: "active-walk")
    do {
        try store.finish(InvalidFinishPayload(), tripID: draft.sessionID, draftID: ActiveWalkCheckpoint.storageID)
        Issue.record("An invalid payload must not finish the walk.")
    } catch { }
    let drafts = try store.read("active-walk", as: ActiveWalkCheckpoint.self), trips = try store.read("trip", as: TripEntry.self)
    #expect(drafts.count == 1 && drafts.first?.sessionID == draft.sessionID && trips.isEmpty)
}
