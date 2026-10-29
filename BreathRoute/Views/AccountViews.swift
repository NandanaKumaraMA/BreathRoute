import SwiftUI
import GoogleSignInSwift
import UIKit

struct AccountCard: View {
    @Bindable var model: AppModel
    let open: () -> Void
    @State private var confirmSignOut = false
    var body: some View {
        Surface {
            SectionHeading(title: "Your account", detail: model.account.isEmulator ? "Local emulator" : "Firebase Authentication")
            if let identity = model.account.identity {
                Label(identity.displayLabel, systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline).foregroundStyle(Palette.ink).textSelection(.enabled)
                if identity.usesGoogle { StatusPill(title: "Signed in with Google", symbol: "checkmark.seal") }
                else if identity.email != nil { StatusPill(title: identity.emailVerified ? "Email verified" : "Email not verified", symbol: identity.emailVerified ? "checkmark.seal" : "envelope") }
                Text("This account has its own journal on this device. Cloud sync is optional; manage it in Cloud journal below.").font(.caption).foregroundStyle(Palette.muted)
                if identity.canVerifyEmail {
                    Button("Send verification email") { Task { await model.account.verifyEmail() } }.frame(minHeight: 44)
                    Button("Refresh verification status") { Task { await model.account.refreshIdentity() } }.font(.caption).frame(minHeight: 44)
                }
                Button("Sign out", role: .destructive) { confirmSignOut = true }.frame(minHeight: 44)
                    .disabled(!model.canChangeAccount)
            } else {
                Label("Using a local journal", systemImage: "iphone").font(.headline).foregroundStyle(Palette.ink)
                Text("Continue with Google to open your account's journal. Your guest journal stays separate and is available again when you sign out.").font(.subheadline).foregroundStyle(Palette.muted)
                if !model.account.available { InfoNote(text: model.account.setupMessage) }
                Button("Open account options", systemImage: "person.badge.key") { model.account.clearMessage(); open() }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(!model.canChangeAccount)
            }
            if model.account.isEmulator { InfoNote(symbol: "hammer", text: "Local emulator test account. Optional journal sync connects only to the local Firestore emulator; these are not cloud records.") }
            if !model.canChangeAccount && !model.account.working { InfoNote(text: "Finish or resolve your unfinished walk and wait for ongoing requests before changing accounts.") }
            if model.account.working { ProgressView("Contacting account service…") }
            if let message = model.account.message { InfoNote(text: message) }
        }.confirmationDialog("Sign out of this account?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { if model.canChangeAccount { model.account.signOut() } }
        } message: { Text("This account's journal stays on this device. Your separate guest journal will be shown. Records are not moved between accounts.") }
    }
}

struct AccountAccessView: View {
    @Bindable var model: AppModel
    @State private var presentingController: UIViewController?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var canStart: Bool { model.account.googleAvailable && model.canChangeAccount && presentingController != nil }
    var body: some View {
        NavigationStack {
            Page {
                HStack(spacing: 10) { BrandMark(); Text("breathe route").font(.headline).foregroundStyle(Palette.ink) }
                PageHeader(title: "A space for\nyour next step.", subtitle: "Your personal account", symbol: "person.crop.circle")
                Surface {
                    Label("Your journal, your account", systemImage: "book.closed")
                        .font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("Use your Google account to sign in or get started. Your walks and check-ins stay in a separate journal on this device.")
                        .font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    GoogleSignInButton(scheme: colorScheme == .dark ? .dark : .light, style: .wide,
                                       state: canStart ? .normal : .disabled) {
                        guard canStart, let presentingController else { return }
                        Task { @MainActor in
                            if await model.account.signInWithGoogle(presenting: presentingController) { dismiss() }
                        }
                    }.frame(minHeight: 48).accessibilityLabel("Continue with Google")
                    if model.account.working { ProgressView("Completing sign-in…") }
                    if !model.account.googleAvailable { InfoNote(symbol: "person.badge.key", text: model.account.googleSetupMessage) }
                    if let message = model.account.message { InfoNote(text: message).accessibilityIdentifier("account-result-message") }
                    if !model.canChangeAccount && !model.account.working {
                        InfoNote(text: "Finish or resolve your unfinished walk and wait for ongoing requests before signing in.")
                    }
                }
                Surface {
                    Label("Keep your own pace", systemImage: "leaf").font(.headline).foregroundStyle(Palette.ink)
                    Text("You can keep using BreatheRoute without an account. Your guest journal stays available when you sign out.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    InfoNote(symbol: "iphone", text: "Signing in does not upload your journal. You can choose optional cloud sync afterwards in Cloud journal.")
                }
                Button("Continue with local journal") { dismiss() }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .disabled(model.account.working)
                Text("Google shares your basic profile and email with BreatheRoute when you sign in.")
                    .font(.caption).foregroundStyle(Palette.muted)
                #if DEBUG
                if model.account.isEmulator {
                    NavigationLink("Local emulator account tests") { EmailAccountAccessView(model: model) }
                        .font(.caption).frame(minHeight: 44).disabled(model.account.working)
                }
                #endif
            }
            .background(SignInPresentationAnchor(controller: $presentingController).frame(width: 0, height: 0))
            .navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(model.account.working) } }
            .interactiveDismissDisabled(model.account.working)
        }
    }
}

