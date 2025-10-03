import SwiftUI
import AppKit

struct DashboardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header (matches Timeline positioning & padding is applied on parent)
            Text("Dashboard")
                .font(.custom("InstrumentSerif-Regular", size: 42))
                .foregroundColor(.black)
                .padding(.leading, 10) // Match Timeline header inset

            // Preview area lives BELOW the dashboard title and within panel padding
            ZStack {
                // Infinite scrolling banner background
                InfiniteScrollingBanner(
                    imageName: "DashboardPreview",
                    speed: 28, // pts/sec
                    direction: .rightToLeft,
                    blurRadius: 2
                )
                .opacity(0.9)
                .allowsHitTesting(false)

                // Centered beta callout card over the preview area only
                VStack(spacing: 10) {
                    Text("This feature is in development. Reach out via the feedback tab if you want to be the first to beta test it!")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)

                    Text("Ask and track answers to any question about your day, such as ‘How many times did I check Twitter today?’, ‘How long did I spend in Figma?’, or ‘What was my longest deep-work block?’")
                        .font(.system(size: 13))
                        .foregroundColor(Color.black.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct InfiniteScrollingBanner: View {
    enum Direction { case leftToRight, rightToLeft }

    let imageName: String
    let speed: CGFloat        // points per second
    let direction: Direction
    let blurRadius: CGFloat

    @State private var startTime: TimeInterval = Date().timeIntervalSinceReferenceDate
    @State private var imageAspect: CGFloat = 2.0 // fallback aspect ratio (w/h)

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let elapsed = max(0, now - startTime)

                // Determine tile size from available height and image aspect ratio
                let h = max(1, geo.size.height)
                let tileW = max(1, h * imageAspect)

                // Compute how many tiles to fully cover width even while shifting
                let visibleW = max(1, geo.size.width)
                let needed = Int(ceil(visibleW / tileW)) + 2

                // Offset that loops per tileW
                let shift = CGFloat(elapsed) * speed
                let phase = shift.truncatingRemainder(dividingBy: tileW)
                let xOffset = (direction == .rightToLeft) ? -phase : phase

                HStack(spacing: 0) {
                    ForEach(0..<max(2, needed), id: \.self) { _ in
                        Image(imageName)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: tileW, height: h)
                            .clipped()
                    }
                }
                .offset(x: xOffset)
                .blur(radius: blurRadius, opaque: true)
            }
        }
        .onAppear {
            startTime = Date().timeIntervalSinceReferenceDate
            if let img = NSImage(named: imageName), img.size.height > 0 {
                imageAspect = img.size.width / img.size.height
            }
        }
        .accessibilityHidden(true)
    }
}
