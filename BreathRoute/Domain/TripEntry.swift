import Foundation

struct TripEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var destination: String
    var metres: Double
    var seconds: Double
    var dose: Double?
    var coverage: Double
    var demo: Bool
    var complete: Bool
    // Optional so existing Core Data JSON payloads remain readable without rewriting them.
    var activity: WalkActivitySummary? = nil
    var recordedPath: [RecordedPathPoint]? = nil
    var plannedPath: [GeoCoordinate]? = nil
    var routeSource: String? = nil
    var ventilation: Double? = nil
    var recovered: Bool? = nil
    var lastRecordedAt: Date? = nil
    var cloudSummary: Bool? = nil
    var conflictCopyOf: UUID? = nil
}
