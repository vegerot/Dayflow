//
//  DayflowUIStyles.swift
//  Dayflow
//
//  Reusable styling components for the new UI
//

import SwiftUI


struct DayflowShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color(red: 0.57, green: 0.57, blue: 0.57).opacity(0.05), radius: 3.08853, x: -1.23541, y: 2.47082)
            .shadow(color: Color(red: 0.57, green: 0.57, blue: 0.57).opacity(0.04), radius: 5.55935, x: -4.32394, y: 10.501)
            .shadow(color: Color(red: 0.57, green: 0.57, blue: 0.57).opacity(0.03), radius: 7.41247, x: -9.26558, y: 22.85511)
            .shadow(color: Color(red: 0.57, green: 0.57, blue: 0.57).opacity(0.01), radius: 8.95673, x: -16.67805, y: 40.76858)
            .shadow(color: Color(red: 0.57, green: 0.57, blue: 0.57).opacity(0), radius: 9.57444, x: -25.94364, y: 63.62368)
    }
}

extension View {
    /// Applies Dayflow's signature shadow stack
    func dayflowShadow() -> some View {
        modifier(DayflowShadowModifier())
    }
    
    /// Applies complete Dayflow style with rounded rectangle shape
    func dayflowStyle(
        cornerRadius: CGFloat = 735.4068,
        backgroundColor: Color = .white
    ) -> some View {
        self
            .background(backgroundColor)
            .cornerRadius(cornerRadius)
    }
    
    /// Applies complete Dayflow style with circle shape
    func dayflowCircleStyle(backgroundColor: Color = .white) -> some View {
        self
            .background(backgroundColor)
            .clipShape(Circle())
    }
}

struct DayflowCircleButton<Content: View>: View {
    let action: () -> Void
    let size: CGSize
    @ViewBuilder let content: () -> Content
    
    init(
        width: CGFloat = 31.40301,
        height: CGFloat = 30.4514,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.size = CGSize(width: width, height: height)
        self.action = action
        self.content = content
    }
    
    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: size.width, height: size.height)
        .dayflowCircleStyle()
        .contentShape(Circle())
    }
}

struct DayflowPillButton: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    let horizontalPadding: CGFloat
    let height: CGFloat
    let fixedWidth: CGFloat?

    init(
        text: String,
        font: Font = .custom("InstrumentSerif-Regular", size: 18),
        foregroundColor: Color = Color(red: 0.2, green: 0.2, blue: 0.2),
        horizontalPadding: CGFloat = 11.77829,
        height: CGFloat = 30.4514,
        fixedWidth: CGFloat? = nil
    ) {
        self.text = text
        self.font = font
        self.foregroundColor = foregroundColor
        self.horizontalPadding = horizontalPadding
        self.height = height
        self.fixedWidth = fixedWidth
    }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .if(fixedWidth != nil) { view in
                view.frame(width: fixedWidth!, height: height)
            }
            .if(fixedWidth == nil) { view in
                view.padding(.horizontal, horizontalPadding)
                    .frame(height: height)
            }
            .dayflowStyle()
    }
}
