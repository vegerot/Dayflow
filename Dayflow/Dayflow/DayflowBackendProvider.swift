//
//  DayflowBackendProvider.swift
//  Dayflow
//

import Foundation

final class DayflowBackendProvider: LLMProvider {
    private let token: String
    private let endpoint: String
    
    init(token: String, endpoint: String = "https://api.dayflow.app") {
        self.token = token
        self.endpoint = endpoint
    }
    
    func transcribeVideo(videoData: Data, mimeType: String, prompt: String) async throws -> (transcripts: [TranscriptChunk], log: LLMCall) {
        fatalError("DayflowBackendProvider not implemented yet")
    }
    
    func generateActivityCards(transcripts: [TranscriptChunk], context: ActivityGenerationContext) async throws -> (cards: [ActivityCard], log: LLMCall) {
        fatalError("DayflowBackendProvider not implemented yet")
    }
}