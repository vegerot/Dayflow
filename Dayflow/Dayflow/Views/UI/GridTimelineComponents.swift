//
//  GridTimelineComponents.swift
//  Dayflow
//
//  Supporting components for the grid timeline view
//

import SwiftUI

// MARK: - Time Column

/// Fixed time column showing hour markers
struct TimeColumnView: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(0..<GridConfig.totalHours, id: \.self) { hourIndex in
                HourMarkerView(hourIndex: hourIndex)
                    .frame(height: GridConfig.rowHeight)
                    .id("hour-\(hourIndex)")
            }
        }
    }
}

/// Individual hour marker in the time column
struct HourMarkerView: View {
    let hourIndex: Int
    
    private var displayHour: Int {
        (GridConfig.startHour + hourIndex) % 24
    }
    
    private var isMajorHour: Bool {
        [6, 12, 18, 0].contains(displayHour)
    }
    
    private var timeString: String {
        if displayHour == 0 {
            return "12 AM"
        } else if displayHour < 12 {
            return "\(displayHour) AM"
        } else if displayHour == 12 {
            return "12 PM"
        } else {
            return "\(displayHour - 12) PM"
        }
    }
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text(timeString)
                    .font(.system(size: isMajorHour ? 13 : 11, weight: isMajorHour ? .medium : .regular))
                    .foregroundColor(isMajorHour ? Color.primary : Color.secondary)
                    .padding(.trailing, 8)
                    // Offset upward by approximately half the text height to align baseline with line
                    .offset(y: isMajorHour ? 6 : 5)
            }
        }
        .frame(height: GridConfig.rowHeight)
    }
}

// MARK: - Grid Background

/// Background grid with hour divider lines
struct GridBackgroundView: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<GridConfig.totalHours, id: \.self) { hourIndex in
                HourRowBackground(hourIndex: hourIndex)
                    .frame(height: GridConfig.rowHeight)
            }
        }
    }
}

/// Individual hour row with divider line
struct HourRowBackground: View {
    let hourIndex: Int
    
    private var displayHour: Int {
        (GridConfig.startHour + hourIndex) % 24
    }
    
    private var isMajorHour: Bool {
        [6, 12, 18, 0].contains(displayHour)
    }
    
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .overlay(
                // Hour divider line at bottom
                Rectangle()
                    .fill(lineColor)
                    .frame(height: lineHeight),
                alignment: .bottom
            )
    }
    
    private var lineColor: Color {
        if isMajorHour {
            return Color.primary.opacity(0.2)
        } else {
            return Color.primary.opacity(0.1)
        }
    }
    
    private var lineHeight: CGFloat {
        isMajorHour ? 1.5 : 0.5
    }
}

// MARK: - Current Time Indicator

/// Red line showing current time position
struct CurrentTimeIndicator: View {
    let yPosition: CGFloat
    @State private var isVisible = true
    @State private var pulseAnimation = false
    
    var body: some View {
        if shouldShowIndicator {
            HStack(spacing: 0) {
                // Red dot at the beginning
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
                
                // Red line across the width
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 2)
                    .opacity(0.8)
            }
            .offset(y: yPosition - 4) // Center the dot on the line
            .onAppear {
                pulseAnimation = true
            }
        }
    }
    
    private var shouldShowIndicator: Bool {
        // Only show if current time is within the grid bounds
        return yPosition >= 0 && yPosition <= GridConfig.gridHeight
    }
}

// MARK: - Empty State

/// Displayed when no activities are present
struct EmptyTimelineView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No activities recorded")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Activities will appear here as you work")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Grid Overlay Helpers

/// Helper view for debugging grid alignment
struct GridDebugOverlay: View {
    var body: some View {
        #if DEBUG
        VStack(spacing: 0) {
            ForEach(0..<GridConfig.totalHours, id: \.self) { hour in
                Rectangle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
                    .frame(height: GridConfig.rowHeight)
                    .overlay(
                        Text("\(hour * 60)px")
                            .font(.caption2)
                            .foregroundColor(.blue.opacity(0.5))
                            .padding(2),
                        alignment: .topLeading
                    )
            }
        }
        #else
        EmptyView()
        #endif
    }
}
