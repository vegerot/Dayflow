import SwiftUI
import AppKit
import Foundation

// MARK: - Card Color Enum
enum CardColor: String, CaseIterable {
    case blue = "BlueTimelineCard"
    case orange = "OrangeTimelineCard"
    case red = "RedTimelineCard"
    case idle = "IdleCard"
}

// MARK: - Canvas Config (preserve Canvas look)
private struct CanvasConfig {
    static let hourHeight: CGFloat = 120           // 120px per hour (Canvas look)
    static let pixelsPerMinute: CGFloat = 2        // 2px = 1 minute (Canvas look)
    static let timeColumnWidth: CGFloat = 60
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
    let color: CardColor
    let faviconPrimaryHost: String?
    let faviconSecondaryHost: String?
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
        case .idle: return Color.gray.opacity(0.2) // Subtle shadow for idle
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
    @State private var didInitialScrollInView: Bool = false

    private let storageManager = StorageManager.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                // Place anchor at ScrollView content level for reliable targeting
                ZStack(alignment: .topLeading) {
                    // White background for the entire content area
                    Color.white
                    // Invisible anchor positioned for "now" scroll target
                    nowAnchorView()
                        .zIndex(-1) // Behind other content
                    
                    // Main content ZStack
                // Horizontal lines that extend past the vertical separator
                VStack(spacing: 0) {
                    ForEach(0..<(CanvasConfig.endHour - CanvasConfig.startHour), id: \.self) { _ in
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color(hex: "E5E4E4"))
                                .frame(height: 1)
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
                            let hourIndex = hour - CanvasConfig.startHour
                            Text(formatHour(hour))
                                .font(.custom("Figtree", size: 13))
                                .foregroundColor(Color(hex: "594838"))
                                .padding(.trailing, 5)
                                .frame(width: CanvasConfig.timeColumnWidth, alignment: .trailing)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.95)
                                .allowsTightening(true)
                                .frame(height: CanvasConfig.hourHeight, alignment: .top)
                                .offset(y: -8)
                                .id("hour-\(hourIndex)")
                        }
                    }
                    .frame(width: CanvasConfig.timeColumnWidth)

                        // Main timeline area
                        ZStack(alignment: .topLeading) {
                            Color.clear

                            ForEach(positionedActivities) { item in
                            CanvasActivityCard(
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
                                },
                                faviconPrimaryHost: item.faviconPrimaryHost,
                                faviconSecondaryHost: item.faviconSecondaryHost
                            )
                            .frame(height: item.height)
                            .offset(y: item.yPosition)
                            }

                        }
                        .clipped() // Prevent shadows/animations from affecting scroll geometry
                        // Allow timeline column to shrink under narrow widths
                        .frame(minWidth: 0, maxWidth: .infinity)
                    }
                }
                .frame(height: CGFloat(CanvasConfig.endHour - CanvasConfig.startHour) * CanvasConfig.hourHeight)
                .background(Color.white)
            }
            .background(Color.white)
            // Respond to external scroll nudges (initial or idle-triggered)
            .onChange(of: scrollToNowTick) { _ in
                // Calculate which hour to scroll to for 80% positioning
                let currentHour = Calendar.current.component(.hour, from: Date())
                let hoursSince4AM = currentHour >= 4 ? currentHour - 4 : (24 - 4) + currentHour
                let targetHourIndex = max(0, min(hoursSince4AM, 24) - 2) // 2 hours before current
                
                // Scroll to the hour marker with 30-minute offset for better positioning
                proxy.scrollTo("hour-\(targetHourIndex)", anchor: UnitPoint(x: 0, y: 0.25))
            }
            // Scroll once right after activities are first loaded and laid out
            .onChange(of: positionedActivities.count) { _ in
                guard !didInitialScrollInView, Calendar.current.isDateInToday(selectedDate) else { return }
                didInitialScrollInView = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Calculate which hour to scroll to for 80% positioning
                    let currentHour = Calendar.current.component(.hour, from: Date())
                    let hoursSince4AM = currentHour >= 4 ? currentHour - 4 : (24 - 4) + currentHour
                    let targetHourIndex = max(0, hoursSince4AM - 2) // 2 hours before current for 80% positioning
                    // 30-minute offset: y: 0.25 positions hour 25% down from top
                    proxy.scrollTo("hour-\(targetHourIndex)", anchor: UnitPoint(x: 0, y: 0.25))
                }
            }
            // Ensure we scroll on first appearance when viewing Today
            .onAppear {
                if Calendar.current.isDateInToday(selectedDate) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        // Calculate which hour to scroll to for 80% positioning
                        let currentHour = Calendar.current.component(.hour, from: Date())
                        let hoursSince4AM = currentHour >= 4 ? currentHour - 4 : (24 - 4) + currentHour
                        let targetHourIndex = max(0, hoursSince4AM - 2) // 2 hours before current for 80% positioning
                        // 30-minute offset: y: 0.25 positions hour 25% down from top
                    proxy.scrollTo("hour-\(targetHourIndex)", anchor: UnitPoint(x: 0, y: 0.25))
                    }
                }
            }
            // When the selected date changes back to Today (e.g., after idle), also scroll
            .onChange(of: selectedDate) { newDate in
                if Calendar.current.isDateInToday(newDate) {
                    didInitialScrollInView = false // allow the data-ready scroll to fire again
                    // Give the layout a moment to update before scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            // Calculate which hour to scroll to for 80% positioning
                            let currentHour = Calendar.current.component(.hour, from: Date())
                            let hoursSince4AM = currentHour >= 4 ? currentHour - 4 : (24 - 4) + currentHour
                            let targetHourIndex = max(0, hoursSince4AM - 2) // 2 hours before current for 80% positioning
                            // 30-minute offset: y: 0.25 positions hour 25% down from top
                    proxy.scrollTo("hour-\(targetHourIndex)", anchor: UnitPoint(x: 0, y: 0.25))
                        }
                    }
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

            // Mitigation transform: resolve visual overlaps by trimming larger cards
            // so that smaller cards "win". This is a display-only fix to handle
            // upstream card-generation overlap bugs without touching stored data.
            let segments = resolveOverlapsForDisplay(activities)

            let positioned = segments.map { seg -> CanvasPositionedActivity in
                let y = calculateYPosition(for: seg.start)
                // Preserve Canvas spacing: -4 total (2px top + 2px bottom)
                let durationMinutes = max(0, seg.end.timeIntervalSince(seg.start) / 60)
                let rawHeight = CGFloat(durationMinutes) * CanvasConfig.pixelsPerMinute
                let height = max(10, rawHeight - 4)
                let primaryHost = normalizeHost(seg.activity.appSites?.primary)
                let secondaryHost = normalizeHost(seg.activity.appSites?.secondary)

                return CanvasPositionedActivity(
                    id: seg.activity.id,
                    activity: seg.activity,
                    yPosition: y + 2, // 2px top spacing like original Canvas
                    height: height,
                    title: seg.activity.title,
                    timeLabel: formatRange(start: seg.start, end: seg.end),
                    color: colorForCategory(seg.activity.category),
                    faviconPrimaryHost: primaryHost,
                    faviconSecondaryHost: secondaryHost
                )
            }

            DispatchQueue.main.async {
                self.positionedActivities = positioned
            }
        }
    }

    // Normalize a domain or URL-like string to just the host
    private func normalizeHost(_ site: String?) -> String? {
        guard var site = site, !site.isEmpty else { return nil }
        site = site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: site), url.host != nil {
            return url.host
        }
        if site.contains("://") {
            if let url = URL(string: site), let host = url.host { return host }
        } else if site.contains("/") {
            if let url = URL(string: "https://" + site), let host = url.host { return host }
        } else {
            return site
        }
        return nil
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
                screenshot: nil,
                appSites: card.appSites
            )
        }
    }

    // MARK: - Overlap Resolution (Display-only)
    // Trims larger overlapping cards so smaller cards keep their full range.
    // This is a mitigation transform for occasional upstream timeline card overlap bugs.
    private struct DisplaySegment {
        let activity: TimelineActivity
        var start: Date
        var end: Date
    }

    private func resolveOverlapsForDisplay(_ activities: [TimelineActivity]) -> [DisplaySegment] {
        // Start with raw segments mirroring activity times
        var segments = activities.map { DisplaySegment(activity: $0, start: $0.startTime, end: $0.endTime) }
        guard segments.count > 1 else { return segments }

        // Sort by start time for deterministic processing
        segments.sort { $0.start < $1.start }

        // Iteratively resolve overlaps until stable, with a safety cap
        var changed = true
        var passes = 0
        let maxPasses = 8
        while changed && passes < maxPasses {
            changed = false
            passes += 1

            // Compare each pair that could overlap (sweep-style)
            var i = 0
            while i < segments.count {
                var j = i + 1
                while j < segments.count {
                    // Early exit if no chance to overlap (since sorted by start)
                    if segments[j].start >= segments[i].end { break }

                    // Compute overlap window
                    let s1 = segments[i]
                    let s2 = segments[j]
                    let overlapStart = max(s1.start, s2.start)
                    let overlapEnd = min(s1.end, s2.end)

                    if overlapEnd > overlapStart {
                        // There is overlap — decide small vs big by duration
                        let d1 = s1.end.timeIntervalSince(s1.start)
                        let d2 = s2.end.timeIntervalSince(s2.start)
                        let smallIdx = d1 <= d2 ? i : j
                        let bigIdx   = d1 <= d2 ? j : i

                        // Reload references after indices chosen
                        let small = segments[smallIdx]
                        var big = segments[bigIdx]

                        // Cases
                        if big.start < small.start && small.end < big.end {
                            // Small fully inside big — keep the longer side of big
                            let left  = small.start.timeIntervalSince(big.start)
                            let right = big.end.timeIntervalSince(small.end)
                            if right >= left {
                                big.start = small.end
                            } else {
                                big.end = small.start
                            }
                        } else if small.start <= big.start && big.start < small.end {
                            // Overlap at big start — trim big.start to small.end
                            big.start = small.end
                        } else if small.start < big.end && big.end <= small.end {
                            // Overlap at big end — trim big.end to small.start
                            big.end = small.start
                        }

                        // Validate and apply change
                        if big.end <= big.start {
                            // Trimmed away — remove big
                            segments.remove(at: bigIdx)
                            changed = true
                            // Restart inner loop from j = i+1 since indices shifted
                            j = i + 1
                            continue
                        } else if big.start != segments[bigIdx].start || big.end != segments[bigIdx].end {
                            segments[bigIdx] = big
                            changed = true
                            // Resort local order if start changed
                            segments.sort { $0.start < $1.start }
                            // Restart scanning from current i
                            j = i + 1
                            continue
                        }
                    }
                    j += 1
                }
                i += 1
            }
        }

        return segments
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


    private func colorForCategory(_ category: String) -> CardColor {
        let key = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "work":
            return .orange   // Work → Orange
        case "personal":
            return .blue     // Personal → Blue
        case "distraction":
            return .red
        case "idle", "idle time":
            return .idle     // Idle → Gray dotted border
        default:
            // If upstream sends unexpected labels, keep a safe default
            return .orange
        }
    }
}

