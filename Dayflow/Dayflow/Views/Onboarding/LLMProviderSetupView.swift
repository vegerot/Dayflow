//
//  LLMProviderSetupView.swift
//  Dayflow
//
//  LLM provider setup flow with step-by-step configuration
//

import SwiftUI

struct LLMProviderSetupView: View {
    let providerType: String // "ollama" or "gemini"
    let onBack: () -> Void
    let onComplete: () -> Void
    
    // Layout constants
    private let sidebarWidth: CGFloat = 250
    private let fixedOffset: CGFloat = 50
    
    @StateObject private var setupState = ProviderSetupState()
    @State private var sidebarOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var nextButtonHovered: Bool = false
    @State private var googleButtonHovered: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Back button and Title on same line
            HStack(alignment: .center, spacing: 0) {
                // Back button container matching sidebar width
                HStack {
                    Button(action: handleBack) {
                        HStack(spacing: 12) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.black.opacity(0.7))
                                .frame(width: 20, alignment: .center)
                            
                            Text("Back")
                                .font(.custom("Nunito", size: 15))
                                .fontWeight(.medium)
                                .foregroundColor(.black.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                    // Position where sidebar items start: 20 + 16 = 36px
                    .padding(.leading, 36) // Align with sidebar item structure
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    
                    Spacer()
                }
                .frame(width: sidebarWidth)
                
                // Title in the content area
                HStack {
                    Text(providerType == "ollama" ? "Use local AI" : "Bring your own API keys")
                        .font(.custom("Nunito", size: 32))
                        .fontWeight(.semibold)
                        .foregroundColor(.black.opacity(0.9))
                    
                    Spacer()
                }
                .padding(.leading, 40) // Gap between sidebar and content
            }
            .padding(.leading, fixedOffset)
            .padding(.top, fixedOffset)
            .padding(.bottom, 40)
            
            // Main content area with sidebar and content
            HStack(alignment: .top, spacing: 40) {
                // Sidebar - fixed width 250px
                VStack(alignment: .leading, spacing: 0) {
                    SetupSidebarView(
                        steps: setupState.steps,
                        currentStepId: setupState.currentStep.id,
                        onStepSelected: { setupState.navigateToStep($0) }
                    )
                    Spacer()
                }
                .frame(width: sidebarWidth)
                .opacity(sidebarOpacity)
                
                // Content area - wrapped in VStack to match sidebar alignment
                VStack(alignment: .leading, spacing: 0) {
                    currentStepContent
                        .frame(maxWidth: 500, alignment: .leading)
                    Spacer()
                }
                .opacity(contentOpacity)
            }
            .padding(.leading, fixedOffset)
            
            Spacer() // Push everything to top
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Background as a layer that doesn't affect layout!
            Image("OnboardingBackgroundv2")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        }
        .onAppear {
            setupState.configureSteps(for: providerType)
            animateAppearance()
        }
    }
    
    private var nextButtonText: String {
        if let title = setupState.currentStep.contentType.informationTitle {
            if (title == "Testing" || title == "Test Connection") && !setupState.testSuccessful {
                return "Test Required"
            }
        }
        return "Next"
    }
    
    @ViewBuilder
    private var nextButton: some View {
        if setupState.isLastStep {
            Button(action: {
                saveConfiguration()
                onComplete()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("Complete Setup")
                        .font(.custom("Nunito", size: 14))
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(Color(red: 1, green: 0.42, blue: 0.02))
                .cornerRadius(4)
            }
            .buttonStyle(NextButtonStyle())
            .scaleEffect(nextButtonHovered ? 1.05 : 1.0)
            .animation(.timingCurve(0.2, 0.8, 0.4, 1.0, duration: 0.25), value: nextButtonHovered)
            .onHover { hovering in
                nextButtonHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        } else {
            Button(action: handleContinue) {
                HStack(spacing: 6) {
                    Text(nextButtonText)
                        .font(.custom("Nunito", size: 14))
                        .fontWeight(.semibold)
                    if nextButtonText == "Next" {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .foregroundColor(.black.opacity(0.8))
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .inset(by: 0.5)
                        .stroke(Color.black.opacity(0.15), lineWidth: 1)
                )
                .cornerRadius(4)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(NextButtonStyle())
            .scaleEffect(nextButtonHovered ? 1.05 : 1.0)
            .animation(.timingCurve(0.2, 0.8, 0.4, 1.0, duration: 0.25), value: nextButtonHovered)
            .onHover { hovering in
                nextButtonHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .disabled(!setupState.canContinue)
            .opacity(!setupState.canContinue ? 0.5 : 1.0)
        }
    }
    
    @ViewBuilder
    private var currentStepContent: some View {
        let step = setupState.currentStep
        
        switch step.contentType {
        case .terminalCommand(let command):
            VStack(alignment: .leading, spacing: 24) {
                TerminalCommandView(
                    title: "Terminal command:",
                    subtitle: "Copy the code below and try running it in your terminal",
                    command: command
                )
                
                HStack {
                    Spacer()
                    nextButton
                }
            }
            
        case .apiKeyInput:
            VStack(alignment: .leading, spacing: 24) {
                APIKeyInputView(
                    apiKey: $setupState.apiKey,
                    title: "Enter your API key:",
                    subtitle: "Paste your Gemini API key below",
                    placeholder: "AIza...",
                    onValidate: { key in
                        // Basic validation for now
                        return key.hasPrefix("AIza") && key.count > 30
                    }
                )
                
                HStack {
                    Spacer()
                    nextButton
                }
            }
            
        case .modelDownload(let command):
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Download the AI model")
                        .font(.custom("Nunito", size: 24))
                        .fontWeight(.semibold)
                        .foregroundColor(.black.opacity(0.9))
                    
                    Text("This model enables Dayflow to understand what's on your screen")
                        .font(.custom("Nunito", size: 14))
                        .foregroundColor(.black.opacity(0.6))
                }
                
                TerminalCommandView(
                    title: "Run this command:",
                    subtitle: "This will download the Qwen 2.5 Vision model (about 3GB)",
                    command: command
                )
                
                HStack {
                    Spacer()
                    nextButton
                }
            }
            
        case .information(let title, let description):
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.custom("Nunito", size: 24))
                        .fontWeight(.semibold)
                        .foregroundColor(.black.opacity(0.9))
                    
                    Text(description)
                        .font(.custom("Nunito", size: 14))
                        .foregroundColor(.black.opacity(0.6))
                }
                
                // Add test button for Test connection step
                if title == "Testing" || title == "Test Connection" {
                    TestConnectionView(
                        onTestComplete: { success in
                            setupState.hasTestedConnection = true
                            setupState.testSuccessful = success
                        }
                    )
                }
                
                HStack {
                    Spacer()
                    nextButton
                }
            }
            
        case .apiKeyInstructions:
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Get your Gemini API key")
                        .font(.custom("Nunito", size: 24))
                        .fontWeight(.semibold)
                        .foregroundColor(.black.opacity(0.9))
                    
                    Text("Google's Gemini offers a generous free tier that should allow you to run Dayflow 24/7 for free - no credit card required")
                        .font(.custom("Nunito", size: 14))
                        .foregroundColor(.black.opacity(0.6))
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("1.")
                            .font(.custom("Nunito", size: 14))
                            .foregroundColor(.black.opacity(0.6))
                            .frame(width: 20, alignment: .leading)
                        
                        Group {
                            Text("Visit Google AI Studio ")
                                .font(.custom("Nunito", size: 14))
                                .foregroundColor(.black.opacity(0.8))
                            + Text("(aistudio.google.com)")
                                .font(.custom("Nunito", size: 14))
                                .foregroundColor(Color(red: 1, green: 0.42, blue: 0.02))
                                .underline()
                        }
                        .onTapGesture {
                            openGoogleAIStudio()
                        }
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("2.")
                            .font(.custom("Nunito", size: 14))
                            .foregroundColor(.black.opacity(0.6))
                            .frame(width: 20, alignment: .leading)
                        
                        Text("Click \"Get API key\" in the top right")
                            .font(.custom("Nunito", size: 14))
                            .foregroundColor(.black.opacity(0.8))
                    }
                    
                    HStack(alignment: .top, spacing: 12) {
                        Text("3.")
                            .font(.custom("Nunito", size: 14))
                            .foregroundColor(.black.opacity(0.6))
                            .frame(width: 20, alignment: .leading)
                        
                        Text("Create a new API key and copy it")
                            .font(.custom("Nunito", size: 14))
                            .foregroundColor(.black.opacity(0.8))
                    }
                }
                .padding(.vertical, 12)
                
                // Buttons row with Open Google AI Studio on left, Next on right
                HStack {
                    Button(action: openGoogleAIStudio) {
                        HStack(spacing: 8) {
                            Image(systemName: "safari")
                                .font(.system(size: 14))
                            Text("Open Google AI Studio")
                                .font(.custom("Nunito", size: 14))
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 13)
                        .background(Color(red: 1, green: 0.42, blue: 0.02))
                        .cornerRadius(4)
                    }
                    .buttonStyle(NextButtonStyle())
                    .scaleEffect(googleButtonHovered ? 1.05 : 1.0)
                    .animation(.timingCurve(0.2, 0.8, 0.4, 1.0, duration: 0.25), value: googleButtonHovered)
                    .onHover { hovering in
                        googleButtonHovered = hovering
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    
                    Spacer()
                    
                    nextButton
                }
            }
        }
    }
    
    private func handleBack() {
        if setupState.currentStepIndex == 0 {
            onBack()
        } else {
            setupState.goBack()
        }
    }
    
    private func handleContinue() {
        if setupState.isLastStep {
            saveConfiguration()
            onComplete()
        } else {
            setupState.markCurrentStepCompleted()
            setupState.goNext()
        }
    }
    
    private func saveConfiguration() {
        // Save API key to keychain for Gemini
        if providerType == "gemini" && !setupState.apiKey.isEmpty {
            KeychainManager.shared.store(setupState.apiKey, for: "gemini")
        }
        
        // Mark setup as complete
        UserDefaults.standard.set(true, forKey: "\(providerType)SetupComplete")
    }
    
    private func openGoogleAIStudio() {
        if let url = URL(string: "https://aistudio.google.com/app/apikey") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func animateAppearance() {
        withAnimation(.easeOut(duration: 0.4)) {
            sidebarOpacity = 1
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.4)) {
                contentOpacity = 1
            }
        }
    }
}

