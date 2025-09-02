import SwiftUI
import AppKit
import Foundation

// MARK: - Canvas Config (preserve Canvas look)
private struct CanvasConfig {
    static let hourHeight: CGFloat = 120           // 120px per hour (Canvas look)
    static let pixelsPerMinute: CGFloat = 2        // 2px = 1 minute (Canvas look)
    static let timeColumnWidth: CGFloat = 80
    static let startHour: Int = 4                  // 4 AM baseline
    static let endHour: Int = 28                   // 4 AM next day
}

// Positioned activity for Canvas rendering
private struct CanvasPositionedActivity: Identifiable {
    let id: UUID
    let activity: TimelineActivity
    let yPosition: CGFloat
    let height: CGFloat
    let title: String
    let timeLabel: String
    let icon: String
    let color: CardColor
}

// MARK: - Selection Effect Constants (file-local)
private struct SelectionEffectConstants {
    static let shadowRadius: CGFloat = 12
    static let shadowOffset = CGSize(width: 4, height: 4)
    static let blueShadowColor = Color(red: 0.2, green: 0.4, blue: 0.9).opacity(0.3)
    static let orangeShadowColor = Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.3)
    static let redShadowColor = Color(red: 0.9, green: 0.3, blue: 0.3).opacity(0.3)

    static let springResponse: Double = 0.35
    static let springDampingFraction: Double = 0.8
    static let springBlendDuration: Double = 0.1

    static func shadowColor(for cardColor: CardColor) -> Color {
        switch cardColor {
        case .blue: return blueShadowColor
        case .orange: return orangeShadowColor
        case .red: return redShadowColor
        }
    }
}

struct CanvasTimelineDataView: View {
    @Binding var selectedDate: Date
    @Binding var selectedActivity: TimelineActivity?
    @Binding var scrollToNowTick: Int

    @State private var selectedCardId: UUID? = nil
    @State private var positionedActivities: [CanvasPositionedActivity] = []
    @State private var refreshTimer: Timer?

