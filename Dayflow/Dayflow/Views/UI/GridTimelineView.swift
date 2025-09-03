//
//  GridTimelineView.swift
//  Dayflow
//
//  Google Calendar-style grid timeline view
//

import SwiftUI

struct GridTimelineView: View {
    @Binding var selectedDate: Date
    @Binding var selectedActivity: TimelineActivity?
    @State private var activities: [TimelineActivity] = []
    @State private var positionedActivities: [GridPositionedActivity] = []
    @State private var isLoading = false
    @State private var refreshTimer: Timer?
    @State private var currentTimeY: CGFloat = 0
    @State private var scrollTarget: Int? = nil
    
    private let storageManager = StorageManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Background grid with hour lines
                        GridBackgroundView()
                            .frame(height: GridConfig.gridHeight)
                        
                        HStack(alignment: .top, spacing: 0) {
                            // Time column (fixed 80px)
                            TimeColumnView()
                                .frame(width: GridConfig.timeColumnWidth)
                            
                            // Activity area with current time indicator
                            ZStack(alignment: .topLeading) {
                                // Activities
                                ForEach(positionedActivities) { positioned in
                                    GridActivityCard(
                                        activity: positioned.activity,
                                        isSelected: selectedActivity?.id == positioned.activity.id,
                                        position: positioned
                                    ) {
                                        selectedActivity = positioned.activity
                                    }
                                }
                                
                                // Current time indicator
                                CurrentTimeIndicator(yPosition: currentTimeY)
                                    .frame(width: geometry.size.width - GridConfig.timeColumnWidth)
                            }
                            .frame(width: geometry.size.width - GridConfig.timeColumnWidth)
                        }
                    }
                    .frame(width: geometry.size.width, height: GridConfig.gridHeight)
                    .id("timeline-grid")
                }
                .background(Color.clear)
                .onAppear {
                    loadActivities(containerWidth: geometry.size.width)
                    scrollToCurrentTime(scrollProxy: scrollProxy)
                    startTimers()
                }
                .onDisappear {
                    stopTimers()
                }
                .onChange(of: selectedDate) { _ in
                    loadActivities(containerWidth: geometry.size.width)
                }
                .onChange(of: scrollTarget) { target in
                    if let hourIndex = target {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scrollProxy.scrollTo("hour-\(hourIndex)", anchor: .top)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadActivities(containerWidth: CGFloat) {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Adjust for 4 AM boundary
            var logicalDate = selectedDate
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: selectedDate)
            
            if hour < GridConfig.startHour {
                logicalDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dayString = formatter.string(from: logicalDate)
            
            let timelineCards = storageManager.fetchTimelineCards(forDay: dayString)
            let activities = processTimelineCards(timelineCards, for: logicalDate)
            
            // Calculate grid positions
            let positioned = ActivityLayoutCalculator.arrangeActivities(
                activities,
                containerWidth: containerWidth,
                selectedDate: logicalDate
            )
            
            DispatchQueue.main.async {
                self.activities = activities
                self.positionedActivities = positioned
                self.isLoading = false
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
            ) else {
                return nil
            }
            
            // Handle times based on 4AM boundary
            var adjustedStartDate = finalStartDate
            var adjustedEndDate = finalEndDate
            
            let startHour = calendar.component(.hour, from: finalStartDate)
            let endHour = calendar.component(.hour, from: finalEndDate)
            
            // Check if this is a short activity crossing the 4 AM boundary
            let duration = finalEndDate.timeIntervalSince(finalStartDate)
            let isShortCrossBoundary = (startHour == 3 && endHour == 4 && duration < 7200) // Less than 2 hours
            
            if !isShortCrossBoundary {
                // Normal handling for activities not crossing boundary
                if startHour < GridConfig.startHour {
                    adjustedStartDate = calendar.date(byAdding: .day, value: 1, to: finalStartDate) ?? finalStartDate
                }
                
                if endHour < GridConfig.startHour {
                    adjustedEndDate = calendar.date(byAdding: .day, value: 1, to: finalEndDate) ?? finalEndDate
                }
                
                // Handle case where end time appears before start time
                if adjustedEndDate < adjustedStartDate {
                    adjustedEndDate = calendar.date(byAdding: .day, value: 1, to: adjustedEndDate) ?? adjustedEndDate
                }
            }
            // For short boundary-crossing activities, keep them as-is
            
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
    
    // MARK: - Scrolling
    
    private func scrollToCurrentTime(scrollProxy: ScrollViewProxy) {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        
        // Calculate which hour row to scroll to (showing ~4 hours before current time)
        let targetHour = hour >= GridConfig.startHour ? hour - GridConfig.startHour : hour + 20
        let scrollToHour = max(0, targetHour - 4)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollTarget = scrollToHour
        }
    }
    
    // MARK: - Timer Management
    
    private func startTimers() {
        // Stop any existing timer first
        stopTimers()
        
        // Update current time position
        updateCurrentTimePosition()
        
        // Refresh current time every minute
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            updateCurrentTimePosition()
            
            // Reload activities every 60 seconds to stay current
            if let window = NSApplication.shared.mainWindow,
               let contentView = window.contentView {
                loadActivities(containerWidth: contentView.frame.width)
            }
        }
    }
    
    private func stopTimers() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func updateCurrentTimePosition() {
        let now = Date()
        currentTimeY = ActivityLayoutCalculator.calculateYPosition(for: now, relativeTo: selectedDate)
    }
}

// MARK: - Preview

#Preview("Grid Timeline View") {
    struct PreviewWrapper: View {
        @State private var selectedDate = Date()
        @State private var selectedActivity: TimelineActivity? = nil
        
        var body: some View {
            GridTimelineView(
                selectedDate: $selectedDate,
                selectedActivity: $selectedActivity
            )
            .frame(width: 800, height: 600)
        }
    }
    
    return PreviewWrapper()
}
