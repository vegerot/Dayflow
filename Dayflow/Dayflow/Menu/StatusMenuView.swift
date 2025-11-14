import SwiftUI
import AppKit

@MainActor
struct StatusMenuView: View {
    let dismissMenu: () -> Void
    @ObservedObject private var appState = AppState.shared
    private let updaterManager = UpdaterManager.shared

    var body: some View {
        VStack(spacing: 6) {
            MenuRow(
                title: appState.isRecording ? "Pause Dayflow" : "Resume Dayflow",
                systemImage: appState.isRecording ? "pause.circle" : "play.circle",
                accent: .accentColor,
                keepsMenuOpen: true,
                action: toggleRecording
            )

            MenuDivider()

            MenuRow(title: "Open Dayflow", systemImage: "macwindow", action: openDayflow)
            MenuRow(title: "Open Recordings", systemImage: "folder", action: openRecordingsFolder)
            MenuRow(title: "Check for Updates", systemImage: "arrow.triangle.2.circlepath", action: checkForUpdates)

            MenuDivider()

            MenuRow(title: "Quit Completely", systemImage: "power", accent: .red, action: quitDayflow)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 9)
        .frame(minWidth: 165, maxWidth: 170)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toggleRecording() {
        appState.isRecording.toggle()
    }

    private func openDayflow() {
        // Capture the popover/menu window before we dismiss it
        let menuWindowNumber = NSApp.keyWindow?.windowNumber

        performAfterMenuDismiss {
            NSApp.setActivationPolicy(.regular)
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)

            var showedWindow = false
            for window in NSApp.windows
            where window.canBecomeKey && window.windowNumber != menuWindowNumber {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
                showedWindow = true
            }

            if !showedWindow {
                MainWindowManager.shared.showMainWindow()
            }
        }
    }

    private func openRecordingsFolder() {
        performAfterMenuDismiss {
            let directory = StorageManager.shared.recordingsRoot
            NSWorkspace.shared.open(directory)
        }
    }

    private func checkForUpdates() {
        performAfterMenuDismiss {
            updaterManager.checkForUpdates(showUI: true)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func quitDayflow() {
        performAfterMenuDismiss {
            AppDelegate.allowTermination = true
            NSApp.terminate(nil)
        }
    }

    private func performAfterMenuDismiss(_ action: @escaping () -> Void) {
        dismissMenu() // calls popover.performClose(nil)

        // Give the runloop a chance to fully remove the popover window
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                action()
            }
        }
    }
}

private struct MenuRow: View {
    let title: String
    let systemImage: String
    var accent: Color = .primary
    var keepsMenuOpen: Bool = false
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 17)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 3.5)
            .padding(.horizontal, 5)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func handleTap() {
        action()
    }
}

private struct MenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.75)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }
}