/// Bind the OAuth presenter to this sheet's window, including when more than one iPad scene exists.
private struct SignInPresentationAnchor: UIViewControllerRepresentable {
    @Binding var controller: UIViewController?
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        DispatchQueue.main.async { self.controller = controller }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private enum AccountFormMode: String, CaseIterable, Identifiable {
    case signIn = "Sign in", register = "Register", reset = "Reset"
    var id: String { rawValue }
    var title: String { switch self { case .signIn: "Welcome back."; case .register: "Your next chapter."; case .reset: "Find your way back." } }
    var action: String { switch self { case .signIn: "Sign in"; case .register: "Create account"; case .reset: "Send reset instructions" } }
}

private struct EmailAccountAccessView: View {
    @Bindable var model: AppModel
    @State private var mode = AccountFormMode.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @FocusState private var focused: Field?
    @Environment(\.dismiss) private var dismiss
    private enum Field { case email, password, confirmation }
    var body: some View {
        NavigationStack {
            Page {
                HStack(spacing: 10) { BrandMark(); Text("breathe route").font(.headline).foregroundStyle(Palette.ink) }
                PageHeader(title: mode.title, subtitle: mode == .reset ? "Password recovery" : "Your personal account", symbol: "person.badge.key")
                if model.account.isEmulator { StatusPill(title: "Local emulator · test accounts only", symbol: "hammer") }
                if !model.account.available { InfoNote(symbol: "network", text: model.account.setupMessage) }
                Surface {
                    Picker("Account action", selection: $mode) { ForEach(AccountFormMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email address").font(.caption).foregroundStyle(Palette.muted)
                        TextField("you@example.com", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused, equals: .email)
                            .submitLabel(mode == .reset ? .done : .next).onSubmit { if mode != .reset { focused = .password } }
                            .accessibilityLabel("Account email address")
                    }.padding(.vertical, 8)
                    if mode != .reset {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password").font(.caption).foregroundStyle(Palette.muted)
                            SecureField("Password", text: $password).textContentType(mode == .register ? .newPassword : .password)
                                .focused($focused, equals: .password).submitLabel(mode == .register ? .next : .done)
                                .onSubmit { if mode == .register { focused = .confirmation } else { focused = nil } }
                                .accessibilityLabel("Account password")
                        }.padding(.vertical, 8)
                    }
                    if mode == .register {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm password").font(.caption).foregroundStyle(Palette.muted)
                            SecureField("Repeat your password", text: $confirmation).textContentType(.newPassword)
                                .focused($focused, equals: .confirmation).submitLabel(.done).onSubmit { focused = nil }
                                .accessibilityLabel("Confirm account password")
                        }.padding(.vertical, 8)
                        Text("Use at least 8 characters. Your project's password policy may require more.").font(.caption).foregroundStyle(Palette.muted)
                    }
                }.disabled(model.account.working || !model.account.available)
                if let message = model.account.message { InfoNote(symbol: "info.circle", text: message) }
                if !model.canChangeAccount && !model.account.working { InfoNote(text: "An unfinished walk or request needs attention before you change accounts.") }
                if model.account.working { ProgressView("Contacting account service…") }
                PrimaryButton(title: mode.action, symbol: mode == .reset ? "envelope" : "arrow.right") { submit() }
                    .disabled(!model.account.available || !model.canChangeAccount)
                InfoNote(symbol: "lock", text: "Your email and password are sent to the configured account service when you submit. Passwords are not saved by this app's journal. Guest and account journals remain separate; cloud journal sync is not enabled yet.")
                Button("Continue with local journal") { dismiss() }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    .disabled(model.account.working)
            }.scrollDismissesKeyboard(.interactively)
                .navigationTitle("Account").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(model.account.working) } }
                .interactiveDismissDisabled(model.account.working)
                .onChange(of: mode) { _, _ in password = ""; confirmation = ""; model.account.clearMessage(); focused = .email }
                .onDisappear { password = ""; confirmation = "" }
        }
    }
    private func submit() {
        guard model.canChangeAccount, model.account.available else { return }
        focused = nil
        Task { @MainActor in
            if mode == .reset { await model.account.resetPassword(email: email) }
            else if await model.account.signIn(email: email, password: password, confirmation: mode == .register ? confirmation : nil) {
                password = ""; confirmation = ""; dismiss()
            }
        }
    }
}
