//
//  ContentView.swift
//  TimelineDemo
//
//  Drop-in file: only `TimelineCard` changed so long labels
//  spill past the right edge without stretching the card.
//

import SwiftUI
import AppKit

// MARK: – Data -----------------------------------------------------------------

struct Subject: Identifiable {
    let id = UUID()
    var title: String
    var subs: [String]
    var isExpanded: Bool = true
    var rows: Int { subs.count }
}

let demo: [Subject] = [
    .init(title: "Computer Science",
          subs: ["Research & Brainstorming",
                 "First Draft",
                 "Presentation Creation"]),
    .init(title: "Geography",
          subs: ["Maps"]),
    .init(title: "Mathematics",
          subs: ["Algebra",
                 "Calc HW",
                 "Video",
                 "Review"]),
    .init(title: "Biology",
          subs: ["Lab prep",
                 "Reading"]),
]

// MARK: – Zoom model -----------------------------------------------------------

enum Zoom: Int, CaseIterable, Identifiable {
    case h1 = 1, h2, h4 = 4, h8 = 8
    var id: Self { self }
    var label: String { "\(rawValue) h" }
    var pxPerMin: CGFloat {
        switch self {
        case .h1: return 10
        case .h2: return 5
        case .h4: return 2.5
        case .h8: return 1.25
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

private let appBG = Color(hex: 0xFDFDFD)

// MARK: – Helpers --------------------------------------------------------------

private let sidebarW:  CGFloat = 240
private let headerH:   CGFloat = 36
private let rowH:      CGFloat = 40
private let startMin            = 6 * 60     // 06:00
private let endMin              = 27 * 60    // 03:00 next day
private let scrollerH           = NSScroller.scrollerWidth(for: .regular,
                                                           scrollerStyle: .legacy)

@inline(__always) func minutes(at x: CGFloat, pxPerMin: CGFloat) -> Int {
    Int((x / pxPerMin).rounded())
}

private func timeString(_ min: Int) -> String {
    let total = min % (24 * 60)
    let h24   = total / 60
    let m     = total % 60
    let amPM  = h24 < 12 ? "AM" : "PM"
    let h12   = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24)
    return String(format: "%d:%02d %@", h12, m, amPM)
}

// MARK: – Scroll link model ----------------------------------------------------

final class ScrollSync: ObservableObject {
    @Published var x: CGFloat = .zero
    @Published var y: CGFloat = .zero
}

// MARK: – SyncableScroll (unchanged) ------------------------------------------

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
            pan.buttonMask = 0x1   // left mouse
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
    
    // MARK: – Coordinator
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
    @State private var zoom: Zoom = .h4
    @State private var hoverX: CGFloat?

    var body: some View {
        let pxPerMin = zoom.pxPerMin

        VStack(spacing: 0) {
            // header
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("SUBJECTS")
                    Picker("", selection: $zoom) {
                        ForEach(Zoom.allCases) { z in Text(z.label) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .padding(.leading, 12)
                .font(.caption.weight(.semibold))
                .frame(width: sidebarW, height: headerH, alignment: .leading)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 0.5)
                }

                SyncableScroll(.x, role: .follower, sync: link) {
                    TimeScale(pxPerMin: pxPerMin,
                              hoverX: hoverX,
                              startMin: startMin)
                    .frame(height: headerH)
                }
                .disabled(true)
            }
            .background(appBG)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 0.5)
            }

            // sidebar + canvas
            HStack(spacing: 0) {
                SyncableScroll(.y, role: .follower, sync: link) {
                    Sidebar(subjects: $subjects)
                        .frame(width: sidebarW, alignment: .leading)
                }
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 0.5)
                }

                SyncableScroll(.both, role: .master, sync: link) {
                    Canvas(subjects: subjects,
                           pxPerMin: pxPerMin,
                           hoverX: $hoverX)
                }
            }
        }
        .animation(.easeInOut(duration: 0.30), value: zoom)
        .frame(maxWidth: .infinity,
               maxHeight: .infinity,
               alignment: .topLeading)
        .background(appBG)
    }
}

// MARK: – Time scale -----------------------------------------------------------

struct TimeScale: View {
    let pxPerMin: CGFloat
    let hoverX: CGFloat?
    let startMin: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            // ── base hour ticks ───────────────────────────────
            HStack(spacing: 0) {
                ForEach(Array(stride(from: startMin,
                                     through: endMin,
                                     by: 60)), id: \.self) { t in
                    Text(timeString(t))
                        .font(.caption2)
                        .frame(width: 60 * pxPerMin, alignment: .leading)
                }
            }
            
