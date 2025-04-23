// Views/Timeline/SidebarColumnView.swift
//  AmiTime
//
//  Created by [Your Name] on [Date].
//

import SwiftUI

struct SidebarColumnView: View {
    @ObservedObject var viewModel: TimelineViewModel

    // Receive constants from parent
    let subjectsSectionHeaderHeight: CGFloat
    let subjectHeaderHeight: CGFloat
    let eventRowHeight: CGFloat
    let eventRowBottomPadding: CGFloat

    // Constants (specific to this view)
    let horizontalPadding: CGFloat = 16
    let indentWidth: CGFloat = 40 // spec says 40px

    // Colors from spec
    let subjectsHeaderColor = Color(hex: "#6B7280")
    let borderColor = Color(hex: "#E5E7EB")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { // Use VStack to add horizontal padding easily
            // Static "SUBJECTS" header
            Text("SUBJECTS")
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.5) // Letter spacing
                .foregroundColor(subjectsHeaderColor)
                .frame(height: subjectsSectionHeaderHeight, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .leading) // Ensure it takes full width for border
                .padding(.horizontal, horizontalPadding)
                .overlay(Rectangle().frame(height: 1).foregroundColor(borderColor), alignment: .bottom)

            // Dynamic subject rows
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.visibleRows, id: \.id) { rowItem in
                    switch rowItem {
                    case .subject(let subject):
                        SubjectHeaderRow(viewModel: viewModel,
                                           subject: subject,
                                           height: subjectHeaderHeight,
                                           horizontalPadding: horizontalPadding)
                            // No frame height needed here, set in SubjectHeaderRow
                            // Add bottom border within the row view
                    case .event(let event):
                        EventRow(event: event,
                                 height: eventRowHeight,
                                 indent: indentWidth)
                            .padding(.bottom, eventRowBottomPadding) // Add bottom padding per spec
                            // No frame height needed here, set in EventRow
                            // Horizontal padding applied by parent VStack
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Row Subviews

struct SubjectHeaderRow: View {
    @ObservedObject var viewModel: TimelineViewModel
    let subject: Subject
    let height: CGFloat
    let horizontalPadding: CGFloat

    // Colors & Specs
    let iconSize: CGFloat = 20
    let iconTextGap: CGFloat = 8
    let chevronSize: CGFloat = 24
    let labelColor = Color(hex: "#111827")
    let borderColor = Color(hex: "#E5E7EB")

    var body: some View {
        HStack(spacing: iconTextGap) {
            // Icon
            Text(subject.icon ?? "")
                .frame(width: iconSize, height: iconSize)
            // Label
            Text(subject.name)
                 .font(.system(size: 16, weight: .semibold))
                 .foregroundColor(labelColor)

            Spacer()
            // Chevron
            Image(systemName: viewModel.expandedSubjectIDs.contains(subject.id) ? "chevron.down" : "chevron.right")
                .foregroundColor(.secondary)
                .frame(width: chevronSize, height: chevronSize)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
        .background(.white)
        .contentShape(Rectangle())
        .overlay(Rectangle().frame(height: 1).foregroundColor(borderColor), alignment: .bottom) // Bottom border
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                 viewModel.toggleSubjectExpansion(subjectID: subject.id)
            }
        }
    }
}

struct EventRow: View {
    let event: TimelineEvent
    let height: CGFloat
    let indent: CGFloat

    // Colors & Specs
    let textColor = Color(hex: "#6B7280")
    let timestampPadding: CGFloat = 16

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }()

    var body: some View {
        HStack { // Use space-between equivalent via Spacer
            // Task Text
            Text(event.title)
                 .font(.system(size: 14, weight: .regular))
                 .foregroundColor(textColor)

            Spacer()
            // Timestamp
            Text(event.startTime, formatter: Self.timeFormatter)
                 .font(.system(size: 14, weight: .regular))
                 .foregroundColor(textColor)
                 .padding(.trailing, timestampPadding) // Align to right edge considering parent padding
        }
        .padding(.leading, indent) // Apply indent here
        .frame(height: height)
        // No background needed, inherits from container
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
         SidebarColumnView(viewModel: TimelineViewModel(subjects: PreviewData.subjects),
                           subjectsSectionHeaderHeight: 40,
                           subjectHeaderHeight: 48,
                           eventRowHeight: 32,
                           eventRowBottomPadding: 4)
    }
    .frame(width: 288)
} 