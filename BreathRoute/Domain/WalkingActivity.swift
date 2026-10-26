import Foundation

public enum PhoneMotionState: String, Codable, Sendable {
    case walking, stationary, other, unknown
}

public enum MotionClassification {
    /// Core Motion flags can overlap. Conflicting or low-confidence states stay unknown.
    public static func state(walking: Bool, stationary: Bool, running: Bool, cycling: Bool, automotive: Bool, unknown: Bool, confident: Bool) -> PhoneMotionState {
        guard confident, !unknown else { return .unknown }
        if automotive || cycling || running { return walking ? .unknown : .other }
        if walking && stationary { return .unknown }
        if walking { return .walking }
        if stationary { return .stationary }
        return .unknown
    }
}

public struct MotionTimeline: Sendable {
    public private(set) var state: PhoneMotionState = .unknown
    public private(set) var walkingSeconds = 0.0
    public private(set) var stationarySeconds = 0.0
    public private(set) var otherSeconds = 0.0
    public private(set) var unknownSeconds = 0.0
    private var cursor: Date
    public init(start: Date) { cursor = start }
    init(restoring summary: WalkActivitySummary, checkpointedAt checkpoint: Date, resumingAt date: Date) {
        walkingSeconds = summary.walkingSeconds; stationarySeconds = summary.stationarySeconds
        otherSeconds = summary.otherSeconds; unknownSeconds = summary.unknownSeconds + max(0, date.timeIntervalSince(checkpoint))
        cursor = date
    }
    public var elapsed: Double { walkingSeconds + stationarySeconds + otherSeconds + unknownSeconds }
    public mutating func advance(to date: Date) {
        let seconds = date.timeIntervalSince(cursor)
        guard seconds.isFinite, seconds > 0 else { return }
        switch state {
        case .walking: walkingSeconds += seconds
        case .stationary: stationarySeconds += seconds
        case .other: otherSeconds += seconds
        case .unknown: unknownSeconds += seconds
        }
        cursor = date
    }
    public mutating func setState(_ next: PhoneMotionState, at date: Date) {
        guard date >= cursor else { return }
        advance(to: date); state = next
    }
}

public enum MotionSensorStatus: String, Codable, Sendable {
    case off, waiting, available, unsupported, denied, failed, paused
}

/// Each foreground monitoring window starts at zero. Counts are never added to GPS distance.
public struct PedometerTotals: Sendable {
    public private(set) var steps: Int?
    public private(set) var metres: Double?
    public private(set) var updatedAt: Date?
    private var baseSteps = 0
    private var baseMetres = 0.0
    private var windowSteps: Int?
    private var windowMetres: Double?
    private var windowStart: Date?
    private var windowUpdatedAt: Date?
    public init() { }
    init(restoring summary: WalkActivitySummary) {
        steps = summary.steps; metres = summary.pedometerMetres; updatedAt = summary.stepsUpdatedAt
        baseSteps = summary.steps ?? 0; baseMetres = summary.pedometerMetres ?? 0
    }
    public mutating func beginWindow(at date: Date) {
        endWindow(); windowStart = date
    }
    @discardableResult public mutating func accept(steps count: Int, metres distance: Double?, at date: Date) -> Bool {
        guard let windowStart, date >= windowStart, count >= 0,
              windowUpdatedAt.map({ date >= $0 }) ?? true,
              windowSteps.map({ count >= $0 }) ?? true,
              count <= Int.max - baseSteps else { return false }
        windowSteps = count; steps = baseSteps + count
        if let distance, distance.isFinite, distance >= 0,
           windowMetres.map({ distance >= $0 }) ?? true, (baseMetres + distance).isFinite {
            windowMetres = distance; metres = baseMetres + distance
        }
        windowUpdatedAt = date; updatedAt = date
        return true
    }
    public mutating func endWindow() {
        if let windowSteps { baseSteps += windowSteps }
        if let windowMetres { baseMetres += windowMetres }
        windowSteps = nil; windowMetres = nil; windowStart = nil; windowUpdatedAt = nil
    }
}

public struct WalkActivitySummary: Codable, Sendable {
    public let steps: Int?
    public let pedometerMetres: Double?
    public let walkingSeconds: Double
    public let stationarySeconds: Double
    public let otherSeconds: Double
    public let unknownSeconds: Double
    public let stepStatus: MotionSensorStatus
    public let classificationStatus: MotionSensorStatus
    public let stepsUpdatedAt: Date?
    public var elapsed: Double { walkingSeconds + stationarySeconds + otherSeconds + unknownSeconds }
    public var classifiedFraction: Double { elapsed > 0 ? (walkingSeconds + stationarySeconds + otherSeconds) / elapsed : 0 }
    var isValid: Bool {
        elapsed.isFinite && [walkingSeconds, stationarySeconds, otherSeconds, unknownSeconds].allSatisfy { $0.isFinite && $0 >= 0 } &&
        (steps.map { $0 >= 0 } ?? true) && (pedometerMetres.map { $0.isFinite && $0 >= 0 } ?? true)
    }
    public init(steps: Int?, pedometerMetres: Double?, timeline: MotionTimeline, stepStatus: MotionSensorStatus, classificationStatus: MotionSensorStatus, stepsUpdatedAt: Date?) {
        self.steps = steps; self.pedometerMetres = pedometerMetres
        walkingSeconds = timeline.walkingSeconds; stationarySeconds = timeline.stationarySeconds
        otherSeconds = timeline.otherSeconds; unknownSeconds = timeline.unknownSeconds
        self.stepStatus = stepStatus; self.classificationStatus = classificationStatus; self.stepsUpdatedAt = stepsUpdatedAt
    }
}
