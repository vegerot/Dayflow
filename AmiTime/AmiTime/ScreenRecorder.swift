//
//  ScreenRecorder.swift
//  AmiTime
//
//  Records the main display at 1280×720, saving 15‑second .mp4
//  segments while AppState.shared.isRecording is true.
//
//  Created 5 May 2025.
//
//  *** DEBUG VERSION: Includes extensive print statements ***
//

import Foundation
@preconcurrency import ScreenCaptureKit
import AVFoundation
import Combine

private enum C {
    static let width  = 1280
    static let height = 720
    static let chunk  : TimeInterval = 15
    static let debugPrefix = "[DEBUG ScreenRecorder]" // Prefix for easy filtering
}

/// Minimal, self‑restarting screen recorder.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {

    @MainActor
    init(autoStart: Bool = true) {
        super.init()
        print("\(C.debugPrefix) 💡 Initializing ScreenRecorder. AutoStart: \(autoStart)")

        // Observe AppState.isRecording on the main actor
        sub = AppState.shared.$isRecording
            .dropFirst() // <---- *** ADD THIS LINE ***
            .removeDuplicates()
            .sink { [weak self] rec in
                // This sink will now ONLY be called for CHANGES *after* initialization
                print("\(C.debugPrefix) 🔔 AppState.isRecording CHANGED to: \(rec)")
                rec ? self?.start() : self?.stop()
            }

        // This auto-start logic now runs *before* the sink processes any changes
        if autoStart, AppState.shared.isRecording {
            print("\(C.debugPrefix) 🚀 Auto-starting based on AppState during init.")
            start() // Call start ONCE here if needed
        } else {
            print("\(C.debugPrefix) 😴 Not auto-starting during init. isRecording: \(AppState.shared.isRecording)")
        }
    }

    deinit {
        print("\(C.debugPrefix) 💀 Deinitializing ScreenRecorder.")
        // Ensure resources are cleaned up if the instance is destroyed
        timer?.cancel()
        sub?.cancel()
        // Consider calling stop() here if necessary, ensuring it's safe from a deinit context
        // q.sync { self.finishSegment(); self.stopStream() } // Might be risky in deinit
    }

    // MARK: – Private state
    private let q = DispatchQueue(label: "com.amitine.recorder", qos: .userInitiated)
    private var stream : SCStream?
    private var writer : AVAssetWriter?
    private var input  : AVAssetWriterInput?
    private var firstPTS: CMTime?
    private var timer  : DispatchSourceTimer?
    private var fileURL: URL?
    private var sub    : AnyCancellable?
    private var framesThisSegment = 0
}

// MARK: – Public control
private extension ScreenRecorder {
    func start() {
        // Ensure this runs on the correct queue or synchronize access
        q.async { // Or use a synchronous check if appropriate
            guard self.stream == nil else {
                print("\(C.debugPrefix) ⚠️ start() called but stream already exists or is starting. Ignoring.")
                return
            }
            // Optional: Add a state variable like `isStarting` to prevent concurrent makeStream calls
            print("\(C.debugPrefix) ▶️ start() called. Queuing makeStream on internal queue.")
            self.makeStream() // No further async needed if start() is already on 'q'
        }
    }
    func stop() {
        print("\(C.debugPrefix) ⏹️ stop() called. Queuing finishSegment & stopStream on internal queue.")
        q.async {
            print("\(C.debugPrefix) ⏹️ Executing stop() tasks on queue...")
            self.finishSegment() // Finish current segment first
            self.stopStream()    // Then stop the stream
            print("\(C.debugPrefix) ⏹️ stop() tasks completed on queue.")
        }
    }
}

// MARK: – Stream lifecycle
private extension ScreenRecorder {

