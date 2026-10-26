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
