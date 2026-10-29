import Foundation
import CryptoKit

enum JournalSyncError: String, LocalizedError {
    case invalid = "This journal contains an unsupported record. Local records have not been changed."
    case tooLarge = "This journal exceeds this version's cloud limit of 500 entries or 350 KB. Your local journal is unchanged."
    case changed = "The cloud journal changed during sync. Please try Sync now again."
    case unavailable = "Cloud sync needs a signed-in account and a configured connection."
    case wrongAccount = "The account changed during sync. No records were applied to this journal."
    var errorDescription: String? { rawValue }
}

struct CloudUserProfile: Codable, Equatable, Sendable {
    var displayName: String
    var valid: Bool { displayName.count <= 200 }
}
struct CloudPreferences: Codable, Equatable, Sendable {
    var walkingPace: String
    var extraMinutes: Double
    var valid: Bool { ["Easy", "Brisk", "Fast"].contains(walkingPace) && extraMinutes.isFinite && (0...120).contains(extraMinutes) }
}

/// An explicit allowlist: GPS geometry, motion summaries and Health records have no cloud fields.
struct CloudTripSummary: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var destination: String
    var metres: Double
    var seconds: Double
    var dose: Double?
    var coverage: Double
    var demo: Bool
    var complete: Bool
    var ventilation: Double?
    var routeSource: String?
    var conflictCopyOf: UUID?

    init(_ trip: TripEntry) {
        id = trip.id; date = JournalCloudSnapshot.cloudDate(trip.date); destination = trip.destination; metres = trip.metres
        seconds = trip.seconds; dose = trip.dose; coverage = trip.coverage; demo = trip.demo
        complete = trip.complete; ventilation = trip.ventilation; routeSource = trip.routeSource
        conflictCopyOf = trip.conflictCopyOf
    }
    func restored(preserving local: TripEntry?) -> TripEntry {
        // Keep the full on-device record only when its summary still describes this version.
        if let local, CloudTripSummary(local) == self { return local }
        return TripEntry(id: id, date: date, destination: destination, metres: metres, seconds: seconds,
                         dose: dose, coverage: coverage, demo: demo, complete: complete,
                         routeSource: routeSource, ventilation: ventilation, cloudSummary: true, conflictCopyOf: conflictCopyOf)
    }
    var valid: Bool {
        JournalCloudSnapshot.valid(date) && !destination.isEmpty && destination.count <= 500 &&
        metres.isFinite && (0...1_000_000).contains(metres) && seconds.isFinite && (0...1_209_600).contains(seconds) &&
        coverage.isFinite && (0...1).contains(coverage) &&
        (dose.map { $0.isFinite && (0...1_000_000_000).contains($0) } ?? true) &&
        (ventilation.map { $0.isFinite && (0.001...0.2).contains($0) } ?? true) &&
        (routeSource.map { $0.count <= 500 } ?? true)
    }
}

struct JournalCloudSnapshot: Codable, Equatable, Sendable {
    var trips: [CloudTripSummary] = []
    var notes: [SymptomEntry] = []
    var profile: CloudUserProfile?
    var preferences: CloudPreferences?
    static let maxEntries = 500
    static let maxBytes = 350_000
    static func cloudDate(_ date: Date) -> Date {
        guard date.timeIntervalSince1970.isFinite else { return date }
        return Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }
    static func valid(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && (0...4_102_444_800).contains(date.timeIntervalSince1970)
    }
    func validated() throws -> Self {
        guard trips.count + notes.count <= Self.maxEntries else { throw JournalSyncError.tooLarge }
        let ids = trips.map(\.id) + notes.map(\.id)
        guard Set(ids).count == ids.count, profile?.valid != false, preferences?.valid != false,
              trips.allSatisfy(\.valid), notes.allSatisfy({
            Self.valid($0.date) && !$0.kind.isEmpty && $0.kind.count <= 80 && (1...5).contains($0.severity) && $0.notes.count <= 12_000
        }) else { throw JournalSyncError.invalid }
        let trips = trips.map { value in var value = value; value.date = Self.cloudDate(value.date); return value }
        let notes = notes.map { value in var value = value; value.date = Self.cloudDate(value.date); return value }
        return Self(trips: trips.sorted { $0.id.uuidString < $1.id.uuidString }, notes: notes.sorted { $0.id.uuidString < $1.id.uuidString },
                    profile: profile, preferences: preferences)
    }
    func encoded() throws -> Data {
        let data = try Self.encoder().encode(validated())
        guard data.count <= Self.maxBytes else { throw JournalSyncError.tooLarge }; return data
    }
    static func decoded(_ data: Data) throws -> Self {
        guard data.count <= maxBytes else { throw JournalSyncError.tooLarge }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Self.self, from: data).validated()
    }
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970; return encoder
    }
}

