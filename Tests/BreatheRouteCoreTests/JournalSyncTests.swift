import Foundation
import Testing
@testable import BreatheRouteCore

private func note(_ text: String = "Synthetic note") -> SymptomEntry {
    SymptomEntry(date: Date(timeIntervalSince1970: 1_700_000_000.123456), notes: text)
}

@Test func cloudPayloadExcludesPathsAndPhoneActivityAndPreservesMatchingLocalDetails() throws {
    let point = GeoCoordinate(latitude: 6.9, longitude: 79.8)
    let trip = TripEntry(date: Date(timeIntervalSince1970: 1_700_000_000.123456), destination: "Synthetic park",
                         metres: 100, seconds: 90, dose: 1, coverage: 0.5, demo: false, complete: true,
                         activity: WalkActivitySummary(steps: 25, pedometerMetres: 80, timeline: MotionTimeline(start: Date()),
                             stepStatus: .available, classificationStatus: .available, stepsUpdatedAt: Date()),
                         plannedPath: [point], routeSource: "Synthetic", ventilation: 0.015)
    let snapshot = JournalCloudSnapshot(trips: [CloudTripSummary(trip)], notes: [note()])
    let data = try snapshot.encoded(), decoded = try JournalCloudSnapshot.decoded(data)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let fields = try #require((json["trips"] as? [[String: Any]])?.first)
    #expect(Set(fields.keys) == ["id", "date", "destination", "metres", "seconds", "dose", "coverage", "demo", "complete", "routeSource", "ventilation"])
    let summary = try #require(decoded.trips.first)
    let kept = summary.restored(preserving: trip)
    #expect(kept.plannedPath?.count == 1 && kept.activity?.steps == 25 && kept.cloudSummary == nil)
    let restored = summary.restored(preserving: nil)
    #expect(restored.cloudSummary == true && restored.plannedPath == nil && restored.activity == nil)
    #expect(decoded == (try snapshot.validated()))
}

@Test func cloudMergeCombinesIndependentChangesAndPropagatesDeletionsBothWays() throws {
    let first = note("First"), second = note("Second")
    let base = JournalCloudSnapshot(notes: [first, second])
    var edited = second; edited.notes = "Edited remotely"
    let merged = try JournalCloudMerge.merge(base: base, local: .init(notes: [second]), remote: .init(notes: [first, edited]))
    #expect(merged.snapshot.notes.count == 1 && merged.snapshot.notes.first?.notes == "Edited remotely")
    #expect(merged.conflictCount == 0)
    let reverse = try JournalCloudMerge.merge(base: base, local: .init(notes: [first, edited]), remote: .init(notes: [second]))
    #expect(reverse.snapshot == merged.snapshot)
}

@Test func competingEditsKeepBothAndRetryDoesNotDuplicateConflictCopies() throws {
    let original = note("Original")
    var mine = original, theirs = original; mine.notes = "Local edit"; theirs.notes = "Remote edit"
    let base = JournalCloudSnapshot(notes: [original]), local = JournalCloudSnapshot(notes: [mine])
    let first = try JournalCloudMerge.merge(base: base, local: local, remote: .init(notes: [theirs]))
    #expect(first.conflictCount == 1 && first.snapshot.notes.count == 2)
    #expect(first.snapshot.notes.first(where: { $0.id == original.id })?.notes == "Remote edit")
    let copy = try #require(first.snapshot.notes.first { $0.conflictCopyOf == original.id })
    #expect(copy.notes == "Local edit" && copy.id != original.id)
    // The upload committed, but the device failed to save its new baseline. Retry the old local state.
    let retry = try JournalCloudMerge.merge(base: base, local: local, remote: first.snapshot)
    #expect(retry.snapshot == first.snapshot)
}

@Test func editDeleteConflictsPreserveEditUnderStableCopyID() throws {
    let original = note("Original"); var edited = original; edited.notes = "Keep this edit"
    let base = JournalCloudSnapshot(notes: [original])
    let localEdit = try JournalCloudMerge.merge(base: base, local: .init(notes: [edited]), remote: .init())
    let remoteEdit = try JournalCloudMerge.merge(base: base, local: .init(), remote: .init(notes: [edited]))
    #expect(localEdit.snapshot == remoteEdit.snapshot && localEdit.conflictCount == 1)
    #expect(localEdit.snapshot.notes.count == 1 && localEdit.snapshot.notes.first?.id != original.id)
    let retry = try JournalCloudMerge.merge(base: base, local: .init(notes: [edited]), remote: localEdit.snapshot)
    #expect(retry.snapshot == localEdit.snapshot)
}

@Test func cloudDateRoundTripDoesNotCreateSpuriousConflict() throws {
    let original = note(), local = JournalCloudSnapshot(notes: [original])
    let remote = try JournalCloudSnapshot.decoded(local.encoded())
    let merged = try JournalCloudMerge.merge(base: remote, local: local, remote: remote)
    #expect(merged.snapshot == remote && merged.conflictCount == 0)
}

@Test func cloudValidationRejectsDuplicatesInvalidNumbersAndOversizedPayloads() throws {
    let entry = note()
    #expect(throws: JournalSyncError.invalid) { try JournalCloudSnapshot(notes: [entry, entry]).encoded() }
    var invalid = entry; invalid.severity = 6
    #expect(throws: JournalSyncError.invalid) { try JournalCloudSnapshot(notes: [invalid]).encoded() }
    let trip = TripEntry(destination: "Invalid", metres: .nan, seconds: 10, dose: nil, coverage: 0, demo: false, complete: false)
    #expect(throws: JournalSyncError.invalid) { try JournalCloudSnapshot(trips: [CloudTripSummary(trip)]).encoded() }
    #expect(throws: JournalSyncError.tooLarge) { try JournalCloudSnapshot(notes: (0...500).map { _ in note() }).encoded() }
    #expect(throws: JournalSyncError.tooLarge) { try JournalCloudSnapshot(notes: (0..<40).map { _ in note(String(repeating: "x", count: 10_000)) }).encoded() }
    #expect(throws: JournalSyncError.tooLarge) { try JournalCloudSnapshot.decoded(Data(repeating: 32, count: 350_001)) }
}
