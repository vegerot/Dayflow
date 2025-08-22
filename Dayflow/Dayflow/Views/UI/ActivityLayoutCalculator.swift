//
//  ActivityLayoutCalculator.swift
//  Dayflow
//
//  Handles grid positioning calculations for timeline activities
//

import Foundation
import SwiftUI

/// Calculates grid positions and handles overlap detection for timeline activities
struct ActivityLayoutCalculator {
    
    // MARK: - Main Layout Method
    
    /// Arranges activities into grid positions with column assignments for overlaps
    static func arrangeActivities(
        _ activities: [TimelineActivity],
        containerWidth: CGFloat,
        selectedDate: Date
    ) -> [GridPositionedActivity] {
        guard !activities.isEmpty else { return [] }
        
        // Sort activities by start time
        let sortedActivities = activities.sorted { $0.startTime < $1.startTime }
        
        // Group overlapping activities
        let overlapGroups = findOverlappingGroups(sortedActivities)
        
        // Calculate positions for each group
        var result: [GridPositionedActivity] = []
        for group in overlapGroups {
            let groupPositions = positionGroup(group, containerWidth: containerWidth, selectedDate: selectedDate)
            result.append(contentsOf: groupPositions)
        }
        
        return result
    }
    
    // MARK: - Overlap Detection
    
    /// Groups activities that overlap in time
    private static func findOverlappingGroups(_ activities: [TimelineActivity]) -> [[TimelineActivity]] {
        var groups: [[TimelineActivity]] = []
        var currentGroup: [TimelineActivity] = []
        var groupEndTime = Date.distantPast
        
        for activity in activities {
            if activity.startTime >= groupEndTime {
                // Start new group
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                }
                currentGroup = [activity]
                groupEndTime = activity.endTime
            } else {
                // Add to current group and extend end time if needed
                currentGroup.append(activity)
                groupEndTime = max(groupEndTime, activity.endTime)
            }
        }
        
