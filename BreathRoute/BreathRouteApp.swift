//
//  BreathRouteApp.swift
//  BreathRoute
//
//  Created by Nandana on 2026-10-07.
//

import SwiftUI
import GoogleSignIn

@main
struct BreathRouteApp: App {
    @UIApplicationDelegateAdaptor(BreatheRouteAppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
        }
    }
}
