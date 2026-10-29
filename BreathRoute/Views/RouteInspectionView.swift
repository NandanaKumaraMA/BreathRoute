import SwiftUI
import MapKit

/// Shared map layers: a solid selected path, dashed alternatives, and optional air samples.
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
            ForEach(selected?.excludedAreas ?? []) { area in
                MapCircle(center: .init(latitude: area.latitude, longitude: area.longitude), radius: area.radius)
                    .foregroundStyle(Color.orange.opacity(0.05))
                    .stroke(.orange.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
            ForEach(selected?.airSamples ?? []) { sample in
                MapCircle(center: sample.coordinate, radius: 250)
                    .foregroundStyle(AirMapStyle.colour(sample.reading).opacity(0.18))
                    .stroke(AirMapStyle.colour(sample.reading).opacity(0.75), lineWidth: 1.5)
            }
        }
        // Use a distinct colour for alternatives, even when their air estimates are similar.
        ForEach(routes.filter { $0.id != selectedID }) { route in
            MapPolyline(route.polyline).stroke(
                RouteMapPresentation.alternative,
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [8, 5])
            ).mapOverlayLevel(level: .aboveRoads)
        }
        // A solid base remains visible while MapKit updates the dynamic sample segments.
        // Keep the segments above labels; a static halo can otherwise obscure them.
        if let selected {
            MapPolyline(selected.polyline).stroke(Palette.forest, lineWidth: 7).mapOverlayLevel(level: .aboveRoads)
            ForEach(selected.pollutionSegments) { segment in
                MapPolyline(coordinates: segment.coordinates).stroke(
                    AirMapStyle.colour(segment.reading),
                    style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round)
                ).mapOverlayLevel(level: .aboveLabels)
            }
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
                            }.font(.caption.weight(.semibold))
                                .foregroundStyle(route.id == selectedID ? Palette.lime : RouteMapPresentation.alternative)
                                .padding(.horizontal, 11).frame(minHeight: 44)
                                .background(route.id == selectedID ? Palette.deep : .white, in: Capsule())
                                .overlay(Capsule().stroke(route.id == selectedID ? Palette.deep : RouteMapPresentation.alternative, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        }.buttonStyle(.plain).disabled(!allowSelection && route.id != selectedID)
                            .accessibilityLabel("Route \(index + 1), \(route.name), \(Int(route.seconds / 60)) minutes")
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let estimate = route.sampledEstimate(ventilation: ventilation)
        Button(action: inspect) {
            HStack(spacing: 12) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: route.isCleanAirPath ? "leaf.circle.fill" : "aqi.medium")
                        .font(.title3).foregroundStyle(route.isCleanAirPath ? Color(hex: 0x1D8348) : Palette.forest).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Air samples & alternative paths")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    }
                    Text("\(Int(estimate.coverage * 100))% sampled · \(route.airSamples.count) points · Est. dose \(doseText(estimate.observedDose))")
                        .font(.caption).foregroundStyle(Palette.muted)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.forest).accessibilityHidden(true)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(route.isCleanAirPath ? Color(hex: 0x1D8348).opacity(0.5) : Palette.line))
        }.buttonStyle(PressStyle())
    }
}

struct RouteInspectionView: View {
    @Bindable var model: AppModel
    @State private var camera: MapCameraPosition = .automatic
    @State private var showAir = true
    @State private var showForecast = false
    @State private var showSamples = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private var selected: WalkRoute? { model.activeRoute ?? model.selected }

