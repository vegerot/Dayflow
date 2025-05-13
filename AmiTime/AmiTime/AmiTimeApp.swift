//
//  AmiTimeApp.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/20/25.
//

import SwiftUI

@main
struct AmiTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("didOnboard") private var didOnboard = false

    var body: some Scene {
        WindowGroup {
            if didOnboard {
                ContentView()
                    .environmentObject(AppState.shared)
            } else {
                OnboardingFlow()
                    .environmentObject(AppState.shared)
            }
        }
    }
}
