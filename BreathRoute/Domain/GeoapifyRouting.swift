import Foundation

enum WalkingRouteProvider: String, CaseIterable, Identifiable {
    case geoapify, openrouteservice
    var id: String { rawValue }
    var name: String { self == .geoapify ? "Geoapify" : "openrouteservice" }
    var keyName: String { rawValue }
}

enum GeoapifyRoutingError: LocalizedError {
    case missingKey, denied, quota, network, options, noRoutes, areaNotAvoided
    var errorDescription: String? {
        switch self {
        case .missingKey: "Walking routes are not configured for this build. Add the Geoapify key to Config.local.xcconfig and rebuild."
        case .denied: "Geoapify rejected the key or account access. Check your Geoapify connection and project permissions."
        case .quota: "The Geoapify request allowance was reached. Check your account usage before trying again."
        case .network: "Geoapify could not complete the walking-route request. Check your connection and try again."
        case .options: "Geoapify could not route with these locations or avoidance areas. Try another destination or fewer areas."
        case .noRoutes: "Geoapify returned no usable walking path for these locations."
        case .areaNotAvoided: "The returned path crosses an excluded pollution sample area. It has not been accepted as an avoidance route."
        }
    }
}

enum GeoapifyRoutingPayload {
    static func decode(_ data: Data) throws -> [ProviderRoute] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let routes = response.features.compactMap { feature -> ProviderRoute? in
            let geometry = feature.geometry, properties = feature.properties
            guard geometry.type == "MultiLineString", !geometry.coordinates.isEmpty,
                  properties.distance.isFinite, properties.distance > 0,
                  properties.time.isFinite, properties.time > 0 else { return nil }
            var points: [[Double]] = []
            for leg in geometry.coordinates {
                guard leg.count >= 2, leg.allSatisfy({ point in
                    point.count >= 2 && GeoCoordinate(latitude: point[1], longitude: point[0]).isValid
                }) else { return nil }
                let normalized = leg.map { Array($0.prefix(2)) }
                // Never invent a connecting line across disconnected route legs.
                if let last = points.last, last != normalized.first { return nil }
                points.append(contentsOf: points.isEmpty ? normalized : Array(normalized.dropFirst()))
            }
            return ProviderRoute(coordinates: points, metres: properties.distance, seconds: properties.time)
        }
        guard !routes.isEmpty else { throw GeoapifyRoutingError.noRoutes }
        return Array(routes.prefix(3))
    }
    private struct Response: Decodable {
        let features: [Feature]
        struct Feature: Decodable {
            let geometry: Geometry
            let properties: Properties
            struct Geometry: Decodable { let type: String; let coordinates: [[[Double]]] }
            struct Properties: Decodable { let distance: Double; let time: Double }
        }
    }
}

struct GeoapifyWalkingRoute: Sendable {
    let geometry: ProviderRoute
    let shortest: Bool
}
struct GeoapifyRouteComparison: Sendable {
    let routes: [GeoapifyWalkingRoute]
    let notice: String?
}

