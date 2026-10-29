import SwiftUI

/// Today: one answer ("how is the air?"), one action ("plan a walk"), everything else quiet.
struct DashboardView: View {
    @Bindable var model: AppModel
    @State private var addingSymptom = false
    @State private var showDepartureForecast = false

    private var weekTrips: [TripEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        return model.trips.filter { !$0.demo && $0.date >= start }
    }

    var body: some View {
        Page {
            topBar
            greeting
            RecoveryCard(model: model)
            hero
            weekSummary
            moreRows
            if model.health.dailyActivity != nil { HealthActivityCard(health: model.health) }
            Text("Estimates support awareness. They are not medical advice.")
                .font(.caption).foregroundStyle(Palette.muted)
        }
        .adaptiveNavigationBar()
        .sheet(isPresented: $addingSymptom) { SymptomEditor(model: model, entry: SymptomEntry()) }
        .sheet(isPresented: $showDepartureForecast) { ForecastEntryView(model: model) }
    }

    // MARK: Header

    private var topBar: some View {
        HStack(spacing: 10) {
            BrandMark()
            Text("breathe route").font(.system(.headline, design: .rounded).weight(.semibold)).foregroundStyle(Palette.ink)
            Spacer()
            Button { model.section = .profile } label: {
                Text(model.name.first.map { String($0).uppercased() } ?? "You")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.forest)
                    .frame(width: 44, height: 44)
                    .background(Palette.surface, in: Circle())
                    .overlay(Circle().stroke(Palette.line, lineWidth: 1))
            }.accessibilityLabel("Open profile and settings")
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.name.isEmpty ? Date().formatted(.dateTime.weekday(.wide).month().day()) : "Hello, \(model.name)")
                .font(.subheadline).foregroundStyle(Palette.muted)
            Text("Ready for a walk?")
                .font(.system(.largeTitle, design: .serif).weight(.medium)).foregroundStyle(Palette.ink)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Air around you", systemImage: "location.fill")
                    .font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button { Task { await model.refreshAir() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityLabel("Refresh current air quality")
                .disabled(model.busy || model.demo)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(statusColour).frame(width: 10, height: 10)
                    Text(statusTag).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                }.accessibilityElement(children: .combine)
                Text(headline).font(.system(.title, design: .serif)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.air == nil, model.activeRoute == nil {
                Button(model.location.hasAuthorization ? "Use my current location" : "Enable location") { model.location.request() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.lime).frame(minHeight: 44)
            }
            Button { model.section = .routes } label: {
                HStack {
                    Image(systemName: "figure.walk")
                    Text(model.activeRoute == nil ? "Plan a walk" : "Return to your walk")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.headline).padding(.horizontal, 18).frame(minHeight: 56)
                .foregroundStyle(Palette.deep).background(Palette.lime, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(PressStyle())
            if model.busy { ProgressView("Updating…").tint(Palette.lime).foregroundStyle(.white) }
        }
        .padding(22)
        .background { Palette.deep.overlay(ContourTexture()).clipShape(RoundedRectangle(cornerRadius: 28)) }
    }

    private var headline: String {
        if let air = model.air { return "Air is \(air.label.lowercased()) right now" }
        return KeyStore.read("openweather").isEmpty ? "See the air before you go" : "No reading yet"
    }
    private var detail: String {
        if let air = model.air {
            let pm = air.pm25.formatted(.number.precision(.fractionLength(1)))
            return air.demo ? "Example data · PM2.5 \(pm) µg/m³"
                : "PM2.5 \(pm) µg/m³ · updated \(air.date.formatted(.dateTime.hour().minute()))"
        }
        return KeyStore.read("openweather").isEmpty
            ? "Add your OpenWeather key in You to see live air quality, or try the example walk in Explore."
            : "Allow location, then tap refresh."
    }
    private var statusTag: String {
        guard let air = model.air else { return "No live reading" }
        return air.demo ? "Example" : (air.isFresh ? "Recent reading" : "Reading is out of date")
    }
    private var statusColour: Color {
        guard let air = model.air, air.isFresh || air.demo else { return .white.opacity(0.4) }
        switch air.aqi { case 1, 2: return Palette.lime; case 3: return Color(hex: 0xE5B84B); default: return Color(hex: 0xE88A82) }
    }

    // MARK: This week

    private var weekSummary: some View {
        Button { model.section = .journal } label: {
            Surface {
                HStack {
                    Text("This week").font(.headline).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
                }
                if weekTrips.isEmpty {
                    Text("Your first walk will start the picture.").font(.subheadline).foregroundStyle(Palette.muted)
                } else {
                    HStack(spacing: 16) {
                        Metric(title: weekTrips.count == 1 ? "walk" : "walks", value: "\(weekTrips.count)")
                        Metric(title: "kilometres", value: String(format: "%.1f", weekTrips.reduce(0) { $0 + $1.metres } / 1000))
                    }
                }
            }
        }.buttonStyle(PressStyle()).accessibilityHint("Opens your journal")
    }

    // MARK: Quiet secondary actions

    private var moreRows: some View {
        Surface(padding: 4) {
            row(symbol: "clock.badge.checkmark", title: "When to walk",
                subtitle: model.activeRoute != nil ? "Available after this walk" : "Compare departure times",
                disabled: model.activeRoute != nil) { showDepartureForecast = true }
            Divider().padding(.leading, 62)
            row(symbol: "heart.text.clipboard", title: "How are you feeling?",
                subtitle: "Add a private note", disabled: false) { addingSymptom = true }
        }
    }

    private func row(symbol: String, title: String, subtitle: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Palette.forest)
                    .frame(width: 40, height: 40).background(Palette.forest.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(subtitle).font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle()).disabled(disabled).accessibilityElement(children: .combine)
    }
}
