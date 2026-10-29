import Foundation

/// Fixed fictional records for demonstrations, never provider or sensor observations.
enum CloudDemoFixtures {
    static let datasetID = "coursework2026"
    static let label = "Coursework demonstration — synthetic"
    static let walkCount = 30
    static let noteCount = 45
    static let symptomKinds = ["Cough", "Wheezing", "Breathlessness", "Throat irritation", "Eye irritation", "Other"]

    static func snapshot() throws -> JournalCloudSnapshot {
        // 26 September–25 October 2026, starting at 06:30 in Sri Lanka.
        // Fixed dates and UUIDs make repeat seeding safe and reproducible.
        let anchor = Date(timeIntervalSince1970: 1_790_384_400)
        let destinations = ["Park-side walk", "Museum walk", "Garden walk", "Library walk", "Riverside walk", "Market walk"]
        let coverageValues = [1.0, 0.6, 0, 0.85, 1]
        let ventilationValues = [0.015, 0.025, 0.035]
        var trips: [CloudTripSummary] = [], notes: [SymptomEntry] = []
        for index in 1...walkCount {
            let tripID = try identifier(prefix: "D3B00000", index: index)
            let coverage = coverageValues[(index - 1) % coverageValues.count]
            let ventilation = ventilationValues[(index - 1) % ventilationValues.count]
            let metres = Double(700 + (index * 173) % 2900)
            let seconds = (metres / [1.0, 1.35, 1.65][(index - 1) % 3]).rounded()
            // Fictional concentration × breathing volume × covered minutes, in µg.
            let dose = coverage == 0 ? nil : Double(6 + (index * 7) % 42) * ventilation * seconds / 60 * coverage
            let trip = TripEntry(id: tripID, date: anchor.addingTimeInterval(Double(index - 1) * 86400 + Double(index % 3) * 1800),
                                 destination: "[SYNTHETIC DEMO] \(destinations[(index - 1) % destinations.count])",
                                 metres: metres, seconds: seconds, dose: dose, coverage: coverage, demo: true, complete: index % 11 != 0,
                                 routeSource: "Synthetic coursework fixture; no provider or sensor measurement", ventilation: ventilation)
            trips.append(CloudTripSummary(trip))
            notes.append(SymptomEntry(id: try identifier(prefix: "D3B10000", index: index),
                date: trip.date.addingTimeInterval(seconds + 600), kind: symptomKinds[(index - 1) % symptomKinds.count],
                severity: 1 + (index * 3) % 5,
                notes: "[SYNTHETIC DEMO] Fictional post-walk check-in \(index). A linked walk does not imply a cause.", tripID: tripID))
            if index.isMultiple(of: 2) {
                notes.append(SymptomEntry(id: try identifier(prefix: "D3B10000", index: walkCount + index / 2),
                    date: trip.date.addingTimeInterval(10 * 3600), kind: symptomKinds[(index + 2) % symptomKinds.count],
                    severity: 1 + index % 5,
                    notes: "[SYNTHETIC DEMO] Fictional independent evening check-in. No walk is linked."))
            }
        }
        return try JournalCloudSnapshot(trips: trips, notes: notes, profile: .init(displayName: "Demo Walker"),
                                        preferences: .init(walkingPace: "Easy", extraMinutes: 10)).validated()
    }

    static func validate(_ snapshot: JournalCloudSnapshot) throws -> JournalCloudSnapshot {
        let result = try snapshot.validated(), ids = Set(snapshot.trips.map(\.id))
        guard result.trips.count == walkCount, result.notes.count == noteCount,
              result.trips.allSatisfy({ $0.demo && $0.destination.hasPrefix("[SYNTHETIC DEMO]") && ($0.coverage > 0 ? $0.dose != nil : $0.dose == nil) }),
              result.notes.allSatisfy({ $0.notes.hasPrefix("[SYNTHETIC DEMO]") && symptomKinds.contains($0.kind) && ($0.tripID.map { ids.contains($0) } ?? true) })
        else { throw JournalSyncError.invalid }
        return result
    }

    private static func identifier(prefix: String, index: Int) throws -> UUID {
        guard let value = UUID(uuidString: String(format: "\(prefix)-0000-4000-8000-%012d", index)) else { throw JournalSyncError.invalid }
        return value
    }
}

struct DemoJournalWindow {
    let trips: [CloudTripSummary]
    let notes: [SymptomEntry]
    init(snapshot: JournalCloudSnapshot, days: Int, calendar: Calendar = .current) {
        let end = (snapshot.trips.map(\.date) + snapshot.notes.map(\.date)).max() ?? .distantPast
        let cutoff = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: calendar.startOfDay(for: end)) ?? .distantPast
        trips = snapshot.trips.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }
        notes = snapshot.notes.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }
    }
    var kilometres: Double { trips.reduce(0) { $0 + $1.metres } / 1000 }
    var completeCoverageCount: Int { trips.filter { $0.coverage == 1 }.count }
    var partialCoverageCount: Int { trips.filter { $0.coverage > 0 && $0.coverage < 1 }.count }
    var missingCoverageCount: Int { trips.filter { $0.coverage == 0 }.count }
}