    private let storageManager = StorageManager.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                // Horizontal lines that extend past the vertical separator
                VStack(spacing: 0) {
                    ForEach(0..<(CanvasConfig.endHour - CanvasConfig.startHour), id: \.self) { _ in
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.black.opacity(0.1))
                                .frame(height: 2)
                            Spacer()
                        }
                        .frame(height: CanvasConfig.hourHeight)
                    }
                }
                .padding(.leading, CanvasConfig.timeColumnWidth)

                    // Main content with time labels
                    HStack(spacing: 0) {
                        // Time labels column
                        VStack(spacing: 0) {
                        ForEach(CanvasConfig.startHour..<CanvasConfig.endHour, id: \.self) { hour in
                            Text(formatHour(hour))
                                .font(.system(size: 13))
                                .foregroundColor(Color.gray)
                                .frame(width: CanvasConfig.timeColumnWidth - 12, alignment: .leading)
                                .padding(.leading, 12)
                                .frame(height: CanvasConfig.hourHeight, alignment: .top)
                                .offset(y: -8)
                        }
                    }
                    .frame(width: CanvasConfig.timeColumnWidth)

                        // Main timeline area
                        ZStack(alignment: .topLeading) {
                            Color.clear

                            ForEach(positionedActivities) { item in
                            CanvasActivityCard(
                                icon: item.icon,
                                title: item.title,
                                time: item.timeLabel,
                                height: item.height,
                                cardColor: item.color,
                                isSelected: selectedCardId == item.id,
                                onTap: {
                                    if selectedCardId == item.id {
                                        selectedCardId = nil
                                        selectedActivity = nil
                                    } else {
                                        selectedCardId = item.id
                                        selectedActivity = item.activity
                                    }
                                }
                            )
                            .frame(height: item.height)
                            .offset(y: item.yPosition)
                            }

                            // Invisible anchor near "now" to enable programmatic scroll
                            nowAnchorView()
                                .id("nowAnchor")
                        }
                        .clipped() // Prevent shadows/animations from affecting scroll geometry
                        // Allow timeline column to shrink under narrow widths
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }
                .frame(height: CGFloat(CanvasConfig.endHour - CanvasConfig.startHour) * CanvasConfig.hourHeight)
            }
            .onChange(of: scrollToNowTick) { _ in
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo("nowAnchor", anchor: .top)
                }
            }
        }
        .background(Color.white)
        .onAppear {
            loadActivities()
            startRefreshTimer()
        }
        .onDisappear {
            stopRefreshTimer()
        }
        .onChange(of: selectedDate) { _ in
            loadActivities()
        }
    }


    // MARK: - Data Loading and Mapping
    private func loadActivities() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Determine logical date (4 AM boundary)
            var logicalDate = selectedDate
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: selectedDate)
            if hour < 4 {
                logicalDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dayString = formatter.string(from: logicalDate)

            let timelineCards = storageManager.fetchTimelineCards(forDay: dayString)
            let activities = processTimelineCards(timelineCards, for: logicalDate)

            let positioned = activities.map { activity -> CanvasPositionedActivity in
                let y = calculateYPosition(for: activity.startTime)
                // Preserve Canvas spacing: -4 total (2px top + 2px bottom)
                let rawHeight = calculateHeight(for: activity)
                let height = max(10, rawHeight - 4)

                return CanvasPositionedActivity(
                    id: activity.id,
                    activity: activity,
                    yPosition: y + 2, // 2px top spacing like original Canvas
                    height: height,
                    title: activity.title,
                    timeLabel: formatRange(start: activity.startTime, end: activity.endTime),
                    icon: iconForCategory(activity.category),
                    color: colorForCategory(activity.category)
                )
            }

            DispatchQueue.main.async {
                self.positionedActivities = positioned
            }
        }
    }

    private func processTimelineCards(_ cards: [TimelineCard], for date: Date) -> [TimelineActivity] {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")

        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: date)

        return cards.compactMap { card -> TimelineActivity? in
            guard let startDate = timeFormatter.date(from: card.startTimestamp),
                  let endDate = timeFormatter.date(from: card.endTimestamp) else {
                return nil
            }

            let startComponents = calendar.dateComponents([.hour, .minute], from: startDate)
            let endComponents = calendar.dateComponents([.hour, .minute], from: endDate)

            guard let finalStartDate = calendar.date(
                bySettingHour: startComponents.hour ?? 0,
                minute: startComponents.minute ?? 0,
                second: 0,
                of: baseDate
            ),
            let finalEndDate = calendar.date(
                bySettingHour: endComponents.hour ?? 0,
                minute: endComponents.minute ?? 0,
                second: 0,
                of: baseDate
            ) else { return nil }

            var adjustedStartDate = finalStartDate
            var adjustedEndDate = finalEndDate

            let startHour = calendar.component(.hour, from: finalStartDate)
            if startHour < 4 {
                adjustedStartDate = calendar.date(byAdding: .day, value: 1, to: finalStartDate) ?? finalStartDate
            }

            let endHour = calendar.component(.hour, from: finalEndDate)
            if endHour < 4 {
                adjustedEndDate = calendar.date(byAdding: .day, value: 1, to: finalEndDate) ?? finalEndDate
            }

            if adjustedEndDate < adjustedStartDate {
                adjustedEndDate = calendar.date(byAdding: .day, value: 1, to: adjustedEndDate) ?? adjustedEndDate
            }

            return TimelineActivity(
                startTime: adjustedStartDate,
                endTime: adjustedEndDate,
                title: card.title,
                summary: card.summary,
                detailedSummary: card.detailedSummary,
                category: card.category,
                subcategory: card.subcategory,
                distractions: card.distractions,
                videoSummaryURL: card.videoSummaryURL,
                screenshot: nil
            )
        }
    }

    // MARK: - Timers
    private func startRefreshTimer() {
        stopRefreshTimer()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            loadActivities()
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Positioning Helpers (Canvas scale)
    private func calculateYPosition(for time: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)

        let hoursSince4AM: Int
        if hour >= CanvasConfig.startHour {
            hoursSince4AM = hour - CanvasConfig.startHour
        } else {
            hoursSince4AM = (24 - CanvasConfig.startHour) + hour
        }

        let totalMinutes = hoursSince4AM * 60 + minute
        return CGFloat(totalMinutes) * CanvasConfig.pixelsPerMinute
    }

    private func calculateHeight(for activity: TimelineActivity) -> CGFloat {
        let durationMinutes = activity.endTime.timeIntervalSince(activity.startTime) / 60
        return CGFloat(durationMinutes) * CanvasConfig.pixelsPerMinute
    }

    // MARK: - UI Helpers
    private func formatHour(_ hour: Int) -> String {
        let normalizedHour = hour >= 24 ? hour - 24 : hour
        let adjustedHour = normalizedHour > 12 ? normalizedHour - 12 : (normalizedHour == 0 ? 12 : normalizedHour)
        let period = normalizedHour >= 12 ? "PM" : "AM"
        return "\(adjustedHour):00 \(period)"
    }

    private func formatRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let s = formatter.string(from: start)
        let e = formatter.string(from: end)
        return "\(s) - \(e)"
    }

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "productive work", "work", "research", "coding", "writing", "learning":
            return "🧠"
        case "distraction", "entertainment", "social media":
            return "😑"
        default:
            return "⏰"
        }
    }

    private func colorForCategory(_ category: String) -> CardColor {
        switch category.lowercased() {
        case let cat where cat.contains("work") || cat.contains("productive") || cat.contains("coding") || cat.contains("research"):
            return .blue  // Will map to teal gradient
        case let cat where cat.contains("distraction") || cat.contains("entertainment") || cat.contains("social"):
            return .red   // Will map to terracotta gradient
        case let cat where cat.contains("learning") || cat.contains("studying") || cat.contains("personal"):
            return .orange  // Will map to purple gradient
        default:
            return .orange  // Default warm gray
        }
    }
}