        // Add final group
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }
        
        return groups
    }
    
    // MARK: - Column Assignment
    
    /// Positions a group of overlapping activities into columns
    private static func positionGroup(
        _ group: [TimelineActivity],
        containerWidth: CGFloat,
        selectedDate: Date
    ) -> [GridPositionedActivity] {
        // Use column-based approach for overlapping activities
        var columns: [ActivityColumn] = []
        var result: [GridPositionedActivity] = []
        
        for activity in group {
            // Find first available column
            var columnIndex = -1
            for (index, var column) in columns.enumerated() {
                if column.canFit(activity) {
                    column.add(activity)
                    columns[index] = column
                    columnIndex = index
                    break
                }
            }
            
            // Create new column if needed
            if columnIndex == -1 {
                var newColumn = ActivityColumn()
                newColumn.add(activity)
                columns.append(newColumn)
                columnIndex = columns.count - 1
            }
            
            // Calculate position for this activity
            let totalColumns = min(columns.count, GridConfig.maxColumns)
            let positioned = calculatePosition(
                for: activity,
                column: columnIndex,
                totalColumns: totalColumns,
                containerWidth: containerWidth,
                selectedDate: selectedDate
            )
            result.append(positioned)
        }
        
        // Adjust positions if we have more than maxColumns
        if columns.count > GridConfig.maxColumns {
            result = compressColumns(result, targetColumns: GridConfig.maxColumns)
        }
        
        return result
    }
    
    // MARK: - Position Calculations
    
    /// Calculates the exact grid position for an activity
    private static func calculatePosition(
        for activity: TimelineActivity,
        column: Int,
        totalColumns: Int,
        containerWidth: CGFloat,
        selectedDate: Date
    ) -> GridPositionedActivity {
        // Calculate Y position (minutes since 4 AM)
        let yPos = calculateYPosition(for: activity.startTime, relativeTo: selectedDate)
        
        // Calculate height
        let height = calculateHeight(for: activity)
        
        // Guard against division by zero
        guard totalColumns > 0 else {
            // Return a default position if no columns
            return GridPositionedActivity(
                activity: activity,
                yPosition: yPos,
                height: height,
                column: 0,
                totalColumns: 1,
                xOffset: GridConfig.timeColumnWidth + GridConfig.columnPadding,
                width: max(100, containerWidth - GridConfig.timeColumnWidth - GridConfig.columnPadding * 2)
            )
        }
        
        // Calculate X position and width
        let availableWidth = max(0, containerWidth - GridConfig.timeColumnWidth)
        let columnWidth = availableWidth / CGFloat(totalColumns)
        let xOffset = GridConfig.timeColumnWidth + (CGFloat(column) * columnWidth) + GridConfig.columnPadding
        let width = max(50, columnWidth - (GridConfig.columnPadding * 2)) // Minimum width of 50px
        
        return GridPositionedActivity(
            activity: activity,
            yPosition: yPos,
            height: height,
            column: column,
            totalColumns: totalColumns,
            xOffset: xOffset,
            width: width
        )
    }
    
    /// Calculates Y position in pixels from top of grid
    static func calculateYPosition(for time: Date, relativeTo selectedDate: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        
        // Calculate hours since 4 AM
        let hoursSince4AM: Int
        if hour >= GridConfig.startHour {
            hoursSince4AM = hour - GridConfig.startHour
        } else {
            // After midnight, before 4 AM
            hoursSince4AM = (24 - GridConfig.startHour) + hour
        }
        
        // Convert to pixels
        let totalMinutes = hoursSince4AM * 60 + minute
        return CGFloat(totalMinutes) * GridConfig.pixelsPerMinute
    }
    
    /// Calculates height in pixels based on duration
    static func calculateHeight(for activity: TimelineActivity) -> CGFloat {
        let durationMinutes = activity.endTime.timeIntervalSince(activity.startTime) / 60
        let height = CGFloat(durationMinutes) * GridConfig.pixelsPerMinute
        return max(height, GridConfig.minActivityHeight)
    }
    
    // MARK: - Column Compression
    
    /// Compresses activities when there are more than maxColumns
    private static func compressColumns(
        _ activities: [GridPositionedActivity],
        targetColumns: Int
    ) -> [GridPositionedActivity] {
        // Guard against division by zero
        guard targetColumns > 0 else { return activities }
        
        return activities.map { activity in
            let compressedColumn = activity.column % targetColumns
            let totalColumns = targetColumns
            
            // Recalculate width and x offset for compressed layout
            let availableWidth = activity.width * CGFloat(activity.totalColumns)
            let columnWidth = availableWidth / CGFloat(totalColumns)
            let xOffset = activity.xOffset - (activity.width * CGFloat(activity.column)) + 
                         (columnWidth * CGFloat(compressedColumn)) + GridConfig.columnPadding
            
            return GridPositionedActivity(
                activity: activity.activity,
                yPosition: activity.yPosition,
                height: activity.height,
                column: compressedColumn,
                totalColumns: totalColumns,
                xOffset: xOffset,
                width: columnWidth - (GridConfig.columnPadding * 2)
            )
        }
    }
    
    // MARK: - Helper Methods
    
    /// Calculates the logical 4 AM start time for a given date
    static func startOf4AM(for date: Date) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        
        // If it's before 4 AM, we're still in yesterday's logical day
        let hour = calendar.component(.hour, from: date)
        if hour < GridConfig.startHour {
            // Safely handle the day component
            if let day = components.day {
                components.day = day - 1
            } else {
                // Fallback: use calendar to subtract a day
                if let adjustedDate = calendar.date(byAdding: .day, value: -1, to: date) {
                    components = calendar.dateComponents([.year, .month, .day], from: adjustedDate)
                }
            }
        }
        
        components.hour = GridConfig.startHour
        components.minute = 0
        components.second = 0
        
        return calendar.date(from: components) ?? date
    }
}