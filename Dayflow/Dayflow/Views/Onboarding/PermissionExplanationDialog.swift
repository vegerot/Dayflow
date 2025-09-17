//
//  PermissionExplanationDialog.swift
//  Dayflow
//
//  Custom dialog to explain permissions before requesting them
//

import SwiftUI
import AppKit

struct PermissionExplanationDialog: View {
    @Binding var isPresented: Bool
    let onProceed: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .cornerRadius(12)
            
            // Title
            Text("Permission Required")
                .font(.custom("Nunito", size: 24))
                .fontWeight(.bold)
                .foregroundColor(.black.opacity(0.9))
            
            // Explanation
            VStack(spacing: 12) {
                Text("macOS will ask for screen recording permission to enable activity tracking.")
                    .font(.custom("Nunito", size: 15))
                    .foregroundColor(.black.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("Your privacy is guaranteed: All recordings stay on your Mac. With local AI models, even processing happens on-device. Nothing leaves your computer.")
                    .font(.custom("Nunito", size: 14))
                    .foregroundColor(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 380)
            
            // Buttons
            HStack(spacing: 16) {
                Button(action: {
                    isPresented = false
                }) {
                    Text("Cancel")
                        .font(.custom("Nunito", size: 16))
                        .fontWeight(.medium)
                        .foregroundColor(.black.opacity(0.6))
                        .frame(minWidth: 100)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    isPresented = false
                    // Small delay to let dialog close before showing system dialog
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onProceed()
                    }
                }) {
                    Text("Grant Permission")
                        .font(.custom("Nunito", size: 16))
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(minWidth: 140)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 20)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(32)
        .frame(width: 480)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
    }
}


extension View {
    func permissionExplanationDialog(isPresented: Binding<Bool>, onProceed: @escaping () -> Void) -> some View {
        self.overlay(
            Group {
                if isPresented.wrappedValue {
                    ZStack {
                        // Background overlay
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture {
                                isPresented.wrappedValue = false
                            }
                        
                        // Dialog
                        PermissionExplanationDialog(
                            isPresented: isPresented,
                            onProceed: onProceed
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.9), value: isPresented.wrappedValue)
        )
    }
}