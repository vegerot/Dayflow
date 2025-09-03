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
    @AppStorage("selectedLLMProvider") private var selectedProvider: String = "gemini" // Persist across sessions
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
                        
                        DayflowSurfaceButton(
                            action: onStart,
                            content: { Text("Start").font(.custom("Nunito", size: 16)).fontWeight(.semibold) },
                            background: Color(red: 1, green: 0.42, blue: 0.02),
                            foreground: .white,
                            borderColor: .clear,
                            cornerRadius: 12,
                            horizontalPadding: 28,
                            verticalPadding: 16,
                            minWidth: 160
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

struct CompletionView: View {
    let onFinish: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
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
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 1, green: 0.98, blue: 0.94),
                            Color(red: 1, green: 0.96, blue: 0.88)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 280)
                .overlay(
                    // Timeline image
                    VStack {
                        Image("OnboardingTimeline")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(10)
                )
            
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
                minWidth: 200
            )
        }
        .padding(48)
        .frame(width: 640)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
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
