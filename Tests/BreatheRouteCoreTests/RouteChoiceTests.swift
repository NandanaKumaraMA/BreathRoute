import Testing
@testable import BreatheRouteCore

@Test func routeChoiceDoesNotRecommendUnknownOrEquivalentExposure() {
    #expect(RouteChoicePolicy.recommended([.init(id: "a", seconds: 300, dose: 5, complete: true), .init(id: "b", seconds: 400, dose: nil, complete: false)], extraMinutes: 10) == nil)
    #expect(RouteChoicePolicy.recommended([.init(id: "a", seconds: 300, dose: 5, complete: true), .init(id: "b", seconds: 400, dose: 5.05, complete: true)], extraMinutes: 10) == nil)
}
@Test func routeChoiceEnforcesTimeBudgetAndUsesDoseNotConcentration() {
    let choices: [RouteChoice] = [.init(id: "short", seconds: 300, dose: 8, complete: true), .init(id: "within", seconds: 500, dose: 5, complete: true), .init(id: "tooLong", seconds: 1800, dose: 2, complete: true)]
    #expect(RouteChoicePolicy.recommended(choices, extraMinutes: 5) == "within")
    #expect(RouteChoicePolicy.recommended(choices, extraMinutes: 0) == nil)
    #expect(RouteChoicePolicy.recommended(choices, extraMinutes: -1) == nil)
}
