import UIKit
import FirebaseCore
import UserNotifications

@MainActor
enum FirebaseBootstrap {
    private(set) static var app: FirebaseApp?
    private(set) static var environment = AccountEnvironment.firebase
    private(set) static var setupMessage = "Cloud accounts have not been configured for this build. Your local journal remains available."
    static var googleClientID: String? { environment == .firebase ? app?.options.clientID : nil }
    static var googleReady: Bool {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return GoogleAccountConfiguration.isReady(clientID: googleClientID, registeredSchemes: schemes)
    }
    static func configure() {
        guard app == nil else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--firebase-auth-emulator") {
            let options = FirebaseOptions(googleAppID: "1:1234567890:ios:abcdef0123456789", gcmSenderID: "1234567890")
            options.apiKey = "AIza" + String(repeating: "0", count: 35); options.projectID = "demo-breatheroute"
            options.bundleID = Bundle.main.bundleIdentifier ?? "MANKumara.BreathRoute"
            FirebaseApp.configure(name: "BreatheRouteEmulator", options: options)
            app = FirebaseApp.app(name: "BreatheRouteEmulator"); environment = .emulator
            return
        }
        #endif
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path),
              options.bundleID == Bundle.main.bundleIdentifier,
              let project = options.projectID, !project.isEmpty,
              let key = options.apiKey, !key.isEmpty, !options.googleAppID.isEmpty else {
            setupMessage = "Cloud accounts are unavailable in this build. The Firebase configuration is missing or does not match this app. Continue with your local journal."
            return
        }
        FirebaseApp.configure(options: options); app = FirebaseApp.app()
    }
}

final class BreatheRouteAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseBootstrap.configure()
        RemotePushService.shared.configure()
        UNUserNotificationCenter.current().delegate = self
        return true
    }
}


extension BreatheRouteAppDelegate: UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        RemotePushService.shared.didRegisterAPNs(deviceToken)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        RemotePushService.shared.didFailAPNs()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let remote = notification.request.trigger is UNPushNotificationTrigger
        let fields = notification.request.content.userInfo.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        let envelope = PushEnvelope(fields: fields)
        let freeAlert = FreeAlertEnvelope(fields: fields)
        Task { @MainActor in
            let allowed: Bool
            if let freeAlert { allowed = FreeNotificationService.shared.received(freeAlert, remote: remote) }
            else { allowed = !remote || envelope.map { RemotePushService.shared.received($0) } == true }
            completionHandler(allowed ? [.banner, .list, .sound] : [])
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let fields = response.notification.request.content.userInfo.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        let envelope = PushEnvelope(fields: fields)
        let freeAlert = FreeAlertEnvelope(fields: fields)
        let remote = response.notification.request.trigger is UNPushNotificationTrigger
        Task { @MainActor in
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                if let freeAlert { FreeNotificationService.shared.open(freeAlert, remote: remote) }
                else if let envelope { RemotePushService.shared.open(envelope) }
            }
            completionHandler()
        }
    }
}
