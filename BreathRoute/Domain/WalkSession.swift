import Foundation

struct AirReading: Codable, Sendable {
    let pm25: Double
    let aqi: Int
    let date: Date
    let demo: Bool
    var label: String { [1: "Good", 2: "Fair", 3: "Moderate", 4: "Poor", 5: "Very poor"][aqi] ?? "Unavailable" }
    var isFresh: Bool { Date().timeIntervalSince(date) < 3600 && date.timeIntervalSinceNow < 300 }
}

struct GeoCoordinate: Codable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

struct RecordedPathPoint: Codable, Sendable {
    let coordinate: GeoCoordinate
    let date: Date
    let accuracy: Double
    let startsNewLeg: Bool
}

enum FixRecordingResult { case started, recorded, gap, ignored }

/// A gap starts a new line, so the map never draws travel across an unobserved interval.
struct WalkRecorder: Codable, Sendable {
    private(set) var path: [RecordedPathPoint] = []
    private(set) var metres = 0.0
    private(set) var recordedSeconds = 0.0
    private(set) var segments: [ExposureSegment] = []
    private(set) var previous: RecordedPathPoint?
    mutating func breakPath() { previous = nil }
    @discardableResult mutating func record(coordinate: GeoCoordinate, date: Date, accuracy: Double, metresFromPrevious: Double?, pm25: Double?) -> FixRecordingResult {
        guard coordinate.isValid, date.timeIntervalSince1970.isFinite, accuracy.isFinite, (0...100).contains(accuracy),
              path.last.map({ date > $0.date }) ?? true else { return .ignored }
        let duration = previous.map { date.timeIntervalSince($0.date) }
        let accepted = duration.map { seconds in
            seconds > 0 && seconds <= 30 && metresFromPrevious.map { $0.isFinite && $0 >= 0 && $0 / seconds < 4 } == true
        } ?? false
        let point = RecordedPathPoint(coordinate: coordinate, date: date, accuracy: accuracy, startsNewLeg: !accepted)
        let wasStarting = previous == nil
        path.append(point); previous = point
        guard accepted, let duration, let metresFromPrevious else { return wasStarting ? .started : .gap }
        metres += metresFromPrevious; recordedSeconds += duration
        let usable = pm25.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        segments.append(ExposureSegment(minutes: duration / 60, pm25: usable))
        return .recorded
    }
    var isValid: Bool {
        guard metres.isFinite, metres >= 0, recordedSeconds.isFinite, recordedSeconds >= 0,
              path.allSatisfy({ $0.coordinate.isValid && $0.date.timeIntervalSince1970.isFinite && $0.accuracy.isFinite && (0...100).contains($0.accuracy) }),
              zip(path, path.dropFirst()).allSatisfy({ $0.date < $1.date }),
              segments.allSatisfy({ $0.minutes.isFinite && $0.minutes > 0 && ($0.pm25.map { $0.isFinite && $0 >= 0 } ?? true) }) else { return false }
        let intervalTotal = segments.reduce(0) { $0 + $1.minutes * 60 }
        let linked = path.dropFirst().filter { !$0.startsNewLeg }
        let pathSeconds = zip(path, path.dropFirst()).reduce(0.0) { $0 + ($1.1.startsNewLeg ? 0 : $1.1.date.timeIntervalSince($1.0.date)) }
        return (path.first?.startsNewLeg ?? true) && linked.count == segments.count &&
            abs(intervalTotal - recordedSeconds) < 0.001 && abs(pathSeconds - recordedSeconds) < 0.001 &&
            (recordedSeconds > 0 ? metres < recordedSeconds * 4 : metres == 0) &&
            (previous == nil || (previous?.date == path.last?.date && previous?.coordinate == path.last?.coordinate))
    }
}

struct SavedAirSample: Codable, Sendable {
    let coordinate: GeoCoordinate
    let reading: AirReading?
    let timeFraction: Double
}

struct SavedRoute: Codable, Sendable {
    let name: String
    let coordinates: [GeoCoordinate]
    let metres: Double
    let seconds: Double
    let estimate: ExposureEstimate
    let demo: Bool
    let airSamples: [SavedAirSample]
    let source: String
    let avoidedAreaCount: Int
    var isValid: Bool {
        coordinates.count >= 2 && coordinates.allSatisfy(\.isValid) && metres.isFinite && metres >= 0 && seconds.isFinite && seconds > 0 &&
        estimate.coverage.isFinite && (0...1).contains(estimate.coverage) && (estimate.observedDose.map { $0.isFinite && $0 >= 0 } ?? true) &&
        airSamples.allSatisfy { $0.coordinate.isValid && $0.timeFraction.isFinite && (0...1).contains($0.timeFraction) &&
            ($0.reading.map { $0.pm25.isFinite && $0.pm25 >= 0 && (1...5).contains($0.aqi) && $0.date.timeIntervalSince1970.isFinite } ?? true) }
    }
}

struct ActiveWalkCheckpoint: Codable, Sendable {
    static let storageID = UUID(uuidString: "BCBC34D6-B37A-4E08-A9E8-D543A6F07594")!
    var version = 1
    let sessionID: UUID
    let startedAt: Date
    let savedAt: Date
    let destination: String
    let route: SavedRoute
    let recorder: WalkRecorder
    let ventilation: Double
    let activity: WalkActivitySummary?
    let recovered: Bool
    var isValid: Bool {
        version == 1 && sessionID != Self.storageID && startedAt.timeIntervalSince1970.isFinite && savedAt.timeIntervalSince1970.isFinite && savedAt >= startedAt &&
        ventilation.isFinite && ventilation > 0 && route.isValid && recorder.isValid &&
        recorder.recordedSeconds <= savedAt.timeIntervalSince(startedAt) + 0.001 &&
        recorder.path.allSatisfy { $0.date >= startedAt && $0.date <= savedAt } &&
        (activity.map { $0.isValid && $0.elapsed <= savedAt.timeIntervalSince(startedAt) + 1 } ?? true)
    }
    func trip(endedAt date: Date, activity latestActivity: WalkActivitySummary? = nil) -> TripEntry {
        let elapsed = max(0, date.timeIntervalSince(startedAt))
        let estimate = ExposureCalculator.estimate(recorder.segments, ventilation: ventilation)
        let coverage = elapsed > 0 ? min(1, estimate.coverage * recorder.recordedSeconds / elapsed) : 0
        return TripEntry(id: sessionID, date: startedAt, destination: route.demo ? "Demo · \(route.name)" : destination,
                         metres: recorder.metres, seconds: elapsed, dose: estimate.observedDose,
                         coverage: coverage, demo: route.demo, complete: coverage >= 0.999999,
                         activity: route.demo ? nil : (latestActivity ?? activity), recordedPath: recorder.path,
                         plannedPath: route.coordinates, routeSource: route.source, ventilation: ventilation,
                         recovered: recovered, lastRecordedAt: recorder.path.last?.date)
    }
}
