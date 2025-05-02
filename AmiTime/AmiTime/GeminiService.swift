//
//  GeminiService.swift
//  AmiTime
//
//  Created on 5/1/2025.
//

import Foundation
import AVFoundation
import GRDB

/// Protocol for Gemini API service
protocol GeminiServicing {
    /// Process video recordings and return analysis
    func processVideos(batchId: Int64, urls: [URL], completion: @escaping (Result<GeminiAnalysisResponse, Error>) -> Void)
    
    /// Get Gemini API key
    func apiKey() -> String?
    
    /// Set Gemini API key
    func setApiKey(_ key: String)
}

/// Error types for Gemini service
enum GeminiServiceError: Error {
    case missingApiKey
    case videoProcessingFailed
    case invalidResponse
    case apiRequestFailed(statusCode: Int, message: String)
    case encodingError
    
    var localizedDescription: String {
        switch self {
        case .missingApiKey:
            return "Missing Gemini API key. Please set your API key in settings."
        case .videoProcessingFailed:
            return "Failed to process video files."
        case .invalidResponse:
            return "Received an invalid response from Gemini API."
        case .apiRequestFailed(let statusCode, let message):
            return "API request failed with status code \(statusCode): \(message)"
        case .encodingError:
            return "Failed to encode request data."
        }
    }
}

/// Response structure for Gemini analysis
struct GeminiAnalysisResponse: Codable {
    // Using a nested type here to avoid conflicts with the global TimelineCard
    struct Card: Codable {
        let title: String
        let description: String?
        let category: String
        let startTimestamp: Int
        let endTimestamp: Int
        let metadata: String?  // JSON string for additional data
    }
    
    let cards: [Card]
    
    // Convert to our domain model
    func toTimelineCards() -> [TimelineCard] {
        return cards.map { card in
            TimelineCard(
                title: card.title,
                description: card.description,
                category: card.category,
                startTimestamp: card.startTimestamp,
                endTimestamp: card.endTimestamp,
                metadata: card.metadata
            )
        }
    }
}

/// Service for interacting with the Gemini API
final class GeminiService: GeminiServicing {
    // MARK: - Singleton
    static let shared = GeminiService()
    
    // MARK: - Properties
    private let session: URLSession
    private let baseURL = "https://generativelanguage.googleapis.com/v1/models/gemini-pro-vision:generateContent"
    private let userDefaults = UserDefaults.standard
    private let apiKeyKey = "gemini_api_key"
    
