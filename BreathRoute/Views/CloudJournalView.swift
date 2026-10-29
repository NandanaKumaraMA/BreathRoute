import SwiftUI

struct CloudJournalCard: View {
    @Bindable var model: AppModel
    @State private var showConsent = false
    @State private var confirmPause = false
    var body: some View {
        Surface {
            SectionHeading(title: "Cloud journal", detail: "Manual sync")
            if model.account.identity == nil {
                Label("Your journal starts here", systemImage: "iphone").font(.headline).foregroundStyle(Palette.ink)
                Text("Sign in to optionally sync your profile, walking preferences, walk summaries and symptom notes across your devices.")
                    .font(.subheadline).foregroundStyle(Palette.muted)
            } else {
                StatusPill(title: model.cloudState.enabled ? "Sync enabled on this device" : "Stored on this device", symbol: model.cloudState.enabled ? "icloud" : "iphone")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], spacing: 16) { Metric(title: "Walk summaries", value: "\(model.trips.count)"); Metric(title: "Symptom notes", value: "\(model.symptoms.count)") }
                InfoNote(symbol: "location.slash", text: "GPS paths, phone activity and Apple Health records stay on their original device.")
                if model.cloudState.enabled && model.cloudState.consentVersion == 2 {
                    if let date = model.cloudState.lastSyncedAt {
                        Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened)).").font(.caption).foregroundStyle(Palette.muted)
                    } else { Text("Not synced yet.").font(.caption).foregroundStyle(Palette.muted) }
                    if model.cloudHasLocalChanges { InfoNote(symbol: "arrow.triangle.2.circlepath", text: "Local changes are ready to sync, including journal deletions.") }
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath.icloud") { Task { await model.syncJournal() } }
                        .font(.headline).frame(minHeight: 44).disabled(!model.canSyncJournal)
                    Button("Pause sync on this device") { confirmPause = true }.font(.caption).frame(minHeight: 44).disabled(!model.canSyncJournal)
                    Text("Sync runs when you tap Sync now. Offline changes remain on your device until you retry.")
                        .font(.caption).foregroundStyle(Palette.muted)
                } else {
                    Text("Choose whether to store your display name, walking preferences, walk summaries and symptom notes in your private Firebase account. Signing in does not upload them.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    Button(model.cloudState.enabled ? "Review expanded cloud sync" : "Set up cloud sync", systemImage: "icloud.and.arrow.up") { showConsent = true }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(!model.canSyncJournal)
                }
                if !model.journalReadableForSync { InfoNote(text: "Sync is disabled because this journal or its saved sync state could not be read. Existing records have not been reset.") }
                else if !model.canSyncJournal && !model.cloud.working {
                    InfoNote(text: "Finish any unfinished walk and wait for ongoing requests before syncing.")
                }
                if model.syncInFlight { ProgressView("Syncing private journal…") }
                if let message = model.cloud.message { InfoNote(text: message).accessibilityIdentifier("cloud-sync-result") }
            }
        }
        .sheet(isPresented: $showConsent) { CloudSyncConsentView(model: model) }
        .confirmationDialog("Pause cloud sync?", isPresented: $confirmPause, titleVisibility: .visible) {
            Button("Pause sync") { model.setCloudSyncEnabled(false) }
        } message: { Text("Your local journal stays available. Existing cloud data is kept, and other devices keep their own sync setting.") }
    }
}

private struct CloudSyncConsentView: View {
    @Bindable var model: AppModel
    @State private var consent = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Page {
                PageHeader(title: "Keep your journal\nwithin reach.", subtitle: "Optional cloud sync", symbol: "icloud")
                Surface {
                    Label("What will be stored", systemImage: "checklist").font(.headline).foregroundStyle(Palette.ink)
                    Text("Your chosen display name, walking pace and extra-time budget; walk dates, destination labels, distance, duration, estimated exposure and coverage; symptom types, severity, note text and linked walk IDs.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    InfoNote(symbol: "lock", text: "These records are sent to this app's Firebase project under your signed-in account. Symptom notes may contain sensitive personal information.")
                }
                Surface {
                    Label("What stays on your iPhone", systemImage: "iphone").font(.headline).foregroundStyle(Palette.ink)
                    Text("Raw GPS paths, sampled map coordinates, phone activity metrics, Apple Health records, API keys and unfinished walks are excluded.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    InfoNote(text: "A walk restored on another device has its summary, without its original GPS path or activity records.")
                }
                Surface {
                    Text("You control each sync").font(.headline).foregroundStyle(Palette.ink)
                    Text("Enable this setting, then tap Sync now to upload and restore records. Deletions are shared on the next sync. When two versions conflict, both edits are kept. Pausing does not erase an existing cloud copy.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                    InfoNote(text: "This version supports up to 500 journal entries and 350 KB per account. Your local journal can remain larger; it will not be truncated.")
                    Toggle("I agree to sync this profile, preferences, walk summaries and symptom notes to my account", isOn: $consent).font(.subheadline)
                }
                PrimaryButton(title: "Enable manual sync", symbol: "icloud") {
                    model.setCloudSyncEnabled(true)
                    if model.cloudState.enabled { dismiss() }
                }.disabled(!consent || !model.canSyncJournal)
            }
            .navigationTitle("Cloud journal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
