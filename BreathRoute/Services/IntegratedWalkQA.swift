#if DEBUG
import Foundation
import MapKit

/// Isolated session integration checks. No cloud writes, permissions or external provider calls.
@MainActor enum IntegratedWalkQA {
    private static var started = false
    static func runIfRequested() async {
        guard !started, AppModel.usesSimulator, ProcessInfo.processInfo.arguments.contains("--integrated-walk-qa") else { return }
        started = true
        var passed: [String] = [], failure: String?
        func check(_ value: Bool, _ description: String) throws {
            guard value else { throw QAError.failed(description) }; passed.append(description)
        }
        do {
            let start = CLLocationCoordinate2D(latitude: 6.91, longitude: 79.86)
            let middle = CLLocationCoordinate2D(latitude: 6.916, longitude: 79.86)
            let end = CLLocationCoordinate2D(latitude: 6.922, longitude: 79.86)
            let area = WatchArea(id: "qa-area", latitude: middle.latitude, longitude: middle.longitude, pm25: 35, aqi: 4, sampledAt: Date())
            let reading = AirReading(pm25: 35, aqi: 4, date: Date(), demo: false)
            let base = WalkRoute(name: "QA baseline", coordinates: [start, middle, end], metres: 1340, seconds: 1000,
                estimate: ExposureCalculator.estimate([.init(minutes: 1000 / 60, pm25: 35)], ventilation: 0.015), demo: false,
                airSamples: [.init(coordinate: middle, reading: reading, timeFraction: 1)], source: "Mock routing provider")
            let probe = Probe()
            let store = try LocalStore(inMemory: true)
            let model = AppModel(journal: store, walkingRoutes: { origin, destination, _, areas in
                probe.calls.append(areas.count)
                if probe.delayed { try? await Task.sleep(for: .milliseconds(600)) }
                if areas.isEmpty {
                    return [WalkRoute(name: base.name, coordinates: [origin, middle, destination.placemark.coordinate],
                        metres: 1300, seconds: 1000, estimate: base.estimate, demo: false, airSamples: base.airSamples, source: base.source)]
                }
                let offset = CLLocationCoordinate2D(latitude: middle.latitude, longitude: middle.longitude + 0.004)
                return [WalkRoute(name: "QA detour", coordinates: [origin, offset, destination.placemark.coordinate], metres: 1600, seconds: 1200,
                    estimate: ExposureCalculator.estimate([.init(minutes: 20, pm25: 10)], ventilation: 0.015), demo: false,
                    airSamples: [.init(coordinate: offset, reading: .init(pm25: 10, aqi: 1, date: Date(), demo: false), timeFraction: 1)],
                    source: base.source, avoidedAreaCount: areas.count, excludedAreas: areas)]
            }, previewAirRequest: { _ in throw ServiceError.noReading })
            let destination = MKMapItem(placemark: MKPlacemark(coordinate: end)); destination.name = "QA destination"
            model.openWalkPlanner(); await model.plan(start: start, destination: destination)
            try check(probe.calls == [0, 1] && model.routes.count == 2, "planning automatically requests baseline and eligible area-avoidance alternatives")
            try check(model.selected?.name == "QA detour", "planning recommends a complete lower-dose option within the time budget")
            guard let plannedBase = model.routes.first(where: { $0.name == base.name }) else { throw QAError.failed("baseline missing") }
            model.startForCurrentEnvironment(plannedBase)
            try check(model.geofences.enabled && model.geofences.simulated && model.geofences.areas.count == 1 && !model.geofences.notificationAllowed,
                      "starting a walk activates foreground geofencing without notification or Always prompts")
            try await Task.sleep(for: .milliseconds(900))
            model.location.pauseSimulation()
            let before = model.trackedMetres, time = model.trackedSeconds, segments = model.trackedSegments.count
            model.location.location = CLLocation(coordinate: start, altitude: 0, horizontalAccuracy: 4, verticalAccuracy: -1, timestamp: Date().addingTimeInterval(-90))
            model.geofences.evaluate(CLLocation(coordinate: middle, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1, timestamp: Date()), source: "Synthetic QA entry")
            try await Task.sleep(for: .milliseconds(150))
            try check(model.geofences.entry?.aqi == area.aqi && !model.remainingOptions.isEmpty, "verified area entry automatically compares remaining routes")
            try check(model.location.currentLocation == nil && !model.remainingOptions.isEmpty,
                      "paused previews can compare from their known synthetic position without treating an old GPS fix as live")
            try check(model.activeRoute?.id == plannedBase.id || model.activeRoute?.name == base.name, "comparison leaves the selected route active until the user chooses")
            guard let option = model.remainingOptions.first else { throw QAError.failed("remaining options missing") }
            model.switchRemaining(to: option)
            try check(model.activeRoute?.id == option.id && model.trackedMetres == before && model.trackedSeconds == time && model.trackedSegments.count == segments,
                      "switching preserves completed distance, time and exposure intervals")
            try check(model.activeRoute?.demo == true && model.geofences.enabled && model.location.preview?.state == .paused,
                      "switched simulator route retains synthetic labels, pause state and monitoring")
            model.setForeground(false); model.setForeground(true)
            let drafts = try store.read("active-walk", as: ActiveWalkCheckpoint.self)
            try check(drafts.first?.previewMetres == 0 && drafts.first?.recorder.metres == before,
                      "checkpoint saves remaining-path preview progress separately from cumulative distance")
            let activeID = model.activeRoute?.id
            model.switchRemaining(to: plannedBase)
            try check(model.activeRoute?.id == activeID, "an option outside the current comparison cannot be applied")
            probe.delayed = true; model.compareRemaining(avoidAreas: true)
            try await Task.sleep(for: .milliseconds(50))
            model.closeIsolatedPreview()
            try await Task.sleep(for: .milliseconds(750))
            try check(model.activeRoute == nil && model.remainingOptions.isEmpty && !model.remainingBusy && !model.geofences.enabled,
                      "late route responses cannot repopulate a closed session")
            let fixture = AppModel(journal: try LocalStore(inMemory: true), walkingRoutes: { _, _, _, _ in
                throw QAError.failed("offline example called an external route provider")
            })
            fixture.loadDemo()
            guard let road = fixture.routes.last else { throw QAError.failed("fixture missing") }
            fixture.startForCurrentEnvironment(road)
            try await Task.sleep(for: .milliseconds(150))
            fixture.compareRemaining(avoidAreas: true)
            try await Task.sleep(for: .milliseconds(100))
            try check(!fixture.remainingOptions.isEmpty && fixture.remainingOptions.allSatisfy { $0.demo && $0.source == "Illustrative demo" },
                      "integrated example supports automatic awareness and offline synthetic alternatives")
            fixture.closeIsolatedPreview()
        } catch { failure = String(describing: error) }
        let result: [String: Any] = ["passed": passed, "failure": failure ?? NSNull(), "success": failure == nil,
                                   "inMemoryJournal": true, "providersMocked": true, "permissionsRequested": false]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("integrated-walk-qa.json"), options: .atomic)
        }
    }
    private final class Probe { var calls: [Int] = []; var delayed = false }
    private enum QAError: Error { case failed(String) }
}
#endif
