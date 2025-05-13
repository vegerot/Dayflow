//  ScreenRecorder.swift
//  Dayflow
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
    static let fps    : Int32 = 1               // keep @ 1 fps
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
    private var isStarting = false            // guards concurrent starts
    private var resumeAfterSleep = false      // remember intent across sleep

    // MARK: public control ----------------------------------------------
    func start() {
        q.async { [weak self] in
            guard let self else { return }
            guard self.stream == nil,       // not already running
                  self.isStarting == false  // not already starting
            else { return dbg("start – already starting/running") }

            self.isStarting = true          // ←–––– set once
            Task { await self.makeStream() }
        }
    }

    func stop() {
        q.async { [weak self] in
            guard let self else { return }
            self.isStarting = false         // ←–––– clear **immediately**
            
            self.finishSegment(restart: false)
            self.stopStream()               // (stopStream also calls reset())
        }
    }

    private func shouldRetry(_ err: Error) -> Bool {
        let scErr = err as NSError
        return scErr.domain == SCStreamErrorDomain               // "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
            && scErr.code == -3807                                // kSCStreamErrorNoDisplayOrWindow
    }
    
    // MARK: stream setup -------------------------------------------------
    private func makeStream(attempt: Int = 1, maxAttempts: Int = 4) async {
        do {
            // 1. find a display
            let content = try await SCShareableContent
                .excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let display = content.displays.first else {
                throw RecorderError.noDisplay          // ← uses the new case
            }

            // 2. filter
            let filter = SCContentFilter(display: display,
                                         excludingApplications: [],
                                         exceptingWindows: [])

            // 3. configuration  ←–––– THIS IS THE cfg THAT MUST EXIST
            let cfg                 = SCStreamConfiguration()
            cfg.width               = C.width
            cfg.height              = C.height
            cfg.capturesAudio       = false
            cfg.pixelFormat         = kCVPixelFormatType_32BGRA
            cfg.minimumFrameInterval = CMTime(value: 1,
                                              timescale: C.fps)   // 1 fps

            // 4. kick‑off
            try await startStream(filter: filter, config: cfg)
        }
        catch {
            dbg("makeStream failed [attempt \(attempt)] – \(error.localizedDescription)")

            // ALWAYS clear the flag on failure
            q.async { self.isStarting = false }

            // transient "no display" → retry
            if attempt < maxAttempts, shouldRetry(error) {
                let delay = Double(attempt)             // 1 s, 2 s, 3 s …
                dbg("retrying in \(delay)s")
                q.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.start()                       // sets isStarting again
                }
            }
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
        stream = nil
        isStarting = false
        reset(); dbg("stream stopped")
    }

    // MARK: segment rotation --------------------------------------------
    private func beginSegment() {
        guard writer == nil else { finishSegment(); return }
        let url = StorageManager.shared.nextFileURL(); fileURL = url; frames = 0

        StorageManager.shared.registerChunk(url: url)
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
        // 1. stop the timer that would have closed the file
        timer?.cancel()
        timer = nil

        // 2. make sure we even have something to finish
        guard let w = writer, let inp = input, let url = fileURL else {
            return reset()
        }

        // ── EARLY EXIT ────────────────────────────────────────────────────
        // If *no* sample was ever appended, calling `markAsFinished()` is
        // illegal and crashes.  Instead: cancel the writer and flag the file
        // as failed / empty.
        guard frames > 0 else {
            w.cancelWriting()
            StorageManager.shared.markChunkFailed(url: url)      // or "skipped"
            return reset()
        }
        // ─────────────────────────────────────────────────────────────────

        // 3. only close a writer that is actually in `.writing`
        guard w.status == .writing else {
            w.cancelWriting()
            StorageManager.shared.markChunkFailed(url: url)
            return reset()
        }

        // 4. normal shutdown path
        inp.markAsFinished()
        w.finishWriting { [weak self] in
            if w.status == .completed {
                StorageManager.shared.markChunkCompleted(url: url)
            } else {
                StorageManager.shared.markChunkFailed(url: url)
            }
            self?.reset()
            if restart && AppState.shared.isRecording {
                self?.beginSegment()
            }
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
        stop()
        if AppState.shared.isRecording { start() }
    }

    private func registerForSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter

        // -------- system will sleep ----------
        nc.addObserver(forName: NSWorkspace.willSleepNotification,
                       object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            dbg("willSleep – pausing")

            // remember whether we should resume afterwards
            resumeAfterSleep = AppState.shared.isRecording
            stop()
        }

        // -------- system did wake ------------
        nc.addObserver(forName: NSWorkspace.didWakeNotification,
                       object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            dbg("didWake – checking flag")

            guard resumeAfterSleep else { return }
            resumeAfterSleep = false      // consume the token

            // give ScreenCaptureKit a moment to re‑enumerate displays
            q.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.start()
            }
        }
    }


    // MARK: helpers ------------------------------------------------------
    private enum RecorderError: Error { case badInput
        case noDisplay }

    /// Accept only fully‑assembled frames (complete & not dropped).
    private func isComplete(_ sb: CMSampleBuffer) -> Bool {
        guard let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo : Any]],
              let raw = arr.first?[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
