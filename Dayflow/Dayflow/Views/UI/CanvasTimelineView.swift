import SwiftUI

// MARK: - CSS Angle Helper
private extension UnitPoint {
    static func fromCSSAngle(_ deg: Double) -> (start: UnitPoint, end: UnitPoint) {
        let r = deg * .pi / 180
        let dx = sin(r), dy = -cos(r)               // SwiftUI y down
        let s = 0.5 / max(abs(dx), abs(dy))         // hit unit square edges
        let (cx, cy) = (0.5, 0.5)
        return (.init(x: cx - dx*s, y: cy - dy*s),
                .init(x: cx + dx*s, y: cy + dy*s))
    }
}

enum CardColor: String, CaseIterable {
    case blue = "BlueTimelineCard"
    case orange = "OrangeTimelineCard"
    case red = "RedTimelineCard"
}

struct DummyActivity: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let startHour: Int
    let startMinute: Int
    let durationMinutes: Int
    let cardColor: CardColor
    
    var yPosition: CGFloat {
        let hoursFromStart = CGFloat(startHour - 4) // 4 AM is our baseline
        let minutesAsHours = CGFloat(startMinute) / 60.0
        return (hoursFromStart + minutesAsHours) * 120 + 2 // Add 2px offset for top spacing
    }
    
    var height: CGFloat {
        return CGFloat(durationMinutes) * 2 - 4 // 60 minutes = 120px, minus 4px for spacing (2px top + 2px bottom)
    }
    
    var formattedTime: String {
        let startFormatted = formatTime(hour: startHour, minute: startMinute)
        let endHour = startHour + (startMinute + durationMinutes) / 60
        let endMinute = (startMinute + durationMinutes) % 60
        let endFormatted = formatTime(hour: endHour, minute: endMinute)
        return "\(startFormatted) - \(endFormatted)"
    }
    
    private func formatTime(hour: Int, minute: Int) -> String {
        let normalizedHour = hour >= 24 ? hour - 24 : hour
        let adjustedHour = normalizedHour > 12 ? normalizedHour - 12 : (normalizedHour == 0 ? 12 : normalizedHour)
        let period = normalizedHour >= 12 ? "PM" : "AM"
        let minuteString = minute == 0 ? "00" : String(format: "%02d", minute)
        return "\(adjustedHour):\(minuteString) \(period)"
    }
}

// MARK: - Selection Effect Constants
private struct SelectionEffectConstants {
    // Shadow parameters - light from top-left
    static let shadowRadius: CGFloat = 12
    static let shadowOffset = CGSize(width: 4, height: 4)  // Bottom-right shadow for top-left light
    
    // Color-specific shadow colors
    static let blueShadowColor = Color(red: 0.2, green: 0.4, blue: 0.9).opacity(0.3)
    static let orangeShadowColor = Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.3)
    static let redShadowColor = Color(red: 0.9, green: 0.3, blue: 0.3).opacity(0.3)
    
    // Animation parameters - Apple-like spring feel
    static let springResponse: Double = 0.35
    static let springDampingFraction: Double = 0.8
    static let springBlendDuration: Double = 0.1
    
    static func shadowColor(for cardColor: CardColor) -> Color {
        switch cardColor {
        case .blue:
            return blueShadowColor
        case .orange:
            return orangeShadowColor
        case .red:
            return redShadowColor
        }
    }
}

struct CanvasTimelineView: View {
    let hourHeight: CGFloat = 120
    let timeColumnWidth: CGFloat = 80
    let startHour = 4  // 4 AM
    let endHour = 28   // 4 AM next day (28 = 24 + 4)
    
    @State private var scrollOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var lastDragVelocity: CGFloat = 0
    @State private var selectedCardId: UUID? = nil
    
