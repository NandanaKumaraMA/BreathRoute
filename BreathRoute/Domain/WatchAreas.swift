import Foundation

public struct WatchArea: Identifiable, Sendable {
    public let id: String
    public let latitude: Double
    public let longitude: Double
    public let radius: Double
    public let pm25: Double
    public let aqi: Int
    public let sampledAt: Date
    public init(id: String, latitude: Double, longitude: Double, radius: Double = 250, pm25: Double, aqi: Int, sampledAt: Date) {
        self.id = id; self.latitude = latitude; self.longitude = longitude; self.radius = radius
        self.pm25 = pm25; self.aqi = aqi; self.sampledAt = sampledAt
    }
    public func isUsable(at now: Date) -> Bool {
        NearbyRanking.distance(fromLatitude: latitude, fromLongitude: longitude, toLatitude: latitude, toLongitude: longitude) != nil
        && radius.isFinite && radius > 0 && radius <= 1000 && pm25.isFinite && pm25 >= 0 && (3...5).contains(aqi)
        && now.timeIntervalSince(sampledAt) < 3600 && sampledAt.timeIntervalSince(now) <= 300
    }
    public func contains(latitude: Double, longitude: Double) -> Bool {
        guard let distance = NearbyRanking.distance(fromLatitude: self.latitude, fromLongitude: self.longitude, toLatitude: latitude, toLongitude: longitude) else { return false }
        return distance <= radius
    }
    /// A closed, circumscribed GeoJSON [longitude, latitude] polygon around the display circle.
    public func polygon() -> [[Double]] {
        let count = 36, radians = Double.pi / 180
        let angular = radius / cos(.pi / Double(count)) / 6_371_000
        let lat = latitude * radians, lon = longitude * radians
        let ring = (0..<count).map { i -> [Double] in
            let bearing = 2 * Double.pi * Double(i) / Double(count)
            let resultLat = asin(sin(lat) * cos(angular) + cos(lat) * sin(angular) * cos(bearing))
            let resultLon = lon + atan2(sin(bearing) * sin(angular) * cos(lat), cos(angular) - sin(lat) * sin(resultLat))
            return [((resultLon / radians + 540).truncatingRemainder(dividingBy: 360)) - 180, resultLat / radians]
        }
        return ring + [ring[0]]
    }
    /// Conservative local projection for small walking-area circles; checks segments, not just vertices.
    public func intersects(_ coordinates: [[Double]]) -> Bool {
        guard coordinates.count > 1 else { return coordinates.first.map { $0.count >= 2 && contains(latitude: $0[1], longitude: $0[0]) } ?? false }
        let factor = Double.pi / 180 * 6_371_000
        func point(_ coordinate: [Double]) -> (Double, Double)? {
            guard coordinate.count >= 2,
                  NearbyRanking.distance(fromLatitude: latitude, fromLongitude: longitude, toLatitude: coordinate[1], toLongitude: coordinate[0]) != nil else { return nil }
            let delta = ((coordinate[0] - longitude + 540).truncatingRemainder(dividingBy: 360)) - 180
            return (delta * factor * cos(latitude * .pi / 180), (coordinate[1] - latitude) * factor)
        }
        for index in 1..<coordinates.count {
            guard let a = point(coordinates[index - 1]), let b = point(coordinates[index]) else { return true }
            let dx = b.0 - a.0, dy = b.1 - a.1, length = dx * dx + dy * dy
            let t = length > 0 ? min(1, max(0, -(a.0 * dx + a.1 * dy) / length)) : 0
            if hypot(a.0 + t * dx, a.1 + t * dy) <= radius + 2 { return true }
        }
        return false
    }
}

public enum WatchAreaPolicy {
    public static func select(_ samples: [WatchArea], now: Date, limit: Int = 8) -> [WatchArea] {
        var result: [WatchArea] = []
        for sample in samples.filter({ $0.isUsable(at: now) }).sorted(by: { $0.aqi == $1.aqi ? $0.id < $1.id : $0.aqi > $1.aqi }) {
            guard result.count < max(0, min(8, limit)) else { break }
            if !result.contains(where: {
                $0.id == sample.id || (NearbyRanking.distance(fromLatitude: $0.latitude, fromLongitude: $0.longitude, toLatitude: sample.latitude, toLongitude: sample.longitude) ?? .infinity) < max($0.radius, sample.radius)
            }) { result.append(sample) }
        }
        return result
    }
}

public struct AreaEntryGate: Sendable {
    private var inside = Set<String>()
    private var lastAlert: Date?
    public init() { }
    public mutating func update(areas: [WatchArea], latitude: Double, longitude: Double, accuracy: Double, now: Date) -> WatchArea? {
        guard accuracy.isFinite, accuracy >= 0, accuracy <= 100 else { return nil }
        let usable = areas.filter { $0.isUsable(at: now) }
        // Require the accuracy circle to be fully inside to reduce uncertain boundary alerts.
        let entered = usable.filter { area in
            guard let distance = NearbyRanking.distance(fromLatitude: latitude, fromLongitude: longitude, toLatitude: area.latitude, toLongitude: area.longitude) else { return false }
            return distance + accuracy <= area.radius
        }
        let ids = Set(entered.map(\.id))
        let newlyEntered = entered.first { !inside.contains($0.id) }
        inside = ids
        guard let newlyEntered, lastAlert.map({ now.timeIntervalSince($0) >= 300 }) ?? true else { return nil }
        lastAlert = now; return newlyEntered
    }
}
