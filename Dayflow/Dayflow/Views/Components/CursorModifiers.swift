import SwiftUI

#if os(macOS)
import AppKit

// Overlay-based cursor rect so SwiftUI doesn't override push/pop states
private struct PointingHandCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CursorNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private class CursorNSView: NSView {
        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.invalidateCursorRects(for: self)
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            window?.invalidateCursorRects(for: self)
        }
    }
}

extension View {
    // Shows a pointing hand cursor over the view's bounds.
    // Using an overlay-backed NSView so SwiftUI state changes don't pop our cursor.
    func pointingHandCursor(enabled: Bool = true) -> some View {
        overlay(
            Group {
                if enabled {
                    PointingHandCursorView().allowsHitTesting(false)
                }
            }
        )
    }
}
#endif
