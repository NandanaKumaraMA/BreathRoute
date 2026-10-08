import Foundation

public struct RouteChoice: Sendable {
    public let id: String
    public let seconds: Double
    public let dose: Double?
    public let complete: Bool
    public init(id: String, seconds: Double, dose: Double?, complete: Bool) {
        self.id = id; self.seconds = seconds; self.dose = dose; self.complete = complete
    }
}
public enum RouteChoicePolicy {
    public static func recommended(_ choices: [RouteChoice], extraMinutes: Double) -> String? {
        guard extraMinutes.isFinite, extraMinutes >= 0,
              choices.allSatisfy({ $0.seconds.isFinite && $0.seconds > 0 }),
              let fastest = choices.map(\.seconds).min() else { return nil }
        let eligible = choices.filter { $0.seconds <= fastest + extraMinutes * 60 }
        guard eligible.count >= 2,
              eligible.allSatisfy({ $0.complete && $0.dose.map { $0.isFinite && $0 >= 0 } == true }) else { return nil }
        let sorted = eligible.sorted { $0.dose! == $1.dose! ? $0.id < $1.id : $0.dose! < $1.dose! }
        guard sorted[1].dose! - sorted[0].dose! > max(0.1, sorted[1].dose! * 0.01) else { return nil }
        return sorted[0].id
    }
}
