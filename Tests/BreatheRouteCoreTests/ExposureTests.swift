import Testing
@testable import BreatheRouteCore

@Test func knownUnits() {
    let result = ExposureCalculator.estimate([.init(minutes: 10, pm25: 20)], ventilation: 0.02)
    #expect(result.observedDose == 4)
    #expect(result.isComplete)
}
@Test func missingIsNotZero() {
    let result = ExposureCalculator.estimate([.init(minutes: 10, pm25: nil)], ventilation: 0.02)
    #expect(result.observedDose == nil)
    #expect(result.coverage == 0)
}
@Test func timeWeightedCoverage() {
    let result = ExposureCalculator.estimate([.init(minutes: 2, pm25: 20), .init(minutes: 8, pm25: nil)], ventilation: 0.02)
    #expect(result.coverage == 0.2)
    #expect(result.observedDose == 0.8)
    #expect(!result.isComplete)
}
@Test func genuineZeroIsAReading() {
    let result = ExposureCalculator.estimate([.init(minutes: 10, pm25: 0)], ventilation: 0.02)
    #expect(result.observedDose == 0)
    #expect(result.isComplete)
}
@Test(arguments: [-1.0, Double.nan, Double.infinity])
func invalidConcentrationIsMissing(value: Double) {
    let result = ExposureCalculator.estimate([.init(minutes: 10, pm25: value)], ventilation: 0.02)
    #expect(result.observedDose == nil)
    #expect(result.coverage == 0)
}
@Test(arguments: [0.0, -1.0, Double.nan, Double.infinity])
func invalidVentilation(value: Double) {
    #expect(ExposureCalculator.estimate([.init(minutes: 10, pm25: 20)], ventilation: value).observedDose == nil)
}
@Test func emptyAndInvalidDurations() {
    #expect(ExposureCalculator.estimate([], ventilation: 0.02).observedDose == nil)
    let result = ExposureCalculator.estimate([.init(minutes: -10, pm25: 20), .init(minutes: .infinity, pm25: 20), .init(minutes: 0, pm25: 20)], ventilation: 0.02)
    #expect(result.observedDose == nil)
    #expect(result.coverage == 0)
}
@Test func segmentAdditivity() {
    let result = ExposureCalculator.estimate([.init(minutes: 5, pm25: 10), .init(minutes: 5, pm25: 30)], ventilation: 0.02)
    #expect(result.observedDose == 4)
}
