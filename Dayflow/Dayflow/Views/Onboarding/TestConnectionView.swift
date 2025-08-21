//
//  TestConnectionView.swift
//  Dayflow
//
//  Test connection button for Gemini API
//

import SwiftUI

struct TestConnectionView: View {
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var isHovered = false
    
    enum TestResult {
        case success(String)
        case failure(String)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Test button
            Button(action: testConnection) {
                HStack(spacing: 12) {
                    if isTesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: testResult == nil ? "bolt.fill" : 
                              (testResult?.isSuccess == true ? "checkmark.circle.fill" : "xmark.circle.fill"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(testResult == nil ? .white : 
                                           (testResult?.isSuccess == true ? Color(red: 0.34, green: 1, blue: 0.45) : Color(hex: "E91515")))
                    }
                    
                    Text(buttonTitle)
                        .font(.custom("Nunito", size: 14))
                        .fontWeight(.semibold)
                }
                .foregroundColor(testResult?.isSuccess == true ? .black : .white)
                .padding(.horizontal, 24)
                .padding(.vertical, 13)
                .frame(minWidth: 200)
                .background(buttonBackground)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(buttonBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isTesting)
            .scaleEffect(isHovered && !isTesting ? 1.05 : 1.0)
            .animation(.timingCurve(0.2, 0.8, 0.4, 1.0, duration: 0.25), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering && !isTesting {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            
            // Result message
            if let result = testResult {
                HStack(spacing: 8) {
                    Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(result.isSuccess ? Color(red: 0.34, green: 1, blue: 0.45) : Color(hex: "E91515"))
                    
                    Text(result.message)
                        .font(.custom("Nunito", size: 13))
                        .foregroundColor(result.isSuccess ? .black.opacity(0.7) : Color(hex: "E91515"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(result.isSuccess ? 
                              Color(red: 0.34, green: 1, blue: 0.45).opacity(0.1) : 
                              Color(hex: "E91515").opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(result.isSuccess ? 
                               Color(red: 0.34, green: 1, blue: 0.45).opacity(0.3) : 
                               Color(hex: "E91515").opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    private var buttonTitle: String {
        if isTesting {
            return "Testing connection..."
        } else if testResult?.isSuccess == true {
            return "Test Successful!"
        } else if testResult?.isSuccess == false {
            return "Test Failed - Try Again"
        } else {
            return "Test Connection"
        }
    }
    
    private var buttonBackground: Color {
        if testResult?.isSuccess == true {
            return Color(red: 0.34, green: 1, blue: 0.45).opacity(0.2)
        } else {
            return Color(red: 1, green: 0.42, blue: 0.02)
        }
    }
    
    private var buttonBorder: Color {
        if testResult?.isSuccess == true {
            return Color(red: 0.34, green: 1, blue: 0.45).opacity(0.5)
        } else {
            return Color.clear
        }
    }
    
    private func testConnection() {
        guard !isTesting else { return }
        
        // Get API key from keychain
        guard let apiKey = KeychainManager.shared.retrieve(for: "gemini") else {
            testResult = .failure("No API key found. Please enter your API key first.")
            return
        }
        
        isTesting = true
        testResult = nil
        
        Task {
            do {
                let response = try await GeminiAPIHelper.shared.testConnection(apiKey: apiKey)
                await MainActor.run {
                    testResult = .success("Connection successful! Response: \(response)")
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}

extension TestConnectionView.TestResult {
    var isSuccess: Bool {
        switch self {
        case .success: return true
        case .failure: return false
        }
    }
    
    var message: String {
        switch self {
        case .success(let msg): return msg
        case .failure(let msg): return msg
        }
    }
}

// Color extension for hex (if not already defined)
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