// MARK: - Now Anchor Helper
extension CanvasTimelineDataView {
    // Places a hidden view at a position slightly above "now" so that scrolling reveals "now" plus more below
    @ViewBuilder
    private func nowAnchorView() -> some View {
        // Position anchor ABOVE current time for 80% down viewport positioning
        let yNow = calculateYPosition(for: Date())
        
        // Place anchor ~6 hours above current time
        // When scrolled to .top, this positions current time at ~80% down the viewport  
        // Adjust hoursAbove to fine-tune: 5 = current time appears higher, 7 = lower
        let hoursAbove: CGFloat = 6
        let anchorY = yNow - (hoursAbove * CanvasConfig.hourHeight)
        
        // Create a frame that spans the full timeline height
        // Then position the anchor absolutely within it
        Color.clear
            .frame(width: 1, height: CGFloat(CanvasConfig.endHour - CanvasConfig.startHour) * CanvasConfig.hourHeight)
            .overlay(
                Rectangle()
                    .fill(Color.red.opacity(0.001))
                    .frame(width: 10, height: 20)
                    .position(x: 5, y: anchorY)
                    .id("nowAnchor"),
                alignment: .topLeading
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Hour Index Helper
extension CanvasTimelineDataView {
    fileprivate func currentHourIndex() -> Int {
        let cal = Calendar.current
        let h = cal.component(.hour, from: Date())
        let idx: Int
        if h >= CanvasConfig.startHour {
            idx = h - CanvasConfig.startHour
        } else {
            idx = (24 - CanvasConfig.startHour) + h
        }
        return max(0, min(idx, (CanvasConfig.endHour - CanvasConfig.startHour) - 1))
    }
}

// MARK: - Canvas Activity Card (visuals preserved from Canvas)
struct CanvasActivityCard: View {
    let title: String
    let time: String
    let height: CGFloat
    let cardColor: CardColor
    let isSelected: Bool
    let onTap: () -> Void
    let faviconPrimaryHost: String?
    let faviconSecondaryHost: String?
    
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
        case .idle:
            // Idle: White background (no gradient)
            return [Color.white, Color.white]
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
        case .idle:
            return Color(red: 0.6, green: 0.6, blue: 0.6).opacity(0.8) // Gray border for idle
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Favicon or fallback ✨
            FaviconOrSparkleView(primaryHost: faviconPrimaryHost, secondaryHost: faviconSecondaryHost)
                .frame(width: 16, height: 16)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(cardColor == .idle ? Color.gray : Color(red: 0.25, green: 0.25, blue: 0.30))

            Spacer()

            Text(time)
                .font(
                    Font.custom("Nunito", size: 10)
                        .weight(.medium)
                )
                .foregroundColor(cardColor == .idle ? Color.gray.opacity(0.8) : Color(red: 0.35, green: 0.35, blue: 0.40).opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(
            GeometryReader { geo in
                let size = geo.size
                Group {
                    if cardColor == .idle {
                        // Idle cards: white background only
                        Color.white
                    } else if let imageName = chooseBackgroundImageName(for: cardColor, cardSize: size),
                       let nsImg = NSImage(named: imageName) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: size.width, height: size.height)
                            .clipped()
                    } else {
                        LinearGradient(
                            colors: gradientColors(for: cardColor),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            }
        )
        .overlay(
            // Add dotted border for idle cards
            cardColor == .idle ?
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: [4, 4]
                        )
                    )
                    .foregroundColor(borderColor(for: cardColor))
            : nil
        )
        // Remove explicit corner radius and strokes; images include any rounding baked-in
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Background asset selection (aspect‑ratio based)
    private func smallImageName(for color: CardColor) -> String {
        switch color { 
            case .blue: return "BlueCard"
            case .orange: return "OrangeCard"
            case .red: return "RedCard"
            case .idle: return "" // No image for idle cards
        }
    }
    private func largeImageName(for color: CardColor) -> String {
        switch color { 
            case .blue: return "LargeBlueCard"
            case .orange: return "LargeOrangeCard"
            case .red: return "LargeRedCard"
            case .idle: return "" // No image for idle cards
        }
    }

    private func chooseBackgroundImageName(for color: CardColor, cardSize: CGSize) -> String? {
        let small = smallImageName(for: color)
        let large = largeImageName(for: color)

        let cardAR = safeAspect(width: cardSize.width, height: cardSize.height)
        let smallAR = imageAspectRatio(named: small)
        let largeAR = imageAspectRatio(named: large)

        switch (smallAR, largeAR) {
        case let (s?, l?):
            let errS = abs(cardAR - s)
            let errL = abs(cardAR - l)
            return errL < errS ? large : small
        case let (s?, nil):
            return small
        case let (nil, l?):
            return large
        default:
            return nil
        }
    }

    private func safeAspect(width: CGFloat, height: CGFloat) -> CGFloat {
        let w = max(width, 1)
        let h = max(height, 1)
        return w / h
    }

    private static var aspectCache: [String: CGFloat] = [:]
    private func imageAspectRatio(named name: String) -> CGFloat? {
        if let cached = Self.aspectCache[name] { return cached }
        guard let img = NSImage(named: name), img.size.width > 0, img.size.height > 0 else { return nil }
        let ar = img.size.width / img.size.height
        Self.aspectCache[name] = ar
        return ar
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

// MARK: - FaviconOrSparkleView
private struct FaviconOrSparkleView: View {
    let primaryHost: String?
    let secondaryHost: String?
    @State private var image: NSImage? = nil
    @State private var didStart = false

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            } else {
                Text("✨")
                    .font(.system(size: 12))
                    .frame(width: 16, height: 16, alignment: .center)
            }
        }
        .onAppear {
            guard !didStart else { return }
            didStart = true
            Task { @MainActor in
                if let img = await FaviconService.shared.fetchFavicon(primary: primaryHost, secondary: secondaryHost) {
                    self.image = img
                }
            }
        }
    }
}
