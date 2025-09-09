//
//  DayflowApp.swift
//  Dayflow
//
//  Created by Jerry Liu on 4/20/25.
//

import SwiftUI
import Sparkle

// MARK: - Root View with Transparent UI
struct AppRootView: View {
    var body: some View {
        MainView()
            .environmentObject(AppState.shared)
    }
}

@main
struct DayflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("didOnboard") private var didOnboard = false
    @AppStorage("useBlankUI") private var useBlankUI = false
    @State private var showVideoLaunch = true
    @State private var contentOpacity = 0.0
    @State private var contentScale = 0.98
    
    init() {
        // Comment out for production - only use for testing onboarding
        // UserDefaults.standard.set(false, forKey: "didOnboard")
    }
    
    // Sparkle updater manager
    private let updaterManager = UpdaterManager.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main app UI or onboarding with entrance animation
                Group {
                    if didOnboard {
                        // Show UI after onboarding
                        AppRootView()
                            .environmentObject(updaterManager)
                    } else {
                        OnboardingFlow()
                            .environmentObject(AppState.shared)
                            .environmentObject(updaterManager)
                    }
                }
                .opacity(contentOpacity)
                .scaleEffect(contentScale)
                .animation(.easeOut(duration: 0.3).delay(0.15), value: contentOpacity)
                .animation(.easeOut(duration: 0.3).delay(0.15), value: contentScale)

                // Video overlay on top with scale + opacity exit
                if showVideoLaunch {
                    VideoLaunchView()
                        .onVideoComplete {
                            // Overlapping animations for smooth handoff
                            withAnimation(.easeOut(duration: 0.25)) {
                                // Start revealing content while video fades
                                contentOpacity = 1.0
                                contentScale = 1.0
                            }
                            
                            // Slightly delayed video exit for overlap
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.easeIn(duration: 0.2)) {
                                    showVideoLaunch = false
                                }
                            }
                        }
                        .opacity(showVideoLaunch ? 1 : 0)
                        .scaleEffect(showVideoLaunch ? 1 : 1.02)
                        .animation(.easeIn(duration: 0.2), value: showVideoLaunch)
                }
            }
            // Inline background behind the main app UI only
            .background {
                if didOnboard {
                    Image("MainUIBackground")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(minWidth: 900, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Remove the "New Window" command if you want a single window app
            CommandGroup(replacing: .newItem) { }
            
            // Add custom menu items after the app info section
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Reset Onboarding") {
                    // Reset the onboarding flag
                    UserDefaults.standard.set(false, forKey: "didOnboard")
                    // Reset the saved onboarding step to start from beginning
                    UserDefaults.standard.set(0, forKey: "onboardingStep")
                    // Reset the selected LLM provider to default
                    UserDefaults.standard.set("gemini", forKey: "selectedLLMProvider")
                    // Force quit and restart the app to show onboarding
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])
            }
            
            // Add Sparkle's update menu item
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterManager.checkForUpdates(showUI: true)
                }
            }
        }
        .defaultSize(width: 1200, height: 800)
    }
}
