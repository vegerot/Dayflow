//
//  StorageManager.swift
//  Dayflow
//
//  Created by Jerry Liu on 4/26/25.
//  Revised 5/1/25 – remove @MainActor isolation so callers from background
//  queues/Swift concurrency contexts can access the API without "MainActor"
//  hops.  All GRDB work is already serialized internally via `DatabaseQueue`,
//  so thread‑safety is preserved.
//

import Foundation
import GRDB

// Helper DateFormatter (can be static var in an extension or class)
extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // Using current time zone. Consider UTC if needed for absolute consistency.
        formatter.timeZone = Calendar.current.timeZone
        return formatter
    }()

    // Add ISO8601 formatter if needed for parsing Gemini strings elsewhere
    // Example:
    // static let iso8601Full: ISO8601DateFormatter = {
    //     let formatter = ISO8601DateFormatter()
    //     formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    //     return formatter
    // }()
}

// MARK: - Date Helper Extension
extension Date {
    /// Calculates the "day" based on a 4 AM start time.
    /// Returns the date string (YYYY-MM-DD) and the Date objects for the start and end of that day.
    func getDayInfoFor4AMBoundary() -> (dayString: String, startOfDay: Date, endOfDay: Date) {
        let calendar = Calendar.current
        guard let fourAMToday = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: self) else {
            print("Error: Could not calculate 4 AM for date \(self). Falling back to standard day.")
            let start = calendar.startOfDay(for: self)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (DateFormatter.yyyyMMdd.string(from: start), start, end)
        }

        let startOfDay: Date
        if self < fourAMToday {
            startOfDay = calendar.date(byAdding: .day, value: -1, to: fourAMToday)!
        } else {
            startOfDay = fourAMToday
        }
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        let dayString = DateFormatter.yyyyMMdd.string(from: startOfDay)
        return (dayString, startOfDay, endOfDay)
    }
}

// MARK: - Protocol ------------------------------------------------------------

/// File + database persistence used by screen‑recorder & Gemini pipeline.
///
/// _No_ `@MainActor` isolation ⇒ can be called from any thread/actor.
/// If you add UI‑touching methods later, isolate **those** individually.
protocol StorageManaging: Sendable {
    // Recording‑chunk lifecycle
    func nextFileURL() -> URL
    func registerChunk(url: URL)
    func markChunkCompleted(url: URL)
    func markChunkFailed(url: URL)

    // Fetch unprocessed (completed + not yet batched) chunks
    func fetchUnprocessedChunks(olderThan oldestAllowed: Int) -> [RecordingChunk]

    // Analysis‑batch management
    func saveBatch(startTs: Int, endTs: Int, chunkIds: [Int64]) -> Int64?
    func updateBatchStatus(batchId: Int64, status: String)
    func markBatchFailed(batchId: Int64, reason: String)

    // Timeline‑cards
    func saveTimelineCards(batchId: Int64, cards: [TimelineCard])

    // Helper for GeminiService – map file paths → timestamps
    func getTimestampsForVideoFiles(paths: [String]) -> [String: (startTs: Int, endTs: Int)]

    // Timeline Queries
    func fetchTimelineCards(forDay day: String) -> [TimelineCard]
}

// MARK: - Data Structures -----------------------------------------------------

// Re-add Distraction struct, as it's used by TimelineCard
struct Distraction: Codable, Sendable, Identifiable {
    let id = UUID()
    let startTime: String
    let endTime: String
    let title: String
    let summary: String
    let videoSummaryURL: String? // Optional link to video summary for the distraction
}

struct TimelineCard: Codable, Sendable, Identifiable {
    let id = UUID()
    let startTimestamp: String
    let endTimestamp: String
    let category: String
    let subcategory: String
    let title: String
    let summary: String
    let detailedSummary: String
    let day: String
    let distractions: [Distraction]?
    let videoSummaryURL: String? // Optional link to video summary
}

// MARK: - Implementation ------------------------------------------------------

final class StorageManager: StorageManaging {
    static let shared = StorageManager()

    private let db: DatabaseQueue
    private let fileMgr = FileManager.default
    private let root: URL
    private let quota = 5 * 1024 * 1024 * 1024  // 5 GB
    var recordingsRoot: URL { root }

    private init() {
        root = fileMgr.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dayflow/recordings", isDirectory: true)
        try? fileMgr.createDirectory(at: root, withIntermediateDirectories: true)

        db = try! DatabaseQueue(path: root.appendingPathComponent("chunks.sqlite").path)
        migrate()
        purgeIfNeeded()
    }

