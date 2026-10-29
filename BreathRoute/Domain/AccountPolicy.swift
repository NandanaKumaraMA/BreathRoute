import Foundation

enum AccountEnvironment: String, Sendable { case firebase, emulator }

struct AccountIdentity: Equatable, Sendable {
    let userID: String
    let projectID: String
    let email: String?
    let emailVerified: Bool
    let environment: AccountEnvironment
    var providerIDs: [String] = []
    var displayName: String? = nil
    var usesGoogle: Bool { providerIDs.contains("google.com") }
    var canVerifyEmail: Bool { providerIDs.contains("password") && email != nil && !emailVerified }
    var displayLabel: String { email ?? displayName ?? "Signed in" }
    var journalNamespace: String { "\(environment.rawValue)|\(projectID.utf8.count):\(projectID)\(userID)" }
}

enum GoogleAccountConfiguration {
    // Validate both the downloaded client and the built callback before invoking the SDK.
    static func callbackScheme(clientID: String?) -> String? {
        guard let clientID,
              clientID.range(of: #"\A[A-Za-z0-9-]+\.apps\.googleusercontent\.com\z"#, options: .regularExpression) != nil else { return nil }
        return clientID.split(separator: ".").reversed().joined(separator: ".")
    }
    static func isReady(clientID: String?, registeredSchemes: [String]) -> Bool {
        guard let expected = callbackScheme(clientID: clientID) else { return false }
        return registeredSchemes.contains(expected)
    }
}

enum AccountInputError: String, LocalizedError {
    case email = "Enter a valid email address."
    case password = "Enter your password."
    case passwordLength = "Use at least 8 characters for a new password. The project may require additional characters."
    case passwordTooLong = "The password is too long."
    case confirmation = "The passwords do not match."
    var errorDescription: String? { rawValue }
}

enum AccountInput {
    static func email(_ value: String) throws -> String {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.utf8.count <= 254, email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else { throw AccountInputError.email }
        return email
    }
    static func validate(email value: String, password: String, confirmation: String? = nil) throws -> String {
        let email = try email(value)
        // Preserve password whitespace and allow existing users to sign in under their original policy.
        guard !password.isEmpty else { throw AccountInputError.password }
        guard password.count <= 4096 else { throw AccountInputError.passwordTooLong }
        if let confirmation {
            guard password.count >= 8 else { throw AccountInputError.passwordLength }
            guard password == confirmation else { throw AccountInputError.confirmation }
        }
        return email
    }
}
