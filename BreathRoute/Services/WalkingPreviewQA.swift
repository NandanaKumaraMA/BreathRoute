#if DEBUG
import Foundation
import CoreLocation

/// Simulator-only, in-memory verification. Never queries/writes HealthKit or uploads records.
@MainActor enum WalkingPreviewQA {
    private static var started = false
    static func runIfRequested() async {
        guard !started, AppModel.usesSimulator, ProcessInfo.processInfo.arguments.contains("--walking-preview-qa") else { return }
        started = true
        var passed: [String] = [], failure: String?
        func check(_ value: Bool, _ description: String) throws {
            guard value else { throw QAError.failed(description) }; passed.append(description)
        }
        do {
            var airAvailable = false
            let store = try LocalStore(inMemory: true), model = AppModel(journal: store, previewAirRequest: { _ in
                guard airAvailable else { throw ServiceError.noReading }
                return AirReading(pm25: 12, aqi: 2, date: Date(), demo: false)
            })
            model.loadDemo()
            guard let route = model.selected else { throw QAError.failed("example route missing") }
            model.startForCurrentEnvironment(route)
            try check(model.activeRoute?.demo == true && model.location.isSimulatingRun, "example starts moving automatically and stays labelled synthetic")
            guard let first = model.location.location else { throw QAError.failed("preview position missing") }
            try await Task.sleep(for: .seconds(2))
            try check(model.location.location.map { $0.distance(from: first) > 1 } == true && model.trackedMetres > 1, "location and recorded path advance along the route")
            try check(model.liveSpeedKmh > 0 && model.livePaceLabel.contains("min/km"), "pace and speed are populated")
            try check((model.location.preview?.exampleMetrics.steps ?? 0) > 0 && (model.location.preview?.exampleMetrics.heartRate ?? 0) > 0,
                      "synthetic steps and body metrics are available")
            try check(model.health.heartRecord == nil && model.health.respiratoryRecord == nil && model.motion.summary == nil,
                      "preview does not fabricate HealthKit records or phone sensor summaries")
            model.toggleSimulatedRun()
            let paused = model.location.preview?.coordinate, metres = model.location.preview?.metres
            try await Task.sleep(for: .seconds(1))
            try check(model.location.preview?.coordinate == paused && model.location.preview?.metres == metres && model.liveSpeedKmh == 0,
                      "pause freezes position and progress")
            model.toggleSimulatedRun()
            try await Task.sleep(for: .seconds(1))
            try check((model.location.preview?.metres ?? 0) > (metres ?? 0) && model.location.isSimulatingRun,
                      "resume continues from the paused position")
            model.finish()
            try check(model.activeRoute == nil && model.trips.count == 1 && model.trips[0].demo && model.trips[0].activity == nil,
                      "finished preview saves only a labelled example without real motion totals")
            try check(try store.read("active-walk", as: ActiveWalkCheckpoint.self).isEmpty, "finish clears the isolated recovery checkpoint")
            let provider = WalkRoute(name: "Synthetic QA provider route", coordinates: route.coordinates, metres: route.metres,
                seconds: route.seconds, estimate: route.estimate, demo: false, airSamples: route.airSamples, source: "QA provider source")
            model.startForCurrentEnvironment(provider)
            try await Task.sleep(for: .seconds(1))
            try check(model.activeRoute?.demo == true && model.activeRoute?.source == provider.source && model.location.isSimulatingRun,
                      "provider route can be previewed while preserving attribution and synthetic activity labelling")
            try check(model.air == nil && model.previewAirMessage != nil, "failed provider request keeps missing air data explicit")
            airAvailable = true; await model.refreshPreviewAir()
            try await Task.sleep(for: .seconds(1))
            try check(model.air?.pm25 == 12 && model.activeEstimate.observedDose != nil && model.activeRoute?.demo == true,
                      "provider air can populate preview exposure without reclassifying synthetic activity")
            model.setForeground(false)
            try check(!model.location.isSimulatingRun && model.location.preview?.state == .paused, "backgrounding pauses synthetic movement")
            model.setForeground(true); model.toggleSimulatedRun()
            try await Task.sleep(for: .milliseconds(700))
            try check(model.location.isSimulatingRun, "cancelled older playback cannot stop a resumed session")
            model.finish()
            try check(model.trips.allSatisfy { $0.demo } && model.trips.count == 2, "all test walks remain examples in an isolated memory store")
            model.startForCurrentEnvironment(provider); model.closeIsolatedPreview()
            try check(model.activeRoute == nil && !model.location.isPreviewLocation && model.trips.count == 2,
                      "closing a separate preview stops playback without saving another walk")
        } catch { failure = String(describing: error) }
        let result: [String: Any] = ["passed": passed, "failure": failure ?? NSNull(), "success": failure == nil,
                                   "simulatorOnly": true, "inMemoryJournal": true, "airProviderMocked": true, "healthKitQueriedOrWritten": false]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("walking-preview-qa.json"), options: .atomic)
        }
    }
    private enum QAError: Error { case failed(String) }
}
#endif
