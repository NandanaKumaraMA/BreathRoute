import Foundation
import Testing
@testable import BreatheRouteCore

@Test func motionClassificationHandlesConfidenceAndOverlappingFlags() {
    func state(_ walking: Bool = false, stationary: Bool = false, automotive: Bool = false, confident: Bool = true) -> PhoneMotionState {
        MotionClassification.state(walking: walking, stationary: stationary, running: false, cycling: false, automotive: automotive, unknown: false, confident: confident)
    }
    #expect(state(true) == .walking)
    #expect(state(stationary: true) == .stationary)
    #expect(state(stationary: true, automotive: true) == .other)
    #expect(state(true, stationary: true) == .unknown)
    #expect(state(true, confident: false) == .unknown)
    #expect(state() == .unknown)
}

@Test func motionTimelineKeepsDisabledAndBackgroundTimeUnclassified() {
    let start = Date(timeIntervalSince1970: 1000)
    var timeline = MotionTimeline(start: start)
    timeline.setState(.walking, at: start.addingTimeInterval(10))
    timeline.setState(.stationary, at: start.addingTimeInterval(30))
    timeline.setState(.unknown, at: start.addingTimeInterval(45)) // background / disabled
    timeline.setState(.walking, at: start.addingTimeInterval(75))
    timeline.advance(to: start.addingTimeInterval(85))
    timeline.setState(.stationary, at: start.addingTimeInterval(20)) // stale callback
    timeline.advance(to: start.addingTimeInterval(90))
    #expect(timeline.walkingSeconds == 35)
    #expect(timeline.stationarySeconds == 15)
    #expect(timeline.unknownSeconds == 40)
    #expect(timeline.elapsed == 90)
}

@Test func pedometerTotalsPreserveCountsAcrossMonitoringWindowsWithoutDuplication() {
    let start = Date(timeIntervalSince1970: 1000)
    var totals = PedometerTotals()
    #expect(totals.steps == nil && totals.metres == nil)
    totals.beginWindow(at: start)
    let first = totals.accept(steps: 50, metres: 35, at: start.addingTimeInterval(30))
    let duplicate = totals.accept(steps: 50, metres: 35, at: start.addingTimeInterval(30))
    let decreasing = totals.accept(steps: 40, metres: 28, at: start.addingTimeInterval(35))
    #expect(first && duplicate && !decreasing)
    totals.endWindow()
    let stopped = totals.accept(steps: 100, metres: 70, at: start.addingTimeInterval(40))
    #expect(!stopped)
    totals.beginWindow(at: start.addingTimeInterval(60))
    let stale = totals.accept(steps: 70, metres: 45, at: start.addingTimeInterval(45))
    let resumed = totals.accept(steps: 20, metres: 14, at: start.addingTimeInterval(80))
    #expect(!stale && resumed)
    #expect(totals.steps == 70 && totals.metres == 49)
}

@Test func pedometerRejectsInvalidValuesWithoutInventingDistance() {
    let now = Date()
    var totals = PedometerTotals()
    totals.beginWindow(at: now)
    let negative = totals.accept(steps: -1, metres: 1, at: now)
    let zero = totals.accept(steps: 0, metres: .nan, at: now)
    #expect(!negative && zero)
    #expect(totals.steps == 0 && totals.metres == nil)
    let valid = totals.accept(steps: 5, metres: 4, at: now.addingTimeInterval(5))
    let invalidDistance = totals.accept(steps: 6, metres: -1, at: now.addingTimeInterval(6))
    #expect(valid && invalidDistance)
    #expect(totals.metres == 4)
}

@Test func activitySummaryRoundTripsWithoutChangingExposureOrGPSDistance() throws {
    let start = Date(timeIntervalSince1970: 1000)
    var timeline = MotionTimeline(start: start)
    timeline.setState(.stationary, at: start)
    timeline.advance(to: start.addingTimeInterval(20))
    let summary = WalkActivitySummary(steps: 7, pedometerMetres: 5, timeline: timeline, stepStatus: .available, classificationStatus: .available, stepsUpdatedAt: start)
    let trip = TripEntry(destination: "Test", metres: 120, seconds: 20, dose: 0.8, coverage: 1, demo: false, complete: false, activity: summary)
    let restored = try JSONDecoder().decode(TripEntry.self, from: JSONEncoder().encode(trip))
    #expect(restored.activity?.steps == 7 && restored.activity?.stationarySeconds == 20)
    #expect(restored.metres == 120 && restored.dose == 0.8)
    #expect(restored.activity?.classifiedFraction == 1)
}

@Test func olderSavedTripsRemainReadableWithoutActivity() throws {
    let trip = TripEntry(destination: "Existing walk", metres: 500, seconds: 300, dose: nil, coverage: 0, demo: false, complete: false)
    var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(trip)) as? [String: Any])
    payload.removeValue(forKey: "activity")
    let restored = try JSONDecoder().decode(TripEntry.self, from: JSONSerialization.data(withJSONObject: payload))
    #expect(restored.activity == nil)
    #expect(restored.destination == trip.destination && restored.metres == 500)
}
