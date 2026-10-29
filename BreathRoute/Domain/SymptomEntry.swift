import Foundation

struct SymptomEntry: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var date = Date()
    var kind = "Cough"
    var severity = 1
    var notes = ""
    var tripID: UUID?
    // Optional for compatibility with earlier local journals.
    var conflictCopyOf: UUID? = nil
}
