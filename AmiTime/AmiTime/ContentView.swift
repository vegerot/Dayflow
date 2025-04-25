//
//  ContentView.swift
//  TimelineDemo
//
import SwiftUI
import AppKit

// MARK: – Data -----------------------------------------------------------------

struct Subject: Identifiable {
    let id = UUID()
    var title: String
    var subs: [String]             // sub-subjects
    var isExpanded: Bool = true
    var rows: Int { subs.count }   // drives canvas height
}

let demo: [Subject] = [
    .init(title: "Computer Science",
          subs: ["Research & Brainstorming", "First Draft", "Presentation Creation"]),
    .init(title: "Geography",   subs: ["Maps"]),
    .init(title: "Mathematics", subs: ["Algebra", "Calc HW", "Video", "Review"]),
    .init(title: "Biology",     subs: ["Lab prep", "Reading"]),
]

// MARK: – Helpers --------------------------------------------------------------

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >>  8) & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: alpha)
    }
}

private let sidebarW:  CGFloat = 240
private let headerH:   CGFloat = 36
private let rowH:      CGFloat = 40
private let pxPerMin:  CGFloat = 10
private let startMin            = 16 * 60
private let endMin              = 24 * 60
private let scrollerH           = NSScroller.scrollerWidth(for: .regular,
                                                           scrollerStyle: .legacy)

private func timeString(_ total: Int) -> String {
    let h = total / 60, m = total % 60
    return String(format: "%d:%02d", h == 24 ? 0 : h, m)
}

// MARK: – Scroll-sync model ----------------------------------------------------

final class ScrollSync: ObservableObject {
    @Published var x: CGFloat = .zero
    @Published var y: CGFloat = .zero
}

// MARK: – NSScrollView wrapper (unchanged) -------------------------------------

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

        let host = context.coordinator.host
        scroll.documentView = host
        host.translatesAutoresizingMaskIntoConstraints = false
        host.topAnchor    .constraint(equalTo: scroll.contentView.topAnchor).isActive = true
        host.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor).isActive = true
        host.widthAnchor  .constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor).isActive = true
        host.heightAnchor .constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true

        if role == .master && (axis == .x || axis == .both) {
            scroll.hasHorizontalScroller = true
            scroll.autohidesScrollers    = false
            scroll.scrollerStyle         = .legacy
        }

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
            scroll.contentView.addGestureRecognizer(pan)
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
            case .began: dragAnchor = clip.bounds.origin
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

            // header (draws its own bottom hair-line)
            HStack(spacing: 0) {
                Text("SUBJECTS")
                    .padding(.leading, 12)
                    .font(.caption.weight(.semibold))
                    .frame(width: sidebarW, height: headerH, alignment: .leading)
                    .overlay(alignment: .trailing) { Divider() }

                SyncableScroll(.x, role: .follower, sync: link) {
                    TimeTicks().frame(height: headerH)
                }.disabled(true)
            }
            .background(Color.white)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 1)
            }

            // sidebar + canvas
            HStack(spacing: 0) {
                SyncableScroll(.y, role: .follower, sync: link) {
                    Sidebar(subjects: $subjects)
                        .frame(width: sidebarW, alignment: .leading)
                }
                .overlay(alignment: .trailing) { Divider() }

                SyncableScroll(.both, role: .master, sync: link) {
                    Canvas(subjects: subjects)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

// MARK: – Time-ticks ------------------------------------------------------------

struct TimeTicks: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(Array(stride(from: startMin, through: endMin, by: 30)), id: \.self) { m in
                    Text(timeString(m))
                        .frame(width: 30 * pxPerMin, alignment: .leading)
                }
            }
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

                // container for one subject ---------------------------------
                VStack(alignment: .leading, spacing: 0) {

                    // parent row
                    HStack(spacing: 4) {
                        Image(systemName: s.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text(s.title)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(height: rowH)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { subjects[i].isExpanded.toggle() }

                    // child rows (no internal dividers)
                    if s.isExpanded {
                        // show every real sub-subject
                                                ForEach(Array(s.subs.enumerated()), id: \.offset) { (j, name) in
                                                    Text("    \(name)")
                                                        .foregroundColor(.secondary)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .padding(.horizontal, 16)
                                                        .frame(height: rowH)
                                                }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // single bottom divider that matches canvas
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 1)
                }
            }
            Color.clear.frame(height: scrollerH)      // footer pad
        }
    }
}

// MARK: – Canvas & cards (unchanged) -------------------------------------------

struct Canvas: View {
    let subjects: [Subject]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(subjects) { s in
                SubjectLane(subj: s)
                    .overlay(alignment: .bottom) {
                                            Rectangle()
                                                .fill(Color.secondary.opacity(0.25))
                                                .frame(height: 1)
                                        }
            }
        }
        .background(Color.white)
    }
}

struct TimelineCard: View {
    let idx: Int
    @State private var hover = false

    var body: some View {
        let start = startMin + 20 + idx * 20
        let end   = start + 15 + idx * 10
        let w     = CGFloat(end - start) * pxPerMin
        let x     = CGFloat(start - startMin) * pxPerMin

        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: 0xD9D9D9), lineWidth: 2)
            )
            .shadow(radius: 1, y: 1)
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
        let rows = subj.isExpanded ? subj.rows : 1
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: rowH)
            ForEach(0..<rows, id: \.self) { idx in
                TimelineCard(idx: idx)
            }
        }
        .frame(
            width: CGFloat(endMin - startMin) * pxPerMin,
            height: subj.isExpanded ? CGFloat(rows + 1) * rowH : rowH,
            alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

// MARK: – Preview --------------------------------------------------------------

#Preview {
    ContentView()
        .frame(width: 1000, height: 650)
}
