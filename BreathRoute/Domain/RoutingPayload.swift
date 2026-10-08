import Foundation

public struct ProviderRoute: Sendable {
    public let coordinates: [[Double]]
    public let metres: Double
    public let seconds: Double
}
public enum RoutingPayload {
    public static func decode(_ data: Data) throws -> [ProviderRoute] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let routes = response.features.compactMap { feature -> ProviderRoute? in
            let points = feature.geometry.coordinates, summary = feature.properties.summary
            guard feature.geometry.type == "LineString", points.count >= 2,
                  summary.distance.isFinite, summary.distance > 0, summary.duration.isFinite, summary.duration > 0,
                  points.allSatisfy({ $0.count >= 2 && NearbyRanking.distance(fromLatitude: $0[1], fromLongitude: $0[0], toLatitude: $0[1], toLongitude: $0[0]) != nil }) else { return nil }
            return ProviderRoute(coordinates: points, metres: summary.distance, seconds: summary.duration)
        }
        guard !routes.isEmpty else { throw CocoaError(.coderReadCorrupt) }
        return Array(routes.prefix(3))
    }
    private struct Response: Decodable {
        let features: [Feature]
        struct Feature: Decodable {
            let geometry: Geometry; let properties: Properties
            struct Geometry: Decodable { let type: String; let coordinates: [[Double]] }
            struct Properties: Decodable {
                let summary: Summary
                struct Summary: Decodable { let distance: Double; let duration: Double }
            }
        }
    }
}
