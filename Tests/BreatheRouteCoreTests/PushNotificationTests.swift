import Foundation
import Testing
@testable import BreatheRouteCore

private let deviceID = "F1B4885A-87DF-4B84-AB09-7C9708C65282"
private func fields(_ kind: String = "journal_updated") -> [String: String] {
    ["version": "1", "kind": kind, "recipientUID": "owner-a", "installationID": deviceID]
}
@Test func pushRoutesOnlyToTheOptedInRecipientAndInstallation() throws {
    let message = try #require(PushEnvelope(fields: fields()))
    #expect(message.destination(userID: "owner-a", installation: deviceID.lowercased(), enabled: true) == .journal)
    #expect(message.destination(userID: "owner-b", installation: deviceID, enabled: true) == nil)
    #expect(message.destination(userID: nil, installation: deviceID, enabled: true) == nil)
    #expect(message.destination(userID: "owner-a", installation: UUID().uuidString, enabled: true) == nil)
    #expect(message.destination(userID: "owner-a", installation: deviceID, enabled: false) == nil)
}
@Test func pushRejectsUnknownActionsVersionsAndIncompleteRouting() {
    for invalid in ["open_url", "delete_journal", ""] { #expect(PushEnvelope(fields: fields(invalid)) == nil) }
    for key in ["version", "kind", "recipientUID", "installationID"] {
        var missing = fields(); missing.removeValue(forKey: key); #expect(PushEnvelope(fields: missing) == nil)
    }
    var future = fields(); future["version"] = "2"; #expect(PushEnvelope(fields: future) == nil)
    var malformed = fields(); malformed["installationID"] = "another-device"; #expect(PushEnvelope(fields: malformed) == nil)
}
@Test func connectionPushOpensSettingsAndNeverAnArbitraryURL() throws {
    var value = fields("connection_test"); value["url"] = "https://example.invalid/untrusted"
    let message = try #require(PushEnvelope(fields: value))
    #expect(message.destination(userID: "owner-a", installation: deviceID, enabled: true) == .settings)
}
