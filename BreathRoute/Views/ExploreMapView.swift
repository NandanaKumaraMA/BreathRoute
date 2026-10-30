import SwiftUI
import MapKit

enum ExploreMapStyle: String, CaseIterable, Identifiable {
    case streets = "Streets", satellite = "Satellite", hybrid = "Hybrid"
    var id: String { rawValue }
    func style(elevated: Bool) -> MapStyle {
        let elevation: MapStyle.Elevation = elevated ? .realistic : .flat
        return switch self {
        case .streets: .standard(elevation: elevation, emphasis: .automatic, pointsOfInterest: .excludingAll, showsTraffic: false)
        case .satellite: .imagery(elevation: elevation)
        case .hybrid: .hybrid(elevation: elevation, pointsOfInterest: .excludingAll, showsTraffic: false)
        }
    }
}

struct ExploreMapView: View {
    @Bindable var model: AppModel
    @Bindable var discovery: NearbyDiscovery
    @Binding var camera: MapCameraPosition
    @Binding var style: ExploreMapStyle
    @Binding var elevated: Bool
    @Binding var showAir: Bool
    var destination: MKMapItem?
    var region: MKCoordinateRegion
    var expanded = false
    let select: (NearbyPlace) -> Void
    let inspectRoute: (WalkRoute) -> Void
    let cameraChanged: (MKCoordinateRegion, MapCamera) -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    var canZoomIn = true
    var canZoomOut = true
    let useLocation: () -> Void
    let expand: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var mapScope

