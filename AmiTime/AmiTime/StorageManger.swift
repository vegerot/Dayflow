//
//  StorageManger.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/26/25.
//

import Foundation
import GRDB

final class StorageManager {
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

        db = try! DatabaseQueue(path: root.appendingPathComponent("chunks.sqlite").path)
        try! db.write { db in
            try db.create(table: "chunks", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("start_ts", .integer).notNull()
                t.column("end_ts",   .integer).notNull()
                t.column("file_url", .text).notNull()
                t.column("uploaded", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "analysis_batches", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("batch_start_ts", .integer).notNull()
                t.column("batch_end_ts", .integer).notNull()
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "batch_chunks", ifNotExists: true) { t in
                t.column("batch_id", .integer).notNull().indexed().references("analysis_batches", onDelete: .cascade)
                t.column("chunk_id", .integer).notNull().indexed().references("chunks", onDelete: .cascade)
                t.primaryKey(["batch_id", "chunk_id"])
            }

            try db.create(table: "llm_requests", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("batch_id", .integer).notNull().indexed().references("analysis_batches", onDelete: .cascade)
                t.column("request_payload", .text).notNull()
                t.column("response_payload", .text)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("attempt", .integer).notNull().defaults(to: 1)
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "timeline_cards", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("batch_id", .integer).indexed().references("analysis_batches", onDelete: .cascade)
                t.column("start_ts", .integer).notNull()
                t.column("end_ts", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("category", .text).notNull()
                t.column("metadata", .text)
                t.column("created_at", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }
        purgeIfNeeded()
    }

    
    func nextFileURL() -> URL {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"          // includes seconds
        let name = fmt.string(from: Date())
        return root.appendingPathComponent("\(name).mp4")
    }
    
    func registerChunk(url: URL) {
        let now = Int(Date().timeIntervalSince1970)
        try? db.write { db in
            try? db.execute(sql: "INSERT INTO chunks(start_ts,end_ts,file_url) VALUES (?,?,?)",
                                   arguments: [now, now + 60, url.path])
        }
        purgeIfNeeded()
    }
    
    private func purgeIfNeeded() {
        let usage = (try? fileMgr.allocatedSizeOfDirectory(at: root)) ?? 0
        guard usage > quota else { return }
        try? db.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id,file_url FROM chunks ORDER BY start_ts LIMIT 10")
            for row in rows {
                let path: String = row["file_url"]
                try? fileMgr.removeItem(atPath: path)
                try db.execute(sql: "DELETE FROM chunks WHERE id = ?", arguments: [row["id"]])
            }
        }
    }
}

// helper
private extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> Int {
        var size = 0
        for file in try contentsOfDirectory(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
            size += try (file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0)
        }
        return size
    }
}
