import Foundation

public struct NearbyCandidate: Sendable {
    public let id: String
    public let latitude: Double
    public let longitude: Double

    public init(id: String, latitude: Double, longitude: Double) {
        self.id = id; self.latitude = latitude; self.longitude = longitude
    }
}

public struct NearbyMatch: Sendable {
    public let id: String
    public let metres: Double
}

/// A search region is only a provider hint. Enforce radius and ranking locally.
public enum NearbyRanking {
    public static func distance(fromLatitude: Double, fromLongitude: Double, toLatitude: Double, toLongitude: Double) -> Double? {
        guard [fromLatitude, fromLongitude, toLatitude, toLongitude].allSatisfy(\.isFinite),
              abs(fromLatitude) <= 90, abs(toLatitude) <= 90,
              abs(fromLongitude) <= 180, abs(toLongitude) <= 180 else { return nil }
        let radians = Double.pi / 180
        let latitude = (toLatitude - fromLatitude) * radians
        let longitude = (toLongitude - fromLongitude) * radians
        let a = pow(sin(latitude / 2), 2) + cos(fromLatitude * radians) * cos(toLatitude * radians) * pow(sin(longitude / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
    }

    public static func rank(_ candidates: [NearbyCandidate], latitude: Double, longitude: Double, radius: Double) -> [NearbyMatch] {
        guard radius.isFinite, radius > 0 else { return [] }
        var matches: [String: Double] = [:]
        for candidate in candidates {
            guard let metres = distance(fromLatitude: latitude, fromLongitude: longitude, toLatitude: candidate.latitude, toLongitude: candidate.longitude), metres <= radius else { continue }
            matches[candidate.id] = min(matches[candidate.id] ?? .infinity, metres)
        }
        return matches.map { NearbyMatch(id: $0.key, metres: $0.value) }.sorted {
            $0.metres == $1.metres ? $0.id < $1.id : $0.metres < $1.metres
        }
    }
}
