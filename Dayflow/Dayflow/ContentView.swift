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

// Add a struct to hold grouped TimelineCard data for the UI
struct CategoryGroup: Identifiable {
    let id = UUID()
    var category: String
    var cards: [TimelineCard] // Keep original cards for details
    var subcategories: [String] { // Extract unique subcategories for sidebar display (optional)
        Array(Set(cards.map { $0.subcategory })).sorted()
    }
    var rows: Int { subcategories.count } // Or adjust based on how you display in sidebar
}

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
            self.role = role
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
                DispatchQueue.main.async {
                    self.sync.x = newX
                    self.sync.y = newY
                }
            default: break
            }
        }
        
        @objc func boundsChanged(_ n: Notification) {
            guard let clip = n.object as? NSClipView else { return }
            if isProgrammatic { return }
            if role == .master {
                    let newX = clip.bounds.origin.x
                    let newY = clip.bounds.origin.y

                    DispatchQueue.main.async { [weak self] in
                        guard let sync = self?.sync else { return }
                        if newX != sync.x { sync.x = newX }
                        if newY != sync.y { sync.y = newY }
                    }
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

// MARK: – Placeholder View for No Data

struct WaitingForDataView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Waiting to collect enough data...")
                .font(.title2)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBG) // Match the app background
    }
}

// MARK: – Root view -------------------------------------------------------------

