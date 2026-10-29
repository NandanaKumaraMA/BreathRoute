import SwiftUI

enum WalkTool: String, Identifiable, CaseIterable {
    case geofencing = "Geofencing", rerouting = "Rerouting"
    var id: String { rawValue }
    var symbol: String { self == .geofencing ? "location.circle" : "arrow.triangle.branch" }
}

struct WalkToolsLauncher: View {
    @Bindable var model: AppModel
    let open: (WalkTool) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize { VStack(spacing: 10) { buttons } }
        else { HStack(spacing: 10) { buttons } }
    }
    @ViewBuilder private var buttons: some View {
        ForEach(WalkTool.allCases) { tool in
            Button { open(tool) } label: {
                HStack(spacing: 10) {
                    Image(systemName: tool.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.forest)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text(status(tool)).font(.caption2).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, lineWidth: 0.7))
            }.buttonStyle(PressStyle()).accessibilityLabel("\(tool.rawValue), \(status(tool)). Open controls")
        }
    }
    private func status(_ tool: WalkTool) -> String {
        guard model.activeRoute?.demo == false else { return "Setup & preview" }
        return tool == .geofencing ? (model.geofences.enabled ? "Alerts on" : "Alerts off") : "Compare from here"
    }
}

struct WalkToolsSheet: View {
    let tool: WalkTool
    @Bindable var model: AppModel
    let configure: () -> Void
    let plan: () -> Void
    @State private var showPreview = false
    @Environment(\.dismiss) private var dismiss
    private var liveWalk: Bool { model.activeRoute?.demo == false }

    var body: some View {
        NavigationStack {
            Page {
                PageHeader(title: tool == .geofencing ? "Area alerts." : "Reroute ahead.", subtitle: tool.rawValue, symbol: tool.symbol)
                if liveWalk {
                    WalkAwarenessView(model: model, tool: tool)
                } else {
                    Surface {
                        StatusPill(title: model.activeRoute?.demo == true ? "Demo walk active" : "Before your walk", symbol: "figure.walk")
                        Text(tool == .geofencing
                             ? "Monitor 250 m AQI 3–5 sample areas with a 5-minute alert cooldown during a live walk."
                             : "Compare remaining routes and request detours around poorer-air areas during a live walk.")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                        if tool == .rerouting {
                            Picker("Extra-time budget", selection: $model.extraMinutes) {
                                Text("5 min").tag(5.0); Text("10 min").tag(10.0); Text("20 min").tag(20.0)
                            }.pickerStyle(.segmented)
                        }
                        Divider()
                        setupRow("OpenWeather", ready: !KeyStore.read("openweather").isEmpty)
                        setupRow("openrouteservice", ready: !KeyStore.read("openrouteservice").isEmpty)
                        HStack {
                            Button("Configure keys", action: configure).font(.subheadline.weight(.semibold))
                            Spacer()
                            if model.activeRoute == nil {
                                Button(model.selected?.demo == false ? "Return to route" : "Plan a walk", action: plan).font(.subheadline.weight(.semibold))
                            }
                        }.frame(minHeight: 40)
                    }
                }
                Surface {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Interactive preview", systemImage: "play.circle").font(.headline).foregroundStyle(Palette.ink)
                            Text("Test entry, comparison & switching with synthetic data.").font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                    }
                    PrimaryButton(title: "Open interactive preview", symbol: "play.fill") { showPreview = true }
                }
            }
            .navigationTitle(tool.rawValue).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showPreview) { WalkToolsDemoView() }
        }
        .presentationDetents([.large])
    }

    private func setupRow(_ name: String, ready: Bool) -> some View {
        HStack {
            Label(name, systemImage: ready ? "checkmark.circle.fill" : "circle")
            Spacer()
            Text(ready ? "Ready" : "Key needed").font(.caption)
        }.font(.subheadline).foregroundStyle(ready ? Palette.forest : Palette.muted).accessibilityElement(children: .combine)
    }
}
