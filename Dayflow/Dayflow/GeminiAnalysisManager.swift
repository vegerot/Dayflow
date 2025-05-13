//
//  GeminiAnalysisManager.swift
//  Dayflow
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
    private let queue = DispatchQueue(label: "com.dayflow.geminianalysis.queue", qos: .utility)

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

        // Define an ISO8601DateFormatter for parsing timestamps from Gemini -- REMOVED as format is 'hh:mm AM/PM'
        // let isoFormatter = ISO8601DateFormatter()
        // isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]

        geminiService.processBatch(batchId) { [weak self] result in
            guard let self else { return }

            // Determine the current logical day based on 4AM boundary BEFORE processing results
            let now = Date()
            let currentDayInfo = now.getDayInfoFor4AMBoundary()
            let currentLogicalDayString = currentDayInfo.dayString
            print("Processing batch \\(batchId) for logical day: \\(currentLogicalDayString)")

            switch result {
            case .success(let activityCards):
                print("Gemini succeeded for Batch \\(batchId). Processing \\(activityCards.count) activity cards for day \\(currentLogicalDayString).")

                // --- Step 1: Delete existing cards for the current logical day --- 
                print("Clearing existing timeline cards for day: \\(currentLogicalDayString) before saving new cards for batch \\(batchId)")
                self.store.deleteTimelineCards(forDay: currentLogicalDayString)

                // --- Step 2: Convert ActivityCards to TimelineCards, assigning the CURRENT logical day --- 
                var timelineCardsToSave: [TimelineCard] = []
                // var uniqueDaysToClear: Set<String> = [] // No longer needed

                for activityCard in activityCards {
                    // Removed date parsing as format is not ISO8601
                    // guard let startDate = isoFormatter.date(from: activityCard.startTime) else {
                    //     print("Error: Could not parse startTime string \\(activityCard.startTime) ...")
                    //     continue
                    // }
                    // let dayInfo = startDate.getDayInfoFor4AMBoundary() // No longer calculating per card
                    // uniqueDaysToClear.insert(dayInfo.dayString) // No longer needed

                    // The explicit mapping is no longer needed as both ActivityCard and TimelineCard
                    // will use the same Distraction type from StorageManager.swift.
                    // let timelineCardDistractions = activityCard.distractions?.map { gsDistraction in
                    //     Distraction( // This refers to StorageManager.Distraction
                    //         startTime: gsDistraction.startTime,
                    //         endTime: gsDistraction.endTime,
                    //         title: gsDistraction.title,
                    //         summary: gsDistraction.summary
                    //     )
                    // }
                    // Direct assignment should work now:
                    let timelineCardDistractions = activityCard.distractions

                    let timelineCard = TimelineCard(
                        startTimestamp: activityCard.startTime,
                        endTimestamp: activityCard.endTime,
                        category: activityCard.category,
                        subcategory: activityCard.subcategory,
                        title: activityCard.title,
                        summary: activityCard.summary,
                        detailedSummary: activityCard.detailedSummary,
                        day: currentLogicalDayString,
                        distractions: timelineCardDistractions // Use directly assigned distractions
                    )
                    timelineCardsToSave.append(timelineCard)
                }

                // Delete logic moved before the loop
                // if !uniqueDaysToClear.isEmpty { ... }

                // --- Step 3: Save the new timeline cards --- 
                if !timelineCardsToSave.isEmpty {
                    print("Saving \\(timelineCardsToSave.count) new timeline cards for batch \\(batchId) (Day: \\(currentLogicalDayString))")
                    self.store.saveTimelineCards(batchId: batchId, cards: timelineCardsToSave)
                    self.updateBatchStatus(batchId: batchId, status: "completed")
                } else {
                    // No cards were converted/saved, but deletion happened.
                    print("No new timeline cards to save for batch \\(batchId) after clearing day \\(currentLogicalDayString). Marking as completed.")
                    self.updateBatchStatus(batchId: batchId, status: "completed")
                }
                
            case .failure(let err):
                // Deletion for currentLogicalDayString might have already happened before failure was known
                // Consider if this is the desired behavior or if deletion should only occur on success.
                // Current logic: Deletion happens BEFORE the switch, so it always occurs if the block is entered.
                print("Gemini failed for Batch \\(batchId). Day \\(currentLogicalDayString) may have been cleared. Error: \\(err.localizedDescription)")
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