    var body: some View {
        NavigationStack {
            Page {
                if let route = selected {
                    routePicker
                    comparisonMap(route)
                    summaryCard(route)
                    if model.routes.count > 1 { alternatives(route) }
                    sampleDisclosure(route)
                } else {
                    ContentUnavailableView("No route selected", systemImage: "map", description: Text("Find walking routes in Explore to compare their air samples."))
                }
            }
            .navigationTitle(selected?.name.isEmpty == false ? selected!.name : "Route details").navigationBarTitleDisplayMode(.inline)
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
                            Image(systemName: route.isCleanAirPath ? "leaf.fill" : (route.id == selected?.id ? "checkmark.circle.fill" : "arrow.triangle.branch"))
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
            if let first = route.coordinates.first { Marker("Start", coordinate: first).tint(Palette.deep) }
            if let last = route.coordinates.last { Marker("Destination", coordinate: last).tint(Palette.deep) }
        }.mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: typeSize.isAccessibilitySize ? 300 : 230)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .bottomTrailing) {
                Button(action: fitRoutes) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.subheadline.bold()).frame(width: 44, height: 44).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
                    .accessibilityLabel("Fit all routes").padding(10)
            }
    }

    private func summaryCard(_ route: WalkRoute) -> some View {
        let estimate = route.sampledEstimate(ventilation: model.intensity.ventilation)
        let usable = route.airSamples.filter { $0.reading?.isFresh == true || $0.reading?.demo == true }.count
        return Surface {
            HStack {
                SectionHeading(title: "Coverage & exposure", detail: "\(usable)/\(route.airSamples.count) points")
                Spacer()
                if route.isCleanAirPath {
                    StatusPill(title: "AQI 1–2", symbol: "leaf.fill")
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], spacing: 16) {
                Metric(title: "Coverage", value: "\(Int(estimate.coverage * 100))%")
                Metric(title: "Distance", value: String(format: "%.2f km", route.metres / 1000))
                Metric(title: "Est. dose", value: doseText(estimate.observedDose))
            }
            ProgressView(value: estimate.coverage).tint(Palette.forest)
            Text("Circles show approximate sample areas, not measured pollution boundaries. Colours use the nearest sample.").font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Text(route.source).font(.caption2).foregroundStyle(Palette.muted)
            Toggle("Show sample circles on map", isOn: $showAir).font(.subheadline)
            if model.activeRoute == nil {
                Divider()
                Button { showForecast = true } label: {
                    Label("Compare departure times (When to walk)", systemImage: "clock.badge.checkmark")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                }
            }
        }
    }

    private func alternatives(_ selectedRoute: WalkRoute) -> some View {
        let options = model.routes.filter { $0.id != selectedRoute.id }
        return Surface {
            SectionHeading(title: "Alternatives", detail: "\(options.count)")
            ForEach(options) { route in
                Button { select(route) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(route.name.isEmpty ? "Alternative path" : route.name).font(.subheadline.weight(.semibold))
                                if route.isCleanAirPath { StatusPill(title: "AQI 1–2", symbol: "leaf.fill") }
                            }
                            let estimate = route.sampledEstimate(ventilation: model.intensity.ventilation)
                            Text("\(Int(route.seconds / 60)) min · \(String(format: "%.2f km", route.metres / 1000)) · \(doseText(estimate.observedDose))")
                                .font(.caption).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(PressStyle()).foregroundStyle(Palette.forest).disabled(model.activeRoute != nil)
            }
        }
    }

    private func sampleDisclosure(_ route: WalkRoute) -> some View {
        Surface {
            DisclosureGroup("Air sample points & turns (\(route.airSamples.count))", isExpanded: $showSamples) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(route.airSamples.enumerated()), id: \.element.id) { index, sample in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 26, height: 26).background(AirMapStyle.colour(sample.reading), in: Circle())
                            if let reading = sample.reading {
                                Text(String(format: "PM2.5 %.1f µg/m³ · AQI %d (%@)", reading.pm25, reading.aqi, reading.label))
                                    .font(.caption).foregroundStyle(Palette.ink)
                            } else {
                                Text("Air data unavailable").font(.caption).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                        }
                    }
                    if !route.steps.isEmpty {
                        Divider()
                        Text("Turn-by-turn directions").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
                        ForEach(route.steps) { step in
                            Label("\(step.instructions) (\(Int(step.metres)) m)", systemImage: "arrow.turn.up.right")
                                .font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }.padding(.top, 10)
            }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
        }
    }

    private func select(_ route: WalkRoute) {
        guard model.activeRoute == nil else { return }
        model.selectedRoute = route.id
    }
    private func fitRoutes() { camera = .rect(RouteMapPresentation.bounds(model.routes)) }
}

struct RouteLineLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            Label("Selected (coloured by AQI)", systemImage: "line.diagonal").foregroundStyle(Palette.forest)
            Label("Alternatives", systemImage: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(RouteMapPresentation.alternative)
        }
    }
}
