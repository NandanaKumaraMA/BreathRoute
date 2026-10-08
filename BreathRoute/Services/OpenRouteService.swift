import Foundation
import CoreLocation

struct OpenRouteService {
    func fetch(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D, avoiding areas: [WatchArea], key: String) async throws -> [ProviderRoute] {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ServiceError.routingMissingKey }
        var body: [String: Any] = ["coordinates": [[start.longitude, start.latitude], [end.longitude, end.latitude]], "instructions": false, "units": "m", "optimized": false]
        if areas.isEmpty {
            body["alternative_routes"] = ["target_count": 3, "weight_factor": 1.4, "share_factor": 0.6]
        } else {
            body["options"] = ["avoid_polygons": ["type": "MultiPolygon", "coordinates": areas.map { [$0.polygon()] }]]
        }
        let data: Data
        do { data = try await send(body, key: key) }
        catch ServiceError.routingOptionsRejected where areas.isEmpty {
            // Hosted accounts/profiles may reject the alternative algorithm. A baseline remains useful.
            body.removeValue(forKey: "alternative_routes")
            data = try await send(body, key: key)
        }
        let routes: [ProviderRoute]
        do { routes = try RoutingPayload.decode(data) }
        catch { throw ServiceError.noRoutes }
        // Avoidance must be verified against the geometry returned, including intervening segments.
        let verified = routes.filter { route in !areas.contains { $0.intersects(route.coordinates) } }
        guard !verified.isEmpty else { throw ServiceError.areaNotAvoided }
        return verified
    }
    private func send(_ body: [String: Any], key: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openrouteservice.org/v2/directions/foot-walking/geojson")!)
        request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue(key.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch is CancellationError { throw CancellationError() }
        catch { throw ServiceError.routingProvider }
        guard let http = response as? HTTPURLResponse else { throw ServiceError.routingProvider }
        switch http.statusCode {
        case 200: return data
        case 401, 403: throw ServiceError.routingDenied
        case 429: throw ServiceError.routingQuota
        case 400: throw ServiceError.routingOptionsRejected
        case 404: throw ServiceError.noRoutes
        default: throw ServiceError.routingProvider
        }
    }
}
