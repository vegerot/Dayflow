//
//  ScreenRecorder.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/26/25.
//

import ScreenCaptureKit
import AVFoundation
import Combine

final class ScreenRecorder: NSObject {
    // MARK: – Queues & state
    private let queue = DispatchQueue(label: "recorder")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input:  AVAssetWriterInput?
    private var chunkTimer: DispatchSourceTimer?
    private var cancellable: AnyCancellable?
    private var wantRecording = true            // mirror of AppState
    private var firstPTS: CMTime?               // fixes 12-hour bug
    private var hasSession = false
    
    // MARK: – Constants
    private let px = 1280, py = 720
    private let fps: Double = 1
    private let chunkSec: TimeInterval = 60     // 1-min chunks
    
    private let store = StorageManager.shared
    
    // MARK: – Init
    override init() {
        super.init()
        
        // Subscribe on MainActor, then hop to recorder queue
        Task { @MainActor in
            self.cancellable = AppState.shared.$isRecording
                .receive(on: queue)
                .sink { [weak self] rec in
                    guard let self = self else { return }
                    self.wantRecording = rec
                    rec ? self.start() : self.stop()
                }
        }
    }
    
    // MARK: – Capture lifecycle
    private func start() {
        Task { [self] in
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else { return }
            
            let cfg = SCStreamConfiguration()
            cfg.width  = px
            cfg.height = py
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            cfg.queueDepth = 4
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            stream = SCStream(filter: filter,
                              configuration: cfg,
                              delegate: nil)
            try stream?.addStreamOutput(self,
                                        type: .screen,
                                        sampleHandlerQueue: queue)
            try await stream?.startCapture()
            openWriter()
            armTimer()
        }
    }
    
    private func stop() {
        chunkTimer?.cancel()
        chunkTimer = nil
        stream?.stopCapture()
        stream = nil
        closeWriter()
    }
    
    // MARK: – Timer & rotation
    private func armTimer() {
        chunkTimer?.cancel()
        chunkTimer = DispatchSource.makeTimerSource(queue: queue)
        chunkTimer?.schedule(deadline: .now() + chunkSec, repeating: chunkSec)
        chunkTimer?.setEventHandler { [weak self] in self?.rotateChunk() }
        chunkTimer?.resume()
    }
    
    private func rotateChunk() {
        closeWriter()
        firstPTS = nil
        hasSession = false
        openWriter()
    }
    
    // MARK: – Writer helpers
    private func openWriter() {
        let url = store.nextFileURL()
        writer = try? AVAssetWriter(outputURL: url, fileType: .mp4)
        
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: px,
            AVVideoHeightKey: py
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input?.expectsMediaDataInRealTime = true
        if let input = input, writer?.canAdd(input) == true {
            writer?.add(input)
        }
        writer?.startWriting()                // session starts on first frame
        store.registerChunk(url: url)         // chunk row in DB
    }
    
    private func closeWriter() {
        input?.markAsFinished()
        writer?.finishWriting { }             // wait until MOOV atom is written
    }
}

// MARK: – SCStreamOutput
extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sb: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard wantRecording,
              writer?.status == .writing,
              input?.isReadyForMoreMediaData == true else { return }
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        if hasSession == false {
            writer?.startSession(atSourceTime: pts)   // align time-base
            firstPTS = pts
            hasSession = true
        }
        input?.append(sb)
    }
}
