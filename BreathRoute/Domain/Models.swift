import Foundation
import CoreLocation
import MapKit

enum WalkingIntensity: String, Codable, CaseIterable, Identifiable {
    case easy = "Easy", brisk = "Brisk", fast = "Fast"
    var id: String { rawValue }
    // Coursework modelling assumptions, not personalised physiological measurements.
    var ventilation: Double { switch self { case .easy: 0.015; case .brisk: 0.025; case .fast: 0.035 } }
}

struct SymptomEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var kind = "Cough"
    var severity = 1
    var notes = ""
    var tripID: UUID?
}

struct WalkRoute: Identifiable {
    let id = UUID()
    let name: String
    let coordinates: [CLLocationCoordinate2D]
    let metres: Double
    let seconds: Double
    let estimate: ExposureEstimate
    let demo: Bool
    var airSamples: [RouteAirSample] = []
    var source = "Illustrative demo"
    var avoidedAreaCount = 0
    var polyline: MKPolyline { MKPolyline(coordinates: coordinates, count: coordinates.count) }
    func sampledEstimate(ventilation: Double) -> ExposureEstimate {
        ExposureCalculator.estimate(airSamples.map { sample in
            ExposureSegment(minutes: seconds / 60 * sample.timeFraction,
                            pm25: sample.reading?.isFresh == true ? sample.reading?.pm25 : nil)
        }, ventilation: ventilation)
    }
}

struct RouteAirSample: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let reading: AirReading?
    let timeFraction: Double
}

extension GeoCoordinate {
    nonisolated init(_ coordinate: CLLocationCoordinate2D) { latitude = coordinate.latitude; longitude = coordinate.longitude }
    nonisolated var mapCoordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
extension WalkRoute {
    var snapshot: SavedRoute {
        SavedRoute(name: name, coordinates: coordinates.map(GeoCoordinate.init), metres: metres, seconds: seconds,
                   estimate: estimate, demo: demo, airSamples: airSamples.map { SavedAirSample(coordinate: GeoCoordinate($0.coordinate), reading: $0.reading, timeFraction: $0.timeFraction) },
                   source: source, avoidedAreaCount: avoidedAreaCount)
    }
}
extension SavedRoute {
    var walkRoute: WalkRoute {
        WalkRoute(name: name, coordinates: coordinates.map(\.mapCoordinate), metres: metres, seconds: seconds,
                  estimate: estimate, demo: demo, airSamples: airSamples.map { RouteAirSample(coordinate: $0.coordinate.mapCoordinate, reading: $0.reading, timeFraction: $0.timeFraction) },
                  source: source, avoidedAreaCount: avoidedAreaCount)
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today", routes = "Explore", journal = "Journal", profile = "You"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .today: "sun.horizon"; case .routes: "map"; case .journal: "chart.xyaxis.line"; case .profile: "person.crop.circle" }
    }
}