    /// Build a new SCStream asynchronously.
    func makeStream() {
            // Guard moved to start() which calls this
            // guard stream == nil else { ... }

            print("\(C.debugPrefix) ⚙️ makeStream() invoked on queue. Starting Task.detached...")

            Task.detached(priority: .userInitiated) { [weak self] in
                 print("\(C.debugPrefix) ⚙️ Task.detached running...")
                guard let self else {
                     print("\(C.debugPrefix) ❌ Task.detached found self is nil. Aborting.")
                    return
                }
                do {
                    // 1. Pick the main display
                    print("\(C.debugPrefix) ⚙️ Getting shareable content...")
                    let content = try await SCShareableContent
                        .excludingDesktopWindows(false, onScreenWindowsOnly: true)
                    print("\(C.debugPrefix) ⚙️ Got shareable content. Displays count: \(content.displays.count)")

                    guard let display = content.displays.first else {
                        print("\(C.debugPrefix) ❌ No display found in shareable content. Cannot start stream.")
                        return
                    }
                    print("\(C.debugPrefix) ⚙️ Using display: \(display.displayID)")

                    // 2. Content filter
                    let filter = SCContentFilter(
                        display: display,
                        excludingApplications: [],
                        exceptingWindows: [])
                    print("\(C.debugPrefix) ⚙️ Created SCContentFilter for display \(display.displayID)")

                    // 3. Stream config - *** ADD EXPLICIT SETTINGS ***
                    let cfg = SCStreamConfiguration()
                    cfg.width = C.width
                    cfg.height = C.height
                    cfg.capturesAudio = false
                    // Set Pixel Format explicitly (BGRA is common and well-supported)
                    cfg.pixelFormat = kCVPixelFormatType_32BGRA // 'BGRA'
                    // Set Minimum Frame Interval (e.g., target 30fps)
                    // This helps stabilize the input rate for the encoder.
                    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                    // Optional: Try 15 fps if 30 still fails: CMTime(value: 1, timescale: 15)
                    // Optional: Can also set maximumFrameRate if needed, but min interval is often enough.

                    // Updated log to show new settings
                    let pixelFormatString = String(fourCC: cfg.pixelFormat) ?? "\(cfg.pixelFormat)" // Use the corrected helper
                    print("\(C.debugPrefix) ⚙️ Created SCStreamConfiguration: \(C.width)x\(C.height), Audio: \(cfg.capturesAudio), PixelFormat: '\(pixelFormatString)', MinInterval: \(cfg.minimumFrameInterval.seconds) (\(String(format: "%.1f", 1.0/cfg.minimumFrameInterval.seconds)) fps target)") // Added formatting for FPS


                    // 4. Start capture on MainActor
                     print("\(C.debugPrefix) ⚙️ Switching to MainActor to call startStream...")
                    try await self.startStream(filter: filter, config: cfg)
                     print("\(C.debugPrefix) ⚙️ Returned from startStream on MainActor.")

                } catch {
                    print("\(C.debugPrefix) ❌❌❌ ScreenRecorder setup error in makeStream Task: \(error.localizedDescription)")
                    // Consider cleanup or retry logic here
                }
            }
        }

    @MainActor
    func startStream(filter: SCContentFilter, config: SCStreamConfiguration) async throws {
        print("\(C.debugPrefix) 🎬 Starting startStream (on MainActor)...")
        do {
            let s = SCStream(filter: filter, configuration: config, delegate: self)
            print("\(C.debugPrefix) 🎬 SCStream initialized.")

            print("\(C.debugPrefix) 🎬 Adding stream output...")
            try s.addStreamOutput(
                self,
                type: SCStreamOutputType.screen,
                sampleHandlerQueue: q) // Ensure callbacks happen on our dedicated queue
            print("\(C.debugPrefix) 🎬 Stream output added.")

            print("\(C.debugPrefix) 🎬 Calling s.startCapture()... (awaiting)")
            try await s.startCapture()
            print("\(C.debugPrefix) 🎬 s.startCapture() completed.")
            stream = s
            print("\(C.debugPrefix) 🎬 Stream reference stored.")

            // REMOVED: q.async { [weak self] in self?.beginSegment() }
            print("\(C.debugPrefix) 🎬 Stream started. First segment will be created upon receiving the first frame.")

        } catch {
            print("\(C.debugPrefix) ❌❌❌ Failed during startStream (MainActor): \(error.localizedDescription)")
            stream = nil
            throw error
        }
    }

