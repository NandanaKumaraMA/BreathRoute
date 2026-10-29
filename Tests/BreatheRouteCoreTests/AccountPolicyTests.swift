import Foundation
import Testing
@testable import BreatheRouteCore

@Test func accountValidationPreservesPasswordsAndChecksRegistrationSeparately() throws {
    #expect(try AccountInput.validate(email: " person+walk@example.test \n", password: " 1234 ") == "person+walk@example.test")
    #expect(throws: AccountInputError.passwordLength) { try AccountInput.validate(email: "p@example.test", password: "123456", confirmation: "123456") }
    #expect(throws: AccountInputError.confirmation) { try AccountInput.validate(email: "p@example.test", password: " spaced pass ", confirmation: "spaced pass") }
    #expect(try AccountInput.validate(email: "p@example.test", password: " spaced pass ", confirmation: " spaced pass ") == "p@example.test")
    #expect(throws: AccountInputError.email) { try AccountInput.email("a b@example.test") }
    #expect(throws: AccountInputError.email) { try AccountInput.email("p@@example.test") }
    #expect(throws: AccountInputError.password) { try AccountInput.validate(email: "p@example.test", password: "") }
}
@Test func accountNamespaceIncludesProjectEnvironmentAndUnambiguousIdentifiers() {
    func identity(_ user: String, _ project: String, _ environment: AccountEnvironment = .firebase) -> String {
        AccountIdentity(userID: user, projectID: project, email: nil, emailVerified: false, environment: environment).journalNamespace
    }
    #expect(identity("alice", "project") != identity("bob", "project"))
    #expect(identity("alice", "project") != identity("alice", "another-project"))
    #expect(identity("alice", "project") != identity("alice", "project", .emulator))
    #expect(identity("b|c", "a") != identity("c", "a|b"))
}

@Test func googleConfigurationRequiresTheMatchingRegisteredCallback() {
    let client = "1234567890-test-client.apps.googleusercontent.com"
    let scheme = "com.googleusercontent.apps.1234567890-test-client"
    #expect(GoogleAccountConfiguration.isReady(clientID: client, registeredSchemes: [scheme]))
    #expect(!GoogleAccountConfiguration.isReady(clientID: client, registeredSchemes: ["breatheroute-unconfigured"]))
    #expect(!GoogleAccountConfiguration.isReady(clientID: client, registeredSchemes: [scheme + ".other-project"]))
    #expect(!GoogleAccountConfiguration.isReady(clientID: nil, registeredSchemes: [scheme]))
    for invalid in ["", "https://example.com", "other.apps.googleusercontent.com\n", "client apps.googleusercontent.com", "client.apps.googleusercontent.com/redirect"] {
        #expect(GoogleAccountConfiguration.callbackScheme(clientID: invalid) == nil)
    }
}

@Test func googleProviderRefreshKeepsTheSameJournalAndAvoidsPasswordOnlyActions() {
    let original = AccountIdentity(userID: "alice", projectID: "project", email: "alice@example.test", emailVerified: false, environment: .firebase, providerIDs: ["password"])
    let google = AccountIdentity(userID: "alice", projectID: "project", email: "alice@example.test", emailVerified: true, environment: .firebase, providerIDs: ["google.com"], displayName: "Alice")
    #expect(original.canVerifyEmail)
    #expect(!google.canVerifyEmail)
    #expect(google.usesGoogle)
    #expect(google.displayLabel == "alice@example.test")
    #expect(original.journalNamespace == google.journalNamespace)
    let other = AccountIdentity(userID: "bob", projectID: "project", email: "alice@example.test", emailVerified: true, environment: .firebase, providerIDs: ["google.com"])
    #expect(other.journalNamespace != google.journalNamespace)
}
