import Foundation

enum PushDestination: String, Sendable { case journal, settings }
struct PushEnvelope: Sendable, Equatable {
    let kind: String
    let recipientUID: String
    let installationID: String
    nonisolated init?(fields: [String: String]) {
        guard fields["version"] == "1", let kind = fields["kind"], ["journal_updated", "connection_test"].contains(kind),
              let uid = fields["recipientUID"], !uid.isEmpty, uid.count <= 128,
              let installation = fields["installationID"], UUID(uuidString: installation) != nil else { return nil }
        self.kind = kind; recipientUID = uid; installationID = installation.lowercased()
    }
    nonisolated func destination(userID: String?, installation: String, enabled: Bool) -> PushDestination? {
        guard enabled, recipientUID == userID, installationID == installation.lowercased() else { return nil }
        return kind == "journal_updated" ? .journal : .settings
    }
}
