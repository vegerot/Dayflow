// Views/Timeline/TimelineBodyView.swift
//  AmiTime
//
//  Created by [Your Name] on [Date].
//

import SwiftUI

struct TimelineBodyView: View {
    @ObservedObject var viewModel: TimelineViewModel
    let sidebarWidth: CGFloat = 288 // Updated width from spec

    // Row heights from spec (can be adjusted)
    let subjectsSectionHeaderHeight: CGFloat = 40 // New static "SUBJECTS" row
    let subjectHeaderHeight: CGFloat = 48
    let eventRowHeight: CGFloat = 32
    let eventRowBottomPadding: CGFloat = 4
    var totalEventRowHeight: CGFloat { eventRowHeight + eventRowBottomPadding } // 36

    // Colors from spec
    let borderColor = Color(hex: "#E5E7EB")

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Sidebar Column
            SidebarColumnView(viewModel: viewModel,
                              subjectsSectionHeaderHeight: subjectsSectionHeaderHeight,
                              subjectHeaderHeight: subjectHeaderHeight,
                              eventRowHeight: eventRowHeight,
                              eventRowBottomPadding: eventRowBottomPadding)
                // REMOVE old top padding
                // .padding(.top, subjectHeaderHeight + 1)
                .frame(width: sidebarWidth)
                // Background set by container

            // Custom Divider
            borderColor // Use color directly
                .frame(width: 1)

            // Horizontally scrolling section
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header for time ticks - REMOVE top padding
                    TimelineHeaderView(viewModel: viewModel)
                         // .padding(.top, subjectsSectionHeaderHeight) // REMOVED

                    Divider()

                    // Canvas Content - ADD top padding
                    CanvasContentView(viewModel: viewModel,
                                      subjectsSectionHeaderHeight: subjectsSectionHeaderHeight,
                                      subjectHeaderHeight: subjectHeaderHeight,
                                      eventRowHeight: totalEventRowHeight)
                        .padding(.top, subjectsSectionHeaderHeight) // ADDED padding
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// Helper included here for simplicity
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0; Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count { case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17); case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF); case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF); default: (a, r, g, b) = (255, 0, 0, 0) }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue:  Double(b) / 255, opacity: Double(a) / 255)
    }
}

#Preview {
    TimelineBodyView(viewModel: TimelineViewModel(subjects: PreviewData.subjects))
} 