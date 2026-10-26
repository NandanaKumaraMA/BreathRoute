import Foundation

struct ForecastBatch {
    let series: [AirForecastSeries?]
    let notice: String?
}

@MainActor
final class ForecastService {
    private var cache: [String: AirForecastSeries] = [:]
    private var credential = ""
    private var accountGeneration = 0
    func clearForAccountChange() { accountGeneration += 1; cache.removeAll(); credential = "" }
    func load(_ points: [GeoCoordinate], key: String, force: Bool = false) async throws -> ForecastBatch {
        let generation = accountGeneration
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ServiceError.missingKey }
        guard !points.isEmpty, points.count <= 8, points.allSatisfy(\.isValid) else { throw ServiceError.noReading }
        if credential != key { cache.removeAll(); credential = key }
        defer {
            if cache.count > 64 {
                cache = Dictionary(uniqueKeysWithValues: cache.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(64).map { ($0.key, $0.value) })
            }
        }
        var result: [AirForecastSeries?] = [], failures = 0
        var requestResults: [String: AirForecastSeries] = [:]
        var firstError: Error?
        for point in points {
            try Task.checkCancellation()
            guard accountGeneration == generation else { throw CancellationError() }
            let identity = "\(point.latitude),\(point.longitude)"
            if let existing = requestResults[identity] ?? (force ? nil : cache[identity]),
               Date().timeIntervalSince(existing.fetchedAt) < 600, existing.isFresh(at: Date()) {
                result.append(existing); requestResults[identity] = existing; continue
            }
            do {
                let series = try await fetch(point, key: key)
                try Task.checkCancellation()
                guard accountGeneration == generation else { throw CancellationError() }
                cache[identity] = series; requestResults[identity] = series; result.append(series)
            } catch is CancellationError { throw CancellationError() }
            catch let error as ServiceError {
                switch error {
                case .unauthorized, .quota, .missingKey: throw error
                default: failures += 1; firstError = firstError ?? error; result.append(nil)
                }
            } catch { failures += 1; firstError = firstError ?? ServiceError.noReading; result.append(nil) }
        }
        guard result.contains(where: { $0 != nil }) else { throw firstError ?? ServiceError.noReading }
        return ForecastBatch(series: result, notice: failures > 0 ? "\(failures) of \(points.count) forecast points could not be loaded. Their intervals remain unknown." : nil)
    }
    private func fetch(_ point: GeoCoordinate, key: String) async throws -> AirForecastSeries {
        var url = URLComponents(string: "https://api.openweathermap.org/data/2.5/air_pollution/forecast")!
        url.queryItems = [.init(name: "lat", value: String(point.latitude)), .init(name: "lon", value: String(point.longitude)), .init(name: "appid", value: key)]
        var request = URLRequest(url: url.url!); request.timeoutInterval = 20
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch is CancellationError { throw CancellationError() }
        catch { throw ServiceError.network }
        guard let http = response as? HTTPURLResponse else { throw ServiceError.provider }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw ServiceError.unauthorized
        case 429: throw ServiceError.quota
        default: throw ServiceError.provider
        }
        guard let hours = try? AirForecastDecoder.decode(data) else { throw ServiceError.noReading }
        return AirForecastSeries(coordinate: point, fetchedAt: Date(), hours: hours)
    }
}
