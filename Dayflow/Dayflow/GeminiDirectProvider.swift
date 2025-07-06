//
//  GeminiDirectProvider.swift
//  Dayflow
//

import Foundation

final class GeminiDirectProvider: LLMProvider {
    private let apiKey: String
    private let genEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-04-17:generateContent"
    private let fileEndpoint = "https://generativelanguage.googleapis.com/upload/v1beta/files"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func transcribeVideo(videoData: Data, mimeType: String, prompt: String, batchStartTime: Date) async throws -> (observations: [Observation], log: LLMCall) {
        let callStart = Date()
        
        // First, save video data to a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try videoData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let fileURI = try await uploadAndAwait(tempURL, mimeType: mimeType, key: apiKey).1
        
        let finalTranscriptionPrompt = """
        Your job is to act as an expert transcriber for someone's computer usage. your descriptions should capture context and intent of the what the user is doing. 
        for example, if the user is watching a youtube video, what's important is capturing the essence of what the video is about, not necessarily every invidiaul detail about the video. 
        Each transcription should include a timestamp range of the particular action eg (MM:SS - MM:SS). Each transcription should also be >30seconds long, although exercise your judgement.
         If you're going to start a separate transcription, it should be because of a big shift in context.
        """
        
        let response = try await geminiTranscribeRequest(
            fileURI: fileURI,
            mimeType: mimeType,
            prompt: finalTranscriptionPrompt
        )
        
        let videoTranscripts = try parseTranscripts(response)
        
        // Convert video transcripts to observations with proper Unix timestamps
        let observations = videoTranscripts.map { chunk in
            let startSeconds = parseVideoTimestamp(chunk.startTimestamp)
            let endSeconds = parseVideoTimestamp(chunk.endTimestamp)
            let startDate = batchStartTime.addingTimeInterval(TimeInterval(startSeconds))
            let endDate = batchStartTime.addingTimeInterval(TimeInterval(endSeconds))
            
            return Observation(
                id: nil,
                batchId: 0, // Will be set when saved
                startTs: Int(startDate.timeIntervalSince1970),
                endTs: Int(endDate.timeIntervalSince1970),
                observation: chunk.description,
                metadata: nil,
                llmModel: "gemini-2.5-flash-preview-04-17",
                createdAt: Date()
            )
        }
        
        let log = LLMCall(
            timestamp: callStart,
            latency: Date().timeIntervalSince(callStart),
            input: finalTranscriptionPrompt,
            output: response
        )
        
        return (observations, log)
    }
    
