//
//  ScreenRecorder.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/26/25.
//  Updated with Sleep/Wake handling, SCStreamDelegate, and bug fixes.
//

import AppKit // Needed for NSWorkspace notifications
@preconcurrency import ScreenCaptureKit
import AVFoundation
import Combine

final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate { // Added SCStreamDelegate
    // MARK: – Queues & state
    private let queue = DispatchQueue(label: "com.amitine.screenrecorder.queue", qos: .userInitiated)
    private var stream: SCStream?               // The ScreenCaptureKit stream
    private var writer: AVAssetWriter?          // AVFoundation writer for the current chunk
    private var input:  AVAssetWriterInput?     // Video input for the writer
    private var sessionStarted = false          // Flag: Has startSession been called for the current writer?
    private var chunkTimer: DispatchSourceTimer? // Timer for rotating video file chunks
    private var cancellable: AnyCancellable?    // Combine cancellable for AppState subscription
    private var wantRecording = false           // Mirror of AppState.isRecording, accessed/modified on `queue`
    private var isRecordingActive = false       // Internal state: stream/writer actually running? Accessed/modified on `queue`
    private var wasRecordingBeforeSleep = false // State preservation across sleep, accessed/modified on `queue`
    private var currentFileURL: URL?            // Track the URL being written to, accessed/modified on `queue`

    // MARK: – Constants
    private let px = 1280 // Video width
    private let py = 720  // Video height
    private let fps: Double = 1 // Frames per second (low FPS for activity tracking)
    private let chunkSec: TimeInterval = 60 // Duration of each video chunk (1 minute)

    // Access the shared instances of AppState and StorageManager
    // Ensure these shared instances conform to the protocols defined above or adapt as needed
    private let appState: any AppStateManaging = AppState.shared
    private let store: any StorageManaging = StorageManager.shared

    // MARK: – Init
    override init() {
        super.init()

        // Subscribe on MainActor initially, then hop to recorder queue for handling
        Task { @MainActor in
            // Need to observe the specific @Published property correctly
            // Assuming AppState.shared has a @Published var isRecording: Bool
            self.cancellable = (appState as? AppState)?.objectWillChange // Or appropriate publisher
                .receive(on: queue) // Ensure state changes are handled on our dedicated queue
                .sink { [weak self] _ in // We just need notification, read value on queue
                    guard let self = self else { return }

                    let currentStateWantsRecording = self.appState.isRecording
                    let wasRecordingActive = self.isRecordingActive

                    // Check if desired state changed
                    if currentStateWantsRecording != self.wantRecording {
                         print("Recorder: AppState changed. isRecording=\(self.appState.isRecording) wantRecording=\(currentStateWantsRecording), wasActive=\(wasRecordingActive)")
                         self.wantRecording = currentStateWantsRecording // Update desired state

                        if currentStateWantsRecording && !wasRecordingActive {
                            // User wants to start, and we are not currently active
                            print("Recorder: Starting recording due to AppState change.")
                            self.startInternal()
                        } else if !currentStateWantsRecording && wasRecordingActive {
                            // User wants to stop, and we are currently active
                            print("Recorder: Stopping recording due to AppState change.")
                            self.stopInternal(reason: "AppState request")
                        }
                    }
                }
        }

        // --- Sleep/Wake Handling ---
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleDidWake), name: NSWorkspace.didWakeNotification, object: nil)

        print("Recorder: Initialized and listening for AppState changes and Sleep/Wake notifications.")
    }

    deinit {
        print("Recorder: Deinitializing.")
        // Clean up observers
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        cancellable?.cancel()
        // Ensure stop is called if object is deallocated while recording
        if isRecordingActive {
            // Use async from deinit to avoid potential deadlocks if queue is busy
            queue.async {
                self.stopInternal(reason: "Deinitialization")
            }
        }
    }

    // MARK: – Capture lifecycle Control (Internal)

    /// Sets up and starts the SCStream, writer, and timer. Must be called on the `queue`.
    private func startInternal() {
        guard !isRecordingActive else {
            print("Recorder: Already recording, ignoring startInternal call.")
            return
        }
        guard wantRecording else {
            print("Recorder: Start requested but AppState no longer wants recording.")
            return
        }

        print("Recorder: Starting internal...")
        isRecordingActive = true // Set early to prevent race conditions on the queue

        // Asynchronously fetch shareable content, then continue setup on queue
        Task(priority: .userInitiated) {
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else {
                    print("Recorder Error: No display found.")
                    queue.async { [weak self] in self?.stopInternal(reason: "No display found") }
                    return
                }

                let cfg = SCStreamConfiguration()
                cfg.width  = px
                cfg.height = py
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
                cfg.queueDepth = 5
                cfg.capturesAudio = false
                cfg.showsCursor = true

                let filter = SCContentFilter(display: display, excludingWindows: [])

                // --- Continue setup on the dedicated queue ---
                queue.async { [weak self] in
                    guard let self = self, self.isRecordingActive else {
                        print("Recorder: Recording cancelled before stream setup could complete on queue.")
                        return
                    }

                    // Create the stream, set delegate to self for error handling
                    self.stream = SCStream(filter: filter, configuration: cfg, delegate: self) // Set delegate

                    // Create a new Task to handle the async startCapture within the sync queue block
                    Task {
                        do {
                            // Add output handler *before* starting capture
                            try self.stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)

                            // Start capture - this is asynchronous
                            try await self.stream?.startCapture()

                             // Check again if we are still supposed to be active after await completes
                            // Must re-capture self strongly inside this Task's context
                            guard self.isRecordingActive else {
                                print("Recorder: Recording cancelled immediately after startCapture returned.")
                                self.stream?.stopCapture { _ in self.stream = nil }
                                return
                            }

                            // Setup writer and timer *after* capture starts successfully
                            // These need to run on the queue, which this Task inherits
                            print("Recorder: Stream capture started successfully.")
                            self.openWriter() // Creates the file and writer instance
                            self.armTimer()   // Starts the chunk rotation timer

                        } catch {
                             // Must re-capture self strongly inside this Task's context
                            print("Recorder Error: Failed to setup stream output or start capture - \(error.localizedDescription)")
                            // Clean up fully if any part of the setup failed
                            // Dispatch back to queue if necessary, though Task inherits it
                            self.stopInternal(reason: "Stream setup/start failed")
                        }
                    }
                }
            } catch {
                 print("Recorder Error: Failed to get shareable content - \(error.localizedDescription)")
                 queue.async { [weak self] in self?.stopInternal(reason: "SCShareableContent failed") }
            }
        }
    }

    /// Stops the stream, finalizes the writer, and cancels the timer. Must be called on the `queue`.
    private func stopInternal(reason: String = "Unknown") {
        guard isRecordingActive else {
            if reason != "Deinitialization" && reason != "AppState request" {
                 print("Recorder: stopInternal called but not active. Reason: \(reason)")
            }
            return
        }
        print("Recorder: Stopping internal... Reason: \(reason)")

        isRecordingActive = false
        // wasRecordingBeforeSleep = false

        // 1. Cancel the timer
        chunkTimer?.cancel()
        chunkTimer = nil
        print("Recorder: Chunk timer cancelled.")

        // 2. Stop the stream (async)
        guard let streamToStop = stream else {
            print("Recorder: Stream already nil during stop.")
            self.closeWriter() // Ensure writer is closed if stream was already gone
            self.stream = nil
            return
        }
        self.stream = nil // Clear stream ref before async stop call

        streamToStop.stopCapture { [weak self] error in
             self?.queue.async { // Dispatch completion handler to queue
                 guard let self = self else { return }
                 if let error = error {
                     print("Recorder Error: Failed to stop stream - \(error.localizedDescription)")
                 } else {
                     print("Recorder: Stream stopped successfully.")
                 }
                 // 3. Close the writer *after* stream stop completes or fails.
                 self.closeWriter()
            }
        }
    }

    // MARK: - Sleep/Wake Handling

    @objc private func handleWillSleep(_ notification: Notification) {
        print("Recorder: Received willSleep notification.")
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.isRecordingActive {
                print("Recorder: Stopping recording before sleep.")
                self.wasRecordingBeforeSleep = true
                self.stopInternal(reason: "System sleep")
            } else {
                print("Recorder: Was not recording before sleep.")
                self.wasRecordingBeforeSleep = false
            }
        }
    }

    @objc private func handleDidWake(_ notification: Notification) {
        print("Recorder: Received didWake notification.")
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.wantRecording && self.wasRecordingBeforeSleep {
                print("Recorder: Resuming recording after wake.")
                self.wasRecordingBeforeSleep = false
                self.startInternal()
            } else {
                 print("Recorder: Not resuming recording after wake. wantRecording=\(self.wantRecording), wasRecordingBeforeSleep=\(self.wasRecordingBeforeSleep)")
                 self.wasRecordingBeforeSleep = false
            }
        }
    }

    // MARK: – Timer & Chunk Rotation

    /// Sets up and starts the chunk rotation timer. Must be called on the `queue`.
    private func armTimer() {
        guard isRecordingActive else {
             print("Recorder: Attempted to arm timer while not active.")
             return
        }
        chunkTimer?.cancel()
        chunkTimer = DispatchSource.makeTimerSource(queue: queue)
        chunkTimer?.schedule(deadline: .now() + chunkSec, repeating: chunkSec)
        chunkTimer?.setEventHandler { [weak self] in
            self?.rotateChunk()
        }
        chunkTimer?.resume()
        print("Recorder: Chunk timer armed for \(chunkSec) seconds.")
    }

    /// Closes the current writer/file and opens a new one. Must be called on the `queue`.
    private func rotateChunk() {
        guard isRecordingActive else {
            print("Recorder: rotateChunk called but not actively recording. Ignoring.")
            return
        }
        print("Recorder: Rotating chunk...")
        // 1. Finalize the current chunk
        closeWriter()

        // 2. Open the next chunk after brief async dispatch to allow closeWriter completion
        queue.async { [weak self] in
             guard let self = self, self.isRecordingActive else {
                 print("Recorder: Recording stopped during chunk rotation gap.")
                 return
             }
             print("Recorder: Opening new chunk after rotation.")
             self.openWriter()
        }
    }

    // MARK: – AVAssetWriter Helpers

    /// Creates a new file URL, initializes the AVAssetWriter and input. Must be called on the `queue`.
    private func openWriter() {
        guard isRecordingActive else {
             print("Recorder Error: Attempted to open writer while not actively recording.")
             writer = nil; input = nil; currentFileURL = nil; sessionStarted = false
             return
        }
        if writer != nil || input != nil || currentFileURL != nil {
            print("Recorder Warning: openWriter called but previous writer resources might still exist. Forcing cleanup.")
            writer = nil; input = nil; currentFileURL = nil;
        }

        let url = store.nextFileURL()
        self.currentFileURL = url
        print("Recorder: Opening writer for URL: \(url.lastPathComponent)")

        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            print("Recorder Error: Failed to create AVAssetWriter for \(url.lastPathComponent) - \(error.localizedDescription)")
            self.currentFileURL = nil
            stopInternal(reason: "Writer creation failed")
            return
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: px,
            AVVideoHeightKey: py,
            AVVideoCompressionPropertiesKey: [
                 AVVideoAverageBitRateKey: 500_000,
                 AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                 AVVideoAllowFrameReorderingKey: false,
             ]
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input?.expectsMediaDataInRealTime = true

        if let input = input, writer?.canAdd(input) == true {
            writer?.add(input)
        } else {
            print("Recorder Error: Could not add AVAssetWriterInput for \(url.lastPathComponent).")
            writer = nil; input = nil; self.currentFileURL = nil
            stopInternal(reason: "Adding writer input failed")
            return
        }

        // Reset session started flag for the new writer
        sessionStarted = false

        if writer?.startWriting() == true {
            print("Recorder: Writer started for \(url.lastPathComponent), waiting for first frame.")
            store.registerChunk(url: url)
        } else {
            let writerError = writer?.error?.localizedDescription ?? "Unknown error"
            let writerStatus = writer?.status.rawValue ?? -99
            print("Recorder Error: AVAssetWriter failed to startWriting for \(url.lastPathComponent). Status: \(writerStatus), Error: \(writerError)")
            self.currentFileURL = nil; self.writer = nil; self.input = nil
            stopInternal(reason: "Writer startWriting failed")
        }
    }

    /// Marks the input as finished and finalizes the AVAssetWriter. Must be called on the `queue`.
    private func closeWriter() {
        guard let writerToClose = writer, let inputToFinish = input, let urlToClose = currentFileURL else {
            self.writer = nil; self.input = nil; self.currentFileURL = nil; sessionStarted = false
            return
        }
        guard writerToClose.status == .writing else {
            print("Recorder: closeWriter called for \(urlToClose.lastPathComponent), but writer status is not 'writing' (Status: \(writerToClose.status.rawValue)). Assuming already closing or failed.")
            if writerToClose.status != .completed {
                 self.writer = nil; self.input = nil; self.currentFileURL = nil; sessionStarted = false
            }
            return
        }

        print("Recorder: Closing writer for URL: \(urlToClose.lastPathComponent)")

        inputToFinish.markAsFinished()

        // Clear internal references *before* calling async finishWriting.
        self.writer = nil
        self.input = nil
        self.currentFileURL = nil
        self.sessionStarted = false // Reset session flag

        writerToClose.finishWriting { [weak self] in
            // Completion handler might run on any thread.
            guard let self = self else { return }
            let finalStatus = writerToClose.status

            if finalStatus == .completed {
                print("Recorder: Writer for \(urlToClose.lastPathComponent) finished successfully.")
                // FIXME: Adapt this call to your actual StorageManager method
                self.store.markChunkCompleted(url: urlToClose)
            } else {
                let errorDesc = writerToClose.error?.localizedDescription ?? "Unknown error"
                print("Recorder Error: Writer for \(urlToClose.lastPathComponent) failed. Final Status: \(finalStatus.rawValue), Error: \(errorDesc)")
                // FIXME: Adapt this call to your actual StorageManager method
                self.store.markChunkFailed(url: urlToClose)
            }
        }
    }

    // MARK: – SCStreamOutput Handler
    // Runs on the `queue`
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sb: CMSampleBuffer,
                of type: SCStreamOutputType) {

        guard CMSampleBufferIsValid(sb), CMSampleBufferGetNumSamples(sb) > 0 else { return }
        guard type == .screen else { return }

        guard isRecordingActive,
              let currentWriter = writer, let currentInput = input,
              currentWriter.status == .writing else {
            return // Not active or writer not ready
        }

        guard currentInput.isReadyForMoreMediaData else {
            print("Recorder Warning: Input not ready for more media data, frame dropped.")
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        guard pts.isValid else {
            print("Recorder Error: Received buffer with invalid timestamp.")
            return
        }

        // Start the AVAssetWriter session exactly once when the first valid buffer arrives
        if !sessionStarted {
            print("Recorder: Starting writer session at PTS: \(CMTimeGetSeconds(pts))")
            currentWriter.startSession(atSourceTime: pts)
            sessionStarted = true // Mark session as started for this writer instance
        }

        // Append the buffer
        if !currentInput.append(sb) {
            let errorDesc = currentWriter.error?.localizedDescription ?? "Unknown error"
            print("Recorder Error: Failed to append sample buffer. Writer status: \(currentWriter.status.rawValue), Error: \(errorDesc)")
            queue.async { [weak self] in // Dispatch async to avoid deadlock
                 if self?.isRecordingActive == true {
                     self?.stopInternal(reason: "Append buffer failed")
                 }
             }
        }
    }

    // MARK: - SCStreamDelegate Implementation
    // Runs on an arbitrary thread, dispatch to queue needed
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { [weak self] in
            guard let self = self else { return }
            // Only act if we were active when the error occurred.
            if self.isRecordingActive {
                 print("Recorder Error: Stream stopped unexpectedly! Error: \(error.localizedDescription)")
                 self.stopInternal(reason: "Stream error delegate")
            } else {
                 print("Recorder Info: Stream stopped with error, but recorder was already stopping/stopped.")
            }
        }
    }
}
