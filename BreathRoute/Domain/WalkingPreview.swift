import Foundation

enum WalkPreviewState: String, Sendable { case paused, playing, completed }
enum WalkPreviewError: Error { case invalidPath }

/// Explicit synthetic playback. Progress is kept when paused; no HealthKit samples are created.
struct WalkingPreviewPlayback: Sendable {
    let coordinates: [GeoCoordinate]
    private let cumulative: [Double]
    let totalMetres: Double
    let speed: Double
    private(set) var metres: Double
    private(set) var movingSeconds: Double
    private(set) var state: WalkPreviewState = .paused

    init(coordinates: [GeoCoordinate], speed: Double, startingMetres: Double = 0, movingSeconds: Double = 0) throws {
        guard coordinates.count >= 2, coordinates.allSatisfy(\.isValid), speed.isFinite, (0.3...3.5).contains(speed),
              startingMetres.isFinite, startingMetres >= 0, movingSeconds.isFinite, movingSeconds >= 0 else { throw WalkPreviewError.invalidPath }
        var lengths = [0.0]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            guard let distance = NearbyRanking.distance(fromLatitude: a.latitude, fromLongitude: a.longitude, toLatitude: b.latitude, toLongitude: b.longitude) else { throw WalkPreviewError.invalidPath }
            lengths.append(lengths.last! + distance)
        }
        guard let total = lengths.last, total > 0, total <= 1_000_000 else { throw WalkPreviewError.invalidPath }
        self.coordinates = coordinates; cumulative = lengths; totalMetres = total; self.speed = speed
        metres = min(startingMetres, total); self.movingSeconds = movingSeconds
        if metres == total { state = .completed }
    }
    mutating func play() { if metres < totalMetres { state = .playing } }
    mutating func pause() { if state == .playing { state = .paused } }
    mutating func advance(seconds: Double) {
        guard state == .playing, seconds.isFinite, seconds > 0 else { return }
        let accepted = min(seconds, (totalMetres - metres) / speed)
        movingSeconds += accepted; metres = min(totalMetres, metres + accepted * speed)
        if totalMetres - metres < 0.00001 { metres = totalMetres; state = .completed }
    }
    var coordinate: GeoCoordinate {
        if metres <= 0 { return coordinates[0] }
        guard metres < totalMetres else { return coordinates.last! }
        let upper = cumulative.firstIndex { $0 > metres } ?? (coordinates.count - 1)
        let lower = max(0, upper - 1), length = cumulative[upper] - cumulative[lower]
        let t = length > 0 ? (metres - cumulative[lower]) / length : 0
        let a = coordinates[lower], b = coordinates[upper]
        let delta = ((b.longitude - a.longitude + 540).truncatingRemainder(dividingBy: 360)) - 180
        let longitude = delta == 0 ? a.longitude : ((a.longitude + delta * t + 540).truncatingRemainder(dividingBy: 360)) - 180
        return GeoCoordinate(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: longitude)
    }
    var nextCoordinate: GeoCoordinate {
        let upper = cumulative.firstIndex { $0 > metres + 0.01 } ?? (coordinates.count - 1)
        return coordinates[upper]
    }
    /// Fixed fictional fixtures for demonstrating the UI, not physiological predictions.
    var exampleMetrics: WalkPreviewMetrics {
        WalkPreviewMetrics(steps: Int(metres / 0.75), heartRate: 96 + (Int(movingSeconds / 10) % 5) * 2,
                           respiratoryRate: 18 + (Int(movingSeconds / 15) % 3))
    }
}
struct WalkPreviewMetrics: Equatable, Sendable {
    let steps: Int
    let heartRate: Int
    let respiratoryRate: Int
}

/// Used only when a location fix supplies no usable speed. Reject jumps and old/noisy pairs.
enum GPSWalkingSpeed {
    static func estimate(metres: Double, seconds: Double, previousAccuracy: Double, accuracy: Double) -> Double? {
        guard metres.isFinite, seconds.isFinite, previousAccuracy.isFinite, accuracy.isFinite,
              (0...100).contains(previousAccuracy), (0...100).contains(accuracy),
              (0.5...15).contains(seconds), metres >= max(1.5, min(previousAccuracy, accuracy) * 0.2) else { return nil }
        let speed = metres / seconds
        return (0.3..<4).contains(speed) ? speed : nil
    }
}
