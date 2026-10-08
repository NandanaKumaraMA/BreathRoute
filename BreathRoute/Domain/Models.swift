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

struct TripEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var destination: String
    var metres: Double
    var seconds: Double
    var dose: Double?
    var coverage: Double
    var demo: Bool
    var complete: Bool
}

struct AirReading {
    let pm25: Double
    let aqi: Int
    let date: Date
    let demo: Bool
    var label: String { [1: "Good", 2: "Fair", 3: "Moderate", 4: "Poor", 5: "Very poor"][aqi] ?? "Unavailable" }
    var isFresh: Bool { Date().timeIntervalSince(date) < 3600 && date.timeIntervalSinceNow < 300 }
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
    var polyline: MKPolyline { MKPolyline(coordinates: coordinates, count: coordinates.count) }
}

struct RouteAirSample: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let reading: AirReading?
}

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today", routes = "Explore", journal = "Journal", profile = "You"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .today: "sun.horizon"; case .routes: "map"; case .journal: "chart.xyaxis.line"; case .profile: "person.crop.circle" }
    }
}
