import Foundation
import Testing
@testable import BreatheRouteCore

private let routingNow = Date(timeIntervalSince1970: 1_800_000_000)
private let routingStart = GeoCoordinate(latitude: 0, longitude: -0.01)
private let routingEnd = GeoCoordinate(latitude: 0, longitude: 0.01)
private func sampleArea(_ index: Int = 0) -> WatchArea {
    WatchArea(id: "sample-\(index)", latitude: Double(index) * 0.01, longitude: 0, pm25: 35, aqi: 4, sampledAt: routingNow)
}
private func routingData(_ legs: [[[Double]]] = [[[-0.01, 0], [0.01, 0]]], distance: Double = 2200, seconds: Double = 1600) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["features": [["geometry": ["type": "MultiLineString", "coordinates": legs],
                                                           "properties": ["distance": distance, "time": seconds]]]])
}
private actor RoutingRequests {
    var values: [URLRequest] = []
    func append(_ request: URLRequest) { values.append(request) }
}

@Test @MainActor func geoapifyUsesWalkingCoordinatesAndHeaderAuthentication() throws {
    let request = try GeoapifyRoutingClient.request(from: .init(latitude: 6.9, longitude: 79.8), to: .init(latitude: 6.91, longitude: 79.82), avoiding: [], shortest: true, key: " synthetic-key ", now: routingNow)
    let url = try #require(request.url)
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    #expect(query.first { $0.name == "waypoints" }?.value == "6.900000,79.800000|6.910000,79.820000")
    #expect(query.first { $0.name == "mode" }?.value == "walk")
    #expect(query.first { $0.name == "type" }?.value == "short")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "synthetic-key")
    #expect(!url.absoluteString.contains("synthetic-key") && !query.contains { $0.name == "apiKey" })
}

@Test @MainActor func geoapifyAvoidanceKeepsAllAreasClosedAndWithinURLBudget() throws {
    let areas = (0..<8).map(sampleArea)
    let request = try GeoapifyRoutingClient.request(from: routingStart, to: routingEnd, avoiding: areas, shortest: false, key: "synthetic-key", now: routingNow)
    let url = try #require(request.url)
    let avoid = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "avoid" }?.value)
    let rules = avoid.components(separatedBy: "|")
    #expect(rules.count == 8 && url.absoluteString.utf8.count < 7500)
    for (rule, area) in zip(rules, areas) {
        #expect(rule.hasPrefix("polygon:"))
        let points = rule.dropFirst("polygon:".count).split(separator: ";").map { $0.split(separator: ",").map { Double($0)! } }
        #expect(points.count == 13 && points.first == points.last)
        for point in points {
            // Geoapify polygons use latitude first; the app's stored GeoJSON uses longitude first.
            let distance = try #require(NearbyRanking.distance(fromLatitude: area.latitude, fromLongitude: area.longitude, toLatitude: point[0], toLongitude: point[1]))
            #expect(distance > area.radius && distance < area.radius + 10)
        }
    }
}

@Test @MainActor func geoapifyRejectsMissingKeysInvalidLocationsAndUnusableAreas() {
    #expect(throws: GeoapifyRoutingError.missingKey) { try GeoapifyRoutingClient.request(from: routingStart, to: routingEnd, avoiding: [], shortest: false, key: " ", now: routingNow) }
    #expect(throws: GeoapifyRoutingError.options) { try GeoapifyRoutingClient.request(from: .init(latitude: 91, longitude: 0), to: routingEnd, avoiding: [], shortest: false, key: "test", now: routingNow) }
    #expect(throws: GeoapifyRoutingError.options) { try GeoapifyRoutingClient.request(from: routingStart, to: routingEnd, avoiding: (0..<9).map(sampleArea), shortest: false, key: "test", now: routingNow) }
    #expect(throws: GeoapifyRoutingError.options) { try GeoapifyRoutingClient.request(from: .init(latitude: 0, longitude: 0), to: routingEnd, avoiding: [sampleArea()], shortest: false, key: "test", now: routingNow) }
    #expect(throws: GeoapifyRoutingError.options) { try GeoapifyRoutingClient.request(from: routingStart, to: routingEnd, avoiding: [sampleArea()], shortest: false, key: "test", now: routingNow.addingTimeInterval(3601)) }
}

@Test func geoapifyJoinsConnectedLegsWithoutDuplicatingTheBoundary() throws {
    let route = try #require(GeoapifyRoutingPayload.decode(routingData([[[79.8, 6.9], [79.81, 6.91]], [[79.81, 6.91], [79.82, 6.92]]], distance: 321.5, seconds: 234)).first)
    #expect(route.coordinates == [[79.8, 6.9], [79.81, 6.91], [79.82, 6.92]])
    #expect(route.metres == 321.5 && route.seconds == 234)
}