// --- Add Mock Data Generator ---
func generateMockTimelineCards(forDay day: String) -> [TimelineCard] {
    var cards: [TimelineCard] = []

    // Card 1: Programming (has distractions, no change needed here for nil)
    cards.append(TimelineCard(
        startTimestamp: "9:05 AM",
        endTimestamp: "10:15 AM",
        category: "Work",
        subcategory: "Development",
        title: "Implement Timeline View",
        summary: "Refactored ContentView to use real data structure.",
        detailedSummary: "Replaced Subject struct with CategoryGroup, updated sidebar and canvas, added time parsing.",
        day: day,
        distractions: [
            Distraction(startTime: "9:45 AM", endTime: "9:50 AM", title: "Slack Check", summary: "Quick check of messages")
        ]
    ))

    // Card 2: Meeting
    cards.append(TimelineCard(
        startTimestamp: "10:30 AM",
        endTimestamp: "11:00 AM",
        category: "Poop",
        subcategory: "Meetings",
        title: "Daily Standup",
        summary: "Discussed progress and blockers.",
        detailedSummary: "Covered timeline refactor status, next steps for data integration.",
        day: day,
        distractions: nil as [Distraction]? // Explicitly typed nil
    ))

    // Card 3: Break
    cards.append(TimelineCard(
        startTimestamp: "11:05 AM",
        endTimestamp: "11:20 AM",
        category: "Personal",
        subcategory: "Break",
        title: "Coffee Break",
        summary: "Short break.",
        detailedSummary: "Made coffee and stretched.",
        day: day,
        distractions: nil as [Distraction]? // Explicitly typed nil
    ))
    
    // Card 4: More Programming (has distractions, no change needed here for nil)
    cards.append(TimelineCard(
        startTimestamp: "11:25 AM",
        endTimestamp: "1:10 PM", // Crosses midday
        category: "Work",
        subcategory: "Development",
        title: "Debug Layout Issues",
        summary: "Investigated why cards overlap.",
        detailedSummary: "Used view debugger, checked offset calculations, tested different zoom levels.",
        day: day,
        distractions: [
             Distraction(startTime: "12:30 PM", endTime: "12:35 PM", title: "Email", summary: "Replied to urgent email"),
             Distraction(startTime: "12:55 PM", endTime: "1:00 PM", title: "Web Browsing", summary: "Looked up documentation")
        ]
    ))

    // Card 5: Lunch
     cards.append(TimelineCard(
         startTimestamp: "1:15 PM",
         endTimestamp: "1:55 PM",
         category: "Personal",
         subcategory: "Meals",
         title: "Lunch Break",
         summary: "Ate lunch.",
         detailedSummary: "Had leftovers, watched a short video.",
         day: day,
         distractions: nil as [Distraction]? // Explicitly typed nil
     ))

     // Card 6: Reading
     cards.append(TimelineCard(
         startTimestamp: "2:00 PM",
         endTimestamp: "2:45 PM",
         category: "Learning",
         subcategory: "Reading",
         title: "SwiftUI Documentation",
         summary: "Read about layout process.",
         detailedSummary: "Focused on NSViewRepresentable and geometry readers.",
         day: day,
         distractions: nil as [Distraction]? // Explicitly typed nil
     ))

    return cards
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var link = ScrollSync()
    @State private var categoryGroups: [CategoryGroup] = []
    @State private var zoom: Zoom = .h4
    @State private var hoverX: CGFloat?
    @State private var currentDayString: String = ""
    @State private var refreshTimer: Timer?

    // Access StorageManager (kept for future switch back)
    private let storageManager = StorageManager.shared

    var body: some View {
        let pxPerMin = zoom.pxPerMin

        VStack(spacing: 0) {
            // header
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("CATEGORIES") // Changed from SUBJECTS
                    Picker("", selection: $zoom) {
                        ForEach(Zoom.allCases) { z in Text(z.label) }
                    }
                    .frame(width: 70)
                    .padding(.trailing, 20)

                    Spacer()
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

            // --- Body: Conditional display of Timeline or Placeholder ---
            if categoryGroups.isEmpty {
                WaitingForDataView()
            } else {
                // sidebar + canvas (REPLACED with HSplitView for view switching)
                HSplitView {
                    // Left Pane: Sidebar
                    SyncableScroll(.y, role: .follower, sync: link) {
                        Sidebar(groups: $categoryGroups)
                            .frame(width: sidebarW, alignment: .leading)
                    }
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 0.5)
                    }
                    .frame(minWidth: sidebarW, idealWidth: sidebarW, maxWidth: sidebarW)
                    
                    // Right Pane: Always show Timeline Canvas
                    SyncableScroll(.both, role: .master, sync: link) {
                        Canvas(groups: categoryGroups,
                               pxPerMin: pxPerMin,
                               hoverX: $hoverX)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.30), value: zoom)
        .frame(maxWidth: .infinity,
               maxHeight: .infinity,
               alignment: .topLeading)
        .background(appBG)
        .onAppear {
            loadTimelineData()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
                print("Timer fired: Refreshing timeline data...")
                loadTimelineData()
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
            print("ContentView disappeared: Refresh timer invalidated.")
        }
    }

    func loadTimelineData() {
        let dayInfo = Date().getDayInfoFor4AMBoundary()
        currentDayString = dayInfo.dayString
        print("Loading timeline data for day: \(currentDayString)")

        // --- Use Real Data --- 
        // print("--- USING MOCK DATA FOR TESTING ---")
        // let fetchedCards = generateMockTimelineCards(forDay: currentDayString)
        // --- Switch to real data fetching ---
        let fetchedCards = storageManager.fetchTimelineCards(forDay: currentDayString)
        
        // Group fetched cards by category (Keep this logic)
        let grouped = Dictionary(grouping: fetchedCards, by: { $0.category })
        
        // Convert grouped dictionary to CategoryGroup array (Keep this logic)
        categoryGroups = grouped.map { category, cardsInGroup in
            // Sort cards within the group by start time using the parser
            let sortedCards = cardsInGroup.sorted { 
                guard let startMin1 = parseTimeHMMA(timeString: $0.startTimestamp),
                      let startMin2 = parseTimeHMMA(timeString: $1.startTimestamp) else {
                    return false // Keep original order if parsing fails for comparison
                }
                return startMin1 < startMin2
            }
            return CategoryGroup(category: category, cards: sortedCards)
        }.sorted { $0.category < $1.category } // Sort categories alphabetically
        
        print("Loaded \(categoryGroups.count) categories with a total of \(fetchedCards.count) cards from StorageManager.")
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
                            ZStack {
                                // 1) pin the tick to the **leading** edge, at the bottom
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.5))
                                    .frame(width: 1, height: 4)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            
                                // 2) center the label *over* that tick by shifting it left ½ cell
                                Text(timeString(t))
                                    .font(.caption2)
                                    .offset(x: -0.5 * 60 * pxPerMin)
                            }
                            .frame(width: 60 * pxPerMin)
                        }
                    }
            // ── cursor vertical line & live-time pill ─────────
            if let x = hoverX {
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
                            // center the pill exactly on the hairline (x)
                            // and vertically in the middle of the header (headerH/2)
                            .position(x: x, y: headerH / 2)
                            .allowsHitTesting(false)
                    }
        }.background(appBG)
    }
}

