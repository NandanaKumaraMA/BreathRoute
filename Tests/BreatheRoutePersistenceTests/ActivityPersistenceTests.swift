import Foundation
import Testing
@testable import BreatheRouteCore
@testable import BreatheRoutePersistence

private struct LegacyTrip: Encodable {
    let id: UUID
    let date: Date
    let destination = "Existing saved walk"
    let metres = 500.0
    let seconds = 300.0
    let dose = 2.0
    let coverage = 1.0
    let demo = false
    let complete = false
}

@MainActor @Test func sqliteReopensNewActivityAndExistingTripPayloads() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BreatheRouteActivityTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("walks.sqlite"), start = Date(timeIntervalSince1970: 1000)
    var timeline = MotionTimeline(start: start)
    timeline.setState(.walking, at: start); timeline.advance(to: start.addingTimeInterval(60))
    let summary = WalkActivitySummary(steps: 80, pedometerMetres: 55, timeline: timeline, stepStatus: .available, classificationStatus: .available, stepsUpdatedAt: start.addingTimeInterval(60))
    let trip = TripEntry(destination: "Activity persistence test", metres: 50, seconds: 60, dose: 1, coverage: 1, demo: false, complete: false, activity: summary)
    let legacy = LegacyTrip(id: UUID(), date: start)
    do {
        let store = try LocalStore(storeURL: url)
        try store.save(trip, id: trip.id, kind: "trip")
        try store.save(legacy, id: legacy.id, kind: "trip")
    }
    let reopened = try LocalStore(storeURL: url)
    let trips = try reopened.read("trip", as: TripEntry.self)
    let restored = try #require(trips.first { $0.id == trip.id })
    let old = try #require(trips.first { $0.id == legacy.id })
    #expect(trips.count == 2 && old.activity == nil)
    #expect(restored.activity?.steps == 80 && restored.activity?.walkingSeconds == 60)
    #expect(restored.metres == 50 && restored.activity?.pedometerMetres == 55 && restored.dose == 1)
}

private struct FailedActivityPayload: Encodable {
    func encode(to encoder: Encoder) throws { throw CocoaError(.coderInvalidValue) }
}
@MainActor @Test func failedActivitySaveKeepsPreviouslySavedWalk() throws {
    let store = try LocalStore(inMemory: true)
    let trip = TripEntry(destination: "Retained walk", metres: 100, seconds: 90, dose: nil, coverage: 0, demo: false, complete: false)
    try store.save(trip, id: trip.id, kind: "trip")
    do {
        try store.save(FailedActivityPayload(), id: trip.id, kind: "trip")
        Issue.record("The invalid payload should fail encoding.")
    } catch { }
    let records = try store.read("trip", as: TripEntry.self)
    #expect(records.count == 1 && records.first?.destination == "Retained walk")
}
