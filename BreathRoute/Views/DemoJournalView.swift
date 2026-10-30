import SwiftUI
import Charts

/// A separate read-only space: examples never enter AppModel's real journal.
struct DemoJournalView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var snapshot = try? CloudDemoFixtures.snapshot()
    @State private var cloudDate: Date?
    @State private var loading = false
    @State private var loadRequest = 0
    @State private var issue: String?
    @State private var days = 30
    @State private var section = "Insights"
    private var window: DemoJournalWindow { DemoJournalWindow(snapshot: snapshot ?? .init(), days: days) }

    var body: some View {
        NavigationStack {
            Page {
                PageHeader(title: "A month\nin motion.", subtitle: "Sample journal", symbol: "sparkles")
                Surface {
                    StatusPill(title: "Sample data · Read only", symbol: "book.closed")
                    Text("Explore 30 days of walks and check-ins.").font(.headline).foregroundStyle(Palette.ink)
                    Text("Browse sample records to explore your walking history and insights.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    InfoNote(symbol: "person.crop.circle.badge.checkmark", text: "Your own journal and activity totals are unchanged.")
                    Text(cloudDate.map { "Cloud examples loaded · \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Viewing bundled example data")
                        .font(.caption.weight(.medium)).foregroundStyle(Palette.forest).accessibilityIdentifier("demo-data-source")
                    if model.account.identity != nil {
                        Button { loadRequest += 1 } label: {
                            Label(cloudDate == nil ? "Load cloud examples" : "Refresh cloud examples", systemImage: "icloud.and.arrow.down")
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }.disabled(loading).accessibilityIdentifier("load-cloud-examples")
                    }
                    if loading { ProgressView("Loading examples…") }
                    if let issue { InfoNote(text: issue) }
                }
                Surface {
                    Text(dateRange).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    if typeSize.isAccessibilitySize {
                        datePicker.pickerStyle(.menu)
                        VStack(alignment: .leading, spacing: 18) { metrics }
                    } else {
                        datePicker.pickerStyle(.segmented)
                        HStack { metrics }
                    }
                }
                if typeSize.isAccessibilitySize { sectionPicker.pickerStyle(.menu) }
                else { sectionPicker.pickerStyle(.segmented) }
                if section == "Insights" { insights }
                else if section == "Walks" {
                    ForEach(window.trips) { trip in
                        NavigationLink { DemoWalkDetail(trip: trip, notes: snapshot?.notes.filter { $0.tripID == trip.id } ?? []) } label: {
                            Surface { walkLabel(trip) }
                        }.buttonStyle(.plain)
                    }
                } else {
                    ForEach(window.notes) { note in noteRow(note) }
                }
                InfoNote(text: "Sample records for exploring the journal. They are not measured air or health data.")
            }
            .navigationTitle("Sample journal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.task(id: loadRequest) { if loadRequest > 0 { await loadCloud() } }
    }

    private var datePicker: some View {
        Picker("Example date range", selection: $days) {
            Text("Last 7 example days").tag(7)
            Text("All 30 days").tag(30)
        }.accessibilityIdentifier("demo-date-filter")
    }
    private var sectionPicker: some View {
        Picker("Journal section", selection: $section) {
            ForEach(["Insights", "Walks", "Notes"], id: \.self) { Text($0) }
        }.accessibilityIdentifier("demo-section-filter")
    }

    private func noteRow(_ note: SymptomEntry) -> some View {
        Surface {
            DemoNoteLabel(note: note)
            if let id = note.tripID, let trip = snapshot?.trips.first(where: { $0.id == id }) {
                NavigationLink {
                    DemoWalkDetail(trip: trip, notes: snapshot?.notes.filter { $0.tripID == id } ?? [])
                } label: { Label("View linked example walk", systemImage: "figure.walk") }
                    .font(.subheadline).frame(minHeight: 44)
            } else { Text("Independent check-in · no linked walk").font(.caption).foregroundStyle(Palette.muted) }
        }
    }

    @ViewBuilder private var metrics: some View {
        Metric(title: "Example walks", value: "\(window.trips.count)")
        Metric(title: "Kilometres", value: String(format: "%.1f", window.kilometres))
        Metric(title: "Check-ins", value: "\(window.notes.count)")
    }
    private var dateRange: String {
        guard let start = window.trips.last?.date, let end = window.trips.first?.date else { return "No examples available" }
        return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
    @ViewBuilder private var insights: some View {
        Surface {
            SectionHeading(title: "Walking rhythm", detail: "Distance over time")
            if typeSize.isAccessibilitySize {
                ForEach(window.trips) { trip in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trip.date.formatted(date: .abbreviated, time: .omitted))
                        Text(String(format: "%.1f example kilometres", trip.metres / 1000)).bold()
                    }.font(.subheadline).foregroundStyle(Palette.ink).accessibilityElement(children: .combine)
                }
            } else {
                Chart(window.trips) { trip in
                    BarMark(x: .value("Day", trip.date, unit: .day), y: .value("Kilometres", trip.metres / 1000))
                        .foregroundStyle(Palette.forest)
                        .accessibilityLabel(trip.date.formatted(date: .abbreviated, time: .omitted))
                        .accessibilityValue(String(format: "%.1f example kilometres", trip.metres / 1000))
                }.chartYAxisLabel("km").frame(height: 180)
            }
        }
        Surface {
            SectionHeading(title: "Check-in patterns", detail: "Check-in trends")
            if typeSize.isAccessibilitySize {
                ForEach(CloudDemoFixtures.symptomKinds, id: \.self) { kind in
                    Text("\(kind): \(window.notes.filter { $0.kind == kind }.count) example check-ins")
                        .font(.subheadline).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Chart(CloudDemoFixtures.symptomKinds, id: \.self) { kind in
                    BarMark(x: .value("Notes", window.notes.filter { $0.kind == kind }.count), y: .value("Type", kind))
                        .foregroundStyle(Palette.forest)
                }.chartXAxisLabel("Number of check-ins").frame(height: 220)
            }
            InfoNote(text: "Severity ranges from 1 to 5. These counts describe the sample journal.")
        }
        Surface {
            SectionHeading(title: "Exposure coverage")
            coverageRow("Complete coverage", count: window.completeCoverageCount, symbol: "checkmark.circle")
            coverageRow("Partial coverage", count: window.partialCoverageCount, symbol: "circle.lefthalf.filled")
            coverageRow("No coverage", count: window.missingCoverageCount, symbol: "questionmark.circle")
            InfoNote(text: "Missing exposure stays unavailable. Partial estimates describe the covered portion only; they are not directly comparable with complete estimates.")
        }
    }
    private func coverageRow(_ title: String, count: Int, symbol: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Label(title, systemImage: symbol).fixedSize(); Spacer(); Text("\(count)").monospacedDigit().bold() }
            VStack(alignment: .leading, spacing: 6) { Label(title, systemImage: symbol); Text("\(count)").monospacedDigit().bold() }
        }
            .font(.subheadline).foregroundStyle(Palette.ink).accessibilityElement(children: .combine)
    }
    private func walkLabel(_ trip: CloudTripSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(demoDestination(trip)).font(.headline); Spacer(); Image(systemName: "chevron.right").font(.caption) }
            Text(trip.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Palette.muted)
            Text(String(format: "%.1f km · %.0f min · %.0f%% coverage", trip.metres / 1000, trip.seconds / 60, trip.coverage * 100))
                .font(.subheadline)
            if !trip.complete { StatusPill(title: "Stopped early", symbol: "stop.circle") }
        }.foregroundStyle(Palette.ink)
    }
    @MainActor private func loadCloud() async {
        guard let identity = model.account.identity, !loading else { return }
        loading = true; issue = nil
        defer { loading = false }
        do {
            let result = try await model.cloud.loadDemonstration(identity: identity)
            try Task.checkCancellation()
            guard model.account.identity == identity else { return }
            snapshot = result.snapshot; cloudDate = result.updatedAt
        } catch is CancellationError { }
        catch {
            guard model.account.identity == identity else { return }
            issue = (error as? CloudDemoReadError)?.rawValue ?? "Cloud examples could not be loaded. The displayed dataset has not changed. Try again when connected."
        }
    }
}

