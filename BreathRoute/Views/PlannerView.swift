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
    @State private var walkTool: WalkTool?
    @State private var toolAction: ToolAction?
    @State private var showRouteDetails = false
    @State private var showDepartureForecast = false
    @State private var showFullMapRouteDetails = false
    @State private var showNearbyWhenRouted = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum SearchTarget: String, Identifiable { case start, destination; var id: String { rawValue } }
    enum NearbyOrigin { case current, manual, map, preview }
    enum ToolAction { case configure, plan }

    var body: some View {
        GeometryReader { geometry in
            Page {
                PageHeader(title: model.activeRoute == nil ? "Explore routes." : "Enjoy your walk.",
                           subtitle: model.activeRoute == nil ? "Plan & compare" : "Walk in progress",
                           symbol: "point.topleft.down.to.point.bottomright.curvepath")
                RecoveryCard(model: model)
                WalkToolsLauncher(model: model) { walkTool = $0 }
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
                        VStack(alignment: .leading, spacing: 14) { routeMap(height: 580); mapStatusStrip; coverageBanner }
                        VStack(alignment: .leading, spacing: 18) { planningControls; routeOptions }.frame(width: 340)
                    }
                    if model.activeRoute == nil { nearbySection }
                } else {
                    routeMap(height: typeSize.isAccessibilitySize ? 480 : 390)
                    mapStatusStrip
                    coverageBanner
                    planningControls
                    routeOptions
                    if model.activeRoute == nil { nearbySection }
                }
                if waitingForLocation { InfoNote(symbol: "location", text: model.location.message) }
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
        .sheet(isPresented: $showRouteDetails) { RouteInspectionView(model: model) }
        .sheet(isPresented: $showDepartureForecast) { ForecastEntryView(model: model) }
        .sheet(item: $walkTool, onDismiss: {
            guard let action = toolAction else { return }
            toolAction = nil
            switch action {
            case .configure: model.section = .profile
            case .plan: if model.selected?.demo != false { searchTarget = .destination }
            }
        }) { tool in
            WalkToolsSheet(tool: tool, model: model, configure: { toolAction = .configure; walkTool = nil }, plan: { toolAction = .plan; walkTool = nil })
        }
        .fullScreenCover(isPresented: $expandedMap) {
            NavigationStack {
                map(expanded: true)
                    .safeAreaInset(edge: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            if searchMovedArea && model.activeRoute == nil { searchAreaButton }
                            if showAir { AirMapLegend() }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
                    }
                    .navigationTitle("Explore map").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { expandedMap = false } } }
                    .sheet(item: $fullMapPlace) { place in
                        NearbyPlaceDetail(place: place, discovery: discovery) { chooseDestination(place) }
                    }
                    .sheet(isPresented: $showFullMapRouteDetails) { RouteInspectionView(model: model) }
            }
        }
        .confirmationDialog("Finish and save this walk?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Save walk") { model.finish() }
        } message: { Text("Only recorded intervals are saved. Missing intervals are labelled as incomplete coverage.") }
        .onChange(of: model.routes.map(\.id)) { _, _ in if !model.routes.isEmpty { focusRoutes() } }
        .onChange(of: model.selectedRoute) { _, _ in if !model.routes.isEmpty { focusRoutes() } }
        .onChange(of: model.remainingOptions.map(\.id)) { _, _ in
            guard !model.remainingOptions.isEmpty else { return }
            let rect = model.remainingOptions.reduce(MKMapRect.null) { $0.union($1.polyline.boundingMapRect) }
            moveCamera(.rect(rect.insetBy(dx: -max(300, rect.size.width * 0.3), dy: -max(500, rect.size.height * 0.5))))
        }
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
                locationNotice = "A recent location is unavailable. Choose a start manually or check Location access in Settings."
            }
        }
        .sensoryFeedback(.selection, trigger: model.selectedRoute)
        .onDisappear { model.voice.stop(); speaking = false }
    }

    private func routeMap(height: CGFloat) -> some View {
        map(expanded: false)
            .overlay(alignment: .topLeading) {
                if model.activeRoute == nil { journeyFields.padding(12).padding(.trailing, 32) }
                else { StatusPill(title: model.demo ? "Demo session" : "Tracking while open", symbol: "record.circle", tint: Palette.deep).padding(12).background(.regularMaterial, in: Capsule()).padding(12) }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if searchMovedArea && model.activeRoute == nil { searchAreaButton }
                    Text(model.routes.isEmpty ? discovery.scope : "\(model.routes.count) walking \(model.routes.count == 1 ? "route" : "routes")")
                        .font(.caption2.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(Palette.ink).background(.regularMaterial, in: Capsule())
                }.padding(12).padding(.trailing, 54)
            }
            .frame(height: height).clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Palette.line, lineWidth: 0.7))
    }

    private func map(expanded: Bool) -> some View {
        ExploreMapView(model: model, discovery: discovery, camera: $camera, style: $mapStyle, elevated: $elevated, showAir: $showAir, destination: destination, region: visibleRegion, expanded: expanded, select: { place in
            if expanded { fullMapPlace = place } else { placeDetail = place }
        }, inspectRoute: { route in
            if model.activeRoute == nil { model.selectedRoute = route.id }
            showAir = true
            if expanded { showFullMapRouteDetails = true } else { showRouteDetails = true }
        }, cameraChanged: { region in
            visibleRegion = region
            guard camera.positionedByUser, let centre = discovery.centre else { return }
            let distance = CLLocation(latitude: centre.latitude, longitude: centre.longitude).distance(from: CLLocation(latitude: region.center.latitude, longitude: region.center.longitude))
            searchMovedArea = distance > max(250, radius * 0.15)
        }, useLocation: useCurrentLocation, expand: { expandedMap.toggle() })
    }

    @ViewBuilder private var mapStatusStrip: some View {
        HStack {
            if showAir && (!(model.selected?.airSamples.isEmpty ?? true) || !discovery.airByPlace.isEmpty) {
                AirMapLegend()
            }
            Spacer(minLength: 8)
            Button { showDepartureForecast = true } label: {
                Label("When to walk", systemImage: "clock.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .foregroundStyle(Palette.forest)
                    .background(Palette.surface, in: Capsule())
                    .overlay(Capsule().stroke(Palette.line, lineWidth: 0.7))
            }.disabled(model.activeRoute != nil)
        }
    }

    @ViewBuilder private var coverageBanner: some View {
        if let route = model.activeRoute ?? model.selected {
            RouteCoverageBanner(route: route, ventilation: model.intensity.ventilation) { showRouteDetails = true }
        }
    }

    @ViewBuilder private var nearbySection: some View {
        if model.routes.isEmpty {
            NearbyPlacesView(discovery: discovery, category: $nearbyCategory, radius: $radius, useLocation: useCurrentLocation, refresh: { refreshNearby() }, select: { placeDetail = $0 })
        } else {
            Surface {
                DisclosureGroup("Nearby places to explore", isExpanded: $showNearbyWhenRouted) {
                    NearbyPlacesView(discovery: discovery, category: $nearbyCategory, radius: $radius, useLocation: useCurrentLocation, refresh: { refreshNearby() }, select: { placeDetail = $0 })
                        .padding(.top, 12)
                }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            }
        }
    }

    private var searchAreaButton: some View {
        Button { origin = .map; refreshNearby() } label: {
            Label("Search this area", systemImage: "arrow.clockwise").font(.caption.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10).foregroundStyle(Palette.lime).background(Palette.deep, in: Capsule())
        }.buttonStyle(PressStyle())
    }

    private var journeyFields: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                Circle().stroke(Palette.forest, lineWidth: 2).frame(width: 9, height: 9)
                Rectangle().fill(Palette.line).frame(width: 1, height: 20)
                Image(systemName: "mappin.circle.fill").font(.system(size: 14)).foregroundStyle(Palette.forest)
            }.padding(.top, 14).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Button { searchTarget = .start } label: {
                    HStack { Text(start?.name ?? "Current location").font(.subheadline.weight(.medium)).lineLimit(1); Spacer(); Image(systemName: "chevron.down").font(.caption2) }.frame(minHeight: 40)
                }.accessibilityLabel("Start: \(start?.name ?? "Current location"). Change start")
                Divider()
                Button { searchTarget = .destination } label: {
                    HStack { Text(destination?.name ?? (model.demo ? "Viharamahadevi Park · demo" : "Where to?")).font(.subheadline.weight(.medium)).lineLimit(1); Spacer(); Image(systemName: "magnifyingglass").font(.caption) }.frame(minHeight: 40)
                }.accessibilityLabel("Destination: \(destination?.name ?? "Choose destination")")
            }
        }.padding(.horizontal, 14).padding(.vertical, 4).foregroundStyle(Palette.ink).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.07), radius: 12, y: 4)
    }

    @ViewBuilder private var planningControls: some View {
        if model.activeRoute == nil {
            HStack {
                Label("Pace", systemImage: "figure.walk").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                Picker("Walking intensity", selection: $model.intensity) { ForEach(WalkingIntensity.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.menu).font(.subheadline.weight(.semibold)).disabled(!model.routes.isEmpty)
                Spacer()
                if start != nil {
                    Button("Use my location") { start = nil; clearRoutes(); useCurrentLocation() }.font(.caption.weight(.semibold))
                }
            }
            if !model.demo {
                PrimaryButton(title: pendingComparison ? "Getting location…" : (model.routes.isEmpty ? "Find walking routes" : "Refresh routes"), symbol: "arrow.triangle.branch") { compare() }
                    .disabled(destination == nil || model.busy || pendingComparison)
            }
            if model.busy {
                HStack(spacing: 12) { ProgressView().tint(Palette.forest); Text("Comparing routes & air samples…").font(.subheadline).foregroundStyle(Palette.muted) }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    @ViewBuilder private var routeOptions: some View {
        if let route = model.activeRoute {
            activeCard(route)
            ActiveMotionCard(model: model, demo: route.demo)
            if !route.demo {
                Button { walkTool = .rerouting } label: { Label("Rerouting controls", systemImage: "arrow.triangle.branch").font(.subheadline.weight(.semibold)) }.frame(minHeight: 44)
            }
        } else if model.routes.isEmpty {
            Surface {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.title3).foregroundStyle(Palette.forest)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Try an example route comparison").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text("Preview time, distance & modelled exposure.").font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button("Load demo") { model.loadDemo(); focusRoutes() }.font(.caption.weight(.semibold))
                }
            }
        } else {
            HStack {
                SectionHeading(title: "Routes", detail: "\(model.routes.count) options")
                Spacer()
                Picker("Extra-time budget", selection: $model.extraMinutes) {
                    Text("+5m").tag(5.0); Text("+10m").tag(10.0); Text("+20m").tag(20.0)
                }.pickerStyle(.menu).font(.caption)
            }
            ForEach(model.routes) { route in
                RouteChoiceCard(route: route, routes: model.routes,
                                ventilation: model.intensity.ventilation,
                                selected: model.selectedRoute == route.id) {
                    model.selectedRoute = route.id; showAir = true; showRouteDetails = true
                }
            }
            if let notice = model.routeNotice { InfoNote(text: notice) }
            if !model.demo {
                Button("Add pollution-avoidance detour") {
                    routeTask?.cancel(); routeTask = Task { await model.addAvoidanceOption() }
                }.font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(model.busy)
            }
        }
    }

    private func activeCard(_ route: WalkRoute) -> some View {
        Surface {
            HStack { SectionHeading(title: "Active walk"); StatusPill(title: "Recording", symbol: "record.circle") }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    Metric(title: "Elapsed", value: "\(Int(context.date.timeIntervalSince(model.walkStarted ?? context.date) / 60)) min")
                    Metric(title: "Distance", value: String(format: "%.0f m", model.trackedMetres))
                    Metric(title: "Est. dose", value: doseText(model.activeEstimate.observedDose))
                }
            }
            InfoNote(text: model.trackingMessage)
            if let message = model.checkpointMessage { InfoNote(symbol: "exclamationmark.triangle", text: message) }
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
                        else { model.voice.speak("\(route.name). \(Int(route.seconds/60)) minutes. \(Int(route.metres)) metres. Estimated dose \(doseText(route.estimate.observedDose)). Sample coverage \(Int(route.estimate.coverage*100)) percent."); speaking = true }
                    } label: { Image(systemName: speaking ? "stop.fill" : "speaker.wave.2").font(.headline).foregroundStyle(Palette.deep).frame(width: 54, height: 54).background(Palette.lime, in: RoundedRectangle(cornerRadius: 16)) }
                        .accessibilityLabel(speaking ? "Stop reading route summary" : "Read route summary aloud")
                }
            }.padding(.horizontal, 22).padding(.vertical, 10).frame(maxWidth: 800).frame(maxWidth: .infinity).background(.regularMaterial)
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
        locationNotice = nil; model.location.request()
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
            guard let current = model.location.currentLocation else { waitingForLocation = true; model.location.request(); return }
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
        moveCamera(.rect(RouteMapPresentation.bounds(model.routes)))
    }
    private func moveCamera(_ position: MapCameraPosition) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { camera = position }
    }
}
