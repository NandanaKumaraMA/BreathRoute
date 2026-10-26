import SwiftUI

extension MotionSensorStatus {
    var title: String {
        switch self {
        case .off: "Off"
        case .waiting: "Waiting for permission or data"
        case .available: "Receiving data"
        case .unsupported: "Unavailable on this device"
        case .denied: "Access unavailable · check Settings"
        case .failed: "Update failed · toggle off/on to retry"
        case .paused: "Paused outside the app"
        }
    }
}
extension PhoneMotionState {
    var title: String {
        switch self { case .walking: "Walking detected"; case .stationary: "Stationary detected"; case .other: "Other motion detected"; case .unknown: "Motion unclassified" }
    }
    var symbol: String {
        switch self { case .walking: "figure.walk"; case .stationary: "pause.circle"; case .other: "arrow.triangle.swap"; case .unknown: "questionmark.circle" }
    }
}
private func activityTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0, seconds < 2_000_000_000 else { return "Unavailable" }
    return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
}

struct MotionSettingsCard: View {
    @Bindable var model: AppModel
    @State private var preview = false
    var body: some View {
        Surface {
            Label("iPhone motion", systemImage: "iphone.gen3.radiowaves.left.and.right").font(.headline).foregroundStyle(Palette.ink)
            Toggle("Track steps during walks", isOn: Binding(get: { model.motionTrackingEnabled }, set: { model.setMotionTracking($0) })).font(.subheadline)
            Text(model.motion.availabilityDescription).font(.caption).foregroundStyle(Palette.muted)
            Text("Optional Motion & Fitness access is requested when a real walk starts. Carry your phone. Only monitored foreground portions are included; missed updates can undercount steps.").font(.caption).foregroundStyle(Palette.muted)
            Button("Preview motion metrics", systemImage: "play.circle") { preview = true }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }.sheet(isPresented: $preview) { MotionPreviewView() }
    }
}

struct ActiveMotionCard: View {
    @Bindable var model: AppModel
    let demo: Bool
    @State private var preview = false
    var body: some View {
        Surface {
            SectionHeading(title: "Movement, from your iPhone")
            if demo {
                StatusPill(title: "Demo · no actual motion recorded", symbol: "sparkles")
                Text("Example walks do not read your motion sensors. Try the isolated preview or start a real walk to record available steps.").font(.caption).foregroundStyle(Palette.muted)
            } else {
                StatusPill(title: model.motion.state.title, symbol: model.motion.state.symbol)
                Toggle("Track steps during this walk", isOn: Binding(get: { model.motionTrackingEnabled }, set: { model.setMotionTracking($0) })).font(.subheadline)
                if let summary = model.motion.summary {
                    ActivityMetrics(summary: summary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], spacing: 18) {
                        Metric(title: "Current cadence", value: model.motion.currentCadence.map { String(format: "%.0f steps/min", $0) } ?? "Unavailable")
                        Metric(title: "Current active pace", value: model.motion.currentPace.map { String(format: "%.1f min/km", $0) } ?? "Unavailable")
                    }
                    Text("Steps: \(summary.stepStatus.title). Classification: \(summary.classificationStatus.title).").font(.caption).foregroundStyle(Palette.muted)
                    if let date = summary.stepsUpdatedAt { Text("Steps reported through \(date.formatted(date: .omitted, time: .standard)).").font(.caption2).foregroundStyle(Palette.muted) }
                }
                if !model.motion.stepsSupported || !model.motion.classificationSupported { Text(model.motion.availabilityDescription).font(.caption).foregroundStyle(Palette.muted) }
                InfoNote(text: "Motion context is separate from GPS and pollution. Low-confidence/conflicting motion and unmonitored time stay unclassified. Stationary time is not zero exposure.")
            }
            Button("Preview motion metrics", systemImage: "play.circle") { preview = true }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }.sheet(isPresented: $preview) { MotionPreviewView() }
    }
}

struct ActivityMetrics: View {
    let summary: WalkActivitySummary
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)] : [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 18) {
            Metric(title: "Reported session steps", value: summary.steps.map { $0.formatted() } ?? "Unavailable")
            Metric(title: "Pedometer estimate", value: summary.pedometerMetres.map { String(format: "%.0f m", $0) } ?? "Unavailable")
            Metric(title: "Classified walking · m:ss", value: activityTime(summary.walkingSeconds))
            Metric(title: "Classified stationary · m:ss", value: activityTime(summary.stationarySeconds))
            Metric(title: "Other motion · m:ss", value: activityTime(summary.otherSeconds))
            Metric(title: "Unclassified elapsed · m:ss", value: activityTime(summary.unknownSeconds))
        }
    }
}

