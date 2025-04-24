//
//  ContentView.swift
//  TimelineDemo
//
//  Paste into a vanilla macOS SwiftUI project.
//
import SwiftUI
import AppKit

// MARK: — Demo data -------------------------------------------------------------

struct Subject: Identifiable {
    let id = UUID()
    var title: String
    var rows: Int
}

let demo: [Subject] = [
    .init(title: "Computer Science", rows: 3),
    .init(title: "Geography",        rows: 1),
    .init(title: "Mathematics",      rows: 4),
    .init(title: "Biology",          rows: 2),
    .init(title: "Computer Science", rows: 3),
    .init(title: "Geography",        rows: 1),
    .init(title: "Mathematics",      rows: 4),
    .init(title: "Biology",          rows: 2),
]

// MARK: — Shared constants ------------------------------------------------------

private let sidebarW:  CGFloat = 240
private let headerH:   CGFloat = 36
private let rowH:      CGFloat = 40
private let pxPerMin:  CGFloat = 10         // 1 h = 600 px
private let startMin            = 16 * 60   // 4 PM
private let endMin              = 24 * 60   // midnight -> 8 h span

// MARK: — Scroll-link model -----------------------------------------------------

final class ScrollSync: ObservableObject {
    @Published var x: CGFloat = .zero
    @Published var y: CGFloat = .zero
}

// MARK: — NSScrollView wrapper --------------------------------------------------

struct SyncableScroll<Content: View>: NSViewRepresentable {
    enum Axis { case x, y, both }
    enum Role { case master, follower }
    let axis: Axis
    let role: Role
    @ObservedObject var sync: ScrollSync
    let content: Content
    
    init(_ axis: Axis, role: Role = .master, sync: ScrollSync, @ViewBuilder _ content: () -> Content) {
        self.axis   = axis
        self.role  = role
        self._sync  = ObservedObject(wrappedValue: sync)
        self.content = content()
    }
    
    func makeCoordinator() -> Coord { Coord(sync: sync, role: role) }  // ← updated

    
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller   = false
            scroll.hasHorizontalScroller = false
            scroll.scrollerStyle         = .overlay   // keeps rubber-band physics
        
        // The hosted SwiftUI subtree
        let host = context.coordinator.host
        scroll.documentView = host
        host.translatesAutoresizingMaskIntoConstraints = false
        // Auto-layout → documentView matches content size
        host.topAnchor    .constraint(equalTo: scroll.contentView.topAnchor).isActive = true
        host.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor).isActive = true
        // width/height ≥ clipView so it can grow
        host.widthAnchor .constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor).isActive = true
        host.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true
        scroll.verticalScrollElasticity   = .none
            scroll.horizontalScrollElasticity = .none
        
        // Observe user scrolling
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coord.boundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView)
        if role == .master {
            let pan = NSPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coord.handlePan(_:)))
            pan.buttonMask = 0x1
            scroll.addGestureRecognizer(pan)
        }

        return scroll
    }
    
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // sync → follower
        if axis != .y && scroll.contentView.bounds.origin.x != sync.x {
            scroll.contentView.bounds.origin.x = sync.x
        }
        if axis != .x && scroll.contentView.bounds.origin.y != sync.y {
            scroll.contentView.bounds.origin.y = sync.y
        }
        context.coordinator.host.rootView = AnyView(content)
    }
    
    class Coord: NSObject {

        let role: Role
        let host = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
        @ObservedObject var sync: ScrollSync

        init(sync: ScrollSync, role: Role) {
            self._sync = ObservedObject(wrappedValue: sync)
            self.role  = role
        }

        // ── feedback-loop guard
        private var isProgrammatic = false
        private var dragAnchor     = CGPoint.zero   // origin at .began

        // Called when the user drags with mouse/track-pad
        @objc func handlePan(_ g: NSPanGestureRecognizer) {
            guard role == .master,
                  let scroll = g.view as? NSScrollView else { return }

            switch g.state {

            case .began:
                dragAnchor = scroll.contentView.bounds.origin   // remember start

            case .changed:
                let delta   = g.translation(in: scroll)
                let doc     = scroll.documentView?.frame.size ?? .zero
                let clip    = scroll.contentView.bounds.size

                var newX = dragAnchor.x - delta.x
                var newY = dragAnchor.y - delta.y   

                // clamp inside content
                newX = max(0, min(newX, doc.width  - clip.width))
                newY = max(0, min(newY, doc.height - clip.height))

                // move once → followers will mirror via KVO
                isProgrammatic = true
                scroll.contentView.bounds.origin = CGPoint(x: newX, y: newY)
                isProgrammatic = false

                // publish so SwiftUI invalidates followers
                sync.x = newX
                sync.y = newY

            default:
                break
            }
        }

        // KVO from *any* scroll view
        @objc func boundsChanged(_ n: Notification) {
            guard let clip = n.object as? NSClipView else { return }

            // Suppress echo during programmatic moves
            if isProgrammatic { return }

            // Master publishes; followers read-only
            if role == .master {
                if clip.bounds.origin.x != sync.x { sync.x = clip.bounds.origin.x }
                if clip.bounds.origin.y != sync.y { sync.y = clip.bounds.origin.y }
            } else {
                // follower just mirrors master instantly
                if clip.bounds.origin.x != sync.x || clip.bounds.origin.y != sync.y {
                    isProgrammatic = true
                    clip.bounds.origin = CGPoint(x: sync.x, y: sync.y)
                    isProgrammatic = false
                }
            }
        }
    }

    
    
}

