import SwiftUI

private enum JournalItem: Identifiable {
    case trip(TripEntry), symptom(SymptomEntry)
    var id: UUID { switch self { case .trip(let trip): trip.id; case .symptom(let symptom): symptom.id } }
    var date: Date { switch self { case .trip(let trip): trip.date; case .symptom(let symptom): symptom.date } }
}

struct JournalView: View {
    @Bindable var model: AppModel
    @State private var editing: SymptomEntry?
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
            HStack(alignment: .top) {
                PageHeader(title: "Your journal.", subtitle: "Journal & insights", symbol: "book.closed")
            }
            overview
            HStack {
                filterTabs
                Spacer(minLength: 5)
                Menu {
                    Button("All time") { periodDays = 0 }
                    Button("Last 7 days") { periodDays = 7 }
                    Button("Last 30 days") { periodDays = 30 }
                } label: { Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Palette.forest).frame(width: 44, height: 44).background(Palette.surface, in: Circle()) }
                    .accessibilityLabel("Filter dates: \(periodDays == 0 ? "All time" : "Last \(periodDays) days")")
            }
            if periodDays != 0 { StatusPill(title: "Last \(periodDays) days", symbol: "calendar") }
            if items.isEmpty { emptyState }
            else {
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 14) {
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
                HStack { Image(systemName: "plus"); Text("Add a symptom note"); Spacer(); Image(systemName: "arrow.up.right") }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).padding(20).background(Palette.lavender, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(PressStyle())
            InfoNote(text: "Symptoms are your own observations. A linked walk does not establish that pollution caused a symptom.")
        }
        .adaptiveNavigationBar()
        .sheet(item: $editing) { SymptomEditor(model: model, entry: $0) }
        .confirmationDialog("Delete this symptom?", isPresented: Binding(get: { deletingSymptom != nil }, set: { if !$0 { deletingSymptom = nil } }), titleVisibility: .visible) {
            Button("Delete symptom", role: .destructive) { if let entry = deletingSymptom { model.deleteSymptom(entry) }; deletingSymptom = nil }
        }
    }
    private var overview: some View {
        let walks = model.trips.filter { !$0.demo && $0.date >= cutoff }
        return HStack(spacing: 0) {
            summaryStat(value: "\(walks.count)", title: "WALKS", symbol: "figure.walk")
            Rectangle().fill(Palette.line).frame(width: 1, height: 36)
            summaryStat(value: String(format: "%.1f", walks.reduce(0) { $0 + $1.metres }/1000), title: "KILOMETRES", symbol: "map")
            Rectangle().fill(Palette.line).frame(width: 1, height: 36)
            summaryStat(value: "\(model.symptoms.filter { $0.date >= cutoff }.count)", title: "NOTES", symbol: "heart")
        }.padding(.vertical, 22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line, lineWidth: 0.7))
    }
    private func summaryStat(value: String, title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.caption).foregroundStyle(Palette.forest)
            Text(value).font(.system(.title2, design: .rounded).weight(.medium)).foregroundStyle(Palette.ink).monospacedDigit()
            Text(title).font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
    private var filterTabs: some View {
        HStack(spacing: 3) {
            ForEach(["All", "Walks", "Symptoms"], id: \.self) { item in
                Button { filter = item } label: { Text(item).font(.caption.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 44).foregroundStyle(filter == item ? Palette.lime : Palette.muted).background(filter == item ? Palette.deep : .clear, in: Capsule()) }
                    .accessibilityAddTraits(filter == item ? .isSelected : [])
            }
        }.sensoryFeedback(.selection, trigger: filter)
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Palette.forest.opacity(0.04)).frame(width: 165, height: 165)
                Circle().stroke(Palette.forest.opacity(0.07), lineWidth: 1).frame(width: 140, height: 140)
                RoundedRectangle(cornerRadius: 18).fill(Palette.surface).frame(width: 83, height: 105).rotationEffect(.degrees(-8)).shadow(color: .black.opacity(0.04), radius: 12, y: 5)
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "leaf.fill").foregroundStyle(Palette.forest)
                    ForEach(0..<3) { index in Capsule().fill(Palette.line).frame(width: index == 2 ? 30 : 48, height: 3) }
                }.rotationEffect(.degrees(-8))
                Image(systemName: "plus").font(.caption.bold()).foregroundStyle(Palette.deep).frame(width: 34, height: 34).background(Palette.lime, in: Circle()).offset(x: 48, y: 34)
            }.accessibilityHidden(true)
            Text("A fresh page for you.").font(.system(.title2, design: .serif)).foregroundStyle(Palette.ink)
            Text(periodDays == 0 ? "Walks and check-ins will build your story here.\nStart with a walk, or a note about your day." : "There are no entries in this date range.\nTry a different filter or add a note.").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Palette.muted)
            Button("Plan a walk") { model.section = .routes }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }.padding(.vertical, 22).frame(maxWidth: .infinity)
    }
    private func tripRow(_ trip: TripEntry) -> some View {
        NavigationLink {
            TripDetailView(model: model, trip: trip).toolbar(.visible, for: .navigationBar)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "figure.walk").font(.headline).foregroundStyle(Palette.forest).frame(width: 44, height: 44).background(Palette.forest.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 8) {
                    Text(trip.destination).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("\(trip.date.formatted(.dateTime.hour().minute())) · \(Int(trip.metres)) m recorded").font(.caption).foregroundStyle(Palette.muted)
                    StatusPill(title: trip.demo ? "Demo session" : "\(Int(trip.coverage*100))% coverage", symbol: trip.demo ? "sparkles" : "chart.bar.fill")
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.muted).padding(.top, 14)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line, lineWidth: 0.7))
        }.buttonStyle(PressStyle())
    }
    private func symptomRow(_ symptom: SymptomEntry) -> some View {
        Surface(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "heart.text.clipboard").font(.headline).foregroundStyle(Palette.ink).frame(width: 44, height: 44).background(Palette.lavender, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 7) {
                    Text(symptom.kind).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("\(symptom.date.formatted(.dateTime.hour().minute())) · Symptom note").font(.caption).foregroundStyle(Palette.muted)
                    HStack(spacing: 4) { ForEach(1...5, id: \.self) { level in Capsule().fill(level <= symptom.severity ? Palette.forest : Palette.line).frame(width: 14, height: 4) }; Text("\(symptom.severity)/5").font(.caption2).foregroundStyle(Palette.muted).padding(.leading, 5) }.accessibilityElement(children: .ignore).accessibilityLabel("Severity \(symptom.severity) of 5")
                }
                Spacer(minLength: 0)
                Menu { Button("Edit note") { editing = symptom }; Button("Delete note", role: .destructive) { deletingSymptom = symptom } } label: { Image(systemName: "ellipsis").foregroundStyle(Palette.muted).frame(width: 44, height: 44) }.accessibilityLabel("Actions for \(symptom.kind) note")
            }
            if !symptom.notes.isEmpty { Text(symptom.notes).font(.subheadline).foregroundStyle(Palette.muted) }
            if let id = symptom.tripID { Label(model.trips.first(where: { $0.id == id })?.destination ?? "Linked walk no longer available", systemImage: "link").font(.caption).foregroundStyle(Palette.muted) }
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
            PageHeader(title: trip.destination, subtitle: trip.date.formatted(date: .abbreviated, time: .shortened), symbol: "figure.walk")
            Surface {
                StatusPill(title: trip.demo ? "Demo session" : "Recorded portions", symbol: trip.demo ? "sparkles" : "chart.bar.fill")
                Text(doseText(trip.dose)).font(.system(.largeTitle, design: .rounded).weight(.medium)).foregroundStyle(Palette.ink)
                Text("Recorded estimated PM2.5 dose").font(.subheadline).foregroundStyle(Palette.muted)
                Divider()
                HStack { Metric(title: "Recorded distance", value: "\(Int(trip.metres)) m"); Metric(title: "Elapsed time", value: "\(Int(trip.seconds/60)) min") }
            }
            Surface {
                SectionHeading(title: "How much was recorded?")
                HStack { Text("Time coverage").font(.subheadline); Spacer(); Text("\(Int(trip.coverage*100))%").font(.headline) }
                ProgressView(value: trip.coverage).tint(Palette.forest)
                InfoNote(text: "Unobserved intervals are excluded. An incomplete recording may understate your total exposure.")
            }
            let linked = model.symptoms.filter { $0.tripID == trip.id }
            Surface {
                SectionHeading(title: "Linked symptom notes", detail: "\(linked.count)")
                if linked.isEmpty { Text("No notes linked to this walk.").font(.subheadline).foregroundStyle(Palette.muted) }
                ForEach(linked) { symptom in LabeledContent(symptom.kind, value: "\(symptom.severity)/5").font(.subheadline) }
            }
            ShareLink(item: "BreatheRoute: \(trip.destination). Recorded distance \(Int(trip.metres)) m. Estimated dose \(doseText(trip.dose)). Coverage \(Int(trip.coverage*100))%. \(trip.demo ? "Demo session." : "For awareness only.")") { Label("Share walk summary", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(16) }.buttonStyle(.bordered)
            Button("Delete walk", role: .destructive) { deleting = true }.frame(maxWidth: .infinity, minHeight: 44)
        }.navigationTitle("Walk summary").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete this walk?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete walk", role: .destructive) { model.deleteTrip(trip); if !model.trips.contains(where: { $0.id == trip.id }) { dismiss() } }
            } message: { Text("Linked symptom notes are kept. This action cannot be undone.") }
    }
}

