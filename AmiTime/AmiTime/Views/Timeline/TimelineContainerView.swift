// Views/Timeline/TimelineContainerView.swift
//  AmiTime
//
//  Created by [Your Name] on [Date].
//

import SwiftUI

struct TimelineContainerView: View {
    @ObservedObject var viewModel: TimelineViewModel

    // Constants
    let sidebarWidth: CGFloat = 250 // Example fixed width for the sidebar

    var body: some View {
        // Remove the outer VStack, header is now inside TimelineBodyView
        // The main view is now just the vertically trackable scroll view
        TrackableScrollView(.vertical, showsIndicators: true, contentOffset: $viewModel.verticalScrollOffset) {
            TimelineBodyView(viewModel: viewModel)
                 // Apply a negative offset to the body content based on the tracked vertical scroll.
                 .offset(y: -viewModel.verticalScrollOffset.y)
        }
        .clipped() // Ensure content doesn't overflow during scroll calculation
        .frame(minWidth: 600, minHeight: 400)
        .background(.white) // Set main background to white
    }
}

#Preview {
    TimelineContainerView(viewModel: TimelineViewModel(subjects: PreviewData.subjects))
} 
