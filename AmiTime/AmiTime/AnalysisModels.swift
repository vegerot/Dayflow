//
//  AnalysisModels.swift
//  AmiTime
//
//  Created on 5/1/2025.
//

import Foundation

/// Represents a recording chunk from the database
struct RecordingChunk: Codable {
    let id: Int64
    let startTs: Int
    let endTs: Int
    let fileUrl: String
    let status: String
    
    var duration: TimeInterval {
        TimeInterval(endTs - startTs)
    }
}

/// Represents a timeline card for display
struct TimelineCard: Codable {
    let title: String
    let description: String?
    let category: String
    let startTimestamp: Int
    let endTimestamp: Int
    let metadata: String?  // JSON string for additional data
}
