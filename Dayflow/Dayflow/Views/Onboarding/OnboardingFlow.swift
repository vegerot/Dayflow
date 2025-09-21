//
//  OnboardingFlow.swift
//  Dayflow
//
//  Created by Jerry Liu on 4/26/25.
//

import SwiftUI
import ScreenCaptureKit

// Window manager removed - no longer needed!

struct OnboardingFlow: View {
    @AppStorage("onboardingStep") private var savedStepRawValue = 0
    @State private var step: Step = .welcome
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var timelineOffset: CGFloat = 300 // Start below screen
    @State private var textOpacity: Double = 0
    @AppStorage("selectedLLMProvider") private var selectedProvider: String = "gemini" // Persist across sessions
    @EnvironmentObject private var categoryStore: CategoryStore
    private let fullText = "Your day has a story. Let's uncover it together."
    
    @ViewBuilder
    var body: some View {
        ZStack {
            // NO NESTING! Just render the appropriate view directly - NO GROUP!
            switch step {
            case .welcome:
                WelcomeView(
                    fullText: fullText,
                    textOpacity: $textOpacity,
                    timelineOffset: $timelineOffset,
                    onStart: advance
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    restoreSavedStep()
                    // screen + start event
                    AnalyticsService.shared.screen("onboarding_welcome")
                    if !UserDefaults.standard.bool(forKey: "onboardingStarted") {
                        AnalyticsService.shared.capture("onboarding_started")
                        UserDefaults.standard.set(true, forKey: "onboardingStarted")
                        AnalyticsService.shared.setPersonProperties(["onboarding_status": "in_progress"]) 
                    }
                }
                
            case .howItWorks:
                HowItWorksView(
                    onBack: { 
                        step.prev()
                        savedStepRawValue = step.rawValue
                    },
                    onNext: { advance() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    restoreSavedStep()
                    AnalyticsService.shared.screen("onboarding_how_it_works")
                }
                
            case .screen:
                ScreenRecordingPermissionView(
                    onBack: { 
                        step.prev()
                        savedStepRawValue = step.rawValue
                    },
                    onNext: { advance() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    restoreSavedStep()
                    AnalyticsService.shared.screen("onboarding_screen_recording")
                }
                
            case .llmSelection:
                OnboardingLLMSelectionView(
                    onBack: { 
                        step.prev()
                        savedStepRawValue = step.rawValue
                    },
                    onNext: { provider in
                        selectedProvider = provider
                        AnalyticsService.shared.capture("llm_provider_selected", ["provider": provider])
                        AnalyticsService.shared.setPersonProperties(["current_llm_provider": provider])
                        step = .categories
                        savedStepRawValue = step.rawValue
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    restoreSavedStep()
                    AnalyticsService.shared.screen("onboarding_llm_selection")
                }
                
            case .categories:
                OnboardingCategorySetupView(
                    onNext: {
                        advance()
                    }
                )
                .environmentObject(categoryStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    restoreSavedStep()
                    AnalyticsService.shared.screen("onboarding_categories")
                }
                
            case .llmSetup:
                // COMPLETELY STANDALONE - no parent constraints!
                LLMProviderSetupView(
                    providerType: selectedProvider,
                    onBack: {
                        step.prev()
                        savedStepRawValue = step.rawValue
                    },
                    onComplete: {
                        advance()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    restoreSavedStep()
                    AnalyticsService.shared.screen("onboarding_llm_setup")
                }
                
            case .done:
                CompletionView(
                    onFinish: {
                        didOnboard = true
                        savedStepRawValue = 0
                        AnalyticsService.shared.capture("onboarding_completed")
                        AnalyticsService.shared.setPersonProperties(["onboarding_status": "completed"]) 
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    restoreSavedStep()
                    AnalyticsService.shared.screen("onboarding_completion")
                }
            }
        }
        .background {
            // Background at parent level - fills entire window!
            Image("OnboardingBackgroundv2")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        }
    }
    
    private func restoreSavedStep() {
        if let savedStep = Step(rawValue: savedStepRawValue) {
            step = savedStep
        }
    }
    
    private func advance() {
        // Mark current step completed before advancing
        func markStepCompleted(_ s: Step) {
            let name: String
            switch s {
            case .welcome: name = "welcome"
            case .howItWorks: name = "how_it_works"
            case .screen: name = "screen_recording"
            case .llmSelection: name = "llm_selection"
            case .categories: name = "categories"
            case .llmSetup: name = "llm_setup"
            case .done: name = "completion"
            }
            AnalyticsService.shared.capture("onboarding_step_completed", ["step": name])
        }

        switch step {
        case .welcome:      
            markStepCompleted(step)
            step.next()
            savedStepRawValue = step.rawValue
        case .howItWorks:   
            markStepCompleted(step)
            step.next()
            savedStepRawValue = step.rawValue
        case .screen:
            // Permission request is handled by ScreenRecordingPermissionView itself
            markStepCompleted(step)
            step.next()
            savedStepRawValue = step.rawValue
            
            // Only try to start recording if we already have permission
            if CGPreflightScreenCaptureAccess() {
                Task {
                    do {
                        // Verify we have permission
                        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                        // Start recording
                        await MainActor.run {
                            AppState.shared.isRecording = true
                        }
                    } catch {
                        // Permission not granted yet, that's ok
                        // It will start after restart
                        print("Will start recording after restart")
                    }
                }
            }
        case .llmSelection:
            markStepCompleted(step)
            step.next()  // Move to categories
            savedStepRawValue = step.rawValue
        case .categories:
            markStepCompleted(step)
            if selectedProvider == "dayflow" {
                step = .done
            } else {
                step.next()
            }
            savedStepRawValue = step.rawValue
        case .llmSetup:
            markStepCompleted(step)
            step.next()
            savedStepRawValue = step.rawValue
        case .done:         
            didOnboard = true
            savedStepRawValue = 0  // Reset for next time
        }
    }
    
    private func requestScreenPerm() async throws {
        _ = try await SCShareableContent.current                 // triggers prompt
    }
}


/// Wizard step order
private enum Step: Int, CaseIterable { case welcome, howItWorks, screen, llmSelection, categories, llmSetup, done
    mutating func next() { self = Step(rawValue: rawValue + 1)! }
    mutating func prev() { self = Step(rawValue: rawValue - 1)! }
}


struct WelcomeView: View {
    let fullText: String
    @Binding var textOpacity: Double
    @Binding var timelineOffset: CGFloat
    let onStart: () -> Void
    
    var body: some View {
        ZStack {
            // Text and button container
            VStack {
                    VStack(spacing: 40) {
                        Text(fullText)
                            .font(.custom("InstrumentSerif-Regular", size: 36))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.horizontal, 20)
                            .minimumScaleFactor(0.5)
                            .lineLimit(3)
                            .frame(minHeight: 100)
                            .opacity(textOpacity)
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.6)) {
                                    textOpacity = 1
                                }
                            }
                        
                        DayflowSurfaceButton(
                            action: onStart,
                            content: { Text("Start").font(.custom("Nunito", size: 16)).fontWeight(.semibold) },
                            background: Color(red: 0.25, green: 0.17, blue: 0),
                            foreground: .white,
                            borderColor: .clear,
                            cornerRadius: 8,
                            horizontalPadding: 28,
                            verticalPadding: 14,
                            minWidth: 160,
                            showOverlayStroke: true
                        )
                            .opacity(textOpacity)
                            .animation(.easeIn(duration: 0.3).delay(0.4), value: textOpacity)
                    }
                    .padding(.top, 80)
                    
                    Spacer()
                }
                .zIndex(1)
                
                // Timeline image
                VStack {
                    Spacer()
                    Image("OnboardingTimeline")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 800)
                        .offset(y: timelineOffset)
                        .opacity(timelineOffset > 0 ? 0 : 1)
                        .onAppear {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0).delay(0.3)) {
                                timelineOffset = 0
                            }
                        }
                }
        }
    }
}

