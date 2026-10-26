import Foundation
import Observation
import CoreMotion

@MainActor @Observable
final class MotionService {
    private let pedometer = CMPedometer()
    private let activityManager = CMMotionActivityManager()
    private var timeline: MotionTimeline?
    private var totals = PedometerTotals()
    private var sessionOpen = false
    private var enabled = false
    private var foreground = true
    private var monitoring = false
    private var pedometerStarted = false
    private var classifierStarted = false
    private var generation = 0
    @ObservationIgnored private var timer: Timer?
    private(set) var stepStatus: MotionSensorStatus = .off
    private(set) var classificationStatus: MotionSensorStatus = .off
    private(set) var cadencePerMinute: Double?
    private(set) var paceMinutesPerKilometre: Double?
    private var paceUpdatedAt: Date?
    var stepsSupported: Bool { CMPedometer.isStepCountingAvailable() }
    var classificationSupported: Bool { CMMotionActivityManager.isActivityAvailable() }
    var state: PhoneMotionState { timeline?.state ?? .unknown }
    var currentCadence: Double? { freshPace ? cadencePerMinute : nil }
    var currentPace: Double? { freshPace ? paceMinutesPerKilometre : nil }
    private var freshPace: Bool { monitoring && paceUpdatedAt.map { Date().timeIntervalSince($0) < 30 } == true }
    var availabilityDescription: String {
        if !stepsSupported && !classificationSupported { return "Motion sensors are unavailable here. GPS, routing and your journal still work. Sensor behaviour needs a supported physical iPhone." }
        return "Uses the phone you carry. Steps \(stepsSupported ? "supported" : "unavailable"); activity classification \(classificationSupported ? "supported" : "unavailable"). No Apple Watch is required."
    }
    var summary: WalkActivitySummary? {
        guard let timeline else { return nil }
        return WalkActivitySummary(steps: totals.steps, pedometerMetres: totals.metres, timeline: timeline, stepStatus: stepStatus, classificationStatus: classificationStatus, stepsUpdatedAt: totals.updatedAt)
    }
    func beginSession(at date: Date, enabled: Bool, foreground: Bool, restoring summary: WalkActivitySummary? = nil, checkpointedAt checkpoint: Date? = nil) {
        endSession()
        if let summary, let checkpoint {
            timeline = MotionTimeline(restoring: summary, checkpointedAt: checkpoint, resumingAt: Date())
            totals = PedometerTotals(restoring: summary)
        } else { timeline = MotionTimeline(start: date); totals = PedometerTotals() }
        sessionOpen = true; self.enabled = enabled; self.foreground = foreground
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        if enabled && foreground { startMonitoring() }
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        guard sessionOpen else { return }
        if value && foreground { startMonitoring() }
        else { stopMonitoring(status: value ? .paused : .off) }
    }
    func setForeground(_ value: Bool) {
        foreground = value
        guard sessionOpen else { return }
        if value && enabled { startMonitoring() }
        else { stopMonitoring(status: enabled ? .paused : .off) }
    }
    func summary(at date: Date) -> WalkActivitySummary? {
        timeline?.advance(to: date); return summary
    }
    func endSession() {
        stopMonitoring(status: .off)
        timer?.invalidate(); timer = nil; sessionOpen = false; timeline = nil
    }
    private func startMonitoring() {
        guard sessionOpen, enabled, foreground, !monitoring else { return }
        monitoring = true; generation += 1; let ticket = generation
        let start = Date(); totals.beginWindow(at: start)
        timeline?.setState(.unknown, at: start)
        stepStatus = stepsSupported ? (Self.denied(CMPedometer.authorizationStatus()) ? .denied : .waiting) : .unsupported
        classificationStatus = classificationSupported ? (Self.denied(CMMotionActivityManager.authorizationStatus()) ? .denied : .waiting) : .unsupported
        if stepStatus == .waiting {
            pedometerStarted = true
            pedometer.startUpdates(from: start) { [weak self] data, error in
                // Copy the framework values before crossing into the main actor.
                let count = data?.numberOfSteps.intValue, metres = data?.distance?.doubleValue
                let date = data?.endDate, cadence = data?.currentCadence?.doubleValue, pace = data?.currentPace?.doubleValue
                let failed = error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.monitoring, self.generation == ticket else { return }
                    if failed {
                        self.stepStatus = Self.denied(CMPedometer.authorizationStatus()) ? .denied : .failed
                        self.cadencePerMinute = nil; self.paceMinutesPerKilometre = nil
                        return
                    }
                    guard let count, let date, date.timeIntervalSinceNow <= 5,
                          self.totals.accept(steps: count, metres: metres, at: date) else { return }
                    self.stepStatus = .available; self.paceUpdatedAt = date
                    self.cadencePerMinute = cadence.flatMap { $0.isFinite && $0 >= 0 && ($0 * 60).isFinite ? $0 * 60 : nil }
                    self.paceMinutesPerKilometre = pace.flatMap { $0.isFinite && $0 > 0 && ($0 * 1000 / 60).isFinite ? $0 * 1000 / 60 : nil }
                }
            }
        }
        if classificationStatus == .waiting {
            classifierStarted = true
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                let hasActivity = activity != nil
                let next = activity.map {
                    MotionClassification.state(walking: $0.walking, stationary: $0.stationary, running: $0.running,
                        cycling: $0.cycling, automotive: $0.automotive, unknown: $0.unknown, confident: $0.confidence != .low)
                } ?? .unknown
                Task { @MainActor [weak self] in
                    guard let self, self.monitoring, self.generation == ticket else { return }
                    self.classificationStatus = Self.denied(CMMotionActivityManager.authorizationStatus()) ? .denied : (hasActivity ? .available : .waiting)
                    self.timeline?.setState(self.classificationStatus == .denied ? .unknown : next, at: Date())
                }
            }
        }
    }
    private func stopMonitoring(status: MotionSensorStatus) {
        generation += 1; monitoring = false
        if pedometerStarted { pedometer.stopUpdates(); pedometerStarted = false }
        if classifierStarted { activityManager.stopActivityUpdates(); classifierStarted = false }
        totals.endWindow(); timeline?.setState(.unknown, at: Date())
        cadencePerMinute = nil; paceMinutesPerKilometre = nil; paceUpdatedAt = nil
        if stepStatus != .unsupported && stepStatus != .denied && stepStatus != .failed { stepStatus = status }
        if classificationStatus != .unsupported && classificationStatus != .denied && classificationStatus != .failed { classificationStatus = status }
    }
    private func tick() {
        guard sessionOpen else { return }
        timeline?.advance(to: Date())
        if monitoring {
            if stepsSupported && Self.denied(CMPedometer.authorizationStatus()) { stepStatus = .denied; cadencePerMinute = nil; paceMinutesPerKilometre = nil }
            if classificationSupported && Self.denied(CMMotionActivityManager.authorizationStatus()) {
                classificationStatus = .denied; timeline?.setState(.unknown, at: Date())
            }
        }
    }
    private static func denied(_ status: CMAuthorizationStatus) -> Bool { status == .denied || status == .restricted }
}
