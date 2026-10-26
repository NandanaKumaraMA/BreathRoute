import SwiftUI
import MapKit

/// Shared map layers keep route numbers, selection and air samples consistent in both maps.
struct RouteComparisonLayers: MapContent {
    let routes: [WalkRoute]
    let selectedID: UUID?
    var showAir = true
    var showSamplePins = false
    var showRouteLabels = true
    var allowSelection = true
    let select: (WalkRoute) -> Void

    private var selected: WalkRoute? { routes.first { $0.id == selectedID } }
    var body: some MapContent {
        if showAir {
            ForEach(selected?.airSamples ?? []) { sample in
                MapCircle(center: sample.coordinate, radius: 250)
                    .foregroundStyle(AirMapStyle.colour(sample.reading).opacity(0.20))
                    .stroke(AirMapStyle.colour(sample.reading).opacity(0.8), lineWidth: 1.5)
            }
        }
        // Alternatives draw first, keeping the selected line visible where paths overlap.
        ForEach(routes.filter { $0.id != selectedID }) { route in
            MapPolyline(route.polyline).stroke(RouteMapPresentation.alternative,
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [8, 5]))
        }
        if let selected {
            MapPolyline(selected.polyline).stroke(.white.opacity(0.9), lineWidth: 9)
            MapPolyline(selected.polyline).stroke(Palette.deep,
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
        if showAir && showSamplePins {
            ForEach(Array((selected?.airSamples ?? []).enumerated()), id: \.element.id) { index, sample in
                Annotation("Air sample \(index + 1)", coordinate: sample.coordinate) {
                    Text("\(index + 1)").font(.caption2.bold()).monospacedDigit()
                        .foregroundStyle(.white).frame(width: 25, height: 25)
                        .background(AirMapStyle.colour(sample.reading), in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .accessibilityLabel("Air sample \(index + 1). Details in sample list")
                }.annotationTitles(.hidden)
            }
        }
        if showRouteLabels {
            ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                if let coordinate = RouteMapPresentation.labelCoordinate(route, index: index) {
                    Annotation("Route \(index + 1)", coordinate: coordinate, anchor: .bottom) {
                        Button { select(route) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: route.id == selectedID ? "checkmark.circle.fill" : "arrow.triangle.branch")
                                Text("\(index + 1) · \(Int(route.seconds / 60)) min")
                            }.font(.caption.weight(.semibold)).foregroundStyle(route.id == selectedID ? Palette.deep : RouteMapPresentation.alternative)
                                .padding(.horizontal, 11).frame(minHeight: 44)
                                .background(.white, in: Capsule())
                                .overlay(Capsule().stroke(route.id == selectedID ? Palette.deep : RouteMapPresentation.alternative, lineWidth: 1.5))
                        }.buttonStyle(.plain).disabled(!allowSelection && route.id != selectedID)
                            .accessibilityLabel("Route \(index + 1), \(route.name), \(Int(route.seconds / 60)) minutes. Show pollution coverage and alternatives")
                            .accessibilityAddTraits(route.id == selectedID ? .isSelected : [])
                    }.annotationTitles(.hidden)
                }
            }
        }
    }
}

enum RouteMapPresentation {
    static let alternative = Color(hex: 0x7054AD)
    static func labelCoordinate(_ route: WalkRoute, index: Int) -> CLLocationCoordinate2D? {
        guard !route.coordinates.isEmpty else { return nil }
        let fraction = index.isMultiple(of: 2) ? 0.32 : 0.68
        let position = Double(route.coordinates.count - 1) * fraction
        let lower = Int(position), upper = min(route.coordinates.count - 1, lower + 1)
        let a = route.coordinates[lower], b = route.coordinates[upper], t = position - Double(lower)
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                      longitude: a.longitude + (b.longitude - a.longitude) * t)
    }
    static func bounds(_ routes: [WalkRoute]) -> MKMapRect {
        let rect = routes.reduce(MKMapRect.null) { $0.union($1.polyline.boundingMapRect) }
        guard !rect.isNull, let latitude = routes.first?.coordinates.first?.latitude else { return .world }
        let padding = MKMapPointsPerMeterAtLatitude(latitude) * 350
        return rect.insetBy(dx: -max(padding, rect.size.width * 0.25), dy: -max(padding, rect.size.height * 0.25))
    }
}

