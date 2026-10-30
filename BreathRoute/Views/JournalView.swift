import SwiftUI

private enum JournalItem: Identifiable {
    case trip(TripEntry), symptom(SymptomEntry)
    var id: UUID { switch self { case .trip(let trip): trip.id; case .symptom(let symptom): symptom.id } }
    var date: Date { switch self { case .trip(let trip): trip.date; case .symptom(let symptom): symptom.date } }
}

struct JournalView: View {
    @Bindable var model: AppModel
    @State private var editing: SymptomEntry?
    @State private var showDemoJournal = false
    @State private var filter = "All"
    @State private var periodDays = 0
    @State private var deletingSymptom: SymptomEntry?
    private var cutoff: Date { periodDays == 0 ? .distantPast : Calendar.current.date(byAdding: .day, value: -periodDays, to: Date())! }
    private var items: [JournalItem] {
        let trips = filter == "Symptoms" ? [] : model.trips.filter { $0.date >= cutoff }.map(JournalItem.trip)
        let symptoms = filter == "Walks" ? [] : model.symptoms.filter { $0.date >= cutoff }.map(JournalItem.symptom)
        return (trips + symptoms).sorted { $0.date > $1.date }
    }
    private var days: [Date] { Array(Set(items.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >) }

    var body: some View {
        Page {
            PageHeader(title: "Your journal.", subtitle: "Walks & notes", symbol: "book.closed")
            overview
            HStack {
                filterTabs
                Spacer(minLength: 5)
                Menu {
                    Button("All time") { periodDays = 0 }
                    Button("Last 7 days") { periodDays = 7 }
                    Button("Last 30 days") { periodDays = 30 }
                } label: {
                    Label(periodDays == 0 ? "All time" : "\(periodDays)d", systemImage: "calendar")
                        .font(.caption.weight(.semibold)).foregroundStyle(Palette.forest)
                        .padding(.horizontal, 12).frame(minHeight: 40).background(Palette.surface, in: Capsule())
                }
            }
            if items.isEmpty { emptyState }
            else {
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        ForEach(items.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { item in
                            switch item {
                            case .trip(let trip): tripRow(trip)
                            case .symptom(let symptom): symptomRow(symptom)
                            }
                        }
                    }
                }
            }
            Button { editing = SymptomEntry() } label: {
                HStack { Image(systemName: "plus"); Text("Add a symptom note"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    .padding(18).background(Palette.lavender, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(PressStyle())
            Button("Explore a sample journal", systemImage: "sparkles") { showDemoJournal = true }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }
        .adaptiveNavigationBar()
        .sheet(isPresented: $showDemoJournal) { DemoJournalView(model: model) }
        .sheet(item: $editing) { SymptomEditor(model: model, entry: $0) }
        .confirmationDialog("Delete this symptom?", isPresented: Binding(get: { deletingSymptom != nil }, set: { if !$0 { deletingSymptom = nil } }), titleVisibility: .visible) {
            Button("Delete symptom", role: .destructive) { if let entry = deletingSymptom { model.deleteSymptom(entry) }; deletingSymptom = nil }
        }
    }

    private var overview: some View {
        let walks = model.trips.filter { !$0.demo && $0.date >= cutoff }
        return HStack(spacing: 0) {
            summaryStat(value: "\(walks.count)", title: "WALKS", symbol: "figure.walk")
            Rectangle().fill(Palette.line).frame(width: 1, height: 32)
            summaryStat(value: String(format: "%.1f", walks.reduce(0) { $0 + $1.metres } / 1000), title: "KM", symbol: "map")
            Rectangle().fill(Palette.line).frame(width: 1, height: 32)
            summaryStat(value: "\(model.symptoms.filter { $0.date >= cutoff }.count)", title: "NOTES", symbol: "heart")
        }.padding(.vertical, 18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line, lineWidth: 0.7))
    }

    private func summaryStat(value: String, title: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.caption).foregroundStyle(Palette.forest)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).foregroundStyle(Palette.ink).monospacedDigit()
            Text(title).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }

    private var filterTabs: some View {
        HStack(spacing: 4) {
            ForEach(["All", "Walks", "Symptoms"], id: \.self) { item in
                Button { filter = item } label: {
                    Text(item).font(.caption.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 40)
                        .foregroundStyle(filter == item ? Palette.lime : Palette.muted)
                        .background(filter == item ? Palette.deep : .clear, in: Capsule())
                }.accessibilityAddTraits(filter == item ? .isSelected : [])
            }
        }.sensoryFeedback(.selection, trigger: filter)
    }

    private var emptyState: some View {
        Surface {
            HStack(spacing: 14) {
                Image(systemName: "leaf.fill").font(.title2).foregroundStyle(Palette.forest)
                    .frame(width: 48, height: 48).background(Palette.forest.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("No entries yet").font(.headline).foregroundStyle(Palette.ink)
                    Text("Saved walks and symptom check-ins appear here.").font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("Plan a walk") { model.section = .routes }.font(.caption.weight(.semibold))
            }
        }
    }

    private func tripRow(_ trip: TripEntry) -> some View {
        NavigationLink {
            TripDetailView(model: model, trip: trip).toolbar(.visible, for: .navigationBar)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "figure.walk").font(.headline).foregroundStyle(Palette.forest)
                    .frame(width: 42, height: 42).background(Palette.forest.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.displayDestination).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("\(trip.date.formatted(.dateTime.hour().minute())) · \(Int(trip.metres)) m · \(doseText(trip.dose))").font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 4)
                StatusPill(title: trip.demo ? "Preview" : "\(Int(trip.coverage * 100))%", symbol: trip.demo ? "sparkles" : nil)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.muted)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line, lineWidth: 0.7))
        }.buttonStyle(PressStyle())
    }

    private func symptomRow(_ symptom: SymptomEntry) -> some View {
        Surface(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.text.clipboard").font(.headline).foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40).background(Palette.lavender, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(symptom.kind) · \(symptom.severity)/5").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(symptom.date.formatted(.dateTime.hour().minute())).font(.caption).foregroundStyle(Palette.muted)
                    if symptom.conflictCopyOf != nil { StatusPill(title: "Conflict copy", symbol: "doc.on.doc") }
                    if !symptom.notes.isEmpty { Text(symptom.notes).font(.caption).foregroundStyle(Palette.muted) }
                    if let id = symptom.tripID {
                        Label(model.trips.first(where: { $0.id == id })?.destination ?? "Linked walk", systemImage: "link").font(.caption2).foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Edit note") { editing = symptom }
                    Button("Delete note", role: .destructive) { deletingSymptom = symptom }
                } label: { Image(systemName: "ellipsis").foregroundStyle(Palette.muted).frame(width: 36, height: 36) }
            }
        }
    }
}

