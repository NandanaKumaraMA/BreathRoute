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
                    }.navigationTitle("BreatheRoute").navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
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
        .background(Palette.canvas)
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
    @State private var stage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Page {
            HStack(spacing: 10) { BrandMark(); Text("breathe route").font(.system(.headline, design: .rounded)).foregroundStyle(Palette.ink); Spacer(); Eyebrow(text: "0\(stage + 1) / 02") }.padding(.top, 12)
            if stage == 0 {
                ZStack(alignment: .bottomLeading) {
                    RouteArtwork()
                    Text("A little more perspective.").font(.caption.weight(.semibold)).foregroundStyle(Palette.deep).padding(.horizontal, 13).padding(.vertical, 9).background(.white.opacity(0.92), in: Capsule()).padding(18)
                }.frame(height: 235).clipShape(RoundedRectangle(cornerRadius: 30))
                VStack(alignment: .leading, spacing: 15) {
                    Eyebrow(text: "Meet your walking companion")
                    Text("Every step,\na little wiser.").font(.system(.largeTitle, design: .serif)).foregroundStyle(Palette.ink)
                    Text("See your walk from a new perspective. Compare routes, understand estimated exposure, and make space for a daily check-in.").font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4)
                }
                HStack(alignment: .top, spacing: 20) {
                    welcomeFeature("map", title: "Explore", text: "Routes with context")
                    welcomeFeature("wind", title: "Understand", text: "Estimated exposure")
                    welcomeFeature("book.closed", title: "Reflect", text: "Your private journal")
                }.padding(.vertical, 12)
            } else {
                PageHeader(title: "Make it your own.", subtitle: "A quick introduction", symbol: "person.crop.circle")
                Surface { Eyebrow(text: "What should we call you?"); TextField("Your first name (optional)", text: $model.name).font(.title3).textContentType(.givenName).padding(.vertical, 8) }
                Surface {
                    SectionHeading(title: "Your usual walking pace")
                    ForEach(WalkingIntensity.allCases) { intensity in
                        Button { model.intensity = intensity } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "figure.walk").font(.headline).frame(width: 40, height: 40).background(Palette.forest.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 4) { Text(intensity.rawValue).font(.subheadline.weight(.semibold)); Text(intensity == .easy ? "Take your time" : intensity == .brisk ? "A steady stride" : "A quicker pace").font(.caption).foregroundStyle(Palette.muted) }
                                Spacer(); Image(systemName: model.intensity == intensity ? "checkmark.circle.fill" : "circle")
                            }.foregroundStyle(Palette.forest).padding(.vertical, 5)
                        }.buttonStyle(.plain).accessibilityAddTraits(model.intensity == intensity ? .isSelected : [])
                    }
                }
                Surface { Label("Your choice. Your privacy.", systemImage: "lock").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink); Text("Location and Apple Health are optional. We’ll ask when you need them. Your journal starts locally on this device.").font(.caption).foregroundStyle(Palette.muted) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                PrimaryButton(title: stage == 0 ? "Get started" : "Start exploring") {
                    if stage == 0 { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { stage = 1 } } else { finish() }
                }
                Text("Exposure awareness · not a medical assessment").font(.caption2).foregroundStyle(Palette.muted)
            }.padding(22).background(Palette.canvas)
        }
    }
    private func welcomeFeature(_ symbol: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Image(systemName: symbol).font(.title3).foregroundStyle(Palette.forest); Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.ink); Text(text).font(.caption2).foregroundStyle(Palette.muted) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
