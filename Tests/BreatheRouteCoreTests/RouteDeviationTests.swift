import Foundation
import Testing
@testable import BreatheRouteCore

private func verify(_ value: Bool) { #expect(value) }

private let path = [GeoCoordinate(latitude: 6.91, longitude: 79.86), GeoCoordinate(latitude: 6.93, longitude: 79.86)]
private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func deviationRequiresSustainedAccurateFixes() {
    var monitor = RouteDeviationMonitor()
    let outside = GeoCoordinate(latitude: 6.92, longitude: 79.862)
    verify(!monitor.update(coordinate: outside, accuracy: 10, date: now, now: now, path: path))
    verify(!monitor.update(coordinate: outside, accuracy: 10, date: now.addingTimeInterval(4), now: now.addingTimeInterval(4), path: path))
    verify(monitor.update(coordinate: outside, accuracy: 10, date: now.addingTimeInterval(8), now: now.addingTimeInterval(8), path: path))
}
@Test func deviationUsesSegmentsAndResetsOnReturningOrLongGap() {
    var monitor = RouteDeviationMonitor()
    let outside = GeoCoordinate(latitude: 6.92, longitude: 79.862)
    for seconds in [0.0, 4] {
        _ = monitor.update(coordinate: outside, accuracy: 10, date: now.addingTimeInterval(seconds), now: now.addingTimeInterval(seconds), path: path)
    }
    verify(!monitor.update(coordinate: .init(latitude: 6.92, longitude: 79.86), accuracy: 10, date: now.addingTimeInterval(8), now: now.addingTimeInterval(8), path: path))
    verify(!monitor.update(coordinate: outside, accuracy: 10, date: now.addingTimeInterval(12), now: now.addingTimeInterval(12), path: path))
    verify(!monitor.update(coordinate: outside, accuracy: 10, date: now.addingTimeInterval(60), now: now.addingTimeInterval(60), path: path))
}
@Test func deviationRejectsStaleInaccurateAndRepeatedFixes() {
    var monitor = RouteDeviationMonitor()
    let outside = GeoCoordinate(latitude: 6.92, longitude: 79.862)
    for accuracy in [-1.0, 90, .nan, .infinity] {
        verify(!monitor.update(coordinate: outside, accuracy: accuracy, date: now, now: now, path: path))
    }
    verify(!monitor.update(coordinate: outside, accuracy: 10, date: now.addingTimeInterval(-60), now: now, path: path))
    for _ in 0..<10 { verify(!monitor.update(coordinate: outside, accuracy: 10, date: now, now: now, path: path)) }
}
@Test func automaticReroutesHaveCooldownAndRejectClockRollback() {
    var gate = AutomaticRerouteGate()
    verify(gate.accept(now: now))
    verify(!gate.accept(now: now.addingTimeInterval(10)))
    verify(!gate.accept(now: now.addingTimeInterval(-1)))
    verify(gate.accept(now: now.addingTimeInterval(120)))
}