    func generateActivityCards(observations: [Observation], context: ActivityGenerationContext) async throws -> (cards: [ActivityCard], log: LLMCall) {
        let callStart = Date()
        
        // Convert observations to human-readable format for the prompt
        let transcriptText = observations.map { obs in
            let startTime = formatTimestampForPrompt(obs.startTs)
            let endTime = formatTimestampForPrompt(obs.endTs)
            return "[\(startTime) - \(endTime)]: \(obs.observation)"
        }.joined(separator: "\n")
        
        // Convert existing cards to JSON string
        let existingCardsJSON = try JSONEncoder().encode(context.existingCards)
        let existingCardsString = String(data: existingCardsJSON, encoding: .utf8) ?? "[]"
        
        // Format current time
        let formatter = ISO8601DateFormatter()
        let currentTimeStr = formatter.string(from: context.currentTime)
        
        // Get the last card title for continuity hint
        let lastCardTitle = context.existingCards.last?.title ?? "None"
        
        let activityGenerationPrompt = """
        You are Dayflow, an AI that analyzes screen recordings to create timeline cards. You are seeing a 1-hour window of activity that may be part of a longer session.

        **CONTEXT PROVIDED:**
        1. Observations from the last hour:
        \(transcriptText)
        
        2. Existing timeline cards that overlap with this window:
        \(existingCardsString)
        
        3. Current time: \(currentTimeStr)

        **YOUR TASK:**
        Generate timeline cards for the full window shown in the observations. You may:
        - Continue existing cards if the activity is ongoing
        - Modify existing cards if better organization is warranted
        - Create new cards for new activities

        **CRITICAL RULES:**
        1. **Continuity**: The last card shown was "\(lastCardTitle)". If observations show this activity continuing, extend it rather than creating a new card.
        2. **15+ minute rule**: Main activity segments must be at least 15 minutes
        3. **Distractions**: Track activities between 30 seconds and 15 minutes as distractions within larger segments
        4. **No time travel**: Cards cannot extend beyond \(currentTimeStr)
        5. **Observation alignment**: Card times should align with observation timestamps (±5 minutes max deviation)
        6. **No overlaps**: Cards must not overlap in time
        7. **Complete coverage**: Your cards must cover the ENTIRE observation window with no gaps

        **OUTPUT FORMAT:**
        Return ONLY a JSON array with this EXACT structure:

        [
          {
            "startTime": "0:00",
            "endTime": "45:30",
            "category": "Productive Work",
            "subcategory": "Coding",
            "title": "Bug Fix",
            "summary": "Fixed authentication bug in the login flow and added error handling",
            "detailedSummary": "Debugged issue where users were getting logged out unexpectedly. Traced problem to JWT token expiration handling. Added proper error boundaries and user-friendly error messages. Tested with multiple user accounts.",
            "distractions": [
              {
                "startTime": "10:15",
                "endTime": "11:45",
                "title": "Twitter",
                "summary": "Checked notifications and scrolled feed"
              }
            ]
          }
        ]

        **FIELD REQUIREMENTS:**
        - startTime/endTime: "MM:SS" format (e.g., "5:30", "65:00" for times over an hour)
        - category: Broad category from taxonomy
        - subcategory: Specific subcategory from taxonomy  
        - title: 1-3 words, specific enough to understand at a glance
        - summary: 1-2 sentences, NO first-person, start with verb, focus on what was accomplished
        - detailedSummary: Longer factual description for future analysis
        - distractions: Array (can be empty), only include activities 30 seconds to 15 minutes

        **ORGANIZATION PRINCIPLES:**
        - Strongly prefer keeping related work in single segments (e.g., one "Coding" card vs multiple)
        - If someone has been doing the same activity for hours, that's ONE card, not many
        - Brief interruptions (<15 min) should be distractions, not new segments
        - If you see fragmentation from previous analysis, feel free to consolidate

        **TAXONOMY:**
        USER PREFERRED TAXONOMY:
        \(context.userTaxonomy)
        
        SYSTEM GENERATED TAXONOMY:
        \(context.extractedTaxonomy)
        
        PREVIOUS SEGMENT:
        \(context.previousSegmentsJSON)

        Remember: You're seeing a rolling window. Activities often continue beyond what you can see. Bias toward continuity while maintaining accuracy.
        """
        
        print(activityGenerationPrompt)
        
        let response = try await geminiCardsRequest(
            prompt: activityGenerationPrompt
        )
        
        let cards = try parseActivityCards(response)
        
        let log = LLMCall(
            timestamp: callStart,
            latency: Date().timeIntervalSince(callStart),
            input: activityGenerationPrompt,
            output: response
        )
        
        return (cards, log)
    }
    
    // MARK: - Gemini-specific methods (from original GeminiService)
    
    private func uploadAndAwait(_ fileURL: URL, mimeType: String, key: String, maxWaitTime: TimeInterval = 6 * 60) async throws -> (fileSize: Int64, fileURI: String) {
        let fileData = try Data(contentsOf: fileURL)
        let fileSize = fileData.count
        var uploadedFileURI: String? = nil
        
        print("[DEBUG] Uploading file of size: \(fileSize / 1024 / 1024) MB")
        
        // Always use resumable upload
        print("[DEBUG] Using resumable upload")
        uploadedFileURI = try await uploadResumable(data: fileData, mimeType: mimeType)
        
        guard let fileURI = uploadedFileURI else {
            throw NSError(domain: "GeminiError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to upload file"])
        }
        
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < maxWaitTime {
            let status = try await getFileStatus(fileURI: fileURI)
            if status == "ACTIVE" {
                return (Int64(fileSize), fileURI)
            }
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
        
        throw NSError(domain: "GeminiError", code: 2, userInfo: [NSLocalizedDescriptionKey: "File processing timeout"])
    }
    
