import UIKit
import FirebaseCore

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
        FirebaseBootstrap.configure(); return true
    }
}
