//
//  SettingsView.swift
//  Dayflow
//
//  Settings page with provider selection cards using shared components
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var updater: UpdaterManager
    // State for current provider
    @State private var currentProvider: String = "gemini"
    @State private var setupModalProvider: String? = nil
    @State private var hasLoadedProvider: Bool = false
    @State private var analyticsEnabled: Bool = AnalyticsService.shared.isOptedIn
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - left aligned
            VStack(alignment: .leading, spacing: 12) {
                Text("Settings")
                    .font(.custom("InstrumentSerif-Regular", size: 42))
                    .foregroundColor(.black.opacity(0.9))
                    .padding(.leading, 10)
                
                Text("Manage how Dayflow is run")
                    .font(.custom("Nunito", size: 14))
                    .foregroundColor(.black.opacity(0.6))

                // Analytics toggle (default ON)
                Toggle(isOn: $analyticsEnabled) {
                    Text("Share anonymous usage analytics")
                        .font(.custom("Nunito", size: 13))
                        .foregroundColor(.black.opacity(0.7))
                }
                .toggleStyle(.switch)
                .frame(maxWidth: 340, alignment: .leading)

                // Simple update status + action
                HStack(spacing: 14) {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                    Text("Dayflow v\(version)")
                        .font(.custom("Nunito", size: 13))
                        .foregroundColor(.black.opacity(0.65))

                    Text(updater.statusText.isEmpty ? "" : updater.statusText)
                        .font(.custom("Nunito", size: 13))
                        .foregroundColor(.black.opacity(0.45))

                    Spacer()

                    Button(action: { updater.checkForUpdates() }) {
                        if updater.isChecking {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Text("Check for updates")
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Provider Cards - centered within content area
            ScrollView {
                HStack(spacing: 20) {
                    ForEach(providerCards, id: \.id) { card in
                        card
                            .frame(maxWidth: 350)  // Cards shouldn't stretch beyond 350px
                            .frame(height: 420)
                    }
                }
                
            }
            .frame(maxWidth: .infinity)  // Center the scrollview content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            loadCurrentProvider()
            AnalyticsService.shared.capture("settings_opened")
            analyticsEnabled = AnalyticsService.shared.isOptedIn
        }
        .onChange(of: analyticsEnabled) { enabled in
            AnalyticsService.shared.setOptIn(enabled)
            AnalyticsService.shared.capture("analytics_opt_in_changed", ["enabled": enabled])
        }
        .sheet(item: Binding(
            get: { setupModalProvider.map { ProviderSetupWrapper(id: $0) } },
            set: { setupModalProvider = $0?.id }
        )) { wrapper in
            LLMProviderSetupView(
                providerType: wrapper.id,
                onBack: { setupModalProvider = nil },
                onComplete: {
                    completeProviderSwitch(wrapper.id)
                    setupModalProvider = nil
                }
            )
            .frame(minWidth: 900, minHeight: 650)
        }
    }
    
    // MARK: - Provider Cards
    
    private var providerCards: [FlexibleProviderCard] {
        [
            FlexibleProviderCard(
                id: "ollama",
                title: "Use local AI",
                badgeText: "MOST PRIVATE",
                badgeType: .green,
                icon: "desktopcomputer",
                features: [
                    ("100% private - everything's processed on your computer", true),
                    ("Works completely offline", true),
                    ("Significantly less intelligence", true),
                    ("Requires the most setup", false),
                    ("16GB+ of RAM recommended", false),
                    ("Can be battery-intensive", false)
                ],
                isSelected: currentProvider == "ollama",
                buttonMode: .settings(onSwitch: { switchToProvider("ollama") }),
                showCurrentlySelected: true
            ),
            
            FlexibleProviderCard(
                id: "gemini",
                title: "Bring your own API keys",
                badgeText: "RECOMMENDED",
                badgeType: .orange,
                icon: "key.fill",
                features: [
                    ("Utilizes more intelligent AI via Google's Gemini models", true),
                    ("Uses Gemini's generous free tier (no credit card needed)", true),
                    ("Faster, more accurate than local models", true),
                    ("Requires getting an API key (takes 2 clicks)", false)
                ],
                isSelected: currentProvider == "gemini",
                buttonMode: .settings(onSwitch: { switchToProvider("gemini") }),
                showCurrentlySelected: true
            ),
            
            FlexibleProviderCard(
                id: "dayflow",
                title: "Dayflow Pro",
                badgeText: "EASIEST SETUP",
                badgeType: .blue,
                icon: "sparkles",
                features: [
                    ("Zero setup - just sign in and go", true),
                    ("Your data is processed then immediately deleted", true),
                    ("Never used to train AI models", true),
                    ("Always the fastest, most capable AI", true),
                    ("Fixed monthly pricing, no surprises", true),
                    ("Requires internet connection", false)
                ],
                isSelected: currentProvider == "dayflow",
                buttonMode: .settings(onSwitch: { switchToProvider("dayflow") }),
                showCurrentlySelected: true
            )
        ]
    }
    
    // MARK: - Actions
    
    private func loadCurrentProvider() {
        guard !hasLoadedProvider else { return }
        
        if let data = UserDefaults.standard.data(forKey: "llmProviderType"),
           let providerType = try? JSONDecoder().decode(LLMProviderType.self, from: data) {
            switch providerType {
            case .geminiDirect:
                currentProvider = "gemini"
            case .dayflowBackend:
                currentProvider = "dayflow"
            case .ollamaLocal:
                currentProvider = "ollama"
            }
        }
        hasLoadedProvider = true
    }
    
    private func switchToProvider(_ providerId: String) {
        guard providerId != currentProvider else { return }
        
        // For Dayflow Pro, just show coming soon
        if providerId == "dayflow" {
            return
        }
        
        // Open setup flow for the selected provider
        AnalyticsService.shared.capture("provider_switch_initiated", ["from": currentProvider, "to": providerId])
        setupModalProvider = providerId
    }
    
    private func completeProviderSwitch(_ providerId: String) {
        // Save the provider type
        let providerType: LLMProviderType
        switch providerId {
        case "ollama":
            let endpoint = UserDefaults.standard.string(forKey: "llmLocalBaseURL") ?? "http://localhost:11434"
            providerType = .ollamaLocal(endpoint: endpoint)
        case "gemini":
            providerType = .geminiDirect
        case "dayflow":
            providerType = .dayflowBackend()
        default:
            return
        }
        if let encoded = try? JSONEncoder().encode(providerType) {
            UserDefaults.standard.set(encoded, forKey: "llmProviderType")
        }
        
        // Update current selection
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            currentProvider = providerId
        }
        AnalyticsService.shared.capture("provider_setup_completed", ["provider": providerId])
        AnalyticsService.shared.setPersonProperties(["current_llm_provider": providerId])
    }
}

// MARK: - Provider Setup Wrapper (for sheet binding)

struct ProviderSetupWrapper: Identifiable {
    let id: String
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .frame(width: 1400, height: 800)
            .background(Color.gray.opacity(0.1))
    }
}
