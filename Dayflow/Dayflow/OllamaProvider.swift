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
    
    func transcribeVideo(videoData: Data, mimeType: String, prompt: String, batchStartTime: Date) async throws -> (observations: [Observation], log: LLMCall) {
        fatalError("OllamaProvider not implemented yet")
    }
    
    func generateActivityCards(observations: [Observation], context: ActivityGenerationContext) async throws -> (cards: [ActivityCard], log: LLMCall) {
        fatalError("OllamaProvider not implemented yet")
    }
}