// MARK: - Now Anchor Helper
extension CanvasTimelineDataView {
    // Places a hidden view at a position slightly above "now" so that scrolling reveals "now" plus more below
    @ViewBuilder
    private func nowAnchorView() -> some View {
        let buffer: CGFloat = 200 // pixels of extra space below current time
        let yNow = calculateYPosition(for: Date())
        let anchorY = max(0, yNow - buffer)
        Color.clear
            .frame(height: 1)
            .offset(y: anchorY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Canvas Activity Card (visuals preserved from Canvas)
struct CanvasActivityCard: View {
    let icon: String
    let title: String
    let time: String
    let height: CGFloat
    let cardColor: CardColor
    let isSelected: Bool
    let onTap: () -> Void
    
    // Helper function to get gradient colors based on card type
    private func gradientColors(for color: CardColor) -> [Color] {
        switch color {
        case .blue:
            // Productive work: Soft mint/sage pastels
            return [
                Color(red: 0.85, green: 0.94, blue: 0.90), // #D9F0E5 - Soft mint
                Color(red: 0.90, green: 0.96, blue: 0.93)  // #E5F5ED - Lighter mint
            ]
        case .red:
            // Distractions: Warm peach/coral pastels
            return [
                Color(red: 1.0, green: 0.88, blue: 0.85),  // #FFE0D9 - Soft peach
                Color(red: 1.0, green: 0.92, blue: 0.90)   // #FFEBE5 - Lighter peach
            ]
        case .orange:
            // Learning/Personal: Soft lavender pastels
            return [
                Color(red: 0.92, green: 0.88, blue: 0.95), // #EBE0F2 - Soft lavender
                Color(red: 0.95, green: 0.92, blue: 0.97)  // #F2EBF7 - Lighter lavender
            ]
        }
    }
    
    // Helper function to get border color based on card type
    private func borderColor(for color: CardColor) -> Color {
        switch color {
        case .blue:
            return Color(red: 0.70, green: 0.85, blue: 0.78).opacity(0.5) // Soft mint border
        case .red:
            return Color(red: 0.95, green: 0.75, blue: 0.70).opacity(0.5) // Soft coral border
        case .orange:
            return Color(red: 0.82, green: 0.75, blue: 0.88).opacity(0.5) // Soft lavender border
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(icon)
                .font(.system(size: 16))

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.30))

            Text("• \(time)")
                .font(
                    Font.custom("Nunito", size: 10)
                        .weight(.medium)
                )
                .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.40).opacity(0.8))

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .background(
            LinearGradient(
                colors: gradientColors(for: cardColor),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .overlay(
            Group {
                // Subtle border based on card type
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(borderColor(for: cardColor), lineWidth: 1)

                // Highlight overlay
                LinearGradient(
                    colors: [
                        Color.white.opacity(isSelected ? 0.25 : 0.08),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.15)
                )
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            }
        )
        .shadow(
            color: isSelected ? Color.black.opacity(0.1) : .clear,
            radius: isSelected ? 2 : 0,
            x: 0,
            y: isSelected ? 1 : 0
        )
        .shadow(
            color: isSelected ? SelectionEffectConstants.shadowColor(for: cardColor) : .clear,
            radius: isSelected ? SelectionEffectConstants.shadowRadius : 0,
            x: isSelected ? SelectionEffectConstants.shadowOffset.width : 0,
            y: isSelected ? SelectionEffectConstants.shadowOffset.height : 0
        )
        .brightness(isSelected ? 0.06 : 0.02)
        .offset(y: isSelected ? -2 : 0)
        .zIndex(isSelected ? 10 : 0)
        .animation(
            .interactiveSpring(
                response: SelectionEffectConstants.springResponse,
                dampingFraction: SelectionEffectConstants.springDampingFraction,
                blendDuration: SelectionEffectConstants.springBlendDuration
            ),
            value: isSelected
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}


#Preview("Canvas Timeline Data View") {
    struct PreviewWrapper: View {
        @State private var date = Date()
        @State private var selected: TimelineActivity? = nil
        @State private var tick: Int = 0
        var body: some View {
            CanvasTimelineDataView(selectedDate: $date, selectedActivity: $selected, scrollToNowTick: $tick)
                .frame(width: 800, height: 600)
        }
    }
    return PreviewWrapper()
}