    // MARK: – Schema / migrations
    private func migrate() {
        try? db.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS chunks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    start_ts INTEGER NOT NULL,
                    end_ts   INTEGER NOT NULL,
                    file_url TEXT    NOT NULL UNIQUE,
                    status   TEXT    NOT NULL DEFAULT 'recording'
                );
                CREATE INDEX IF NOT EXISTS idx_chunks_status   ON chunks(status);
                CREATE INDEX IF NOT EXISTS idx_chunks_start_ts ON chunks(start_ts);
            """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS analysis_batches (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    batch_start_ts INTEGER NOT NULL,
                    batch_end_ts   INTEGER NOT NULL,
                    status         TEXT    NOT NULL DEFAULT 'pending',
                    reason         TEXT,
                    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX IF NOT EXISTS idx_analysis_batches_status ON analysis_batches(status);
            """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS batch_chunks (
                    batch_id INTEGER NOT NULL REFERENCES analysis_batches(id) ON DELETE CASCADE,
                    chunk_id INTEGER NOT NULL REFERENCES chunks(id)          ON DELETE RESTRICT,
                    PRIMARY KEY (batch_id, chunk_id)
                );
            """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS timeline_cards (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    batch_id   INTEGER REFERENCES analysis_batches(id) ON DELETE CASCADE,
                    start   TEXT NOT NULL, -- Renamed from start_ts
                    end     TEXT NOT NULL, -- Renamed from end_ts
                    day        DATE    NOT NULL,
                    title      TEXT    NOT NULL,
                    summary TEXT,
                    category    TEXT    NOT NULL,
                    subcategory TEXT,
                    detailed_summary TEXT,
                    metadata    TEXT, -- For distractions JSON
                    video_summary_url TEXT, -- Link to video summary on filesystem
                    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                 CREATE INDEX IF NOT EXISTS idx_timeline_cards_day ON timeline_cards(day);
            """)
        }
    }

    // MARK: – Recording‑file helpers ------------------------------------------

    func nextFileURL() -> URL {
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd_HHmmssSSS"
        return root.appendingPathComponent("\(df.string(from: Date())).mp4")
    }

    func registerChunk(url: URL) {
        let ts = Int(Date().timeIntervalSince1970)
        try? db.write { db in
            try db.execute(sql: "INSERT INTO chunks(start_ts, end_ts, file_url, status) VALUES (?, ?, ?, 'recording')",
                           arguments: [ts, ts + 60, url.path])
        }
        purgeIfNeeded()
    }

    func markChunkCompleted(url: URL) {
        let end = Int(Date().timeIntervalSince1970)
        try? db.write { db in
            try db.execute(sql: "UPDATE chunks SET end_ts = ?, status = 'completed' WHERE file_url = ?",
                           arguments: [end, url.path])
        }
    }

    func markChunkFailed(url: URL) {
        try? db.write { db in
            try db.execute(sql: "DELETE FROM chunks WHERE file_url = ?", arguments: [url.path])
        }
        try? fileMgr.removeItem(at: url)
    }

    // MARK: – Queries used by GeminiAnalysisManager ---------------------------

    func fetchUnprocessedChunks(olderThan oldestAllowed: Int) -> [RecordingChunk] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM chunks
                WHERE start_ts >= ?
                  AND status = 'completed'
                  AND id NOT IN (SELECT chunk_id FROM batch_chunks)
                ORDER BY start_ts ASC
            """, arguments: [oldestAllowed])
                .map { row in
                    RecordingChunk(id: row["id"], startTs: row["start_ts"], endTs: row["end_ts"], fileUrl: row["file_url"], status: row["status"]) }
        }) ?? []
    }

    func saveBatch(startTs: Int, endTs: Int, chunkIds: [Int64]) -> Int64? {
        guard !chunkIds.isEmpty else { return nil }
        var batchID: Int64 = 0
        try? db.write { db in
            try db.execute(sql: "INSERT INTO analysis_batches(batch_start_ts, batch_end_ts) VALUES (?, ?)",
                           arguments: [startTs, endTs])
            batchID = db.lastInsertedRowID
            for id in chunkIds {
                try db.execute(sql: "INSERT INTO batch_chunks(batch_id, chunk_id) VALUES (?, ?)", arguments: [batchID, id])
            }
        }
        return batchID == 0 ? nil : batchID
    }

    func updateBatchStatus(batchId: Int64, status: String) {
        try? db.write { db in
            try db.execute(sql: "UPDATE analysis_batches SET status = ? WHERE id = ?", arguments: [status, batchId])
        }
    }

    func markBatchFailed(batchId: Int64, reason: String) {
        try? db.write { db in
            try db.execute(sql: "UPDATE analysis_batches SET status = 'failed', reason = ? WHERE id = ?", arguments: [reason, batchId])
        }
    }

    func saveTimelineCards(batchId: Int64, cards: [TimelineCard]) {
        guard !cards.isEmpty else { return }
        let encoder = JSONEncoder()
        try? db.write { db in
            for c in cards {
                var metadataString: String? = nil
                if let distractions = c.distractions, !distractions.isEmpty {
                    if let jsonData = try? encoder.encode(distractions) {
                        metadataString = String(data: jsonData, encoding: .utf8)
                    }
                }

                try db.execute(sql: """
                    INSERT INTO timeline_cards(
                        batch_id, start, end, day, title, -- Renamed start_ts, end_ts
                        summary, category, subcategory, detailed_summary, metadata, video_summary_url
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    batchId, c.startTimestamp, c.endTimestamp, c.day, c.title,
                    c.summary,
                    c.category, c.subcategory, c.detailedSummary, metadataString, c.videoSummaryURL
                ])
            }
        }
    }

    // MARK: – Helper for GeminiService ----------------------------------------

    func getTimestampsForVideoFiles(paths: [String]) -> [String: (startTs: Int, endTs: Int)] {
            guard !paths.isEmpty else { return [:] }
            var out: [String: (Int, Int)] = [:]
            let placeholders = Array(repeating: "?", count: paths.count).joined(separator: ",")
            let sql = "SELECT file_url, start_ts, end_ts FROM chunks WHERE file_url IN (\(placeholders))"
            try? db.read { db in
                let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(paths))
                for row in rows {
                    if let path: String = row["file_url"],
                       let start: Int  = row["start_ts"],
                       let end:   Int  = row["end_ts"] {
                        out[path] = (start, end)
                    }
                }
            }
            return out
        }

    // All batches, newest first
    func allBatches() -> [(id: Int64, start: Int, end: Int, status: String)] {
        (try? db.read { db in
            try Row.fetchAll(db, sql:
                "SELECT id, batch_start_ts, batch_end_ts, status FROM analysis_batches ORDER BY id DESC"
            ).map { row in
                (row["id"], row["batch_start_ts"], row["batch_end_ts"], row["status"])
            }
        }) ?? []
    }

    /// Chunks that belong to one batch, already sorted.
    func chunksForBatch(_ batchId: Int64) -> [RecordingChunk] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.* FROM batch_chunks bc
                JOIN chunks c ON c.id = bc.chunk_id
                WHERE bc.batch_id = ?
                ORDER BY c.start_ts ASC
                """, arguments: [batchId]
            ).map { r in
                RecordingChunk(id: r["id"], startTs: r["start_ts"], endTs: r["end_ts"],
                               fileUrl: r["file_url"], status: r["status"])
            }
        }) ?? []
    }

    // MARK: - Timeline Queries -----------------------------------------------

    func fetchTimelineCards(forDay day: String) -> [TimelineCard] {
        let decoder = JSONDecoder()
        let cards: [TimelineCard]? = try? db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM timeline_cards
                WHERE day = ?
                ORDER BY start ASC -- Order by renamed column 'start'
            """, arguments: [day])
            .map { row in
                // Decode distractions from metadata JSON
                var distractions: [Distraction]? = nil
                if let metadataString: String = row["metadata"],
                   let jsonData = metadataString.data(using: .utf8) {
                    distractions = try? decoder.decode([Distraction].self, from: jsonData)
                }

                // Create TimelineCard instance using renamed columns
                return TimelineCard(
                    startTimestamp: row["start"] ?? "", // Use row["start"]
                    endTimestamp: row["end"] ?? "",   // Use row["end"]
                    category: row["category"],
                    subcategory: row["subcategory"],
                    title: row["title"],
                    summary: row["summary"],
                    detailedSummary: row["detailed_summary"],
                    day: row["day"],
                    distractions: distractions,
                    videoSummaryURL: row["video_summary_url"]
                )
            }
        }
        return cards ?? []
    }

    // MARK: – Purging Logic --------------------------------------------------

    private let purgeQ = DispatchQueue(label: "com.dayflow.storage.purge", qos: .background)

    private func purgeIfNeeded() {
        purgeQ.async {
            guard let size = try? self.fileMgr.allocatedSizeOfDirectory(at: self.root), size > self.quota else { return }
            try? self.db.write { db in
                let old = try Row.fetchAll(db, sql: "SELECT id, file_url FROM chunks WHERE status = 'completed' ORDER BY start_ts ASC LIMIT 20")
                for r in old {
                    guard let id: Int64 = r["id"], let path: String = r["file_url"] else { continue }
                    try? self.fileMgr.removeItem(atPath: path)
                    try db.execute(sql: "DELETE FROM chunks WHERE id = ?", arguments: [id])
                }
            }
        }
    }
}

// MARK: - File‑size helper -----------------------------------------------------

private extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> Int {
        try contentsOfDirectory(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
            .reduce(0) { sum, file in
                sum + (try file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0)
            }
    }
}
