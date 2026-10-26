import Foundation
import Testing
@testable import BreatheRouteCore

private let forecastStart = Date(timeIntervalSince1970: 1_700_000_000)
private let forecastCoordinate = GeoCoordinate(latitude: 6.9147, longitude: 79.864)
private func series(_ values: [(Double, Double?)], age: Double = 0) -> AirForecastSeries {
    AirForecastSeries(coordinate: forecastCoordinate, fetchedAt: forecastStart.addingTimeInterval(-age),
                      hours: values.map { .init(date: forecastStart.addingTimeInterval($0.0), pm25: $0.1, aqi: nil) })
}
private func evaluate(_ samples: [ForecastSample], offset: Double = 0, seconds: Double = 1800, id: Int = 0) -> DepartureEstimate {
    DepartureForecastCalculator.evaluate(id: id, departure: forecastStart.addingTimeInterval(offset), seconds: seconds,
                                         ventilation: 0.015, samples: samples, now: forecastStart)
}

@Test func hourlyForecastInterpolationIntegratesOnlyTravelInterval() {
    let result = evaluate([.init(timeFraction: 1, series: series([(0, 10), (3600, 30)]))], offset: 900)
    #expect(result.estimate.isComplete)
    #expect(abs(result.estimate.observedDose! - 9) < 0.000001)
    #expect(abs(result.meanPM25! - 20) < 0.000001)
    #expect(result.arrival == forecastStart.addingTimeInterval(2700))
}
@Test func eachRoutePointUsesItsAnticipatedArrivalTime() {
    let result = evaluate([
        .init(timeFraction: 0.5, series: series([(0, 10), (3600, 10), (7200, 10)])),
        .init(timeFraction: 0.5, series: series([(0, 100), (3600, 30), (7200, 30)]))
    ], seconds: 7200)
    #expect(result.estimate.isComplete)
    #expect(abs(result.estimate.observedDose! - 36) < 0.000001)
    #expect(abs(result.meanPM25! - 20) < 0.000001)
}
@Test func forecastGapsAndMissingPointsReduceCoverage() {
    let gap = evaluate([.init(timeFraction: 1, series: series([(0, 10), (7200, 40)]))], seconds: 7200)
    #expect(gap.estimate.observedDose == nil && gap.estimate.coverage == 0)
    let partial = evaluate([.init(timeFraction: 1, series: series([(0, 10), (3600, 10), (7200, nil), (10800, 30)]))], seconds: 10800)
    #expect(abs(partial.estimate.coverage - 1.0 / 3) < 0.000001)
    #expect(abs(partial.estimate.observedDose! - 9) < 0.000001)
    #expect(!partial.estimate.isComplete)
    let missing = evaluate([.init(timeFraction: 0.5, series: series([(0, 10), (3600, 10)])), .init(timeFraction: 0.5, series: nil)])
    #expect(missing.estimate.coverage == 0.5)
}
@Test func forecastNeverExtrapolatesBeforeOrAfterReturnedHorizon() {
    let result = evaluate([.init(timeFraction: 1, series: series([(0, 10), (3600, 10)]))], offset: -1800, seconds: 7200)
    #expect(result.estimate.coverage == 0.5)
    #expect(result.estimate.observedDose == 9)
    let after = evaluate([.init(timeFraction: 1, series: series([(0, 10), (3600, 10)]))], offset: 3600)
    #expect(after.estimate.observedDose == nil && after.estimate.coverage == 0)
}
@Test func staleForecastsAndInvalidWeightsStayUnknown() {
    let stale = evaluate([.init(timeFraction: 1, series: series([(0, 10), (3600, 10)], age: 1800))])
    #expect(stale.estimate.observedDose == nil)
    let wrongWeights = evaluate([.init(timeFraction: 0.4, series: series([(0, 10), (3600, 10)]))])
    #expect(wrongWeights.estimate.observedDose == nil)
    let zero = evaluate([.init(timeFraction: 1, series: series([(0, 0), (3600, 0)]))])
    #expect(zero.estimate.observedDose == 0 && zero.estimate.isComplete)
    let extreme = evaluate([.init(timeFraction: 1, series: series([(0, Double.greatestFiniteMagnitude / 4), (3600, Double.greatestFiniteMagnitude / 4)]))])
    #expect(extreme.estimate.observedDose == nil && extreme.estimate.coverage == 0)
}
@Test func forecastDecoderPreservesMissingValuesAndRejectsAmbiguousHours() throws {
    let data = Data(#"{"list":[{"dt":1700000000,"main":{"aqi":1},"components":{"pm2_5":10}},{"dt":1700003600,"main":{"aqi":9},"components":{"pm2_5":-3}},{"dt":1700000000,"main":{"aqi":2},"components":{"pm2_5":20}}]}"#.utf8)
    let hours = try AirForecastDecoder.decode(data)
    #expect(hours.count == 3)
    #expect(hours[1].pm25 == nil && hours[1].aqi == nil)
    let normalized = AirForecastSeries(coordinate: forecastCoordinate, fetchedAt: forecastStart, hours: hours)
    #expect(normalized.hours.count == 2 && normalized.hours.first?.pm25 == nil)
    #expect(throws: ForecastDecodingError.self) { try AirForecastDecoder.decode(Data(#"{"list":[]}"#.utf8)) }
}
@Test func departureAdviceExcludesPartialDataAndTreatsSmallDifferencesAsSimilar() {
    func option(_ id: Int, dose: Double?, coverage: Double = 1) -> DepartureEstimate {
        .init(id: id, departure: forecastStart.addingTimeInterval(Double(id) * 3600), arrival: forecastStart,
              estimate: ExposureEstimate(observedDose: dose, coverage: coverage), meanPM25: nil)
    }
    #expect(DepartureForecastCalculator.advice([option(0, dose: 4), option(1, dose: 1, coverage: 0.5)]) == .insufficient)
    #expect(DepartureForecastCalculator.advice([option(0, dose: 4), option(1, dose: 4.05)]) == .similar)
    #expect(DepartureForecastCalculator.advice([option(0, dose: 4), option(1, dose: 3), option(2, dose: 1, coverage: 0.5)]) == .lowest(1))
}