@Test func geoapifyRejectsBrokenLegsBadCoordinatesAndInvalidMetrics() throws {
    for data in [try routingData([[[-0.01, 0], [0, 0]], [[0.005, 0], [0.01, 0]]]),
                 try routingData([[[-0.01, 0], [0.01, 91]]]), try routingData(distance: -1), try routingData(seconds: 0),
                 Data(#"{"features":[]}"#.utf8)] {
        #expect(throws: (any Error).self) { try GeoapifyRoutingPayload.decode(data) }
    }
}

@Test @MainActor func geoapifyDeduplicatesBalancedAndShortestWalkingPaths() async throws {
    let log = RoutingRequests(), data = try routingData()
    let client = GeoapifyRoutingClient(clock: { routingNow }, transport: { request in await log.append(request); return (data, 200) })
    let comparison = try await client.fetch(from: routingStart, to: routingEnd, avoiding: [], key: "test")
    #expect(comparison.routes.count == 1 && comparison.notice == nil)
    let requests = await log.values
    #expect(requests.count == 2)
    #expect(requests.map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "type" }!.value! } == ["balanced", "short"])
}

@Test @MainActor func geoapifyKeepsARealDistinctShortestOption() async throws {
    let balanced = try routingData([[[-0.01, 0], [0, 0.005], [0.01, 0]]])
    let shortest = try routingData()
    let client = GeoapifyRoutingClient(clock: { routingNow }, transport: { request in
        (request.url!.absoluteString.contains("type=short") ? shortest : balanced, 200)
    })
    let comparison = try await client.fetch(from: routingStart, to: routingEnd, avoiding: [], key: "test")
    #expect(comparison.routes.count == 2 && comparison.routes[1].shortest)
}

@Test @MainActor func geoapifyPreservesTheBaselineWhenTheSecondComparisonHitsQuota() async throws {
    let data = try routingData()
    let client = GeoapifyRoutingClient(clock: { routingNow }, transport: { request in
        (data, request.url!.absoluteString.contains("type=short") ? 429 : 200)
    })
    let comparison = try await client.fetch(from: routingStart, to: routingEnd, avoiding: [], key: "test")
    #expect(comparison.routes.count == 1 && comparison.notice?.contains("allowance") == true)
}

@Test @MainActor func geoapifyRejectsAnAvoidancePathCrossingBetweenOutsideVertices() async throws {
    let data = try routingData()
    let client = GeoapifyRoutingClient(clock: { routingNow }, transport: { _ in (data, 200) })
    await #expect(throws: GeoapifyRoutingError.areaNotAvoided) {
        try await client.fetch(from: routingStart, to: routingEnd, avoiding: [sampleArea()], key: "test")
    }
}

@Test @MainActor func geoapifyAcceptsAClearAvoidancePathWithOneRequest() async throws {
    let data = try routingData([[[-0.01, 0], [-0.01, 0.01], [0.01, 0.01], [0.01, 0]]]), log = RoutingRequests()
    let client = GeoapifyRoutingClient(clock: { routingNow }, transport: { request in await log.append(request); return (data, 200) })
    let comparison = try await client.fetch(from: routingStart, to: routingEnd, avoiding: [sampleArea()], key: "test")
    #expect(comparison.routes.count == 1 && comparison.notice == nil)
    #expect(await log.values.count == 1)
}

@Test @MainActor func geoapifyCancellationStopsTheComparison() async throws {
    let client = GeoapifyRoutingClient(clock: { routingNow }, transport: { _ in throw URLError(.cancelled) })
    await #expect(throws: CancellationError.self) { try await client.fetch(from: routingStart, to: routingEnd, avoiding: [], key: "test") }
}

@Test func savedAvoidanceAreasRoundTripAndOlderRoutesStillDecode() throws {
    var route = SavedRoute(name: "Synthetic avoidance fixture", coordinates: [routingStart, routingEnd], metres: 2200, seconds: 1600,
                           estimate: ExposureCalculator.estimate([.init(minutes: 20, pm25: 10)], ventilation: 0.015),
                           demo: false, airSamples: [], source: "Synthetic", avoidedAreaCount: 1)
    route.excludedAreas = [sampleArea()]
    let encoded = try JSONEncoder().encode(route)
    let restored = try JSONDecoder().decode(SavedRoute.self, from: encoded)
    #expect(restored.isValid && restored.excludedAreas?.first?.id == "sample-0")
    var older = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    older.removeValue(forKey: "excludedAreas")
    let historical = try JSONDecoder().decode(SavedRoute.self, from: JSONSerialization.data(withJSONObject: older))
    #expect(historical.isValid && historical.excludedAreas == nil && historical.avoidedAreaCount == 1)
}

@Test func savedAvoidanceAreasRejectMismatchedCountsAndInvalidGeometry() {
    var route = SavedRoute(name: "Synthetic avoidance fixture", coordinates: [routingStart, routingEnd], metres: 2200, seconds: 1600,
                           estimate: ExposureCalculator.estimate([], ventilation: 0.015), demo: false, airSamples: [], source: "Synthetic", avoidedAreaCount: 1)
    route.excludedAreas = [sampleArea(), sampleArea()]
    #expect(!route.isValid)
    route.excludedAreas = [.init(id: "bad", latitude: 91, longitude: 0, pm25: 20, aqi: 4, sampledAt: routingNow)]
    #expect(!route.isValid)
}
