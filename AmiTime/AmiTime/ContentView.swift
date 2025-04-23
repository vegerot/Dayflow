//
//  ContentView.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/20/25.
//

import SwiftUI

struct ContentView: View {
    // The single source of truth for timeline data and state
    @StateObject private var viewModel = TimelineViewModel(subjects: PreviewData.subjects)

    var body: some View {
        // Replace the old NavigationSplitView with the new TimelineContainerView
        TimelineContainerView(viewModel: viewModel)
    }
}

#Preview {
    ContentView()
}
