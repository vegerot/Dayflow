//
//  OnboardingLLMSelectionView.swift
//  Dayflow
//
//  LLM provider selection view for onboarding flow
//

import SwiftUI

struct OnboardingLLMSelectionView: View {
    // Navigation callbacks
    var onBack: () -> Void
    var onNext: () -> Void
    
    // MARK: - State
    @AppStorage("selectedLLMProvider") private var selectedProvider: String = "gemini" // Default to "Bring your own API"
    @State private var titleOpacity: Double = 0
    @State private var cardsOpacity: Double = 0
    @State private var bottomTextOpacity: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            let idealWidth: CGFloat = 1400
            let idealHeight: CGFloat = 900
            
            // Calculate scale factor to fit content in available space
            let scaleX = geometry.size.width / idealWidth
            let scaleY = geometry.size.height / idealHeight
            let scale = min(scaleX, scaleY, 1.0) // Never scale up, only down
            
            ZStack {
                // Main content with fixed ideal size
                VStack(spacing: 0) {
                    Spacer()
                    
                    VStack(spacing: 48) {
                        // MARK: - Title
                        Text("Choose a way to run Dayflow")
                            .font(.custom("InstrumentSerif-Regular", size: 48))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.black.opacity(0.9))
                            .opacity(titleOpacity)
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.6)) {
                                    titleOpacity = 1
                                }
                                animateContent()
                            }
                        
                        // MARK: - Provider Cards (Horizontal Layout)
                        HStack(spacing: 24) {
                            // Run locally card
                            ProviderCard(
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
                                isSelected: selectedProvider == "ollama",
                                onSelect: {
                                    // Higher damping (0.9) for less bounce, more professional feel
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                        selectedProvider = "ollama"
                                    }
                                },
                                onProceed: {
                                    selectedProvider = "ollama"
                                    saveProviderSelection()
                                    onNext()
                                }
                            )
                            
                            // Bring your own API card (selected by default)
                            ProviderCard(
                                id: "gemini",
                                title: "Bring your own API keys",
                                badgeText: "RECOMMENED",
                                badgeType: .orange,
                                icon: "key.fill",
                                features: [
                                    ("Utilizes more intelligent AI via Google's Gemini models", true),
                                    ("Uses Gemini's generous free tier (no credit card needed)", true),
                                    ("Your data goes directly to Google, bypasses our servers", true),
                                    ("Faster, more accurate than local models", true),
                                    ("Requires getting an API key (takes 2 clicks)", false)
                                ],
                                isSelected: selectedProvider == "gemini",
                                onSelect: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                        selectedProvider = "gemini"
                                    }
                                },
                                onProceed: {
                                    selectedProvider = "gemini"
                                    saveProviderSelection()
                                    onNext()
                                }
                            )
                            
                            // Dayflow Pro card
                            ProviderCard(
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
                                isSelected: selectedProvider == "dayflow",
                                onSelect: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                        selectedProvider = "dayflow"
                                    }
                                },
                                onProceed: {
                                    selectedProvider = "dayflow"
                                    saveProviderSelection()
                                    onNext()
                                }
                            )
                        }
                        .opacity(cardsOpacity)
                        
                        // MARK: - Bottom text
                        HStack {
                            Text("Not sure which to choose? ")
                                .font(.custom("Nunito", size: 14))
                                .foregroundColor(.black.opacity(0.6))
                            + Text("Try Dayflow Pro free for 1 month")
                                .font(.custom("Nunito", size: 14))
                                .fontWeight(.semibold)
                                .foregroundColor(.black.opacity(0.8))
                            
                            Text(" - no credit card required.")
                                .font(.custom("Nunito", size: 14))
                                .foregroundColor(.black.opacity(0.6))
                        }
                        .opacity(bottomTextOpacity)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 60)
                    
                    Spacer()
                }
                .frame(width: idealWidth, height: idealHeight)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }
    
    // MARK: - Helper Methods
    private func saveProviderSelection() {
        let providerType: LLMProviderType
        
        switch selectedProvider {
        case "ollama":
            providerType = .ollamaLocal()
        case "gemini":
            providerType = .geminiDirect
        case "dayflow":
            providerType = .dayflowBackend()
        default:
            providerType = .geminiDirect
        }
        
        if let encoded = try? JSONEncoder().encode(providerType) {
            UserDefaults.standard.set(encoded, forKey: "llmProviderType")
        }
    }
    
    private func animateContent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.6)) {
                cardsOpacity = 1
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeOut(duration: 0.4)) {
                bottomTextOpacity = 1
            }
        }
    }
}

