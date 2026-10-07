import SwiftUI
import MapKit

struct PlannerView: View {
    @Bindable var model: AppModel
    @State private var start: MKMapItem?
    @State private var destination: MKMapItem?
    @State private var searchTarget: SearchTarget?
    @State private var camera: MapCameraPosition = .region(.init(center: .init(latitude: 6.915, longitude: 79.864), span: .init(latitudeDelta: 0.018, longitudeDelta: 0.018)))
    @State private var confirmFinish = false
    enum SearchTarget: String, Identifiable { case start, destination; var id: String { rawValue } }
    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 8) { Eyebrow(text: "Walk with awareness"); Text(model.activeRoute == nil ? "Find your next route." : "One step at a time.").font(.largeTitle.bold()) }
            if model.demo {
                HStack { Label("Demo · illustrative routes and air data", systemImage: "sparkles").font(.subheadline); Spacer(); if model.activeRoute == nil { Button("Exit") { model.leaveDemo() } } }
                    .padding(14).background(Palette.lime.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
            }
            if model.activeRoute == nil {
                Surface {
                    Button { searchTarget = .start } label: { Label(start?.name ?? "Current location", systemImage: "location.circle.fill").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8) }
                    if start != nil { Button("Use current location") { start = nil; model.location.request() }.font(.subheadline) }
                    Divider()
                    Button { searchTarget = .destination } label: { Label(destination?.name ?? "Where would you like to go?", systemImage: "mappin.circle").frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8) }
                    Picker("Walking intensity", selection: $model.intensity) { ForEach(WalkingIntensity.allCases) { Text($0.rawValue).tag($0) } }
                        .disabled(!model.routes.isEmpty)
                    PrimaryButton(title: "Compare walking routes", symbol: "arrow.triangle.branch") {
                        guard let destination else { return }
                        guard let coordinate = start?.placemark.coordinate ?? model.location.location?.coordinate else {
                            model.location.request(); model.error = "Waiting for location. You can select a start point manually instead."; return
                        }
                        Task { await model.plan(start: coordinate, destination: destination); camera = .automatic }
                    }.disabled(destination == nil || model.busy)
                    if model.busy { ProgressView("Finding routes and sampling air quality…") }
                }
            }
            Map(position: $camera) {
                UserAnnotation()
                ForEach(model.routes) { route in
                    MapPolyline(route.polyline).stroke(route.id == model.selectedRoute ? Palette.forest : Color.gray.opacity(0.5), lineWidth: route.id == model.selectedRoute ? 6 : 3)
                }
                if let first = model.selected?.coordinates.first { Marker("Start", systemImage: "figure.walk", coordinate: first).tint(Palette.forest) }
                if let last = model.selected?.coordinates.last { Marker("Destination", coordinate: last).tint(.orange) }
            }.mapControls { MapCompass(); MapScaleView() }.frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 24))
                .accessibilityLabel("Route map. Route distance, time and exposure are also listed below.")
            if let route = model.activeRoute { activeCard(route) }
            else if model.routes.isEmpty {
                Surface { Label("A route that fits your day", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline); Text("Choose two places to compare walking time, distance and estimated exposure. Walking directions depend on MapKit coverage in your area.").foregroundStyle(.secondary); Button("Explore the demo") { model.loadDemo(); camera = .automatic } }
            } else {
                HStack { Text("Your options").font(.title2.bold()); Spacer(); Text("\(model.routes.count) available").font(.caption).foregroundStyle(.secondary) }
                ForEach(model.routes) { route in routeCard(route) }
                if let route = model.selected {
                    PrimaryButton(title: route.demo ? "Start demo session" : "Start walk", symbol: "figure.walk") { model.start(route) }
                    Button { model.voice.speak("\(route.name). \(Int(route.seconds / 60)) minutes. \(Int(route.metres)) metres. Estimated dose: \(doseText(route.estimate.observedDose)). Data coverage \(Int(route.estimate.coverage * 100)) percent. \(route.demo ? "This is a demonstration." : "This is an estimate, not a safety rating.")") } label: { Label("Read route summary aloud", systemImage: "speaker.wave.2") }.padding(.vertical, 8)
                    Button("Stop reading") { model.voice.stop() }.font(.subheadline)
                }
                InfoNote(text: "Estimates use an assumed ventilation rate of \(Int(model.intensity.ventilation * 1000)) L/min. Rankings require complete sampled coverage. Coverage is not a guarantee of spatial accuracy.")
            }
        }.navigationTitle("Explore").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $searchTarget) { target in
                PlaceSearch(title: target == .start ? "Choose a start" : "Choose a destination") { place in
                    if target == .start { start = place } else { destination = place }
                    if model.demo { model.leaveDemo() } else { model.routes = []; model.selectedRoute = nil }
                }
            }
            .confirmationDialog("Finish and save this walk?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Save walk") { model.finish() }
            } message: { Text("Only recorded intervals are saved. Missing intervals will be labelled as incomplete coverage.") }
            .onChange(of: model.routes.map(\.id)) { _, _ in if !model.routes.isEmpty { camera = .automatic } }
    }
    private func routeCard(_ route: WalkRoute) -> some View {
        Button { model.selectedRoute = route.id; camera = .automatic } label: {
            Surface {
                HStack { Text(route.name.isEmpty ? "Walking route" : route.name).font(.headline); Spacer(); Image(systemName: model.selectedRoute == route.id ? "checkmark.circle.fill" : "circle").foregroundStyle(Palette.forest) }
                if route.id == model.bestRouteID { Label("Lowest modelled dose in this comparison", systemImage: "leaf").font(.caption.weight(.semibold)).foregroundStyle(Palette.forest) }
                HStack { Metric(title: "Walking time", value: "\(Int(route.seconds / 60)) min"); Metric(title: "Distance", value: String(format: "%.2f km", route.metres / 1000)) }
                Divider()
                HStack { Text(route.estimate.isComplete ? "Estimated dose" : "Partial dose"); Spacer(); Text(doseText(route.estimate.observedDose)).bold() }.font(.subheadline)
                Text("\(Int(route.estimate.coverage * 100))% sampled coverage · \(route.demo ? "Demo" : "OpenWeather")").font(.caption).foregroundStyle(.secondary)
            }.overlay(RoundedRectangle(cornerRadius: 24).stroke(model.selectedRoute == route.id ? Palette.forest : .clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityAddTraits(model.selectedRoute == route.id ? .isSelected : [])
    }
    private func activeCard(_ route: WalkRoute) -> some View {
        Surface {
            Label(route.demo ? "Demo session" : "Walk in progress", systemImage: "figure.walk").font(.headline)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Metric(title: "Elapsed time", value: "\(Int(context.date.timeIntervalSince(model.walkStarted ?? context.date) / 60)) min")
            }
            HStack { Metric(title: "Recorded distance", value: String(format: "%.0f m", model.trackedMetres)); Metric(title: "Recorded estimated dose", value: doseText(model.activeEstimate.observedDose)) }
            InfoNote(text: model.trackingMessage)
            PrimaryButton(title: "Finish and save", symbol: "checkmark") { confirmFinish = true }
        }
    }
}

struct PlaceSearch: View {
    let title: String
    let select: (MKMapItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var busy = false
    @State private var message = "Search by place, street or city."
    var body: some View {
        NavigationStack {
            List {
                TextField("Search places", text: $query).submitLabel(.search).onSubmit { search() }
                Button("Search", action: search).disabled(busy || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if busy { ProgressView("Searching…") }
                if results.isEmpty { Text(message).foregroundStyle(.secondary) }
                ForEach(Array(results.enumerated()), id: \.offset) { _, place in
                    Button { select(place); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 6) { Text(place.name ?? "Place").font(.headline); Text(place.placemark.title ?? "").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 6)
                    }
                }
            }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    private func search() {
        let submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submitted.isEmpty, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { results = try await RouteService().search(submitted); message = "No matching places. Try adding a city name." }
            catch { results = []; message = error.localizedDescription }
        }
    }
}
