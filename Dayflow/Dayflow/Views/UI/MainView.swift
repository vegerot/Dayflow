//
//  MainView.swift
//  Dayflow
//
//  Timeline UI with transparent design
//

import SwiftUI
import AVKit
import AVFoundation

struct MainView: View {
    @State private var selectedIcon: SidebarIcon = .timeline
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var selectedActivity: TimelineActivity? = nil
    @State private var scrollToNowTick: Int = 0
    @ObservedObject private var inactivity = InactivityMonitor.shared
    
    // Animation states for orchestrated entrance - Emil Kowalski principles
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var timelineOffset: CGFloat = -20
    @State private var timelineOpacity: Double = 0
    @State private var sidebarOffset: CGFloat = -30
    @State private var sidebarOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    
    // Track if we've performed the initial scroll to current time
    @State private var didInitialScroll = false
    @State private var previousDate = Date()
    @State private var lastDateNavMethod: String? = nil
    // Minute tick to handle civil-day rollover (header updates + jump to today)
    @State private var dayChangeTimer: Timer? = nil
    @State private var lastObservedCivilDay: String = {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; return fmt.string(from: Date())
    }()
    
    var body: some View {
        // Two-column layout: left logo + sidebar; right white panel with header, filters, timeline
        HStack(alignment: .top, spacing: 0) {
            // Left column: Logo on top, sidebar centered
            VStack(spacing: 0) {
                // Logo area (keeps same animation)
                LogoBadgeView(imageName: "DayflowLogoMainApp", size: 36)
                    .frame(height: 100)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                Spacer(minLength: 0)

                // Sidebar in fixed-width gutter
                VStack {
                    Spacer()
                    SidebarView(selectedIcon: $selectedIcon)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .offset(y: sidebarOffset)
                        .opacity(sidebarOpacity)
                    Spacer()
                }
                Spacer(minLength: 0)
            }
            .frame(width: 100)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxHeight: .infinity)
            .layoutPriority(1)

            // Right column: Main white panel including header + content
            ZStack {
                switch selectedIcon {
                case .settings:
                    SettingsView()
                        .padding(15)
                case .dashboard:
                    DashboardView()
                        .padding(15)
                case .journal:
                    JournalView()
                        .padding(15)
                case .timeline:
                    VStack(alignment: .leading, spacing: 20) {
                        // Header: Timeline title + Date navigation (now inside white panel)
                        HStack {
                            Text("Timeline")
                                .font(.custom("InstrumentSerif-Regular", size: 42))
                                .foregroundColor(.primary)
                                .offset(x: timelineOffset)
                                .opacity(timelineOpacity)

                            Spacer()

                            HStack(spacing: 12) {
                                DayflowCircleButton {
                                    // Go to previous day
                                    let from = selectedDate
                                    let to = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                                    previousDate = selectedDate
                                    selectedDate = to
                                    lastDateNavMethod = "prev"
                                    AnalyticsService.shared.capture("date_navigation", [
                                        "method": "prev",
                    						"from_day": dayString(from),
                                        "to_day": dayString(to)
                                    ])
                                } content: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                                }

                                Button(action: { showDatePicker = true; lastDateNavMethod = "picker" }) {
                                    DayflowPillButton(text: formatDateForDisplay(selectedDate))
                                }
                                .buttonStyle(PlainButtonStyle())

                                DayflowCircleButton {
                                    // Go to next day
                                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                                    if tomorrow <= Date() {
                                        let from = selectedDate
                                        previousDate = selectedDate
                                        selectedDate = tomorrow
                                        lastDateNavMethod = "next"
                                        AnalyticsService.shared.capture("date_navigation", [
                                            "method": "next",
                                            "from_day": dayString(from),
                                            "to_day": dayString(tomorrow)
                                        ])
                                    }
                                } content: {
                                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(tomorrow > Date() ? Color.gray.opacity(0.3) : Color(red: 0.3, green: 0.3, blue: 0.3))
                                }
                            }
                        }
                        .padding(.leading, 10)

                        // Content area: Left (chips + timeline) and Right (summary)
                        GeometryReader { geo in
                            HStack(alignment: .top, spacing: 20) {
                                // Left column: chips row at top, timeline below
                                VStack(alignment: .leading, spacing: 12) {
                                    TabFilterBar()
                                        .padding(.leading, -13) // nudge chips 13px left
                                        .opacity(contentOpacity)

                                    CanvasTimelineDataView(
                                        selectedDate: $selectedDate,
                                        selectedActivity: $selectedActivity,
                                        scrollToNowTick: $scrollToNowTick
                                    )
                                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                                    .opacity(contentOpacity)
                                }
                                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                                // Right column: activity detail card — constrained height with internal scrolling for summary
                                ActivityCard(activity: selectedActivity, maxHeight: geo.size.height, scrollSummary: true)
                                    .frame(minWidth: 260, idealWidth: 380, maxWidth: 420)
                                    .opacity(contentOpacity)
                            }
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                        }
                    }
                    .padding(15)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14.72286, style: .continuous)
                    .fill(Color.white)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14.72286, style: .continuous))
            // No outline stroke — clean white panel
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $selectedDate, isPresented: $showDatePicker)
        }
        .onAppear {
            // screen viewed and initial timeline view
            AnalyticsService.shared.screen("timeline")
            AnalyticsService.shared.capture("timeline_viewed", ["date_bucket": dayString(selectedDate)])
            // Orchestrated entrance animations following Emil Kowalski principles
            // Fast, under 300ms, natural spring motion
            
            // Logo appears first with scale and fade
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0)) {
                logoScale = 1.0
                logoOpacity = 1
            }
            
            // Timeline text slides in from left
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0).delay(0.1)) {
                timelineOffset = 0
                timelineOpacity = 1
            }
            
            // Sidebar slides up
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0).delay(0.15)) {
                sidebarOffset = 0
                sidebarOpacity = 1
            }
            
            // Main content fades in last
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0).delay(0.2)) {
                contentOpacity = 1
            }
            
            // Perform initial scroll to current time on cold start
            if !didInitialScroll {
                performInitialScrollIfNeeded()
            }

            // Start minute-level tick to detect civil-day rollover (midnight)
            startDayChangeTimer()
        }
        // Trigger reset when idle fired and timeline is visible
        .onChange(of: inactivity.pendingReset) { fired in
            if fired, selectedIcon != .settings {
                performIdleResetAndScroll()
                InactivityMonitor.shared.markHandledIfPending()
            }
        }
        .onChange(of: selectedIcon) { newIcon in
            // tab selected + screen viewed
            let tabName: String
            switch newIcon { case .timeline: tabName = "timeline"; case .dashboard: tabName = "dashboard"; case .journal: tabName = "journal"; case .settings: tabName = "settings" }
            AnalyticsService.shared.capture("tab_selected", ["tab": tabName])
            AnalyticsService.shared.screen(tabName)
            if newIcon == .timeline {
                AnalyticsService.shared.capture("timeline_viewed", ["date_bucket": dayString(selectedDate)])
            }
        }
        .onChange(of: selectedDate) { newDate in
            // If changed via picker, emit navigation now
            if let method = lastDateNavMethod, method == "picker" {
                AnalyticsService.shared.capture("date_navigation", [
                    "method": method,
                    "from_day": dayString(previousDate),
                    "to_day": dayString(newDate)
                ])
            }
            previousDate = newDate
            AnalyticsService.shared.capture("timeline_viewed", ["date_bucket": dayString(newDate)])
        }
        .onChange(of: selectedActivity?.id) { _ in
            guard let a = selectedActivity else { return }
            let dur = a.endTime.timeIntervalSince(a.startTime)
            AnalyticsService.shared.capture("activity_card_opened", [
                "activity_type": a.category,
                "duration_bucket": AnalyticsService.shared.secondsBucket(dur),
                "has_video": a.videoSummaryURL != nil
            ])
        }
        // If user returns from Settings and a reset was pending, perform it once
        .onChange(of: selectedIcon) { newIcon in
            if newIcon != .settings, inactivity.pendingReset {
                performIdleResetAndScroll()
                InactivityMonitor.shared.markHandledIfPending()
            }
        }
        .onDisappear {
            // Safety: stop timer if view disappears
            stopDayChangeTimer()
        }
    }
    
    private func formatDateForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today,' MMM d"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday,' MMM d"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "'Tomorrow,' MMM d"
        } else {
            formatter.dateFormat = "E, MMM d"
        }
        
        return formatter.string(from: date)
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Sidebar
enum SidebarIcon: CaseIterable {
    case timeline
    case dashboard
    case journal
    case settings

