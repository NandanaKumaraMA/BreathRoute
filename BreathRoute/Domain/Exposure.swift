import Foundation

/// Units: concentration µg/m³, ventilation m³/min, duration minutes, dose µg.
/// Missing or invalid samples never become zero-exposure observations.
public struct ExposureSegment: Sendable {
    public let minutes: Double
    public let pm25: Double?
    public init(minutes: Double, pm25: Double?) { self.minutes = minutes; self.pm25 = pm25 }
}

public struct ExposureEstimate: Sendable {
    public let observedDose: Double?
    public let coverage: Double
    public var isComplete: Bool { coverage >= 0.999999 }
}

public enum ExposureCalculator {
    public static func estimate(_ segments: [ExposureSegment], ventilation: Double) -> ExposureEstimate {
        guard ventilation.isFinite, ventilation > 0 else {
            return ExposureEstimate(observedDose: nil, coverage: 0)
        }
        var total = 0.0, covered = 0.0, dose = 0.0
        for segment in segments where segment.minutes.isFinite && segment.minutes > 0 {
            total += segment.minutes
            if let value = segment.pm25, value.isFinite, value >= 0 {
                covered += segment.minutes
                dose += value * ventilation * segment.minutes
            }
        }
        return ExposureEstimate(observedDose: covered > 0 ? dose : nil,
                                coverage: total > 0 ? covered / total : 0)
    }
}
