import SwiftUI
import Charts

struct DashboardView: View {
    @Bindable var model: AppModel
    @State private var addingSymptom = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var realTrips: [TripEntry] { model.trips.filter { !$0.demo } }
    private var weekTrips: [TripEntry] { realTrips.filter { $0.date >= Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))! } }
    var body: some View {
        GeometryReader { geometry in
            Page {
                HStack(spacing: 10) {
                    BrandMark()
                    Text("breathe route").font(.system(.headline, design: .rounded).weight(.semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    Button { model.section = .profile } label: {
                        Text(model.name.first.map { String($0).uppercased() } ?? "You").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.forest).frame(width: 44, height: 44).background(Palette.surface, in: Circle()).overlay(Circle().stroke(Palette.line, lineWidth: 1))
                    }.accessibilityLabel("Open profile and settings")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: model.name.isEmpty ? Date().formatted(.dateTime.weekday(.wide).month().day()) : "Hello, \(model.name)")
                    Text("Make room\nfor a better walk.").font(.system(.largeTitle, design: .serif).weight(.medium)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
                if geometry.size.width >= 740 {
                    HStack(alignment: .top, spacing: 22) { VStack(spacing: 22) { airCard; exploreCard }; VStack(spacing: 22) { weekCard; symptomCard } }
                } else { airCard; weekCard; exploreCard; symptomCard }
                InfoNote(text: "Estimates support awareness. They do not diagnose symptoms or guarantee a route is safe.")
            }
        }
        .adaptiveNavigationBar()
        .sheet(isPresented: $addingSymptom) { SymptomEditor(model: model, entry: SymptomEntry()) }
    }
    private var airCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("AIR AROUND YOU", systemImage: "location.fill").font(.system(.caption2, design: .monospaced).weight(.medium)).tracking(1.3)
                Spacer()
                Button { Task { await model.refreshAir() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44).background(.white.opacity(0.07), in: Circle()) }
                    .accessibilityLabel("Refresh current air quality").disabled(model.busy || model.demo)
            }.foregroundStyle(.white.opacity(0.85))
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 18) { airReading; AirQualityDial(reading: model.air) }
                } else {
                    HStack(spacing: 8) { airReading.frame(maxWidth: .infinity, alignment: .leading); AirQualityDial(reading: model.air) }
                }
            }
            HStack(spacing: 6) {
                Circle().fill(model.air == nil ? Color.white.opacity(0.4) : Palette.lime).frame(width: 5, height: 5)
                Text(sourceLabel).font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            Button { model.section = .routes } label: {
                HStack { Image(systemName: "figure.walk"); Text(model.activeRoute == nil ? "Plan your next walk" : "Return to your walk"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.subheadline.weight(.semibold)).padding(16).foregroundStyle(Palette.deep).background(Palette.lime, in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(PressStyle())
            if model.busy { ProgressView("Updating…").tint(Palette.lime).foregroundStyle(.white) }
        }.padding(22).background { Palette.deep.overlay(ContourTexture()).clipShape(RoundedRectangle(cornerRadius: 28)) }
    }
    private var airReading: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(model.air?.label ?? "Not connected").font(.title3.weight(.medium)).foregroundStyle(Palette.lime)
            if let air = model.air {
                Text(air.pm25, format: .number.precision(.fractionLength(1))).font(.system(.largeTitle, design: .rounded).weight(.medium)).foregroundStyle(.white)
                Text("µg/m³ · PM2.5").font(.caption).foregroundStyle(.white.opacity(0.75))
            } else {
                Text("Your air.\nIn perspective.").font(.system(.title, design: .serif)).foregroundStyle(.white)
                Button("Enable location") { model.location.request() }.font(.caption.weight(.semibold)).foregroundStyle(Palette.lime).padding(.vertical, 8)
            }
        }.accessibilityElement(children: .contain)
    }
    private var sourceLabel: String {
        guard let air = model.air else { return "No live reading · add your data connection in You" }
        return air.demo ? "DEMO · illustrative data" : "OpenWeather · \(air.date.formatted(.dateTime.hour().minute())) · \(air.isFresh ? "recent" : "stale")"
    }
    private var weekCard: some View {
        Surface {
            HStack {
                SectionHeading(title: "Your week")
                Button { model.section = .journal } label: { Image(systemName: "arrow.up.right").frame(width: 44, height: 44) }.accessibilityLabel("View walking journal")
            }
            HStack(spacing: 14) {
                stat(value: "\(weekTrips.count)", label: "walks recorded", symbol: "figure.walk")
                Rectangle().fill(Palette.line).frame(width: 1, height: 38)
                stat(value: String(format: "%.1f", weekTrips.reduce(0) { $0 + $1.metres }/1000), label: "kilometres", symbol: "point.topleft.down.to.point.bottomright.curvepath")
            }
            if weekTrips.contains(where: { $0.dose != nil }) {
                Chart(weekTrips) { trip in
                    if let dose = trip.dose { BarMark(x: .value("Day", trip.date, unit: .day), y: .value("Recorded dose µg", dose)).cornerRadius(4).foregroundStyle(Palette.forest.gradient) }
                }.chartYAxis { AxisMarks(position: .leading) }.frame(height: 115)
                Text("Recorded exposure only · partial coverage may understate dose").font(.caption2).foregroundStyle(Palette.muted)
            } else {
                VStack(spacing: 14) {
                    HStack(alignment: .bottom, spacing: 9) {
                        ForEach(0..<7) { index in
                            VStack(spacing: 9) {
                                RoundedRectangle(cornerRadius: 3).fill(Palette.forest.opacity(0.06)).frame(height: 30)
                                    .overlay(alignment: .bottom) { RoundedRectangle(cornerRadius: 3).fill(Palette.forest.opacity(0.17)).frame(height: 3) }
                                Text(dayLabel(index)).font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted)
                            }
                        }
                    }.accessibilityHidden(true)
                    Text("Your first walk will start the picture.").font(.caption).foregroundStyle(Palette.muted)
                }.padding(.top, 8)
            }
        }
    }
    private func stat(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) { Text(value).font(.system(.title, design: .rounded).weight(.medium)).monospacedDigit(); Image(systemName: symbol).font(.caption).foregroundStyle(Palette.forest) }
            Text(label).font(.caption).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Palette.ink).accessibilityElement(children: .combine)
    }
    private func dayLabel(_ offset: Int) -> String {
        Calendar.current.date(byAdding: .day, value: offset - 6, to: Date())!.formatted(.dateTime.weekday(.abbreviated))
    }
    private var exploreCard: some View {
        Button { model.section = .routes } label: {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Find your way")
                    Text("Time, distance.\nAnd a little more.").font(.system(.title3, design: .serif)).foregroundStyle(Palette.ink)
                    Label("Compare a walk", systemImage: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.forest)
                }.frame(maxWidth: .infinity, alignment: .leading)
                RouteArtwork().frame(width: 112, height: 135).clipShape(RoundedRectangle(cornerRadius: 19)).rotationEffect(.degrees(4))
            }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line, lineWidth: 0.7))
        }.buttonStyle(PressStyle())
    }
    private var symptomCard: some View {
        Button { addingSymptom = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "heart.text.clipboard").font(.title3).foregroundStyle(Palette.ink).frame(width: 46, height: 46).background(Palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) { Text("A moment to check in").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink); Text("How are you feeling today?").font(.caption).foregroundStyle(Palette.muted) }
                Spacer(minLength: 2); Image(systemName: "plus").foregroundStyle(Palette.ink)
            }.padding(18).background(Palette.lavender, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(PressStyle())
    }
}