    let dummyActivities = [
        DummyActivity(icon: "☕", title: "Morning Coffee", startHour: 6, startMinute: 30, durationMinutes: 15, cardColor: .blue),
        
        // Back-to-back 15min blocks from 8:00 AM to 9:30 AM
        DummyActivity(icon: "📨", title: "Check Emails", startHour: 8, startMinute: 0, durationMinutes: 15, cardColor: .orange),
        DummyActivity(icon: "📋", title: "Review Tasks", startHour: 8, startMinute: 15, durationMinutes: 15, cardColor: .blue),
        DummyActivity(icon: "💬", title: "Slack Updates", startHour: 8, startMinute: 30, durationMinutes: 15, cardColor: .red),
        DummyActivity(icon: "📊", title: "Check Metrics", startHour: 8, startMinute: 45, durationMinutes: 15, cardColor: .orange),
        DummyActivity(icon: "🎯", title: "Set Priorities", startHour: 9, startMinute: 0, durationMinutes: 15, cardColor: .blue),
        DummyActivity(icon: "☎️", title: "Quick Call", startHour: 9, startMinute: 15, durationMinutes: 15, cardColor: .red),
        
        DummyActivity(icon: "💼", title: "Team Standup", startHour: 9, startMinute: 30, durationMinutes: 30, cardColor: .orange),
        DummyActivity(icon: "💻", title: "Feature Development", startHour: 10, startMinute: 0, durationMinutes: 60, cardColor: .blue),
        DummyActivity(icon: "📧", title: "Email Review", startHour: 11, startMinute: 0, durationMinutes: 20, cardColor: .red),
        DummyActivity(icon: "🍕", title: "Lunch Break", startHour: 12, startMinute: 15, durationMinutes: 45, cardColor: .orange),
        
        // Another dense block from 2:00 PM to 3:00 PM
        DummyActivity(icon: "📝", title: "Write Notes", startHour: 14, startMinute: 0, durationMinutes: 15, cardColor: .blue),
        DummyActivity(icon: "🔍", title: "Code Review", startHour: 14, startMinute: 15, durationMinutes: 15, cardColor: .orange),
        DummyActivity(icon: "🐛", title: "Bug Fix", startHour: 14, startMinute: 30, durationMinutes: 15, cardColor: .red),
        DummyActivity(icon: "✅", title: "Testing", startHour: 14, startMinute: 45, durationMinutes: 15, cardColor: .blue),
        
        DummyActivity(icon: "🤝", title: "Client Meeting", startHour: 15, startMinute: 0, durationMinutes: 60, cardColor: .orange),
        DummyActivity(icon: "📚", title: "Documentation", startHour: 16, startMinute: 15, durationMinutes: 45, cardColor: .blue),
        DummyActivity(icon: "🔬", title: "Research with ChatGPT", startHour: 17, startMinute: 0, durationMinutes: 60, cardColor: .red),
        DummyActivity(icon: "🏃", title: "Quick Break", startHour: 18, startMinute: 30, durationMinutes: 15, cardColor: .orange),
        DummyActivity(icon: "🎯", title: "Planning Tomorrow", startHour: 19, startMinute: 0, durationMinutes: 25, cardColor: .blue),
        DummyActivity(icon: "📱", title: "Slack Catchup", startHour: 20, startMinute: 0, durationMinutes: 15, cardColor: .red)
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Content that can be dragged
                ZStack(alignment: .topLeading) {
                    // Background
                    Color.white
                    
                    // Horizontal lines that extend past the vertical separator
                    VStack(spacing: 0) {
                        ForEach(0..<(endHour - startHour), id: \.self) { index in
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.black.opacity(0.1))
                                    .frame(height: 2)
                                Spacer()
                            }
                            .frame(height: hourHeight)
                        }
                    }
                    .padding(.leading, timeColumnWidth) // Lines start at the edge of time column
                    
                    // Main content with time labels
                    HStack(spacing: 0) {
                        // Time labels column
                        VStack(spacing: 0) {
                            ForEach(startHour..<endHour, id: \.self) { hour in
                                Text(formatHour(hour))
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.gray)
                                    .frame(width: timeColumnWidth - 12, alignment: .leading)
                                    .padding(.leading, 12)
                                    .frame(height: hourHeight, alignment: .top)
                                    .offset(y: -8) // Offset to align with the line
                            }
                        }
                        .frame(width: timeColumnWidth)
                        
