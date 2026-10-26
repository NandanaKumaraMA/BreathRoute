import Foundation

enum AccountEnvironment: String, Sendable { case firebase, emulator }

struct AccountIdentity: Equatable, Sendable {
    let userID: String
    let projectID: String
    let email: String?
    let emailVerified: Bool
    let environment: AccountEnvironment
    var journalNamespace: String { "\(environment.rawValue)|\(projectID.utf8.count):\(projectID)\(userID)" }
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