struct OnboardingCategorySetupView: View {
    let onNext: () -> Void
    @EnvironmentObject private var categoryStore: CategoryStore

    var body: some View {
        VStack(spacing: 32) {
            // Centered title section
            VStack(alignment: .center, spacing: 12) {
                Text("Customize your categories")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .frame(maxWidth: 800)

            // Full-width ColorOrganizerRoot with see-through effect
            ColorOrganizerRoot(showBackgroundGradient: false, onDismiss: {
                // Save button now advances to next step
                onNext()
            })
                .environmentObject(categoryStore)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 600)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CompletionView: View {
    let onFinish: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Image("DayflowLogoMainApp")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(height: 64)

            // Title section
            VStack(spacing: 12) {
                Text("You are ready to go!")
                    .font(.custom("InstrumentSerif-Regular", size: 36))
                    .foregroundColor(.black.opacity(0.9))
                
                Text("Welcome to Dayflow! Hit proceed to begin. For the best experience, let Dayflow run for about 30 minutes to learn your work patterns, then return to explore your personalized timeline.")
                    .font(.custom("Nunito", size: 15))
                    .foregroundColor(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Preview area
            Image("OnboardingTimeline")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 720)
                .frame(maxHeight: 400)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)

            // Proceed button
            DayflowSurfaceButton(
                action: onFinish,
                content: { 
                    Text("Proceed")
                        .font(.custom("Nunito", size: 16))
                        .fontWeight(.semibold) 
                },
                background: Color(red: 0.25, green: 0.17, blue: 0),
                foreground: .white,
                borderColor: .clear,
                cornerRadius: 8,
                horizontalPadding: 40,
                verticalPadding: 14,
                minWidth: 200,
                showOverlayStroke: true
            )
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 60)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OnboardingFlow_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingFlow()
            .environmentObject(AppState.shared)
            .frame(width: 1200, height: 800)
    }
}