    var assetName: String? {
        switch self {
        case .timeline: return "TimelineIcon"
        case .dashboard: return "DashboardIcon"
        case .journal: return "JournalIcon"
        case .settings: return nil
        }
    }

    var systemNameFallback: String? {
        switch self {
        case .settings: return "gearshape"
        default: return nil
        }
    }
}

struct SidebarView: View {
    @Binding var selectedIcon: SidebarIcon
    
    var body: some View {
        VStack(alignment: .center, spacing: 10.501) {
            ForEach(SidebarIcon.allCases, id: \.self) { icon in
                SidebarIconButton(
                    icon: icon,
                    isSelected: selectedIcon == icon,
                    action: { selectedIcon = icon }
                )
                .frame(width: 40, height: 40)
            }
        }
        // Outer rounded container removed per design
    }
}

struct SidebarIconButton: View {
    let icon: SidebarIcon
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Image("IconBackground")
                        .resizable()
                        .interpolation(.high)
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                }

                if let asset = icon.assetName {
                    Image(asset)
                        .resizable()
                        .interpolation(.high)
                        .renderingMode(.template)
                        .foregroundColor(isSelected ? Color(hex: "F96E00") : Color(red: 0.6, green: 0.4, blue: 0.3))
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                } else if let sys = icon.systemNameFallback {
                    Image(systemName: sys)
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? Color(hex: "F96E00") : Color(red: 0.6, green: 0.4, blue: 0.3))
                        .frame(width: 40, height: 40)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Tab Filter Bar
