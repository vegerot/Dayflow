//
//  GeminiAnalysisManager.swift
//  AmiTime
//
//  Created on 5/1/2025.
//

import Foundation
import AVFoundation
import GRDB

/// Protocol defining the interface for analysis management
protocol AnalysisManaging {
    /// Starts the background job for batching and analyzing recordings
    func startAnalysisJob()
    
    /// Stops the background job
    func stopAnalysisJob()
    
    /// Forces an immediate analysis run
    func triggerAnalysisNow()
}

/// Manager responsible for batching recorded chunks and sending them to Gemini for analysis
final class GeminiAnalysisManager: AnalysisManaging {
    // MARK: - Singleton
    static let shared = GeminiAnalysisManager()
    
    // MARK: - Properties
    private let store: any StorageManaging
    private let geminiService: any GeminiServicing
    private let checkInterval: TimeInterval = 60 // Check every 15 minutes
    private let targetBatchDuration: TimeInterval = 15 * 60 // ~15 minute batches
    private let maxLookback: TimeInterval = 24 * 60 * 60 // Last 24 hours
    private var analysisTimer: Timer?
    private var isProcessing = false
    
    // Queue for background processing
    private let queue = DispatchQueue(label: "com.amitime.geminianalysis.queue", qos: .utility)
    
    // MARK: - Initialization
    private init() {
        self.store = StorageManager.shared
        self.geminiService = GeminiService.shared
        print("GeminiAnalysisManager: Initialized")
    }
    
