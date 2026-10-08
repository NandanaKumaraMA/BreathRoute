import Testing
@testable import BreatheRouteCore

@Test func nearbyDistanceHasMeaningfulUnits() {
    let metres = NearbyRanking.distance(fromLatitude: 0, fromLongitude: 0, toLatitude: 0, toLongitude: 1)
    #expect(abs((metres ?? 0) - 111_195) < 5)
    #expect(NearbyRanking.distance(fromLatitude: 6.9, fromLongitude: 79.8, toLatitude: 6.9, toLongitude: 79.8) == 0)
}

@Test func nearbyEnforcesRadiusAndRanksClosestFirst() {
    let matches = NearbyRanking.rank([
        .init(id: "far", latitude: 0, longitude: 0.1),
        .init(id: "second", latitude: 0, longitude: 0.02),
        .init(id: "first", latitude: 0, longitude: 0.01)
    ], latitude: 0, longitude: 0, radius: 3000)
    #expect(matches.map(\.id) == ["first", "second"])
}

@Test func nearbyRejectsInvalidLocationsAndRadius() {
    #expect(NearbyRanking.distance(fromLatitude: .nan, fromLongitude: 0, toLatitude: 0, toLongitude: 0) == nil)
    #expect(NearbyRanking.distance(fromLatitude: 91, fromLongitude: 0, toLatitude: 0, toLongitude: 0) == nil)
    let candidates = [NearbyCandidate(id: "place", latitude: 0, longitude: 0)]
    #expect(NearbyRanking.rank(candidates, latitude: 0, longitude: 0, radius: -1).isEmpty)
    #expect(NearbyRanking.rank(candidates, latitude: 0, longitude: 0, radius: .infinity).isEmpty)
}

@Test func nearbyDeduplicatesAndBreaksTiesDeterministically() {
    let matches = NearbyRanking.rank([
        .init(id: "b", latitude: 0, longitude: 0.01),
        .init(id: "a", latitude: 0, longitude: 0.01),
        .init(id: "a", latitude: 0, longitude: 0.02)
    ], latitude: 0, longitude: 0, radius: 3000)
    #expect(matches.map(\.id) == ["a", "b"])
    #expect(matches.count == 2)
}
