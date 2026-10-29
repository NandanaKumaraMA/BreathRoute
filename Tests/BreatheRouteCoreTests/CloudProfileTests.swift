import Foundation
import Testing
@testable import BreatheRouteCore

@Test func legacyJournalRestoresWithoutInventingProfileAndSettings() throws {
    let data = Data(#"{"trips":[],"notes":[]}"#.utf8)
    let old = try JournalCloudSnapshot.decoded(data)
    #expect(old.profile == nil && old.preferences == nil)
    let enriched = JournalCloudSnapshot(profile: .init(displayName: "Demo Walker"), preferences: .init(walkingPace: "Brisk", extraMinutes: 20))
    let migrated = try JournalCloudMerge.merge(base: old, local: enriched, remote: old)
    #expect(migrated.snapshot == enriched && migrated.settingsConflictCount == 0)
}
@Test func profileAndPreferenceChangesMergeIndependentlyAndFirstDeviceRestores() throws {
    let base = JournalCloudSnapshot(profile: .init(displayName: "Original"), preferences: .init(walkingPace: "Easy", extraMinutes: 10))
    var mine = base, theirs = base
    mine.profile?.displayName = "Updated name"; theirs.preferences?.extraMinutes = 20
    let result = try JournalCloudMerge.merge(base: base, local: mine, remote: theirs)
    #expect(result.snapshot.profile == mine.profile && result.snapshot.preferences == theirs.preferences)
    let restored = try JournalCloudMerge.merge(base: .init(), local: .init(), remote: result.snapshot)
    #expect(restored.snapshot == result.snapshot)
}
@Test func competingPreferencesKeepServerValueAndReportReviewInsteadOfSilentLoss() throws {
    let base = JournalCloudSnapshot(preferences: .init(walkingPace: "Easy", extraMinutes: 10))
    var mine = base, theirs = base
    mine.preferences?.extraMinutes = 5; theirs.preferences?.extraMinutes = 20
    let result = try JournalCloudMerge.merge(base: base, local: mine, remote: theirs)
    #expect(result.snapshot.preferences == theirs.preferences && result.settingsConflictCount == 1)
}
@Test func cloudSettingsRejectSecretsUnsupportedPaceAndInvalidBudget() throws {
    let valid = JournalCloudSnapshot(profile: .init(displayName: "Synthetic"), preferences: .init(walkingPace: "Easy", extraMinutes: 10))
    let fields = try #require(JSONSerialization.jsonObject(with: valid.encoded()) as? [String: Any])
    #expect(Set((fields["profile"] as? [String: Any])?.keys.map { $0 } ?? []) == ["displayName"])
    #expect(Set((fields["preferences"] as? [String: Any])?.keys.map { $0 } ?? []) == ["walkingPace", "extraMinutes"])
    for preference in [CloudPreferences(walkingPace: "Unsupported", extraMinutes: 10), .init(walkingPace: "Easy", extraMinutes: .nan), .init(walkingPace: "Easy", extraMinutes: -1)] {
        #expect(throws: JournalSyncError.invalid) { try JournalCloudSnapshot(preferences: preference).encoded() }
    }
    #expect(throws: JournalSyncError.invalid) { try JournalCloudSnapshot(profile: .init(displayName: String(repeating: "x", count: 201))).encoded() }
}

@Test func courseworkDemoFixturesAreStableLabelledAndContainNoPrivateSensors() throws {
    let first = try CloudDemoFixtures.snapshot(), repeated = try CloudDemoFixtures.snapshot()
    #expect(first == repeated && first.trips.count == 30 && first.notes.count == 45)
    #expect(first.trips.allSatisfy { $0.demo && $0.destination.contains("SYNTHETIC DEMO") })
    #expect(first.notes.allSatisfy { $0.notes.contains("SYNTHETIC DEMO") })
    #expect(Set(first.trips.map(\.coverage)) == [0, 0.6, 0.85, 1])
    let text = try #require(String(data: first.encoded(), encoding: .utf8))
    for forbidden in ["recordedPath", "plannedPath", "heartRate", "respiratoryRate", "openweather", "apiKey"] {
        #expect(!text.contains(forbidden))
    }
}

@Test func demoFixturesExerciseAllScenariosWithoutFabricatingMissingExposure() throws {
    let snapshot = try CloudDemoFixtures.validate(CloudDemoFixtures.snapshot())
    #expect(Set(snapshot.notes.map(\.kind)) == Set(CloudDemoFixtures.symptomKinds))
    #expect(Set(snapshot.notes.map(\.severity)) == [1, 2, 3, 4, 5])
    #expect(snapshot.notes.filter { $0.tripID == nil }.count == 15)
    #expect(snapshot.trips.filter { !$0.complete }.count == 2)
    #expect(Set(snapshot.trips.compactMap(\.ventilation)) == [0.015, 0.025, 0.035])
    #expect(snapshot.trips.allSatisfy { $0.coverage > 0 ? ($0.dose ?? 0) > 0 : $0.dose == nil })
    #expect(snapshot.trips.allSatisfy { (0.9...1.7).contains($0.metres / $0.seconds) })
}

@Test func demoWindowsAnchorToDatasetDatesAndKeepMissingCoverageSeparate() throws {
    let snapshot = try CloudDemoFixtures.snapshot()
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 19800)!
    let month = DemoJournalWindow(snapshot: snapshot, days: 30, calendar: calendar)
    let week = DemoJournalWindow(snapshot: snapshot, days: 7, calendar: calendar)
    #expect(month.trips.count == 30 && month.notes.count == 45)
    #expect(week.trips.count == 7 && week.notes.count == 11)
    #expect(month.completeCoverageCount == 12 && month.partialCoverageCount == 12 && month.missingCoverageCount == 6)
    #expect(week.completeCoverageCount + week.partialCoverageCount + week.missingCoverageCount == week.trips.count)
    #expect(abs(month.kilometres - snapshot.trips.reduce(0) { $0 + $1.metres } / 1000) < 0.00001)
    #expect(month.trips.first?.date == snapshot.trips.map(\.date).max())
    #expect(DemoJournalWindow(snapshot: .init(), days: 7).trips.isEmpty)
}

@Test func demoValidationRejectsRealRecordsDanglingLinksAndIncompleteDatasets() throws {
    let valid = try CloudDemoFixtures.snapshot()
    var real = valid; real.trips[0].demo = false
    var missing = valid; missing.trips.removeLast()
    var unlabelled = valid; unlabelled.notes[0].notes = "An actual person's note"
    var dangling = valid; dangling.notes[0].tripID = UUID()
    var invented = valid; let index = invented.trips.firstIndex { $0.coverage == 0 }!; invented.trips[index].dose = 12
    for invalid in [real, missing, unlabelled, dangling, invented] {
        #expect(throws: JournalSyncError.invalid) { try CloudDemoFixtures.validate(invalid) }
    }
}
