//
//  ScreenRecordingPermissionView.swift
//  Dayflow
//
//  Screen recording permission request using idiomatic ScreenCaptureKit approach
//

import SwiftUI
import ScreenCaptureKit
import CoreGraphics

struct ScreenRecordingPermissionView: View {
    var onBack: () -> Void
    var onNext: () -> Void
    
    @State private var permissionState: PermissionState = .notChecked
    @State private var isCheckingPermission = false
    
    enum PermissionState {
        case notChecked
        case granted
        case denied
    }
    
    var body: some View {
        HStack(spacing: 60) {
            // Left side - text and controls
            VStack(alignment: .leading, spacing: 24) {
                Text("Let's configure essential settings to get\nthe most out of Dayflow.")
                    .font(.custom("Nunito", size: 20))
                    .foregroundColor(.black.opacity(0.7))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
                
                Text("Screen Recording")
                    .font(.custom("Nunito", size: 32))
                    .fontWeight(.bold)
                    .foregroundColor(.black.opacity(0.9))
                
                Text("Screen recordings are stored locally on your Mac and can be processed entirely on-device using local AI models.")
                    .font(.custom("Nunito", size: 16))
                    .foregroundColor(.black.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                
                // State-based messaging
                Group {
                    switch permissionState {
                    case .notChecked:
                        EmptyView()
                    case .granted:
                        Text("✓ Permission granted! Click Next to continue.")
                            .font(.custom("Nunito", size: 14))
                            .foregroundColor(.green)
                    case .denied:
                        Text("Please grant permission in System Settings.")
                            .font(.custom("Nunito", size: 14))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.top, 8)
                
                // Action button
                Group {
                    switch permissionState {
                    case .notChecked:
                        DayflowSurfaceButton(
                            action: { checkPermission() },
                            content: { 
                                HStack {
                                    if isCheckingPermission {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .progressViewStyle(CircularProgressViewStyle())
                                    }
                                    Text(isCheckingPermission ? "Checking..." : "Grant Permission")
                                        .font(.custom("Nunito", size: 16))
                                        .fontWeight(.medium)
                                }
                            },
                            background: Color(red: 0.25, green: 0.17, blue: 0),
                            foreground: .white,
                            borderColor: .clear,
                            cornerRadius: 8,
                            horizontalPadding: 24,
                            verticalPadding: 12,
                            showOverlayStroke: true
                        )
                        .disabled(isCheckingPermission)
                    case .denied:
                        DayflowSurfaceButton(
                            action: openSystemSettings,
                            content: { 
                                Text("Open System Settings")
                                    .font(.custom("Nunito", size: 16))
                                    .fontWeight(.medium)
                            },
                            background: Color(red: 0.25, green: 0.17, blue: 0),
                            foreground: .white,
                            borderColor: .clear,
                            cornerRadius: 8,
                            horizontalPadding: 24,
                            verticalPadding: 12,
                            showOverlayStroke: true
                        )
                    case .granted:
                        EmptyView()
                    }
                }
                .padding(.top, 16)
                
                // Navigation buttons
                HStack(spacing: 16) {
                    DayflowSurfaceButton(
                        action: onBack,
                        content: { Text("Back").font(.custom("Nunito", size: 14)).fontWeight(.semibold) },
                        background: .white,
                        foreground: Color(red: 0.25, green: 0.17, blue: 0),
                        borderColor: .clear,
                        cornerRadius: 8,
                        horizontalPadding: 20,
                        verticalPadding: 12,
                        minWidth: 120,
                        isSecondaryStyle: true
                    )
                    DayflowSurfaceButton(
                        action: { 
                            if permissionState == .granted {
                                onNext()
                            }
                        },
                        content: { Text("Next").font(.custom("Nunito", size: 14)).fontWeight(.semibold) },
                        background: permissionState == .granted ? Color(red: 0.25, green: 0.17, blue: 0) : Color(red: 0.25, green: 0.17, blue: 0).opacity(0.3),
                        foreground: permissionState == .granted ? .white : .white.opacity(0.5),
                        borderColor: .clear,
                        cornerRadius: 8,
                        horizontalPadding: 20,
                        verticalPadding: 12,
                        minWidth: 120,
                        showOverlayStroke: permissionState == .granted
                    )
                    .disabled(permissionState != .granted)
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .frame(maxWidth: 400)
            
            // Right side - image
            if let image = NSImage(named: "ScreenRecordingPermissions") {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 500)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Check permission status using preflight (won't trigger dialog)
            if CGPreflightScreenCaptureAccess() {
                permissionState = .granted
                // Keep termination blocked if already granted
                Task { @MainActor in AppDelegate.allowTermination = false }
            } else {
                permissionState = .denied
                // Allow Quit & Reopen while permission is pending/denied
                Task { @MainActor in AppDelegate.allowTermination = true }
            }
        }
        .onDisappear {
            // Restore default behavior: do not allow termination unless explicit
            Task { @MainActor in AppDelegate.allowTermination = false }
        }
    }
    
    private func checkPermission() {
        guard !isCheckingPermission else { return }
        isCheckingPermission = true
        
        Task {
            do {
                // This is the idiomatic way - try to access content
                // Will trigger system dialog if permission not granted
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                
                // If we get here, permission is granted
                await MainActor.run {
                    permissionState = .granted
                    isCheckingPermission = false
                }
                AnalyticsService.shared.capture("screen_permission_granted")
                // Block termination again now that permission is granted
                await MainActor.run { AppDelegate.allowTermination = false }
            } catch {
                // Permission denied or not granted
                await MainActor.run {
                    permissionState = .denied
                    isCheckingPermission = false
                }
                AnalyticsService.shared.capture("screen_permission_denied")
                // Keep allowing termination for system Quit & Reopen
                await MainActor.run { AppDelegate.allowTermination = true }
            }
        }
    }
    
    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            // Ensure termination is allowed before the user toggles permission
            Task { @MainActor in AppDelegate.allowTermination = true }
            NSWorkspace.shared.open(url)
            // Don't change state - they might not grant permission
            // Keep showing the instructions until they restart
        }
    }
}