    private func uploadSimple(data: Data, mimeType: String) async throws -> String {
        var request = URLRequest(url: URL(string: fileEndpoint + "?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        
        if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let file = json["file"] as? [String: Any],
           let uri = file["uri"] as? String {
            return uri
        }
        
        throw NSError(domain: "GeminiError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse upload response"])
    }
    
private func uploadResumable(data: Data, mimeType: String) async throws -> String {
        let metadata = GeminiFileMetadata(file: GeminiFileInfo(displayName: "dayflow_video"))
        let boundary = UUID().uuidString
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
        body.append(try JSONEncoder().encode(metadata))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        var request = URLRequest(url: URL(string: fileEndpoint + "?key=\(apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        request.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        request.setValue("\(data.count)", forHTTPHeaderField: "X-Goog-Upload-Raw-Size")
        request.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(metadata)
        
        let (responseData, response) = try await URLSession.shared.data(for: request)
        
        print("[DEBUG] Resumable upload init response status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        if let httpResponse = response as? HTTPURLResponse {
            print("[DEBUG] Response headers: \(httpResponse.allHeaderFields)")
        }
        if let responseString = String(data: responseData, encoding: .utf8) {
            print("[DEBUG] Response body: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse,
              let uploadURL = httpResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL") else {
            throw NSError(domain: "GeminiError", code: 4, userInfo:  [NSLocalizedDescriptionKey: "No upload URL in response"])
        }
        
        var uploadRequest = URLRequest(url: URL(string: uploadURL)!)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.httpBody = data
        
        let (uploadResponseData, _) = try await URLSession.shared.data(for: uploadRequest)
        
        if let json = try JSONSerialization.jsonObject(with: uploadResponseData) as? [String: Any],
           let file = json["file"] as? [String: Any],
           let uri = file["uri"] as? String {
            return uri
        }
        
        throw NSError(domain: "GeminiError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse upload response"])
    }
    
    private func getFileStatus(fileURI: String) async throws -> String {
        guard let url = URL(string: fileURI + "?key=\(apiKey)") else {
            throw NSError(domain: "GeminiError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid file URI"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let state = json["state"] as? String {
            return state
        }
        
        return "UNKNOWN"
    }
    
    private func geminiTranscribeRequest(fileURI: String, mimeType: String, prompt: String) async throws -> String {
        let transcriptionSchema: [String:Any] = [
          "type":"ARRAY",
          "items": [
            "type":"OBJECT",
            "properties":[
              "startTimestamp":["type":"STRING"],
              "endTimestamp":  ["type":"STRING"],
              "description":   ["type":"STRING"]
            ],
            "required":["startTimestamp","endTimestamp","description"],
            "propertyOrdering":["startTimestamp","endTimestamp","description"]
          ]
        ]
        
        let generationConfig: [String: Any] = [
            "temperature": 0.3,
            "maxOutputTokens": 65536,
            "responseMimeType": "application/json",
            "responseSchema": transcriptionSchema,
            "thinkingConfig": [
                "thinkingBudget": 24576
            ]
        ]

        let requestBody: [String: Any] = [
            "contents": [["parts": [
                ["file_data": ["mime_type": mimeType, "file_uri": fileURI]],
                ["text": prompt]
            ]]],
            "generationConfig": generationConfig
        ]
        
        // Retry logic with exponential backoff
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                var request = URLRequest(url: URL(string: genEndpoint + "?key=\(apiKey)")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                request.timeoutInterval = 120 // 2 minutes timeout
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                // Check for rate limiting
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    let delay = TimeInterval(retryAfter ?? "60") ?? 60
                    print("[DEBUG] Rate limited, retrying after \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    throw NSError(domain: "GeminiError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                }
                
                return text
                
            } catch {
                lastError = error
                
                // If it's not the last attempt, wait before retrying
                if attempt < maxRetries - 1 {
                    let backoffDelay = pow(2.0, Double(attempt)) * 5.0 // 5s, 10s, 20s
                    print("[DEBUG] Gemini transcribe request failed (attempt \(attempt + 1)/\(maxRetries)): \(error.localizedDescription)")
                    print("[DEBUG] Retrying in \(backoffDelay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                }
            }
        }
        
        print("[DEBUG] Gemini transcribe request failed after \(maxRetries) attempts")
        throw lastError ?? NSError(domain: "GeminiError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Request failed after \(maxRetries) attempts"])
    }
    
    // Temporary struct for parsing Gemini response
    private struct VideoTranscriptChunk: Codable {
        let startTimestamp: String   // MM:SS
        let endTimestamp: String     // MM:SS
        let description: String
    }
    
    private func parseTranscripts(_ response: String) throws -> [VideoTranscriptChunk] {
        guard let data = response.data(using: .utf8) else {
            throw NSError(domain: "GeminiError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid response encoding"])
        }
        
        let transcripts = try JSONDecoder().decode([VideoTranscriptChunk].self, from: data)
        return transcripts
    }
    
    private func geminiCardsRequest(prompt: String) async throws -> String {
        let distractionSchema: [String: Any] = [
            "type": "OBJECT", "properties": ["startTime": ["type": "STRING"], "endTime": ["type": "STRING"], "title": ["type": "STRING"], "summary": ["type": "STRING"]],
            "required": ["startTime", "endTime", "title", "summary"], "propertyOrdering": ["startTime", "endTime", "title", "summary"]
        ]
        
        let cardSchema: [String: Any] = [
            "type": "ARRAY", "items": [
                "type": "OBJECT", "properties": [
                    "startTimestamp": ["type": "STRING"], "endTimestamp": ["type": "STRING"], "category": ["type": "STRING"],
                    "subcategory": ["type": "STRING"], "title": ["type": "STRING"], "summary": ["type": "STRING"],
                    "detailedSummary": ["type": "STRING"], "distractions": ["type": "ARRAY", "items": distractionSchema]
                ],
                "required": ["startTimestamp", "endTimestamp", "category", "subcategory", "title", "summary", "detailedSummary"],
                "propertyOrdering": ["startTimestamp", "endTimestamp", "category", "subcategory", "title", "summary", "detailedSummary", "distractions"]
            ]
        ]
        
        let generationConfig: [String: Any] = [
            "temperature": 0.3,
            "maxOutputTokens": 65536,
            "responseMimeType": "application/json",
            "responseSchema": cardSchema,
            "thinkingConfig": [
                "thinkingBudget": 24576
            ]
        ]
        
        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": generationConfig
        ]
        
        // Retry logic with exponential backoff
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                var request = URLRequest(url: URL(string: genEndpoint + "?key=\(apiKey)")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                request.timeoutInterval = 120 // 2 minutes timeout
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                // Check for rate limiting
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    let delay = TimeInterval(retryAfter ?? "60") ?? 60
                    print("[DEBUG] Rate limited, retrying after \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    throw NSError(domain: "GeminiError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                }
                
                return text
                
            } catch {
                lastError = error
                
                // If it's not the last attempt, wait before retrying
                if attempt < maxRetries - 1 {
                    let backoffDelay = pow(2.0, Double(attempt)) * 5.0 // 5s, 10s, 20s
                    print("[DEBUG] Gemini cards request failed (attempt \(attempt + 1)/\(maxRetries)): \(error.localizedDescription)")
                    print("[DEBUG] Retrying in \(backoffDelay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                }
            }
        }
        
        print("[DEBUG] Gemini cards request failed after \(maxRetries) attempts")
        throw lastError ?? NSError(domain: "GeminiError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Request failed after \(maxRetries) attempts"])
    }
    
    private func parseActivityCards(_ response: String) throws -> [ActivityCard] {
        guard let data = response.data(using: .utf8) else {
            throw NSError(domain: "GeminiError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid response encoding"])
        }
        
        // Need to map the response format to our ActivityCard format
        struct GeminiActivityCard: Codable {
            let startTimestamp: String
            let endTimestamp: String
            let category: String
            let subcategory: String
            let title: String
            let summary: String
            let detailedSummary: String
            let distractions: [GeminiDistraction]?
        }
        
        struct GeminiDistraction: Codable {
            let startTime: String
            let endTime: String
            let title: String
            let summary: String
        }
        
        let geminiCards = try JSONDecoder().decode([GeminiActivityCard].self, from: data)
        
        // Convert to our ActivityCard format
        return geminiCards.map { geminiCard in
            ActivityCard(
                startTime: geminiCard.startTimestamp,
                endTime: geminiCard.endTimestamp,
                category: geminiCard.category,
                subcategory: geminiCard.subcategory,
                title: geminiCard.title,
                summary: geminiCard.summary,
                detailedSummary: geminiCard.detailedSummary,
                distractions: geminiCard.distractions?.map { d in
                    Distraction(
                        startTime: d.startTime,
                        endTime: d.endTime,
                        title: d.title,
                        summary: d.summary
                    )
                }
            )
        }
    }
}

// MARK: - Gemini-specific types

private struct GeminiFileMetadata: Codable {
    let file: GeminiFileInfo
}

private struct GeminiFileInfo: Codable {
    let displayName: String
    
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}
