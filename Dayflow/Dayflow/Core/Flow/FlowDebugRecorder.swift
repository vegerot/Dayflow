//
//  FlowDebugRecorder.swift
//  Dayflow
//
//  Debug builds only: records this app's own windows (the main window and
//  the Flow overlay panel) to a movie, so a walkthrough of the Flow web app
//  can be reviewed afterwards. Started and stopped from outside the app by
//  creating and removing the flag file below; nothing in the UI triggers it.
//

#if DEBUG
  import AppKit
  import Foundation
  import ScreenCaptureKit

  @available(macOS 15.0, *)
  @MainActor
  final class FlowDebugRecorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    static let shared = FlowDebugRecorder()

    static var outputURL: URL {
      URL(fileURLWithPath: "/tmp/dayflow-flow-walkthrough.mov")
    }

    private var stream: SCStream?

    /// Recording runs for as long as this file exists.
    static let flagPath = "/tmp/dayflow-flow-record.flag"
    private var timer: Timer?

    func install() {
      timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          let wanted = FileManager.default.fileExists(atPath: Self.flagPath)
          if wanted, self.stream == nil, !self.starting {
            await self.start()
          } else if !wanted, self.stream != nil {
            await self.stop()
          }
        }
      }
    }

    private var starting = false

    private func start() async {
      guard stream == nil else { return }
      starting = true
      defer { starting = false }
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: false)
        let pid = ProcessInfo.processInfo.processIdentifier
        guard
          let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
            ?? content.displays.first,
          let app = content.applications.first(where: { $0.processID == pid })
        else { return }

        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true

        try? FileManager.default.removeItem(at: Self.outputURL)
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = Self.outputURL
        recordingConfig.outputFileType = .mov
        recordingConfig.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addRecordingOutput(
          SCRecordingOutput(configuration: recordingConfig, delegate: self))
        try await stream.startCapture()
        self.stream = stream
        NSLog("FlowDebugRecorder: recording to %@", Self.outputURL.path)
      } catch {
        NSLog("FlowDebugRecorder: could not start: %@", String(describing: error))
      }
    }

    private func stop() async {
      guard let stream else { return }
      self.stream = nil
      try? await stream.stopCapture()
      NSLog("FlowDebugRecorder: stopped")
    }
  }
#endif
