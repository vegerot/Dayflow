//
//  StatusBarController.swift
//  Dayflow
//
//  Created by Jerry Liu on 4/26/25.
//

import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var sub: Any?
    private var toggleItem: NSMenuItem!
    
    init() {
        // Build menu
        item.menu = menu

        // Configure status item to show icon only (no text)
        if let btn = item.button {
            if let img = NSImage(named: "MenuBarIcon") {
                img.isTemplate = true // follows system tint
                btn.image = img
                btn.imagePosition = .imageOnly
            }
        }
        item.length = NSStatusItem.squareLength

        // Keep menu label in sync with recording state
        sub = AppState.shared.$isRecording.sink { [weak self] rec in
            guard let self = self else { return }
            self.toggleItem.title = rec ? "Pause Dayflow" : "Resume Dayflow"
        }
    }
    
    private lazy var menu: NSMenu = {
        let m = NSMenu()

        // Pause / Resume
        let t = NSMenuItem(title: "Pause Dayflow",
                           action: #selector(toggle),
                           keyEquivalent: "")
        t.target = self
        m.addItem(t)
        self.toggleItem = t

        // Open Recordings…
        let open = NSMenuItem(title: "Open Recordings…",
                              action: #selector(openFolder),
                              keyEquivalent: "o")
        open.target = self               // ← add this line
        m.addItem(open)

        // Check for Updates… (Sparkle)
        let updates = NSMenuItem(title: "Check for Updates…",
                                 action: #selector(checkForUpdates),
                                 keyEquivalent: "")
        updates.target = self
        m.addItem(updates)
        
        m.addItem(NSMenuItem.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit",
                              action: #selector(quit),
                              keyEquivalent: "q")
        quit.target = self
        m.addItem(quit)

        return m
    }()
    
    @objc private func openFolder() {
        let dir = StorageManager.shared.recordingsRoot
        NSWorkspace.shared.open(dir)
    }
    @objc private func toggle() { AppState.shared.isRecording.toggle() }
    @objc private func checkForUpdates() { UpdaterManager.shared.checkForUpdates(showUI: true) }
    @objc private func quit()   {
        // Allow termination only when explicitly quitting from the status bar
        AppDelegate.allowTermination = true
        // Optionally stop recording gracefully
        AppState.shared.isRecording = false
        NSApp.terminate(nil)
    }
}