struct TripDetailView: View {
    @Bindable var model: AppModel
    let trip: TripEntry
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Page {
            PageHeader(title: trip.displayDestination, subtitle: trip.date.formatted(date: .abbreviated, time: .shortened), symbol: "figure.walk")
            Surface {
                HStack {
                    StatusPill(title: trip.demo ? "Preview" : "\(Int(trip.coverage * 100))% time coverage", symbol: trip.demo ? "sparkles" : "chart.bar.fill")
                    Spacer()
                    if trip.recovered == true { StatusPill(title: "Recovered", symbol: "arrow.counterclockwise") }
                }
                HStack(spacing: 16) {
                    Metric(title: "Est. PM2.5 dose", value: doseText(trip.dose))
                    Metric(title: "Distance", value: "\(Int(trip.metres)) m")
                    Metric(title: "Elapsed", value: "\(Int(trip.seconds / 60)) min")
                }
                ProgressView(value: trip.coverage).tint(Palette.forest)
                if let ventilation = trip.ventilation {
                    Text("Assumed breathing rate: \(Int(ventilation * 1000)) L/min. Unobserved gaps are excluded.").font(.caption).foregroundStyle(Palette.muted)
                }
            }
            if trip.cloudSummary == true { InfoNote(symbol: "icloud.and.arrow.down", text: "Restored summary. GPS paths and activity remain on the original device.") }
            if trip.conflictCopyOf != nil { InfoNote(symbol: "doc.on.doc", text: "Conflict copy. Both versions were kept after competing edits.") }
            if !(trip.recordedPath?.isEmpty ?? true) || !(trip.plannedPath?.isEmpty ?? true) {
                RecordedPathView(points: trip.recordedPath ?? [], planned: trip.plannedPath ?? [], demo: trip.demo)
            }
            if let activity = trip.activity { SavedActivityCard(summary: activity) }
            let linked = model.symptoms.filter { $0.tripID == trip.id }
            if !linked.isEmpty {
                Surface {
                    SectionHeading(title: "Linked symptom notes", detail: "\(linked.count)")
                    ForEach(linked) { symptom in LabeledContent(symptom.kind, value: "\(symptom.severity)/5").font(.subheadline) }
                }
            }
            HStack(spacing: 12) {
                ShareLink(item: "BreatheRoute\(trip.demo ? " preview" : ""): \(trip.displayDestination). Distance \(Int(trip.metres)) m. Est. dose \(doseText(trip.dose)). Coverage \(Int(trip.coverage * 100))%.") {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(12)
                }.buttonStyle(.bordered)
                Button("Delete walk", role: .destructive) { deleting = true }.buttonStyle(.bordered)
            }
        }
        .navigationTitle("Walk summary").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this walk?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete walk", role: .destructive) { model.deleteTrip(trip); if !model.trips.contains(where: { $0.id == trip.id }) { dismiss() } }
        } message: { Text("Linked symptom notes are kept.") }
    }
}

struct SymptomEditor: View {
    @Bindable var model: AppModel
    @State var entry: SymptomEntry
    @Environment(\.dismiss) private var dismiss
    private let kinds = ["Cough", "Wheezing", "Breathlessness", "Throat irritation", "Eye irritation", "Other"]

    var body: some View {
        NavigationStack {
            Page {
                Surface {
                    SectionHeading(title: "Symptom & severity", detail: "\(entry.severity) of 5")
                    Picker("Symptom", selection: $entry.kind) {
                        ForEach(kinds, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu)
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { level in
                            Button { entry.severity = level } label: {
                                Text("\(level)").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(entry.severity == level ? Palette.lime : Palette.muted)
                                    .background(entry.severity == level ? Palette.deep : Palette.canvas, in: RoundedRectangle(cornerRadius: 12))
                            }.accessibilityLabel("Severity \(level) of 5")
                        }
                    }
                    DatePicker("When", selection: $entry.date, in: ...Date()).font(.subheadline)
                    if !model.trips.isEmpty {
                        Picker("Link a walk", selection: $entry.tripID) {
                            Text("No linked walk").tag(Optional<UUID>.none)
                            ForEach(model.trips) { trip in Text(trip.displayDestination).tag(Optional(trip.id)) }
                        }.font(.subheadline)
                    }
                }
                Surface {
                    SectionHeading(title: "Notes", detail: "Optional")
                    TextField("What were you doing? How did it feel?", text: $entry.notes, axis: .vertical).font(.subheadline).lineLimit(3...6)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton(title: "Save note", symbol: "checkmark") {
                    entry.notes = String(entry.notes.prefix(2000))
                    if model.save(entry) { dismiss() }
                }.disabled(!model.persistenceAvailable).padding(20).background(.regularMaterial)
            }
            .navigationTitle("Symptom check-in").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
