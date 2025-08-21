//
//  TerminalCommandView.swift
//  Dayflow
//
//  Terminal command display with copy functionality
//

import SwiftUI
import AppKit

struct TerminalCommandView: View {
    let title: String
    let subtitle: String
    let command: String
    
    @State private var isCopied = false
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(title)
                .font(.custom("Nunito", size: 16))
                .fontWeight(.semibold)
                .foregroundColor(.black.opacity(0.9))
            
            // Subtitle
            Text(subtitle)
                .font(.custom("Nunito", size: 14))
                .foregroundColor(.black.opacity(0.6))
            
            // Command block with copy button
            HStack(spacing: 0) {
                // Command text area
                Text(command)
                    .font(.custom("SF Mono", size: 13))
                    .foregroundColor(.black.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Copy button
                Button(action: copyCommand) {
                    HStack(spacing: 6) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                        
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.custom("Nunito", size: 13))
                            .fontWeight(.medium)
                    }
                    .foregroundColor(isCopied ? Color(red: 0.34, green: 1, blue: 0.45) : .black.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(isHovered ? 0.9 : 0.7))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovered)
                .onHover { hovering in
                    isHovered = hovering
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .padding(.trailing, 12)
            }
            .background(Color(hex: "F8F9FA"))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private func copyCommand() {
        // Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        
        // Show feedback
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }
        
        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}