import SwiftUI

struct JournalView: View {
    @Bindable var model: AppModel
    @State private var editing: SymptomEntry?
    @State private var filter = "All"
    @State private var deletingSymptom: SymptomEntry?
    @State private var deletingTrip: TripEntry?
    var body: some View {
        Page {
            Eyebrow(text: "Your personal record")
            Text("Small notes.\nA clearer picture.").font(.largeTitle.bold())
            Picker("Journal filter", selection: $filter) { Text("All").tag("All"); Text("Walks").tag("Walks"); Text("Symptoms").tag("Symptoms") }.pickerStyle(.segmented)
            PrimaryButton(title: "Log a symptom", symbol: "plus") { editing = SymptomEntry() }
            if model.symptoms.isEmpty && model.trips.isEmpty {
                Surface { Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(Palette.forest); Text("Your story starts here").font(.title2.bold()); Text("Your walks and symptom notes will appear here. Everything in this journal is currently stored on this device.").foregroundStyle(.secondary) }
            }
            if filter != "Symptoms" {
                ForEach(model.trips) { trip in
                    Surface {
                        HStack { Label(trip.destination, systemImage: "figure.walk").font(.headline); Spacer(); Menu { Button("Delete walk", role: .destructive) { deletingTrip = trip } } label: { Image(systemName: "ellipsis").padding(10) }.accessibilityLabel("Walk actions") }
                        Text(trip.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                        HStack { Metric(title: "Recorded distance", value: String(format: "%.0f m", trip.metres)); Metric(title: "Recorded dose", value: doseText(trip.dose)) }
                        Text("\(Int(trip.coverage * 100))% time coverage · \(trip.demo ? "Demo session" : "Partial recording")").font(.caption).foregroundStyle(.secondary)
                        ShareLink(item: "BreatheRoute walk: \(trip.destination). Recorded distance: \(Int(trip.metres)) m. Estimated dose: \(doseText(trip.dose)). Coverage: \(Int(trip.coverage * 100))%. \(trip.demo ? "Demo session." : "Partial recording; awareness only.")") { Label("Share summary", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            if filter != "Walks" {
                ForEach(model.symptoms) { symptom in
                    Surface {
                        HStack { Label(symptom.kind, systemImage: "heart.text.clipboard").font(.headline); Spacer(); Text("\(symptom.severity)/5").font(.headline).foregroundStyle(Palette.forest) }
                        Text(symptom.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                        if !symptom.notes.isEmpty { Text(symptom.notes) }
                        if let id = symptom.tripID { Text(model.trips.first(where: { $0.id == id })?.destination ?? "Linked walk no longer available").font(.caption).foregroundStyle(.secondary) }
                        HStack { Button("Edit") { editing = symptom }; Spacer(); Button("Delete", role: .destructive) { deletingSymptom = symptom } }.padding(.vertical, 6)
                    }
                }
            }
            InfoNote(text: "These are self-reported observations. Showing a symptom alongside a walk does not establish that pollution caused it.")
        }.navigationTitle("Journal").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { SymptomEditor(model: model, entry: $0) }
            .confirmationDialog("Delete this symptom?", isPresented: Binding(get: { deletingSymptom != nil }, set: { if !$0 { deletingSymptom = nil } }), titleVisibility: .visible) {
                Button("Delete symptom", role: .destructive) { if let entry = deletingSymptom { model.deleteSymptom(entry) }; deletingSymptom = nil }
            }
            .confirmationDialog("Delete this walk?", isPresented: Binding(get: { deletingTrip != nil }, set: { if !$0 { deletingTrip = nil } }), titleVisibility: .visible) {
                Button("Delete walk", role: .destructive) { if let entry = deletingTrip { model.deleteTrip(entry) }; deletingTrip = nil }
            } message: { Text("Symptom notes are kept. This action cannot be undone.") }
    }
}

struct SymptomEditor: View {
    @Bindable var model: AppModel
    @State var entry: SymptomEntry
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("What did you notice?") {
                    Picker("Symptom", selection: $entry.kind) { ForEach(["Cough", "Wheezing", "Breathlessness", "Throat irritation", "Eye irritation", "Other"], id: \.self) { Text($0) } }
                    Stepper("Severity: \(entry.severity) of 5", value: $entry.severity, in: 1...5)
                    Text("1 = mild · 5 = severe. This is your own rating.").font(.caption).foregroundStyle(.secondary)
                    DatePicker("When", selection: $entry.date, in: ...Date())
                }
                Section("Your notes") { TextField("Optional context", text: $entry.notes, axis: .vertical).lineLimit(4...8) }
                Section("Link a walk") {
                    Picker("Walk", selection: $entry.tripID) {
                        Text("No linked walk").tag(Optional<UUID>.none)
                        ForEach(model.trips) { trip in Text("\(trip.destination) · \(trip.date.formatted(date: .abbreviated, time: .shortened))").tag(Optional(trip.id)) }
                    }
                }
                Section { Text("Saved locally on this device. BreatheRoute does not diagnose symptoms or detect emergencies.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("Symptom note").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { entry.notes = String(entry.notes.prefix(2000)); if model.save(entry) { dismiss() } }.disabled(!model.persistenceAvailable) }
                }
        }
    }
}
