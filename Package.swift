// swift-tools-version: 6.0
import PackageDescription

// The same production calculation source is tested independently of simulator services.
let package = Package(
    name: "BreatheRouteCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BreatheRouteCore", targets: ["BreatheRouteCore"])],
    targets: [
        .target(name: "BreatheRouteCore", path: "BreathRoute/Domain", exclude: ["Models.swift"], sources: ["Exposure.swift", "NearbyRanking.swift", "WatchAreas.swift", "RoutingPayload.swift", "RouteChoicePolicy.swift"]),
        .testTarget(name: "BreatheRouteCoreTests", dependencies: ["BreatheRouteCore"], path: "Tests/BreatheRouteCoreTests")
    ]
)