/// Provider protocol, parsing and geometry checks can be tested without real credentials.
@MainActor final class GeoapifyRoutingClient {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)
    private let transport: Transport
    private let clock: () -> Date
    init(clock: @escaping () -> Date = Date.init,
         transport: @escaping Transport = { request in
             let configuration = URLSessionConfiguration.ephemeral
             configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
             let session = URLSession(configuration: configuration, delegate: RoutingRedirectPolicy(), delegateQueue: nil)
             defer { session.finishTasksAndInvalidate() }
             let (data, response) = try await session.data(for: request)
             guard let response = response as? HTTPURLResponse else { throw GeoapifyRoutingError.network }
             return (data, response.statusCode)
         }) {
        self.clock = clock; self.transport = transport
    }
    func fetch(from start: GeoCoordinate, to end: GeoCoordinate, avoiding areas: [WatchArea], key: String) async throws -> GeoapifyRouteComparison {
        let baseline = try await fetchOne(from: start, to: end, avoiding: areas, shortest: false, key: key)
        var routes = baseline.map { GeoapifyWalkingRoute(geometry: $0, shortest: false) }
        var notice: String?
        // The API documents balanced/short preferences. Request both and keep only distinct paths.
        if areas.isEmpty {
            do {
                let shortest = try await fetchOne(from: start, to: end, avoiding: [], shortest: true, key: key)
                for route in shortest where !routes.contains(where: { samePath($0.geometry, route) }) {
                    routes.append(GeoapifyWalkingRoute(geometry: route, shortest: true))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { notice = error.localizedDescription + " The available balanced walking option is shown." }
        }
        try Task.checkCancellation()
        return GeoapifyRouteComparison(routes: Array(routes.prefix(3)), notice: notice)
    }
    static func request(from start: GeoCoordinate, to end: GeoCoordinate, avoiding areas: [WatchArea], shortest: Bool, key: String, now: Date) throws -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GeoapifyRoutingError.missingKey }
        guard start.isValid, end.isValid, areas.count <= 8,
              areas.allSatisfy({ $0.isUsable(at: now) && !$0.contains(latitude: start.latitude, longitude: start.longitude) && !$0.contains(latitude: end.latitude, longitude: end.longitude) }) else { throw GeoapifyRoutingError.options }
        func decimal(_ number: Double) -> String { String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), number) }
        var items = [URLQueryItem(name: "waypoints", value: "\(decimal(start.latitude)),\(decimal(start.longitude))|\(decimal(end.latitude)),\(decimal(end.longitude))"),
                     URLQueryItem(name: "mode", value: "walk"), URLQueryItem(name: "type", value: shortest ? "short" : "balanced"),
                     URLQueryItem(name: "units", value: "metric"), URLQueryItem(name: "format", value: "geojson")]
        if !areas.isEmpty {
            var rules: [String] = []
            for area in areas {
                // Twelve circumscribed sides keep eight areas within a normal request URL size.
                let ring = area.polygon(vertexCount: 12)
                guard zip(ring, ring.dropFirst()).allSatisfy({ abs($0[0] - $1[0]) <= 180 }) else { throw GeoapifyRoutingError.options }
                rules.append("polygon:" + ring.map { "\(decimal($0[1])),\(decimal($0[0]))" }.joined(separator: ";"))
            }
            items.append(URLQueryItem(name: "avoid", value: rules.joined(separator: "|")))
        }
        var components = URLComponents(string: "https://api.geoapify.com/v1/routing")!
        components.queryItems = items
        guard let url = components.url, url.absoluteString.utf8.count < 7500 else { throw GeoapifyRoutingError.options }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25; request.cachePolicy = .reloadIgnoringLocalCacheData
        // Official API supports this header; credentials never need to appear in request URLs.
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        return request
    }
    private func fetchOne(from start: GeoCoordinate, to end: GeoCoordinate, avoiding areas: [WatchArea], shortest: Bool, key: String) async throws -> [ProviderRoute] {
        try Task.checkCancellation()
        let request = try Self.request(from: start, to: end, avoiding: areas, shortest: shortest, key: key, now: clock())
        let data: Data, status: Int
        do { (data, status) = try await transport(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw GeoapifyRoutingError.network }
        try Task.checkCancellation()
        switch status {
        case 200: break
        case 401, 403: throw GeoapifyRoutingError.denied
        case 429: throw GeoapifyRoutingError.quota
        case 400, 422: throw GeoapifyRoutingError.options
        case 404: throw GeoapifyRoutingError.noRoutes
        default: throw GeoapifyRoutingError.network
        }
        let decoded: [ProviderRoute]
        do { decoded = try GeoapifyRoutingPayload.decode(data) }
        catch { throw GeoapifyRoutingError.noRoutes }
        let verified = decoded.filter { route in !areas.contains { $0.intersects(route.coordinates) } }
        guard !verified.isEmpty else { throw GeoapifyRoutingError.areaNotAvoided }
        return verified
    }
    private func samePath(_ a: ProviderRoute, _ b: ProviderRoute) -> Bool {
        a.coordinates.count == b.coordinates.count && zip(a.coordinates, b.coordinates).allSatisfy { a, b in
            abs(a[0] - b[0]) < 0.00001 && abs(a[1] - b[1]) < 0.00001
        }
    }
}

private final class RoutingRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