    // MARK: - Public API
    func startAnalysisJob() {
        stopAnalysisJob() // Ensure we don't start multiple timers
        
        // Create and schedule the timer on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("GeminiAnalysisManager: Starting analysis job with interval \(self.checkInterval) seconds")
            self.analysisTimer = Timer.scheduledTimer(
                timeInterval: self.checkInterval,
                target: self,
                selector: #selector(self.timerFired),
                userInfo: nil,
                repeats: true
            )
            
            // Run an immediate analysis to process any pending recordings
            self.triggerAnalysisNow()
        }
    }
    
    func stopAnalysisJob() {
        analysisTimer?.invalidate()
        analysisTimer = nil
        print("GeminiAnalysisManager: Analysis job stopped")
    }
    
    func triggerAnalysisNow() {
        guard !isProcessing else {
            print("GeminiAnalysisManager: Analysis already in progress, skipping trigger")
            return
        }
        
        queue.async { [weak self] in
            self?.processRecordings()
        }
    }
    
    // MARK: - Timer Handler
    @objc private func timerFired() {
        triggerAnalysisNow()
    }
    
    // MARK: - Internal Processing
    private func processRecordings() {
        guard !isProcessing else { return }
        isProcessing = true
        print("GeminiAnalysisManager: Starting recording analysis")
        
        // Step 1: Find unprocessed recording chunks from the last 24 hours
        let unprocessedChunks = fetchUnprocessedChunks()
        // Step 2: Group chunks into ~30 minute batches
        let batches = createBatches(from: unprocessedChunks)
        
        // Step 3: Save batches to database and mark chunks as being processed
        var savedBatchIds = [(Int64, AnalysisBatch)]()
        for batch in batches {
            if let batchId = saveBatch(batch) {
                savedBatchIds.append((batchId, batch))
            }
        }
        
        // Step 4: Queue API requests for processing
        for (batchId, batch) in savedBatchIds {
            queueGeminiRequest(batchId: batchId, batch: batch)
        }
        
        print("GeminiAnalysisManager: Created \(batches.count) batches for Gemini processing")
        
        isProcessing = false
    }
    
    /// Queues a Gemini API request for the given batch
    private func queueGeminiRequest(batchId: Int64, batch: AnalysisBatch) {
        // Create array of URLs for the video files
        let urls = batch.chunks.compactMap { URL(fileURLWithPath: $0.fileUrl) }
        guard !urls.isEmpty else {
            print("GeminiAnalysisManager Error: No valid URLs for batch \(batchId)")
            markBatchFailed(batchId: batchId, reason: "No valid URLs")
            return
        }
        
        // Update batch status to processing
        updateBatchStatus(batchId: batchId, status: "processing")
        
        // Process videos with Gemini service
        geminiService.processVideos(batchId: batchId, urls: urls) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let response):
                self.processBatchResults(batchId: batchId, response: response)
                
            case .failure(let error):
                print("GeminiAnalysisManager Error: Gemini API request failed - \(error.localizedDescription)")
                self.markBatchFailed(batchId: batchId, reason: error.localizedDescription)
            }
        }
    }
    
    /// Process the results from a successful Gemini API call
    private func processBatchResults(batchId: Int64, response: GeminiAnalysisResponse) {
        // Convert the response cards to our domain model timeline cards
        let timelineCards = response.toTimelineCards()
        
        // Use the StorageManager to save timeline cards
        store.saveTimelineCards(batchId: batchId, cards: timelineCards)
        print("GeminiAnalysisManager: Successfully processed batch \(batchId) with \(timelineCards.count) timeline cards")
    }
    
    /// Mark a batch as failed in the database
    private func markBatchFailed(batchId: Int64, reason: String) {
        // Use the StorageManager to mark the batch as failed
        store.markBatchFailed(batchId: batchId, reason: reason)
        print("GeminiAnalysisManager: Marked batch \(batchId) as failed. Reason: \(reason)")
    }
    
    /// Update a batch's status in the database
    private func updateBatchStatus(batchId: Int64, status: String) {
        // Use the StorageManager to update the batch status
        store.updateBatchStatus(batchId: batchId, status: status)
        print("GeminiAnalysisManager: Updated batch \(batchId) status to \(status)")
    }
    
    // MARK: - Helper Methods
    
    /// Represents a batch of recording chunks to be processed together
    private struct AnalysisBatch {
        let chunks: [RecordingChunk]
        let startTs: Int
        let endTs: Int
        
        var duration: TimeInterval {
            TimeInterval(endTs - startTs)
        }
    }
    
    /// Fetches unprocessed recording chunks from the last 24 hours
    private func fetchUnprocessedChunks() -> [RecordingChunk] {
        let currentTime = Int(Date().timeIntervalSince1970)
        let oldestTime = currentTime - Int(maxLookback)
        
        return store.fetchUnprocessedChunks(olderThan: oldestTime)
    }
    
    private func createBatches(from chunks: [RecordingChunk]) -> [AnalysisBatch] {
        let ordered = chunks.sorted { $0.startTs < $1.startTs }
        var batches: [AnalysisBatch] = []

        var current: [RecordingChunk] = []
        var currentDur: TimeInterval = 0

        for ch in ordered {
            current.append(ch)
            currentDur += ch.duration

            if currentDur >= targetBatchDuration {
                batches.append(
                    AnalysisBatch(chunks: current,
                                  startTs: current.first!.startTs,
                                  endTs:   current.last!.endTs)
                )
                current = []
                currentDur = 0
            }
        }

        return batches
    }



    
    /// Saves a batch to the database and marks its chunks as being processed
    /// Returns the batch ID if successful, or nil if it fails
    private func saveBatch(_ batch: AnalysisBatch) -> Int64? {
        guard !batch.chunks.isEmpty else { return nil }
        
        // Extract the chunk IDs
        let chunkIds = batch.chunks.map { $0.id }
        
        // Use the StorageManager to save the batch
        let batchId = store.saveBatch(startTs: batch.startTs, endTs: batch.endTs, chunkIds: chunkIds)
        
        if batchId != nil {
            print("GeminiAnalysisManager: Saved batch with ID \(batchId!), containing \(batch.chunks.count) chunks")
        } else {
            print("GeminiAnalysisManager Error: Failed to save batch")
        }
        
        return batchId
    }
}

