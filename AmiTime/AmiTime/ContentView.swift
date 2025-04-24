//
//  ContentView.swift
//  TimelineDemo
//
import SwiftUI
import AppKit

// MARK: – Demo data -------------------------------------------------------------

struct Subject: Identifiable {
    let id = UUID()
    var title: String
    var rows: Int
    var isExpanded: Bool = true
}

let demo: [Subject] = [
    .init(title: "Computer Science", rows: 1),
    .init(title: "Geography",        rows: 1),
    .init(title: "Mathematics",      rows: 4),
    .init(title: "Biology",          rows: 2),
    .init(title: "Computer Science", rows: 3),
    .init(title: "Geography",        rows: 1),
    .init(title: "Mathematics",      rows: 4),
    .init(title: "Biology",          rows: 2),
]

// MARK: – Constants -------------------------------------------------------------

private let sidebarW:  CGFloat = 240
private let headerH:   CGFloat = 36
private let rowH:      CGFloat = 40
private let pxPerMin:  CGFloat = 10            // 1 min = 10 px
private let startMin            = 16 * 60      // start at 16:00
private let endMin              = 24 * 60      // midnight
private let scrollerH = NSScroller.scrollerWidth(for: .regular,
                                                 scrollerStyle: .legacy) // ≈15 px

private func timeString(_ total: Int) -> String {
    let h = total / 60, m = total % 60
    return String(format: "%d:%02d", h == 24 ? 0 : h, m)
}

// MARK: – Scroll link model -----------------------------------------------------

final class ScrollSync: ObservableObject {
    @Published var x: CGFloat = .zero
    @Published var y: CGFloat = .zero
}

// MARK: – NSScrollView wrapper --------------------------------------------------

struct SyncableScroll<Content: View>: NSViewRepresentable {
    enum Axis { case x, y, both }
    enum Role { case master, follower }
    let axis: Axis
    let role: Role
    @ObservedObject var sync: ScrollSync
    let content: Content

    init(_ axis: Axis, role: Role = .master, sync: ScrollSync,
         @ViewBuilder _ content: () -> Content) {
        self.axis   = axis
        self.role   = role
        self._sync  = ObservedObject(wrappedValue: sync)
        self.content = content()
    }

    func makeCoordinator() -> Coord { Coord(sync: sync, role: role) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller   = false
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle         = .overlay
        scroll.autohidesScrollers    = true

        // host SwiftUI
        let host = context.coordinator.host
        scroll.documentView = host
        host.translatesAutoresizingMaskIntoConstraints = false
        host.topAnchor    .constraint(equalTo: scroll.contentView.topAnchor).isActive = true
        host.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor).isActive = true
        host.widthAnchor  .constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor).isActive = true
        host.heightAnchor .constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true

        // always-visible horizontal bar for master
        if role == .master && (axis == .x || axis == .both) {
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers    = false
            scroll.scrollerStyle         = .legacy
        }

        // observe bounds
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coord.boundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView)

        // click-and-drag support (but ignore scrollbar knob)
        if role == .master {
            let pan = NSPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coord.handlePan(_:)))
            pan.buttonMask = 0x1
            scroll.contentView.addGestureRecognizer(pan)     //  ← changed line
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
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
        private var isProgrammatic = false
        private var dragAnchor = CGPoint.zero

        @objc func handlePan(_ g: NSPanGestureRecognizer) {
            guard role == .master, let clip = g.view as? NSClipView else { return }
            switch g.state {
            case .began:   dragAnchor = clip.bounds.origin
            case .changed:
                let delta = g.translation(in: clip)
                let doc   = clip.documentView?.frame.size ?? .zero
                let clipS = clip.bounds.size
                var newX = dragAnchor.x - delta.x
                var newY = dragAnchor.y - delta.y
                newX = max(0, min(newX, doc.width  - clipS.width))
                newY = max(0, min(newY, doc.height - clipS.height))
                isProgrammatic = true
                clip.bounds.origin = CGPoint(x: newX, y: newY)
                isProgrammatic = false
                sync.x = newX; sync.y = newY
            default: break
            }
        }

        @objc func boundsChanged(_ n: Notification) {
            guard let clip = n.object as? NSClipView else { return }
            if isProgrammatic { return }
            if role == .master {
                if clip.bounds.origin.x != sync.x { sync.x = clip.bounds.origin.x }
                if clip.bounds.origin.y != sync.y { sync.y = clip.bounds.origin.y }
            } else {
                if clip.bounds.origin.x != sync.x || clip.bounds.origin.y != sync.y {
                    isProgrammatic = true
                    clip.bounds.origin = CGPoint(x: sync.x, y: sync.y)
                    isProgrammatic = false
                }
            }
        }
    }
}