struct SavedActivityCard: View {
    let summary: WalkActivitySummary
    var body: some View {
        Surface {
            SectionHeading(title: "Recorded phone activity")
            ActivityMetrics(summary: summary)
            Text("\(Int(summary.classifiedFraction * 100))% of elapsed time classified. Steps: \(summary.stepStatus.title).").font(.caption).foregroundStyle(Palette.muted)
            if let date = summary.stepsUpdatedAt { Text("Last step sample: \(date.formatted(date: .abbreviated, time: .standard)).").font(.caption2).foregroundStyle(Palette.muted) }
            InfoNote(text: "Source: iPhone Core Motion, monitored foreground portions only. Pedometer distance is a separate estimate and is never added to GPS distance. Sensor gaps may undercount activity; motion does not measure breathing or change the exposure estimate.")
        }
    }
}

struct HealthActivityCard: View {
    @Bindable var health: HealthService
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Surface {
            Label("Today in Apple Health", systemImage: "figure.walk.circle").font(.headline).foregroundStyle(Palette.ink)
            Text("Optional · iPhone activity, no Watch required").font(.caption).foregroundStyle(Palette.muted)
            if let activity = health.dailyActivity {
                if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 16) { healthMetrics(activity) } }
                else { HStack(spacing: 16) { healthMetrics(activity) } }
                Text("\(activity.start.formatted(date: .abbreviated, time: .omitted)), midnight–\(activity.end.formatted(date: .omitted, time: .shortened)). \(Calendar.current.isDateInToday(activity.end) ? "Snapshot, not live." : "Previous-day snapshot. Refresh to read today.")").font(.caption2).foregroundStyle(Palette.muted)
            }
            Text(health.activityMessage).font(.caption).foregroundStyle(Palette.muted)
            Button(health.isReadingActivity ? "Reading activity…" : "Read today's activity") { Task { await health.readToday() } }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(health.isReadingActivity || health.isReadingVitals)
            if health.isReadingActivity { ProgressView("Checking readable activity…").font(.caption) }
            InfoNote(text: "Read-only. Health totals use available records and can include other apps or devices. They are kept on this device and are not added to your walk's steps, GPS distance or dose. Missing or unreadable data stays unavailable.")
        }
    }
    @ViewBuilder private func healthMetrics(_ activity: HealthDailyActivity) -> some View {
        Metric(title: "Health steps", value: activity.steps.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "Unavailable")
        Metric(title: "Walking & running", value: activity.walkingRunningMetres.map { String(format: "%.2f km", $0 / 1000) } ?? "Unavailable")
    }
}

/// Sensor-independent preview; it never writes to AppModel, Core Data or HealthKit.
struct MotionPreviewView: View {
    @State private var timeline = MotionTimeline(start: Date(timeIntervalSince1970: 1000))
    @State private var totals = PedometerTotals()
    @State private var progressed = false
    @Environment(\.dismiss) private var dismiss
    private var summary: WalkActivitySummary {
        WalkActivitySummary(steps: totals.steps, pedometerMetres: totals.metres, timeline: timeline, stepStatus: progressed ? .available : .waiting, classificationStatus: progressed ? .available : .waiting, stepsUpdatedAt: nil)
    }
    var body: some View {
        NavigationStack {
            Page {
                PageHeader(title: "A walk in numbers.", subtitle: "Synthetic motion preview", symbol: "figure.walk")
                InfoNote(symbol: "sparkles", text: "Synthetic data only. No sensor access, Health data, trip saving or changes to your open walk.")
                Surface {
                    StatusPill(title: "Demo · synthetic activity", symbol: "sparkles")
                    ActivityMetrics(summary: summary)
                    Text(progressed ? "Example: 30 seconds walking, 20 stationary, then a 10-second unmonitored gap. Only the first foreground window reports 42 steps / 29 m." : "No samples yet. Missing step counts are shown as unavailable, not zero.").font(.caption).foregroundStyle(Palette.muted)
                    PrimaryButton(title: progressed ? "Reset example" : "Run activity example", symbol: progressed ? "arrow.counterclockwise" : "play.fill") {
                        timeline = MotionTimeline(start: Date(timeIntervalSince1970: 1000)); totals = PedometerTotals()
                        if !progressed {
                            let start = Date(timeIntervalSince1970: 1000)
                            totals.beginWindow(at: start)
                            timeline.setState(.walking, at: start)
                            _ = totals.accept(steps: 42, metres: 29, at: start.addingTimeInterval(30))
                            timeline.setState(.stationary, at: start.addingTimeInterval(30))
                            timeline.setState(.unknown, at: start.addingTimeInterval(50))
                            totals.endWindow(); timeline.advance(to: start.addingTimeInterval(60))
                        }
                        progressed.toggle()
                    }
                }
                InfoNote(text: "The live implementation uses Core Motion callbacks. This preview validates the presentation and calculation flow; real sensor behaviour needs a physical iPhone.")
            }.navigationTitle("Motion preview").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
