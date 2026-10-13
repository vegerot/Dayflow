//
//  FlowSupportChatView.swift
//  Dayflow
//
//  The Support button on Flow's home screen: the chat from the waitlist
//  screen, in a card over the dimmed Flow page. Someone who joined the
//  waitlist on this Mac keeps the conversation they started there.
//

import SwiftUI

struct FlowSupportChatView: View {
  let onClose: () -> Void

  @State private var chatUnavailable = false
  @State private var context = SupportChatSession.flowSupportContext()

  private var session: SupportChatSession { .session(for: context) }

  private static var placeholder: String {
    String(
      localized:
        "Report a bug, an issue or a feature request. You can drag and drop screenshots here too."
    )
  }

  var body: some View {
    ZStack {
      Color.black.opacity(0.35)
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)

      VStack(spacing: 0) {
        HStack {
          Text("Support")
            .font(.custom("InstrumentSerif-Regular", size: 26))
            .foregroundColor(Color(hex: "333333"))
          Spacer()
          Button(action: onClose) {
            Image(systemName: "xmark")
              .font(.system(size: 12, weight: .semibold))
              .foregroundColor(Color(hex: "707070"))
              .frame(width: 26, height: 26)
              .background(Circle().fill(Color.black.opacity(0.06)))
          }
          .buttonStyle(.plain)
          .keyboardShortcut(.cancelAction)
          .accessibilityLabel(Text("Close"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)

        ZStack {
          SupportChatWebView(palette: .light, context: context) { event in
            switch event {
            case .ready:
              chatUnavailable = false
              session.setMessagePlaceholder(Self.placeholder)
            case .unavailable:
              chatUnavailable = true
            }
          }
          .opacity(chatUnavailable ? 0 : 1)
          .onAppear { session.setMessagePlaceholder(Self.placeholder) }

          if chatUnavailable {
            VStack(spacing: 12) {
              Text("Chat is temporarily unavailable.")
                .font(.custom("Figtree", size: 16).weight(.medium))
              Text("Try again in a bit, or email jerry@dayflow.so.")
                .font(.custom("Figtree", size: 14))
            }
            .foregroundColor(Color(hex: "333333"))
            .multilineTextAlignment(.center)
            .padding(32)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(maxWidth: 680, maxHeight: 580)
      .background(Color.white.opacity(0.96))
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(.white.opacity(0.5), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 10)
      .padding(32)
    }
    .onAppear {
      session.setVisible(true)
      AnalyticsService.shared.screen("flow_support_chat")
    }
    .onDisappear { session.setVisible(false) }
  }
}