// MARK: - State Management
class ProviderSetupState: ObservableObject {
    @Published var steps: [SetupStep] = []
    @Published var currentStepIndex: Int = 0
    @Published var apiKey: String = ""
    @Published var hasTestedConnection: Bool = false
    @Published var testSuccessful: Bool = false
    
    var currentStep: SetupStep {
        guard currentStepIndex < steps.count else {
            return SetupStep(id: "fallback", title: "Setup", contentType: .information("Complete", "Setup is complete"))
        }
        return steps[currentStepIndex]
    }
    
    var canContinue: Bool {
        switch currentStep.contentType {
        case .apiKeyInput:
            return !apiKey.isEmpty && apiKey.count > 20
        case .terminalCommand, .modelDownload:
            // Allow users to continue after copying/running commands
            // They're responsible for ensuring commands complete
            return true
        case .information(let title, _):
            // For test connection step, require successful test
            if title == "Testing" || title == "Test Connection" {
                return testSuccessful
            }
            return true
        default:
            return true
        }
    }
    
    var isLastStep: Bool {
        return currentStepIndex == steps.count - 1
    }
    
    func configureSteps(for provider: String) {
        if provider == "ollama" {
            steps = [
                SetupStep(id: "install", title: "Basic setup", 
                         contentType: .terminalCommand("/bin/bash -c \"$(curl -fsSL https://ollama.com/install.sh)\"")),
                SetupStep(id: "model", title: "Download model", 
                         contentType: .modelDownload("ollama pull qwen2.5vl:3b")),
                SetupStep(id: "verify", title: "Verify installation", 
                         contentType: .terminalCommand("ollama list")),
                SetupStep(id: "complete", title: "Complete", 
                         contentType: .information("All set!", "Ollama is now configured and ready to use with Dayflow."))
            ]
        } else { // gemini
            steps = [
                SetupStep(id: "getkey", title: "Get API key", 
                         contentType: .apiKeyInstructions),
                SetupStep(id: "enterkey", title: "Enter API key", 
                         contentType: .apiKeyInput),
                SetupStep(id: "verify", title: "Test connection", 
                         contentType: .information("Test Connection", "Click the button below to verify your API key works with Gemini")),
                SetupStep(id: "complete", title: "Complete", 
                         contentType: .information("All set!", "Gemini is now configured and ready to use with Dayflow."))
            ]
        }
    }
    