            // ── cursor vertical line & live-time pill ─────────
            if let x = hoverX {
                // hair-line (same tint as canvas)
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 0.5, height: .infinity)
                    .offset(x: x)
                
                // pill label
                let lblMin = startMin + minutes(at: x, pxPerMin: pxPerMin)
                Text(timeString(lblMin))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(appBG)
                            .shadow(radius: 1)
                    )
                    .offset(x: x - 40)   // tweak so it’s centred over the line
            }
        }.background(appBG)
    }
}

// MARK: – Sidebar --------------------------------------------------------------

struct Sidebar: View {
    @Binding var subjects: [Subject]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(subjects.indices, id: \.self) { i in
                let s = subjects[i]
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: s.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text(s.title).font(.system(size: 16, weight: .semibold))
                    }
                    .frame(height: rowH)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { subjects[i].isExpanded.toggle() }
                    
                    if s.isExpanded {
                        ForEach(Array(s.subs.enumerated()), id: \.offset) { (_, name) in
                            Text(name)
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 32)
                                .frame(height: rowH)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 0.5)
                }
            }
            Color.clear.frame(height: scrollerH)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: – Canvas ---------------------------------------------------------------

struct Canvas: View {
    let subjects: [Subject]
    let pxPerMin: CGFloat
    @Binding var hoverX: CGFloat?

    var body: some View {
        ZStack(alignment: .topLeading) {

            // live vertical hair-line
            if let x = hoverX {
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 0.5)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .offset(x: x)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(subjects) { s in
                    SubjectLane(subj: s, pxPerMin: pxPerMin)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.25))
                                .frame(height: 0.5)
                        }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(appBG)
        .background(HoverSensor(hoverX: $hoverX))
    }
}

// MARK: – Hover sensor ---------------------------------------------------------

private struct HoverSensor: NSViewRepresentable {
    @Binding var hoverX: CGFloat?
    func makeCoordinator() -> NSView { TrackingView(hoverX: $hoverX) }
    func makeNSView(context: Context) -> NSView { context.coordinator }
    func updateNSView(_: NSView, context: Context) {}

    final class TrackingView: NSView {
        @Binding var hoverX: CGFloat?
        init(hoverX: Binding<CGFloat?>) {
            self._hoverX = hoverX
            super.init(frame: .zero)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            let opts: NSTrackingArea.Options = [.mouseMoved,
                                                .mouseEnteredAndExited,
                                                .activeInKeyWindow,
                                                .inVisibleRect]
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: opts,
                                           owner: self,
                                           userInfo: nil))
        }
        override func mouseMoved(with e: NSEvent) {
            let loc = convert(e.locationInWindow, from: nil)
            hoverX = max(0, loc.x)
        }
        override func mouseExited(with _: NSEvent) { hoverX = nil }
    }
}

// MARK: – Lanes & cards --------------------------------------------------------

struct SubjectLane: View {
    let subj: Subject
    let pxPerMin: CGFloat
    var body: some View {
        let rows = subj.isExpanded ? subj.rows : 0
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: rowH)
            ForEach(0..<(rows + 1), id: \.self) { idx in
                let label = idx == 0 ? subj.title : subj.subs[idx - 1]
                TimelineCard(idx: idx,
                             pxPerMin: pxPerMin,
                             label: label)
            }
        }
        .frame(width: CGFloat(endMin - startMin) * pxPerMin,
               height: CGFloat(rows + 1) * rowH,
               alignment: .topLeading)
    }
}

struct TimelineCard: View {
    let idx: Int
    let pxPerMin: CGFloat
    let label: String
    @State private var hover = false

    // geometry
    private var start: Int { startMin + 20 + idx * 20 }
    private var end:   Int { start + 15 + idx * 10 }
    private var width: CGFloat { CGFloat(end - start) * pxPerMin }
    private var xOffset: CGFloat { CGFloat(start - startMin) * pxPerMin }

    var body: some View {
        // fixed-size background
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(red: 0.90, green: 0.90, blue: 0.90), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
            .frame(width: width, height: rowH - 8)              // ← card width DOES NOT change
            .overlay(alignment: .leading) {                     // text drawn *on top* of width-locked card
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)                                // no wrapping
                    .fixedSize(horizontal: true, vertical: false) // let it run past right edge
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .offset(x: xOffset, y: CGFloat(idx) * rowH + 4)
            .overlay(                                           // hover time tooltip
                Text("\(timeString(start)) – \(timeString(end))")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(4)
                    .opacity(hover ? 1 : 0)
            )
            .onHover { hover = $0 }
    }
}

// MARK: – Preview --------------------------------------------------------------

#Preview {
    ContentView()
        .frame(width: 1000, height: 650)
}
