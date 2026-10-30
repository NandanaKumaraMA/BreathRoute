import Foundation

/// Requires sustained, accurate fixes outside the path before requesting another route.
struct RouteDeviationMonitor {
    private var firstOutside: Date?
    private var lastFix: Date?
    private var count = 0
    mutating func update(coordinate: GeoCoordinate, accuracy: Double, date: Date, now: Date, path: [GeoCoordinate]) -> Bool {
        guard coordinate.isValid, accuracy.isFinite, (0...50).contains(accuracy),
              abs(date.timeIntervalSince(now)) <= 15, lastFix.map({ date > $0 }) ?? true,
              path.count >= 2, path.allSatisfy(\.isValid) else { return false }
        if lastFix.map({ date.timeIntervalSince($0) > 30 }) ?? false { firstOutside = nil; count = 0 }
        lastFix = date
        let radius = max(60, accuracy * 2)
        let circle = WatchArea(id: "distance", latitude: coordinate.latitude, longitude: coordinate.longitude,
                               radius: radius, pm25: 0, aqi: 3, sampledAt: date)
        guard !circle.intersects(path.map { [$0.longitude, $0.latitude] }) else {
            firstOutside = nil; count = 0; return false
        }
        if firstOutside == nil { firstOutside = date }
        count += 1
        return count >= 3 && date.timeIntervalSince(firstOutside!) >= 8
    }
}

struct AutomaticRerouteGate {
    private var lastRequest: Date?
    mutating func accept(now: Date) -> Bool {
        guard lastRequest.map({ now.timeIntervalSince($0) >= 120 }) ?? true else { return false }
        lastRequest = now; return true
    }
}