    func stopStream() {
        print("\(C.debugPrefix) 🛑 Stopping stream (stopStream)...")
        guard let s = stream else {
            print("\(C.debugPrefix) 🛑 Stream already nil. Nothing to stop.")
            return
        }
        do {
            // We don't use await here as per original code, assuming sync stop is fine
            // If async stop is needed: Task { try? await s.stopCapture() } but manage concurrency carefully
            try s.stopCapture()
            print("\(C.debugPrefix) 🛑 Stream stopCapture() called successfully.")
        } catch {
            print("\(C.debugPrefix) ❌ Error stopping stream: \(error.localizedDescription)")
        }
        stream = nil
        print("\(C.debugPrefix) 🛑 Stream reference set to nil.")
    }
}

// MARK: – 15‑second segment rotation
private extension ScreenRecorder {

    func isValidFrame(_ sb: CMSampleBuffer) -> Bool {
        guard
            let attaches = CMSampleBufferGetSampleAttachmentsArray(sb,
                           createIfNecessary: false) as? [[SCStreamFrameInfo : Any]],
            let first    = attaches.first,
            let raw      = first[SCStreamFrameInfo.status] as? Int,
            let status   = SCFrameStatus(rawValue: raw),
            status == .complete
        else { return false }

        return true
    }
    
    func beginSegment() {
            print("\(C.debugPrefix) 🎬 ⏱️ beginSegment() called.")

            // Safety: if a writer is still around, finish it first and bail.
            guard writer == nil else {
                print("\(C.debugPrefix) ⚠️ beginSegment() invoked while writer != nil. Finishing current segment first.")
                finishSegment()          // will relaunch beginSegment() once safe
                return
            }

            //–––– 1. Create output URL ––––
            let url = StorageManager.shared.nextFileURL()
            print("\(C.debugPrefix) 📂 Next segment URL → \(url.lastPathComponent)")
            StorageManager.shared.registerChunk(url: url)

            fileURL = url
            framesThisSegment = 0

            do {
                //–––– 2. Build writer & input ––––
                print("\(C.debugPrefix) ✍️ Creating AVAssetWriter(.mp4)…")
                let w = try AVAssetWriter(outputURL: url, fileType: .mp4)

                let settings: [String: Any] = [
                    AVVideoCodecKey  : AVVideoCodecType.h264,
                    AVVideoWidthKey  : C.width,
                    AVVideoHeightKey : C.height,
                ]

                let inp = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                inp.expectsMediaDataInRealTime = true

                guard w.canAdd(inp) else {
                    print("\(C.debugPrefix) ❌ can’t add input; aborting segment.")
                    StorageManager.shared.markChunkFailed(url: url)
                    return
                }
                w.add(inp)

                writer = w
                input  = inp
                firstPTS = nil
                print("\(C.debugPrefix) ✍️ Writer ready for \(url.lastPathComponent)")

                //–––– 3. Schedule timer to *finish* this segment ––––
                print("\(C.debugPrefix) ⏱️ Timer set for \(C.chunk) s to finish segment.")
                let t = DispatchSource.makeTimerSource(queue: q)
                t.schedule(deadline: .now() + C.chunk)
                t.setEventHandler { [weak self] in
                    print("\(C.debugPrefix) 🔥 Timer fired → finishing segment.")
                    self?.finishSegment()        // serialised rollover
                }
                t.resume()
                timer = t

            } catch {
                print("\(C.debugPrefix) ❌ Writer creation failed: \(error.localizedDescription)")
                StorageManager.shared.markChunkFailed(url: url)
                resetState()
            }
        }

