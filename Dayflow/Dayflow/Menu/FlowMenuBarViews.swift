//
//  FlowMenuBarViews.swift
//  Dayflow
//
//  What the menu bar shows while a Flow session is on: the countdown pill that
//  stands in for the status icon, and the illustrated session card at the top
//  of the menu. Neither appears outside a session.
//

import SwiftUI

/// A piece of artwork cropped the way the design crops it: the image is laid
/// out larger than its box and shifted, and the box clips the rest.
private struct CroppedArt: View {
  let name: String
  let box: CGSize
  let imageSize: CGSize
  let imageOffset: CGSize

  var body: some View {
    Image(name)
      .resizable()
      .interpolation(.high)
      .frame(width: imageSize.width, height: imageSize.height)
      .offset(imageOffset)
      .frame(width: box.width, height: box.height, alignment: .topLeading)
      .clipped()
  }
}

/// The white patch the design puts behind the creature's map.
private struct MapPatch: Shape {
  let points: [CGPoint]
  let size: CGSize

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let sx = rect.width / size.width
    let sy = rect.height / size.height
    for (index, point) in points.enumerated() {
      let scaled = CGPoint(x: point.x * sx, y: point.y * sy)
      if index == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
    }
    path.closeSubpath()
    return path
  }
}

// MARK: - Status item pill

/// Replaces the status icon during a session: the creature's face and the
/// time left (or the time so far, for an always-on session).
struct FlowMenuBarPill: View {
  let time: String?

  var body: some View {
    HStack(spacing: 8) {
      face
      if let time {
        Text(time)
          .font(.system(size: 11).monospacedDigit())
          .foregroundStyle(Color(red: 1, green: 0.976, blue: 0.949))
          .fixedSize()
      }
    }
    .padding(.leading, 8)
    .padding(.trailing, time == nil ? 8 : 10)
    .frame(height: 21)
    .background(
      LinearGradient(
        stops: [
          .init(color: Color(red: 1, green: 0.58, blue: 0.325).opacity(0.68), location: 0),
          .init(color: Color(red: 0.251, green: 0.157, blue: 0.137).opacity(0.68), location: 0.3),
          .init(color: .black.opacity(0.68), location: 0.65),
          .init(color: .black.opacity(0.68), location: 1),
        ],
        startPoint: .leading, endPoint: .trailing)
    )
    .clipShape(Capsule())
    .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.3))
  }

  private var face: some View {
    ZStack(alignment: .topLeading) {
      MapPatch(
        points: [
          CGPoint(x: 7.941, y: 0.243), CGPoint(x: 0.967, y: 0), CGPoint(x: 0, y: 1.346),
          CGPoint(x: 0.152, y: 5.397), CGPoint(x: 5.791, y: 5.794), CGPoint(x: 8.367, y: 4.728),
        ],
        size: CGSize(width: 8.367, height: 5.794)
      )
      .fill(.white)
      .frame(width: 8.367, height: 5.794)
      .offset(x: 3.66, y: 8.39)

      CroppedArt(
        name: "FlowMenuCreature",
        box: CGSize(width: 17.47, height: 15.934),
        imageSize: CGSize(width: 51.68, height: 29.2),
        imageOffset: CGSize(width: -12.19, height: -4.77)
      )
      .offset(x: 2.265, y: 1.033)
    }
    .frame(width: 22, height: 18, alignment: .topLeading)
  }
}

// MARK: - Session card

/// The card at the top of the status menu. The design is drawn at a 156pt
/// wide popover; `scale` brings it up to the width of a real menu.
struct FlowMenuSessionCard: View {
  enum Mode: Equatable {
    case inProgress
    case onBreak
    /// Dayflow's recording is paused, so Flow can't see the screen.
    case dayflowPaused
  }

  enum Control {
    case pause
    case resume
    case snooze
    case stop
  }

  static let scale: CGFloat = 1.45
  static let size = CGSize(width: 152 * scale, height: 48 * scale)

  let mode: Mode
  let onControl: (Control) -> Void

  private var s: CGFloat { Self.scale }

  var body: some View {
    ZStack(alignment: .topLeading) {
      Color(red: 1, green: 0.976, blue: 0.961)

      CroppedArt(
        name: "FlowMenuEnvironment",
        box: Self.size,
        imageSize: CGSize(width: 220.3 * s, height: 146.86 * s),
        imageOffset: CGSize(width: -61.68 * s, height: -33.78 * s))

      // 147.33deg in the design, expressed as the same line across the card.
      LinearGradient(
        stops: tint,
        startPoint: UnitPoint(x: 0.2826, y: -0.574), endPoint: UnitPoint(x: 0.7174, y: 1.574))

      creature

      Group {
        if mode == .dayflowPaused {
          pausedCopy
        } else {
          sessionControls
        }
      }
      .offset(x: 8.99 * s, y: (mode == .dayflowPaused ? 7 : 8) * s)
    }
    .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    .clipShape(RoundedRectangle(cornerRadius: 13 * s, style: .continuous))
    .shadow(color: .black.opacity(0.12), radius: 2.5, x: 0, y: 2)
  }

