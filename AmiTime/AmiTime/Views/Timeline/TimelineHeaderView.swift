// Views/Timeline/TimelineHeaderView.swift
//  AmiTime
//
//  Created by [Your Name] on [Date].
//

import SwiftUI

struct TimelineHeaderView: View {
    @ObservedObject var viewModel: TimelineViewModel

    // Constants for drawing
    let hourMarkHeight: CGFloat = 10
    let halfHourMarkHeight: CGFloat = 6
    let quarterHourMarkHeight: CGFloat = 4
    let labelSpacing: CGFloat = 150 // Adjust based on desired label frequency and zoom

    var body: some View {
        GeometryReader { geometry in
            let totalDuration = viewModel.totalTimeRangeEnd.timeIntervalSince(viewModel.totalTimeRangeStart)
            let totalWidth = totalDuration / 3600 * viewModel.zoomScale // Total width based on time range and zoom

            // Remove the ScrollView wrapper
            // ZStack now directly holds the background and the Canvas
            ZStack(alignment: .topLeading) {
                // Background for the header area
                Rectangle()
                    .fill(.white)
                    .frame(height: 30) // Fixed height for the header

                // Ticks and Labels layer
                Canvas { context, size in
                    let startHour = Calendar.current.component(.hour, from: viewModel.totalTimeRangeStart)
                    let endHour = Calendar.current.component(.hour, from: viewModel.totalTimeRangeEnd) + 1
                    let totalHours = endHour - startHour

                    for hour in 0..<(totalHours * 4) {
                        let currentTime = Calendar.current.date(byAdding: .minute, value: hour * 15, to: viewModel.totalTimeRangeStart)!
                        let xPos = CGFloat(currentTime.timeIntervalSince(viewModel.totalTimeRangeStart) / 3600) * viewModel.zoomScale
                        let minute = Calendar.current.component(.minute, from: currentTime)
                        var path = Path()
                        var markHeight = quarterHourMarkHeight
                        if minute == 0 { markHeight = hourMarkHeight }
                        else if minute == 30 { markHeight = halfHourMarkHeight }
                        path.move(to: CGPoint(x: xPos, y: size.height - markHeight))
                        path.addLine(to: CGPoint(x: xPos, y: size.height))
                        context.stroke(path, with: .color(.gray), lineWidth: 1)
                        if minute == 0 && xPos >= 0 && xPos <= size.width { // Check if label is roughly visible
                             let hourString = currentTime.formatted(.dateTime.hour())
                             context.draw(Text(hourString).font(.caption).foregroundColor(.secondary),
                                         at: CGPoint(x: xPos + 5, y: size.height - markHeight - 8))
                         }
                    }
                }
                .frame(width: totalWidth, height: 30)
                // ZStack content does NOT get offset anymore, the ZStack itself does

            } // End ZStack
            // Make the ZStack wide enough to contain all ticks
            .frame(width: totalWidth)
            // REMOVE offset - Header now scrolls naturally within parent ScrollView
            // .offset(x: -viewModel.horizontalScrollOffset.x)
            // Clip the ZStack to the bounds provided by GeometryReader
            .clipped()
            // REMOVE overlay - Indicator doesn't make sense if header scrolls with content
            // .overlay(alignment: .bottomLeading) { ... }
        }
        .frame(height: 30) // Ensure GeometryReader takes necessary height
        .background(Color(.windowBackgroundColor)) // Add background to the GeometryReader container
    }
}

#Preview {
    TimelineHeaderView(viewModel: TimelineViewModel(subjects: PreviewData.subjects))
        .padding()
} 