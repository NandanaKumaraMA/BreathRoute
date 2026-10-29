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
    @State private var showAir = false
    @State private var searchMovedArea = false
    @State private var waitingForLocation = false
    @State private var nearbyTask: Task<Void, Never>?
    @State private var fitNearbyWhenLoaded = false
    @State private var pendingComparison = false
    @State private var locationNotice: String?
    @State private var routeTask: Task<Void, Never>?
    @State private var walkTool: WalkTool?
    @State private var toolAction: ToolAction?
    @State private var previewRequest = UUID()
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
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                Page {
                    flowHeader
                    RecoveryCard(model: model)
                    if model.activeRoute == nil {
                        Surface(padding: 16) {
                            journeyFields
                            planningControls
                        }.id("journey")
                    }
                    if model.demo {
                        HStack {
                            Label("Example routes and air data", systemImage: "sparkles").font(.caption).foregroundStyle(Palette.muted)
                            Spacer()
                            if model.activeRoute == nil { Button("Exit example") { model.leaveDemo() }.font(.caption.weight(.semibold)).frame(minHeight: 44) }
                        }
                    }
                    routeMap(height: typeSize.isAccessibilitySize ? 300 : (geometry.size.width >= 800 ? 420 : 310))
                        .id("route-map")
                    if !model.routes.isEmpty || model.activeRoute != nil {
                        mapStatusStrip
                        coverageBanner
                        routeOptions
                    } else {
                        nearbySection
                    }
                    if typeSize.isAccessibilitySize { walkAction }
                    if waitingForLocation { InfoNote(symbol: "location", text: model.location.message) }
                    if let locationNotice { InfoNote(symbol: "location", text: locationNotice) }
                }
            }
            .onChange(of: model.routes.map(\.id)) { _, routes in
                guard !routes.isEmpty else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo("route-map", anchor: .top) }
            }
            .onChange(of: previewRequest) { _, _ in
                guard model.selectedRoute != nil, model.activeRoute == nil, !showRouteDetails else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo("route-map", anchor: .top) }
            }
        }
        .adaptiveNavigationBar()
        .safeAreaInset(edge: .bottom, spacing: 0) { if !typeSize.isAccessibilitySize { walkAction } }
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
                    .navigationTitle("Route map").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { expandedMap = false } } }
                    .sheet(item: $fullMapPlace) { place in
                        NearbyPlaceDetail(place: place, discovery: discovery) { chooseDestination(place) }
                    }
                    .sheet(isPresented: $showFullMapRouteDetails) { RouteInspectionView(model: model) }
            }
        }
        .confirmationDialog("Finish and save this session?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Save walk") { model.finish() }
        } message: { Text("Only recorded intervals are saved. Missing intervals are labelled as incomplete coverage.") }
        .onChange(of: model.routes.map(\.id)) { _, _ in if !model.routes.isEmpty { focusRoutes() } }
        .onChange(of: model.selectedRoute) { _, _ in if !model.routes.isEmpty && model.activeRoute == nil { focusRoutes() } }
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
            if let activeLocation = model.location.location, model.activeRoute != nil, model.followCamera {
                followRunnerCamera(at: activeLocation.coordinate)
                return
            }
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
                if model.activeRoute != nil { liveTurnBanner.padding(12).padding(.trailing, 54) }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if searchMovedArea && model.activeRoute == nil { searchAreaButton }
                    if model.activeRoute?.demo == true {
                        Button {
                            model.toggleSimulatedRun()
                        } label: {
                            Label(model.location.isSimulatingRun ? "Pause example movement" : "Play example movement",
                                  systemImage: model.location.isSimulatingRun ? "pause.circle.fill" : "figure.run.circle.fill")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(Palette.lime)
                                .background(Palette.deep, in: Capsule())
                        }.buttonStyle(PressStyle())
                    } else if !typeSize.isAccessibilitySize {
                        Text(model.routes.isEmpty ? discovery.scope : "\(model.routes.count) walking \(model.routes.count == 1 ? "path" : "paths")")
                            .font(.caption2.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8).foregroundStyle(Palette.ink).background(.regularMaterial, in: Capsule())
                    }
                }.padding(12).padding(.trailing, 54)
            }
            .frame(height: height).clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Palette.line, lineWidth: 0.7))
    }

    /// Real-time turn-by-turn navigation banner powered by MapKit MKRoute.Step during an active walk/run.
    private var liveTurnBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isRunningLive ? "figure.run" : "arrow.turn.up.right")
                .font(.headline).foregroundStyle(Palette.lime)
                .frame(width: 38, height: 38)
                .background(Palette.deep, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.activeRoute?.source == "Apple Maps" ? (model.nextRouteStep?.instructions ?? "Follow your selected path") : "Follow your selected path")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text("\(Int(model.remainingDistanceMetres)) m remaining · \(model.livePaceLabel)")
                    .font(.caption2.weight(.medium)).foregroundStyle(Palette.muted).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
    }

    private func map(expanded: Bool) -> some View {
        ExploreMapView(model: model, discovery: discovery, camera: $camera, style: $mapStyle, elevated: $elevated, showAir: $showAir, destination: destination, region: visibleRegion, expanded: expanded, select: { place in
            if expanded { fullMapPlace = place } else { placeDetail = place }
        }, inspectRoute: { route in
            if model.activeRoute == nil { model.selectedRoute = route.id; previewRequest = UUID() }
        }, cameraChanged: { region in
            visibleRegion = region
            guard camera.positionedByUser, let centre = discovery.centre else { return }
            let distance = CLLocation(latitude: centre.latitude, longitude: centre.longitude).distance(from: CLLocation(latitude: region.center.latitude, longitude: region.center.longitude))
            searchMovedArea = distance > max(250, radius * 0.15)
        }, useLocation: useCurrentLocation, expand: { expandedMap.toggle() })
    }

    private var flowHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.activeRoute == nil ? "Plan a walk" : "Your walk")
                    .font(.system(.title, design: .serif)).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                Text(model.activeRoute == nil ? "Choose a destination, then compare routes." : "Follow your selected path. Keep the app open to record.")
                    .font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Departure forecasts", systemImage: "clock") { showDepartureForecast = true }.disabled(model.activeRoute != nil)
                Button("Geofencing and awareness", systemImage: "location.circle") { walkTool = .geofencing }
                Button("Rerouting tools", systemImage: "arrow.triangle.branch") { walkTool = .rerouting }
                if model.activeRoute == nil {
                    Button("Try an example", systemImage: "sparkles") { model.loadDemo(); focusRoutes() }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                    .background(Palette.surface, in: Circle())
            }.accessibilityLabel("More walking tools")
        }
    }

    private var mapStatusStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show air sample areas", isOn: $showAir).font(.subheadline).tint(Palette.forest)
                .accessibilityHint("Approximate sample areas, not measured pollution boundaries.")
            if showAir { AirMapLegend() }
        }
    }

    @ViewBuilder private var coverageBanner: some View {
        if let route = model.activeRoute ?? model.selected {
            RouteCoverageBanner(route: route, ventilation: model.intensity.ventilation) { showRouteDetails = true }
        }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nearby places").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Menu {
                    Picker("Place type", selection: $nearbyCategory) {
                        ForEach(NearbyCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Search radius", selection: $radius) { Text("1 km").tag(1000.0); Text("3 km").tag(3000.0); Text("5 km").tag(5000.0) }
                    Button("Refresh places", systemImage: "arrow.clockwise") { refreshNearby() }
                } label: { Label(nearbyCategory.rawValue, systemImage: "line.3.horizontal.decrease").font(.caption).frame(minHeight: 44) }
            }
            Text(discovery.scope).font(.caption).foregroundStyle(Palette.muted)
            if discovery.loading { ProgressView("Finding nearby places…").font(.subheadline) }
            else if let message = discovery.message { Text(message).font(.caption).foregroundStyle(Palette.muted) }
            ForEach(discovery.places.prefix(3)) { place in
                Button { chooseDestination(place) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: place.category.symbol).foregroundStyle(Palette.forest).frame(width: 28).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                            Text("\(place.distanceLabel) straight-line distance").font(.caption).foregroundStyle(Palette.muted)
                        }.fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Palette.forest).accessibilityHidden(true)
                    }.padding(14).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityHint("Uses this place as your destination.")
            }
            Button("Search for another place") { searchTarget = .destination }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }
    }

    private var searchAreaButton: some View {
        Button { origin = .map; refreshNearby() } label: {
            Label("Search this area", systemImage: "arrow.clockwise").font(.caption.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10).foregroundStyle(Palette.lime).background(Palette.deep, in: Capsule())
        }.buttonStyle(PressStyle())
    }

    private var journeyFields: some View {
        VStack(spacing: 0) {
            journeyField(title: "From", value: start?.name ?? "My current location", symbol: "location.circle", target: .start)
            Divider()
            journeyField(title: "To", value: destination?.name ?? (model.demo ? "Example destination" : "Where would you like to go?"), symbol: "mappin.circle", target: .destination)
        }
    }
    private func journeyField(title: String, value: String, symbol: String, target: SearchTarget) -> some View {
        Button { searchTarget = target } label: {
            HStack(spacing: 12) {
                if !typeSize.isAccessibilitySize { Image(systemName: symbol).font(.title3).foregroundStyle(Palette.forest).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.caption).foregroundStyle(Palette.muted)
                    Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize { Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(Palette.forest).accessibilityHidden(true) }
            }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(title): \(value). Change \(target == .start ? "start" : "destination")")
    }

    @ViewBuilder private var planningControls: some View {
        if model.activeRoute == nil {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
                Label("Pace", systemImage: "figure.walk").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                Picker("Walking intensity", selection: $model.intensity) {
                    Text("Easy").tag(WalkingIntensity.easy)
                    Text("Brisk").tag(WalkingIntensity.brisk)
                    Text("Fast").tag(WalkingIntensity.fast)
                }.pickerStyle(.menu).font(.subheadline.weight(.semibold)).disabled(!model.routes.isEmpty)
                if !typeSize.isAccessibilitySize { Spacer() }
                if start != nil {
                    Button("Use my location") { start = nil; clearRoutes(); useCurrentLocation() }.font(.caption.weight(.semibold))
                }
            }
            if !model.demo {
                PrimaryButton(title: pendingComparison ? "Getting location…" : (model.routes.isEmpty ? "Compare routes" : "Update routes"), symbol: "arrow.triangle.branch") { compare() }
                    .disabled(destination == nil || model.busy || pendingComparison)
            }
            if model.busy {
                HStack(spacing: 12) { ProgressView().tint(Palette.forest); Text("Finding paths and sampling air…").font(.subheadline).foregroundStyle(Palette.muted); Spacer(); Button("Cancel") { routeTask?.cancel(); model.cancelPlanning(); pendingComparison = false; waitingForLocation = false } }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    @ViewBuilder private var routeOptions: some View {
        if let route = model.activeRoute {
            activeCard(route)
            ActiveMotionCard(model: model, demo: route.demo)
            if !route.demo {
                Button { walkTool = .rerouting } label: { Label("Compare the remaining walk", systemImage: "arrow.triangle.branch").font(.subheadline.weight(.semibold)) }.frame(minHeight: 44)
            }
        } else if model.routes.isEmpty {
            Surface {
                HStack(spacing: 12) {
                    Image(systemName: "leaf.fill").font(.title3).foregroundStyle(Color(hex: 0x1D8348))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Preview clean-air paths & live 3D running").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        Text("Compare low-pollution park corridors against main roads.").font(.caption).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button("Load demo") { model.loadDemo(); focusRoutes() }.font(.caption.weight(.semibold))
                }
            }
        } else {
            SectionHeading(title: "Choose a route", detail: "\(model.routes.count) options")
            ForEach(model.routes) { route in
                RouteChoiceCard(route: route, routes: model.routes,
                                ventilation: model.intensity.ventilation,
                                selected: model.selectedRoute == route.id) {
                    model.selectedRoute = route.id; previewRequest = UUID()
                }
            }
            if let notice = model.routeNotice { InfoNote(text: notice) }
            if !model.demo, model.hasAvoidableAreas {
                Button {
                    routeTask?.cancel(); routeTask = Task { await model.addAvoidanceOption() }
                } label: {
                    Label("Find an alternative around higher-AQI samples", systemImage: "leaf.arrow.triangle.circlepath")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }.disabled(model.busy)
            }
        }
    }

    private func activeCard(_ route: WalkRoute) -> some View {
        Surface {
            HStack {
                SectionHeading(title: model.isRunningLive ? "Live run telemetry" : "Live walk telemetry")
                Spacer()
                StatusPill(title: "Live GPS", symbol: route.isCleanAirPath ? "leaf.fill" : "location.north.line.fill")
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], spacing: 14) {
                    Metric(title: "Elapsed", value: "\(Int(context.date.timeIntervalSince(model.walkStarted ?? context.date) / 60))m \(Int(context.date.timeIntervalSince(model.walkStarted ?? context.date)) % 60)s")
                    Metric(title: "Live pace", value: model.livePaceLabel)
                    Metric(title: "Speed", value: String(format: "%.1f km/h", model.liveSpeedKmh))
                    Metric(title: "Covered", value: String(format: "%.0f m", model.trackedMetres))
                    Metric(title: "Remaining", value: String(format: "%.0f m", model.remainingDistanceMetres))
                    Metric(title: "Est. PM2.5 dose", value: doseText(model.activeEstimate.observedDose))
                }
            }
            InfoNote(text: model.trackingMessage)
            if let message = model.checkpointMessage { InfoNote(symbol: "exclamationmark.triangle", text: message) }
        }
    }

    @ViewBuilder private var walkAction: some View {
        if model.activeRoute != nil || model.selected != nil {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                PrimaryButton(title: model.activeRoute != nil ? "Finish walk" : (model.demo ? "Start example walk" : "Start this walk"),
                              symbol: model.activeRoute != nil ? "checkmark" : (model.intensity == .fast ? "figure.run" : "location.north.line.fill")) {
                    if model.activeRoute != nil { confirmFinish = true }
                    else if let route = model.selected {
                        model.start(route)
                        if let first = route.coordinates.first { followRunnerCamera(at: first) }
                    }
                }
                if let route = model.selected, model.activeRoute == nil {
                    Button {
                        if speaking { model.voice.stop(); speaking = false }
                        else { model.voice.speak("\(route.name). \(route.isCleanAirPath ? "Lower sampled air-quality index." : "") \(Int(route.seconds/60)) minutes. \(Int(route.metres)) metres. Estimated dose \(doseText(route.estimate.observedDose))."); speaking = true }
                    } label: {
                        HStack {
                            if typeSize.isAccessibilitySize {
                                Text(speaking ? "Stop reading" : "Read route summary").font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            Image(systemName: speaking ? "stop.fill" : "speaker.wave.2").font(.system(size: 20, weight: .semibold)).accessibilityHidden(true)
                        }.padding(.horizontal, typeSize.isAccessibilitySize ? 16 : 0)
                            .foregroundStyle(Palette.deep).frame(minWidth: 54, maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: 54)
                            .background(Palette.lime, in: RoundedRectangle(cornerRadius: 16))
                    }
                        .accessibilityLabel(speaking ? "Stop reading route summary" : "Read route summary aloud")
                }
            }.padding(.horizontal, typeSize.isAccessibilitySize ? 0 : 22).padding(.vertical, 10).frame(maxWidth: 800).frame(maxWidth: .infinity).background(.regularMaterial)
        }
    }

    private func followRunnerCamera(at coordinate: CLLocationCoordinate2D) {
        let cam = MapCamera(
            centerCoordinate: coordinate,
            distance: model.isRunningLive ? 380 : 460,
            heading: model.location.headingDegrees,
            pitch: model.pitch3D ? 55 : 0
        )
        withAnimation(reduceMotion ? nil : .linear(duration: 0.8)) {
            camera = .camera(cam)
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
        if model.activeRoute != nil { followRunnerCamera(at: location.coordinate); return }
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