struct TabFilterBar: View {
    var body: some View {
        HStack(spacing: 10) {
            // Work
            Button(action: {}) {
                Image("WorkChip")
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 30)
            }
            .buttonStyle(PlainButtonStyle())

            // Personal
            Button(action: {}) {
                Image("PersonalChip")
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 30)
            }
            .buttonStyle(PlainButtonStyle())

            // Distractions
            Button(action: {}) {
                Image("DistractionsChip")
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 30)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()
        }
        .padding(.leading, 15)
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Idle Reset Helpers
extension MainView {
    // MARK: - Civil Day Change Timer
    private func startDayChangeTimer() {
        stopDayChangeTimer()
        dayChangeTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            handleMinuteTickForDayChange()
        }
    }

    private func stopDayChangeTimer() {
        dayChangeTimer?.invalidate()
        dayChangeTimer = nil
    }

    private func handleMinuteTickForDayChange() {
        // Detect civil day rollover regardless of what day user is viewing
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let currentCivilDay = fmt.string(from: Date())
        if currentCivilDay != lastObservedCivilDay {
            lastObservedCivilDay = currentCivilDay

            // Jump to current civil day and re-scroll near now
            selectedDate = Date()
            selectedActivity = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.35)) {
                    scrollToNowTick &+= 1
                }
            }
        }
    }

    private func performIdleResetAndScroll() {
        // Switch to today
        selectedDate = Date()
        // Clear selection
        selectedActivity = nil
        // Nudge timeline to scroll to now after it reloads
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            #if DEBUG
            print("[MainView] performIdleResetAndScroll -> nudging scrollToNowTick")
            #endif
            withAnimation(.easeInOut(duration: 0.35)) {
                scrollToNowTick &+= 1
            }
        }
    }
    
    private func performInitialScrollIfNeeded() {
        // Check all conditions for initial scroll:
        // 1. Timeline is visible (not in settings)
        // 2. No modal is open
        // 3. Selected date is today
        guard selectedIcon != .settings,
              !showDatePicker,
              Calendar.current.isDateInToday(selectedDate) else {
            return
        }
        
        // Mark that we've attempted initial scroll
        didInitialScroll = true
        
        // Wait for layout to settle after animations complete
        // Increased delay to ensure ScrollView is fully ready on cold start
        #if DEBUG
        print("[MainView] performInitialScrollIfNeeded scheduled with 1.5s delay")
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            #if DEBUG
            print("[MainView] performInitialScrollIfNeeded firing -> nudging scrollToNowTick")
            #endif
            withAnimation(.easeInOut(duration: 0.35)) {
                scrollToNowTick &+= 1
            }
        }
    }
}