// MARK: - Badge Type
enum BadgeType {
    case green, orange, blue
}

// MARK: - Custom Button Style (No press dimming)
struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // No opacity or scale changes on press
    }
}

// MARK: - Proceed Button Style with active state
struct ProceedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.timingCurve(0.2, 0.8, 0.4, 1.0, duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Provider Card Component
struct ProviderCard: View {
    let id: String
    let title: String
    let badgeText: String
    let badgeType: BadgeType
    let icon: String
    let features: [(text: String, isAvailable: Bool)]
    let isSelected: Bool
    let onSelect: () -> Void
    let onProceed: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            cardContent
        }
        .buttonStyle(NoHighlightButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private var cardContent: some View {
        VStack(spacing: 0) {
            // Main content area
            VStack(alignment: .leading, spacing: 0) {
                iconSection
                titleSection
                badgeSection
                featuresSection
                Spacer()
            }
            
            proceedButton
        }
        .frame(width: 360, height: 500)
        .background(cardBackground)
        .cornerRadius(4)
        .overlay(cardOverlay)
        .modifier(CardShadowModifier(isSelected: isSelected))
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)  // Only hover effect
        // Less bouncy spring for selection (0.9 damping = minimal bounce)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: isSelected)
        .animation(.easeOut(duration: 0.2), value: isHovered)
    }
    
    private var iconSection: some View {
        HStack {
            Spacer()
            ProviderIconView(icon: icon)
            Spacer()
        }
        .padding(.top, 24)
        .padding(.bottom, 16)
    }
    
    private var titleSection: some View {
        HStack {
            Spacer()
            Text(title)
                .font(.custom("Nunito", size: 20))
                .fontWeight(.semibold)
                .foregroundColor(.black.opacity(0.9))
            Spacer()
        }
        .padding(.bottom, 8)
    }
    
    private var badgeSection: some View {
        HStack {
            Spacer()
            BadgeView(text: badgeText, type: badgeType)
            Spacer()
        }
        .padding(.bottom, 24)
    }
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                FeatureRowView(feature: feature)
            }
        }
        .padding(.horizontal, 24)
    }
    
    private var proceedButton: some View {
        ProceedButtonView(
            isSelected: isSelected,
            action: onProceed
        )
        .padding(.bottom, 24)
    }
    
    @ViewBuilder
    private var cardBackground: some View {
        if isSelected {
            SelectedCardBackground()
        } else {
            Color.white.opacity(0.3)
        }
    }
    
    @ViewBuilder
    private var cardOverlay: some View {
        if isSelected {
            SelectedCardOverlay()
        } else {
            RoundedRectangle(cornerRadius: 4)
                .inset(by: 0.5)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }
}

// MARK: - Subcomponents

struct ProviderIconView: View {
    let icon: String
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(.black.opacity(0.7))
            .frame(width: 40, height: 40)
            .background(.white.opacity(0.6))
            .cornerRadius(3)
            .shadow(color: Color(red: 0.92, green: 0.91, blue: 0.91), radius: 1, x: -1, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .inset(by: 0.23)
                    .stroke(.white.opacity(0.87), lineWidth: 0.46508)
            )
    }
}

