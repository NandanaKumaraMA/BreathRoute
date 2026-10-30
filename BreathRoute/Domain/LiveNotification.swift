import Foundation

/// Only authoritative, committed revision changes represent a new cloud update.
struct JournalRevisionEvent: Sendable {
    let exists: Bool
    let revision: String?
    var fromCache = false
    var pendingWrites = false
    var valid = true
}

struct JournalUpdateTracker {
    private(set) var hasBaseline = false
    private(set) var revision: String?
    private var recent: [String] = []

    mutating func accept(_ event: JournalRevisionEvent, suppressAlert: Bool = false) -> Bool {
        guard !event.fromCache, !event.pendingWrites, event.valid,
              !event.exists || event.revision.flatMap(UUID.init(uuidString:)) != nil else { return false }
        let next = event.exists ? event.revision?.lowercased() : nil
        defer {
            hasBaseline = true; revision = next
            if let next, !recent.contains(next) { recent.append(next) }
            if recent.count > 64 { recent.removeFirst(recent.count - 64) }
        }
        return hasBaseline && next != nil && next != revision && !recent.contains(next!) && !suppressAlert
    }
}

struct FreeAlertEnvelope: Sendable {
    let source: String
    let kind: String
    let scope: String
    let installation: String
    let testSession: String?
    var destination: PushDestination { kind == "journal_updated" ? .journal : .settings }

    nonisolated init?(fields: [String: String]) {
        guard fields["freeVersion"] == "1", let source = fields["freeSource"], let kind = fields["freeKind"],
              ["local:local_test", "firestore:journal_updated", "simulator:simulator_test"].contains("\(source):\(kind)"),
              let scope = fields["accountScope"], !scope.isEmpty, scope.count <= 1024,
              let installation = fields["installationID"], UUID(uuidString: installation) != nil else { return nil }
        self.source = source; self.kind = kind; self.scope = scope; self.installation = installation.lowercased()
        testSession = fields["testSession"]
        if source == "simulator", testSession.flatMap(UUID.init(uuidString:)) == nil { return nil }
    }

    nonisolated func matches(scope: String, installation: String) -> Bool {
        self.scope == scope && self.installation == installation.lowercased()
    }
}
