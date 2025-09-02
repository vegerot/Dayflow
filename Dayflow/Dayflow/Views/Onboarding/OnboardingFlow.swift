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
    // MARK: – State
    @AppStorage("onboardingStep") private var savedStepRawValue = 0
    @State private var step: Step = .welcome
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var timelineOffset: CGFloat = 300 // Start below screen
    @State private var textOpacity: Double = 0
    @State private var selectedProvider: String = "" // Track selected provider
    private let fullText = "Stop wondering where your day went.\nStart understanding it."
    
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
                }
                
            case .howItWorks:
                HowItWorksView(
                    onBack: { step.prev() },
                    onNext: { advance() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    restoreSavedStep()
                }
                
            case .screen:
                ScreenRecordingPermissionView(
                    onBack: { step.prev() },
                    onNext: { advance() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    restoreSavedStep()
                }
                
            case .llmSelection:
                OnboardingLLMSelectionView(
                    onBack: { step.prev() },
                    onNext: { provider in
                        selectedProvider = provider
                        if provider == "dayflow" {
                            step = .done
                            savedStepRawValue = step.rawValue
                        } else {
                            advance()
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    restoreSavedStep()
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
                }
                
            case .done:
                CompletionView(
                    onFinish: {
                        didOnboard = true
                        savedStepRawValue = 0
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    restoreSavedStep()
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
    
    // MARK: – Flow control
    private func restoreSavedStep() {
        if let savedStep = Step(rawValue: savedStepRawValue) {
            step = savedStep
        }
    }
    
    private func advance() {
        switch step {
        case .welcome:      
            step.next()
            savedStepRawValue = step.rawValue
        case .howItWorks:   
            step.next()
            savedStepRawValue = step.rawValue
        case .screen:
            Task { try? await requestScreenPerm() }
            step.next()
            savedStepRawValue = step.rawValue
        case .llmSelection:
            step.next()  // Move to llmSetup
            savedStepRawValue = step.rawValue
        case .llmSetup:
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

// MARK: – Helpers

/// Wizard step order
private enum Step: Int, CaseIterable { case welcome, howItWorks, screen, llmSelection, llmSetup, done
    mutating func next() { self = Step(rawValue: rawValue + 1)! }
    mutating func prev() { self = Step(rawValue: rawValue - 1)! }
}

// MARK: - Standalone Views

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
                        
                        DayflowButton(title: "Start", action: onStart)
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

struct CompletionView: View {
    let onFinish: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Setup Complete")
                .font(.custom("InstrumentSerif-Regular", size: 28))
                .fontWeight(.medium)
            
            Text("You can now close this window; Dayflow will keep running in the menu-bar.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            DayflowButton(
                title: "Finish",
                action: onFinish,
                width: 120,
                fontSize: 14
            )
        }
        .padding(40)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(radius: 20)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview
struct OnboardingFlow_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingFlow()
            .environmentObject(AppState.shared)
            .frame(width: 1200, height: 800)
    }
}