// MARK: – Root view -------------------------------------------------------------

struct ContentView: View {
    @StateObject private var link = ScrollSync()
    @State private var subjects = demo

    var body: some View {
        VStack(spacing: 0) {
            // header
            HStack(spacing: 0) {
                Text("SUBJECTS")
                    .padding(.leading, 12)
                    .font(.caption.weight(.semibold))
                    .frame(width: sidebarW, height: headerH, alignment: .leading)
                    .overlay(alignment: .trailing) { Divider() }
                SyncableScroll(.x, role: .follower, sync: link) {
                    TimeTicks().frame(height: headerH)
                }.disabled(true)
            }.background(Color.white)
            Divider()
            // sidebar + canvas
            HStack(spacing: 0) {
                SyncableScroll(.y, role: .follower, sync: link) {
                    Sidebar(subjects: $subjects)
                        .frame(width: sidebarW, alignment: .leading)
                }
                .overlay(alignment: .trailing) { Divider() }   // ← vertical divider
                SyncableScroll(.both, role: .master, sync: link) {
                    Canvas(subjects: subjects)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

// MARK: – Timeline scale (labels + ticks) --------------------------------------

struct TimeTicks: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            // labels
            HStack(spacing: 0) {
                ForEach(Array(stride(from: startMin, through: endMin, by: 30)), id: \.self) { m in
                    Text(timeString(m))
                        .frame(width: 30 * pxPerMin, alignment: .leading)
                }
            }
            // tick marks
            Path { p in
                for m in stride(from: startMin, through: endMin, by: 10) {
                    let x = CGFloat(m - startMin) * pxPerMin
                    let h: CGFloat = (m % 30 == 0) ? headerH : headerH * 0.5
                    p.move(to: .init(x: x, y: 0))
                    p.addLine(to: .init(x: x, y: h))
                }
            }
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: – Sidebar --------------------------------------------------------------

struct Sidebar: View {
    @Binding var subjects: [Subject]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(subjects.indices, id: \.self) { i in
                let s = subjects[i]
                HStack(spacing: 4) {
                    Image(systemName: s.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text(s.title)
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(height: rowH)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
                .onTapGesture { subjects[i].isExpanded.toggle() }
                Color.clear
                    .frame(height: CGFloat(s.isExpanded ? s.rows : 0) * rowH)
                Divider()
            }
            Color.clear.frame(height: scrollerH)
        }
    }
}

// MARK: – Canvas & cards --------------------------------------------------------

struct Canvas: View {
    let subjects: [Subject]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(subjects) { s in
                SubjectLane(subj: s)
                Divider()
            }
        }
        .background(Color.white)
    }
}

struct TimelineCard: View {
    let idx: Int
    @State private var hover = false
    var body: some View {
        // DEMO geometry – replace with real data later
        let start = startMin + 20 + idx * 20          // minutes since midnight
        let end   = start + 15 + idx * 10
        let w     = CGFloat(end - start) * pxPerMin   // pxPerMin keeps alignment
        let x     = CGFloat(start - startMin) * pxPerMin

        RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor.opacity(0.35 + Double(idx) * 0.1))
            .frame(width: w, height: rowH - 8)
            .offset(x: x, y: CGFloat(idx) * rowH + 4)
            .overlay(
                Text("\(timeString(start)) – \(timeString(end))")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(4)
                    .opacity(hover ? 1 : 0)
            )
            .onHover { hover = $0 }
            .help("\(timeString(start)) – \(timeString(end))")
    }
}

struct SubjectLane: View {
    let subj: Subject
    var body: some View {
        let rows = subj.isExpanded ? subj.rows : 0
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: rowH)          // title spacer
            ForEach(0..<rows, id: \.self) { idx in
                TimelineCard(idx: idx)
            }
        }
        .frame(
            width: CGFloat(endMin - startMin) * pxPerMin,
            height: CGFloat(rows + 1) * rowH,
            alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

// MARK: – Preview --------------------------------------------------------------

#Preview {
    ContentView()
        .frame(width: 1000, height: 650)
}
