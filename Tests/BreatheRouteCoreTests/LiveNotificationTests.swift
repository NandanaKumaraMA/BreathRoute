import Foundation
import Testing
@testable import BreatheRouteCore

@Test func journalUpdatesRequireAuthoritativeCommittedChanges() {
    var tracker = JournalUpdateTracker()
    func accept(_ event: JournalRevisionEvent, suppressAlert: Bool = false) -> Bool { tracker.accept(event, suppressAlert: suppressAlert) }
    let first = UUID().uuidString, second = UUID().uuidString
    #expect(!accept(.init(exists: true, revision: first, fromCache: true)))
    #expect(!tracker.hasBaseline)
    #expect(!accept(.init(exists: true, revision: first)))
    #expect(!accept(.init(exists: true, revision: second, pendingWrites: true)))
    #expect(tracker.revision == first.lowercased())
    #expect(accept(.init(exists: true, revision: second)))
    #expect(!accept(.init(exists: true, revision: second.lowercased())))
    #expect(!accept(.init(exists: true, revision: first)))
}
@Test func malformedAndOwnJournalWritesCannotCreateFalseAlerts() {
    var tracker = JournalUpdateTracker()
    func accept(_ event: JournalRevisionEvent, suppressAlert: Bool = false) -> Bool { tracker.accept(event, suppressAlert: suppressAlert) }
    #expect(!accept(.init(exists: true, revision: "bad")))
    #expect(!tracker.hasBaseline)
    #expect(!accept(.init(exists: false, revision: nil)))
    let own = UUID().uuidString
    #expect(!accept(.init(exists: true, revision: own), suppressAlert: true))
    #expect(!accept(.init(exists: true, revision: own)))
    #expect(!accept(.init(exists: true, revision: UUID().uuidString, valid: false)))
    #expect(accept(.init(exists: true, revision: UUID().uuidString)))
}
@Test func freeAlertsAreTypedAndBoundToAnAccountAndInstallation() throws {
    let id = UUID().uuidString
    var fields = ["freeVersion": "1", "freeSource": "firestore", "freeKind": "journal_updated", "accountScope": "owner-a", "installationID": id]
    let alert = try #require(FreeAlertEnvelope(fields: fields))
    #expect(alert.destination == .journal)
    #expect(alert.matches(scope: "owner-a", installation: id.lowercased()))
    #expect(!alert.matches(scope: "owner-b", installation: id))
    #expect(!alert.matches(scope: "owner-a", installation: UUID().uuidString))
    fields["freeSource"] = "simulator"
    #expect(FreeAlertEnvelope(fields: fields) == nil)
    fields["freeKind"] = "simulator_test"
    #expect(FreeAlertEnvelope(fields: fields) == nil)
    fields["testSession"] = UUID().uuidString
    #expect(FreeAlertEnvelope(fields: fields)?.destination == .settings)
    fields["freeVersion"] = "2"
    #expect(FreeAlertEnvelope(fields: fields) == nil)
}
