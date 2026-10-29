import SwiftUI

/// Turns dose numbers into a verdict people can read at a glance.
/// Only routes with complete, valid data are compared; anything else says so honestly.
enum ExposureLevel {
    case lowest, similar, higher, unknown

    var title: String {
        switch self {
        case .lowest: "Lowest exposure"
        case .similar: "Similar exposure"
        case .higher: "Higher exposure"
        case .unknown: "Not enough air data"
        }
    }
    var symbol: String {
        switch self {
        case .lowest: "leaf.fill"
        case .similar: "equal.circle"
        case .higher: "arrow.up.circle"
        case .unknown: "questionmark.circle"
        }
    }
    var tint: Color {
        switch self {
        case .lowest: Palette.forest
        case .similar, .unknown: Palette.muted
        case .higher: Color(hex: 0xB34C46)
        }
    }

    static func level(for route: WalkRoute, in routes: [WalkRoute], ventilation: Double) -> ExposureLevel {
        func complete(_ r: WalkRoute) -> Double? {
            let e = r.sampledEstimate(ventilation: ventilation)
            guard e.isComplete, let dose = e.observedDose, dose.isFinite, dose >= 0 else { return nil }
            return dose
        }
        guard let mine = complete(route) else { return .unknown }
        let doses = routes.compactMap(complete)
        guard doses.count >= 2, let low = doses.min(), let high = doses.max() else { return .unknown }
        let tolerance = max(0.1, high * 0.01)
        if high - low <= tolerance { return .similar }
        return mine - low <= tolerance ? .lowest : .higher
    }
}

struct RouteChoiceCard: View {
    let route: WalkRoute
    let routes: [WalkRoute]
    let ventilation: Double
    let selected: Bool
    let action: () -> Void

    private var level: ExposureLevel { .level(for: route, in: routes, ventilation: ventilation) }
    private var minutes: Int { Int((route.seconds / 60).rounded()) }
    private var timeNote: String {
        guard let fastest = routes.map(\.seconds).min() else { return "" }
        let extra = Int(((route.seconds - fastest) / 60).rounded())
        return extra <= 0 ? "Fastest" : "+\(extra) min"
    }
    private var coverage: Double { route.sampledEstimate(ventilation: ventilation).coverage }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(route.name.isEmpty ? "Walking route" : route.name)
                        .font(.headline).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(Palette.forest)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(minutes) min").font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                    Text(timeNote).font(.subheadline).foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                    Text(String(format: "%.1f km", route.metres / 1000)).font(.subheadline).foregroundStyle(Palette.muted)
                }.foregroundStyle(Palette.ink)
                StatusPill(title: level.title, symbol: level.symbol, tint: level.tint)
                HStack {
                    if coverage < 0.999 && level != .unknown {
                        Text("Based on partial air data").font(.caption).foregroundStyle(Palette.muted)
                    } else if route.demo {
                        Text("Example route").font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Text("Details").font(.caption.weight(.semibold)).foregroundStyle(Palette.forest)
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Palette.forest)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Palette.forest : Palette.line, lineWidth: selected ? 1.5 : 0.7))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(route.name.isEmpty ? "Walking route" : route.name), \(minutes) minutes, \(timeNote), \(String(format: "%.1f", route.metres / 1000)) kilometres. \(level.title).")
        .accessibilityHint("Shows details and alternatives")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
