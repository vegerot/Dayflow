//
//  AppDelegate.swift
//  Dayflow
//
//  Created by Jerry Liu on 4/26/25.
//

import AppKit
import ServiceManagement
import ScreenCaptureKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var recorder : ScreenRecorder!

    func applicationDidFinishLaunching(_ note: Notification) {
        statusBar = StatusBarController()   // safe: AppKit is ready, main thread
        
        // Check if we've passed the screen recording permission step
        let onboardingStep = UserDefaults.standard.integer(forKey: "onboardingStep")
        let didOnboard = UserDefaults.standard.bool(forKey: "didOnboard")
        
        // Initialize recorder but control when it starts
        recorder = ScreenRecorder(autoStart: false)
        
        // Only attempt to start recording if we're past the screen step or fully onboarded
        // Steps: 0=welcome, 1=howItWorks, 2=screen, 3=llmSelection, 4=llmSetup, 5=done
        if didOnboard || onboardingStep > 2 {
            // Try to start recording, but handle permission failures gracefully
            Task {
                do {
                    // Check if we have permission by trying to access content
                    _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    // Permission granted, start recording
                    await MainActor.run {
                        AppState.shared.isRecording = true
                    }
                } catch {
                    // No permission or error - don't start recording
                    // User will need to grant permission in onboarding
                    await MainActor.run {
                        AppState.shared.isRecording = false
                    }
                    print("Screen recording permission not granted, skipping auto-start")
                }
            }
        } else {
            // Still in early onboarding, don't attempt recording
            AppState.shared.isRecording = false
        }
        
        try? SMAppService.mainApp.register()// autostart at login
        
        // Start the Gemini analysis background job
        setupGeminiAnalysis()

        // Start inactivity monitoring for idle reset
        InactivityMonitor.shared.start()
    }
    
    // Start Gemini analysis as a background task
    private func setupGeminiAnalysis() {
        // Perform after a short delay to ensure other initialization completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            AnalysisManager.shared.startAnalysisJob()
            print("AppDelegate: Gemini analysis job started")
        }
    }
}
