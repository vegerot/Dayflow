//
//  AppDelegate.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/26/25.
//

import AppKit
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var recorder : ScreenRecorder!

    func applicationDidFinishLaunching(_ note: Notification) {
        statusBar = StatusBarController()   // safe: AppKit is ready, main thread
        recorder  = ScreenRecorder()        // hooks into AppState
        try? SMAppService.mainApp.register()// autostart at login
    }
}
