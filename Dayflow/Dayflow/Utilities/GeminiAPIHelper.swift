//
//  GeminiAPIHelper.swift
//  Dayflow
//
//  Helper for testing Gemini API connection
//

import Foundation

class GeminiAPIHelper {
    static let shared = GeminiAPIHelper()
    private init() {}
    
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
    
    enum APIError: Error, LocalizedError {
        case invalidAPIKey
        case networkError(String)
        case invalidResponse
        
        var errorDescription: String? {
            switch self {
            case .invalidAPIKey:
                return "Invalid or missing API key"
            case .networkError(let message):
                return "Network error: \(message)"
            case .invalidResponse:
                return "Invalid response from server"
            }
        }
    }
    
    // Test the API connection with a simple request
    func testConnection(apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw APIError.invalidAPIKey
        }
        
        let url = URL(string: "\(baseURL)?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Simple test request
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "Please respond with exactly: Hi from Gemini!"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 100
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw APIError.invalidAPIKey
        }
        
        if httpResponse.statusCode != 200 {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorData["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw APIError.networkError(message)
            }
            throw APIError.networkError("Status code: \(httpResponse.statusCode)")
        }
        
        // Parse the response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw APIError.invalidResponse
        }
        
        return text
    }
}