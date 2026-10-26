import SwiftUI

struct AccountCard: View {
    @Bindable var model: AppModel
    let open: () -> Void
    @State private var confirmSignOut = false
    var body: some View {
        Surface {
            SectionHeading(title: "Your account", detail: model.account.isEmulator ? "Local emulator" : "Firebase Authentication")
            if let identity = model.account.identity {
                Label(identity.email ?? "Signed in", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline).foregroundStyle(Palette.ink).textSelection(.enabled)
                StatusPill(title: identity.emailVerified ? "Email verified" : "Email not verified", symbol: identity.emailVerified ? "checkmark.seal" : "envelope")
                Text("This account has its own journal on this device. Cloud backup and sync are the next implementation step.").font(.caption).foregroundStyle(Palette.muted)
                if !identity.emailVerified {
                    Button("Send verification email") { Task { await model.account.verifyEmail() } }.frame(minHeight: 44)
                    Button("Refresh verification status") { Task { await model.account.refreshIdentity() } }.font(.caption).frame(minHeight: 44)
                }
                Button("Sign out", role: .destructive) { confirmSignOut = true }.frame(minHeight: 44)
                    .disabled(!model.canChangeAccount)
            } else {
                Label("Using a local journal", systemImage: "iphone").font(.headline).foregroundStyle(Palette.ink)
                Text("Sign in or create an account. Your existing guest journal stays separate and is available again when you sign out.").font(.subheadline).foregroundStyle(Palette.muted)
                if !model.account.available { InfoNote(text: model.account.setupMessage) }
                Button(model.account.available ? "Sign in or create account" : "View account options", systemImage: "person.badge.key") { model.account.clearMessage(); open() }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(!model.canChangeAccount)
            }
            if model.account.isEmulator { InfoNote(symbol: "hammer", text: "Local authentication emulator. Test accounts are not cloud accounts and no cloud journal is connected.") }
            if !model.canChangeAccount && !model.account.working { InfoNote(text: "Finish or resolve your unfinished walk and wait for ongoing requests before changing accounts.") }
            if model.account.working { ProgressView("Contacting account service…") }
            if let message = model.account.message { InfoNote(text: message) }
        }.confirmationDialog("Sign out of this account?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { if model.canChangeAccount { model.account.signOut() } }
        } message: { Text("This account's journal stays on this device. Your separate guest journal will be shown. Records are not moved between accounts.") }
    }
}

private enum AccountFormMode: String, CaseIterable, Identifiable {
    case signIn = "Sign in", register = "Register", reset = "Reset"
    var id: String { rawValue }
    var title: String { switch self { case .signIn: "Welcome back."; case .register: "Your next chapter."; case .reset: "Find your way back." } }
    var action: String { switch self { case .signIn: "Sign in"; case .register: "Create account"; case .reset: "Send reset instructions" } }
}

struct AccountAccessView: View {
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
