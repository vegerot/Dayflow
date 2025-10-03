import SwiftUI

struct JournalView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Journal")
                .font(.custom("InstrumentSerif-Regular", size: 42))
                .foregroundColor(.black)
                .padding(.leading, 10) // Match Timeline header inset

            // Preview area fills the remaining content space (static image)
            ZStack {
                GeometryReader { geo in
                    Image("JournalPreview")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .clipped()
                }

                // Centered white rectangle overlay
                VStack(spacing: 10) {
                    Text("This feature is in development. Reach out via the feedback tab if you want to be the first to beta test it!")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)

                    Text("A narrative overview of how you spent your day, highlighting focus blocks, key apps and sites, context switches, and distractions; perfect for reflection or sharing.")
                        .font(.system(size: 13))
                        .foregroundColor(Color.black.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
