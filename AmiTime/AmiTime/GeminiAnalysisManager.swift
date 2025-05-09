//
//  GeminiAnalysisManager.swift
//  AmiTime
//
//  Re‑written 2025‑05‑07 to use the new `GeminiServicing.processBatch` API.
//  • Drops the per‑chunk URL plumbing – the service handles stitching/encoding.
//  • Still handles batching logic + DB status updates.
//  • Keeps the public `AnalysisManaging` contract unchanged.
//
import Foundation
import AVFoundation
import GRDB

// MARK: – Public protocol ---------------------------------------------------

protocol AnalysisManaging {
    func startAnalysisJob()
    func stopAnalysisJob()
    func triggerAnalysisNow()
}

// MARK: – Manager -----------------------------------------------------------

final class GeminiAnalysisManager: AnalysisManaging {
    static let shared = GeminiAnalysisManager()
    private init() {
        store = StorageManager.shared
        geminiService = GeminiService.shared
        print("GeminiAnalysisManager: Initialized")
    }

    // MARK: – Private state
    private let store: any StorageManaging
    private let geminiService: any GeminiServicing

    private let checkInterval: TimeInterval = 60          // every minute
    private let targetBatchDuration: TimeInterval = 15*60 // ≈15‑min logical batches
    private let maxLookback: TimeInterval   = 24*60*60    // only last 24h

    private var analysisTimer: Timer?
    private var isProcessing = false
    private let queue = DispatchQueue(label: "com.amitime.geminianalysis.queue", qos: .utility)

    // MARK: – Public API -----------------------------------------------------

    func startAnalysisJob() {
        stopAnalysisJob()               // ensure single timer
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.analysisTimer = Timer.scheduledTimer(timeInterval: self.checkInterval,
                                                       target: self,
                                                       selector: #selector(self.timerFired),
                                                       userInfo: nil,
                                                       repeats: true)
            self.triggerAnalysisNow()   // immediate run
        }
    }

    func stopAnalysisJob() {
        analysisTimer?.invalidate(); analysisTimer = nil
    }

    func triggerAnalysisNow() {
        guard !isProcessing else { return }
        queue.async { [weak self] in self?.processRecordings() }
    }

    // MARK: – Timer
    @objc private func timerFired() { triggerAnalysisNow() }

    // MARK: – Core work ------------------------------------------------------

    private func processRecordings() {
        guard !isProcessing else { return }; isProcessing = true
        defer { isProcessing = false }

        // 1. Gather unprocessed chunks
        let chunks = fetchUnprocessedChunks()
        // 2. Build logical batches (~15‑min)
        let batches = createBatches(from: chunks)
        // 3. Persist batch rows & join table
        let batchIDs = batches.compactMap(saveBatch)
        // 4. Fire Gemini for each batch
        for id in batchIDs { queueGeminiRequest(batchId: id) }
    }

    // MARK: – Gemini kick‑off ----------------------------------------------

    private func queueGeminiRequest(batchId: Int64) {
        updateBatchStatus(batchId: batchId, status: "processing")

        geminiService.processBatch(batchId) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let resp):
                let cards = resp.toTimelineCards()
                self.store.saveTimelineCards(batchId: batchId, cards: cards)
                self.updateBatchStatus(batchId: batchId, status: "done")
                print("Batch \(batchId) processed – \(cards.count) cards")
            case .failure(let err):
                self.markBatchFailed(batchId: batchId, reason: err.localizedDescription)
            }
        }
    }

    // MARK: – DB helpers -----------------------------------------------------

    private func markBatchFailed(batchId: Int64, reason: String) {
        store.markBatchFailed(batchId: batchId, reason: reason)
    }

    private func updateBatchStatus(batchId: Int64, status: String) {
        store.updateBatchStatus(batchId: batchId, status: status)
    }

    // MARK: – Batching logic -------------------------------------------------

    private struct AnalysisBatch { let chunks: [RecordingChunk]; let start: Int; let end: Int }

    private func fetchUnprocessedChunks() -> [RecordingChunk] {
        let oldest = Int(Date().timeIntervalSince1970) - Int(maxLookback)
        return store.fetchUnprocessedChunks(olderThan: oldest)
    }

    private func createBatches(from chunks: [RecordingChunk]) -> [AnalysisBatch] {
        let ordered = chunks.sorted { $0.startTs < $1.startTs }
        var out: [AnalysisBatch] = []
        var bucket: [RecordingChunk] = []; var dur: TimeInterval = 0

        for ch in ordered {
            bucket.append(ch); dur += ch.duration
            if dur >= targetBatchDuration {
                out.append(AnalysisBatch(chunks: bucket,
                                         start: bucket.first!.startTs,
                                         end:   bucket.last!.endTs))
                bucket.removeAll(); dur = 0
            }
        }
        return out
    }

    private func saveBatch(_ batch: AnalysisBatch) -> Int64? {
        let ids = batch.chunks.map { $0.id }
        return store.saveBatch(startTs: batch.start, endTs: batch.end, chunkIds: ids)
    }
}