struct JournalCloudState: Codable {
    static let storageID = UUID(uuidString: "D1EFB760-C73B-47DA-BB98-337E34271D95")!
    var enabled = false
    var base = JournalCloudSnapshot()
    var revision: String?
    var lastSyncedAt: Date?
    var consentVersion: Int?
}

struct JournalMergeResult {
    let snapshot: JournalCloudSnapshot
    let conflictCount: Int
    var settingsConflictCount = 0
}

enum JournalCloudMerge {
    static func merge(base: JournalCloudSnapshot, local: JournalCloudSnapshot, remote: JournalCloudSnapshot) throws -> JournalMergeResult {
        let base = try base.validated(), local = try local.validated(), remote = try remote.validated()
        let trips = try mergeRecords(base: base.trips, local: local.trips, remote: remote.trips) { value in
            var copy = value; copy.id = try copyID(value); copy.conflictCopyOf = value.id; return copy
        }
        let notes = try mergeRecords(base: base.notes, local: local.notes, remote: remote.notes) { value in
            var copy = value; copy.id = try copyID(value); copy.conflictCopyOf = value.id; return copy
        }
        let profile = mergeSetting(base: base.profile, local: local.profile, remote: remote.profile)
        let preferences = mergeSetting(base: base.preferences, local: local.preferences, remote: remote.preferences)
        let snapshot = try JournalCloudSnapshot(trips: trips.0, notes: notes.0, profile: profile.0, preferences: preferences.0).validated()
        _ = try snapshot.encoded()
        return JournalMergeResult(snapshot: snapshot, conflictCount: trips.1 + notes.1, settingsConflictCount: profile.1 + preferences.1)
    }
    private static func mergeSetting<T: Equatable>(base: T?, local: T?, remote: T?) -> (T?, Int) {
        if local == remote { return (local, 0) }
        if local == base { return (remote, 0) }
        if remote == base { return (local, 0) }
        // A newly connected device restores existing settings; competing settings
        // keep the server version and explicitly ask the user to review them.
        return (remote, 1)
    }
    private static func mergeRecords<T: Identifiable & Equatable>(base: [T], local: [T], remote: [T], copy: (T) throws -> T) throws -> ([T], Int) where T.ID == UUID {
        let b = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        let l = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let r = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        var result: [UUID: T] = [:], copies: [T] = []; var conflicts = 0
        for id in Set(b.keys).union(l.keys).union(r.keys) {
            let previous = b[id], mine = l[id], theirs = r[id]
            if mine == theirs { result[id] = mine }
            else if mine == previous { result[id] = theirs }
            else if theirs == previous { result[id] = mine }
            else {
                conflicts += 1
                // Different edits keep the cloud original plus a local conflict copy.
                // Edit/delete keeps the deletion and preserves the edit under a new ID.
                if let mine, let theirs { result[id] = theirs; copies.append(try copy(mine)) }
                else if let edited = mine ?? theirs { copies.append(try copy(edited)) }
            }
        }
        for value in copies {
            guard result[value.id] == nil || result[value.id] == value else { throw JournalSyncError.invalid }
            result[value.id] = value
        }
        return (Array(result.values), conflicts)
    }
    private static func copyID<T: Encodable>(_ value: T) throws -> UUID {
        // Deterministic IDs prevent duplicate conflict copies after a committed upload
        // followed by a local-save failure or interrupted acknowledgement.
        var bytes = Array(SHA256.hash(data: try JournalCloudSnapshot.encoder().encode(value)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50; bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
