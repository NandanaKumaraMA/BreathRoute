import Foundation
import Observation
import FirebaseAuth
import FirebaseCore

@MainActor @Observable
final class AccountService {
    private(set) var identity: AccountIdentity?
    private(set) var initializing = true
    private(set) var available = false
    private(set) var working = false
    private(set) var message: String?
    private(set) var setupMessage = "Checking account connection…"
    var isEmulator: Bool { FirebaseBootstrap.environment == .emulator }
    @ObservationIgnored var onIdentityChange: ((AccountIdentity?) -> Void)?
    @ObservationIgnored private var auth: Auth?
    @ObservationIgnored private var listener: AuthStateDidChangeListenerHandle?
    private var started = false

    func start() {
        guard !started else { return }; started = true
        guard let app = FirebaseBootstrap.app, let project = app.options.projectID else {
            initializing = false; setupMessage = FirebaseBootstrap.setupMessage; return
        }
        let auth = Auth.auth(app: app); self.auth = auth
        if isEmulator { auth.useEmulator(withHost: "127.0.0.1", port: 9099) }
        available = true
        let environment = FirebaseBootstrap.environment
        listener = auth.addStateDidChangeListener { [weak self] _, user in
            let account = user.map { AccountIdentity(userID: $0.uid, projectID: project, email: $0.email,
                                                    emailVerified: $0.isEmailVerified, environment: environment) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.identity = account; self.onIdentityChange?(account); self.initializing = false
            }
        }
    }
    func signIn(email: String, password: String, confirmation: String? = nil) async -> Bool {
        guard !working, let auth else { return false }
        message = nil; working = true; defer { working = false }
        do {
            let email = try AccountInput.validate(email: email, password: password, confirmation: confirmation)
            if confirmation != nil { _ = try await auth.createUser(withEmail: email, password: password) }
            else { _ = try await auth.signIn(withEmail: email, password: password) }
            return true
        } catch { message = Self.explain(error); return false }
    }
    func resetPassword(email: String) async {
        guard !working, let auth else { return }
        message = nil; working = true; defer { working = false }
        do {
            try await auth.sendPasswordReset(withEmail: AccountInput.email(email))
            message = "If that email has an account, password-reset instructions will be sent. Check your inbox and spam folder."
        } catch { message = Self.explain(error) }
    }
    func signOut() {
        guard !working, let auth else { return }
        message = nil
        do { try auth.signOut() } catch { message = Self.explain(error) }
    }
    func verifyEmail() async {
        guard !working, let user = auth?.currentUser else { return }
        working = true; message = nil; defer { working = false }
        do { try await user.sendEmailVerification(); message = "Verification instructions sent. Check your inbox and spam folder." }
        catch { message = Self.explain(error) }
    }
    func refreshIdentity() async {
        guard !working, let user = auth?.currentUser else { return }
        working = true; message = nil; defer { working = false }
        do {
            try await user.reload()
            if let old = identity {
                identity = AccountIdentity(userID: user.uid, projectID: old.projectID, email: user.email, emailVerified: user.isEmailVerified, environment: old.environment)
                onIdentityChange?(identity)
            }
        } catch { message = Self.explain(error) }
    }
    func clearMessage() { message = nil }
    private static func explain(_ error: Error) -> String {
        if let input = error as? AccountInputError { return input.rawValue }
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .invalidEmail: return "Enter a valid email address."
        case .weakPassword: return "The password does not meet this project's policy. Try a longer password with upper/lowercase letters, numbers and symbols."
        case .wrongPassword, .invalidCredential, .userNotFound: return "Could not sign in with those details. Check your email and password, or request a password reset."
        case .emailAlreadyInUse: return "Could not create this account. Try signing in or requesting a password reset."
        case .networkError: return "The account service could not be reached. Check your connection and try again."
        case .tooManyRequests: return "Too many account requests. Wait before trying again."
        case .operationNotAllowed: return "Email/password accounts are not enabled for this Firebase project."
        case .userDisabled: return "This account is unavailable. Contact the project administrator."
        case .invalidAPIKey, .appNotAuthorized: return "The account connection is not configured correctly for this app."
        default: return "The account request could not be completed. Try again."
        }
    }
}
