import Foundation
import Testing
@testable import BreatheRouteCore

@Test func routeDecoderKeepsGeoJSONOrderAndMetricUnits() throws {
    let data = Data(#"{"features":[{"geometry":{"type":"LineString","coordinates":[[79.864,6.9147],[79.865,6.916]]},"properties":{"summary":{"distance":234.5,"duration":180}}}]}"#.utf8)
    let route = try #require(RoutingPayload.decode(data).first)
    #expect(route.coordinates[0] == [79.864, 6.9147])
    #expect(route.metres == 234.5 && route.seconds == 180)
}
@Test func routeDecoderRejectsInvalidGeometryAndDurations() {
    for invalid in [#"{"features":[]}"#, #"{"features":[{"geometry":{"type":"LineString","coordinates":[[79.8,6.9],[79.8,96]]},"properties":{"summary":{"distance":100,"duration":180}}}]}"#, #"{"features":[{"geometry":{"type":"LineString","coordinates":[[79.8,6.9],[79.9,6.9]]},"properties":{"summary":{"distance":100,"duration":0}}}]}"#] {
        #expect(throws: (any Error).self) { try RoutingPayload.decode(Data(invalid.utf8)) }
    }
}