struct SymptomEditor: View {
    @Bindable var model: AppModel
    @State var entry: SymptomEntry
    @Environment(\.dismiss) private var dismiss
    private let kinds = ["Cough", "Wheezing", "Breathlessness", "Throat irritation", "Eye irritation", "Other"]
    private let symbols = ["wind", "lungs", "figure.walk", "waveform", "eye", "ellipsis"]
    var body: some View {
        NavigationStack {
            Page {
                VStack(alignment: .leading, spacing: 9) { Eyebrow(text: "A moment for yourself"); Text("How are you feeling?").font(.system(.title, design: .serif)).foregroundStyle(Palette.ink); Text("Add a note in your own words.").font(.subheadline).foregroundStyle(Palette.muted) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { index, kind in
                        Button { entry.kind = kind } label: {
                            HStack(spacing: 9) { Image(systemName: symbols[index]).font(.subheadline); Text(kind).font(.caption.weight(.medium)); Spacer(minLength: 0) }
                                .padding(16).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                                .foregroundStyle(entry.kind == kind ? Palette.lime : Palette.ink)
                                .background(entry.kind == kind ? Palette.deep : Palette.surface, in: RoundedRectangle(cornerRadius: 17))
                        }.buttonStyle(PressStyle()).accessibilityAddTraits(entry.kind == kind ? .isSelected : [])
                    }
                }
                Surface {
                    SectionHeading(title: "How noticeable is it?", detail: "\(entry.severity) of 5")
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { level in
                            Button { entry.severity = level } label: { Text("\(level)").font(.headline).frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(entry.severity == level ? Palette.lime : Palette.muted).background(entry.severity == level ? Palette.deep : Palette.canvas, in: RoundedRectangle(cornerRadius: 14)) }.accessibilityLabel("Severity \(level) of 5").accessibilityAddTraits(entry.severity == level ? .isSelected : [])
                        }
                    }
                    HStack { Text("Mild"); Spacer(); Text("Severe") }.font(.caption).foregroundStyle(Palette.muted)
                    Divider()
                    DatePicker("When", selection: $entry.date, in: ...Date()).font(.subheadline)
                }
                Surface {
                    SectionHeading(title: "Anything else?", detail: "Optional")
                    TextField("What were you doing? How did it feel?", text: $entry.notes, axis: .vertical).font(.subheadline).lineLimit(4...8)
                }
                if !model.trips.isEmpty {
                    Surface { Picker("Link a walk", selection: $entry.tripID) { Text("No linked walk").tag(Optional<UUID>.none); ForEach(model.trips) { trip in Text(trip.destination).tag(Optional(trip.id)) } }.font(.subheadline) }
                }
                InfoNote(symbol: "lock", text: "Your note stays on this device. It’s a personal observation, not a diagnosis.")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton(title: "Save note", symbol: "checkmark") { entry.notes = String(entry.notes.prefix(2000)); if model.save(entry) { dismiss() } }.disabled(!model.persistenceAvailable).padding(22).background(.regularMaterial)
            }
            .navigationTitle("Check-in").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .sensoryFeedback(.selection, trigger: entry.severity)
        }
    }
}
