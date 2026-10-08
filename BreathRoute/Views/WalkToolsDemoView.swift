import SwiftUI
import MapKit

/// An isolated preview: no AppModel, location permissions, notifications or saved trips.
struct WalkToolsDemoView: View {
    private enum Step: Int { case outside, entered, compared, switched }
    @State private var step: Step = .outside
    @State private var gate = AreaEntryGate()
    @State private var entryDetected = false
    @State private var camera: MapCameraPosition = .region(.init(
        center: .init(latitude: 6.9145, longitude: 79.8670),
        span: .init(latitudeDelta: 0.019, longitudeDelta: 0.012)))
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private let outside = CLLocationCoordinate2D(latitude: 6.9212, longitude: 79.8662)
    private let entryPoint = CLLocationCoordinate2D(latitude: 6.9175, longitude: 79.8662)
    private let futurePoint = CLLocationCoordinate2D(latitude: 6.9120, longitude: 79.8662)
    private let destination = CLLocationCoordinate2D(latitude: 6.9070, longitude: 79.8662)
    private var original: [CLLocationCoordinate2D] { [entryPoint, futurePoint, destination] }
    private var detour: [CLLocationCoordinate2D] {
        [entryPoint, .init(latitude: 6.9175, longitude: 79.8702),
         .init(latitude: 6.9070, longitude: 79.8702), destination]
    }
    private func area(id: String, point: CLLocationCoordinate2D, now: Date) -> WatchArea {
        WatchArea(id: id, latitude: point.latitude, longitude: point.longitude, pm25: 35, aqi: 4, sampledAt: now)
    }
    private func estimate(minutes: Double, pm25: Double) -> ExposureEstimate {
        ExposureCalculator.estimate([.init(minutes: minutes, pm25: pm25)], ventilation: 0.015)
    }
    private var recommended: String? {
        let baseline = estimate(minutes: 18, pm25: 35), alternative = estimate(minutes: 30, pm25: 18)
        return RouteChoicePolicy.recommended([
            .init(id: "original", seconds: 18 * 60, dose: baseline.observedDose, complete: baseline.isComplete),
            .init(id: "detour", seconds: 30 * 60, dose: alternative.observedDose, complete: alternative.isComplete)
        ], extraMinutes: 20)
    }
    private var detourAvoidsArea: Bool {
        !area(id: "future", point: futurePoint, now: Date()).intersects(detour.map { [$0.longitude, $0.latitude] })
    }
    private var stageTitle: String {
        switch step {
        case .outside: "1 · Outside the example area"
        case .entered: "2 · Example entry detected"
        case .compared: "3 · Compare remaining paths"
        case .switched: "4 · Example route switched"
        }
    }

