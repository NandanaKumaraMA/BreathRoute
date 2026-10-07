import SwiftUI
import LocalAuthentication

struct ProfileView: View {
    @Bindable var model: AppModel
    @AppStorage("biometricLock") private var biometricLock = false
    @AppStorage("dailyReminder") private var reminder = false
    @State private var time = Date()
    @State private var key = ""
    @State private var status: String?
    @State private var working = false
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 50)).foregroundStyle(Palette.forest)
                    VStack(alignment: .leading, spacing: 5) { Text(model.name.isEmpty ? "Your space" : model.name).font(.title2.bold()); Text("Local profile · on this device").font(.subheadline).foregroundStyle(.secondary) }
                }.padding(.vertical, 10)
                TextField("Display name", text: $model.name)
                Picker("Walking intensity", selection: $model.intensity) { ForEach(WalkingIntensity.allCases) { Text($0.rawValue).tag($0) } }.disabled(model.activeRoute != nil || !model.routes.isEmpty)
            } header: { Text("Profile") } footer: { Text("Cloud accounts and sync are not connected in this build.") }
            Section("Privacy and accessibility") {
                Toggle("Device authentication lock", isOn: Binding(get: { biometricLock }, set: { enabled in
                    Task {
                        do {
                            let success = try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: enabled ? "Protect your BreatheRoute journal" : "Turn off the journal lock")
                            if success { biometricLock = enabled }
                        } catch { status = error.localizedDescription }
                    }
                }))
                Text("Uses Face ID, Touch ID or your device passcode. This protects app access; it is not a cloud account login.").font(.caption).foregroundStyle(.secondary)
                Text("VoiceOver follows the reading order. Text follows your system size. Route summaries can be read aloud from Explore.").font(.subheadline)
            }
            Section("Apple Health · optional") {
                Text(model.health.summary).font(.subheadline)
                if let hr = model.health.heartRate { LabeledContent("Recent heart rate", value: "\(Int(hr)) bpm") }
                if let rr = model.health.respiratoryRate { LabeledContent("Recent respiratory rate", value: "\(Int(rr)) breaths/min") }
                Button("Read recent health samples") { Task { await model.health.connect() } }
                Text("Health data stays on-device. Heart rate and respiratory rate alone do not measure inhaled air volume; this build uses labelled intensity assumptions for exposure.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Daily check-in") {
                Toggle("Daily reminder", isOn: $reminder)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                Button("Save reminder") {
                    working = true
                    Task {
                        defer { working = false }
                        do {
                            let enabled = try await ReminderService().setDaily(enabled: reminder, at: time)
                            status = enabled ? "Daily reminder scheduled." : (reminder ? "Notifications are unavailable. Enable them in device Settings." : "Daily reminder removed.")
                            reminder = enabled
                            UserDefaults.standard.set(time.timeIntervalSince1970, forKey: "reminderTime")
                        } catch { status = error.localizedDescription }
                    }
                }.disabled(working)
                Text("This is a local reminder, not a remote push notification or emergency alert.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Data connection") {
                SecureField("OpenWeather API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save API key on this device") {
                    do { try KeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), key: "openweather"); key = ""; status = "API key saved in Keychain. Go to Today and refresh, or search a route." }
                    catch { status = "Could not save the key." }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text(KeyStore.read("openweather").isEmpty ? "Not configured. Demo mode works without credentials." : "API key configured in Keychain.").font(.caption).foregroundStyle(.secondary)
                Link("OpenWeather attribution and API information", destination: URL(string: "https://openweathermap.org/api/air-pollution")!)
            }
            Section("Understand your estimate") {
                Text("Estimated dose combines PM2.5 concentration, an assumed breathing volume per minute, and time. Easy, Brisk and Fast currently assume 15, 25 and 35 L/min. These are unvalidated coursework assumptions, not personalised medical measurements.")
                Text("OpenWeather AQI uses its own 1–5 scale. It is not the US 0–500 AQI. Missing or stale samples are excluded and reduce coverage. Neighbouring routes may share the same modelled pollution values.")
                Text("Foreground tracking only. Locking the phone or leaving the app may create gaps, which are excluded. No emergency detection is provided.")
            }.font(.subheadline)
        }.navigationTitle("You")
            .onAppear { if let saved = UserDefaults.standard.object(forKey: "reminderTime") as? Double { time = Date(timeIntervalSince1970: saved) } }
            .alert("BreatheRoute", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) { Button("OK") { status = nil } } message: { Text(status ?? "") }
    }
}