                        // Main timeline area
                        ZStack(alignment: .topLeading) {
                            Color.clear
                            
                            // Dummy activity cards with time-based positioning
                            ForEach(dummyActivities) { activity in
                                DummyActivityCard(
                                    icon: activity.icon,
                                    title: activity.title,
                                    time: activity.formattedTime,
                                    height: activity.height,
                                    cardColor: activity.cardColor,
                                    activity: activity,
                                    isSelected: selectedCardId == activity.id,
                                    onTap: {
                                        // Toggle selection - tap same card to deselect, tap different card to select it
                                        if selectedCardId == activity.id {
                                            selectedCardId = nil
                                        } else {
                                            selectedCardId = activity.id
                                        }
                                    }
                                )
                                .frame(height: activity.height)
                                .offset(y: activity.yPosition)
                            }
                        }
                        .frame(width: geometry.size.width - timeColumnWidth)
                    }
                }
                .frame(height: CGFloat(endHour - startHour) * hourHeight)
                .offset(y: scrollOffset + dragOffset)
                .animation(isDragging ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.8), value: scrollOffset)
            }
            .clipped()
            .contentShape(Rectangle()) // Make entire area draggable
            .onHover { hovering in
                if hovering && !isDragging {
                    NSCursor.openHand.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            NSCursor.closedHand.set()
                        }
                        dragOffset = value.translation.height
                        
                        // Track velocity for momentum
                        lastDragVelocity = value.predictedEndTranslation.height - value.translation.height
                    }
                    .onEnded { value in
                        isDragging = false
                        NSCursor.openHand.set()
                        
                        // Apply the drag and add momentum
                        var newOffset = scrollOffset + value.translation.height + (lastDragVelocity * 0.2)
                        
                        // Constrain to bounds
                        let maxOffset: CGFloat = 0
                        let minOffset = -(CGFloat(endHour - startHour) * hourHeight - geometry.size.height)
                        newOffset = min(maxOffset, max(minOffset, newOffset))
                        
                        scrollOffset = newOffset
                        dragOffset = 0
                    }
            )
        }
        .background(Color.white)
    }
    
    private func formatHour(_ hour: Int) -> String {
        // Handle hours that go into next day (24+)
        let normalizedHour = hour >= 24 ? hour - 24 : hour
        let adjustedHour = normalizedHour > 12 ? normalizedHour - 12 : (normalizedHour == 0 ? 12 : normalizedHour)
        let period = normalizedHour >= 12 ? "PM" : "AM"
        return "\(adjustedHour):00 \(period)"
    }
}

// MARK: - Dummy Activity Card
struct DummyActivityCard: View {
    let icon: String
    let title: String
    let time: String
    let height: CGFloat
    let cardColor: CardColor
    let activity: DummyActivity
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(icon)
                .font(.system(size: 16))
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.black.opacity(0.8))
            
            Text("• \(time)")
                .font(
                    Font.custom("Nunito", size: 10)
                        .weight(.medium)
                )
                .foregroundColor(.black.opacity(0.6))
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
        .background(
            Image(cardColor.rawValue)
                .resizable()
        )
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .overlay(
            Group {
                // Existing stroke borders
                if cardColor == .orange {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(Color(hex: "FFEBC9"), lineWidth: 1.5)
                } else if cardColor == .blue {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(Color(hex: "C9D6F6"), lineWidth: 1.5)
                }
            }
        )
        .shadow(
            color: isSelected ? SelectionEffectConstants.shadowColor(for: cardColor) : .clear,
            radius: isSelected ? SelectionEffectConstants.shadowRadius : 0,
            x: isSelected ? SelectionEffectConstants.shadowOffset.width : 0,
            y: isSelected ? SelectionEffectConstants.shadowOffset.height : 0
        )
        .animation(
            .interactiveSpring(
                response: SelectionEffectConstants.springResponse,
                dampingFraction: SelectionEffectConstants.springDampingFraction,
                blendDuration: SelectionEffectConstants.springBlendDuration
            ),
            value: isSelected
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle()) // Make entire card tappable
        .onTapGesture {
            onTap()
        }
    }
}

struct CanvasTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        CanvasTimelineView()
            .frame(width: 600, height: 400)
    }
}
