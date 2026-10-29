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
                Image(systemName: "aqi.medium").font(.title3).foregroundStyle(Palette.forest)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Route details & air samples").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("\(Int(estimate.coverage * 100))% sampled · \(route.airSamples.count) points · \(doseText(estimate.observedDose))")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Palette.forest)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line))
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
                            Image(systemName: route.id == selected?.id ? "checkmark.circle.fill" : "arrow.triangle.branch")
                            Text("Route \(index + 1) · \(Int(route.seconds / 60)) min")
                        }.font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 40)
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
                Button(action: fitRoutes) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.subheadline.bold()).frame(width: 40, height: 40).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
                    .accessibilityLabel("Fit all routes").padding(10)
            }
    }

    private func summaryCard(_ route: WalkRoute) -> some View {
        let estimate = route.sampledEstimate(ventilation: model.intensity.ventilation)
        let usable = route.airSamples.filter { $0.reading?.isFresh == true }.count
        return Surface {
            SectionHeading(title: "Coverage & exposure", detail: route.demo ? "Synthetic demo" : "\(usable)/\(route.airSamples.count) fresh points")
            HStack(spacing: 16) {
                Metric(title: "Coverage", value: "\(Int(estimate.coverage * 100))%")
                Metric(title: "Distance", value: String(format: "%.2f km", route.metres / 1000))
                Metric(title: "Est. dose", value: doseText(estimate.observedDose))
            }
            ProgressView(value: estimate.coverage).tint(Palette.forest)
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
                            Text(route.name.isEmpty ? "Alternative path" : route.name).font(.subheadline.weight(.semibold))
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
            DisclosureGroup("Air sample points (\(route.airSamples.count))", isExpanded: $showSamples) {
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
                    InfoNote(text: "Dose assumes \(Int(model.intensity.ventilation * 1000)) L/min breathing volume.")
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
            Label("Selected", systemImage: "line.diagonal").foregroundStyle(Palette.forest)
            Label("Alternatives", systemImage: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(RouteMapPresentation.alternative)
        }
    }
}