struct FeatureRowView: View {
    let feature: (text: String, isAvailable: Bool)
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: feature.isAvailable ? "checkmark" : "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(feature.isAvailable ? Color(red: 0.34, green: 1, blue: 0.45) : Color(hex: "E91515"))
                .frame(width: 16)
            
            Text(feature.text)
                .font(.custom("Nunito", size: 14))
                .foregroundColor(.black.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ProceedButtonView: View {
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("Proceed")
                    .font(.custom("Nunito", size: 14))
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .black.opacity(0.8))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .frame(width: 312)
            .background(buttonBackground)
            .cornerRadius(4)
            .overlay(buttonOverlay)
        }
        .buttonStyle(ProceedButtonStyle())
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.timingCurve(0.2, 0.8, 0.4, 1.0, duration: 0.25), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    @ViewBuilder
    private var buttonBackground: some View {
        if isSelected {
            Color(red: 0.25, green: 0.17, blue: 0)
        } else {
            Color.white.opacity(0.0001)
        }
    }
    
    @ViewBuilder
    private var buttonOverlay: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(
                isSelected ? Color.clear : Color.black.opacity(0.2),
                lineWidth: 1
            )
    }
}

struct SelectedCardBackground: View {
    var body: some View {
        ZStack {
            // Layer 1: Solid background
            Color(hex: "FCF2E3")
            
            // Layer 2: White overlay at 69% opacity
            Color.white.opacity(0.69)
            
            // Layer 3: Gradient from transparent to orange (flipped)
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color.clear, location: 0.25),                          // Start transparent
                    Gradient.Stop(color: Color(hex: "FF7506").opacity(0.05), location: 0.7),    // Light orange
                    Gradient.Stop(color: Color(hex: "FF7506").opacity(0.15), location: 1.0)     // End with stronger orange
                ],
                startPoint: UnitPoint(x: 0, y: 0.5), // Left
                endPoint: UnitPoint(x: 1, y: 0.5)    // Right
            )
        }
    }
}

struct SelectedCardOverlay: View {
    var body: some View {
        ZStack {
            // Layer 1: Base stroke - light gray
            RoundedRectangle(cornerRadius: 4)
                .inset(by: 0.5)
                .stroke(Color(hex: "EBE9E6"), lineWidth: 1)
            
            // Layer 2: Middle stroke - peachy/cream
            RoundedRectangle(cornerRadius: 4)
                .inset(by: 0.5)
                .stroke(Color(hex: "FFEBC9"), lineWidth: 1)
            
            // Layer 3: Angular gradient stroke with closed loop
            RoundedRectangle(cornerRadius: 4)
                .inset(by: 0.5)
                .stroke(
                    AngularGradient(
                        stops: [
                            // CLOSE THE LOOP — same color at 0.0 and 1.0
                            .init(color: Color(hex: "FFF1D3").opacity(0.50), location: 0.00),
                            
                            .init(color: Color(hex: "FF8904").opacity(0.50), location: 0.03),
                            .init(color: Color(hex: "FF8904").opacity(0.35), location: 0.09),
                            .init(color: .white, location: 0.17),
                            .init(color: .white.opacity(0.75), location: 0.23),
                            .init(color: .white.opacity(0.50), location: 0.25),
                            .init(color: .white.opacity(0.50), location: 0.30),
                            .init(color: Color(hex: "FF8904").opacity(0.35), location: 0.52),
                            .init(color: Color(hex: "FFE0A5"), location: 0.58),
                            .init(color: .white, location: 0.80),
                            .init(color: Color(hex: "FFF1D3").opacity(0.50), location: 0.91),
                            
                            // mirror the first stop so 1.0 == 0.0
                            .init(color: Color(hex: "FFF1D3").opacity(0.50), location: 1.00)
                        ],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    lineWidth: 1
                )
        }
    }
}

struct CardShadowModifier: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .shadow(
                color: isSelected ? Color(red: 0.47, green: 0.27, blue: 0.09).opacity(0.21) : Color.clear,
                radius: 5,
                x: 4,
                y: 3
            )
            .shadow(
                color: isSelected ? Color(red: 0.47, green: 0.27, blue: 0.09).opacity(0.18) : Color.clear,
                radius: 9.5,
                x: 14,
                y: 12
            )
            .shadow(
                color: isSelected ? Color(red: 0.48, green: 0.27, blue: 0.1).opacity(0.11) : Color.clear,
                radius: 12.5,
                x: 32,
                y: 27
            )
    }
}