private func demoDestination(_ trip: CloudTripSummary) -> String {
    trip.destination.replacingOccurrences(of: "[SYNTHETIC DEMO] ", with: "")
}
private struct DemoWalkDetail: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let trip: CloudTripSummary
    let notes: [SymptomEntry]
    var body: some View {
        Page {
            PageHeader(title: demoDestination(trip), subtitle: "Sample walk", symbol: "figure.walk")
            Surface {
                StatusPill(title: "Sample record · Read only", symbol: "book.closed")
                Text(trip.date.formatted(date: .complete, time: .shortened)).font(.subheadline).foregroundStyle(Palette.muted)
                if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 18) { metrics } }
                else { HStack { metrics } }
                Metric(title: "Estimated exposure · covered portion", value: doseText(trip.dose))
                Text(String(format: "%.0f%% coverage · %@", trip.coverage * 100, trip.complete ? "Finished" : "Stopped early")).font(.subheadline).foregroundStyle(Palette.ink)
                InfoNote(text: trip.coverage == 0 ? "No exposure value is invented for missing coverage." : "Sample exposure estimate for the covered portion. This is not a sensor measurement.")
                if let ventilation = trip.ventilation { Text(String(format: "Modelled breathing volume: %.0f L/min", ventilation * 1000)).font(.caption).foregroundStyle(Palette.muted) }
            }
            SectionHeading(title: "Linked example check-ins")
            ForEach(notes.sorted { $0.date < $1.date }) { note in Surface { DemoNoteLabel(note: note) } }
            InfoNote(text: "This summary has no recorded GPS path or Health data. Linking a symptom to a walk does not establish a cause.")
        }.navigationTitle("Example walk").navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private var metrics: some View {
        Metric(title: "Distance", value: String(format: "%.1f km", trip.metres / 1000))
        Metric(title: "Duration", value: String(format: "%.0f min", trip.seconds / 60))
    }
}
private struct DemoNoteLabel: View {
    let note: SymptomEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(note.kind).font(.headline).foregroundStyle(Palette.ink)
            Text(note.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Palette.muted)
            Label("Severity \(note.severity) of 5", systemImage: "heart.text.clipboard").font(.subheadline).foregroundStyle(Palette.forest)
            Text(note.notes.replacingOccurrences(of: "[SYNTHETIC DEMO] ", with: "").replacingOccurrences(of: "Fictional ", with: "")).font(.subheadline).foregroundStyle(Palette.muted)
        }
    }
}