    var body: some View {
        Map(position: $camera, scope: mapScope) {
            if model.activeRoute == nil { UserAnnotation() }
            if showAir {
                if model.routes.isEmpty && model.activeRoute == nil && !model.demo {
                    ForEach(discovery.places.filter { discovery.airByPlace[$0.id] != nil }) { place in
                        MapCircle(center: place.coordinate, radius: 250)
                            .foregroundStyle(AirMapStyle.colour(discovery.airByPlace[place.id]).opacity(0.14))
                            .stroke(AirMapStyle.colour(discovery.airByPlace[place.id]).opacity(0.6), lineWidth: 1)
                    }
                }
            }
            RouteComparisonLayers(routes: model.routes, selectedID: model.selectedRoute, showAir: showAir, showRouteLabels: !typeSize.isAccessibilitySize, allowSelection: model.activeRoute == nil, select: inspectRoute)
            if showAir && model.geofences.enabled {
                ForEach(model.geofences.areas) { area in
                    MapCircle(center: .init(latitude: area.latitude, longitude: area.longitude), radius: area.radius)
                        .foregroundStyle(Color.orange.opacity(0.08))
                        .stroke(Color.orange.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
            RecordedPathLayers(points: model.recordedPath)
            ForEach(model.remainingOptions) { route in
                MapPolyline(route.polyline).stroke(
                    route.isCleanAirPath ? Color(hex: 0x16A085) : Color(hex: 0x6E5BA8),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [7, 5])
                )
            }
            if let active = model.activeRoute, let liveLocation = model.location.location ?? model.recordedPath.last.map({ CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }) {
                Annotation(active.demo ? "Walk preview location" : "Your location", coordinate: liveLocation.coordinate) {
                    LiveRunnerPuck(heading: model.location.headingDegrees, isRunning: model.isRunningLive, speedKmh: model.liveSpeedKmh, preview: active.demo)
                }.annotationTitles(.hidden)
            }
            if model.activeRoute == nil && model.routes.isEmpty && !model.demo {
                ForEach(mapPlaces, id: \.element.id) { index, place in
                    Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                        Button { select(place) } label: {
                            HStack(spacing: 5) { Image(systemName: place.category.symbol); Text("\(index + 1)").monospacedDigit() }
                                .font(.caption.weight(.bold)).foregroundStyle(Palette.lime).padding(.horizontal, 10).padding(.vertical, 9)
                                .background(Palette.deep, in: Capsule()).overlay(Capsule().stroke(.white, lineWidth: 2))
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2).frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel("\(place.name), \(place.distanceLabel) from search centre. Show details")
                    }.annotationTitles(.hidden)
                }
            }
            if model.activeRoute == nil, let first = model.selected?.coordinates.first {
                Annotation("Start", coordinate: first) {
                    Image(systemName: "figure.walk").font(.subheadline.bold()).foregroundStyle(Palette.deep)
                        .frame(width: 34, height: 34).background(.white, in: Circle())
                        .overlay(Circle().stroke(Palette.deep, lineWidth: 2))
                }
            }
            if let last = model.selected?.coordinates.last ?? destination?.placemark.coordinate {
                Annotation("Destination", coordinate: last, anchor: .bottom) {
                    Image(systemName: "flag.fill").font(.subheadline).foregroundStyle(Palette.lime)
                        .frame(width: 38, height: 38).background(Palette.deep, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(style.style(elevated: elevated))
        .mapControls {
            MapCompass(scope: mapScope)
            MapScaleView(scope: mapScope)
        }
        .mapScope(mapScope)
        .onMapCameraChange(frequency: .onEnd) { context in cameraChanged(context.region, context.camera) }
        .accessibilityLabel("Walking route map. Choose a destination above, or select a nearby place.")
        .overlay(alignment: .bottomTrailing) {
            HStack(alignment: .bottom, spacing: 8) {
                VStack(spacing: 8) {
                    Button(action: zoomIn) { toolIcon("plus") }
                        .accessibilityLabel("Zoom in")
                        .accessibilityHint("Show more map detail. Keeps camera follow on if enabled.")
                        .disabled(!canZoomIn).opacity(canZoomIn ? 1 : 0.4)
                    Button(action: zoomOut) { toolIcon("minus") }
                        .accessibilityLabel("Zoom out")
                        .accessibilityHint("Show a wider area. Keeps camera follow on if enabled.")
                        .disabled(!canZoomOut).opacity(canZoomOut ? 1 : 0.4)
                }
                VStack(spacing: 8) {
                    Menu {
                        Picker("Map style", selection: $style) { ForEach(ExploreMapStyle.allCases) { Text($0.rawValue).tag($0) } }
                        Toggle("3D terrain & buildings", isOn: $elevated)
                        Toggle("3D navigation pitch", isOn: $model.pitch3D)
                        Toggle("Air sample circles", isOn: $showAir)
                    } label: { toolIcon("square.3.layers.3d") }.accessibilityLabel("Map appearance and air sample areas")
                    if model.activeRoute != nil {
                        Button {
                            model.followCamera.toggle()
                        } label: {
                            toolIcon(model.followCamera ? "location.north.line.fill" : "location.slash")
                        }.accessibilityLabel(model.followCamera ? "Stop following the walker" : "Follow the walker")
                    }
                    Button(action: useLocation) { toolIcon("location.fill") }.accessibilityLabel("Recenter on my current location")
                    Button(action: expand) { toolIcon(expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }.accessibilityLabel(expanded ? "Close full-screen map" : "Expand map")
                }
            }.padding(12)
        }
    }

    private var mapPlaces: [(offset: Int, element: NearbyPlace)] {
        let minimumSeparation = max(15, abs(region.span.longitudeDelta) * 111_320 * cos(region.center.latitude * .pi / 180) * 0.12)
        return Array(discovery.places.prefix(6).enumerated()).reduce(into: []) { shown, candidate in
            let location = CLLocation(latitude: candidate.element.coordinate.latitude, longitude: candidate.element.coordinate.longitude)
            if !shown.contains(where: {
                location.distance(from: CLLocation(latitude: $0.element.coordinate.latitude, longitude: $0.element.coordinate.longitude)) < minimumSeparation
            }) { shown.append(candidate) }
        }
    }

    private func toolIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
            .frame(width: 44, height: 44).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.6), lineWidth: 0.7))
    }
}

/// Real-time animated runner/walker marker with directional heading cone and speed indicator.
struct LiveRunnerPuck: View {
    let heading: Double
    let isRunning: Bool
    let speedKmh: Double
    var preview = false

    var body: some View {
        VStack(spacing: 3) {
            if speedKmh > 0.3 {
                Text(String(format: "%.1f km/h", speedKmh))
                    .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.lime)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Palette.deep, in: Capsule())
            }
            ZStack {
                Circle().fill(Color(hex: 0x16A085).opacity(0.24)).frame(width: 54, height: 54)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0x16A085))
                    .offset(y: -22)
                    .rotationEffect(.degrees(heading))
                Circle().fill(Palette.deep).frame(width: 34, height: 34)
                    .overlay(Circle().stroke(.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                Image(systemName: isRunning ? "figure.run" : "figure.walk")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.lime)
            }
        }
        .accessibilityLabel(preview ? "Walk preview position" : (isRunning ? "Runner position" : "Walker position"))
    }
}

struct AirMapLegend: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
            legend("AQI 1–2", colour: Color(hex: 0x1D8348))
            legend("AQI 3", colour: Color(hex: 0xB88320))
            legend("AQI 4–5", colour: Color(hex: 0xB34C46))
        }.accessibilityElement(children: .combine)
    }
    private func legend(_ label: String, colour: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(colour).frame(width: 8, height: 8)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(Palette.ink)
        }
    }
}