    var body: some View {
        NavigationStack {
            Page {
                PageHeader(title: "See it in motion.", subtitle: "Interactive feature preview", symbol: "play.circle")
                InfoNote(symbol: "sparkles", text: "Synthetic readings and sketched paths. This preview does not change your walk, enable live alerts or save a trip.")
                previewMap
                Surface {
                    StatusPill(title: "Demo · synthetic data", symbol: "sparkles")
                    Text(stageTitle).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                    stepContent
                }
                if step.rawValue >= Step.compared.rawValue {
                    routeCard(name: "Original example", minutes: 18, pm25: 35, recommended: recommended == "original", detail: "Crosses the next example area.")
                    routeCard(name: "Example detour", minutes: 30, pm25: 18, recommended: recommended == "detour", detail: detourAvoidsArea ? "Sketched geometry stays outside the next 250 m example area. Adds 12 minutes." : "Geometry intersects the example area; review this preview.")
                    InfoNote(text: "A 20-minute extra-time budget is used only in this preview. Dose uses synthetic PM2.5 and an assumed 15 L/min ventilation; these values are not measurements or a health guarantee.")
                    if step == .compared {
                        PrimaryButton(title: "Switch to example detour", symbol: "arrow.triangle.branch") { step = .switched }
                    } else {
                        Surface {
                            Label("Example progress preserved", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Palette.forest)
                            progressMetrics
                            Text("These are synthetic completed intervals. In a live walk, switching preserves the intervals you actually recorded.").font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                }
                Button("Restart preview", systemImage: "arrow.counterclockwise") {
                    step = .outside; gate = AreaEntryGate(); entryDetected = false
                }.frame(minHeight: 44).font(.subheadline.weight(.semibold))
            }
            .navigationTitle("Feature preview").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.large])
    }

    private var previewMap: some View {
        Map(position: $camera) {
            MapCircle(center: entryPoint, radius: 250).foregroundStyle(.orange.opacity(0.16)).stroke(.orange.opacity(0.7), lineWidth: 1.5)
            MapCircle(center: futurePoint, radius: 250).foregroundStyle(.orange.opacity(0.16)).stroke(.orange.opacity(0.7), lineWidth: 1.5)
            MapPolyline(coordinates: step == .outside ? [outside] + original : original)
                .stroke(step == .switched ? Color.gray.opacity(0.55) : Palette.deep, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            if step.rawValue >= Step.compared.rawValue {
                MapPolyline(coordinates: detour).stroke(step == .switched ? Palette.forest : Color.purple, style: StrokeStyle(lineWidth: step == .switched ? 6 : 4, lineCap: .round, dash: step == .switched ? [] : [6, 5]))
            }
            Annotation("Example walker", coordinate: step == .outside ? outside : entryPoint) {
                Image(systemName: "figure.walk").font(.headline).foregroundStyle(Palette.lime)
                    .frame(width: 36, height: 36).background(Palette.deep, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 3))
            }
            Marker("Example destination", systemImage: "flag.fill", coordinate: destination).tint(Palette.forest)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: typeSize.isAccessibilitySize ? 320 : 280)
        .overlay(alignment: .topLeading) { Text("Sketched example paths").font(.caption2.weight(.semibold)).padding(10).background(.regularMaterial, in: Capsule()).padding(12) }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityLabel("Interactive example map. Two synthetic 250 metre sample areas. \(stageTitle). Paths are sketched examples, not walking directions.")
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .outside:
            Text("Move the example walker into a 250 m sample area. The entry check uses synthetic AQI 4/5, PM2.5 35 µg/m³ and 10 m location accuracy.").font(.subheadline).foregroundStyle(Palette.muted)
            PrimaryButton(title: "Simulate entering an area", symbol: "location.circle") {
                let now = Date(), sample = area(id: "entry", point: entryPoint, now: Date())
                _ = gate.update(areas: [sample], latitude: outside.latitude, longitude: outside.longitude, accuracy: 10, now: now)
                entryDetected = gate.update(areas: [sample], latitude: entryPoint.latitude, longitude: entryPoint.longitude, accuracy: 10, now: now) != nil
                step = .entered
            }
        case .entered:
            Label(entryDetected ? "Geofencing preview: entry detected" : "Entry could not be confirmed", systemImage: entryDetected ? "location.circle.fill" : "location.slash").font(.headline).foregroundStyle(Palette.forest)
            Text("A live entry can show an in-app message and an optional local notification. This preview sends no notification.").font(.subheadline).foregroundStyle(Palette.muted)
            Text("Compare a remaining path with a detour around the next example area. The area you are already inside is omitted from avoidance.").font(.caption).foregroundStyle(Palette.muted)
            PrimaryButton(title: "Compare example routes", symbol: "arrow.triangle.branch") { step = .compared }
        case .compared:
            Text("Review time and estimated dose below. The example detour avoids the next circle and fits the preview’s 20-minute extra-time budget.").font(.subheadline).foregroundStyle(Palette.muted)
        case .switched:
            Label("Rerouting preview: detour selected", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Palette.forest)
            Text("The green path is now selected. Your completed example progress stays intact.").font(.subheadline).foregroundStyle(Palette.muted)
        }
    }
    private func routeCard(name: String, minutes: Double, pm25: Double, recommended: Bool, detail: String) -> some View {
        Surface {
            Text(name).font(.headline).foregroundStyle(Palette.ink)
            if recommended { StatusPill(title: "Lower example dose", symbol: "wind") }
            HStack(spacing: 16) {
                Metric(title: "Example time", value: "\(Int(minutes)) min")
                Metric(title: "Synthetic dose", value: doseText(estimate(minutes: minutes, pm25: pm25).observedDose))
            }
            Text(detail).font(.caption).foregroundStyle(Palette.muted)
        }
    }
    @ViewBuilder private var progressMetrics: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) { retainedMetrics }
        } else { HStack(spacing: 12) { retainedMetrics } }
    }
    @ViewBuilder private var retainedMetrics: some View {
        Metric(title: "Example elapsed", value: "3 min")
        Metric(title: "Example distance", value: "120 m")
        Metric(title: "Synthetic dose", value: doseText(estimate(minutes: 3, pm25: 35).observedDose))
    }
}
