import SwiftUI
import AppKit

struct BugReportView: View {
    private let emailAddress = "liu.z.jerry@gmail.com"
    @State private var didCopyEmail = false
    @State private var copyResetTask: DispatchWorkItem? = nil

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 16) {
                Text("Thanks for using Dayflow")
                    .font(.custom("InstrumentSerif-Regular", size: 40))
                    .foregroundColor(.black.opacity(0.9))

                Text("Dayflow is built and maintained by a one-man team. If you spot hiccups or have ideas, I would love to hear your feedback.")
                    .font(.custom("Nunito", size: 16))
                    .foregroundColor(.black.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
            }
        HStack(spacing: 16) {
            DayflowSurfaceButton(
                action: composeEmail,
                content: {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Email Jerry")
                            .font(.custom("Nunito", size: 16).weight(.semibold))
                    }
                },
                background: Color.white,
                foreground: Color.black,
                borderColor: Color.black.opacity(0.12),
                cornerRadius: 18,
                horizontalPadding: 28,
                verticalPadding: 16,
                showShadow: true
            )

            DayflowSurfaceButton(
                action: copyEmail,
                content: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 16, weight: .semibold))
                        Text(didCopyEmail ? "Copied!" : "Copy email")
                            .font(.custom("Nunito", size: 15).weight(.semibold))
                    }
                },
                background: Color.white,
                foreground: Color.black,
                borderColor: Color.black.opacity(0.12),
                cornerRadius: 14,
                horizontalPadding: 22,
                verticalPadding: 14,
                showShadow: true
            )
            .opacity(didCopyEmail ? 0.85 : 1.0)
        }
        .padding(.horizontal, 8)
    }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
        .padding(.horizontal, 48)
    }

    private func composeEmail() {
        AnalyticsService.shared.capture("bug_report_email_tapped", ["destination": emailAddress])

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = emailAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Dayflow feedback")
        ]

        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyEmail() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(emailAddress, forType: .string)
        AnalyticsService.shared.capture("bug_report_email_copied")

        withAnimation(.easeOut(duration: 0.2)) {
            didCopyEmail = true
        }

        copyResetTask?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) {
                didCopyEmail = false
            }
            self.copyResetTask = nil
        }
        copyResetTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }
}

#Preview {
    BugReportView()
}
