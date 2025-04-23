// Views/TrackableScrollView.swift
//  AmiTime
//
//  Created by [Your Name] on [Date].
//

import SwiftUI

// PreferenceKey to track the scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        // The preference key is set on a GeometryReader inside the ScrollView.
        // We only care about the latest value reported.
        value = nextValue()
    }
}

// A ScrollView that allows tracking its content offset
struct TrackableScrollView<Content: View>: View {
    let axes: Axis.Set
    let showsIndicators: Bool
    @Binding var contentOffset: CGPoint
    let content: Content

    init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, contentOffset: Binding<CGPoint>, @ViewBuilder content: () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self._contentOffset = contentOffset
        self.content = content()
    }

    var body: some View {
        // Remove extra prints
        // let _ = print("[TrackableScrollView] body evaluated for axes: \(axes)")

        ScrollView(axes, showsIndicators: showsIndicators) {
            // Use a background GeometryReader to capture the offset
            GeometryReader { geometry in
                let origin = geometry.frame(in: .named("scrollView")).origin
                // Remove extra prints
                // let _ = print("[TrackableScrollView] GeometryReader reading origin: \(origin)")
                Color.clear
                    .preference(key: ScrollOffsetPreferenceKey.self, value: origin)
            }
            .frame(width: 0, height: 0) // Make the GeometryReader itself take no space

            // The actual scrollable content
            content
        }
        .coordinateSpace(name: "scrollView")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            // Update the binding when the preference key changes
            // Note: Offset is negative of the intuitive scroll amount
            print("[TrackableScrollView] Offset updated: \(offset)") // Keep this one
            contentOffset = offset
        }
    }
}

// MARK: - Preview

struct TrackableScrollView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @State private var offset: CGPoint = .zero

        var body: some View {
            VStack {
                Text("Offset: (\(String(format: "%.1f", -offset.x)), \(String(format: "%.1f", -offset.y)))")
                TrackableScrollView([.vertical, .horizontal], contentOffset: $offset) {
                    VStack {
                        ForEach(0..<50) { i in
                            Text("Row \(i)")
                                .frame(width: 200 + CGFloat(i * 5), height: 30)
                                .background(Color.blue.opacity(0.2))
                        }
                    }
                }
                .border(Color.red)
            }
            .padding()
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
} 