    // MARK: – 15‑second segment rotation (serialised)
    /**
     Finishes the *current* segment and, **only after the encoder is
     fully flushed**, optionally starts the next one.

     - Important: Call **only** from the recorder’s queue `q`.
                  (The `stream(_:didOutput…)` callback already runs there.)
     */
    func finishSegment(restartIfNeeded: Bool = true) {
        //–––– 1. Stop the timer driving this segment ––––
        if let t = timer {
            t.cancel()
            timer = nil
            print("\(C.debugPrefix) 🏁 Timer cancelled.")
        }

        //–––– 2. Verify we have something to finish ––––
        guard let w   = writer,
              let inp = input,
              let url = fileURL else {
            print("\(C.debugPrefix) ⏭️ finishSegment: nothing to finish.")
            resetState()
            return
        }

        let frames = framesThisSegment
        let preStatus = w.status
        print("\(C.debugPrefix) 🏁 Writer status before finish ⇒ \(preStatus.rawValue)")

        //–––– 3. If we never entered .writing, bail out early ––––
        guard preStatus == .writing else {
            print("\(C.debugPrefix) ⏭️ Writer isn’t writing (status \(preStatus)); marking as failed.")
            StorageManager.shared.markChunkFailed(url: url)
            resetState()
            return
        }

        //–––– 4. Ask the writer to finish ––––
        inp.markAsFinished()
        w.finishWriting { [weak self, url, frames] in
            guard let self else { return }

            let postStatus = w.status
            let err        = w.error
            if postStatus == .completed {
                print("\(C.debugPrefix) ✅ Segment finished → \(url.lastPathComponent) (\(frames) frames)")
                StorageManager.shared.markChunkCompleted(url: url)
            } else {
                print("\(C.debugPrefix) ❌ Segment FAILED  → \(url.lastPathComponent). " +
                      "status \(postStatus.rawValue), err: \(err?.localizedDescription ?? "nil")")
                StorageManager.shared.markChunkFailed(url: url)
            }

            //–––– 5. Cleanup state *after* the writer is fully done ––––
            self.resetState()

            //–––– 6. If the user is still recording, start the next segment ––––
            if restartIfNeeded {
                Task { @MainActor in
                    if AppState.shared.isRecording {
                        self.q.async { [weak self] in self?.beginSegment() }
                    } else {
                        print("\(C.debugPrefix) 🏁 Recording stopped – no new segment.")
                    }
                }
            }
        }
    }

    /** Resets all per‑segment ivars.
        Must be called on queue `q`. */
    private func resetState() {
        timer = nil
        writer = nil
        input  = nil
        fileURL = nil
        firstPTS = nil
        framesThisSegment = 0
    }
}

