import Foundation
import MapKit

struct AirService {
    func fetch(at coordinate: CLLocationCoordinate2D, key: String) async throws -> AirReading {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ServiceError.missingKey }
        var url = URLComponents(string: "https://api.openweathermap.org/data/2.5/air_pollution")!
        url.queryItems = [.init(name: "lat", value: String(coordinate.latitude)), .init(name: "lon", value: String(coordinate.longitude)), .init(name: "appid", value: key)]
        var request = URLRequest(url: url.url!); request.timeoutInterval = 20
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch is CancellationError { throw CancellationError() }
        catch { throw ServiceError.network }
        guard let response = response as? HTTPURLResponse else { throw ServiceError.provider }
        switch response.statusCode {
        case 200: break
        case 401, 403: throw ServiceError.unauthorized
        case 429: throw ServiceError.quota
        default: throw ServiceError.provider
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { throw ServiceError.noReading }
        guard let first = decoded.list.first, let pm = first.components.pm2_5, pm.isFinite, pm >= 0,
              (1...5).contains(first.main.aqi), first.dt.isFinite, first.dt > 0 else { throw ServiceError.noReading }
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
    case missingKey, unauthorized, quota, network, provider, noReading, noRoutes
    case routingMissingKey, routingDenied, routingQuota, routingProvider, routingOptionsRejected, areaNotAvoided, noAvoidableAreas
    var errorDescription: String? {
        switch self {
        case .missingKey: "The air-data connection is not configured in this build. Add BREATHE_OPENWEATHER_KEY to Config.local.xcconfig and rebuild, or try an example."
        case .unauthorized: "OpenWeather rejected the API key. Check the saved key and its activation status in your OpenWeather account."
        case .quota: "OpenWeather's request limit has been reached. Wait before trying again, and check your account's usage allowance."
        case .network: "Air-quality data could not be reached. Check your internet connection and try again."
        case .provider: "The air-quality provider could not complete the request. Check your API key, connection, and quota."
        case .noReading: "No usable PM2.5 reading was returned. Missing data is not zero exposure."
        case .noRoutes: "No walking route was returned for these locations. Try another destination."
        case .routingMissingKey: "Walking directions are unavailable here. Configure BREATHE_GEOAPIFY_KEY in Config.local.xcconfig and rebuild to use walking routes and area avoidance."
        case .routingDenied: "openrouteservice rejected the key or account access. Check the routing key and account used by this build."
        case .routingQuota: "The openrouteservice request limit was reached. Check your account allowance before trying again."
        case .routingProvider: "The walking-route provider could not be reached. Check your connection and try again."
        case .routingOptionsRejected: "The provider could not route with these options. Try a different destination or fewer avoidance areas."
        case .areaNotAvoided: "The returned path intersects a selected monitoring area. It has not been accepted as an avoidance route."
        case .noAvoidableAreas: "No fresh AQI 3–5 sample areas can be avoided. Areas containing the start or destination cannot be excluded from this request."
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

    func routes(from start: CLLocationCoordinate2D, to destination: MKMapItem, intensity: WalkingIntensity, key: String, avoiding areas: [WatchArea] = []) async throws -> [WalkRoute] {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ServiceError.missingKey }
        let geoapifyKey = KeyStore.read("geoapify")
        if !geoapifyKey.isEmpty {
            let result = try await GeoapifyRoutingClient().fetch(from: GeoCoordinate(start), to: GeoCoordinate(destination.placemark.coordinate), avoiding: areas, key: geoapifyKey)
            var scored: [WalkRoute] = []
            for option in result.routes {
                let geometry = option.geometry
                let points = geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                let name = areas.isEmpty ? (option.shortest ? "Shortest walk" : "Balanced walk") : "Avoidance alternative"
                scored.append(try await score(name: name, coordinates: points, metres: geometry.metres, seconds: geometry.seconds, intensity: intensity, key: key, source: "Geoapify · OpenStreetMap contributors", avoidedAreaCount: areas.count, excludedAreas: areas))
            }
            return Self.rankCleanAirFirst(scored)
        }
        let routingKey = KeyStore.read("openrouteservice")
        if !routingKey.isEmpty {
            let geometries = try await OpenRouteService().fetch(from: start, to: destination.placemark.coordinate, avoiding: areas, key: routingKey)
            var routes: [WalkRoute] = []
            for (index, geometry) in geometries.enumerated() {
                let points = geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                let routeName = areas.isEmpty ? "Walking option \(index + 1)" : "Clean-air detour"
                routes.append(try await score(name: routeName, coordinates: points, metres: geometry.metres, seconds: geometry.seconds, intensity: intensity, key: key, source: "openrouteservice · OpenStreetMap contributors", avoidedAreaCount: areas.count, steps: Self.syntheticSteps(for: points, name: routeName)))
            }
            return Self.rankCleanAirFirst(routes)
        }
        // Native Apple MapKit multi-waypoint clean-air detour when avoiding polluted areas without an ORS key.
        if !areas.isEmpty {
            return try await mapKitCleanAirDetour(from: start, to: destination, avoiding: areas, intensity: intensity, key: key)
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = destination
        request.transportType = .walking
        request.requestsAlternateRoutes = true
        let response: MKDirections.Response
        do { response = try await MKDirections(request: request).calculate() }
        catch is CancellationError { throw CancellationError() }
        catch {
            let failure = error as NSError
            if failure.domain == MKErrorDomain && failure.code == MKError.Code.directionsNotFound.rawValue { throw ServiceError.routingMissingKey }
            throw ServiceError.routingProvider
        }
        guard !response.routes.isEmpty else { throw ServiceError.noRoutes }
        var result: [WalkRoute] = []
        for mkRoute in response.routes.prefix(3) {
            try Task.checkCancellation()
            let points = mkRoute.polyline.points()
            let coordinates = (0..<mkRoute.polyline.pointCount).map { points[$0].coordinate }
            let routeSteps = mkRoute.steps.compactMap { step -> RouteStep? in
                guard !step.instructions.isEmpty else { return nil }
                let coord = step.polyline.pointCount > 0 ? step.polyline.points()[0].coordinate : (coordinates.first ?? start)
                return RouteStep(instructions: step.instructions, metres: step.distance, coordinate: GeoCoordinate(coord))
            }
            let scored = try await score(name: mkRoute.name.isEmpty ? "Walking path" : mkRoute.name, coordinates: coordinates, metres: mkRoute.distance, seconds: mkRoute.expectedTravelTime, intensity: intensity, key: key, source: "Apple Maps", steps: routeSteps)
            result.append(scored)
        }
        // If any returned route crosses AQI 3–5 areas and no clean-air route exists yet, automatically try a native MapKit clean-air detour.
        let highPollutionAreas = result.flatMap { route in
            route.airSamples.compactMap { sample -> WatchArea? in
                guard let reading = sample.reading, reading.aqi >= 3 else { return nil }
                return WatchArea(id: sample.id.uuidString, latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude, pm25: reading.pm25, aqi: reading.aqi, sampledAt: reading.date)
            }
        }
        let avoidable = WatchAreaPolicy.select(highPollutionAreas, now: Date()).filter {
            !$0.contains(latitude: start.latitude, longitude: start.longitude) &&
            !$0.contains(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude)
        }
        if !avoidable.isEmpty && !result.contains(where: \.isCleanAirPath) {
            if let detours = try? await mapKitCleanAirDetour(from: start, to: destination, avoiding: avoidable, intensity: intensity, key: key) {
                for detour in detours where !result.contains(where: { $0.coordinates.count == detour.coordinates.count }) {
                    result.append(detour)
                }
            }
        }
        return Self.rankCleanAirFirst(result)
    }

    /// Uses Apple MapKit multi-leg MKDirections via perpendicular offset waypoints around polluted WatchAreas.
    private func mapKitCleanAirDetour(from start: CLLocationCoordinate2D, to destination: MKMapItem, avoiding areas: [WatchArea], intensity: WalkingIntensity, key: String) async throws -> [WalkRoute] {
        guard let worst = areas.max(by: { $0.pm25 < $1.pm25 }) else { throw ServiceError.noAvoidableAreas }
        let end = destination.placemark.coordinate
        let dx = end.longitude - start.longitude
        let dy = end.latitude - start.latitude
        let len = max(0.0001, hypot(dx, dy))
        // Offset ~380 m perpendicular to the journey axis outside the 250 m polluted circle.
        let offsetDeg = 0.0036
        let perpLat = -dx / len * offsetDeg
        let perpLon = dy / len * offsetDeg
        let candidates = [
            CLLocationCoordinate2D(latitude: worst.latitude + perpLat, longitude: worst.longitude + perpLon),
            CLLocationCoordinate2D(latitude: worst.latitude - perpLat, longitude: worst.longitude - perpLon)
        ]
        var detours: [WalkRoute] = []
        for candidate in candidates {
            try Task.checkCancellation()
            let midItem = MKMapItem(placemark: MKPlacemark(coordinate: candidate))
            let leg1Req = MKDirections.Request()
            leg1Req.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
            leg1Req.destination = midItem
            leg1Req.transportType = .walking
            let leg2Req = MKDirections.Request()
            leg2Req.source = midItem
            leg2Req.destination = destination
            leg2Req.transportType = .walking
            guard let res1 = try? await MKDirections(request: leg1Req).calculate(),
                  let res2 = try? await MKDirections(request: leg2Req).calculate(),
                  let r1 = res1.routes.first, let r2 = res2.routes.first else { continue }
            let pts1 = (0..<r1.polyline.pointCount).map { r1.polyline.points()[$0].coordinate }
            let pts2 = (0..<r2.polyline.pointCount).map { r2.polyline.points()[$0].coordinate }
            let combined = pts1 + Array(pts2.dropFirst())
            let geoPairs = combined.map { [$0.longitude, $0.latitude] }
            guard !areas.contains(where: { $0.intersects(geoPairs) }) else { continue }
            let steps = (r1.steps + r2.steps).compactMap { step -> RouteStep? in
                guard !step.instructions.isEmpty else { return nil }
                let coord = step.polyline.pointCount > 0 ? step.polyline.points()[0].coordinate : candidate
                return RouteStep(instructions: step.instructions, metres: step.distance, coordinate: GeoCoordinate(coord))
            }
            let scored = try await score(name: "Clean-air detour", coordinates: combined, metres: r1.distance + r2.distance, seconds: r1.expectedTravelTime + r2.expectedTravelTime, intensity: intensity, key: key, source: "Apple Maps · Clean-air waypoint detour", avoidedAreaCount: areas.count, steps: steps)
            detours.append(scored)
        }
        guard !detours.isEmpty else { throw ServiceError.areaNotAvoided }
        return Self.rankCleanAirFirst(detours)
    }

    private static func rankCleanAirFirst(_ routes: [WalkRoute]) -> [WalkRoute] {
        routes.sorted { a, b in
            if a.isCleanAirPath != b.isCleanAirPath { return a.isCleanAirPath }
            if let da = a.estimate.observedDose, let db = b.estimate.observedDose, abs(da - db) > 0.05 {
                return da < db
            }
            return a.seconds < b.seconds
        }
    }

    private func score(name: String, coordinates: [CLLocationCoordinate2D], metres: Double, seconds: Double, intensity: WalkingIntensity, key: String, source: String, avoidedAreaCount: Int = 0, excludedAreas: [WatchArea] = [], steps: [RouteStep] = []) async throws -> WalkRoute {
        let samples = sampleCoordinates(coordinates, maxCount: 8)
        var segments: [ExposureSegment] = []
        var airSamples: [RouteAirSample] = []
        for sample in samples {
            try Task.checkCancellation()
            let reading: AirReading?
            do { reading = try await AirService().fetch(at: sample.coordinate, key: key) }
            catch is CancellationError { throw CancellationError() }
            catch let error as ServiceError {
                switch error {
                case .missingKey, .unauthorized, .quota: throw error
                default: reading = nil
                }
            }
            catch { reading = nil }
            airSamples.append(.init(coordinate: sample.coordinate, reading: reading, timeFraction: sample.weight))
            segments.append(ExposureSegment(minutes: seconds / 60 * sample.weight,
                                            pm25: reading?.isFresh == true ? reading?.pm25 : nil))
        }
        let finalSteps = steps.isEmpty ? Self.syntheticSteps(for: coordinates, name: name) : steps
        return WalkRoute(name: name, coordinates: coordinates, metres: metres, seconds: seconds,
                         estimate: ExposureCalculator.estimate(segments, ventilation: intensity.ventilation),
                         demo: false, airSamples: airSamples, source: source, avoidedAreaCount: avoidedAreaCount, excludedAreas: excludedAreas, steps: finalSteps)
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

    private static func syntheticSteps(for coordinates: [CLLocationCoordinate2D], name: String) -> [RouteStep] {
        guard coordinates.count >= 2 else { return [] }
        let mid = coordinates[coordinates.count / 2]
        return [
            RouteStep(instructions: "Start along \(name)", metres: 280, coordinate: GeoCoordinate(coordinates[0])),
            RouteStep(instructions: "Continue on the low-exposure corridor", metres: 360, coordinate: GeoCoordinate(mid)),
            RouteStep(instructions: "Arrive at destination", metres: 180, coordinate: GeoCoordinate(coordinates.last!))
        ]
    }

    static func demoRoutes(intensity: WalkingIntensity) -> [WalkRoute] {
        let parkPath: [CLLocationCoordinate2D] = [
            .init(latitude: 6.9178, longitude: 79.8637),
            .init(latitude: 6.9168, longitude: 79.8618),
            .init(latitude: 6.9148, longitude: 79.8615),
            .init(latitude: 6.9125, longitude: 79.8645)
        ]
        let gardenPath: [CLLocationCoordinate2D] = [
            .init(latitude: 6.9178, longitude: 79.8637),
            .init(latitude: 6.9165, longitude: 79.8626),
            .init(latitude: 6.9144, longitude: 79.8628),
            .init(latitude: 6.9125, longitude: 79.8645)
        ]
        let roadPath: [CLLocationCoordinate2D] = [
            .init(latitude: 6.9178, longitude: 79.8637),
            .init(latitude: 6.9170, longitude: 79.8655),
            .init(latitude: 6.9144, longitude: 79.8659),
            .init(latitude: 6.9125, longitude: 79.8645)
        ]
        let configs: [(name: String, coords: [CLLocationCoordinate2D], metres: Double, seconds: Double, samples: [(Double, Int)], avoided: Int)] = [
            ("Clean-Air Canopy Corridor", parkPath, 960, 790, [(9.5, 1), (11.0, 1)], 2),
            ("Park-side Walk", gardenPath, 920, 780, [(12.0, 2), (16.0, 2)], 1),
            ("Town Hall Main Road", roadPath, 820, 660, [(21.0, 3), (32.0, 4)], 0)
        ]
        return configs.map { cfg in
            let airSamples = cfg.samples.enumerated().map { idx, val in
                RouteAirSample(coordinate: cfg.coords[min(idx + 1, cfg.coords.count - 1)],
                               reading: AirReading(pm25: val.0, aqi: val.1, date: Date(), demo: true),
                               timeFraction: 1.0 / Double(cfg.samples.count))
            }
            let meanPM = cfg.samples.map(\.0).reduce(0, +) / Double(cfg.samples.count)
            return WalkRoute(
                name: cfg.name,
                coordinates: cfg.coords,
                metres: cfg.metres,
                seconds: cfg.seconds,
                estimate: ExposureCalculator.estimate([.init(minutes: cfg.seconds / 60, pm25: meanPM)], ventilation: intensity.ventilation),
                demo: true,
                airSamples: airSamples,
                source: "Illustrative demo",
                avoidedAreaCount: cfg.avoided,
                steps: syntheticSteps(for: cfg.coords, name: cfg.name)
            )
        }
    }
}
