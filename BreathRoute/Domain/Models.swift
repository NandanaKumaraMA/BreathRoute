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

struct RouteStep: Identifiable, Sendable {
    let id = UUID()
    let instructions: String
    let metres: Double
    let coordinate: GeoCoordinate
}

struct RoutePollutionSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let reading: AirReading?
    var isCleanAir: Bool {
        guard let reading, reading.isFresh || reading.demo else { return false }
        return reading.aqi <= 2 && reading.pm25 <= 18.0
    }
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
    var excludedAreas: [WatchArea] = []
    var steps: [RouteStep] = []

    var polyline: MKPolyline { MKPolyline(coordinates: coordinates, count: coordinates.count) }

    /// True when every sampled interval has Good/Fair air (AQI 1–2, PM2.5 <= 18 µg/m³).
    var isCleanAirPath: Bool {
        guard !airSamples.isEmpty else { return false }
        let usable = airSamples.compactMap(\.reading).filter { $0.isFresh || $0.demo }
        guard usable.count == airSamples.count else { return false }
        return usable.allSatisfy { $0.aqi <= 2 && $0.pm25 <= 18.0 }
    }

    var pollutedSampleCount: Int {
        airSamples.compactMap(\.reading).filter { ($0.isFresh || $0.demo) && ($0.aqi >= 3 || $0.pm25 > 18.0) }.count
    }

    var maxAQI: Int? {
        airSamples.compactMap(\.reading).filter { $0.isFresh || $0.demo }.map(\.aqi).max()
    }

    /// Splits the route polyline into colour-coded segments mapped to the nearest air-quality sample.
    var pollutionSegments: [RoutePollutionSegment] {
        guard coordinates.count > 1 else { return [] }
        guard !airSamples.isEmpty else {
            return [RoutePollutionSegment(id: 0, coordinates: coordinates, reading: nil)]
        }
        var result: [RoutePollutionSegment] = []
        var group: [CLLocationCoordinate2D] = []
        var sampleIndex: Int?
        for i in 0..<(coordinates.count - 1) {
            let a = coordinates[i], b = coordinates[i + 1]
            let midLat = (a.latitude + b.latitude) * 0.5
            let midLon = (a.longitude + b.longitude) * 0.5
            let midLoc = CLLocation(latitude: midLat, longitude: midLon)
            let nearest = airSamples.indices.min { left, right in
                midLoc.distance(from: CLLocation(latitude: airSamples[left].coordinate.latitude, longitude: airSamples[left].coordinate.longitude)) <
                midLoc.distance(from: CLLocation(latitude: airSamples[right].coordinate.latitude, longitude: airSamples[right].coordinate.longitude))
            }
            if nearest == sampleIndex, !group.isEmpty { group.append(b) }
            else {
                if let sampleIndex, group.count > 1 {
                    result.append(RoutePollutionSegment(id: result.count, coordinates: group, reading: airSamples[sampleIndex].reading))
                }
                sampleIndex = nearest; group = [a, b]
            }
        }
        if let sampleIndex, group.count > 1 { result.append(RoutePollutionSegment(id: result.count, coordinates: group, reading: airSamples[sampleIndex].reading)) }
        return result
    }

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
                   source: source, avoidedAreaCount: avoidedAreaCount, excludedAreas: excludedAreas.isEmpty ? nil : excludedAreas)
    }
}
extension SavedRoute {
    var walkRoute: WalkRoute {
        WalkRoute(name: name, coordinates: coordinates.map(\.mapCoordinate), metres: metres, seconds: seconds,
                  estimate: estimate, demo: demo, airSamples: airSamples.map { RouteAirSample(coordinate: $0.coordinate.mapCoordinate, reading: $0.reading, timeFraction: $0.timeFraction) },
                  source: source, avoidedAreaCount: avoidedAreaCount, excludedAreas: excludedAreas ?? [])
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today", routes = "Explore", journal = "Journal", profile = "You"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .today: "sun.horizon"; case .routes: "map"; case .journal: "chart.xyaxis.line"; case .profile: "person.crop.circle" }
    }
}
