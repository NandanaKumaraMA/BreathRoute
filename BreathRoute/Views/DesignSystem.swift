import SwiftUI

private struct AdaptiveNavigationBar: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        // Keep the system sidebar toggle reachable after the iPad sidebar closes.
        content.toolbar(sizeClass == .regular ? .visible : .hidden, for: .navigationBar)
    }
}

extension View {
    func adaptiveNavigationBar() -> some View { modifier(AdaptiveNavigationBar()) }
}

enum Palette {
    static let ink = adaptive(light: 0x183A33, dark: 0xE4EEE7)
    static let forest = adaptive(light: 0x215E4D, dark: 0x94D6B9)
    static let deep = Color(hex: 0x183E35)
    static let lime = Color(hex: 0xDBEDA3)
    static let canvas = adaptive(light: 0xF5F6F0, dark: 0x141E1A)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x202D26)
    static let line = adaptive(light: 0xE3E8DF, dark: 0x39473E)
    static let lavender = adaptive(light: 0xEEEBF8, dark: 0x342E46)
    static let muted = adaptive(light: 0x66736A, dark: 0xADBBB1)
    static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light) })
    }
}
private extension UIColor {
    convenience init(rgb: UInt) { self.init(red: CGFloat((rgb >> 16) & 255)/255, green: CGFloat((rgb >> 8) & 255)/255, blue: CGFloat(rgb & 255)/255, alpha: 1) }
}
extension Color {
    init(hex: UInt) { self.init(red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255) }
}

struct Surface<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line.opacity(0.7), lineWidth: 0.7))
    }
}
struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) { content }.padding(22).padding(.bottom, 20).frame(maxWidth: 1060).frame(maxWidth: .infinity) }
            .background(Palette.canvas).scrollIndicators(.hidden)
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(.caption2, design: .monospaced).weight(.medium)).tracking(1.7).foregroundStyle(Palette.muted) }
}
struct PrimaryButton: View {
    let title: String
    var symbol = "arrow.up.right"
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) { Text(title); Spacer(); Image(systemName: symbol) }
                .font(.headline).padding(.horizontal, 20).padding(.vertical, 18)
                .foregroundStyle(Palette.lime).frame(maxWidth: .infinity)
                .background(Palette.deep.opacity(enabled ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(PressStyle()).accessibilityElement(children: .combine)
    }
}
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
struct InfoNote: View {
    var symbol = "info.circle"
    let text: String
    var body: some View { Label(text, systemImage: symbol).font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true) }
}
struct Metric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink)
            Text(title).font(.caption).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
struct StatusPill: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = Palette.forest
    var body: some View {
        HStack(spacing: 5) { if let symbol { Image(systemName: symbol) }; Text(title) }
            .font(.caption2.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(tint).background(tint.opacity(0.09), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}
struct SectionHeading: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) { Text(title).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink); Spacer(); if let detail { Text(detail).font(.caption).foregroundStyle(Palette.muted) } }
    }
}
struct BrandMark: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3).fill(Palette.deep)
            Image(systemName: "leaf.fill").font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(Palette.lime)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
struct PageHeader: View {
    let title: String
    let subtitle: String
    var symbol: String = "leaf"
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) { Eyebrow(text: subtitle); Text(title).font(.system(.largeTitle, design: .serif).weight(.medium)).foregroundStyle(Palette.ink) }
            Spacer(minLength: 4)
            Image(systemName: symbol).font(.title3).foregroundStyle(Palette.forest).frame(width: 48, height: 48).background(Palette.surface, in: Circle()).overlay(Circle().stroke(Palette.line, lineWidth: 1)).accessibilityHidden(true)
        }
    }
}

