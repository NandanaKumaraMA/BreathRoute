import Foundation
import Testing
@testable import BreatheRouteCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func area(_ id: String = "a", latitude: Double = 0, aqi: Int = 4, age: Double = 0) -> WatchArea {
    WatchArea(id: id, latitude: latitude, longitude: 0, pm25: 35, aqi: aqi, sampledAt: now.addingTimeInterval(-age))
}

@Test func watchAreasRejectExpiredLowAndInvalidSamples() {
    #expect(WatchAreaPolicy.select([area(age: 3600), area(aqi: 1), area(latitude: .nan)], now: now).isEmpty)
    #expect(WatchAreaPolicy.select([area(age: -301)], now: now).isEmpty)
}
@Test func watchAreasDeduplicateNearbyAndRespectLimit() {
    let selected = WatchAreaPolicy.select([area("a"), area("b", latitude: 0.001), area("c", latitude: 0.01)], now: now)
    #expect(selected.map(\.id) == ["a", "c"])
    let many = (0..<30).map { area(String($0), latitude: Double($0) * 0.01) }
    #expect(WatchAreaPolicy.select(many, now: now).count == 8)
}
@Test func geofenceChecksAccuracyOverlapAndCooldown() {
    var gate = AreaEntryGate()
    #expect(gate.update(areas: [area()], latitude: 0, longitude: 0, accuracy: 101, now: now) == nil)
    #expect(gate.update(areas: [area()], latitude: 0, longitude: 0, accuracy: 10, now: now)?.id == "a")
    #expect(gate.update(areas: [area(), area("b")], latitude: 0, longitude: 0, accuracy: 10, now: now.addingTimeInterval(1)) == nil)
    _ = gate.update(areas: [area()], latitude: 1, longitude: 0, accuracy: 10, now: now.addingTimeInterval(20))
    #expect(gate.update(areas: [area()], latitude: 0, longitude: 0, accuracy: 10, now: now.addingTimeInterval(30)) == nil)
    _ = gate.update(areas: [area()], latitude: 1, longitude: 0, accuracy: 10, now: now.addingTimeInterval(300))
    #expect(gate.update(areas: [area()], latitude: 0, longitude: 0, accuracy: 10, now: now.addingTimeInterval(301)) != nil)
}
@Test func avoidancePolygonIsClosedAndUsesLongitudeFirst() {
    let sample = WatchArea(id: "colombo", latitude: 6.9, longitude: 79.8, pm25: 30, aqi: 4, sampledAt: now)
    let ring = sample.polygon()
    #expect(ring.count == 37 && ring.first == ring.last)
    #expect(abs(ring[0][0] - 79.8) < 0.00001 && ring[0][1] > 6.9)
    for point in ring {
        let distance = NearbyRanking.distance(fromLatitude: 6.9, fromLongitude: 79.8, toLatitude: point[1], toLongitude: point[0])!
        #expect(distance > 250 && distance < 252)
    }
}
@Test func avoidanceChecksCrossingSegmentsWithOutsideEndpoints() {
    #expect(area().intersects([[-0.01, 0], [0.01, 0]]))
    #expect(!area().intersects([[-0.01, 0.01], [0.01, 0.01]]))
    #expect(area().intersects([[Double.nan, 0], [0.01, 0.01]]))
}
