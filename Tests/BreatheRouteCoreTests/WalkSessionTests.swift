import Foundation
import Testing
@testable import BreatheRouteCore

private let recordingStart = Date(timeIntervalSince1970: 1000)
private let recordingPoint = GeoCoordinate(latitude: 6.9178, longitude: 79.8637)
private func sessionRoute() -> SavedRoute {
    SavedRoute(name: "Public-coordinate test", coordinates: [recordingPoint, .init(latitude: 6.9165, longitude: 79.8626)],
               metres: 220, seconds: 180, estimate: ExposureCalculator.estimate([.init(minutes: 3, pm25: 20)], ventilation: 0.015),
               demo: false, airSamples: [], source: "Synthetic test fixture", avoidedAreaCount: 0)
}
@Test func recordedPathNeverBridgesClosedAppTimeAndMissingAir() throws {
    var recorder = WalkRecorder()
    recorder.record(coordinate: recordingPoint, date: recordingStart, accuracy: 5, metresFromPrevious: nil, pm25: 20)
    recorder.record(coordinate: recordingPoint, date: recordingStart.addingTimeInterval(10), accuracy: 5, metresFromPrevious: 12, pm25: 20)
    recorder.breakPath()
    recorder.record(coordinate: recordingPoint, date: recordingStart.addingTimeInterval(110), accuracy: 5, metresFromPrevious: 999, pm25: 20)
    recorder.record(coordinate: recordingPoint, date: recordingStart.addingTimeInterval(120), accuracy: 5, metresFromPrevious: 11, pm25: nil)
    let checkpoint = ActiveWalkCheckpoint(sessionID: UUID(), startedAt: recordingStart, savedAt: recordingStart.addingTimeInterval(120),
                                          destination: "Recovered walk", route: sessionRoute(), recorder: recorder, ventilation: 0.015, activity: nil, recovered: true)
    let trip = checkpoint.trip(endedAt: checkpoint.savedAt)
    #expect(checkpoint.isValid && recorder.isValid)
    #expect(recorder.path.map(\.startsNewLeg) == [true, false, true, false])
    #expect(trip.metres == 23 && trip.seconds == 120 && recorder.recordedSeconds == 20)
    #expect(abs(try #require(trip.dose) - 0.05) < 0.000001)
    #expect(abs(trip.coverage - 10.0 / 120) < 0.000001 && !trip.complete)
}
@Test func badGPSFixesDoNotCreateMileageAndJumpsStartSeparateLines() {
    var recorder = WalkRecorder()
    recorder.record(coordinate: recordingPoint, date: recordingStart, accuracy: 5, metresFromPrevious: nil, pm25: 10)
    recorder.record(coordinate: .init(latitude: 100, longitude: 79), date: recordingStart.addingTimeInterval(1), accuracy: 5, metresFromPrevious: 10, pm25: 10)
    recorder.record(coordinate: recordingPoint, date: recordingStart.addingTimeInterval(2), accuracy: 101, metresFromPrevious: 10, pm25: 10)
    recorder.record(coordinate: recordingPoint, date: recordingStart, accuracy: 5, metresFromPrevious: 10, pm25: 10)
    recorder.record(coordinate: recordingPoint, date: recordingStart.addingTimeInterval(10), accuracy: 5, metresFromPrevious: 500, pm25: 10)
    recorder.record(coordinate: recordingPoint, date: recordingStart.addingTimeInterval(20), accuracy: 5, metresFromPrevious: 12, pm25: 10)
    #expect(recorder.path.count == 3 && recorder.path.map(\.startsNewLeg) == [true, true, false])
    #expect(recorder.metres == 12 && recorder.recordedSeconds == 10 && recorder.isValid)
}
@Test func recoveryRestoresMotionTotalsWithoutBackfillingSteps() {
    var timeline = MotionTimeline(start: recordingStart)
    timeline.setState(.walking, at: recordingStart); timeline.advance(to: recordingStart.addingTimeInterval(10))
    let original = WalkActivitySummary(steps: 14, pedometerMetres: 10, timeline: timeline, stepStatus: .available, classificationStatus: .available, stepsUpdatedAt: recordingStart.addingTimeInterval(10))
    var restored = MotionTimeline(restoring: original, checkpointedAt: recordingStart.addingTimeInterval(10), resumingAt: recordingStart.addingTimeInterval(110))
    var totals = PedometerTotals(restoring: original)
    totals.beginWindow(at: recordingStart.addingTimeInterval(110))
    let accepted = totals.accept(steps: 6, metres: 4, at: recordingStart.addingTimeInterval(120))
    restored.setState(.walking, at: recordingStart.addingTimeInterval(110)); restored.advance(to: recordingStart.addingTimeInterval(120))
    #expect(accepted && totals.steps == 20 && totals.metres == 14)
    #expect(restored.walkingSeconds == 20 && restored.unknownSeconds == 100 && restored.elapsed == 120)
}
@Test func checkpointRoundTripRetainsRouteAndBreaksItsNextRecordingLeg() throws {
    var recorder = WalkRecorder()
    recorder.record(coordinate: recordingPoint, date: recordingStart, accuracy: 4, metresFromPrevious: nil, pm25: nil)
    let original = ActiveWalkCheckpoint(sessionID: UUID(), startedAt: recordingStart, savedAt: recordingStart.addingTimeInterval(1),
                                        destination: "Saved destination", route: sessionRoute(), recorder: recorder, ventilation: 0.015, activity: nil, recovered: false)
    let decoded = try JSONDecoder().decode(ActiveWalkCheckpoint.self, from: JSONEncoder().encode(original))
    var resumed = decoded.recorder; resumed.breakPath()
    resumed.record(coordinate: recordingPoint, date: recordingStart.addingTimeInterval(120), accuracy: 4, metresFromPrevious: 800, pm25: 20)
    #expect(decoded.isValid && decoded.sessionID == original.sessionID && decoded.route.coordinates == original.route.coordinates)
    #expect(resumed.metres == 0 && resumed.path.last?.startsNewLeg == true)
    var futureVersion = decoded; futureVersion.version = 2
    #expect(!futureVersion.isValid)
}

@Test func reroutedCheckpointKeepsCumulativeAndRemainingProgressSeparate() throws {
    var recorder = WalkRecorder()
    recorder.record(coordinate: recordingPoint, date: recordingStart, accuracy: 5, metresFromPrevious: nil, pm25: 10)
    recorder.record(coordinate: recordingPoint, date: recordingStart.addingTimeInterval(10), accuracy: 5, metresFromPrevious: 12, pm25: 10)
    var checkpoint = ActiveWalkCheckpoint(sessionID: UUID(), startedAt: recordingStart, savedAt: recordingStart.addingTimeInterval(10),
        destination: "Rerouted example", route: sessionRoute(), recorder: recorder, ventilation: 0.015, activity: nil, recovered: false,
        previewMetres: 0, previewMovingSeconds: 10, routeStartRecordedMetres: 12)
    let decoded = try JSONDecoder().decode(ActiveWalkCheckpoint.self, from: JSONEncoder().encode(checkpoint))
    #expect(decoded.isValid && decoded.recorder.metres == 12 && decoded.previewMetres == 0 && decoded.routeStartRecordedMetres == 12)
    checkpoint.routeStartRecordedMetres = 13
    #expect(!checkpoint.isValid)
    var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
    for key in ["previewMetres", "previewMovingSeconds", "routeStartRecordedMetres"] { legacy.removeValue(forKey: key) }
    let old = try JSONDecoder().decode(ActiveWalkCheckpoint.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(old.isValid && old.previewMetres == nil && old.routeStartRecordedMetres == nil)
}