// MARK: — Root view -------------------------------------------------------------

struct ContentView: View {
    @StateObject private var link = ScrollSync()
    @State private var subjects   = demo
    
    var body: some View {
        VStack(spacing: 0) {
            
            // ── Sticky header row ───────────────────────────────────────────
            HStack(spacing: 0) {
                Text("SUBJECTS")
                    .padding(.leading, 12)
                    .font(.caption.weight(.semibold))
                    .frame(width: sidebarW, height: headerH, alignment: .leading)
                    .overlay(alignment: .trailing) {     // ← NEW
                            Divider()                        // vertical hair-line
                        }
                
                SyncableScroll(.x, role: .follower, sync: link) {
                    TimeTicks()
                        .frame(height: headerH)
                }
                .disabled(true)   // follower only
            }
            Divider()
            
            // ── Sidebar + canvas ────────────────────────────────────────────
            HStack(spacing: 0) {
                // sidebar : Y only
                SyncableScroll(.y,role: .follower, sync: link) {
                    Sidebar(subjects: subjects)
                        .frame(width: sidebarW, alignment: .leading)
                }
                
                // canvas : master XY
                SyncableScroll(.both, role: .master, sync: link) {
                    Canvas(subjects: subjects)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

// MARK: — Header ticks -----------------------------------------------------------

struct TimeTicks: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stride(from: startMin, through: endMin, by: 30)), id: \.self) { m in
                Text(label(for: m))
                    .frame(width: 30 * pxPerMin, alignment: .leading)
            }
        }
    }
    private func label(for total: Int) -> String {
        let h = total / 60, m = total % 60
        return String(format: "%d:%02d", h == 24 ? 0 : h, m)
    }
}

// MARK: — Sidebar ---------------------------------------------------------------

struct Sidebar: View {
    let subjects: [Subject]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(subjects) { s in
                Text(s.title)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(height: rowH, alignment: .leading)
                    .padding(.horizontal, 12)
                
                Divider()
                
                // reserve the same vertical space as the canvas rows
                Color.clear
                    .frame(height: CGFloat(s.rows) * rowH)
            }
        }
    }
}

// MARK: — Canvas ----------------------------------------------------------------

struct Canvas: View {
    let subjects: [Subject]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(subjects) { s in
                SubjectLane(subj: s)
                Divider()
            }
        }
        .background(Color(.white))
    }
}

struct SubjectLane: View {
    let subj: Subject
    var body: some View {
        ZStack(alignment: .topLeading) {
            // header spacer (matches sidebar title height)
            Color.clear.frame(height: rowH)
            
            // coloured demo rectangles
            ForEach(0..<subj.rows, id: \.self) { idx in
                let w = CGFloat(15 + idx * 10) * pxPerMin
                let x = CGFloat(20 + idx * 20) * pxPerMin
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.35 + Double(idx) * 0.1))
                    .frame(width: w, height: rowH - 8)
                    .offset(x: x, y: CGFloat(idx) * rowH + 4)
            }
        }
        .frame(
            width: CGFloat(endMin - startMin) * pxPerMin,
            height: CGFloat(subj.rows + 1) * rowH,   // +1 for header spacer
            alignment: .topLeading)
        .contentShape(Rectangle())   // full-row hit area for scrolling
    }
}

// MARK: — Preview ---------------------------------------------------------------

#Preview {
    ContentView()
        .frame(width: 1000, height: 650)
}
