import Foundation
import MapKit

struct AirService {
    func fetch(at coordinate: CLLocationCoordinate2D, key: String) async throws -> AirReading {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ServiceError.missingKey }
        var url = URLComponents(string: "https://api.openweathermap.org/data/2.5/air_pollution")!
        url.queryItems = [.init(name: "lat", value: String(coordinate.latitude)), .init(name: "lon", value: String(coordinate.longitude)), .init(name: "appid", value: key)]
        var request = URLRequest(url: url.url!); request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw ServiceError.provider }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let first = decoded.list.first, let pm = first.components.pm2_5, pm.isFinite, pm >= 0,
              (1...5).contains(first.main.aqi) else { throw ServiceError.noReading }
        return AirReading(pm25: pm, aqi: first.main.aqi, date: Date(timeIntervalSince1970: first.dt), demo: false)
    }
    private struct Response: Decodable {
        let list: [Item]
        struct Item: Decodable {
            let dt: Double; let main: Index; let components: Components
            struct Index: Decodable { let aqi: Int }
            struct Components: Decodable { let pm2_5: Double? }
        }
    }
}

enum ServiceError: LocalizedError {
    case missingKey, provider, noReading, noRoutes
    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your OpenWeather API key in You → Data connection, or explore the labelled demo."
        case .provider: "The air-quality provider could not complete the request. Check your API key, connection, and quota."
        case .noReading: "No usable PM2.5 reading was returned. Missing data is not zero exposure."
        case .noRoutes: "No walking route was returned for these locations. Try another destination."
        }
    }
}

@MainActor
struct RouteService {
    func search(_ query: String) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: .init(latitude: 6.9147, longitude: 79.8640), span: .init(latitudeDelta: 0.15, longitudeDelta: 0.15))
        return try await MKLocalSearch(request: request).start().mapItems
    }
    func routes(from start: CLLocationCoordinate2D, to destination: MKMapItem, intensity: WalkingIntensity, key: String) async throws -> [WalkRoute] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = destination; request.transportType = .walking; request.requestsAlternateRoutes = true
        let response = try await MKDirections(request: request).calculate()
        guard !response.routes.isEmpty else { throw ServiceError.noRoutes }
        var result: [WalkRoute] = []
        for route in response.routes.prefix(3) {
            try Task.checkCancellation()
            let points = route.polyline.points()
            let coordinates = (0..<route.polyline.pointCount).map { points[$0].coordinate }
            // Distance-weighted sample intervals, capped to keep request volume bounded.
            let samples = sampleCoordinates(coordinates, maxCount: 8)
            var segments: [ExposureSegment] = []
            for sample in samples {
                try Task.checkCancellation()
                let reading = try? await AirService().fetch(at: sample.coordinate, key: key)
                segments.append(ExposureSegment(minutes: route.expectedTravelTime / 60 * sample.weight,
                                                pm25: reading?.isFresh == true ? reading?.pm25 : nil))
            }
            result.append(WalkRoute(name: route.name, coordinates: coordinates, metres: route.distance,
                                    seconds: route.expectedTravelTime,
                                    estimate: ExposureCalculator.estimate(segments, ventilation: intensity.ventilation), demo: false))
        }
        return result
    }
    private func sampleCoordinates(_ coordinates: [CLLocationCoordinate2D], maxCount: Int) -> [(coordinate: CLLocationCoordinate2D, weight: Double)] {
        guard coordinates.count > 1 else { return coordinates.map { ($0, 1) } }
        var cumulative = [0.0]
        for i in 1..<coordinates.count {
            let a = CLLocation(latitude: coordinates[i-1].latitude, longitude: coordinates[i-1].longitude)
            let b = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            cumulative.append(cumulative.last! + a.distance(from: b))
        }
        let total = cumulative.last!
        guard total > 0 else { return [(coordinates[0], 1)] }
        let count = min(maxCount, max(2, Int(ceil(total / 500))))
        return (0..<count).map { index in
            let target = total * (Double(index) + 0.5) / Double(count)
            let upper = cumulative.firstIndex(where: { $0 >= target }) ?? coordinates.count - 1
            let lower = max(0, upper - 1)
            let length = cumulative[upper] - cumulative[lower]
            let t = length > 0 ? (target - cumulative[lower]) / length : 0
            let a = coordinates[lower], b = coordinates[upper]
            return (.init(latitude: a.latitude + (b.latitude-a.latitude)*t, longitude: a.longitude+(b.longitude-a.longitude)*t), 1 / Double(count))
        }
    }
    static func demoRoutes(intensity: WalkingIntensity) -> [WalkRoute] {
        let points: [[CLLocationCoordinate2D]] = [
            [.init(latitude: 6.9178, longitude: 79.8637), .init(latitude: 6.9165, longitude: 79.8626), .init(latitude: 6.9144, longitude: 79.8628), .init(latitude: 6.9125, longitude: 79.8645)],
            [.init(latitude: 6.9178, longitude: 79.8637), .init(latitude: 6.9170, longitude: 79.8655), .init(latitude: 6.9144, longitude: 79.8659), .init(latitude: 6.9125, longitude: 79.8645)]
        ]
        return points.enumerated().map { i, coordinates in
            WalkRoute(name: i == 0 ? "Park-side walk" : "Town Hall walk", coordinates: coordinates,
                      metres: i == 0 ? 920 : 820, seconds: i == 0 ? 780 : 660,
                      estimate: ExposureCalculator.estimate([.init(minutes: i == 0 ? 13 : 11, pm25: i == 0 ? 14 : 23)], ventilation: intensity.ventilation), demo: true)
        }
    }
}
