//
//  WhatsNewView.swift
//  Dayflow
//
//  Displays release highlights after app updates
//

import SwiftUI

// MARK: - Release Notes Data Structure

struct ReleaseNote: Identifiable {
    let id = UUID()
    let version: String      // e.g. "2.0.1"
    let title: String        // e.g. "Timeline Improvements"
    let highlights: [String] // Array of bullet points
    let imageName: String?   // Optional asset name for preview

    // Helper to compare semantic versions
    var semanticVersion: [Int] {
        version.split(separator: ".").compactMap { Int($0) }
    }
}

// MARK: - Release Notes Database
// TO UPDATE: Add new releases at the TOP of this array

private let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"

let releaseNotes: [ReleaseNote] = [
    // Current release - update highlights when shipping a new build
    ReleaseNote(
        version: currentAppVersion,
        title: "Thanks for being an early user of Dayflow! This is the first major update to the app - really appreciate everyone who spent the time to send in feedback.",
        highlights: [
            "Huge UI refresh - Dayflow should feel much more pleasant on the eyes.",
            "Added ability to retry a failed timeline card. (Much requested feature!)",
            "Fixed a lot of bugs with timeline card generation and recording - thank you to everyone who submitted a bug report.",
            "Please keep the feedback coming - I would love to hear from you, whether it's just to say you enjoy a particular feature, have a feature request, or see any issues using the app!"
        ],
        imageName: nil
    ),

    // Add future releases here...
    // ReleaseNote(
    //     version: "1.2.0",
    //     title: "Amazing New Features",
    //     highlights: [
    //         "Feature 1",
    //         "Feature 2"
    //     ],
    //     imageName: nil
    // ),
]

// MARK: - What's New View

struct WhatsNewView: View {
    let releaseNote: ReleaseNote
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What's New in \(releaseNote.version) 🎉")
                        .font(.custom("InstrumentSerif-Regular", size: 32))
                        .foregroundColor(.black.opacity(0.9))

                    Text(releaseNote.title)
                        .font(.custom("Nunito", size: 15))
                        .fontWeight(.semibold)
                        .foregroundColor(.black.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(8)
                        .background(Color.black.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Close")
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(releaseNote.highlights.enumerated()), id: \.offset) { _, highlight in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color(red: 0.25, green: 0.17, blue: 0).opacity(0.6))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)

                        Text(highlight)
                            .font(.custom("Nunito", size: 15))
                            .foregroundColor(.black.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Divider()

            ReferralSurveyView(
                prompt: "I have a small favor to ask. I'd love to understand where you first heard about Dayflow.",
                onSubmit: handleReferralSubmission
            )
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 36)
        .frame(width: 780)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.25), radius: 40, x: 0, y: 20)
        )
        .onAppear {
            AnalyticsService.shared.screen("whats_new")
            AnalyticsService.shared.capture("whats_new_viewed", [
                "version": releaseNote.version
            ])
        }
    }

    private func handleReferralSubmission(option: ReferralOption, detail: String?) {
        var payload: [String: String] = [
            "version": releaseNote.version,
            "source": option.analyticsValue
        ]

        if let detail = detail, !detail.isEmpty {
            payload["detail"] = detail
        }

        AnalyticsService.shared.capture("whats_new_referral", payload)
        dismiss()
    }

    private func dismiss() {
        AnalyticsService.shared.capture("whats_new_dismissed", [
            "version": releaseNote.version
        ])

        // Mark this version as seen
        WhatsNewView.markAsSeen()

        onDismiss()
    }
}

// MARK: - Helper Functions

extension WhatsNewView {
    /// Determines if What's New should be shown for the current app version
    /// - Returns: ReleaseNote to show, or nil if shouldn't show
    static func shouldShowWhatsNew() -> ReleaseNote? {
        // Get current app version build number
        guard let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return nil
        }

        let lastSeenVersion = UserDefaults.standard.string(forKey: "lastSeenWhatsNewVersion") ?? ""

        // If never seen before, save current and don't show (fresh install)
        if lastSeenVersion.isEmpty {
            UserDefaults.standard.set(currentBuild, forKey: "lastSeenWhatsNewVersion")
            return nil
        }

        // If already seen this version, don't show
        if lastSeenVersion == currentBuild {
            return nil
        }

        // Find the release note for current version
        // Match by comparing short version (e.g., "1.0.0")
        let currentShortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let matchingNote = releaseNotes.first { $0.version == currentShortVersion }

        return matchingNote
    }

    /// Marks the current version as seen
    static func markAsSeen() {
        guard let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return
        }
        UserDefaults.standard.set(currentBuild, forKey: "lastSeenWhatsNewVersion")
    }
}

// MARK: - Preview

struct WhatsNewView_Previews: PreviewProvider {
    static var previews: some View {
        WhatsNewView(
            releaseNote: releaseNotes[0],
            onDismiss: { print("Dismissed") }
        )
        .frame(width: 1200, height: 800)
    }
}
