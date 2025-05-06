//  ScreenRecorder.swift
//  AmiTime
//
//  Lightweight screen recorder – captures the main display at 1280 × 720
//  and stores 15‑second H.264 (.mp4) chunks while `AppState.shared.isRecording` is true.
//
//  Created 5 May 2025.  Last cleaned‑up <today>.
//
//  Notes
//  -----
//  •  The recorder lives entirely on its own serial queue (`q`).
//  •  Recording auto‑restarts after errors *and* after system sleep/wake.
//  •  Debug prints are compiled‑in **only** for DEBUG builds.
//
import Foundation
@preconcurrency import ScreenCaptureKit
import AVFoundation
import Combine
import IOKit.pwr_mgt   // sleep / wake notifications

private enum C {
    static let width  = 1280
    static let height = 720
    static let chunk  : TimeInterval = 15       // seconds per file
    static let fps    : Int32 = 1               // keep @ 1 fps
}

#if DEBUG
@inline(__always) func dbg(_ msg: @autoclosure () -> String) { print("[Recorder] \(msg())") }
#else
@inline(__always) func dbg(_: @autoclosure () -> String) {}
#endif

// MARK: - ScreenRecorder

@MainActor
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {

    // MARK: lifecycle ----------------------------------------------------
    init(autoStart: Bool = true) {
        super.init()
        dbg("init – autoStart = \(autoStart)")

        // Observe the app‑wide recording flag.
        sub = AppState.shared.$isRecording
            .dropFirst()                // ignore initial value
            .removeDuplicates()
            .sink { [weak self] rec in rec ? self?.start() : self?.stop() }

        // Honor the current flag once (after subscription exists).
        if autoStart, AppState.shared.isRecording { start() }

        registerForSleepWake()
    }

    deinit { sub?.cancel(); dbg("deinit") }

    // MARK: private state ----------------------------------------------
    private let q = DispatchQueue(label: "com.amitime.recorder", qos: .userInitiated)
    private var stream : SCStream?
    private var writer : AVAssetWriter?
    private var input  : AVAssetWriterInput?
    private var firstPTS : CMTime?
    private var timer  : DispatchSourceTimer?
    private var fileURL: URL?
    private var sub    : AnyCancellable?
    private var frames : Int = 0

    // MARK: public control ----------------------------------------------
    func start() {
        q.async { [weak self] in
            guard let self, self.stream == nil else { return dbg("start – already running") }
            Task { await self.makeStream() }
        }
    }

    func stop() {
        q.async { [weak self] in
            self?.finishSegment(restart: false)
            self?.stopStream()
        }
    }

    // MARK: stream setup -------------------------------------------------
    private func makeStream() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                               onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return dbg("no display") }

            let filter = SCContentFilter(display: display,
                                         excludingApplications: [],
                                         exceptingWindows: [])

            let cfg              = SCStreamConfiguration()
            cfg.width            = C.width
            cfg.height           = C.height
            cfg.capturesAudio    = false
            cfg.pixelFormat      = kCVPixelFormatType_32BGRA
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: C.fps) // 1 fps

            try await startStream(filter: filter, config: cfg)
        } catch {
            dbg("stream setup failed – \(error.localizedDescription)")
        }
    }

    @MainActor
    private func startStream(filter: SCContentFilter, config: SCStreamConfiguration) async throws {
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: q)
        try await s.startCapture()
        stream = s
        dbg("stream started")
    }

    private func stopStream() {
        if let s = stream { try? s.stopCapture() }
        reset(); dbg("stream stopped")
    }

    // MARK: segment rotation --------------------------------------------
    private func beginSegment() {
        guard writer == nil else { finishSegment(); return }
        let url = StorageManager.shared.nextFileURL(); fileURL = url; frames = 0

        do {
            let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let inp = AVAssetWriterInput(mediaType: .video,
                                         outputSettings: [
                                             AVVideoCodecKey  : AVVideoCodecType.h264,
                                             AVVideoWidthKey  : C.width,
                                             AVVideoHeightKey : C.height
                                         ])
            inp.expectsMediaDataInRealTime = true
            guard w.canAdd(inp) else { throw RecorderError.badInput }
            w.add(inp); writer = w; input = inp

            // auto‑finish after C.chunk seconds
            let t = DispatchSource.makeTimerSource(queue: q)
            t.schedule(deadline: .now() + C.chunk)
            t.setEventHandler { [weak self] in self?.finishSegment() }
            t.resume(); timer = t
        } catch {
            dbg("writer creation failed – \(error.localizedDescription)")
            StorageManager.shared.markChunkFailed(url: url); reset()
        }
    }

    private func finishSegment(restart: Bool = true) {
        timer?.cancel(); timer = nil
        guard let w = writer, let inp = input, let url = fileURL else { return reset() }
        inp.markAsFinished()
        w.finishWriting { [weak self] in
            if w.status == .completed {
                StorageManager.shared.markChunkCompleted(url: url)
            } else {
                StorageManager.shared.markChunkFailed(url: url)
            }
            self?.reset()
            if restart && AppState.shared.isRecording { self?.beginSegment() }
        }
    }

    private func reset() {
        timer = nil; writer = nil; input = nil; firstPTS = nil; fileURL = nil; frames = 0
    }

    // MARK: sample‑buffer handling ---------------------------------------
    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferDataIsReady(sb), isComplete(sb) else { return }
        if writer == nil { beginSegment() }
        guard let w = writer, let inp = input else { return }

        if firstPTS == nil {
            firstPTS = sb.presentationTimeStamp
            w.startWriting(); w.startSession(atSourceTime: firstPTS!)
        }

        if inp.isReadyForMoreMediaData, w.status == .writing {
            if inp.append(sb) { frames += 1 } else { finishSegment() }
        }
    }

    // MARK: error & sleep / wake ----------------------------------------
    func stream(_ s: SCStream, didStopWithError err: Error) {
        dbg("stream error – \(err.localizedDescription)")
        q.async { [weak self] in self?.finishSegment(restart: false); self?.stopStream() }
        if AppState.shared.isRecording { start() }
    }

    private func registerForSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            dbg("willSleep – pausing"); self?.stop()
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            dbg("didWake – checking flag"); if AppState.shared.isRecording { self?.start() }
        }
    }

    // MARK: helpers ------------------------------------------------------
    private enum RecorderError: Error { case badInput }

    /// Accept only fully‑assembled frames (complete & not dropped).
    private func isComplete(_ sb: CMSampleBuffer) -> Bool {
        guard let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo : Any]],
              let raw = arr.first?[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
