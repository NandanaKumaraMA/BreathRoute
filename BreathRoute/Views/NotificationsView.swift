import SwiftUI
import UIKit

struct NotificationsCard: View {
    @Bindable var service: FreeNotificationService
    let remote: RemotePushService
    @State private var showChecks = false
    var body: some View {
        Surface {
            SectionHeading(title: "Notifications")
            if service.signedIn {
                Toggle("Live journal updates", isOn: Binding(get: { service.enabled }, set: service.setEnabled))
                    .font(.subheadline.weight(.semibold)).accessibilityIdentifier("live-journal-toggle")
                Text("Receive changes while BreatheRoute is open. Choose Sync now in Journal to apply them.")
                    .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if service.enabled {
                    StatusPill(title: service.connected ? "Listening" : "Waiting", symbol: service.connected ? "antenna.radiowaves.left.and.right" : "wifi")
                    Text(service.status).font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("live-journal-status")
                    Toggle("Show notification banners", isOn: Binding(get: { service.banners }, set: { value in Task { await service.setBanners(value) } }))
                        .font(.subheadline).disabled(service.checking)
                    if !service.connected { Button("Reconnect updates", systemImage: "arrow.clockwise") { service.retry() }.frame(minHeight: 44) }
                }
                if let last = service.lastUpdate { Text("Cloud change received \(last.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(Palette.forest) }
            } else {
                Text("Sign in to receive journal updates while the app is open.").font(.subheadline).foregroundStyle(Palette.muted)
            }
            Button("Check notifications", systemImage: "bell.badge") { showChecks = true }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44).accessibilityIdentifier("notification-checks")
            Text("Reminders and walk area alerts work on this device. Live journal updates pause when the app closes or locks.")
                .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Remote delivery connection") { RemoteNotificationControls(service: remote).padding(.top, 10) }
                .font(.subheadline)
        }
        .sheet(isPresented: $showChecks) { NotificationChecksView(service: service) }
        .onChange(of: service.navigationRequest) { _, _ in showChecks = false }
    }
}

struct NotificationChecksView: View {
    @Bindable var service: FreeNotificationService
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Page {
                Surface {
                    SectionHeading(title: "Local alert")
                    Text("Schedule an alert in three seconds. Try leaving the app, then tap the alert to return to You.")
                        .font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Send local test alert", symbol: "bell") { Task { await service.sendLocalTest() } }
                        .disabled(service.checking).accessibilityIdentifier("send-local-test")
                }
                if FreeNotificationService.supportsSimulatorPush {
                    Surface {
                        SectionHeading(title: "Simulator push")
                        Text("Test a push payload and its tap action using Xcode Simulator. This check is simulated; it does not use APNs or internet delivery.")
                            .font(.subheadline).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        Button("Prepare simulator push", systemImage: "iphone.and.arrow.forward") { Task { await service.prepareSimulatorCheck() } }
                            .frame(minHeight: 44).disabled(service.checking).accessibilityIdentifier("prepare-simulator-push")
                        if service.simulatorPrepared {
                            Text("On your Mac, run the send-simulator-notification.py helper in this project's scripts folder.")
                                .font(.caption).foregroundStyle(Palette.muted).textSelection(.enabled)
                        }
                    }
                }
                if let status = service.checkStatus {
                    Surface { Text(status).font(.subheadline).foregroundStyle(Palette.ink).accessibilityIdentifier("notification-check-status") }
                }
                Link("Open notification settings", destination: URL(string: UIApplication.openNotificationSettingsURLString)!).frame(minHeight: 44)
            }
            .navigationTitle("Check notifications").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct CloudJournalUpdateBanner: View {
    let review: () -> Void
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath.icloud").accessibilityHidden(true)
            Text("Your cloud journal changed").font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Review", action: review).font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            Button("Dismiss update", systemImage: "xmark", action: dismiss).labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }
        .foregroundStyle(Palette.deep).padding(.horizontal, 16).background(Palette.lime)
        .accessibilityIdentifier("cloud-journal-update-banner")
    }
}
