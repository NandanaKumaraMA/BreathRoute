import SwiftUI

enum Palette {
    static let ink = Color(red: 0.08, green: 0.23, blue: 0.22)
    static let forest = Color(red: 0.08, green: 0.39, blue: 0.32)
    static let lime = Color(red: 0.84, green: 0.94, blue: 0.61)
    static let canvas = Color(uiColor: .systemGroupedBackground)
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}
struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) { content }.padding(20).frame(maxWidth: 1000).frame(maxWidth: .infinity) }
            .background(Palette.canvas)
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(.secondary) }
}
struct PrimaryButton: View {
    let title: String
    var symbol = "arrow.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9) }
            .buttonStyle(.borderedProminent).tint(Palette.forest).controlSize(.large)
    }
}
struct InfoNote: View {
    var symbol = "info.circle"
    let text: String
    var body: some View { Label(text, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
struct Metric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
func doseText(_ value: Double?) -> String { value.map { String(format: "%.1f µg", $0) } ?? "Unavailable" }
