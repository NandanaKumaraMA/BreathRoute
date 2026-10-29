import SwiftUI
import LocalAuthentication

struct ProfileView: View {
    @Bindable var model: AppModel
    @AppStorage("biometricLock") private var biometricLock = false
    @AppStorage("dailyReminder") private var reminder = false
    @State private var reminderDraft = false
    @State private var time = Date()
    @State private var status: String?
    @State private var working = false
    @State private var showAccount = false
    @State private var showHealthSection = false

    var body: some View {
        Page {
            PageHeader(title: "Your space.", subtitle: "Preferences & privacy", symbol: "slider.horizontal.3")
            profileAndPreferencesCard
            AccountCard(model: model) { showAccount = true }
            if model.account.identity != nil { CloudJournalCard(model: model) }
            remindersAndPrivacyCard
            healthAndMotionDisclosure
            methodologyCard
        }
        .adaptiveNavigationBar()
        .sheet(isPresented: $showAccount) { AccountAccessView(model: model) }
        .onAppear {
            reminderDraft = reminder
            if let saved = UserDefaults.standard.object(forKey: "reminderTime") as? Double { time = Date(timeIntervalSince1970: saved) }
        }
        .alert("BreatheRoute", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) {
            Button("OK") { status = nil }
        } message: { Text(status ?? "") }
    }

    private var profileAndPreferencesCard: some View {
        Surface {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(Palette.lime).frame(width: 56, height: 56)
                    Text(model.name.first.map { String($0).uppercased() } ?? "B")
                        .font(.system(.title2, design: .serif)).foregroundStyle(Palette.deep)
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Your display name", text: $model.name).font(.headline).textContentType(.givenName)
                    StatusPill(title: model.account.identity == nil ? "Local profile" : "Account profile", symbol: "lock")
                }
            }
            Divider()
            HStack {
                settingsIcon("figure.walk", tint: Palette.forest)
                Picker("Usual walking pace", selection: $model.intensity) {
                    ForEach(WalkingIntensity.allCases) { Text($0.rawValue).tag($0) }
                }.font(.subheadline)
            }.disabled(model.activeRoute != nil || !model.routes.isEmpty)
        }
    }

    private var remindersAndPrivacyCard: some View {
        Surface {
            SectionHeading(title: "Privacy & reminders")
            HStack(spacing: 14) {
                settingsIcon("faceid", tint: Palette.forest)
                Toggle(isOn: Binding(get: { biometricLock }, set: setLock)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protect your journal").font(.subheadline.weight(.semibold))
                        Text("Face ID, Touch ID or passcode").font(.caption).foregroundStyle(Palette.muted)
                    }
                }
            }
            Divider()
            HStack(spacing: 14) {
                settingsIcon("bell.badge", tint: Palette.forest)
                Toggle(isOn: $reminderDraft) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily check-in reminder").font(.subheadline.weight(.semibold))
                        Text(reminder ? "Enabled on this device" : "Off").font(.caption).foregroundStyle(Palette.muted)
                    }
                }
            }
            if reminderDraft {
                DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute).font(.subheadline)
            }
            Button(working ? "Saving…" : "Save reminder preference") { saveReminder() }
                .font(.caption.weight(.semibold)).frame(minHeight: 44).disabled(working)
        }
    }

    private var healthAndMotionDisclosure: some View {
        Surface {
            DisclosureGroup("Health & motion sensors", isExpanded: $showHealthSection) {
                VStack(alignment: .leading, spacing: 16) {
                    MotionSettingsCard(model: model)
                    HealthActivityCard(health: model.health)
                    HealthVitalsCard(health: model.health)
                }.padding(.top, 12)
            }.font(.headline).foregroundStyle(Palette.ink)
        }
    }

    private var methodologyCard: some View {
        Surface {
            DisclosureGroup("Understand your estimate & attribution") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dose combines PM2.5 (µg/m³), assumed ventilation (Easy 15, Brisk 25, Fast 35 L/min) and time. Missing or stale samples reduce coverage. Walks are recorded while the app is open.")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Link("OpenWeather Air Pollution API", destination: URL(string: "https://openweathermap.org/api/air-pollution")!).font(.caption)
                    Link("Geoapify routing & OpenStreetMap", destination: URL(string: "https://www.geoapify.com/routing-api/")!).font(.caption)
                    Link("Optional openrouteservice", destination: URL(string: "https://openrouteservice.org/dev/")!).font(.caption)
                }.padding(.top, 8)
            }.font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
        }
    }

    private func settingsIcon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol).font(.subheadline).foregroundStyle(tint)
            .frame(width: 34, height: 34).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    private func setLock(_ enabled: Bool) {
        Task {
            do {
                if try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: enabled ? "Protect your BreatheRoute journal" : "Turn off the journal lock") {
                    biometricLock = enabled
                }
            } catch { status = error.localizedDescription }
        }
    }

    private func saveReminder() {
        working = true
        Task {
            defer { working = false }
            do {
                let enabled = try await ReminderService().setDaily(enabled: reminderDraft, at: time)
                status = enabled ? "Daily reminder scheduled." : (reminderDraft ? "Notifications are unavailable in Settings." : "Daily reminder removed.")
                reminder = enabled; reminderDraft = enabled
                UserDefaults.standard.set(time.timeIntervalSince1970, forKey: "reminderTime")
            } catch { status = error.localizedDescription }
        }
    }
}
