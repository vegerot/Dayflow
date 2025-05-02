//
//  StorageManger.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/26/25.
//

import Foundation
import GRDB

final class StorageManager: StorageManaging { // Conform to the protocol used in ScreenRecorder
    static let shared = StorageManager()
    private let db: DatabaseQueue
    private let fileMgr = FileManager.default
    private let root: URL
    private let quota = 5 * 1024 * 1024 * 1024  // 5 GB
    var recordingsRoot: URL { root }

    private init() {
        root = fileMgr.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AmiTime/recordings", isDirectory: true)
        try? fileMgr.createDirectory(at: root, withIntermediateDirectories: true)

        let dbPath = root.appendingPathComponent("chunks.sqlite").path
        print("StorageManager: Database path: \(dbPath)") // Good for debugging
        db = try! DatabaseQueue(path: dbPath)
        try! db.write { db in
            // Keep table creation simple, add columns later if needed via migrations
             try db.execute(sql: """
                 CREATE TABLE IF NOT EXISTS chunks (
                     id INTEGER PRIMARY KEY AUTOINCREMENT,
                     start_ts INTEGER NOT NULL,
                     end_ts INTEGER NOT NULL,
                     file_url TEXT NOT NULL UNIQUE, -- Added UNIQUE constraint
                     uploaded INTEGER NOT NULL DEFAULT 0,
                     status TEXT NOT NULL DEFAULT 'recording' -- Added status column
                 );
             """)
             try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_chunks_start_ts ON chunks(start_ts);")
             try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_chunks_status ON chunks(status);")


            // --- Other tables (assuming they are correct as is) ---
            try db.create(table: "analysis_batches", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("batch_start_ts", .integer).notNull()
                t.column("batch_end_ts", .integer).notNull()
                t.column("status", .text).notNull().defaults(to: "pending") // e.g., pending, processing, completed, failed
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_analysis_batches_status ON analysis_batches(status);")

            try db.create(table: "batch_chunks", ifNotExists: true) { t in
                t.column("batch_id", .integer).notNull().indexed().references("analysis_batches", onDelete: .cascade)
                t.column("chunk_id", .integer).notNull().indexed().references("chunks", onDelete: .restrict) // Use RESTRICT to prevent deleting chunks part of a batch
                t.primaryKey(["batch_id", "chunk_id"])
            }

            try db.create(table: "llm_requests", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("batch_id", .integer).notNull().indexed().references("analysis_batches", onDelete: .cascade)
                t.column("request_payload", .text).notNull()
                t.column("response_payload", .text)
                t.column("status", .text).notNull().defaults(to: "pending") // e.g., pending, success, failed_retry, failed_final
                t.column("attempt", .integer).notNull().defaults(to: 1)
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_llm_requests_status ON llm_requests(status);")


            try db.create(table: "timeline_cards", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("batch_id", .integer).indexed().references("analysis_batches", onDelete: .cascade)
                t.column("start_ts", .integer).notNull()
                t.column("end_ts", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("category", .text).notNull()
                t.column("metadata", .text) // JSON perhaps
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
            // --- End of other tables ---
        }
        purgeIfNeeded() // Check quota on startup
    }


    func nextFileURL() -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmssSSS" // Added milliseconds for higher uniqueness guarantee
        let name = fmt.string(from: Date())
        let url = root.appendingPathComponent("\(name).mp4")
        print("StorageManager: Providing next file URL: \(url.path)")
        return url
    }

    func registerChunk(url: URL) {
        let now = Int(Date().timeIntervalSince1970)
        // Initial end_ts is just an estimate, will be updated on completion
        let estimatedEndTs = now + 60
        let urlPath = url.path // Use the file path string

        print("StorageManager: Registering chunk: \(urlPath) with start: \(now)")
        do {
            try db.write { db in
                // Insert with initial 'recording' status
                try db.execute(sql: """
                    INSERT INTO chunks(start_ts, end_ts, file_url, status)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [now, estimatedEndTs, urlPath, "recording"])
            }
            print("StorageManager: Successfully registered chunk: \(url.lastPathComponent)")
        } catch {
            print("StorageManager Error: Failed to register chunk \(url.lastPathComponent) - \(error.localizedDescription)")
        }
        // Check quota after registration
        purgeIfNeeded()
    }

    // --- NEW METHOD ---
    /// Called when the AVAssetWriter successfully finishes writing a chunk.
    /// Updates the end timestamp and status in the database.
    func markChunkCompleted(url: URL) {
        let actualEndTs = Int(Date().timeIntervalSince1970)
        let urlPath = url.path

        print("StorageManager: Marking chunk COMPLETED: \(url.lastPathComponent) at \(actualEndTs)")
        do {
            try db.write { db in
                // Update end_ts to actual time and status to 'completed'
                try db.execute(sql: """
                    UPDATE chunks
                    SET end_ts = ?, status = ?
                    WHERE file_url = ?
                    """, arguments: [actualEndTs, "completed", urlPath])
            }
             print("StorageManager: Successfully marked chunk complete: \(url.lastPathComponent)")
        } catch {
            print("StorageManager Error: Failed to mark chunk complete \(url.lastPathComponent) - \(error.localizedDescription)")
        }
         // Optionally trigger analysis logic here or elsewhere based on 'completed' status
    }

    // --- NEW METHOD ---
    /// Called when the AVAssetWriter fails to write a chunk.
    /// Removes the database record and attempts to delete the partial file.
    func markChunkFailed(url: URL) {
        let urlPath = url.path
        print("StorageManager: Marking chunk FAILED: \(url.lastPathComponent)")

        do {
            // First, remove the database record
            try db.write { db in
                try db.execute(sql: "DELETE FROM chunks WHERE file_url = ?", arguments: [urlPath])
            }
             print("StorageManager: Removed failed chunk record from DB: \(url.lastPathComponent)")

            // Second, attempt to delete the potentially corrupted file
            do {
                if fileMgr.fileExists(atPath: urlPath) {
                    try fileMgr.removeItem(at: url)
                    print("StorageManager: Deleted failed chunk file: \(url.lastPathComponent)")
                } else {
                     print("StorageManager: Failed chunk file not found for deletion: \(url.lastPathComponent)")
                }
            } catch {
                // Log file deletion error, but don't necessarily re-throw, DB record is gone.
                print("StorageManager Warning: Failed to delete failed chunk file \(url.lastPathComponent) - \(error.localizedDescription)")
            }

        } catch {
             print("StorageManager Error: Failed to remove failed chunk record from DB \(url.lastPathComponent) - \(error.localizedDescription)")
        }
    }

    private func purgeIfNeeded() {
        queue.async { [weak self] in // Perform potentially slow I/O off the main thread
            guard let self = self else { return }
            do {
                let usage = try self.fileMgr.allocatedSizeOfDirectory(at: self.root)
                print("StorageManager: Current directory usage: \(usage / (1024*1024)) MB, Quota: \(self.quota / (1024*1024)) MB")

                guard usage > self.quota else { return }
                print("StorageManager: Usage exceeds quota. Purging oldest chunks...")

                // Fetch oldest deletable chunks (status completed or recording - failed are already deleted)
                // Prioritize deleting 'completed' chunks that haven't been uploaded? Adapt based on logic.
                // Simple approach: Delete oldest chunks regardless of status (except maybe 'failed' if status exists).
                // Let's delete oldest 'completed' or 'recording' chunks first.
                 let chunksToDelete = try self.db.read { db in
                     try Row.fetchAll(db, sql: """
                         SELECT id, file_url FROM chunks
                         WHERE status = 'completed' OR status = 'recording'
                         ORDER BY start_ts ASC
                         LIMIT 10
                         """) // Fetch oldest 10 non-failed chunks
                 }


                if chunksToDelete.isEmpty {
                    print("StorageManager: Purge needed, but no deletable chunks found.")
                    return
                }

                print("StorageManager: Attempting to purge \(chunksToDelete.count) chunks.")
                var deletedCount = 0
                try self.db.write { db in // Use write for deletions
                    for row in chunksToDelete {
                        guard let id: Int64 = row["id"], let path: String = row["file_url"] else { continue }

                        // Check if chunk is part of an analysis batch first if needed (using ON DELETE RESTRICT helps)
                         let isBatched = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM batch_chunks WHERE chunk_id = ?", arguments: [id]) ?? 0 > 0
                         if isBatched {
                             print("StorageManager: Skipping purge of chunk ID \(id), part of an analysis batch.")
                             continue // Skip deletion if it's part of a batch
                         }


                        // Delete file first
                        do {
                            if self.fileMgr.fileExists(atPath: path) {
                                try self.fileMgr.removeItem(atPath: path)
                                print("StorageManager: Purged file: \(path)")
                            }
                            // Now delete DB record
                            try db.execute(sql: "DELETE FROM chunks WHERE id = ?", arguments: [id])
                             print("StorageManager: Purged DB record for chunk ID \(id)")
                            deletedCount += 1
                        } catch {
                            print("StorageManager Warning: Failed during purge of chunk ID \(id) (\(path)): \(error.localizedDescription)")
                            // Decide whether to continue or stop purging on error
                        }
                    }
                }
                print("StorageManager: Purged \(deletedCount) chunks.")

                // Optional: Re-check usage after purge
                let newUsage = try self.fileMgr.allocatedSizeOfDirectory(at: self.root)
                print("StorageManager: New directory usage after purge: \(newUsage / (1024*1024)) MB")

            } catch {
                print("StorageManager Error: Failed during purge check - \(error.localizedDescription)")
            }
        }
    }

    // Define the queue for purgeIfNeeded
    private let queue = DispatchQueue(label: "com.amitine.storagemanager.purgequeue", qos: .background)
}


// Helper extension remains the same
private extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> Int {
        var size: Int = 0
        let contents = try contentsOfDirectory(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey])

        for url in contents {
            let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey])
            if values.isDirectory == true {
                // Recursively calculate size of subdirectories if needed, or ignore them
                // For simplicity here, let's assume recordings are flat in the root or we only care about root files
                 // To recurse: size += try allocatedSizeOfDirectory(at: url)
            } else {
                size += values.totalFileAllocatedSize ?? 0
            }
        }
        return size
    }
}

// Define the protocol if not defined elsewhere
protocol StorageManaging {
    func nextFileURL() -> URL
    func registerChunk(url: URL)
    func markChunkCompleted(url: URL)
    func markChunkFailed(url: URL)
}