// MARK: - Activity Card
struct ActivityCard: View {
    let activity: TimelineActivity?
    var maxHeight: CGFloat? = nil
    var scrollSummary: Bool = false
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    var body: some View {
        if let activity = activity {
            VStack(alignment: .leading, spacing: 16) {
                // Header (icon removed by request)
                HStack {
                    Text(activity.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                }
                
                Text("\(timeFormatter.string(from: activity.startTime)) to \(timeFormatter.string(from: activity.endTime))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Video thumbnail placeholder
                if let videoURL = activity.videoSummaryURL {
                    VideoThumbnailView(
                        videoURL: videoURL,
                        title: activity.title,
                        startTime: activity.startTime,
                        endTime: activity.endTime
                    )
                        .id(videoURL)
                        .frame(height: 200)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 200)
                        .overlay(
                            VStack {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text("No video available")
                                    .font(.caption)
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                        )
                }
                
                // Summary section (scrolls internally when constrained)
                Group {
                    if scrollSummary {
                        ScrollView(.vertical, showsIndicators: false) {
                            summaryContent(for: activity)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        summaryContent(for: activity)
                    }
                }
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
            )
            .if(maxHeight != nil) { view in
                view.frame(maxHeight: maxHeight!)
            }
        } else {
            // Empty state
            VStack {
                Spacer()
                Text("Select an activity to view details")
                    .font(.custom("Nunito", size: 15))
                    .fontWeight(.regular)
                    .foregroundColor(.gray.opacity(0.5))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(hex: "E5E5E5"), lineWidth: 1)
            )
            .if(maxHeight != nil) { view in
                view.frame(maxHeight: maxHeight!)
            }
        }
    }

    @ViewBuilder
    private func summaryContent(for activity: TimelineActivity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUMMARY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text(activity.summary)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            if !activity.detailedSummary.isEmpty && activity.detailedSummary != activity.summary {
                Text("DETAILED SUMMARY")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                
                Text(activity.detailedSummary)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private func iconForActivity(_ activity: TimelineActivity) -> String {
        switch activity.category.lowercased() {
        case "productive work", "work":
            return "laptopcomputer" // valid SF Symbol
        case "research", "learning":
            return "book"
        case "personal", "hobbies":
            return "person"
        case "distraction", "entertainment":
            return "play.rectangle.fill"
        default:
            return "circle"
        }
    }
    
    private func colorForActivity(_ activity: TimelineActivity) -> Color {
        switch activity.category.lowercased() {
        case "productive work", "work":
            return .blue
        case "research", "learning":
            return .purple
        case "personal", "hobbies":
            return .green
        case "distraction", "entertainment":
            return .red
        default:
            return .gray
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack {
                Text("\(value)%")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: geometry.size.width * CGFloat(value) / 100, height: 8)
                    }
                }
                .frame(height: 8)
            }
        }
    }
}

// Background view moved to separate file: MainUIBackgroundView.swift
