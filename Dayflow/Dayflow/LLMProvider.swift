//
//  LLMProvider.swift
//  Dayflow
//

import Foundation

protocol LLMProvider {
    func transcribeVideo(videoData: Data, mimeType: String, prompt: String) async throws -> (transcripts: [TranscriptChunk], log: LLMCall)
    func generateActivityCards(transcripts: [TranscriptChunk], context: ActivityGenerationContext) async throws -> (cards: [ActivityCard], log: LLMCall)
}

struct ActivityGenerationContext {
    let previousSegmentsJSON: String
    let userTaxonomy: String
    let extractedTaxonomy: String
}

enum LLMProviderType: Codable {
    case geminiDirect(apiKey: String)
    case dayflowBackend(token: String, endpoint: String = "https://api.dayflow.app")
    case ollamaLocal(endpoint: String = "http://localhost:11434")
}

// MARK: - Data Models

struct TranscriptChunk: Codable, Sendable {
    let startTimestamp: String   // MM:SS
    let endTimestamp: String     // MM:SS
    let description: String
}

struct ActivityCard: Codable {
    let startTime: String
    let endTime: String
    let category: String
    let subcategory: String
    let title: String
    let summary: String
    let detailedSummary: String
    let distractions: [Distraction]?
}

struct Distraction: Codable, Sendable, Identifiable {
    let id = UUID()
    let startTime: String
    let endTime: String
    let title: String
    let summary: String
    let videoSummaryURL: String? = nil
}

// LLMCall is defined in StorageManager.swift