/// Decorative topographic contours; never represents measured pollution or a map.
struct ContourTexture: View {
    var color: Color = .white.opacity(0.1)
    var body: some View {
        Canvas { context, size in
            for index in 0..<12 {
                let rx = size.width * (0.2 + Double(index) * 0.06)
                let ry = size.height * (0.2 + Double(index) * 0.085)
                var path = Path()
                for step in 0...100 {
                    let angle = Double(step) / 100 * .pi * 2
                    let wobble = 1 + 0.1 * sin(angle * 3 + Double(index) * 0.12)
                    let point = CGPoint(x: size.width * 0.83 + cos(angle) * rx * wobble,
                                        y: size.height * 0.5 + sin(angle) * ry * wobble)
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(color), lineWidth: 0.75)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct AirQualityDial: View {
    let reading: AirReading?
    var body: some View {
        ZStack {
            ForEach(0..<5) { index in
                Circle().trim(from: Double(index)*0.15 + 0.015, to: Double(index+1)*0.15 - 0.015)
                    .stroke(reading?.aqi == index + 1 ? Palette.lime : Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(135))
            }
            Circle().stroke(.white.opacity(0.1), lineWidth: 1).padding(17)
            VStack(spacing: 3) {
                if let reading {
                    Text("\(reading.aqi)").font(.system(size: 42, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("OF 5 AQI").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.2)
                } else {
                    Image(systemName: "wind").font(.system(size: 32, weight: .light))
                    Text("NO READING").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(0.5)
                }
            }.foregroundStyle(Palette.lime)
        }.frame(width: 128, height: 128).accessibilityLabel(reading.map { "OpenWeather AQI \($0.aqi) of 5, \($0.label)" } ?? "No air-quality reading available")
    }
}

/// A vector illustration for onboarding and empty states, not a geographic route.
struct RouteArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            ZStack {
                Color(hex: 0xE7EDDF)
                Canvas { context, size in
                    let parks = [CGRect(x: size.width*0.5, y: 0, width: size.width*0.3, height: size.height*0.45), CGRect(x: 0, y: size.height*0.55, width: size.width*0.4, height: size.height*0.5)]
                    for rect in parks { context.fill(Path(roundedRect: rect, cornerRadius: 28), with: .color(Color(hex: 0xC9DDB3))) }
                    for i in 0..<7 {
                        var p = Path(); p.move(to: CGPoint(x: -20, y: Double(i)*size.height/5)); p.addLine(to: CGPoint(x: size.width+20, y: Double(i)*size.height/5-50))
                        context.stroke(p, with: .color(.white.opacity(0.75)), lineWidth: 12)
                    }
                    for i in 0..<7 {
                        var p = Path(); p.move(to: CGPoint(x: Double(i)*size.width/5, y: -40)); p.addLine(to: CGPoint(x: Double(i)*size.width/5+50, y: size.height+40))
                        context.stroke(p, with: .color(.white.opacity(0.75)), lineWidth: 10)
                    }
                    var route = Path(); route.move(to: CGPoint(x: size.width*0.15, y: size.height*0.8))
                    route.addCurve(to: CGPoint(x: size.width*0.75, y: size.height*0.23), control1: CGPoint(x: size.width*0.1, y: size.height*0.1), control2: CGPoint(x: size.width*0.62, y: size.height*0.8))
                    context.stroke(route, with: .color(.white), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    context.stroke(route, with: .color(Palette.deep), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 5]))
                }
                Image(systemName: "figure.walk").font(.caption.bold()).foregroundStyle(Palette.deep).frame(width: 30, height: 30).background(.white, in: Circle()).shadow(color: .black.opacity(0.12), radius: 6, y: 3).position(x: w*0.15, y: h*0.8)
                Image(systemName: "leaf.fill").font(.caption).foregroundStyle(Palette.deep).frame(width: 36, height: 36).background(Palette.lime, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 3)).position(x: w*0.75, y: h*0.23)
            }.clipped()
        }.accessibilityHidden(true)
    }
}
func doseText(_ value: Double?) -> String { value.map { String(format: "%.1f µg", $0) } ?? "Unavailable" }