    // MARK: - Initialization
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300  // 5 minutes timeout for video processing
        session = URLSession(configuration: config)
    }
    
    // MARK: - API Key Management
    func apiKey() -> String? {
        userDefaults.string(forKey: apiKeyKey)
    }
    
    func setApiKey(_ key: String) {
        userDefaults.set(key, forKey: apiKeyKey)
    }
    
    // MARK: - Video Processing
    func processVideos(batchId: Int64, urls: [URL], completion: @escaping (Result<GeminiAnalysisResponse, Error>) -> Void) {
        guard let apiKey = apiKey(), !apiKey.isEmpty else {
            completion(.failure(GeminiServiceError.missingApiKey))
            return
        }
        
        // Create a dedicated background queue for video processing
        let processingQueue = DispatchQueue(label: "com.amitine.geminiservice.videoprocessing", qos: .utility)
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Prepare video data
                let videoDataList = try self.prepareVideoData(from: urls)
                print("GeminiService: Prepared \(videoDataList.count) videos for analysis")
                
                // Create Gemini API request
                guard let request = self.createGeminiRequest(
                    apiKey: apiKey,
                    videoDataList: videoDataList,
                    batchId: batchId
                ) else {
                    DispatchQueue.main.async {
                        completion(.failure(GeminiServiceError.encodingError))
                    }
                    return
                }
                
                // Execute request
                let task = self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        DispatchQueue.main.async {
                            completion(.failure(GeminiServiceError.invalidResponse))
                        }
                        return
                    }
                    
                    guard (200...299).contains(httpResponse.statusCode) else {
                        let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                        DispatchQueue.main.async {
                            completion(.failure(GeminiServiceError.apiRequestFailed(
                                statusCode: httpResponse.statusCode,
                                message: message
                            )))
                        }
                        return
                    }
                    
                    guard let data = data else {
                        DispatchQueue.main.async {
                            completion(.failure(GeminiServiceError.invalidResponse))
                        }
                        return
                    }
                    
                    // For now, just provide a simulated response
                    // In a real implementation, we would parse the specific Gemini API response format
                    let simulatedResponse = GeminiAnalysisResponse(cards: [
                        .init(
                            title: "Browsing Documentation",
                            description: "Reading technical documentation",
                            category: "Research",
                            startTimestamp: Int(Date().timeIntervalSince1970) - 1800,
                            endTimestamp: Int(Date().timeIntervalSince1970),
                            metadata: nil
                        )
                    ])
                    
                    DispatchQueue.main.async {
                        completion(.success(simulatedResponse))
                    }
                }
                
                task.resume()
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Struct to represent a video file with its metadata
    private struct VideoData {
        let fileData: Data
        let fileName: String
        let mimeType: String
        let startTimestamp: Int
        let endTimestamp: Int
    }
    
    /// Prepares video data for uploading to Gemini
    private func prepareVideoData(from videoURLs: [URL]) throws -> [VideoData] {
        var videoDataList = [VideoData]()
        
        // First, let's retrieve the timestamps for these videos from the database
        let videoTimestamps = fetchTimestampsForVideos(videoURLs)
        
        for url in videoURLs {
            do {
                // Load the file data
                let fileData = try Data(contentsOf: url)
                
                // Get timestamps from our lookup dictionary, or use placeholders if not found
                let fileName = url.lastPathComponent
                let timestamps = videoTimestamps[url.path] ?? (Int(Date().timeIntervalSince1970) - 1800, Int(Date().timeIntervalSince1970))
                
                videoDataList.append(VideoData(
                    fileData: fileData,
                    fileName: fileName,
                    mimeType: "video/mp4",
                    startTimestamp: timestamps.0,
                    endTimestamp: timestamps.1
                ))
                
                print("GeminiService: Prepared video \(fileName), size: \(fileData.count / 1024) KB, timespan: \(timestamps.1 - timestamps.0) seconds")
            } catch {
                print("GeminiService Error: Failed to prepare video \(url.lastPathComponent) - \(error.localizedDescription)")
                // Continue with other videos rather than failing the entire batch
            }
        }
        
        guard !videoDataList.isEmpty else {
            throw GeminiServiceError.videoProcessingFailed
        }
        
        return videoDataList
    }
    
    /// Fetches timestamps for video files from the database
    private func fetchTimestampsForVideos(_ urls: [URL]) -> [String: (Int, Int)] {
        var result = [String: (Int, Int)]()
        
        // Create a list of paths for the query
        let paths = urls.map { $0.path }
        guard !paths.isEmpty else { return result }
        
        // Get timestamps from StorageManager's new helper method
        let storageManager = StorageManager.shared
        let timestamps = storageManager.getTimestampsForVideoFiles(paths: paths)
        
        // Convert from named tuple to regular tuple format
        for (path, tuple) in timestamps {
            result[path] = (tuple.startTs, tuple.endTs)
        }
        
        print("GeminiService: Retrieved timestamps for \(result.count) of \(paths.count) videos")
        
        return result
    }
    
    /// Creates a Gemini API request with the full video data
    private func createGeminiRequest(apiKey: String, videoDataList: [VideoData], batchId: Int64) -> URLRequest? {
        guard var urlComponents = URLComponents(string: baseURL) else { return nil }
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let url = urlComponents.url else { return nil }
        
        // For multipart form data with videos
        let boundary = UUID().uuidString
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // In a real implementation, we would need to construct a proper multipart request
        // with each video file encoded as a part, along with the JSON prompt
        // This is a placeholder that demonstrates the approach but would need to be completed
        
        let bodyData = NSMutableData()
        
        // Add JSON part with the prompt
        let jsonPart = """
        {
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {
                            "text": "Analyze these screen recordings of my computer activity. Identify distinct tasks and activities I was performing. Group them into segments based on what I was working on. For each segment provide:\\n1. A brief title describing the activity\\n2. The category of work (e.g., coding, research, communication, etc.)\\n3. A description of what I was doing\\n\\nFormat your response as JSON with an array of timeline cards, each with 'title', 'description', 'category', 'startTimestamp', and 'endTimestamp' fields."
                        }
                    ]
                }
            ],
            "generationConfig": {
                "temperature": 0.2,
                "topK": 32,
                "topP": 0.95,
                "maxOutputTokens": 4096,
                "responseMimeType": "application/json"
            }
        }
        """
        
        // Add boundary
        bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
        // Add JSON part header
        bodyData.append("Content-Disposition: form-data; name=\"request\"\r\n".data(using: .utf8)!)
        bodyData.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        // Add JSON data
        bodyData.append(jsonPart.data(using: .utf8)!)
        bodyData.append("\r\n".data(using: .utf8)!)
        
        // Add each video file as a part
        for (index, videoData) in videoDataList.enumerated() {
            // Add boundary
            bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
            // Add file part header
            bodyData.append("Content-Disposition: form-data; name=\"video\(index)\"; filename=\"\(videoData.fileName)\"\r\n".data(using: .utf8)!)
            bodyData.append("Content-Type: \(videoData.mimeType)\r\n\r\n".data(using: .utf8)!)
            // Add file data
            bodyData.append(videoData.fileData)
            bodyData.append("\r\n".data(using: .utf8)!)
        }
        
        // Close the multipart form
        bodyData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = bodyData as Data
        
        // For now, in our simplified version, we'll just use a placeholder
        // In a real implementation, we would need to construct the proper multipart request
        
        return request
    }
}
