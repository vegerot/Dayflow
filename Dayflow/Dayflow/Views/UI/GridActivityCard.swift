//
//  GridActivityCard.swift
//  Dayflow
//
//  Activity card component for the grid timeline
//

import SwiftUI

struct GridActivityCard: View {
    let activity: TimelineActivity
    let isSelected: Bool
    let position: GridPositionedActivity
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                // Icon and title
                HStack(spacing: 4) {
                    Text(categoryIcon)
                        .font(.system(size: iconSize))
                    
                    Text(activity.title)
                        .font(.system(size: titleFontSize, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(titleLineLimit)
                        .truncationMode(.tail)
                }
                
                // Time range (only if card is tall enough)
                if shouldShowTimeRange {
                    Text(timeRangeString)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // Summary (only if card is very tall)
                if shouldShowSummary && !activity.summary.isEmpty {
                    Text(activity.summary)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(width: position.width, height: position.height, alignment: .topLeading)
            .background(backgroundView)
            .cornerRadius(6)
            .overlay(borderOverlay)
            .shadow(
                color: shadowColor,
                radius: isHovering ? 3 : 1,
                x: 0,
                y: isHovering ? 2 : 1
            )
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: position.xOffset, y: position.yPosition)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help(tooltipText) // Tooltip on hover
    }
    
    // MARK: - Visual Properties
    
    private var categoryIcon: String {
        switch activity.category.lowercased() {
        case "productive work", "work", "research":
            return "💼"
        case "coding", "programming", "development":
            return "💻"
        case "writing", "documentation":
            return "✍️"
        case "learning", "studying", "reading":
            return "📚"
        case "meeting", "call", "discussion":
            return "🗣️"
        case "break", "rest":
            return "☕"
        case "distraction", "social media":
            return "📱"
        case "entertainment":
            return "🎮"
        case "idle", "idle time":
            return "⏸️"
        default:
            return "📋"
        }
    }
    
    private var backgroundView: some View {
        Group {
            if activity.category.lowercased().contains("idle") {
                // Idle time - dashed border, lighter background
                Color.gray.opacity(0.05)
            } else {
                // Regular activities with gradient based on category
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
    
    private var gradientColors: [Color] {
        switch activity.category.lowercased() {
        case let cat where cat.contains("work") || cat.contains("productive"):
            return [Color.blue.opacity(0.15), Color.blue.opacity(0.08)]
        case let cat where cat.contains("coding") || cat.contains("programming"):
            return [Color.purple.opacity(0.15), Color.purple.opacity(0.08)]
        case let cat where cat.contains("meeting") || cat.contains("call"):
            return [Color.green.opacity(0.15), Color.green.opacity(0.08)]
        case let cat where cat.contains("learning") || cat.contains("studying"):
            return [Color.orange.opacity(0.15), Color.orange.opacity(0.08)]
        case let cat where cat.contains("distraction") || cat.contains("entertainment"):
            return [Color.pink.opacity(0.15), Color.pink.opacity(0.08)]
        case let cat where cat.contains("break") || cat.contains("rest"):
            return [Color.teal.opacity(0.15), Color.teal.opacity(0.08)]
        default:
            return [Color.gray.opacity(0.1), Color.gray.opacity(0.05)]
        }
    }
    
    private var borderOverlay: some View {
        Group {
            if isSelected {
                // Selected state - orange border
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.orange, lineWidth: 2)
            } else if activity.category.lowercased().contains("idle") {
                // Idle time - dashed border
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        Color.gray.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 2])
                    )
            } else {
                // Normal state - subtle border
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
            }
        }
    }
    
    private var shadowColor: Color {
        if isSelected {
            return Color.orange.opacity(0.3)
        } else if isHovering {
            return Color.black.opacity(0.15)
        } else {
            return Color.black.opacity(0.05)
        }
    }
    
    // MARK: - Layout Calculations
    
    private var iconSize: CGFloat {
        if position.height < 20 {
            return 10
        } else if position.height < 40 {
            return 12
        } else {
            return 14
        }
    }
    
    private var titleFontSize: CGFloat {
        if position.height < 20 {
            return 10
        } else if position.height < 40 {
            return 11
        } else {
            return 12
        }
    }
    
    private var titleLineLimit: Int {
        if position.height < 30 {
            return 1
        } else if position.height < 60 {
            return 2
        } else {
            return 3
        }
    }
    
    private var shouldShowTimeRange: Bool {
        position.height >= 35
    }
    
    private var shouldShowSummary: Bool {
        position.height >= 80
    }
    
    private var horizontalPadding: CGFloat {
        position.width < 100 ? 4 : 8
    }
    
    private var verticalPadding: CGFloat {
        if position.height < 20 {
            return 2
        } else if position.height < 40 {
            return 4
        } else {
            return 6
        }
    }
    
    // MARK: - Text Generation
    
    private var timeRangeString: String {
        let startStr = timeFormatter.string(from: activity.startTime)
        let endStr = timeFormatter.string(from: activity.endTime)
        
        // Shorten if width is constrained
        if position.width < 120 {
            // Just show start time for narrow cards
            return startStr
        } else {
            return "\(startStr) - \(endStr)"
        }
    }
    
    private var tooltipText: String {
        let duration = activity.endTime.timeIntervalSince(activity.startTime) / 60
        let durationStr = String(format: "%.0f min", duration)
        
        var tooltip = "\(activity.title)\n"
        tooltip += "\(timeFormatter.string(from: activity.startTime)) - \(timeFormatter.string(from: activity.endTime))\n"
        tooltip += "Duration: \(durationStr)\n"
        tooltip += "Category: \(activity.category)"
        
        if !activity.summary.isEmpty {
            tooltip += "\n\n\(activity.summary)"
        }
        
        return tooltip
    }
}