// MARK: – SCStreamOutput
extension ScreenRecorder {
    func stream(_ s: SCStream,
                    didOutputSampleBuffer sb: CMSampleBuffer,
                    of type: SCStreamOutputType) {

            // Basic checks first
            guard type == .screen,
                  CMSampleBufferDataIsReady(sb),
                  isValidFrame(sb)          // ⬅️ new check
            else { return }

            // --- Check if writer needs creation (first frame overall) ---
            if writer == nil {
                print("\(C.debugPrefix) ✨ Writer is nil. First frame overall received! Calling beginSegment() synchronously on queue 'q'.")
                // Since we are already on queue 'q', call beginSegment directly.
                beginSegment()

                // Check if writer was successfully created.
                guard writer != nil, input != nil else {
                    print("\(C.debugPrefix) ❌ beginSegment() was called but writer/input is still nil after attempt. Cannot process frame.")
                    // Consider stopping the stream or implementing retry logic here.
                    return
                }
                print("\(C.debugPrefix) ✨ beginSegment() completed. Writer/Input should now be ready for first frame.")
                // Since this IS the first frame, we proceed directly to starting the writer below.
            }

            // Get writer/input (should definitely exist now unless beginSegment failed above)
            guard let inp = input, let w = writer else {
                print("\(C.debugPrefix) ⚠️ CRITICAL: Writer/Input is nil even after creation check! Should not happen. FileURL: \(fileURL?.lastPathComponent ?? "N/A")")
                return // Should not be reached if beginSegment worked
            }

            // --- Handle the first frame *of the current segment* ---
            if firstPTS == nil {
                // This block handles the very first frame of a new segment that needs to start the writing session.

                // Check writer status BEFORE starting
                guard w.status == .unknown else {
                    print("\(C.debugPrefix) ❌ Writer status for \(fileURL?.lastPathComponent ?? "?") is not '.unknown' (\(w.status.rawValue)) before starting session. Error: \(w.error?.localizedDescription ?? "nil"). Aborting segment.")
                    // Reset state and wait for next timer/frame to potentially start fresh segment
                    self.timer?.cancel(); self.timer = nil
                    self.writer = nil; self.input = nil; self.fileURL = nil; self.firstPTS = nil; self.framesThisSegment = 0
                    // Mark as failed in StorageManager if needed
                    if let url = fileURL { StorageManager.shared.markChunkFailed(url: url) }
                    return
                }

                firstPTS = sb.presentationTimeStamp // Set the start time for this specific segment
                print("\(C.debugPrefix) ✨ First frame *for this segment* (\(fileURL?.lastPathComponent ?? "?")). PTS: \(firstPTS!.seconds). Calling startWriting/startSession.")
                w.startWriting()

                // Check status AFTER startWriting
                guard w.status == .writing else {
                    print("\(C.debugPrefix) ❌ Writer status for \(fileURL?.lastPathComponent ?? "?") did not become '.writing' (\(w.status.rawValue)) after startWriting(). Error: \(w.error?.localizedDescription ?? "nil"). Aborting segment.")
                    if let url = fileURL { StorageManager.shared.markChunkFailed(url: url) }
                    self.timer?.cancel(); self.timer = nil
                    self.writer = nil; self.input = nil; self.fileURL = nil; self.firstPTS = nil; self.framesThisSegment = 0
                    return
                }

                print("\(C.debugPrefix) ✨ Calling startSession(atSourceTime: \(firstPTS!.seconds)) for \(fileURL?.lastPathComponent ?? "?")")
                w.startSession(atSourceTime: firstPTS!)
                print("\(C.debugPrefix) ✨ Writer session started for \(fileURL?.lastPathComponent ?? "?"). Status: \(w.status.rawValue)") // Should be .writing (1)

                // NOW, attempt to append this first frame immediately.
                // We DON'T check isReadyForMoreMediaData for the very first append.
                print("\(C.debugPrefix) ✨ Attempting to append the very first frame (Frame 1) for \(fileURL?.lastPathComponent ?? "?")...")
                if inp.append(sb) {
                     framesThisSegment += 1
                     print("\(C.debugPrefix) ✅ First frame appended successfully (Frame \(framesThisSegment)) for \(fileURL?.lastPathComponent ?? "?").")
                } else {
                     // Handle append failure for the *first* frame
                     let status = w.status
                     let nsError = w.error as? NSError
                     print("\(C.debugPrefix) ❌❌❌ append() FAILED for FIRST frame of \(fileURL?.lastPathComponent ?? "?"). Writer status: \(status.rawValue). Error: \(nsError?.localizedDescription ?? "nil")")
                     if let error = w.error { print("\(C.debugPrefix) Error details: \(error)") }
                     // Call finishSegment immediately on the same queue
                     print("\(C.debugPrefix) ❌ Calling finishSegment() immediately due to FIRST frame append failure.")
                     finishSegment() // Finish the failed segment
                }
                // We are done processing this first frame.
                return // Exit here after handling the first frame.
            }

            // --- Processing for SUBSEQUENT frames (where firstPTS is NOT nil) ---

            // Check if input can accept more data
            guard inp.isReadyForMoreMediaData else {
                // This is expected sometimes under load. PTS might be useful here too.
                let currentPTS = sb.presentationTimeStamp.seconds
                print("\(C.debugPrefix) ⚠️ Input not ready for more data. Dropping SUBSEQUENT frame \(framesThisSegment + 1) (PTS: \(currentPTS)) for \(fileURL?.lastPathComponent ?? "?").")
                return
            }

            // Ensure writer is still in .writing state for subsequent frames
             guard w.status == .writing else {
                 let currentPTS = sb.presentationTimeStamp.seconds
                 print("\(C.debugPrefix) ⚠️ Attempted to append subsequent frame \(framesThisSegment + 1) (PTS: \(currentPTS)) but writer status is \(w.status.rawValue), not .writing. Frame dropped for \(fileURL?.lastPathComponent ?? "?"). Error: \(w.error?.localizedDescription ?? "nil")")
                // This might happen if the writer failed asynchronously between frames.
                // Consider calling finishSegment here if status is .failed or .cancelled
                if w.status == .failed || w.status == .cancelled {
                    print("\(C.debugPrefix) ⚠️ Writer is failed/cancelled. Calling finishSegment() immediately.")
                    finishSegment()
                }
                return
            }

            // *** ADDED DETAILED LOGGING BEFORE SUBSEQUENT APPEND ***
            let currentPTS = sb.presentationTimeStamp.seconds
            let frameNumber = framesThisSegment + 1
            print("\(C.debugPrefix) ↳ Appending SUBSEQUENT frame \(frameNumber). PTS: \(currentPTS). File: \(fileURL?.lastPathComponent ?? "?")")
            // *******************************************************

            // Append the subsequent frame
            if inp.append(sb) {
                framesThisSegment += 1
                // print("\(C.debugPrefix) ✅ Subsequent frame \(framesThisSegment) appended.") // Optional success log
            } else {
                // Handle append failure for subsequent frames
                let status = w.status
                let nsError = w.error as? NSError
                // Log the PTS of the frame that *failed* to append
                print("\(C.debugPrefix) ❌❌❌ append() failed for SUBSEQUENT frame \(frameNumber) of \(fileURL?.lastPathComponent ?? "?"). Failing PTS: \(currentPTS). Writer status: \(status.rawValue). Error: \(nsError?.localizedDescription ?? "nil")")
                if let error = w.error { print("\(C.debugPrefix) Error details: \(error)") }
                // Call finishSegment *synchronously* since we are already on the correct queue
                // and need to clean up before the next frame potentially arrives.
                print("\(C.debugPrefix) ❌ Calling finishSegment() immediately due to subsequent append failure.")
                finishSegment()
            }
        }
}

