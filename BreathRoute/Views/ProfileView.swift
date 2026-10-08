import SwiftUI
import LocalAuthentication

struct ProfileView: View {
    @Bindable var model: AppModel
    @AppStorage("biometricLock") private var biometricLock = false
    @AppStorage("dailyReminder") private var reminder = false
    @State private var reminderDraft = false
    @State private var time = Date()
    @State private var key = ""
    @State private var status: String?
    @State private var working = false
    @State private var healthWorking = false
    var body: some View {
        Page {
            PageHeader(title: "Your space.", subtitle: "Preferences & privacy", symbol: "slider.horizontal.3")
            profileCard
            SectionHeading(title: "Your preferences")
            Surface {
                VStack(alignment: .leading, spacing: 8) { Text("Display name").font(.caption).foregroundStyle(Palette.muted); TextField("What should we call you?", text: $model.name).font(.headline).textContentType(.givenName) }
                Divider()
                HStack { settingsIcon("figure.walk", tint: Palette.forest); Picker("Usual walking pace", selection: $model.intensity) { ForEach(WalkingIntensity.allCases) { Text($0.rawValue).tag($0) } }.font(.subheadline) }.disabled(model.activeRoute != nil || !model.routes.isEmpty)
            }
            SectionHeading(title: "Connected to you")
            Surface {
                HStack(alignment: .top, spacing: 14) {
                    settingsIcon("heart.fill", tint: Color(hex: 0xB95763))
                    VStack(alignment: .leading, spacing: 6) { Text("Apple Health").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink); Text("Optional · recent health context").font(.caption).foregroundStyle(Palette.muted) }
                    Spacer()
                    if healthWorking { ProgressView() } else { Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Palette.muted) }
                }
                Text(model.health.summary).font(.caption).foregroundStyle(Palette.muted)
                if let hr = model.health.heartRate { LabeledContent("Recent heart rate", value: "\(Int(hr)) bpm").font(.subheadline) }
                if let rr = model.health.respiratoryRate { LabeledContent("Recent respiratory rate", value: "\(Int(rr)) breaths/min").font(.subheadline) }
                Button("Read recent samples") {
                    healthWorking = true
                    Task { await model.health.connect(); healthWorking = false }
                }.font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(healthWorking)
                DisclosureGroup("How health data is used") { Text("Samples stay on this device. Heart rate and respiratory rate alone do not measure inhaled air volume. Exposure uses your labelled walking-intensity assumption.").font(.caption).foregroundStyle(Palette.muted).padding(.top, 8) }.font(.caption)
            }
            Surface {
                HStack(spacing: 14) { settingsIcon("bell.badge", tint: Palette.forest); Toggle(isOn: $reminderDraft) { VStack(alignment: .leading, spacing: 5) { Text("A daily check-in").font(.subheadline.weight(.semibold)); Text("A quiet reminder to reflect on your day").font(.caption).foregroundStyle(Palette.muted) } } }
                if reminderDraft { DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute).font(.subheadline) }
                Button(working ? "Saving…" : "Save reminder preference") { saveReminder() }.font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(working)
                Text("Scheduled on your device. \(reminder ? "Daily reminder enabled." : "Daily reminder off.")").font(.caption2).foregroundStyle(Palette.muted)
            }
            SectionHeading(title: "Private by design")
            Surface {
                HStack(spacing: 14) {
                    settingsIcon("faceid", tint: Palette.forest)
                    Toggle(isOn: Binding(get: { biometricLock }, set: setLock)) { VStack(alignment: .leading, spacing: 5) { Text("Protect your journal").font(.subheadline.weight(.semibold)); Text("Face ID, Touch ID or device passcode").font(.caption).foregroundStyle(Palette.muted) } }
                }
                Divider()
                HStack(alignment: .top, spacing: 14) { settingsIcon("accessibility", tint: Palette.forest); VStack(alignment: .leading, spacing: 6) { Text("Accessible, your way").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink); Text("Follows your text size and VoiceOver settings. Use the speaker in Explore for a spoken route summary.").font(.caption).foregroundStyle(Palette.muted) } }
            }
            Surface {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 16) {
                        SecureField("OpenWeather API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().font(.subheadline).padding(14).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 13))
                        Button("Save key on this device") {
                            do { try KeyStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), key: "openweather"); key = ""; status = "API key saved in Keychain. Refresh Today or compare a route to request data." }
                            catch { status = "Could not save the API key." }
                        }.font(.subheadline.weight(.semibold)).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("The key is stored in device Keychain. Requests send the selected coordinates to OpenWeather.").font(.caption).foregroundStyle(Palette.muted)
                        Link("OpenWeather API & attribution", destination: URL(string: "https://openweathermap.org/api/air-pollution")!).font(.caption)
                    }.padding(.top, 16)
                } label: {
                    HStack(spacing: 14) { settingsIcon("cloud.sun", tint: Palette.forest); VStack(alignment: .leading, spacing: 6) { Text("Air-quality connection").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink); Text(KeyStore.read("openweather").isEmpty ? "Add OpenWeather to see live data" : "API key saved on this device").font(.caption).foregroundStyle(Palette.muted) } }
                }
            }
            Surface {
                DisclosureGroup("Understand your estimate") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Dose combines PM2.5 concentration, assumed ventilation and time. Easy, Brisk and Fast assume 15, 25 and 35 L/min. These are unvalidated coursework assumptions, not personalised measurements.")
                        Text("OpenWeather AQI uses a 1–5 scale. Missing or stale samples reduce coverage. Nearby routes may share the same modelled pollution values.")
                        Text("Walks are recorded while the app is open. Background gaps are excluded. BreatheRoute does not detect emergencies.")
                    }.font(.caption).foregroundStyle(Palette.muted).padding(.top, 12)
                }.font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
            }
            HStack(spacing: 8) { BrandMark(size: 24); Text("breathe route").font(.caption.weight(.semibold)); Spacer(); Text("ON-DEVICE JOURNAL").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1) }.foregroundStyle(Palette.muted).padding(.vertical, 8)
        }
        .adaptiveNavigationBar()
        .onAppear { reminderDraft = reminder; if let saved = UserDefaults.standard.object(forKey: "reminderTime") as? Double { time = Date(timeIntervalSince1970: saved) } }
        .alert("BreatheRoute", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) { Button("OK") { status = nil } } message: { Text(status ?? "") }
    }
    private var profileCard: some View {
        HStack(spacing: 18) {
            ZStack { Circle().fill(Palette.lime).frame(width: 66, height: 66); Text(model.name.first.map { String($0).uppercased() } ?? "B").font(.system(.title, design: .serif)).foregroundStyle(Palette.deep) }
            VStack(alignment: .leading, spacing: 8) { Text(model.name.isEmpty ? "Make yourself at home" : model.name).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink); StatusPill(title: "Local profile", symbol: "lock") }
            Spacer(minLength: 0)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 25)).overlay(RoundedRectangle(cornerRadius: 25).stroke(Palette.line, lineWidth: 0.7))
    }
    private func settingsIcon(_ symbol: String, tint: Color) -> some View { Image(systemName: symbol).font(.subheadline).foregroundStyle(tint).frame(width: 38, height: 38).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true) }
    private func setLock(_ enabled: Bool) {
        Task {
            do { if try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: enabled ? "Protect your BreatheRoute journal" : "Turn off the journal lock") { biometricLock = enabled } }
            catch { status = error.localizedDescription }
        }
    }
    private func saveReminder() {
        working = true
        Task {
            defer { working = false }
            do {
                let enabled = try await ReminderService().setDaily(enabled: reminderDraft, at: time)
                status = enabled ? "Daily reminder scheduled." : (reminderDraft ? "Notifications are unavailable. You can enable them in device Settings." : "Daily reminder removed.")
                reminder = enabled; reminderDraft = enabled
                UserDefaults.standard.set(time.timeIntervalSince1970, forKey: "reminderTime")
            } catch { status = error.localizedDescription }
        }
    }
}
