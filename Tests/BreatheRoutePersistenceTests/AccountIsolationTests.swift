import Foundation
import Testing
@testable import BreatheRouteCore
@testable import BreatheRoutePersistence

@MainActor @Test func accountStoresKeepGuestAndTwoAccountsSeparateAcrossReopenAndDelete() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BreatheRouteAccounts-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let guestURL = LocalStore.url(in: folder, accountNamespace: nil)
    let aliceURL = LocalStore.url(in: folder, accountNamespace: "firebase|project|alice")
    let bobURL = LocalStore.url(in: folder, accountNamespace: "firebase|project|bob")
    let sharedID = UUID()
    func trip(_ name: String) -> TripEntry { TripEntry(id: sharedID, destination: name, metres: 100, seconds: 60, dose: nil, coverage: 0, demo: false, complete: false) }
    do {
        let guest = try LocalStore(storeURL: guestURL)
        let alice = try LocalStore(storeURL: aliceURL)
        let bob = try LocalStore(storeURL: bobURL)
        try guest.save(trip("Guest walk"), id: sharedID, kind: "trip")
        #expect(try alice.read("trip", as: TripEntry.self).isEmpty)
        try alice.save(trip("Alice walk"), id: sharedID, kind: "trip")
        #expect(try bob.read("trip", as: TripEntry.self).isEmpty)
        try bob.save(trip("Bob walk"), id: sharedID, kind: "trip")
        try bob.delete(id: sharedID)
    }
    #expect(try LocalStore(storeURL: guestURL).read("trip", as: TripEntry.self).first?.destination == "Guest walk")
    #expect(try LocalStore(storeURL: aliceURL).read("trip", as: TripEntry.self).first?.destination == "Alice walk")
    #expect(try LocalStore(storeURL: bobURL).read("trip", as: TripEntry.self).isEmpty)
    #expect(guestURL.lastPathComponent == "BreatheRouteV1.sqlite")
    #expect(aliceURL != bobURL && !aliceURL.lastPathComponent.contains("alice"))
    #expect(LocalStore.url(in: folder, accountNamespace: "../../elsewhere").deletingLastPathComponent().path == folder.path)
}