  private var tint: [Gradient.Stop] {
    func stops(
      _ a: (Double, Double, Double), _ b: (Double, Double, Double), _ c: (Double, Double, Double)
    )
      -> [Gradient.Stop]
    {
      [
        .init(
          color: Color(red: a.0 / 255, green: a.1 / 255, blue: a.2 / 255).opacity(0.96), location: 0
        ),
        .init(
          color: Color(red: b.0 / 255, green: b.1 / 255, blue: b.2 / 255).opacity(0.82),
          location: 0.46),
        .init(
          color: Color(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255).opacity(0.64), location: 1
        ),
      ]
    }
    switch mode {
    case .inProgress: return stops((246, 155, 125), (195, 151, 162), (171, 218, 255))
    case .onBreak: return stops((182, 165, 159), (196, 164, 171), (255, 255, 255))
    case .dayflowPaused: return stops((164, 161, 160), (162, 157, 157), (255, 255, 255))
    }
  }

  @ViewBuilder
  private var creature: some View {
    switch mode {
    case .inProgress:
      MapPatch(
        points: [
          CGPoint(x: 17.985, y: 0.482), CGPoint(x: 4.272, y: 0), CGPoint(x: 1.515, y: 2.274),
          CGPoint(x: 0, y: 9.509), CGPoint(x: 7.235, y: 12.059), CGPoint(x: 18.95, y: 10.405),
        ],
        size: CGSize(width: 18.95, height: 12.059)
      )
      .fill(.white)
      .frame(width: 18.95 * s, height: 12.059 * s)
      .offset(x: 107.97 * s, y: 20.54 * s)

      CroppedArt(
        name: "FlowMenuCreature",
        box: CGSize(width: 58.139 * s, height: 43.468 * s),
        imageSize: CGSize(width: 98.69 * s, height: 55.77 * s),
        imageOffset: CGSize(width: -15.95 * s, height: -9.11 * s)
      )
      .offset(x: 98.43 * s, y: 8 * s)
    case .onBreak:
      CroppedArt(
        name: "FlowMenuCreaturePaused",
        box: CGSize(width: 61.193 * s, height: 47.193 * s),
        imageSize: CGSize(width: 108.37 * s, height: 61.2 * s),
        imageOffset: CGSize(width: -20.07 * s, height: -11.49 * s)
      )
      .offset(x: 100.82 * s, y: 7.18 * s)
    case .dayflowPaused:
      CroppedArt(
        name: "FlowMenuCreatureAsleep",
        box: CGSize(width: 63.793 * s, height: 38.323 * s),
        imageSize: CGSize(width: 79.54 * s, height: 59.98 * s),
        imageOffset: CGSize(width: -8.11 * s, height: -9.52 * s)
      )
      .offset(x: 97.1 * s, y: 9.68 * s)
    }
  }

  private var sessionControls: some View {
    VStack(alignment: .leading, spacing: 6 * s) {
      Text(
        mode == .onBreak
          ? String(localized: "Flow session paused.")
          : String(localized: "Flow session in progress")
      )
      .font(.system(size: 7 * s, weight: .semibold))
      .foregroundStyle(.white)
      .fixedSize()

      HStack(spacing: 3 * s) {
        if mode == .onBreak {
          FrostButton(
            icon: "FlowMenuPlay", help: String(localized: "Resume the session"), scale: s
          ) { onControl(.resume) }
        } else {
          FrostButton(
            icon: "FlowMenuPause", help: String(localized: "Take a break"), scale: s
          ) { onControl(.pause) }
        }
        FrostButton(
          icon: "FlowMenuSnooze", help: String(localized: "No nudges for 5 minutes"), scale: s
        ) { onControl(.snooze) }
        FrostButton(
          icon: "FlowMenuStop", help: String(localized: "End the session"), scale: s
        ) { onControl(.stop) }
      }
    }
  }

  private var pausedCopy: some View {
    VStack(alignment: .leading, spacing: 4 * s) {
      Text("Dayflow is paused.")
        .font(.system(size: 7 * s, weight: .semibold))
      Text("Resume Dayflow to continue with the current session.")
        .font(.system(size: 7 * s))
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(.white)
    .frame(width: 88.1 * s, alignment: .leading)
  }
}

/// The frosted glass buttons on the session card.
private struct FrostButton: View {
  let icon: String
  let help: String
  let scale: CGFloat
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
    Button(action: action) {
      Image(icon)
        .resizable()
        .frame(width: 12 * scale, height: 12 * scale)
        .padding(.horizontal, 7 * scale)
        .padding(.vertical, 3 * scale)
        .background(
          LinearGradient(
            stops: [
              .init(color: .white.opacity(0.23), location: 0),
              .init(color: .white.opacity(0.12), location: 0.5),
              .init(
                color: Color(red: 0.886, green: 0.949, blue: 0.988).opacity(0.18), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
        )
        .background(.white.opacity(hovering ? 0.18 : 0))
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.6), lineWidth: 0.55 * scale))
        .shadow(color: Color(red: 0.89, green: 0.957, blue: 1).opacity(0.3), radius: 1)
        .contentShape(shape)
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .onHover { hovering = $0 }
    .help(help)
    .accessibilityLabel(help)
  }
}
