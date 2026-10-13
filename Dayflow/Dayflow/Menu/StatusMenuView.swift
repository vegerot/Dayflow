import SwiftUI

/// The row of pause lengths in the status menu. It's the one custom view in an
/// otherwise standard menu, hosted by `StatusBarController`.
struct StatusMenuPauseStrip: View {
  static let height: CGFloat = 34

  let durations: [PauseDuration]
  let onSelect: (PauseDuration) -> Void

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(durations.enumerated()), id: \.offset) { index, duration in
        if index > 0 {
          Divider().frame(height: 14)
        }
        PauseStripSegment(duration: duration) { onSelect(duration) }
      }
    }
    .padding(2)
    .background(Color.primary.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    // Lines the strip up with the text of the menu items around it.
    .padding(.horizontal, 14)
    .padding(.top, 2)
    .padding(.bottom, 6)
  }
}

private struct PauseStripSegment: View {
  let duration: PauseDuration
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Text(duration.shortLabel)
        .font(.system(size: duration == .indefinite ? 14 : 12, weight: .medium))
        .foregroundStyle(hovering ? .white : .primary)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .background(
          // The same highlight color the system uses for a selected menu item.
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(hovering ? Color(nsColor: .selectedContentBackgroundColor) : .clear)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .accessibilityLabel(
      duration == .indefinite ? String(localized: "Until I Resume") : duration.shortLabel)
  }
}
