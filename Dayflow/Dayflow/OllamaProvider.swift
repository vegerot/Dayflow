//
//  OllamaProvider.swift
//  Dayflow
//

import Foundation

final class OllamaProvider: LLMProvider {
    private let endpoint: String
    
    init(endpoint: String = "http://localhost:11434") {
        self.endpoint = endpoint
    }
    
    func transcribeVideo(videoData: Data, mimeType: String, prompt: String) async throws -> (transcripts: [TranscriptChunk], log: LLMCall) {
        fatalError("OllamaProvider not implemented yet")
    }
    
    func generateActivityCards(transcripts: [TranscriptChunk], context: ActivityGenerationContext) async throws -> (cards: [ActivityCard], log: LLMCall) {
        fatalError("OllamaProvider not implemented yet")
    }
}