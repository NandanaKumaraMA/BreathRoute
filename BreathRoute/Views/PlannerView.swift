import SwiftUI
import MapKit

struct PlannerView: View {
    @Bindable var model: AppModel
    @State private var start: MKMapItem?
    @State private var destination: MKMapItem?
    @State private var searchTarget: SearchTarget?
    @State private var camera: MapCameraPosition = .region(.init(center: .init(latitude: 6.915, longitude: 79.864), span: .init(latitudeDelta: 0.018, longitudeDelta: 0.018)))
    @State private var confirmFinish = false
    @State private var speaking = false
    @State private var discovery = NearbyDiscovery()
    @State private var nearbyCategory: NearbyCategory = .parks
    @State private var radius = 3000.0
    @State private var origin: NearbyOrigin = .preview
    @State private var visibleRegion = MKCoordinateRegion(center: .init(latitude: 6.915, longitude: 79.864), span: .init(latitudeDelta: 0.04, longitudeDelta: 0.04))
    @State private var placeDetail: NearbyPlace?
    @State private var fullMapPlace: NearbyPlace?
    @State private var expandedMap = false
    @State private var mapStyle: ExploreMapStyle = .streets
    @State private var elevated = false
    @State private var showAir = true
    @State private var searchMovedArea = false
    @State private var waitingForLocation = false
    @State private var nearbyTask: Task<Void, Never>?
    @State private var fitNearbyWhenLoaded = false
    @State private var pendingComparison = false
    @State private var locationNotice: String?
    @State private var routeTask: Task<Void, Never>?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    enum SearchTarget: String, Identifiable { case start, destination; var id: String { rawValue } }
    enum NearbyOrigin { case current, manual, map, preview }
    var body: some View {
        GeometryReader { geometry in
            Page {
                PageHeader(title: model.activeRoute == nil ? "Find your next stop." : "Enjoy your walk.", subtitle: model.activeRoute == nil ? "Explore your surroundings" : "Walk in progress", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                if model.demo {
                    HStack(spacing: 10) {
                        StatusPill(title: "Demo", symbol: "sparkles")
                        Text("Illustrative routes & air data").font(.caption).foregroundStyle(Palette.muted)
                        Spacer()
                        if model.activeRoute == nil { Button("Exit") { model.leaveDemo() }.font(.caption.weight(.semibold)).frame(minHeight: 44) }
                    }
                }
                if geometry.size.width >= 800 {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 16) { routeMap(height: 620); airLegend }
                        VStack(alignment: .leading, spacing: 20) { planningControls; routeOptions }.frame(width: 340)
                    }
                    if model.activeRoute == nil { nearbyPlaces }
                } else {
                    routeMap(height: typeSize.isAccessibilitySize ? 510 : 420)
                    airLegend
                    if model.activeRoute == nil { nearbyPlaces }
                    planningControls; routeOptions
                }
                if waitingForLocation { InfoNote(symbol: "location", text: model.location.message + " The map area remains available while waiting for a recent location.") }
                if let locationNotice { InfoNote(symbol: "location", text: locationNotice) }
            }
        }
        .adaptiveNavigationBar()
        .safeAreaInset(edge: .bottom, spacing: 0) { walkAction }
        .sheet(item: $searchTarget) { target in
            PlaceSearch(title: target == .start ? "Choose a start" : "Where would you like to go?", region: visibleRegion, nearby: discovery.places) { place in
                clearRoutes()
                if target == .start { waitingForLocation = false; locationNotice = nil; start = place; origin = .manual; refreshNearby(recenter: true) }
                else { destination = place; focus(on: place.placemark.coordinate) }
            }
        }
        .sheet(item: $placeDetail) { place in
            NearbyPlaceDetail(place: place, discovery: discovery) { chooseDestination(place) }
        }
        .fullScreenCover(isPresented: $expandedMap) {
            NavigationStack {
                map(expanded: true)
                    .safeAreaInset(edge: .bottom) {
                        VStack(alignment: .leading, spacing: 12) {
                            if searchMovedArea && model.activeRoute == nil { searchAreaButton }
                            if showAir { AirMapLegend() }
                            Text(discovery.scope).font(.caption).foregroundStyle(Palette.muted)
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
                    }
                    .navigationTitle("Explore map").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { expandedMap = false } } }
                    .sheet(item: $fullMapPlace) { place in
                        NearbyPlaceDetail(place: place, discovery: discovery) { chooseDestination(place) }
                    }
            }
        }
        .confirmationDialog("Finish and save this walk?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Save walk") { model.finish() }
        } message: { Text("Only recorded intervals are saved. Missing intervals are labelled as incomplete coverage.") }
        .onChange(of: model.routes.map(\.id)) { _, _ in if !model.routes.isEmpty { focusRoutes() } }
        .onChange(of: model.selectedRoute) { _, _ in if !model.routes.isEmpty { focusRoutes() } }
        .onChange(of: nearbyCategory) { _, _ in refreshNearby() }
        .onChange(of: radius) { _, _ in refreshNearby(recenter: true) }
        .onChange(of: discovery.places.map(\.id)) { _, ids in
            guard fitNearbyWhenLoaded, !ids.isEmpty, model.routes.isEmpty, destination == nil else { return }
            fitNearbyWhenLoaded = false
            var rect = MKMapRect.null
            if let centre = discovery.centre { let point = MKMapPoint(centre); rect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1) }
            for place in discovery.places.prefix(6) {
                let point = MKMapPoint(place.coordinate)
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
            }
            let minimumPadding = MKMapPointsPerMeterAtLatitude(visibleRegion.center.latitude) * 350
            moveCamera(.rect(rect.insetBy(dx: -max(minimumPadding, rect.size.width * 0.4), dy: -max(minimumPadding, rect.size.height * 0.7))))
        }
        .onChange(of: model.location.location?.timestamp) { _, _ in
            guard let location = model.location.currentLocation, model.activeRoute == nil else { return }
            if pendingComparison { pendingComparison = false; waitingForLocation = false; compare() }
            if waitingForLocation || (origin == .preview && start == nil) {
                waitingForLocation = false; origin = .current; refreshNearby(recenter: true)
            } else if origin == .current, let centre = discovery.centre,
                      location.distance(from: CLLocation(latitude: centre.latitude, longitude: centre.longitude)) > 500 {
                refreshNearby()
            }
        }
        .task {
            if model.location.hasAuthorization { model.location.request() }
            if discovery.centre == nil {
                if start == nil && model.location.currentLocation != nil { origin = .current }
                refreshNearby(recenter: model.routes.isEmpty)
            }
        }
        .task(id: waitingForLocation) {
            guard waitingForLocation else { return }
            do { try await Task.sleep(for: .seconds(15)); try Task.checkCancellation() }
            catch { return }
            if model.location.currentLocation == nil {
                waitingForLocation = false; pendingComparison = false
                locationNotice = "A recent location is unavailable. Choose a start manually or check Location access in Settings, then try again."
            }
        }
        .sensoryFeedback(.selection, trigger: model.selectedRoute)
        .onDisappear { model.voice.stop(); speaking = false }
    }
    private func routeMap(height: CGFloat) -> some View {
        map(expanded: false)
        .overlay(alignment: .topLeading) {
            if model.activeRoute == nil { journeyFields.padding(14).padding(.trailing, 35) }
            else { StatusPill(title: model.demo ? "Demo session" : "Tracking while app is open", symbol: "record.circle", tint: Palette.deep).padding(16).background(.regularMaterial, in: Capsule()).padding(14) }
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 8) {
                if searchMovedArea && model.activeRoute == nil { searchAreaButton }
                Text(model.routes.isEmpty ? discovery.scope : "\(model.routes.count) walking \(model.routes.count == 1 ? "route" : "routes")")
                    .font(.caption2.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 9).foregroundStyle(Palette.ink).background(.regularMaterial, in: Capsule())
            }.padding(14).padding(.trailing, 56)
        }
        .frame(height: height).clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Palette.line, lineWidth: 0.7))

    }
    private func map(expanded: Bool) -> some View {
        ExploreMapView(model: model, discovery: discovery, camera: $camera, style: $mapStyle, elevated: $elevated, showAir: $showAir, destination: destination, region: visibleRegion, expanded: expanded, select: { place in
            if expanded { fullMapPlace = place } else { placeDetail = place }
        }, cameraChanged: { region in
            visibleRegion = region
            guard camera.positionedByUser, let centre = discovery.centre else { return }
            let distance = CLLocation(latitude: centre.latitude, longitude: centre.longitude).distance(from: CLLocation(latitude: region.center.latitude, longitude: region.center.longitude))
            searchMovedArea = distance > max(250, radius * 0.15)
        }, useLocation: useCurrentLocation, expand: { expandedMap.toggle() })
    }
    @ViewBuilder private var airLegend: some View {
        if showAir && (!(model.selected?.airSamples.isEmpty ?? true) || !discovery.airByPlace.isEmpty) { AirMapLegend() }
    }
    private var nearbyPlaces: some View {
        NearbyPlacesView(discovery: discovery, category: $nearbyCategory, radius: $radius, useLocation: useCurrentLocation, refresh: { refreshNearby() }, select: { placeDetail = $0 })
    }
    private var searchAreaButton: some View {
        Button { origin = .map; refreshNearby() } label: {
            Label("Search this area", systemImage: "arrow.clockwise").font(.caption.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 12).foregroundStyle(Palette.lime).background(Palette.deep, in: Capsule())
        }.buttonStyle(PressStyle())
    }
    private var journeyFields: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                Circle().stroke(Palette.forest, lineWidth: 2).frame(width: 9, height: 9)
                Rectangle().fill(Palette.line).frame(width: 1, height: 22)
                Image(systemName: "mappin.circle.fill").font(.system(size: 15)).foregroundStyle(Palette.forest)
            }.padding(.top, 16).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Button { searchTarget = .start } label: {
                    HStack { Text(start?.name ?? "Current location").font(.subheadline.weight(.medium)).lineLimit(1); Spacer(); Image(systemName: "chevron.down").font(.caption2) }.frame(minHeight: 44)
                }.accessibilityLabel("Start: \(start?.name ?? "Current location"). Change start")
                Divider()
                Button { searchTarget = .destination } label: {
                    HStack { Text(destination?.name ?? (model.demo ? "Viharamahadevi Park · demo" : "Where to?")).font(.subheadline.weight(.medium)).lineLimit(1); Spacer(); Image(systemName: "magnifyingglass").font(.caption) }.frame(minHeight: 44)
                }.accessibilityLabel("Destination: \(destination?.name ?? "Choose destination")")
            }
        }.padding(.horizontal, 16).padding(.vertical, 4).foregroundStyle(Palette.ink).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.07), radius: 16, y: 5)
    }
    @ViewBuilder private var planningControls: some View {
        if model.activeRoute == nil {
            HStack {
                Label("Walking pace", systemImage: "figure.walk").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                Spacer()
                Picker("Walking intensity", selection: $model.intensity) { ForEach(WalkingIntensity.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.menu).font(.subheadline.weight(.semibold)).disabled(!model.routes.isEmpty)
            }
            if start != nil { Button("Use current location instead") { start = nil; clearRoutes(); useCurrentLocation() }.font(.caption).frame(minHeight: 44) }
            if !model.demo {
                PrimaryButton(title: pendingComparison ? "Getting your location…" : (model.routes.isEmpty ? "Find walking routes" : "Refresh route comparison"), symbol: "arrow.triangle.branch") { compare() }
                    .disabled(destination == nil || model.busy || pendingComparison)
            }
            if model.busy {
                HStack(spacing: 12) { ProgressView().tint(Palette.forest); VStack(alignment: .leading, spacing: 5) { Text("Comparing your options").font(.subheadline.weight(.semibold)); Text("Walking routes, air samples & estimated dose").font(.caption).foregroundStyle(Palette.muted) } }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
    @ViewBuilder private var routeOptions: some View {
        if let route = model.activeRoute { activeCard(route) }
        else if model.routes.isEmpty {
            Surface {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.triangle.branch").font(.title2).foregroundStyle(Palette.forest).frame(width: 48, height: 48).background(Palette.forest.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 5) { Text("There’s more than one way").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink); Text("Compare time, distance & estimated exposure.").font(.caption).foregroundStyle(Palette.muted) }
                }
                Button { model.loadDemo(); focusRoutes() } label: { HStack { Text("See an example comparison"); Spacer(); Image(systemName: "arrow.up.right") }.font(.caption.weight(.semibold)).padding(.vertical, 8) }
            }
        } else {
            SectionHeading(title: "Choose your walk", detail: "\(model.routes.count) options")
            ForEach(Array(model.routes.enumerated()), id: \.element.id) { index, route in routeCard(route, index: index) }
            InfoNote(text: "Dose assumes \(Int(model.intensity.ventilation * 1000)) L/min ventilation. Sample coverage does not establish street-level accuracy.")
        }
    }
    private func routeCard(_ route: WalkRoute, index: Int) -> some View {
        let selected = model.selectedRoute == route.id
        return Button { model.selectedRoute = route.id } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Text(String(format: "%02d", index + 1)).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundStyle(selected ? Palette.deep : Palette.muted).frame(width: 34, height: 34).background(selected ? Palette.lime : Palette.canvas, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(route.name.isEmpty ? "Walking route" : route.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        if route.id == model.bestRouteID { Text("LOWEST ESTIMATED DOSE").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.6).foregroundStyle(Palette.forest) }
                        else { Text(route.demo ? "Illustrative comparison" : "Walking route").font(.caption2).foregroundStyle(Palette.muted) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(Palette.forest)
                }
                HStack(spacing: 0) {
                    routeMetric("\(Int(route.seconds / 60)) min", title: "time")
                    routeMetric(String(format: "%.2f km", route.metres/1000), title: "distance")
                    routeMetric(route.estimate.observedDose.map { String(format: "%.1f µg", $0) } ?? "—", title: route.estimate.isComplete ? "est. dose" : "partial dose")
                }
                HStack(spacing: 9) {
                    Capsule().fill(Palette.line).frame(width: 50, height: 3).overlay(alignment: .leading) { Capsule().fill(Palette.forest).frame(width: 50 * route.estimate.coverage, height: 3) }
                    Text("\(Int(route.estimate.coverage * 100))% sampled coverage").font(.caption2).foregroundStyle(Palette.muted)
                    Spacer()
                    if route.demo { Text("DEMO").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.muted) }
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Palette.forest : Palette.line, lineWidth: selected ? 1.5 : 0.7))
        }.buttonStyle(PressStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func routeMetric(_ value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(.headline, design: .rounded)).foregroundStyle(Palette.ink).monospacedDigit(); Text(title).font(.caption2).foregroundStyle(Palette.muted) }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private func activeCard(_ route: WalkRoute) -> some View {
        Surface {
            HStack { SectionHeading(title: "Your walk, so far"); StatusPill(title: "Active", symbol: "record.circle") }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    Metric(title: "Elapsed", value: "\(Int(context.date.timeIntervalSince(model.walkStarted ?? context.date) / 60)) min")
                    Metric(title: "Recorded distance", value: String(format: "%.0f m", model.trackedMetres))
                }
            }
            Divider()
            HStack { Text("Recorded estimated dose").font(.subheadline); Spacer(); Text(doseText(model.activeEstimate.observedDose)).font(.headline) }
            InfoNote(text: model.trackingMessage)
        }
    }
    @ViewBuilder private var walkAction: some View {
        if model.activeRoute != nil || model.selected != nil {
            HStack(spacing: 12) {
                PrimaryButton(title: model.activeRoute != nil ? "Finish & save walk" : (model.demo ? "Start demo session" : "Start this walk"), symbol: model.activeRoute != nil ? "checkmark" : "figure.walk") {
                    if model.activeRoute != nil { confirmFinish = true } else if let route = model.selected { model.start(route) }
                }
                if let route = model.selected, model.activeRoute == nil {
                    Button {
                        if speaking { model.voice.stop(); speaking = false }
                        else { model.voice.speak("\(route.name). \(Int(route.seconds/60)) minutes. \(Int(route.metres)) metres. Estimated dose \(doseText(route.estimate.observedDose)). Sample coverage \(Int(route.estimate.coverage*100)) percent. \(route.demo ? "Demo data." : "For awareness only.")"); speaking = true }
                    } label: { Image(systemName: speaking ? "stop.fill" : "speaker.wave.2").font(.headline).foregroundStyle(Palette.deep).frame(width: 56, height: 56).background(Palette.lime, in: RoundedRectangle(cornerRadius: 18)) }
                        .accessibilityLabel(speaking ? "Stop reading route summary" : "Read route summary aloud")
                }
            }.padding(.horizontal, 22).padding(.vertical, 12).frame(maxWidth: 800).frame(maxWidth: .infinity).background(.regularMaterial)
        }
    }
    private func compare() {
        guard let destination else { return }
        guard let coordinate = start?.placemark.coordinate ?? model.location.currentLocation?.coordinate else {
            locationNotice = nil; pendingComparison = true; waitingForLocation = true; model.location.request(); return
        }
        pendingComparison = false; waitingForLocation = false; locationNotice = nil
        routeTask?.cancel()
        routeTask = Task { await model.plan(start: coordinate, destination: destination); if !Task.isCancelled { focusRoutes() } }
    }
    private func clearRoutes() {
        pendingComparison = false; routeTask?.cancel(); model.cancelPlanning()
        if model.demo { model.leaveDemo() } else { model.routes = []; model.selectedRoute = nil }
    }
    private func chooseDestination(_ place: NearbyPlace) {
        guard model.activeRoute == nil else { return }
        clearRoutes(); destination = place.item; focus(on: place.coordinate)
    }
    private func useCurrentLocation() {
        locationNotice = nil
        model.location.request()
        guard let location = model.location.currentLocation else { waitingForLocation = true; return }
        waitingForLocation = false
        if model.activeRoute != nil { focus(on: location.coordinate); return }
        origin = .current; refreshNearby(recenter: true)
    }
    private func refreshNearby(recenter: Bool = false) {
        guard model.activeRoute == nil else { return }
        let coordinate: CLLocationCoordinate2D
        let scope: String
        switch origin {
        case .current:
            guard let current = model.location.currentLocation else {
                waitingForLocation = true; model.location.request(); return
            }
            coordinate = current.coordinate; scope = "Near your current location"
        case .manual:
            guard let start else { origin = .preview; refreshNearby(recenter: recenter); return }
            coordinate = start.placemark.coordinate; scope = "Near \(start.name ?? "your chosen start")"
        case .map: coordinate = visibleRegion.center; scope = "Around the map area"
        case .preview: coordinate = visibleRegion.center; scope = "Colombo map preview"
        }
        searchMovedArea = false
        fitNearbyWhenLoaded = recenter && model.routes.isEmpty && destination == nil
        if recenter {
            moveCamera(.region(MKCoordinateRegion(center: coordinate, latitudinalMeters: radius * 2.5, longitudinalMeters: radius * 2.5)))
        }
        nearbyTask?.cancel()
        nearbyTask = Task { await discovery.load(around: coordinate, category: nearbyCategory, radius: radius, scope: scope) }
    }
    private func focus(on coordinate: CLLocationCoordinate2D) {
        moveCamera(.region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1800, longitudinalMeters: 1800)))
    }
    private func focusRoutes() {
        guard !model.routes.isEmpty else { return }
        let rect = model.routes.reduce(MKMapRect.null) { $0.union($1.polyline.boundingMapRect) }
        if !rect.isNull {
            moveCamera(.rect(rect.insetBy(dx: -max(300, rect.size.width * 0.3), dy: -max(500, rect.size.height * 0.5))))
        }
    }
    private func moveCamera(_ position: MapCameraPosition) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { camera = position }
    }
}
