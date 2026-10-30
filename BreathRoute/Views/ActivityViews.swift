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
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Track iPhone steps during walks", isOn: Binding(get: { model.motionTrackingEnabled }, set: { model.setMotionTracking($0) })).font(.subheadline.weight(.medium))
            Text(model.motion.availabilityDescription).font(.caption).foregroundStyle(Palette.muted)
            Button("Preview motion metrics", systemImage: "play.circle") { preview = true }.font(.caption.weight(.semibold))
        }.sheet(isPresented: $preview) { MotionPreviewView() }
    }
}

struct ActiveMotionCard: View {
    @Bindable var model: AppModel
    let demo: Bool
    @State private var preview = false
    var body: some View {
        Surface {
            HStack {
                SectionHeading(title: "iPhone motion")
                Spacer()
                StatusPill(title: demo ? "Preview" : model.motion.state.title, symbol: demo ? "sparkles" : model.motion.state.symbol)
            }
            if demo {
                Text("This preview uses sample activity values.").font(.caption).foregroundStyle(Palette.muted)
            } else {
                Toggle("Track steps during this walk", isOn: Binding(get: { model.motionTrackingEnabled }, set: { model.setMotionTracking($0) })).font(.subheadline)
                if let summary = model.motion.summary {
                    ActivityMetrics(summary: summary)
                }
            }
            Button("Preview motion metrics", systemImage: "play.circle") { preview = true }.font(.caption.weight(.semibold))
        }.sheet(isPresented: $preview) { MotionPreviewView() }
    }
}

struct ActivityMetrics: View {
    let summary: WalkActivitySummary
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)] : [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 14) {
                Metric(title: "Steps", value: summary.steps.map { $0.formatted() } ?? "Unavailable")
                Metric(title: "Pedometer", value: summary.pedometerMetres.map { String(format: "%.0f m", $0) } ?? "Unavailable")
                Metric(title: "Walking time", value: activityTime(summary.walkingSeconds))
            }
            Text("Stationary \(activityTime(summary.stationarySeconds)) · Unclassified \(activityTime(summary.unknownSeconds)) · \(Int(summary.classifiedFraction * 100))% classified")
                .font(.caption2).foregroundStyle(Palette.muted)
        }
    }
}

struct SavedActivityCard: View {
    let summary: WalkActivitySummary
    var body: some View {
        Surface {
            SectionHeading(title: "Recorded phone activity")
            ActivityMetrics(summary: summary)
            Text("Foreground Core Motion snapshot · separate from GPS distance.").font(.caption2).foregroundStyle(Palette.muted)
        }
    }
}

struct HealthActivityCard: View {
    @Bindable var health: HealthService
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Today in Apple Health", systemImage: "figure.walk.circle").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Button(health.isReadingActivity ? "Reading…" : "Refresh") { Task { await health.readToday() } }
                    .font(.caption.weight(.semibold)).disabled(health.isReadingActivity || health.isReadingVitals)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], spacing: 16) {
                Metric(title: "Steps", value: health.dailyActivity?.steps.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "Unavailable")
                Metric(title: "Walk + run", value: health.dailyActivity?.walkingRunningMetres.map { String(format: "%.2f km", $0 / 1000) } ?? "Unavailable")
            }
            Text(health.activityMessage).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
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
                PageHeader(title: "Motion preview.", subtitle: "Activity preview", symbol: "figure.walk")
                Surface {
                    StatusPill(title: "Sample readings", symbol: "sparkles")
                    ActivityMetrics(summary: summary)
                    Text(progressed ? "Preview includes 30s walking (42 steps / 29 m), 20s stationary and a 10s unobserved gap." : "Explore a minute of activity with sample readings.").font(.caption).foregroundStyle(Palette.muted)
                    PrimaryButton(title: progressed ? "Reset preview" : "Play activity preview", symbol: progressed ? "arrow.counterclockwise" : "play.fill") {
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
            }.navigationTitle("Motion preview").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}


/// Read-only HealthKit snapshots. Missing values stay visible instead of silently disappearing.
struct HealthVitalsCard: View {
    @Bindable var health: HealthService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Health records").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            vital("Heart rate", unit: "bpm", record: health.heartRecord)
            vital("Breathing rate", unit: "breaths/min", record: health.respiratoryRecord)
            Text(health.summary).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Button(health.isReadingVitals ? "Reading Apple Health…" : "Read Apple Health records") { Task { await health.readRecentVitals() } }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                .disabled(health.isReadingVitals || health.isReadingActivity)
            Text("An iPhone does not measure heart or breathing rate by itself. Available records need a compatible source; permission alone does not create readings.")
                .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func vital(_ title: String, unit: String, record: HealthVitalRecord?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: record.map { "\($0.value.formatted(.number.precision(.fractionLength(0)))) \(unit)" } ?? "Unavailable")
                .font(.subheadline).foregroundStyle(Palette.ink)
            if let record {
                Text("\(record.source) · \(record.date.formatted(date: .abbreviated, time: .shortened))\(record.manuallyEntered ? " · Manually entered" : "")")
                    .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
