// Views/Timeline/TimelineCardView.swift
//  AmiTime
//
//  Created by [Your Name] on [Date].
//

import SwiftUI

struct TimelineCardView: View {
    let event: TimelineEvent
    let subjectColor: Color

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(event.color ?? subjectColor)
                .opacity(0.8)

            RoundedRectangle(cornerRadius: 4)
                 .stroke(subjectColor, lineWidth: 1) // Add border with subject color

            HStack(spacing: 4) {
                if let icon = event.icon {
                    Text(icon)
                }
                Text(event.title)
                    .font(.caption)
                     .foregroundColor(.primary) // Use primary color for better contrast on colored bg
                    .lineLimit(1) // Prevent text wrapping
            }
            .padding(.horizontal, 4)
        }
    }
}

#Preview {
    // Get a sample event from PreviewData
    let sampleEvent = PreviewData.subjects.first!.children.first!
    let sampleSubject = PreviewData.subjects.first!

    return TimelineCardView(event: sampleEvent, subjectColor: sampleSubject.color)
        .frame(width: 150, height: 20)
        .padding()
} 