    func goNext() {
        // Save API key to keychain when moving from API key input step
        if currentStep.contentType.isApiKeyInput && !apiKey.isEmpty {
            KeychainManager.shared.store(apiKey, for: "gemini")
            // Reset test state when API key changes
            hasTestedConnection = false
            testSuccessful = false
        }
        
        if currentStepIndex < steps.count - 1 {
            currentStepIndex += 1
        }
    }
    
    func goBack() {
        if currentStepIndex > 0 {
            currentStepIndex -= 1
        }
    }
    
    func navigateToStep(_ stepId: String) {
        if let index = steps.firstIndex(where: { $0.id == stepId }) {
            // Reset test state when navigating to test step
            if stepId == "verify" {
                hasTestedConnection = false
                testSuccessful = false
            }
            // Allow free navigation between all steps
            currentStepIndex = index
        }
    }
    
    func markCurrentStepCompleted() {
        if currentStepIndex < steps.count {
            steps[currentStepIndex].markCompleted()
        }
    }
}

// MARK: - Data Models
struct SetupStep: Identifiable {
    let id: String
    let title: String
    let contentType: StepContentType
    private(set) var isCompleted: Bool = false
    
    mutating func markCompleted() {
        isCompleted = true
    }
}

enum StepContentType {
    case terminalCommand(String)
    case apiKeyInput
    case apiKeyInstructions
    case modelDownload(String)
    case information(String, String)
    
    var isApiKeyInput: Bool {
        if case .apiKeyInput = self {
            return true
        }
        return false
    }
    
    var informationTitle: String? {
        if case .information(let title, _) = self {
            return title
        }
        return nil
    }
}

// MARK: - Button Style
struct NextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.timingCurve(0.2, 0.8, 0.4, 1.0, duration: 0.15), value: configuration.isPressed)
    }
}