struct RouteCoverageBanner: View {
    let route: WalkRoute
    let ventilation: Double
    let inspect: () -> Void
    var body: some View {
        let estimate = route.sampledEstimate(ventilation: ventilation)
        Button(action: inspect) {
            HStack(spacing: 12) {
                Image(systemName: "aqi.medium").font(.title2).foregroundStyle(Palette.forest)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Pollution coverage & alternative paths").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("\(Int(estimate.coverage * 100))% sampled time · \(route.airSamples.count) air points\(route.demo ? " · demo" : "")")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Palette.forest)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))
        }.buttonStyle(PressStyle())
    }
}

struct RouteInspectionView: View {
    @Bindable var model: AppModel
    @State private var camera: MapCameraPosition = .automatic
    @State private var showAir = true
    @State private var showForecast = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private var selected: WalkRoute? { model.activeRoute ?? model.selected }

    var body: some View {
        NavigationStack {
            Page {
                if let route = selected {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: route.demo ? "Illustrative route · demo data" : "Your selected walking path")
                        Text(route.name.isEmpty ? "Walking route" : route.name).font(.title2.bold()).foregroundStyle(Palette.ink)
                        Text(model.activeRoute == nil ? "Choose a numbered path to compare its air samples." : "Air samples for your open walk. Remaining-path changes are available in Rerouting.")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    routePicker
                    comparisonMap(route)
                    RouteLineLegend()
                    coverage(route)
                    if model.activeRoute == nil {
                        Surface {
                            SectionHeading(title: "When to walk")
                            Text("Compare hourly forecasts and estimated dose for different departure times on this path.").font(.subheadline).foregroundStyle(Palette.muted)
                            Button("Compare departure-time forecasts", systemImage: "clock.badge.checkmark") { showForecast = true }
                                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        }
                    }
                    alternatives(route)
                    sampleList(route)
                } else {
                    ContentUnavailableView("No route selected", systemImage: "map", description: Text("Find walking routes in Explore to compare their air samples."))
                }
            }
            .navigationTitle("Route & air quality").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { fitRoutes() }
            .onChange(of: model.routes.map(\.id)) { _, _ in fitRoutes() }
            .sheet(isPresented: $showForecast) {
                if let route = selected { ForecastPlanningView(model: model, route: route.snapshot) }
            }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private var routePicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(Array(model.routes.enumerated()), id: \.element.id) { index, route in
                    Button { select(route) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: route.id == selected?.id ? "checkmark.circle.fill" : "arrow.triangle.branch")
                            Text("Route \(index + 1) · \(Int(route.seconds / 60)) min")
                        }.font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 44)
                            .foregroundStyle(route.id == selected?.id ? Palette.lime : Palette.forest)
                            .background(route.id == selected?.id ? Palette.deep : Palette.surface, in: Capsule())
                    }.buttonStyle(.plain).disabled(model.activeRoute != nil && route.id != selected?.id)
                        .accessibilityAddTraits(route.id == selected?.id ? .isSelected : [])
                }
            }
        }.scrollIndicators(.hidden)
    }
    private func comparisonMap(_ route: WalkRoute) -> some View {
        Map(position: $camera) {
            RouteComparisonLayers(routes: model.routes, selectedID: route.id, showAir: showAir, showSamplePins: true, showRouteLabels: false, select: select)
            if let first = route.coordinates.first { Marker("A · Start", coordinate: first).tint(Palette.deep) }
            if let last = route.coordinates.last { Marker("B · Destination", coordinate: last).tint(Palette.deep) }
        }.mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapScaleView() }
            .frame(height: typeSize.isAccessibilitySize ? 380 : 300)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(alignment: .bottomTrailing) {
                Button(action: fitRoutes) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.headline).frame(width: 44, height: 44).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                    .accessibilityLabel("Fit all route paths and sample areas").padding(12)
            }
    }
    private func coverage(_ route: WalkRoute) -> some View {
        let estimate = route.sampledEstimate(ventilation: model.intensity.ventilation)
        let usable = route.airSamples.filter { $0.reading?.isFresh == true }.count
        return Surface {
            SectionHeading(title: "Pollution coverage", detail: route.demo ? "Synthetic" : "API samples")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 130))], alignment: .leading, spacing: 18) {
                Metric(title: "Sampled trip time", value: "\(Int(estimate.coverage * 100))%")
                Metric(title: "Recent air points", value: "\(usable) / \(route.airSamples.count)")
                Metric(title: "Walking distance", value: String(format: "%.2f km", route.metres / 1000))
                Metric(title: estimate.isComplete ? "Estimated dose" : "Partial estimated dose", value: estimate.observedDose.map { String(format: "%.1f µg", $0) } ?? "Unavailable")
            }
            ProgressView(value: estimate.coverage).tint(Palette.forest)
            Toggle("Show pollution sample areas", isOn: $showAir).font(.subheadline)
            AirMapLegend()
            InfoNote(text: "Coverage is the share of estimated trip time assigned a usable PM2.5 sample. It does not describe the percentage of land measured. Dose assumes \(Int(model.intensity.ventilation * 1000)) L/min breathing volume.")
            if route.demo { InfoNote(symbol: "sparkles", text: "These air values and route metrics are synthetic examples. Live pollution and routing have not been requested.") }
            if route.airSamples.isEmpty { InfoNote(text: "No air points are available for this route. No pollution area or zero-exposure estimate has been invented.") }
        }
    }
    private func alternatives(_ selectedRoute: WalkRoute) -> some View {
        let options = model.routes.filter { $0.id != selectedRoute.id }
        return Surface {
            SectionHeading(title: "Alternative paths", detail: "\(options.count) available")
            if options.isEmpty {
                InfoNote(text: "The provider returned only this path. Another walking path is not guaranteed for this A–B journey.")
            } else {
                ForEach(options) { route in
                    Button { select(route) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(route.name.isEmpty ? "Alternative walking path" : route.name).font(.subheadline.weight(.semibold)); Spacer(); Image(systemName: "arrow.up.right") }
                            Text(comparison(route, with: selectedRoute)).font(.caption).foregroundStyle(Palette.muted)
                            let estimate = route.sampledEstimate(ventilation: model.intensity.ventilation)
                            Text("\(Int(estimate.coverage * 100))% sampled time · \(estimate.observedDose.map { String(format: "%.1f µg", $0) } ?? "Unavailable dose")\(estimate.isComplete ? " estimated dose" : " · incomplete")")
                                .font(.caption).foregroundStyle(Palette.muted)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(PressStyle()).foregroundStyle(Palette.forest).disabled(model.activeRoute != nil)
                }
            }
            if let notice = model.routeNotice { InfoNote(text: notice) }
            if model.activeRoute != nil {
                InfoNote(text: "This walk is already recording. Use the Rerouting controls in Explore to compare and switch the remaining path while keeping completed intervals.")
            }
            if !selectedRoute.demo && model.activeRoute == nil {
                Button { Task { await model.addAvoidanceOption() } } label: {
                    Label(model.busy ? "Finding an avoidance path…" : "Find a pollution-area avoidance path", systemImage: "arrow.triangle.branch")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }.disabled(model.busy)
                InfoNote(text: "Uses your openrouteservice connection to avoid eligible fresh AQI 3–5 sample circles. A detour may take longer or increase estimated dose.")
            }
        }
    }
    private func sampleList(_ route: WalkRoute) -> some View {
        Surface {
            SectionHeading(title: "Air points along this path")
            ForEach(Array(route.airSamples.enumerated()), id: \.element.id) { index, sample in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 30, height: 30).background(AirMapStyle.colour(sample.reading), in: Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        if let reading = sample.reading {
                            Text(String(format: "PM2.5 %.1f µg/m³", reading.pm25)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                            Text("AQI \(reading.aqi)/5 · \(reading.label)\(reading.isFresh ? "" : " · stale")").font(.caption).foregroundStyle(Palette.muted)
                            Text("\(reading.demo ? "Synthetic example" : "Provider sample") · \(reading.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(Palette.muted)
                        } else {
                            Text("Air data unavailable").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                            Text("This point contributes no estimated dose. Its interval remains missing coverage.").font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
            }
        }
    }
    private func comparison(_ route: WalkRoute, with current: WalkRoute) -> String {
        let minutes = (route.seconds - current.seconds) / 60
        let time = abs(minutes) < 0.5 ? "Similar travel time" : "\(Int(abs(minutes).rounded())) min \(minutes > 0 ? "longer" : "quicker")"
        return "\(Int(route.seconds / 60)) min · \(String(format: "%.2f km", route.metres / 1000)) · \(time)"
    }
    private func select(_ route: WalkRoute) {
        guard model.activeRoute == nil else { return }
        model.selectedRoute = route.id
    }
    private func fitRoutes() { camera = .rect(RouteMapPresentation.bounds(model.routes)) }
}

struct RouteLineLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { lines }
            VStack(alignment: .leading, spacing: 8) { lines }
        }
    }
    @ViewBuilder private var lines: some View {
        Label("Solid green: selected", systemImage: "line.diagonal").foregroundStyle(Palette.forest)
        Label("Dashed purple: alternatives", systemImage: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(RouteMapPresentation.alternative)
    }
}