// MARK: – Sidebar --------------------------------------------------------------

struct Sidebar: View {
    @Binding var groups: [CategoryGroup]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(groups.indices, id: \.self) { i in
                let group = groups[i]
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(group.category).font(.system(size: 16, weight: .semibold))
                    }
                    .frame(height: rowH)
                    .padding(.horizontal, 12)
                    
                    ForEach(group.subcategories, id: \.self) { subcatName in
                        Text(subcatName)
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                                .frame(height: rowH)
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
    let groups: [CategoryGroup]
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
                ForEach(groups) { group in
                    CategoryLane(group: group, pxPerMin: pxPerMin)
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

struct CategoryLane: View {
    let group: CategoryGroup
    let pxPerMin: CGFloat
    var body: some View {
        // Calculate height: 1 row for Category header + 1 row for each Subcategory (no longer depends on isExpanded)
        let totalRows = 1 + group.subcategories.count
        
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: CGFloat(totalRows) * rowH)

            ForEach(Array(group.subcategories.enumerated()), id: \.element) { subcategoryIndex, subcategoryName in
                let cardsInSubcategory = group.cards.filter { $0.subcategory == subcategoryName }
                let cardRowIndex = subcategoryIndex + 1
                
                ForEach(cardsInSubcategory) { card in
                    TimelineCardView(card: card,
                                     rowIndex: cardRowIndex,
                                     pxPerMin: pxPerMin)
                }
            }
        }
        .frame(width: CGFloat(endMin - startMin) * pxPerMin,
               height: CGFloat(totalRows) * rowH,
               alignment: .topLeading)
    }
}

struct TimelineCardView: View {
    let card: TimelineCard
    let rowIndex: Int
    let pxPerMin: CGFloat
    @State private var hover = false

    private var startMinute: Int? { parseTimeHMMA(timeString: card.startTimestamp) }
    private var endMinute: Int? { parseTimeHMMA(timeString: card.endTimestamp) }
    
    private var width: CGFloat {
        guard let startM = startMinute, let endM = endMinute, endM > startM else { return 0 }
        return CGFloat(endM - startM) * pxPerMin
    }
    private var xOffset: CGFloat {
        guard let startM = startMinute else { return 0 }
        return CGFloat(max(0, startM - startMin)) * pxPerMin 
    }
    private var yOffset: CGFloat {
        CGFloat(rowIndex) * rowH + 4
    }

    var body: some View {
        if let startM = startMinute, let endM = endMinute, endM > startM, width > 0 {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(red: 0.90, green: 0.90, blue: 0.90), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                .frame(width: width, height: rowH - 8)
                .overlay(alignment: .leading) {
                    Text(card.title)
                    .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
                .offset(x: xOffset, y: yOffset)
                .overlay(
                    Text("\(card.startTimestamp) – \(card.endTimestamp)")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(4)
                    .opacity(hover ? 1 : 0)
                        .offset(x: xOffset, y: yOffset - 20)
                        .animation(.easeInOut(duration: 0.1), value: hover)
            )
            .onHover { hover = $0 }
        } else {
            EmptyView()
                .onAppear {
                    print("Warning: Could not render card '\(card.title)' due to invalid time: Start='\(card.startTimestamp)', End='\(card.endTimestamp)'")
                }
        }
    }
}

// MARK: – Preview --------------------------------------------------------------

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState.shared)
    }
}
