import SwiftUI

struct WalkAwarenessView: View {
    @Bindable var model: AppModel
    var tool: WalkTool? = nil
    @State private var enabling = false
    @State private var requestAvoidance = true
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if tool == nil || tool == .geofencing {
            Surface {
                Label("Geofencing · area alerts", systemImage: "location.circle").font(.headline).foregroundStyle(Palette.ink)
                Text("Optional entry awareness for fresh AQI 3–5 samples. Monitoring areas use a 250 m app-defined radius; they are not measured pollution boundaries.").font(.caption).foregroundStyle(Palette.muted)
                Text(model.geofences.message).font(.caption).foregroundStyle(Palette.muted)
                if model.geofences.enabled {
                    Button("Turn off area alerts") { model.geofences.stop() }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    if !model.geofences.hasAlwaysAccess && !model.geofences.areas.isEmpty {
                        Button("Allow native region awareness") { model.geofences.requestBackgroundAwareness() }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        Text("Requests Always location access. Region delivery can be delayed or unavailable. This does not enable background walk recording or session recovery.").font(.caption2).foregroundStyle(Palette.muted)
                    }
                } else {
                    Button(enabling ? "Enabling…" : "Enable area-entry alerts") {
                        enabling = true
                        Task { await model.geofences.enable(samples: model.watchSamples); enabling = false; if let location = model.location.currentLocation { model.geofences.evaluate(location) } }
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(enabling)
                }
                if let area = model.geofences.entry, let time = model.geofences.entryTime {
                    Divider()
                    Label("Inside a sampled area", systemImage: "wind").font(.subheadline.weight(.semibold))
                    Text("PM2.5 \(String(format: "%.1f", area.pm25)) µg/m³ · overall AQI \(area.aqi)/5. Sample \(area.sampledAt.formatted(date: .omitted, time: .shortened)); entry \(time.formatted(date: .omitted, time: .shortened)).").font(.caption).foregroundStyle(Palette.muted)
                    Button("Dismiss area message") { model.geofences.clearEntry() }.font(.caption).frame(minHeight: 44)
                }
            }
            }
            if tool == nil || tool == .rerouting {
            Surface {
                SectionHeading(title: "Rerouting · compare from here")
                Text("Request fresh options for the remaining journey. Choosing a new route preserves the time, distance and exposure already recorded.").font(.caption).foregroundStyle(Palette.muted)
                Picker("Extra-time budget", selection: $model.extraMinutes) {
                    Text("5 min").tag(5.0); Text("10 min").tag(10.0); Text("20 min").tag(20.0)
                }.pickerStyle(.segmented)
                Toggle("Request an area-avoidance option", isOn: $requestAvoidance).font(.caption)
                Text("Avoidance requires openrouteservice. Areas containing your start or destination are omitted. A detour can increase estimated dose.").font(.caption2).foregroundStyle(Palette.muted)
                PrimaryButton(title: model.remainingBusy ? "Comparing remaining routes…" : "Compare remaining walk", symbol: "arrow.triangle.branch") { model.compareRemaining(avoidAreas: requestAvoidance) }.disabled(model.remainingBusy)
                if model.remainingBusy { ProgressView("Routes and new air samples…").font(.caption) }
            }
            if let notice = model.remainingNotice { InfoNote(text: notice) }
            ForEach(model.remainingOptions) { route in
                Surface {
                    HStack { Text(route.name).font(.headline).foregroundStyle(Palette.ink); Spacer(); if route.id.uuidString == model.bestRemainingRouteID { StatusPill(title: "Lower estimated dose", symbol: "wind") } }
                    HStack { Metric(title: "Remaining time", value: "\(Int(route.seconds / 60)) min"); Metric(title: "Distance", value: String(format: "%.2f km", route.metres / 1000)); Metric(title: route.estimate.isComplete ? "Estimated dose" : "Partial dose", value: doseText(route.estimate.observedDose)) }
                    Text("\(Int(route.estimate.coverage * 100))% sampled coverage · \(route.source)").font(.caption2).foregroundStyle(Palette.muted)
                    if route.avoidedAreaCount > 0 { Text("Returned geometry checked against \(route.avoidedAreaCount) excluded sample areas.").font(.caption).foregroundStyle(Palette.forest) }
                    if let fastest = model.remainingOptions.map(\.seconds).min(), route.seconds > fastest + model.extraMinutes * 60 {
                        Text("Exceeds your extra-time budget.").font(.caption).foregroundStyle(Palette.muted)
                    }
                    Button("Switch remaining route") { model.switchRemaining(to: route) }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
            }
            if !model.remainingOptions.isEmpty {
                InfoNote(text: model.bestRemainingRouteID == nil ? "No distinct lower-dose recommendation with comparable complete data inside your time budget. Review the available options." : "Recommendation compares complete sampled estimates inside your extra-time budget. The difference may reflect duration, not cleaner streets. No route is guaranteed safe.")
            }
            }
        }
    }
}