// MARK: – SCStreamDelegate
extension ScreenRecorder {
    func stream(_ s: SCStream, didStopWithError err: Error) {
        // This indicates an unexpected stop, not a user-initiated stop.
        print("\(C.debugPrefix) ‼️‼️‼️ Stream stopped unexpectedly with error: \(err.localizedDescription)")
        print("\(C.debugPrefix) Error details: \(err)") // Print full error

        // Clean up resources associated with the stopped stream
        // Should happen on our queue for safety
        q.async { [weak self] in
             print("\(C.debugPrefix) ‼️ Cleaning up after stream error...")
            self?.finishSegment() // Ensure any active segment is finalized (likely failed)
            self?.stream = nil    // Clear the stream reference
             print("\(C.debugPrefix) ‼️ Cleanup complete.")

            // Check user's intent on the MainActor before restarting
            Task { @MainActor [weak self] in
                 print("\(C.debugPrefix) ‼️ Checking AppState.isRecording on MainActor...")
                guard let self else { return }
                if AppState.shared.isRecording {
                    print("\(C.debugPrefix) ‼️ AppState indicates recording should continue. Scheduling restart...")
                    // Use the recorder's queue 'q' for the restart logic
                    self.q.asyncAfter(deadline: .now() + 1) { [weak self] in
                        // We don't call stop() because stream is already stopped.
                        // We just need to start a *new* stream attempt.
                         print("\(C.debugPrefix) ‼️ Attempting auto-restart...")
                        self?.start() // This will call makeStream again
                    }
                } else {
                    print("\(C.debugPrefix) ‼️ AppState indicates recording stopped. No restart scheduled.")
                }
            }
        }
    }
}


// Helper extension to convert FourCharCode to String
extension String {
    init?(fourCC: FourCharCode) {
        // Create a character array including the null terminator
        let bytes: [CChar] = [
            CChar((fourCC >> 24) & 0xFF),
            CChar((fourCC >> 16) & 0xFF),
            CChar((fourCC >> 8) & 0xFF),
            CChar(fourCC & 0xFF),
            0 // Null terminator
        ]

        // Use the initializer that takes a pointer to a null-terminated string
        self.init(validatingUTF8: bytes)
    }
}
