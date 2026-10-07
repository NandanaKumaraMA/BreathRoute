import SwiftUI
import Charts

struct DashboardView: View {
    @Bindable var model: AppModel
    @State private var addingSymptom = false
    private var realTrips: [TripEntry] { model.trips.filter { !$0.demo } }
    var body: some View {
        Page {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: Date().formatted(.dateTime.weekday(.wide).month().day()))
                    Text(model.name.isEmpty ? "Room to breathe." : "Hello, \(model.name).").font(.largeTitle.bold())
                }
                Spacer()
                Image(systemName: "leaf.fill").font(.title).foregroundStyle(Palette.forest).padding(14).background(Palette.forest.opacity(0.1), in: Circle()).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label(model.demo ? "DEMO AIR QUALITY" : "YOUR AIR, AT A GLANCE", systemImage: "wind").font(.caption.weight(.bold)).tracking(1)
                    Spacer()
                    Button { Task { await model.refreshAir() } } label: { Image(systemName: "arrow.clockwise").padding(10) }.accessibilityLabel("Refresh current air quality").disabled(model.busy || model.demo)
                }
                Text(model.air?.label ?? "Know your air.").font(.system(.largeTitle, design: .rounded).bold())
                if let air = model.air {
                    HStack(alignment: .firstTextBaseline, spacing: 8) { Text(air.pm25, format: .number.precision(.fractionLength(1))).font(.system(size: 56, weight: .medium, design: .rounded)); Text("µg/m³ PM2.5").font(.subheadline) }.accessibilityElement(children: .combine)
                    Text(air.demo ? "Illustrative sample · not a live measurement" : "OpenWeather · \(air.date.formatted(date: .abbreviated, time: .shortened)) · \(air.isFresh ? "recent" : "stale")").font(.footnote)
                } else {
                    Text("Connect air-quality data to see what’s around you before your next walk.").font(.body)
                    Button("Enable location") { model.location.request() }.buttonStyle(.bordered).tint(.white)
                }
                Divider().overlay(.white.opacity(0.2))
                Text("A more informed walk starts here.").font(.subheadline)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.white).background(LinearGradient(colors: [Palette.ink, Palette.forest], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
            if model.busy { ProgressView("Updating air quality…") }
            PrimaryButton(title: model.activeRoute == nil ? "Plan a walk" : "Return to active walk", symbol: "figure.walk") { model.section = .routes }
            Surface {
                HStack { Text("Your walking journal").font(.headline); Spacer(); Image(systemName: "chart.bar.xaxis").foregroundStyle(Palette.forest) }
                if realTrips.isEmpty {
                    Text("Your first walk is a fresh start.").font(.title3.weight(.semibold))
                    Text("Finish a walk to see your distance and recorded exposure here. Demo sessions stay separate.").foregroundStyle(.secondary)
                } else {
                    HStack {
                        Metric(title: "Recorded walks", value: "\(realTrips.count)")
                        Metric(title: "Distance recorded", value: String(format: "%.1f km", realTrips.reduce(0) { $0 + $1.metres } / 1000))
                    }
                    Chart(realTrips.prefix(7).reversed()) { trip in
                        if let dose = trip.dose {
                            BarMark(x: .value("Walk", trip.date, unit: .day), y: .value("Recorded dose µg", dose)).foregroundStyle(Palette.forest)
                        }
                    }.frame(height: 150).accessibilityLabel("Recorded exposure by day. Partial records are not full-day exposure.")
                    Text("Recorded portions only; incomplete coverage can understate exposure.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button { addingSymptom = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "heart.text.clipboard").font(.title2).padding(12).background(Palette.forest.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) { Text("How are you feeling?").font(.headline); Text("Add a private symptom note").font(.subheadline).foregroundStyle(.secondary) }
                    Spacer(); Image(systemName: "plus")
                }.padding(20).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
            }.buttonStyle(.plain)
            if !model.demo && model.activeRoute == nil {
                Button("Try an example route comparison") { model.loadDemo() }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            InfoNote(text: "Estimated exposure is not a medical assessment. Pollution data may not resolve differences between neighbouring streets.")
        }.navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $addingSymptom) { SymptomEditor(model: model, entry: SymptomEntry()) }
    }
}
