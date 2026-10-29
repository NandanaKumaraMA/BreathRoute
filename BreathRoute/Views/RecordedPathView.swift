import SwiftUI
import MapKit

struct RecordedPathLayers: MapContent {
    let points: [RecordedPathPoint]
    var body: some MapContent {
        ForEach(legs, id: \.id) { leg in
            if leg.coordinates.count > 1 {
                MapPolyline(coordinates: leg.coordinates).stroke(.white.opacity(0.9), lineWidth: 8)
                MapPolyline(coordinates: leg.coordinates).stroke(Color(hex: 0x187AAB), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
    }
    private var legs: [RecordedMapLeg] {
        points.reduce(into: []) { result, point in
            if point.startsNewLeg || result.isEmpty { result.append(RecordedMapLeg(id: result.count, coordinates: [])) }
            result[result.count - 1].coordinates.append(point.coordinate.mapCoordinate)
        }
    }
}
private struct RecordedMapLeg { let id: Int; var coordinates: [CLLocationCoordinate2D] }

struct RecordedPathView: View {
    let points: [RecordedPathPoint]
    let planned: [GeoCoordinate]
    let demo: Bool
    @State private var camera: MapCameraPosition = .automatic
    @State private var pointCount = 0
    @State private var replayTask: Task<Void, Never>?
    @State private var replaying = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var shown: [RecordedPathPoint] { Array(points.prefix(pointCount)) }
    var body: some View {
        Surface {
            SectionHeading(title: points.isEmpty ? "Planned path" : "Recorded GPS path", detail: "\(points.count) fixes")
            Map(position: $camera) {
                if planned.count > 1 { MapPolyline(coordinates: planned.map(\.mapCoordinate)).stroke(.gray, style: StrokeStyle(lineWidth: 3, dash: [5, 5])) }
                RecordedPathLayers(points: shown)
                if let first = points.first?.coordinate ?? planned.first { Marker("A · Start", coordinate: first.mapCoordinate).tint(Palette.deep) }
                if let latest = shown.last { Marker("Last shown fix", coordinate: latest.coordinate.mapCoordinate).tint(Color(hex: 0x187AAB)) }
                else if let end = planned.last { Marker("B · Destination", coordinate: end.mapCoordinate).tint(Palette.deep) }
            }.mapStyle(.standard(pointsOfInterest: .excludingAll)).mapControls { MapCompass(); MapScaleView() }
                .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 18))
            if !points.isEmpty {
                Label("Blue: recorded · grey dashed: last planned path", systemImage: "map").font(.caption).foregroundStyle(Palette.muted)
                if points.count > 1 {
                    Slider(value: Binding(get: { Double(pointCount) }, set: { stopReplay(); pointCount = Int($0) }), in: 1...Double(points.count), step: 1)
                        .accessibilityLabel("Recorded path replay").accessibilityValue("\(pointCount) of \(points.count) fixes")
                    Button(replaying ? "Stop replay" : "Replay recorded points", systemImage: replaying ? "stop.fill" : "play.fill") {
                        if replaying { stopReplay() } else { replay() }
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                if let fix = shown.last {
                    Text("Fix \(pointCount) of \(points.count) · \(fix.date.formatted(date: .abbreviated, time: .standard)) · reported accuracy ±\(Int(fix.accuracy)) m")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                InfoNote(text: "Breaks in the blue line are unobserved intervals. Replay advances recorded fixes at an accelerated rate; it does not reconstruct movement between them. GPS coordinates stay in this device’s journal and are excluded from the shared summary.")
            } else {
                InfoNote(text: demo ? "This is a synthetic planned route. Demo sessions record no actual GPS fixes." : "No GPS path was recorded. Earlier saved walks still retain their summary.")
            }
        }.onAppear { pointCount = points.count; fit() }
            .onDisappear { stopReplay() }
    }
    private func fit() {
        var rect = MKMapRect.null
        for coordinate in planned + points.map(\.coordinate) where coordinate.isValid {
            let point = MKMapPoint(coordinate.mapCoordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        if !rect.isNull {
            let latitude = (points.first?.coordinate ?? planned.first)?.latitude ?? 0
            let pad = MKMapPointsPerMeterAtLatitude(latitude) * 250
            camera = .rect(rect.insetBy(dx: -max(pad, rect.size.width * 0.2), dy: -max(pad, rect.size.height * 0.2)))
        }
    }
    private func replay() {
        stopReplay(); pointCount = 1; replaying = true
        replayTask = Task { @MainActor in
            while pointCount < points.count {
                do { try await Task.sleep(for: .milliseconds(reduceMotion ? 700 : 400)); try Task.checkCancellation() }
                catch { return }
                pointCount += 1
            }
            replaying = false; replayTask = nil
        }
    }
    private func stopReplay() { replayTask?.cancel(); replayTask = nil; replaying = false }
}

struct RecoveryCard: View {
    @Bindable var model: AppModel
    @State private var discard = false
    @State private var previewSavedRoute = false
    var body: some View {
        if let draft = model.pendingRecovery {
            Surface {
                Label("An unfinished walk is saved", systemImage: "arrow.counterclockwise.circle.fill").font(.headline).foregroundStyle(Palette.forest)
                Text(draft.route.demo ? "Demo · \(draft.route.name)" : draft.destination).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                Text("Last saved \(draft.savedAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(draft.recorder.metres)) m recorded · \(draft.recorder.path.count) GPS fixes")
                    .font(.caption).foregroundStyle(Palette.muted)
                InfoNote(text: "The app was closed before this walk finished. Resume keeps recorded portions and starts a new path section. Time while the app was closed remains unobserved.")
                PrimaryButton(title: "Resume saved walk", symbol: "figure.walk") { model.resumeRecovery() }
                if AppModel.usesSimulator {
                    Button("Preview this saved route", systemImage: "play.circle") { previewSavedRoute = true }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    Text("Preview uses a separate temporary journal. This unfinished walk stays unchanged.")
                        .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                Button("Save recorded portion") { model.saveRecoveryPortion() }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                Button("Discard unfinished walk", role: .destructive) { discard = true }.font(.caption).frame(minHeight: 44)
            }.fullScreenCover(isPresented: $previewSavedRoute) { SavedRoutePreview(route: draft.route) }
            .confirmationDialog("Discard this unfinished walk?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard recorded portions", role: .destructive) { model.discardRecovery() }
            } message: { Text("Its unfinished recording will be removed from this device.") }
        } else if model.unreadableRecovery {
            Surface {
                SectionHeading(title: "Unfinished walk needs attention")
                Text(model.checkpointMessage ?? "The saved recording could not be read.").font(.subheadline).foregroundStyle(Palette.muted)
                Button("Discard unreadable unfinished walk", role: .destructive) { discard = true }.frame(minHeight: 44)
            }.confirmationDialog("Discard the unreadable unfinished walk?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard unfinished walk", role: .destructive) { model.discardRecovery() }
            }
        }
    }
}


/// Previewing a recovery route must not overwrite the user's unfinished checkpoint.
private struct SavedRoutePreview: View {
    let route: SavedRoute
    @State private var previewModel: AppModel?
    @State private var issue: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Separate simulator preview").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Button("Done") { previewModel?.closeIsolatedPreview(); dismiss() }.font(.headline).frame(minHeight: 44)
            }.padding(.horizontal, 22).background(Palette.canvas)
            if let previewModel { NavigationStack { PlannerView(model: previewModel) } }
            else if let issue { ContentUnavailableView("Preview unavailable", systemImage: "map", description: Text(issue)) }
            else { ProgressView("Opening preview…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.background(Palette.canvas)
            .task {
                guard previewModel == nil, issue == nil else { return }
                do {
                    guard route.isValid else { throw CocoaError(.coderInvalidValue) }
                    let model = AppModel(journal: try LocalStore(inMemory: true))
                    let path = route.walkRoute
                    model.routes = [path]; model.selectedRoute = path.id
                    model.startForCurrentEnvironment(path)
                    previewModel = model
                } catch { issue = "The saved route could not be previewed. Its original recording has not been changed." }
            }
            .onDisappear { previewModel?.closeIsolatedPreview() }
    }
}
