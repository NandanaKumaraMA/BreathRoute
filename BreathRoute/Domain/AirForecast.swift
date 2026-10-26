import Foundation

struct ForecastHour: Sendable {
    let date: Date
    let pm25: Double?
    let aqi: Int?
}

struct AirForecastSeries: Sendable {
    let coordinate: GeoCoordinate
    let fetchedAt: Date
    let hours: [ForecastHour]
    init(coordinate: GeoCoordinate, fetchedAt: Date, hours: [ForecastHour]) {
        self.coordinate = coordinate; self.fetchedAt = fetchedAt
        // Conflicting duplicate timestamps remain unknown instead of picking a favourable value.
        self.hours = Dictionary(grouping: hours.filter { $0.date.timeIntervalSince1970.isFinite && $0.date.timeIntervalSince1970 > 0 }, by: \.date)
            .map { date, values in values.count == 1 ? values[0] : ForecastHour(date: date, pm25: nil, aqi: nil) }
            .sorted { $0.date < $1.date }
    }
    func isFresh(at now: Date) -> Bool {
        coordinate.isValid && now.timeIntervalSince(fetchedAt) >= -300 && now.timeIntervalSince(fetchedAt) < 1800
    }
}

enum ForecastDecodingError: Error { case noHours }
enum AirForecastDecoder {
    static func decode(_ data: Data) throws -> [ForecastHour] {
        struct Response: Decodable {
            let list: [Item]
            struct Item: Decodable {
                let dt: Double
                let main: Index?
                let components: Components?
                struct Index: Decodable { let aqi: Int? }
                struct Components: Decodable { let pm2_5: Double? }
            }
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let hours = response.list.filter { $0.dt.isFinite && $0.dt > 0 }.map { item in
            ForecastHour(date: Date(timeIntervalSince1970: item.dt),
                         pm25: item.components?.pm2_5.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
                         aqi: item.main?.aqi.flatMap { (1...5).contains($0) ? $0 : nil })
        }
        guard hours.contains(where: { $0.pm25 != nil }) else { throw ForecastDecodingError.noHours }
        return hours
    }
}

struct ForecastSample: Sendable {
    let timeFraction: Double
    let series: AirForecastSeries?
}

struct DepartureEstimate: Identifiable, Sendable {
    let id: Int
    let departure: Date
    let arrival: Date
    let estimate: ExposureEstimate
    let meanPM25: Double?
}

enum DepartureAdvice: Equatable {
    case insufficient, similar, lowest(Int)
}

enum DepartureForecastCalculator {
    /// Uniform speed assigns each retained spatial interval its existing share of travel time.
    /// Between adjacent hourly points, integrate a linear model; never bridge a missing hour or extrapolate.
    static func evaluate(id: Int, departure: Date, seconds: Double, ventilation: Double,
                         samples: [ForecastSample], now: Date) -> DepartureEstimate {
        let empty = ExposureEstimate(observedDose: nil, coverage: 0)
        guard seconds.isFinite, seconds > 0, seconds <= 86400, ventilation.isFinite, ventilation > 0,
              departure.timeIntervalSince1970.isFinite, !samples.isEmpty, samples.count <= 8,
              samples.allSatisfy({ $0.timeFraction.isFinite && $0.timeFraction > 0 && $0.timeFraction <= 1 }),
              abs(samples.reduce(0) { $0 + $1.timeFraction } - 1) < 0.000001 else {
            return DepartureEstimate(id: id, departure: departure, arrival: departure, estimate: empty, meanPM25: nil)
        }
        var segments: [ExposureSegment] = [], offset = 0.0, concentrationSeconds = 0.0, covered = 0.0, finiteDose = 0.0
        for sample in samples {
            let duration = seconds * sample.timeFraction
            let start = departure.addingTimeInterval(offset), end = start.addingTimeInterval(duration)
            offset += duration
            var coveredHere = 0.0
            if let series = sample.series, series.isFresh(at: now) {
                for (a, b) in zip(series.hours, series.hours.dropFirst()) {
                    let interval = b.date.timeIntervalSince(a.date)
                    guard interval > 0, interval <= 3600.001, let first = a.pm25, let last = b.pm25,
                          first.isFinite, last.isFinite, first >= 0, last >= 0 else { continue }
                    let left = max(start, a.date), right = min(end, b.date)
                    guard right > left else { continue }
                    let leftValue = first + (last - first) * left.timeIntervalSince(a.date) / interval
                    let rightValue = first + (last - first) * right.timeIntervalSince(a.date) / interval
                    let length = right.timeIntervalSince(left), mean = (leftValue + rightValue) / 2
                    let integral = mean * length, dose = mean * ventilation * (length / 60)
                    guard mean.isFinite, mean >= 0, integral.isFinite, (concentrationSeconds + integral).isFinite,
                          dose.isFinite, (finiteDose + dose).isFinite else { continue }
                    segments.append(.init(minutes: length / 60, pm25: mean))
                    coveredHere += length; concentrationSeconds += integral; finiteDose += dose
                }
            }
            covered += coveredHere
            if duration - coveredHere > 0.000001 { segments.append(.init(minutes: (duration - coveredHere) / 60, pm25: nil)) }
        }
        let estimate = ExposureCalculator.estimate(segments, ventilation: ventilation)
        return DepartureEstimate(id: id, departure: departure, arrival: departure.addingTimeInterval(seconds), estimate: estimate,
                                 meanPM25: covered > 0 ? concentrationSeconds / covered : nil)
    }
    static func advice(_ options: [DepartureEstimate]) -> DepartureAdvice {
        let comparable = options.filter { $0.estimate.isComplete && $0.estimate.observedDose.map { $0.isFinite && $0 >= 0 } == true }
            .sorted { $0.departure < $1.departure }
        guard comparable.count >= 2,
              let best = comparable.min(by: { $0.estimate.observedDose! < $1.estimate.observedDose! }),
              let largest = comparable.map({ $0.estimate.observedDose! }).max() else { return .insufficient }
        guard largest - best.estimate.observedDose! > max(0.1, largest * 0.01) else { return .similar }
        return .lowest(best.id)
    }
}
