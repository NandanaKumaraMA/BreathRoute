import SwiftUI

/// The awareness controls belong to the planned walk, rather than separate tool screens.
struct WalkAwarenessView: View {
    @Bindable var model: AppModel
    @State private var requestingNotifications = false
    private var active: Bool { model.activeRoute != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Surface(padding: 16) {
                Label(active ? "Walk monitoring is on" : "Included in your walk", systemImage: "location.shield")
                    .font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                Label(active ? "Air coverage shown on your map" : "Air samples and route comparison", systemImage: "aqi.medium")
                    .font(.subheadline).foregroundStyle(Palette.forest)
                Label(active ? "Geofencing · \(model.geofences.areas.count) monitored areas" : "Geofencing starts with your walk", systemImage: "location.circle")
                    .font(.subheadline).foregroundStyle(Palette.ink)
                Text(active ? model.geofences.message : "\(model.plannedWatchAreaCount) fresh higher-AQI areas on this path. Area entries and route departures will trigger a comparison automatically.")
                    .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if active {
                    Label(model.automaticRouteChecks ? "Automatic reroute suggestions on" : "Automatic reroute suggestions paused", systemImage: "arrow.triangle.branch")
                        .font(.subheadline).foregroundStyle(Palette.ink)
                    Text(model.routeCheckMessage).font(.caption).foregroundStyle(Palette.muted)
                    if let area = model.geofences.entry {
                        Divider()
                        Label("Inside a higher-AQI sample area", systemImage: "wind").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text("AQI \(area.aqi)/5 · PM2.5 \(area.pm25.formatted(.number.precision(.fractionLength(1)))) µg/m³. Sampled \(area.sampledAt.formatted(date: .omitted, time: .shortened)).")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    if model.remainingBusy { ProgressView("Comparing remaining paths and air samples…").font(.caption) }
                    else if model.remainingOptions.isEmpty {
                        Button("Compare routes from here", systemImage: "arrow.triangle.branch") { model.compareRemaining(avoidAreas: true) }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }
                }
                DisclosureGroup("Walk preferences") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Automatic reroute suggestions", isOn: $model.automaticRouteChecks).font(.subheadline)
                        Text("Compare after entering a sampled area or leaving the path. You choose whether to switch.").font(.caption).foregroundStyle(Palette.muted)
                        Text("Extra walking time").font(.caption.weight(.semibold))
                        Picker("Extra-time budget", selection: $model.extraMinutes) {
                            Text("5 min").tag(5.0); Text("10 min").tag(10.0); Text("20 min").tag(20.0)
                        }.pickerStyle(.segmented)
                        if active && model.activeRoute?.demo == false {
                            if !model.geofences.notificationAllowed {
                                Button(requestingNotifications ? "Requesting…" : "Allow area notifications") {
                                    requestingNotifications = true
                                    Task { await model.geofences.requestNotifications(); requestingNotifications = false }
                                }.frame(minHeight: 44).disabled(requestingNotifications)
                            }
                            if !model.geofences.hasAlwaysAccess {
                                Button("Allow background area awareness") { model.geofences.requestBackgroundAwareness() }.frame(minHeight: 44)
                                Text("Optional Always location permission for native region events. Background walk recording is not enabled.").font(.caption2).foregroundStyle(Palette.muted)
                            }
                        }
                        Text("Circles are approximate 250 m sample areas, not measured pollution boundaries. Missing or expired readings remain unknown.")
                            .font(.caption2).foregroundStyle(Palette.muted)
                    }.padding(.top, 12)
                }.font(.subheadline.weight(.medium))
            }
            if let notice = model.remainingNotice { InfoNote(text: notice) }
            if !model.remainingOptions.isEmpty {
                SectionHeading(title: "Choose your remaining path")
                ForEach(model.remainingOptions) { route in
                    Surface(padding: 16) {
                        Text(route.name).font(.headline).foregroundStyle(Palette.ink)
                        if route.id.uuidString == model.bestRemainingRouteID { StatusPill(title: "Lower estimated dose", symbol: "wind") }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) { metrics(route) }
                            VStack(alignment: .leading, spacing: 10) { metrics(route) }
                        }
                        Text("\(Int(route.estimate.coverage * 100))% sampled coverage · \(route.sourceLabel)").font(.caption).foregroundStyle(Palette.muted)
                        if let fastest = model.remainingOptions.map(\.seconds).min(), route.seconds > fastest + model.extraMinutes * 60 {
                            Text("Exceeds your extra-time budget.").font(.caption).foregroundStyle(Palette.muted)
                        }
                        if route.avoidedAreaCount > 0 && !route.excludedAreas.isEmpty {
                            Text("Path checked against \(route.avoidedAreaCount) excluded sample areas.").font(.caption).foregroundStyle(Palette.forest)
                        }
                        PrimaryButton(title: "Use this remaining path", symbol: "arrow.triangle.turn.up.right.diamond") { model.switchRemaining(to: route) }
                    }
                }
                Button("Keep my current path") { model.dismissRemainingOptions() }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                Text("Recommendations require comparable complete samples within your time budget. A detour can increase exposure; no route is guaranteed safe.")
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
        }
    }
    @ViewBuilder private func metrics(_ route: WalkRoute) -> some View {
        Metric(title: "Remaining", value: "\(Int(route.seconds / 60)) min")
        Metric(title: "Distance", value: String(format: "%.2f km", route.metres / 1000))
        Metric(title: route.estimate.isComplete ? "Est. dose" : "Partial dose", value: doseText(route.estimate.observedDose))
    }
}
