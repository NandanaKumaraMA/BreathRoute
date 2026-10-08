import SwiftUI
import MapKit

enum ExploreMapStyle: String, CaseIterable, Identifiable {
    case streets = "Streets", satellite = "Satellite", hybrid = "Hybrid"
    var id: String { rawValue }
    func style(elevated: Bool) -> MapStyle {
        let elevation: MapStyle.Elevation = elevated ? .realistic : .flat
        return switch self {
        case .streets: .standard(elevation: elevation, pointsOfInterest: .excludingAll)
        case .satellite: .imagery(elevation: elevation)
        case .hybrid: .hybrid(elevation: elevation, pointsOfInterest: .excludingAll)
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
    let cameraChanged: (MKCoordinateRegion) -> Void
    let useLocation: () -> Void
    let expand: () -> Void

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            if showAir {
                ForEach(model.selected?.airSamples ?? []) { sample in
                    MapCircle(center: sample.coordinate, radius: 250)
                        .foregroundStyle(AirMapStyle.colour(sample.reading).opacity(0.14))
                        .stroke(AirMapStyle.colour(sample.reading).opacity(0.6), lineWidth: 1)
                }
                if model.activeRoute == nil && !model.demo {
                    ForEach(discovery.places.filter { discovery.airByPlace[$0.id] != nil }) { place in
                        MapCircle(center: place.coordinate, radius: 250)
                            .foregroundStyle(AirMapStyle.colour(discovery.airByPlace[place.id]).opacity(0.14))
                            .stroke(AirMapStyle.colour(discovery.airByPlace[place.id]).opacity(0.6), lineWidth: 1)
                    }
                }
            }
            ForEach(model.routes) { route in
                MapPolyline(route.polyline).stroke(route.id == model.selectedRoute ? Palette.deep : Color.gray.opacity(0.6), style: StrokeStyle(lineWidth: route.id == model.selectedRoute ? 6 : 3, lineCap: .round, lineJoin: .round))
            }
            if model.activeRoute == nil && !model.demo {
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
            if let first = model.selected?.coordinates.first {
                Annotation("Start", coordinate: first) {
                    Image(systemName: "figure.walk").font(.subheadline.bold()).foregroundStyle(Palette.deep).frame(width: 34, height: 34).background(.white, in: Circle()).overlay(Circle().stroke(Palette.deep, lineWidth: 2))
                }
            }
            if let last = model.selected?.coordinates.last ?? destination?.placemark.coordinate {
                Annotation("Destination", coordinate: last, anchor: .bottom) {
                    Image(systemName: "flag.fill").font(.subheadline).foregroundStyle(Palette.lime).frame(width: 38, height: 38).background(Palette.deep, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(style.style(elevated: elevated))
        .mapControls { MapCompass(); MapScaleView() }
        .onMapCameraChange(frequency: .onEnd) { context in cameraChanged(context.region) }
        .accessibilityLabel("Explore map. Nearby places and route information are also available in lists.")
        .overlay(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                Menu {
                    Picker("Map style", selection: $style) { ForEach(ExploreMapStyle.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Terrain elevation", isOn: $elevated)
                    Toggle("Air sample circles", isOn: $showAir)
                } label: { toolIcon("square.3.layers.3d") }.accessibilityLabel("Map layers and style")
                Button(action: useLocation) { toolIcon("location.fill") }.accessibilityLabel("Recenter on my current location")
                Button(action: expand) { toolIcon(expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }.accessibilityLabel(expanded ? "Close full-screen map" : "Expand map")
            }.padding(14)
        }
    }
    private var mapPlaces: [(offset: Int, element: NearbyPlace)] {
        let minimumSeparation = max(15, abs(region.span.longitudeDelta) * 111_320 * cos(region.center.latitude * .pi / 180) * 0.12)
        return Array(discovery.places.enumerated()).reduce(into: []) { shown, candidate in
            let location = CLLocation(latitude: candidate.element.coordinate.latitude, longitude: candidate.element.coordinate.longitude)
            if !shown.contains(where: {
                location.distance(from: CLLocation(latitude: $0.element.coordinate.latitude, longitude: $0.element.coordinate.longitude)) < minimumSeparation
            }) { shown.append(candidate) }
        }
    }
    private func toolIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.ink)
            .frame(width: 44, height: 44).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.6), lineWidth: 0.7))
    }
}

struct AirMapLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { levels }
                VStack(alignment: .leading, spacing: 6) { levels }
            }
            Text("OpenWeather overall AQI · 250 m illustrative sample circles. Grey means missing or stale. Circles are not pollution boundaries.")
                .font(.caption2).foregroundStyle(Palette.muted)
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private var levels: some View {
        legend("1–2", colour: Palette.forest); legend("3", colour: Color(hex: 0xB88320)); legend("4–5", colour: Color(hex: 0xB34C46)); legend("Unknown", colour: .gray)
    }
    private func legend(_ label: String, colour: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(colour).frame(width: 8, height: 8); Text(label).font(.caption2.weight(.medium)).foregroundStyle(Palette.ink) }
    }
}
