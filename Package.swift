// swift-tools-version: 6.0
import PackageDescription

// Production domain and storage sources are tested independently of simulator services.
let package = Package(
    name: "BreatheRouteCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BreatheRouteCore", targets: ["BreatheRouteCore"])],
    targets: [
        .target(name: "BreatheRouteCore", path: "BreathRoute/Domain", exclude: ["Models.swift"], sources: ["Exposure.swift", "NearbyRanking.swift", "WatchAreas.swift", "RoutingPayload.swift", "GeoapifyRouting.swift", "RouteChoicePolicy.swift", "WalkingActivity.swift", "TripEntry.swift", "WalkSession.swift", "AirForecast.swift", "AccountPolicy.swift", "SymptomEntry.swift", "JournalSync.swift", "CloudDemoFixtures.swift", "WalkingPreview.swift", "RouteDeviation.swift", "PushNotification.swift", "LiveNotification.swift"]),
        .target(name: "BreatheRoutePersistence", path: "BreathRoute/Services", exclude: ["FreeNotificationQA.swift", "FreeNotificationService.swift", "RemotePushQA.swift", "RemotePushService.swift", "IntegratedWalkQA.swift", "WalkingPreviewQA.swift", "LiveJournalQA.swift", "CloudJournalService.swift", "StructuredCloudStore.swift", "CloudDemoSeeder.swift", "CloudJournalQA.swift", "StructuredCloudQA.swift", "AppModel.swift", "AccountService.swift", "FirebaseBootstrap.swift", "ForecastService.swift", "GeofenceService.swift", "HealthService.swift", "MotionService.swift", "NearbyService.swift", "OpenRouteService.swift", "PlaceSearchService.swift", "PlatformServices.swift", "RouteService.swift"], sources: ["LocalStore.swift"]),
        .testTarget(name: "BreatheRouteCoreTests", dependencies: ["BreatheRouteCore"], path: "Tests/BreatheRouteCoreTests"),
        .testTarget(name: "BreatheRoutePersistenceTests", dependencies: ["BreatheRouteCore", "BreatheRoutePersistence"], path: "Tests/BreatheRoutePersistenceTests")
    ]
)