// MARK: - Badge View Component
struct BadgeView: View {
    let text: String
    let type: BadgeType
    
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.custom("Nunito", size: 11))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeBackground)
        .cornerRadius(2)
        .modifier(BadgeShadowModifier(shadowColor: shadowColor))
        .overlay(badgeOverlay)
    }
    
    private var badgeBackground: some View {
        ZStack {
            Color.white.opacity(0.69)
            
            LinearGradient(
                stops: gradientColors,
                startPoint: UnitPoint(x: 1.15, y: 3.61),
                endPoint: UnitPoint(x: 0.02, y: 0)
            )
        }
    }
    
    private var badgeOverlay: some View {
        RoundedRectangle(cornerRadius: 2)
            .inset(by: 0.25)
            .stroke(strokeColor, lineWidth: 0.5)
    }
    
    private var gradientColors: [Gradient.Stop] {
        switch type {
        case .green:
            return [
                Gradient.Stop(color: Color(red: 0.34, green: 1, blue: 0.45), location: 0.00),
                Gradient.Stop(color: Color(red: 1, green: 0.98, blue: 0.95).opacity(0), location: 1.00)
            ]
        case .orange:
            return [
                Gradient.Stop(color: Color(red: 1, green: 0.49, blue: 0.34), location: 0.00),
                Gradient.Stop(color: Color(red: 1, green: 0.98, blue: 0.95).opacity(0), location: 1.00)
            ]
        case .blue:
            return [
                Gradient.Stop(color: Color(red: 0.34, green: 0.56, blue: 1), location: 0.00),
                Gradient.Stop(color: Color(red: 1, green: 0.98, blue: 0.95).opacity(0), location: 1.00)
            ]
        }
    }
    
    private var shadowColor: Color {
        switch type {
        case .green:
            return Color(red: 0.34, green: 1, blue: 0.45)
        case .orange:
            return Color(red: 1, green: 0.53, blue: 0)
        case .blue:
            return Color(red: 0.34, green: 0.56, blue: 1)
        }
    }
    
    private var strokeColor: Color {
        switch type {
        case .green:
            return Color(red: 0.34, green: 1, blue: 0.45).opacity(0.3)
        case .orange:
            return Color(red: 1, green: 0.25, blue: 0.02).opacity(0.3)
        case .blue:
            return Color(red: 0.34, green: 0.56, blue: 1).opacity(0.3)
        }
    }
}

struct BadgeShadowModifier: ViewModifier {
    let shadowColor: Color
    
    func body(content: Content) -> some View {
        content
            .shadow(color: shadowColor.opacity(0.14), radius: 1.5, x: 0, y: 1)
            .shadow(color: shadowColor.opacity(0.12), radius: 2.5, x: 2, y: 4)
            .shadow(color: shadowColor.opacity(0.07), radius: 3, x: 4, y: 10)
            .shadow(color: shadowColor.opacity(0.02), radius: 3.5, x: 7, y: 17)
            .shadow(color: shadowColor.opacity(0), radius: 4, x: 10, y: 27)
    }
}

// MARK: - Color Extension for Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview
struct OnboardingLLMSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingLLMSelectionView(
            onBack: {},
            onNext: {}
        )
        .frame(width: 1400, height: 900)
        .background(
            Image("OnboardingBackgroundv2")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
    }
}
