import SwiftUI
import LocalAuthentication

struct ContentView: View {
    @State private var model = AppModel()
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("biometricLock") private var biometricLock = false
    @State private var unlocked = false
    @State private var unlockError: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if !onboarded { WelcomeView(model: model) { onboarded = true; unlocked = true } }
            else if biometricLock && !unlocked { lockScreen }
            else if sizeClass == .regular {
                NavigationSplitView {
                    List(AppSection.allCases) { section in
                        Button { model.section = section } label: { Label(section.rawValue, systemImage: section.symbol).padding(.vertical, 8) }
                            .listRowBackground(model.section == section ? Palette.forest.opacity(0.12) : Color.clear)
                    }.navigationTitle("BreatheRoute")
                } detail: { NavigationStack { destination(model.section) } }
            } else {
                TabView(selection: $model.section) {
                    ForEach(AppSection.allCases) { section in
                        NavigationStack { destination(section) }.tabItem { Label(section.rawValue, systemImage: section.symbol) }.tag(section)
                    }
                }
            }
        }
        .tint(Palette.forest)
        .onChange(of: phase) { _, next in
            model.setForeground(next == .active)
            if next == .background { unlocked = false; model.voice.stop() }
        }
        .alert("Something needs attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    @ViewBuilder private func destination(_ section: AppSection) -> some View {
        switch section {
        case .today: DashboardView(model: model)
        case .routes: PlannerView(model: model)
        case .journal: JournalView(model: model)
        case .profile: ProfileView(model: model)
        }
    }
    private var lockScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield").font(.system(size: 60)).foregroundStyle(Palette.forest)
            Text("Your journal is private").font(.title.bold())
            Text("Unlock BreatheRoute using your device authentication.").multilineTextAlignment(.center)
            PrimaryButton(title: "Unlock", symbol: "faceid") {
                Task {
                    do { unlocked = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open your BreatheRoute journal") }
                    catch { unlockError = error.localizedDescription }
                }
            }
            if let unlockError { Text(unlockError).font(.footnote).foregroundStyle(.secondary) }
        }.padding(32)
    }
}

struct WelcomeView: View {
    @Bindable var model: AppModel
    var finish: () -> Void
    var body: some View {
        Page {
            HStack { Label("BreatheRoute", systemImage: "leaf.fill").font(.headline); Spacer(); Text("01 / START").font(.caption.monospaced()).foregroundStyle(.secondary) }.padding(.top, 30)
            ZStack {
                Circle().fill(Palette.forest.opacity(0.08)).frame(width: 230, height: 230)
                Circle().stroke(Palette.forest.opacity(0.18), lineWidth: 1).frame(width: 180, height: 180)
                Image(systemName: "figure.walk").font(.system(size: 90, weight: .light)).foregroundStyle(Palette.forest)
                Image(systemName: "leaf.fill").font(.largeTitle).foregroundStyle(Palette.forest).offset(x: 75, y: -60)
            }.frame(maxWidth: .infinity).accessibilityHidden(true)
            Text("A little more awareness.\nEvery step.").font(.largeTitle.bold())
            Text("Compare walking routes, understand estimated pollution exposure, and keep a personal journal.").font(.title3).foregroundStyle(.secondary)
            Surface {
                TextField("What should we call you?", text: $model.name).textContentType(.givenName).font(.headline)
                Divider()
                Picker("Usual walking pace", selection: $model.intensity) { ForEach(WalkingIntensity.allCases) { Text($0.rawValue).tag($0) } }
                InfoNote(text: "Location and Apple Health are optional. We’ll ask only when you use them.")
            }
            PrimaryButton(title: "Start exploring") { finish() }
            Text("Exposure estimates are for awareness, not diagnosis or a guarantee of safety. You can begin locally without an account.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}
