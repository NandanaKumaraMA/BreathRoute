import SwiftUI
import UIKit

struct RemoteNotificationsCard: View {
    @Bindable var service: RemotePushService
    var body: some View {
        Surface {
            RemoteNotificationControls(service: service)
        }
    }
}

struct RemoteNotificationControls: View {
    @Bindable var service: RemotePushService
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Cloud notifications")
            Text(service.automaticJournalAlerts ? "Get an alert when your private cloud journal changes." : "Receive service updates on this device.").font(.subheadline).foregroundStyle(Palette.ink)
            Text("Enabling shares a device delivery token with Firebase. Notifications contain a general update, without symptoms, health readings or routes.")
                .font(.caption).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                StatusPill(title: service.connected ? "Connected" : (service.enabled ? "Not connected" : "Off"), symbol: service.connected ? "bell.badge.fill" : "bell")
                Spacer()
                if service.working { ProgressView().accessibilityLabel("Updating cloud notifications") }
            }
            Text(service.status).font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("push-status")
            if service.signedIn && service.available {
                if service.enabled {
                    if !service.connected {
                        Button("Retry connection", systemImage: "arrow.clockwise") { Task { await service.reconnect() } }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(service.working)
                    }
                    if service.connected && service.supportsRemoteTest {
                        Button("Send a test notification", systemImage: "paperplane") { Task { await service.sendConnectionTest() } }
                            .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(service.working)
                    }
                    Button("Turn off cloud notifications", role: .destructive) { Task { await service.disable() } }
                        .font(.subheadline).frame(minHeight: 44).disabled(service.working)
                } else {
                    PrimaryButton(title: "Enable cloud notifications", symbol: "bell.badge") { Task { await service.enable() } }.disabled(service.working)
                }
            }
            if service.signedIn && service.available {
                Link("Notification settings", destination: URL(string: UIApplication.openNotificationSettingsURLString)!)
                    .font(.caption.weight(.semibold)).frame(minHeight: 44)
            }
            if let date = service.lastReceived { Text("Last received \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(Palette.forest) }
            Text("APNs delivery needs a configured Apple Developer team. Local alerts and live in-app updates work separately.").font(.caption2).foregroundStyle(Palette.muted)
        }
    }
}
