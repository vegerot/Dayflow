import SwiftUI

// Shared card color assets for Canvas look
enum CardColor: String, CaseIterable {
    case blue = "BlueTimelineCard"
    case orange = "OrangeTimelineCard"
    case red = "RedTimelineCard"
}

// Minimal prototype view kept for previews only (data-driven version lives in CanvasTimelineDataView)
struct CanvasTimelineView: View {
    var body: some View {
        Text("Canvas prototype (replaced by CanvasTimelineDataView)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
    }
}

#Preview("Canvas Prototype") {
    CanvasTimelineView()
        .frame(width: 600, height: 400)
}

