import SwiftUI

/// Today: one answer ("how is the air?"), one action ("plan a walk"), everything else quiet.
struct DashboardView: View {
    @Bindable var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var addingSymptom = false
    @State private var showDepartureForecast = false

    private var weekTrips: [TripEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        return model.trips.filter { !$0.demo && $0.date >= start }
    }

    var body: some View {
        Page {
            header
            RecoveryCard(model: model)
            hero
            weekAndActions
            Text("Estimates support awareness. They are not medical advice.")
                .font(.caption).foregroundStyle(Palette.muted)
        }
        .adaptiveNavigationBar()
        .sheet(isPresented: $addingSymptom) { SymptomEditor(model: model, entry: SymptomEntry()) }
        .sheet(isPresented: $showDepartureForecast) { ForecastEntryView(model: model) }
        .task {
            guard !model.demo, model.location.hasAuthorization else { return }
            model.location.request()
            if model.location.currentLocation != nil { await model.refreshAir(reportErrors: false) }
        }
        .onChange(of: model.location.currentLocation != nil) { _, available in
            if available, model.air == nil, !model.demo { Task { await model.refreshAir(reportErrors: false) } }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name.isEmpty ? Date().formatted(.dateTime.weekday(.wide).month().day()) : "Hello, \(model.name)")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                Text("Ready for a walk?")
                    .font(.system(.largeTitle, design: .serif).weight(.medium)).foregroundStyle(Palette.ink)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { model.section = .profile } label: {
                Text(model.name.first.map { String($0).uppercased() } ?? "You")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.forest)
                    .frame(width: 44, height: 44)
                    .background(Palette.surface, in: Circle())
                    .overlay(Circle().stroke(Palette.line, lineWidth: 1))
            }.accessibilityLabel("Open profile and settings")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(statusColour).frame(width: 10, height: 10)
                    Text(statusTag).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                }.accessibilityElement(children: .combine)
                Spacer()
                Button { Task { await model.refreshAir() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 18)).frame(width: 44, height: 44)
                }
                .foregroundStyle(.white.opacity(0.85))
                .accessibilityLabel("Refresh current air quality")
                .disabled(model.busy || model.demo)
            }
            Text(headline).font(.system(.title, design: .serif)).foregroundStyle(.white)
            Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            if model.air == nil, model.activeRoute == nil {
                Button(model.location.hasAuthorization ? "Use my current location" : "Enable location") { model.location.request() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.lime).frame(minHeight: 44)
            }
            Button { model.openWalkPlanner() } label: {
                HStack {
                    if !typeSize.isAccessibilitySize { Image(systemName: "figure.walk").accessibilityHidden(true) }
                    Text(model.activeRoute == nil ? "Plan a walk" : "Return to your walk")
                    Spacer()
                    if !typeSize.isAccessibilitySize { Image(systemName: "arrow.right").accessibilityHidden(true) }
                }
                .font(.headline).padding(.horizontal, 18).frame(minHeight: 54)
                .foregroundStyle(Palette.deep).background(Palette.lime, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(PressStyle())
            if model.busy { ProgressView("Updating…").tint(Palette.lime).foregroundStyle(.white) }
        }
        .padding(22)
        .background { Palette.deep.overlay(ContourTexture()).clipShape(RoundedRectangle(cornerRadius: 28)) }
    }

    private var weekAndActions: some View {
        Surface(padding: 8) {
            row(symbol: "chart.xyaxis.line", title: "This week",
                subtitle: weekTrips.isEmpty ? "No walks recorded yet" : "\(weekTrips.count) \(weekTrips.count == 1 ? "walk" : "walks") · \(String(format: "%.1f km", weekTrips.reduce(0) { $0 + $1.metres } / 1000))",
                disabled: false) { model.section = .journal }
            Divider().padding(.leading, 58)
            row(symbol: "clock.badge.checkmark", title: "When to walk",
                subtitle: model.activeRoute != nil ? "Available after this walk" : "Compare hourly departure times",
                disabled: model.activeRoute != nil) { showDepartureForecast = true }
            Divider().padding(.leading, 58)
            row(symbol: "heart.text.clipboard", title: "How are you feeling?",
                subtitle: "Log a private symptom note",
                disabled: false) { addingSymptom = true }
        }
    }

    private func row(symbol: String, title: String, subtitle: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: symbol).font(.headline).foregroundStyle(Palette.forest)
                    .frame(width: 38, height: 38).background(Palette.forest.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(subtitle).font(.caption).foregroundStyle(Palette.muted)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.muted).accessibilityHidden(true) }
            }
            .padding(10).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle()).disabled(disabled).accessibilityElement(children: .combine)
    }

    private var headline: String {
        if let air = model.air { return "Air is \(air.label.lowercased()) right now" }
        return "See the air before you go"
    }
    private var detail: String {
        if let notice = model.airNotice { return notice }
        if let air = model.air {
            let pm = air.pm25.formatted(.number.precision(.fractionLength(1)))
            return air.demo ? "Example data · PM2.5 \(pm) µg/m³"
                : "PM2.5 \(pm) µg/m³ · updated \(air.date.formatted(.dateTime.hour().minute()))"
        }
        return "Allow location and tap refresh, or preview clean-air routes in Explore."
    }
    private var statusTag: String {
        guard let air = model.air else { return "No live reading" }
        return air.demo ? "Example" : (air.isFresh ? "Recent reading" : "Reading is out of date")
    }
    private var statusColour: Color {
        guard let air = model.air, air.isFresh || air.demo else { return .white.opacity(0.4) }
        switch air.aqi { case 1, 2: return Palette.lime; case 3: return Color(hex: 0xE5B84B); default: return Color(hex: 0xE88A82) }
    }
}
