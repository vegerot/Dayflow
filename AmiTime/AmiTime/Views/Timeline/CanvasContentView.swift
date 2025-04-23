// Views/Timeline/CanvasContentView.swift
//  AmiTime
//
//  Created by [Your Name] on [Date].
//

import SwiftUI

// This view contains the actual drawing canvas content (grid + cards)
// It does not handle scrolling itself.
struct CanvasContentView: View {
    @ObservedObject var viewModel: TimelineViewModel

    // Receive constants from parent
    let subjectsSectionHeaderHeight: CGFloat // Height of the static "SUBJECTS" row in sidebar
    let subjectHeaderHeight: CGFloat
    let eventRowHeight: CGFloat // Combined height including padding

    // Calculated total height based on visible rows + static header
    var totalContentHeight: CGFloat {
        var height = subjectsSectionHeaderHeight // Start with static header height
        for item in viewModel.visibleRows {
            switch item {
            case .subject: height += subjectHeaderHeight
            case .event: height += eventRowHeight // Use combined height
            }
        }
        return height
    }

    // Calculated total width based on time range and zoom
    var totalContentWidth: CGFloat {
        let totalDuration = viewModel.totalTimeRangeEnd.timeIntervalSince(viewModel.totalTimeRangeStart)
        return totalDuration / 3600 * viewModel.zoomScale
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background Grid Lines
            drawGridLines()

            // Event Cards Layer
            drawEventCards()
        }
        .frame(width: totalContentWidth, height: totalContentHeight)
        // Note: The vertical offset synchronizing with the sidebar
        // is applied to the PARENT TrackableScrollView in TimelineContainerView
        // So this view itself doesn't need the .offset(y:)
    }

    // Helper function to draw background grid lines
    @ViewBuilder
    private func drawGridLines() -> some View {
        Canvas {
            context, size in
            let hourIncrement = 3600.0 // Seconds in an hour
            let numberOfHours = Int(ceil(viewModel.totalTimeRangeEnd.timeIntervalSince(viewModel.totalTimeRangeStart) / hourIncrement))

            // Vertical hour lines
            for hourIndex in 0...numberOfHours {
                let timeOffset = Double(hourIndex) * hourIncrement
                let xPos = timeOffset / 3600.0 * viewModel.zoomScale
                var path = Path()
                path.move(to: CGPoint(x: xPos, y: 0))
                path.addLine(to: CGPoint(x: xPos, y: size.height))
                context.stroke(path, with: .color(.gray.opacity(0.3)), lineWidth: 1)
            }

            // Horizontal row lines (matching sidebar rows + static header)
            var currentY: CGFloat = subjectsSectionHeaderHeight // Start below static header
            // Draw line after static SUBJECTS header
            var path = Path()
            path.move(to: CGPoint(x: 0, y: currentY))
            path.addLine(to: CGPoint(x: size.width, y: currentY))
            context.stroke(path, with: .color(Color(hex: "#E5E7EB")), lineWidth: 1) // Use border color

            for rowItem in viewModel.visibleRows {
                let rowHeight: CGFloat
                switch rowItem {
                case .subject: rowHeight = subjectHeaderHeight
                case .event: rowHeight = eventRowHeight
                }
                currentY += rowHeight // Move Y down by the height of the current row
                path = Path() // Reset path
                path.move(to: CGPoint(x: 0, y: currentY))
                path.addLine(to: CGPoint(x: size.width, y: currentY))
                // Only draw border after subject rows, matching spec
                if case .subject = rowItem {
                     context.stroke(path, with: .color(Color(hex: "#E5E7EB")), lineWidth: 1)
                }
            }
        }
    }

    // Helper function to draw event cards
    @ViewBuilder
    private func drawEventCards() -> some View {
        ForEach(Array(viewModel.visibleRows.enumerated()), id: \.offset) { index, rowItem in
            if case .event(let event) = rowItem {
                let xPos = calculateXPosition(for: event)
                // Pass static header height to Y calculation
                let yPos = calculateYPosition(forRowIndex: index, staticHeaderHeight: subjectsSectionHeaderHeight)
                let width = calculateWidth(for: event)
                // Base card height on eventRowHeight *before* padding was added
                let cardHeight = eventRowHeight - (4*2) // Spec: 32px height = 4px top + 24px font + 4px bottom. Use 32?
                                                     // Let's try using the base eventRowHeight passed in (which should be 32) minus padding
                let baseEventRowHeight = eventRowHeight - 4 // Assume passed-in is 36
                let finalCardHeight = baseEventRowHeight - 5 // Previous logic, adjust as needed

                TimelineCardView(event: event, subjectColor: viewModel.getSubject(for: event)?.color ?? .gray)
                    .frame(width: width, height: finalCardHeight)
                    // Center card vertically within its row space (top padding 4px)
                    .offset(x: xPos, y: yPos + 4)
            }
        }
    }

    // --- Calculation Helpers ---
    private func calculateXPosition(for event: TimelineEvent) -> CGFloat {
        let timeSinceStart = event.startTime.timeIntervalSince(viewModel.totalTimeRangeStart)
        return CGFloat(timeSinceStart / 3600.0) * viewModel.zoomScale
    }

    private func calculateYPosition(forRowIndex index: Int, staticHeaderHeight: CGFloat) -> CGFloat {
        // Calculate cumulative height of rows before this index, INCLUDING static header
        var yPos: CGFloat = staticHeaderHeight // Start below static header
        for i in 0..<index {
            let rowItem = viewModel.visibleRows[i]
            switch rowItem {
            case .subject: yPos += subjectHeaderHeight
            case .event: yPos += eventRowHeight // Use combined height
            }
        }
        return yPos
    }

    private func calculateWidth(for event: TimelineEvent) -> CGFloat {
        let durationInSeconds = event.duration
        return max(CGFloat(durationInSeconds / 3600.0) * viewModel.zoomScale, 2) // Ensure minimum width
    }
}

#Preview {
    ScrollView([.horizontal, .vertical]) { // Add vertical scroll for preview
         CanvasContentView(viewModel: TimelineViewModel(subjects: PreviewData.subjects),
                           subjectsSectionHeaderHeight: 40,
                           subjectHeaderHeight: 48,
                           eventRowHeight: 36) // Pass combined height (32 + 4 padding)
    }
} 