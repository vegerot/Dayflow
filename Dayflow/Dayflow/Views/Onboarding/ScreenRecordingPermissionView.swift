//
//  ScreenRecordingPermissionView.swift
//  Dayflow
//
//  Screen recording permission request with visual guide
//

import SwiftUI
import ScreenCaptureKit

struct ScreenRecordingPermissionView: View {
    var onBack: () -> Void
    var onNext: () -> Void
    
    @State private var hasPermission = false
    @State private var checkTimer: Timer?
    
    var body: some View {
        HStack(spacing: 60) {
            // Left side - Instructions
            VStack(alignment: .leading, spacing: 24) {
                Text("Let's configure essential settings to get\nthe most out of Dayflow.")
                    .font(.custom("Nunito", size: 20))
                    .foregroundColor(.black.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 40)
                
                Text("Screen Recording")
                    .font(.custom("InstrumentSerif-Regular", size: 32))
                    .foregroundColor(.black.opacity(0.9))
                
                Text("We'll need permission to see which apps you're using (no content is captured).")
                    .font(.custom("Nunito", size: 16))
                    .foregroundColor(.black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                
                // Show restart message if permission was granted
                if hasPermission {
                    Text("Great! Please restart Dayflow to continue.")
                        .font(.custom("Nunito", size: 14))
                        .foregroundColor(.green)
                        .padding(.top, 8)
                }
                
                // Open Settings button
                DayflowSurfaceButton(
                    action: openScreenRecordingSettings,
                    content: { Text("Open System Settings").font(.custom("Nunito", size: 16)).fontWeight(.medium) },
                    background: Color.blue,
                    foreground: .white,
                    borderColor: .clear,
                    cornerRadius: 8,
                    horizontalPadding: 24,
                    verticalPadding: 12
                )
                .padding(.top, 16)
                
                // Navigation buttons
                HStack(spacing: 16) {
                    DayflowSurfaceButton(
                        action: onBack,
                        content: { Text("Back").font(.custom("Nunito", size: 14)).fontWeight(.semibold) },
                        background: .white,
                        foreground: .black,
                        borderColor: Color.black.opacity(0.15),
                        cornerRadius: 8,
                        horizontalPadding: 20,
                        verticalPadding: 12,
                        minWidth: 120
                    )
                    DayflowSurfaceButton(
                        action: { if hasPermission { onNext() } },
                        content: { Text("Next").font(.custom("Nunito", size: 14)).fontWeight(.semibold) },
                        background: hasPermission ? Color(red: 1, green: 0.42, blue: 0.02) : Color.white,
                        foreground: hasPermission ? .white : .black.opacity(0.4),
                        borderColor: hasPermission ? .clear : Color.black.opacity(0.1),
                        cornerRadius: 8,
                        horizontalPadding: 20,
                        verticalPadding: 12,
                        minWidth: 120
                    )
                    .disabled(!hasPermission)
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .frame(maxWidth: 400)
            
            // Right side - System Settings preview
            if let image = NSImage(named: "ScreenRecordingSettings") {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            } else {
                // Placeholder if image not found
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 600, height: 400)
                    .overlay(
                        Text("System Settings Preview")
                            .foregroundColor(.gray)
                    )
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            checkPermission()
            startPermissionMonitoring()
        }
        .onDisappear {
            checkTimer?.invalidate()
        }
    }
    
    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func checkPermission() {
        Task {
            do {
                // Try to get available content - this will fail if we don't have permission
                _ = try await SCShareableContent.current
                await MainActor.run {
                    if !hasPermission {
                        hasPermission = true
                        // Auto-advance after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onNext()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    hasPermission = false
                }
            }
        }
    }
    
    private func startPermissionMonitoring() {
        // Check every second for permission changes
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkPermission()
        }
    }
}
