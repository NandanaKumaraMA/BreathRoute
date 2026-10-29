import Foundation
import Observation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

@MainActor @Observable
final class AccountService {
    private(set) var identity: AccountIdentity?
    private(set) var initializing = true
    private(set) var available = false
    private(set) var working = false
    private(set) var message: String?
    private(set) var setupMessage = "Checking account connection…"
    var isEmulator: Bool { FirebaseBootstrap.environment == .emulator }
    var googleAvailable: Bool { available && !isEmulator && FirebaseBootstrap.googleReady }
    var googleSetupMessage: String {
        if !available { return setupMessage }
        if isEmulator { return "Google sign-in uses a real Google account. This build is using local test accounts instead." }
        return "Google sign-in needs to be connected for this build. You can continue with your local journal."
    }
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
            let account = user.map { Self.identity(for: $0, project: project, environment: environment) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.identity = account; self.onIdentityChange?(account); self.initializing = false
            }
        }
    }
    func signInWithGoogle(presenting controller: UIViewController) async -> Bool {
        guard !working, !initializing, googleAvailable, let auth,
              let clientID = FirebaseBootstrap.googleClientID else { return false }
        guard auth.currentUser == nil else {
            message = "Sign out before choosing a different account."; return false
        }
        guard controller.viewIfLoaded?.window != nil else {
            message = "The sign-in window is not ready. Close account options and try again."; return false
        }
        working = true; message = nil; defer { working = false }
        let google = GIDSignIn.sharedInstance
        // Firebase remains the source of the app's signed-in state. A stale Google-only
        // SDK session must not silently choose the previous account after sign-out.
        google.signOut()
        google.configuration = GIDConfiguration(clientID: clientID)
        do {
            let result = try await google.signIn(withPresenting: controller)
            guard auth.currentUser == nil else { google.signOut(); return false }
            guard let idToken = result.user.idToken?.tokenString, !idToken.isEmpty else {
                google.signOut(); message = "Google could not complete sign-in. Please try again."; return false
            }
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            _ = try await auth.signIn(with: credential)
            return true
        } catch {
            google.signOut()
            let failure = error as NSError
            if failure.domain == kGIDSignInErrorDomain {
                if failure.code != GIDSignInError.canceled.rawValue {
                    message = "Google sign-in could not be completed. Check your connection and try again."
                }
            } else { message = Self.explain(error) }
            return false
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
        do { try auth.signOut(); GIDSignIn.sharedInstance.signOut() } catch { message = Self.explain(error) }
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
                identity = Self.identity(for: user, project: old.projectID, environment: old.environment)
                onIdentityChange?(identity)
            }
        } catch { message = Self.explain(error) }
    }
    private static func identity(for user: User, project: String, environment: AccountEnvironment) -> AccountIdentity {
        AccountIdentity(userID: user.uid, projectID: project, email: user.email,
                        emailVerified: user.isEmailVerified, environment: environment,
                        providerIDs: user.providerData.map(\.providerID), displayName: user.displayName)
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
        case .operationNotAllowed: return "This sign-in method is not enabled for the Firebase project."
        case .accountExistsWithDifferentCredential: return "This email already uses another sign-in method. Use its original method; accounts are not merged automatically."
        case .userDisabled: return "This account is unavailable. Contact the project administrator."
        case .invalidAPIKey, .appNotAuthorized: return "The account connection is not configured correctly for this app."
        default: return "The account request could not be completed. Try again."
        }
    }
}
