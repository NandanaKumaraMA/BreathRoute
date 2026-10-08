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
        if typeSize.isAccessibilitySize { VStack(spacing: 12) { buttons } }
        else { HStack(spacing: 12) { buttons } }
    }
    @ViewBuilder private var buttons: some View {
        ForEach(WalkTool.allCases) { tool in
            Button { open(tool) } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Image(systemName: tool.symbol).font(.title3).foregroundStyle(Palette.forest)
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.muted)
                    }
                    Text(tool.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(status(tool)).font(.caption2).foregroundStyle(Palette.muted)
                }.padding(14).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 19))
                    .overlay(RoundedRectangle(cornerRadius: 19).stroke(Palette.line, lineWidth: 0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }.buttonStyle(PressStyle()).accessibilityLabel("\(tool.rawValue), \(status(tool)). Open controls")
        }
    }
    private func status(_ tool: WalkTool) -> String {
        guard model.activeRoute?.demo == false else { return "Setup & preview" }
        return tool == .geofencing ? (model.geofences.enabled ? "Area alerts on" : "Area alerts off") : "Compare from here"
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
                PageHeader(title: tool == .geofencing ? "Know when you enter." : "A fresh way forward.", subtitle: tool.rawValue, symbol: tool.symbol)
                Text(tool == .geofencing ? "Review sampled air-quality areas and choose optional entry alerts for a live walk." : "Compare your remaining journey, review the trade-offs and choose whether to switch paths.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                if liveWalk {
                    WalkAwarenessView(model: model, tool: tool)
                } else {
                    Surface {
                        StatusPill(title: model.activeRoute?.demo == true ? "Example walk is open" : "Before your walk", symbol: "figure.walk")
                        Text(tool == .geofencing ? "Live geofencing starts with a real route." : "Live rerouting starts during a real walk.").font(.headline).foregroundStyle(Palette.ink)
                        Text(model.activeRoute?.demo == true ? "The current example walk has no live GPS or air samples. You can preview the workflow below. Finish the example walk before starting a live one." : "Connect air and routing data, choose a destination, compare routes, then start a walk. These controls will use its current location and fresh samples.")
                            .font(.caption).foregroundStyle(Palette.muted)
                        setupRow("OpenWeather", ready: !KeyStore.read("openweather").isEmpty)
                        setupRow("openrouteservice", ready: !KeyStore.read("openrouteservice").isEmpty)
                        Button("Configure data connections", action: configure).font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        if model.activeRoute == nil {
                            PrimaryButton(title: model.selected?.demo == false ? "Return to your planned walk" : "Plan a live walk", symbol: "figure.walk", action: plan)
                        }
                    }
                    Surface {
                        SectionHeading(title: tool == .geofencing ? "Area-alert settings" : "Remaining-route options")
                        if tool == .geofencing {
                            LabeledContent("Monitoring radius", value: "250 m")
                            LabeledContent("Eligible overall AQI", value: "3–5")
                            LabeledContent("Alert cooldown", value: "5 minutes")
                            Text("Circles are approximate sample areas. Freshness and location accuracy are checked before an entry message. Always access is optional for native region events.").font(.caption).foregroundStyle(Palette.muted)
                        } else {
                            Picker("Extra-time budget", selection: $model.extraMinutes) {
                                Text("5 min").tag(5.0); Text("10 min").tag(10.0); Text("20 min").tag(20.0)
                            }.pickerStyle(.segmented)
                            Text("During a live walk you can compare from your location, request an area-avoidance option and explicitly switch the remaining route. Completed recording stays intact.").font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }
                Surface {
                    Label("Try the feature flow", systemImage: "play.circle").font(.headline).foregroundStyle(Palette.ink)
                    Text("An interactive example of area entry, route comparison and switching, using clearly labelled synthetic data.").font(.caption).foregroundStyle(Palette.muted)
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
        HStack { Label(name, systemImage: ready ? "checkmark.circle.fill" : "circle"); Spacer(); Text(ready ? "Key saved" : "Key needed").font(.caption) }.font(.subheadline).foregroundStyle(ready ? Palette.forest : Palette.muted).accessibilityElement(children: .combine)
    }
}
