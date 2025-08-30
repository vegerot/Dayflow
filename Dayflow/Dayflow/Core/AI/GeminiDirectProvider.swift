//
//  GeminiDirectProvider.swift
//  Dayflow
//

import Foundation

final class GeminiDirectProvider: LLMProvider {
    private let apiKey: String
    private let genEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent"
    private let fileEndpoint = "https://generativelanguage.googleapis.com/upload/v1beta/files"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Debug helpers
    private func truncate(_ text: String, max: Int = 2000) -> String {
        if text.count <= max { return text }
        let endIdx = text.index(text.startIndex, offsetBy: max)
        return String(text[..<endIdx]) + "…(truncated)"
    }

    private func headerValue(_ response: URLResponse?, _ name: String) -> String? {
        (response as? HTTPURLResponse)?.value(forHTTPHeaderField: name)
    }

    private func logGeminiFailure(context: String, attempt: Int? = nil, response: URLResponse?, data: Data?, error: Error?) {
        var parts: [String] = []
        parts.append("🔎 GEMINI DEBUG: context=\(context)")
        if let attempt { parts.append("attempt=\(attempt)") }
        if let http = response as? HTTPURLResponse {
            parts.append("status=\(http.statusCode)")
            let reqId = headerValue(response, "X-Goog-Request-Id") ?? headerValue(response, "x-request-id")
            if let reqId { parts.append("requestId=\(reqId)") }
            if let ct = headerValue(response, "Content-Type") { parts.append("contentType=\(ct)") }
        }
        if let error = error as NSError? {
            parts.append("error=\(error.domain)#\(error.code): \(error.localizedDescription)")
        }
        print(parts.joined(separator: " "))

        if let data {
            if let jsonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let keys = Array(jsonObj.keys).sorted().joined(separator: ", ")
                if let err = jsonObj["error"] as? [String: Any] {
                    let message = err["message"] as? String ?? "<none>"
                    let status = err["status"] as? String ?? "<none>"
                    let code = err["code"] as? Int ?? -1
                    print("🔎 GEMINI DEBUG: errorObject code=\(code) status=\(status) message=\(truncate(message, max: 500))")
                } else {
                    print("🔎 GEMINI DEBUG: jsonKeys=[\(keys)]")
                }
            }
            if let body = String(data: data, encoding: .utf8) {
                print("🔎 GEMINI DEBUG: bodySnippet=\(truncate(body, max: 1200))")
            } else {
                print("🔎 GEMINI DEBUG: bodySnippet=<non-UTF8 data length=\(data.count) bytes>")
            }
        }
    }
    
    private func generateCurlCommand(url: String, requestBody: [String: Any]) -> String {
        // Convert request body to JSON string with pretty printing for readability
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody, options: [.prettyPrinted, .sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "# Failed to generate curl command"
        }
        
        // Escape single quotes in JSON for shell
        let escapedJson = jsonString.replacingOccurrences(of: "'", with: "'\\''")
        
        // Mask API key in URL for security (show first 8 chars only)
        var maskedUrl = url
        if let keyRange = url.range(of: "key=") {
            let keyStart = url.index(keyRange.upperBound, offsetBy: 0)
            if url.distance(from: keyStart, to: url.endIndex) > 8 {
                let keyEnd = url.index(keyStart, offsetBy: 8)
                let maskedKey = String(url[keyStart..<keyEnd]) + "..."
                maskedUrl = String(url[url.startIndex..<keyRange.upperBound]) + maskedKey
            }
        }
        
        // Build curl command
        var curlCommand = "# Replace YOUR_API_KEY with your actual API key\n"
        curlCommand += "curl -X POST '\(maskedUrl)' \\\n"
        curlCommand += "  -H 'Content-Type: application/json' \\\n"
        curlCommand += "  -d '\(escapedJson)'"
        
        return curlCommand
    }
    
    private func logCurlCommand(context: String, url: String, requestBody: [String: Any]) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("\n📋 CURL COMMAND for \(context) at \(timestamp):")
        print("================================================================================")
        print(generateCurlCommand(url: url, requestBody: requestBody))
        print("================================================================================\n")
    }
    
    // Track request timing for rate limit analysis
    private static var lastRequestTime: Date?
    private static let requestQueue = DispatchQueue(label: "gemini.request.timing")
    
    private func logRequestTiming(context: String) {
        Self.requestQueue.sync {
            let now = Date()
            if let last = Self.lastRequestTime {
                let interval = now.timeIntervalSince(last)
                print("⏱️ GEMINI TIMING: \(context) - \(String(format: "%.1f", interval))s since last request")
            } else {
                print("⏱️ GEMINI TIMING: \(context) - First request")
            }
            Self.lastRequestTime = now
        }
    }
    
    func transcribeVideo(videoData: Data, mimeType: String, prompt: String, batchStartTime: Date, videoDuration: TimeInterval, batchId: Int64?) async throws -> (observations: [Observation], log: LLMCall) {
        let callStart = Date()
        
        // First, save video data to a temporary file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try videoData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let fileURI = try await uploadAndAwait(tempURL, mimeType: mimeType, key: apiKey).1
        
        // Format duration for display
        let durationMinutes = Int(videoDuration / 60)
        let durationSeconds = Int(videoDuration.truncatingRemainder(dividingBy: 60))
        let durationString = String(format: "%02d:%02d", durationMinutes, durationSeconds)
        
        let finalTranscriptionPrompt = """
        # Video Transcription Prompt

        Your job is to transcribe someone's computer usage into a small number of meaningful activity segments.

        ## CRITICAL: This video is exactly \(durationString) long. ALL timestamps MUST be within 00:00 to \(durationString).

        ## Golden Rule: Aim for 3-5 segments per 15-minute video (fewer is better than more)

        ## Core Principles:
        1. **Group by purpose, not by platform** - If someone is planning a trip across 5 websites, that's ONE segment
        2. **Include interruptions in the description** - Don't create segments for brief distractions
        3. **Only split when context changes for 2-3+ minutes** - Quick checks don't count as context switches
        4. **Combine related activities** - Multiple videos on the same topic = one segment
        5. **Think in terms of "sessions"** - What would you tell a friend you spent time doing?

        ## When to create a new segment:
        Only when the user switches to a COMPLETELY different purpose for MORE than 2-3 minutes:
        - Entertainment → Work
        - Learning → Shopping  
        - Project A → Project B
        - Topic X → Unrelated Topic Y

        ## Format:
        ```json
        [
          {
            "startTimestamp": "MM:SS",
            "endTimestamp": "MM:SS", 
            "description": "1-3 sentences describing what the user accomplished"
          }
        ]
        ```

        ## Examples:

        **GOOD - Properly condensed:**
        ```json
        [
          {
            "startTimestamp": "00:00",
            "endTimestamp": "06:45",
            "description": "User plans a trip to Japan, researching flights on multiple booking sites, reading hotel reviews, and watching YouTube videos about Tokyo neighborhoods. They briefly check email twice and respond to a text message during their research."
          },
          {
            "startTimestamp": "06:45", 
            "endTimestamp": "10:30",
            "description": "User takes an online Spanish course, completing lesson exercises and watching grammar explanation videos. They use Google Translate to verify some phrases and briefly check Reddit when they get stuck on a difficult concept."
          },
          {
            "startTimestamp": "10:30",
            "endTimestamp": "14:58",
            "description": "User shops for home gym equipment, comparing prices across Amazon, fitness retailer sites, and watching product review videos. They check their banking app to verify their budget midway through."
          }
        ]
        ```

        **BAD - Too many segments:**
        ```json
        [
          {
            "startTimestamp": "00:00",
            "endTimestamp": "02:00",
            "description": "User searches for flights to Tokyo"
          },
          {
            "startTimestamp": "02:00",
            "endTimestamp": "02:30", 
            "description": "User checks email"
          },
          {
            "startTimestamp": "02:30",
            "endTimestamp": "04:00",
            "description": "User looks at hotels in Tokyo"
          },
          {
            "startTimestamp": "04:00",
            "endTimestamp": "05:00",
            "description": "User watches a Tokyo travel video"
          }
        ]
        ```

        **ALSO BAD - Splitting brief interruptions:**
        ```json
        [
          {
            "startTimestamp": "00:00",
            "endTimestamp": "05:00",
            "description": "User shops for gym equipment"
          },
          {
            "startTimestamp": "05:00",
            "endTimestamp": "05:45",
            "description": "User checks their bank balance"
          },
          {
            "startTimestamp": "05:45",
            "endTimestamp": "10:00",
            "description": "User continues shopping for gym equipment"
          }
        ]
        ```

        **CORRECT way to handle the above:**
        ```json
        [
          {
            "startTimestamp": "00:00",
            "endTimestamp": "10:00",
            "description": "User shops for home gym equipment across multiple retailers, comparing dumbbells, benches, and resistance bands. They briefly check their bank balance around the 5-minute mark to confirm their budget before continuing."
          }
        ]
        ```

        Remember: The goal is to tell the story of what someone accomplished, not log every click. Group aggressively and only split when they truly change what they're doing for an extended period. If an activity is less than 2-3 minutes, it almost never deserves its own segment.
        """
        
        let response = try await geminiTranscribeRequest(
            fileURI: fileURI,
            mimeType: mimeType,
            prompt: finalTranscriptionPrompt,
            batchId: batchId
        )
        
        
        let videoTranscripts = try parseTranscripts(response)
        
        // Convert video transcripts to observations with proper Unix timestamps
        // Validate and process observations
        var hasValidationErrors = false
        let observations = videoTranscripts.compactMap { chunk -> Observation? in
            let startSeconds = parseVideoTimestamp(chunk.startTimestamp)
            let endSeconds = parseVideoTimestamp(chunk.endTimestamp)
            
            // Validate timestamps are within video duration (with 2 minute tolerance)
            let tolerance: TimeInterval = 120.0 // 2 minutes
            if Double(startSeconds) < -tolerance || Double(endSeconds) > videoDuration + tolerance {
                print("❌ VALIDATION ERROR: Observation timestamps exceed video duration!")
                hasValidationErrors = true
                return nil
            }
            let startDate = batchStartTime.addingTimeInterval(TimeInterval(startSeconds))
            let endDate = batchStartTime.addingTimeInterval(TimeInterval(endSeconds))
            
            
            return Observation(
                id: nil,
                batchId: 0, // Will be set when saved
                startTs: Int(startDate.timeIntervalSince1970),
                endTs: Int(endDate.timeIntervalSince1970),
                observation: chunk.description,
                metadata: nil,
                llmModel: "gemini-2.5-flash",
                createdAt: Date()
            )
        }
        
        // If we had validation errors, throw to trigger retry
        if hasValidationErrors {
            throw NSError(domain: "GeminiProvider", code: 100, userInfo: [
                NSLocalizedDescriptionKey: "Gemini generated observations with timestamps exceeding video duration. Video is \(durationString) long but observations extended beyond this."
            ])
        }
        
        // Ensure we have at least one observation
        if observations.isEmpty {
            throw NSError(domain: "GeminiProvider", code: 101, userInfo: [
                NSLocalizedDescriptionKey: "No valid observations generated after filtering out invalid timestamps"
            ])
        }
        
        let log = LLMCall(
            timestamp: callStart,
            latency: Date().timeIntervalSince(callStart),
            input: finalTranscriptionPrompt,
            output: response
        )
        
        let duration = Date().timeIntervalSince(callStart)
        
        return (observations, log)
    }
    
    func generateActivityCards(observations: [Observation], context: ActivityGenerationContext, batchId: Int64?) async throws -> (cards: [ActivityCardData], log: LLMCall) {
        let callStart = Date()
        
        // Convert observations to human-readable format for the prompt
        let transcriptText = observations.map { obs in
            let startTime = formatTimestampForPrompt(obs.startTs)
            let endTime = formatTimestampForPrompt(obs.endTs)
            
            return "[" + startTime + " - " + endTime + "]: " + obs.observation
        }.joined(separator: "\n")
        
        // Building transcript text from observations
        
        // Convert existing cards to JSON string with pretty printing
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let existingCardsJSON = try encoder.encode(context.existingCards)
        let existingCardsString = String(data: existingCardsJSON, encoding: .utf8) ?? "[]"
        
        let activityGenerationPrompt = """
        You are a digital anthropologist, observing a user's raw activity log. Your goal is to synthesize this log into a high-level, human-readable story of their session, presented as a series of timeline cards.
        THE GOLDEN RULE:
        Your primary objective is to create long, meaningful cards that represent a cohesive session of activity, ideally 30-60 minutes+. However, thematic coherence is essential - a card must tell a coherent story. Avoid creating cards shorter than 15-20 minutes unless a major context switch forces it. 
        CRITICAL DATA INTEGRITY RULE:
        When you decide to extend a card, its original startTime is IMMUTABLE. You MUST carry over the startTime from the previous_card you are extending. Failure to preserve the original startTime is a critical error.
        CORE DIRECTIVES:

        Extend by Default: Your first instinct should be to extend the last card. When extending, you must perform these steps:
        a. Preserve the original startTime of the card you are extending. NEVER MODIFY THE START TIMES OF CARDS
        b. Update the endTime to reflect the latest observation.
        c. Rewrite the summary and detailedSummary to tell the complete, unified story from the original start to the new end.
        Group Thematically: Group activities that share a common purpose or topic. If extending would require fundamentally changing the card's title or theme, create a new card instead. Acknowledge the messy reality of multitasking within the summary.
        Tell a Story: The title and summary of each card should tell a coherent story. How did the session start? Where did it pivot? What was the user's apparent goal or rabbit hole?
        Title guidelines:
        Write titles like you're texting a friend about what you did. Natural, conversational, direct.

        Rules:
        - Be specific and clear (not creative or vague)
        - Keep it short - aim for 5-10 words
        - Don't reference other cards or assume context
        - Include main activity + distraction if relevant

        Good examples:
        - "Edited photos in Lightroom"
        - "Python tutorial on Codecademy"
        - "Watched 3 episodes on Netflix"
        - "Wrote blog post, kept checking Instagram"
        - "Researched flights to Tokyo"

        Bad examples:
        - "Early morning digital drift" (too vague/poetic)
        - "Fell down a rabbit hole after lunch" (too long, assumes context)
        - "Extended Browsing Session" (too formal)
        - "Random browsing and activities" (not specific)
        - "Continuing from earlier" (references other cards)

        Summary guidelines:
        Write brief factual summaries optimized for quick scanning. First person perspective without "I".

        Critical rules - NEVER:
        - Use third person ("The session", "The work")
        - Assume future actions, mental states, or unverifiable details
        - Add filler phrases like "kicked off", "dove into", "started with", "began by"
        - Write more than 2-3 short sentences
        - Repeat the same phrases across different summaries

        Style guidelines:
        - State what happened directly - no lead-ins
        - List activities and tools concisely
        - Mention major interruptions or context switches briefly
        - Keep technical terms simple

        Content rules:
        - Maximum 2-3 sentences
        - Just the facts: what you did, which tools/projects, major blockers
        - Include specific names (apps, tools, sites) not generic terms
        - Note pattern interruptions without elaborating

        Good examples:

        "Refactored the user auth module in React, added OAuth support. Debugged CORS issues with the backend API for an hour. Posted question on Stack Overflow when the fix wasn't working."

        "Designed new landing page mockups in Figma. Exported assets and started implementing in Next.js before getting pulled into a client meeting that ran long."

        "Researched competitors' pricing models across SaaS platforms. Built comparison spreadsheet and wrote up recommendations. Got sidetracked reading an article about pricing psychology."

        "Configured CI/CD pipeline in GitHub Actions. Tests kept failing on the build step, turned out to be a Node version mismatch. Fixed it and deployed to staging."

        Bad examples:

        "Kicked off the morning by diving into some design work before transitioning to development tasks. The session was quite productive overall."
        (Too vague, unnecessary transitions, says nothing specific)

        "Started with refactoring the authentication system before moving on to debugging some issues that came up. Ended up spending time researching solutions online."
        (Wordy, lacks specifics, could be half the length)

        "Began by reviewing the codebase and then dove deep into implementing new features. The work involved multiple context switches between different parts of the application."
        (All filler, no actual information)

        YOUR MENTAL MODEL (How to Decide):
        Before making a decision, ask yourself these questions in order:

        What is the dominant theme of the current card?
        Do the new observations continue or relate to this theme? If yes, extend the card by following the procedure in Core Directive #1.
        Is this a brief (<5 min) and unrelated pivot? If yes, add it as a distraction to the current card and continue extending.
        Is this a sustained shift in focus (>15 min) that represents a different activity category or goal? If yes, create a new card regardless of the current card's length.

        DISTRACTIONS:
        A "distraction" is a brief (<5 min) and unrelated activity that interrupts the main theme of a card. Sustained activities (>5 min) are NOT distractions - they either belong to the current theme or warrant a new card. Don't label related sub-tasks as distractions.

        INPUTS:
        Previous cards: \(existingCardsString)
        New observations: \(transcriptText)
        Return ONLY a JSON array with this EXACT structure:
                
                [
                  {
                    "startTime": "1:12 AM",
                    "endTime": "1:30 AM",
                    "category": "Productive Work",
                    "subcategory": "Coding",
                    "title": "Working on auth bug in Dayflow",
                    "summary": "Fixed authentication bug in the login flow and added error handling",
                    "detailedSummary": "Debugged issue where users were getting logged out unexpectedly. Traced problem to JWT token expiration handling. Added proper error boundaries and user-friendly error messages. Tested with multiple user accounts.",
                    "distractions": [
                      {
                        "startTime": "1:15 AM",
                        "endTime": "1:18 AM",
                        "title": "Twitter",
                        "summary": "Checked notifications and scrolled feed"
                      }
                    ]
                  }
                ]
        """
        
        
        // Initial request
        var response = try await geminiCardsRequest(
            prompt: activityGenerationPrompt,
            batchId: batchId
        )
        var cards = try parseActivityCards(response)
        
        // Track the actual prompt used for logging
        var actualPromptUsed = activityGenerationPrompt
        
        // Combined validation and retry loop
        var retryCount = 0
        let maxRetries = 3
        
        while retryCount < maxRetries {
            // Run both validations
            let (coverageValid, coverageError) = validateTimeCoverage(existingCards: context.existingCards, newCards: cards)
            let (durationValid, durationError) = validateTimeline(cards)
            
            // Check if both validations pass
            if coverageValid && durationValid {
                if retryCount > 0 {
                } else {
                }
                break
            }
            
            retryCount += 1
            
            // Build error message combining both validation failures
            var errorMessages: [String] = []
            
            if !coverageValid && coverageError != nil {
                errorMessages.append("""
                TIME COVERAGE ERROR:
                \(coverageError!)
                
                You MUST ensure your output cards collectively cover ALL time periods from the input cards. Do not drop any time segments.
                """)
            }
            
            if !durationValid && durationError != nil {
                if !coverageValid || retryCount == 1 {
                    // Print raw output on first failure or if both validations fail
                }
                errorMessages.append("""
                DURATION ERROR:
                \(durationError!)
                
                REMINDER: All cards except the last one must be at least 10 minutes long. Please merge short activities into longer, more meaningful cards that tell a coherent story.
                """)
            }
            
            if retryCount >= maxRetries {
                break
            }
            
            
            // Enhanced prompt with all error details
            let retryPrompt = activityGenerationPrompt + """
            
            
            PREVIOUS ATTEMPT FAILED - CRITICAL REQUIREMENTS NOT MET:
            
            \(errorMessages.joined(separator: "\n\n"))
            
            Please fix these issues and ensure your output meets all requirements.
            """
            
            // Retry with enhanced prompt
            actualPromptUsed = retryPrompt
            response = try await geminiCardsRequest(prompt: retryPrompt, batchId: batchId)
            cards = try parseActivityCards(response)
        }
        
        let log = LLMCall(
            timestamp: callStart,
            latency: Date().timeIntervalSince(callStart),
            input: actualPromptUsed,
            output: response
        )
        
        let duration = Date().timeIntervalSince(callStart)
        
        return (cards, log)
    }
    
    // MARK: - Gemini-specific methods (from original GeminiService)
    
    private func uploadAndAwait(_ fileURL: URL, mimeType: String, key: String, maxWaitTime: TimeInterval = 6 * 60) async throws -> (fileSize: Int64, fileURI: String) {
        let fileData = try Data(contentsOf: fileURL)
        let fileSize = fileData.count
        var uploadedFileURI: String? = nil
        
        // Removed debug print
        
        // Always use resumable upload
        // Removed debug print
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

        let (responseData, response) = try await URLSession.shared.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
           let file = json["file"] as? [String: Any],
           let uri = file["uri"] as? String {
            return uri
        }
        // Log unexpected response to help debugging
        logGeminiFailure(context: "uploadSimple", response: response, data: responseData, error: nil)
        throw NSError(domain: "GeminiError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse upload response"])
    }
    
private func uploadResumable(data: Data, mimeType: String) async throws -> String {
        print("📤 Starting resumable video upload:")
        print("   Size: \(data.count / 1024 / 1024) MB")
        print("   MIME Type: \(mimeType)")
        
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
        
        let startTime = Date()
        let (responseData, response) = try await URLSession.shared.data(for: request)
        let initDuration = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("🔴 Upload init failed: Non-HTTP response")
            throw NSError(domain: "GeminiError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response during upload init"])
        }
        
        print("📡 Upload session initialized:")
        print("   Status: \(httpResponse.statusCode)")
        print("   Init Duration: \(String(format: "%.2f", initDuration))s")
        
        guard let uploadURL = httpResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL") else {
            print("🔴 No upload URL in response")
            if let bodyText = String(data: responseData, encoding: .utf8) {
                print("   Response Body: \(truncate(bodyText, max: 1000))")
            }
            logGeminiFailure(context: "uploadResumable(start)", response: response, data: responseData, error: nil)
            throw NSError(domain: "GeminiError", code: 4, userInfo:  [NSLocalizedDescriptionKey: "No upload URL in response"])
        }
        
        print("   Upload URL: \(uploadURL.prefix(80))...")
        
        var uploadRequest = URLRequest(url: URL(string: uploadURL)!)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.httpBody = data
        
        let uploadStartTime = Date()
        let (uploadResponseData, uploadResponse) = try await URLSession.shared.data(for: uploadRequest)
        let uploadDuration = Date().timeIntervalSince(uploadStartTime)

        guard let httpUploadResponse = uploadResponse as? HTTPURLResponse else {
            print("🔴 Upload finalize failed: Non-HTTP response")
            throw NSError(domain: "GeminiError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response during upload finalize"])
        }
        
        print("📥 Upload completed:")
        print("   Status: \(httpUploadResponse.statusCode)")
        print("   Upload Duration: \(String(format: "%.2f", uploadDuration))s")
        print("   Upload Speed: \(String(format: "%.2f", Double(data.count) / uploadDuration / 1024 / 1024)) MB/s")
        
        if httpUploadResponse.statusCode != 200 {
            print("🔴 Upload failed with status \(httpUploadResponse.statusCode)")
            if let bodyText = String(data: uploadResponseData, encoding: .utf8) {
                print("   Response Body: \(truncate(bodyText, max: 1000))")
            }
        }
        
        if let json = try JSONSerialization.jsonObject(with: uploadResponseData) as? [String: Any],
           let file = json["file"] as? [String: Any],
           let uri = file["uri"] as? String {
            print("✅ Video uploaded successfully")
            print("   File URI: \(uri)")
            return uri
        }
        
        print("🔴 Failed to parse upload response")
        if let bodyText = String(data: uploadResponseData, encoding: .utf8) {
            print("   Response Body: \(truncate(bodyText, max: 1000))")
        }
        logGeminiFailure(context: "uploadResumable(finalize)", response: uploadResponse, data: uploadResponseData, error: nil)
        throw NSError(domain: "GeminiError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to parse upload response"])
    }
    
    private func getFileStatus(fileURI: String) async throws -> String {
        guard let url = URL(string: fileURI + "?key=\(apiKey)") else {
            throw NSError(domain: "GeminiError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Invalid file URI"])
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let state = json["state"] as? String {
            return state
        }
        // Unexpected response – log for diagnosis but still return UNKNOWN
        logGeminiFailure(context: "getFileStatus", response: response, data: data, error: nil)
        return "UNKNOWN"
    }
    
    private func geminiTranscribeRequest(fileURI: String, mimeType: String, prompt: String, batchId: Int64?) async throws -> String {
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
            "responseSchema": transcriptionSchema
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
        
        let callGroupId = UUID().uuidString
        for attempt in 0..<maxRetries {
                let urlWithKey = genEndpoint + "?key=\(apiKey)"
            var request = URLRequest(url: URL(string: urlWithKey)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 120 // 2 minutes timeout
            let requestStart = Date()
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                
                // Log curl command on first attempt or after failures
                if attempt == 0 || lastError != nil {
                    logCurlCommand(context: "transcribe.generateContent.attempt\(attempt + 1)", url: urlWithKey, requestBody: requestBody)
                }
                
                // Log request timing
                logRequestTiming(context: "transcribe.attempt\(attempt + 1)")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                let requestDuration = Date().timeIntervalSince(requestStart)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("🔴 Non-HTTP response received")
                    throw NSError(domain: "GeminiError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"])
                }
                
                print("📥 Response received for attempt \(attempt + 1):")
                print("   Status Code: \(httpResponse.statusCode)")
                print("   Duration: \(String(format: "%.2f", requestDuration))s")
                
                // Log important headers
                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                    print("   Content-Type: \(contentType)")
                }
                if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length") {
                    print("   Content-Length: \(contentLength) bytes")
                }
                if let requestId = httpResponse.value(forHTTPHeaderField: "X-Goog-Request-Id") ?? httpResponse.value(forHTTPHeaderField: "x-request-id") {
                    print("   Request ID: \(requestId)")
                }
                
                // Check for rate limiting
                if httpResponse.statusCode == 429 {
                    print("🚫 RATE LIMITED (429)")
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    if let retryAfter = retryAfter {
                        print("   Retry-After: \(retryAfter)s")
                    }
                    if let remaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining") {
                        print("   Rate Limit Remaining: \(remaining)")
                    }
                    if let reset = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset") {
                        print("   Rate Limit Reset: \(reset)")
                    }
                    
                    // Log response body for 429 errors
                    if let bodyText = String(data: data, encoding: .utf8) {
                        print("   429 Response Body: \(truncate(bodyText, max: 1000))")
                    }
                    
                    let delay = TimeInterval(retryAfter ?? "60") ?? 60
                    print("⏳ Rate limited, waiting \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                
                // Log any non-200 response details
                if httpResponse.statusCode != 200 {
                    print("🔴 Non-200 status code: \(httpResponse.statusCode)")
                    if let bodyText = String(data: data, encoding: .utf8) {
                        print("   Response Body: \(truncate(bodyText, max: 2000))")
                    } else {
                        print("   Response Body: <non-UTF8 data, \(data.count) bytes>")
                    }
                    
                    // Try to parse error details
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? [String: Any] {
                        if let code = error["code"] { print("   Error Code: \(code)") }
                        if let message = error["message"] { print("   Error Message: \(message)") }
                        if let status = error["status"] { print("   Error Status: \(status)") }
                        if let details = error["details"] { print("   Error Details: \(details)") }
                    }
                }
                // Centralized LLM call logging (success)
                let responseHeaders: [String:String] = (response as? HTTPURLResponse)?.allHeaderFields.reduce(into: [:]) { acc, kv in
                    if let k = kv.key as? String, let v = kv.value as? CustomStringConvertible { acc[k] = v.description }
                } ?? [:]
                let modelName: String? = {
                    if let u = URL(string: urlWithKey) {
                        let last = u.path.split(separator: "/").last.map(String.init)
                        return last?.split(separator: ":").first.map(String.init)
                    }
                    return nil
                }()
                let ctx = LLMCallContext(
                    batchId: batchId,
                    callGroupId: callGroupId,
                    attempt: attempt + 1,
                    provider: "gemini",
                    model: modelName,
                    operation: "transcribe",
                    requestMethod: request.httpMethod,
                    requestURL: request.url,
                    requestHeaders: request.allHTTPHeaderFields,
                    requestBody: request.httpBody,
                    startedAt: requestStart
                )
                LLMLogger.logSuccess(
                    ctx: ctx,
                    http: LLMHTTPInfo(httpStatus: (response as? HTTPURLResponse)?.statusCode, responseHeaders: responseHeaders, responseBody: data),
                    finishedAt: Date()
                )

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    logGeminiFailure(context: "transcribe.generateContent.invalidJSON", attempt: attempt + 1, response: response, data: data, error: nil)
                    throw NSError(domain: "GeminiError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
                }
                
                guard let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first else {
                    logGeminiFailure(context: "transcribe.generateContent.noCandidates", attempt: attempt + 1, response: response, data: data, error: nil)
                    throw NSError(domain: "GeminiError", code: 7, userInfo: [NSLocalizedDescriptionKey: "No candidates in response"])
                }
                
                guard let content = firstCandidate["content"] as? [String: Any] else {
                    logGeminiFailure(context: "transcribe.generateContent.noContent", attempt: attempt + 1, response: response, data: data, error: nil)
                    throw NSError(domain: "GeminiError", code: 7, userInfo: [NSLocalizedDescriptionKey: "No content in candidate"])
                }
                
                guard let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    // This is the key failure - empty content with no parts
                    logGeminiFailure(context: "transcribe.generateContent.emptyContent", attempt: attempt + 1, response: response, data: data, error: nil)
                    throw NSError(domain: "GeminiError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Empty content - no parts array"])
                }
                
                return text
                
            } catch {
                lastError = error
                // Centralized LLM call logging (failure)
                let modelName: String? = {
                    if let u = URL(string: genEndpoint) {
                        let last = u.path.split(separator: "/").last.map(String.init)
                        return last?.split(separator: ":").first.map(String.init)
                    }
                    return nil
                }()
                let ctx = LLMCallContext(
                    batchId: batchId,
                    callGroupId: callGroupId,
                    attempt: attempt + 1,
                    provider: "gemini",
                    model: modelName,
                    operation: "transcribe",
                    requestMethod: request.httpMethod,
                    requestURL: request.url,
                    requestHeaders: request.allHTTPHeaderFields,
                    requestBody: request.httpBody,
                    startedAt: requestStart
                )
                LLMLogger.logFailure(
                    ctx: ctx,
                    http: nil,
                    finishedAt: Date(),
                    errorDomain: (error as NSError).domain,
                    errorCode: (error as NSError).code,
                    errorMessage: (error as NSError).localizedDescription
                )
                
                // Log detailed error information for this attempt
                print("🔴 GEMINI TRANSCRIBE ATTEMPT \(attempt + 1)/\(maxRetries) FAILED:")
                print("   Error Type: \(type(of: error))")
                print("   Error Description: \(error.localizedDescription)")
                
                // Log URLError details if applicable
                if let urlError = error as? URLError {
                    print("   URLError Code: \(urlError.code.rawValue) (\(urlError.code))")
                    if let failingURL = urlError.failingURL {
                        print("   Failing URL: \(failingURL.absoluteString)")
                    }
                    // Note: underlyingError might not be available in all Swift versions
                    
                    // Check for specific network errors
                    switch urlError.code {
                    case .timedOut:
                        print("   ⏱️ REQUEST TIMED OUT")
                    case .notConnectedToInternet:
                        print("   📵 NO INTERNET CONNECTION")
                    case .networkConnectionLost:
                        print("   📡 NETWORK CONNECTION LOST")
                    case .cannotFindHost:
                        print("   🔍 CANNOT FIND HOST")
                    case .cannotConnectToHost:
                        print("   🚫 CANNOT CONNECT TO HOST")
                    case .badServerResponse:
                        print("   💔 BAD SERVER RESPONSE")
                    default:
                        break
                    }
                }
                
                // Log NSError details if applicable
                if let nsError = error as NSError? {
                    print("   NSError Domain: \(nsError.domain)")
                    print("   NSError Code: \(nsError.code)")
                    if !nsError.userInfo.isEmpty {
                        print("   NSError UserInfo: \(nsError.userInfo)")
                    }
                }
                
                // Log transport/parse error with attempt number
                logGeminiFailure(context: "transcribe.generateContent.catch", attempt: attempt + 1, response: nil, data: nil, error: error)
                
                // If it's not the last attempt, wait before retrying
                if attempt < maxRetries - 1 {
                    let backoffDelay = pow(2.0, Double(attempt)) * 5.0 // 5s, 10s, 20s
                    print("⏳ Waiting \(backoffDelay)s before retry \(attempt + 2)/\(maxRetries)...")
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                    print("🔄 Starting transcribe attempt \(attempt + 2)/\(maxRetries)...")
                } else {
                    print("❌ All \(maxRetries) transcribe attempts failed")
                }
            }
        }
        
        // Gemini transcribe request failed after max attempts
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
            print("🔎 GEMINI DEBUG: parseTranscripts received non-UTF8 or empty response: \(truncate(response, max: 400))")
            throw NSError(domain: "GeminiError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Invalid response encoding"])
        }
        do {
            let transcripts = try JSONDecoder().decode([VideoTranscriptChunk].self, from: data)
            return transcripts
        } catch {
            let snippet = truncate(String(data: data, encoding: .utf8) ?? "<non-utf8>", max: 1200)
            print("🔎 GEMINI DEBUG: parseTranscripts JSON decode failed: \(error.localizedDescription) bodySnippet=\(snippet)")
            throw error
        }
    }
    
    private func geminiCardsRequest(prompt: String, batchId: Int64?) async throws -> String {
        let distractionSchema: [String: Any] = [
            "type": "OBJECT", "properties": ["startTime": ["type": "STRING"], "endTime": ["type": "STRING"], "title": ["type": "STRING"], "summary": ["type": "STRING"]],
            "required": ["startTime", "endTime", "title", "summary"], "propertyOrdering": ["startTime", "endTime", "title", "summary"]
        ]
        
        let cardSchema: [String: Any] = [
            "type": "ARRAY", "items": [
                "type": "OBJECT", "properties": [
                    "startTime": ["type": "STRING"], "endTime": ["type": "STRING"], "category": ["type": "STRING"],
                    "subcategory": ["type": "STRING"], "title": ["type": "STRING"], "summary": ["type": "STRING"],
                    "detailedSummary": ["type": "STRING"], "distractions": ["type": "ARRAY", "items": distractionSchema]
                ],
                "required": ["startTime", "endTime", "category", "subcategory", "title", "summary", "detailedSummary"],
                "propertyOrdering": ["startTime", "endTime", "category", "subcategory", "title", "summary", "detailedSummary", "distractions"]
            ]
        ]
        
        let generationConfig: [String: Any] = [
            "temperature": 0.3,
            "maxOutputTokens": 65536,
            "responseMimeType": "application/json",
            "responseSchema": cardSchema
        ]
        
        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": generationConfig
        ]
        
        // Retry logic with exponential backoff
        let maxRetries = 3
        var lastError: Error?
        let callGroupId = UUID().uuidString
        
        for attempt in 0..<maxRetries {
            let urlWithKey = genEndpoint + "?key=\(apiKey)"
            var request = URLRequest(url: URL(string: urlWithKey)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 120 // 2 minutes timeout
            let requestStart = Date()
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                
                // Log curl command on first attempt or after failures
                if attempt == 0 || lastError != nil {
                    logCurlCommand(context: "cards.generateContent.attempt\(attempt + 1)", url: urlWithKey, requestBody: requestBody)
                }
                
                // Log request timing
                logRequestTiming(context: "cards.attempt\(attempt + 1)")
                
                let (data, response) = try await URLSession.shared.data(for: request)
                let requestDuration = Date().timeIntervalSince(requestStart)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("🔴 Non-HTTP response received for cards request")
                    throw NSError(domain: "GeminiError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"])
                }
                
                print("📥 Cards response received for attempt \(attempt + 1):")
                print("   Status Code: \(httpResponse.statusCode)")
                print("   Duration: \(String(format: "%.2f", requestDuration))s")
                
                // Log important headers
                if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                    print("   Content-Type: \(contentType)")
                }
                if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length") {
                    print("   Content-Length: \(contentLength) bytes")
                }
                if let requestId = httpResponse.value(forHTTPHeaderField: "X-Goog-Request-Id") ?? httpResponse.value(forHTTPHeaderField: "x-request-id") {
                    print("   Request ID: \(requestId)")
                }
                
                // Check for rate limiting
                if httpResponse.statusCode == 429 {
                    print("🚫 RATE LIMITED (429) on cards request")
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    if let retryAfter = retryAfter {
                        print("   Retry-After: \(retryAfter)s")
                    }
                    if let remaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining") {
                        print("   Rate Limit Remaining: \(remaining)")
                    }
                    if let reset = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset") {
                        print("   Rate Limit Reset: \(reset)")
                    }
                    
                    // Log response body for 429 errors
                    if let bodyText = String(data: data, encoding: .utf8) {
                        print("   429 Response Body: \(truncate(bodyText, max: 1000))")
                    }
                    
                    let delay = TimeInterval(retryAfter ?? "60") ?? 60
                    print("⏳ Rate limited, waiting \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                
                // Log any non-200 response details
                if httpResponse.statusCode != 200 {
                    print("🔴 Non-200 status code for cards: \(httpResponse.statusCode)")
                    if let bodyText = String(data: data, encoding: .utf8) {
                        print("   Response Body: \(truncate(bodyText, max: 2000))")
                    } else {
                        print("   Response Body: <non-UTF8 data, \(data.count) bytes>")
                    }
                    
                    // Try to parse error details
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = json["error"] as? [String: Any] {
                        if let code = error["code"] { print("   Error Code: \(code)") }
                        if let message = error["message"] { print("   Error Message: \(message)") }
                        if let status = error["status"] { print("   Error Status: \(status)") }
                        if let details = error["details"] { print("   Error Details: \(details)") }
                    }
                }
                // Centralized LLM call logging (success)
                let responseHeaders: [String:String] = (response as? HTTPURLResponse)?.allHeaderFields.reduce(into: [:]) { acc, kv in
                    if let k = kv.key as? String, let v = kv.value as? CustomStringConvertible { acc[k] = v.description }
                } ?? [:]
                let modelName: String? = {
                    if let u = URL(string: urlWithKey) {
                        let last = u.path.split(separator: "/").last.map(String.init)
                        return last?.split(separator: ":").first.map(String.init)
                    }
                    return nil
                }()
                let ctx = LLMCallContext(
                    batchId: batchId,
                    callGroupId: callGroupId,
                    attempt: attempt + 1,
                    provider: "gemini",
                    model: modelName,
                    operation: "generate_activity_cards",
                    requestMethod: request.httpMethod,
                    requestURL: request.url,
                    requestHeaders: request.allHTTPHeaderFields,
                    requestBody: request.httpBody,
                    startedAt: requestStart
                )
                LLMLogger.logSuccess(
                    ctx: ctx,
                    http: LLMHTTPInfo(httpStatus: (response as? HTTPURLResponse)?.statusCode, responseHeaders: responseHeaders, responseBody: data),
                    finishedAt: Date()
                )

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any] else {
                    // Log raw response for invalid format
                    logGeminiFailure(context: "cards.generateContent.invalidFormat", attempt: attempt + 1, response: response, data: data, error: nil)
                    throw NSError(domain: "GeminiError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Invalid response format - missing candidates or content"])
                }
                
                // Check for parts array - if missing, this is likely a schema validation failure
                guard let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    // Log the specific failure - empty content likely means schema validation failed
                    logGeminiFailure(context: "cards.generateContent.emptyContent", attempt: attempt + 1, response: response, data: data, error: nil)
                    throw NSError(domain: "GeminiError", code: 9, userInfo: [NSLocalizedDescriptionKey: "Schema validation likely failed - no content parts in response"])
                }
                
                return text
                
            } catch {
                lastError = error
                let modelName: String? = {
                    if let u = URL(string: genEndpoint) {
                        let last = u.path.split(separator: "/").last.map(String.init)
                        return last?.split(separator: ":").first.map(String.init)
                    }
                    return nil
                }()
                let ctx = LLMCallContext(
                    batchId: batchId,
                    callGroupId: callGroupId,
                    attempt: attempt + 1,
                    provider: "gemini",
                    model: modelName,
                    operation: "generate_activity_cards",
                    requestMethod: request.httpMethod,
                    requestURL: request.url,
                    requestHeaders: request.allHTTPHeaderFields,
                    requestBody: request.httpBody,
                    startedAt: requestStart
                )
                LLMLogger.logFailure(
                    ctx: ctx,
                    http: nil,
                    finishedAt: Date(),
                    errorDomain: (error as NSError).domain,
                    errorCode: (error as NSError).code,
                    errorMessage: (error as NSError).localizedDescription
                )
                
                // Log detailed error information for this attempt
                print("🔴 GEMINI CARDS ATTEMPT \(attempt + 1)/\(maxRetries) FAILED:")
                print("   Error Type: \(type(of: error))")
                print("   Error Description: \(error.localizedDescription)")
                
                // Log URLError details if applicable
                if let urlError = error as? URLError {
                    print("   URLError Code: \(urlError.code.rawValue) (\(urlError.code))")
                    if let failingURL = urlError.failingURL {
                        print("   Failing URL: \(failingURL.absoluteString)")
                    }
                    // Note: underlyingError might not be available in all Swift versions
                    
                    // Check for specific network errors
                    switch urlError.code {
                    case .timedOut:
                        print("   ⏱️ REQUEST TIMED OUT")
                    case .notConnectedToInternet:
                        print("   📵 NO INTERNET CONNECTION")
                    case .networkConnectionLost:
                        print("   📡 NETWORK CONNECTION LOST")
                    case .cannotFindHost:
                        print("   🔍 CANNOT FIND HOST")
                    case .cannotConnectToHost:
                        print("   🚫 CANNOT CONNECT TO HOST")
                    case .badServerResponse:
                        print("   💔 BAD SERVER RESPONSE")
                    default:
                        break
                    }
                }
                
                // Log NSError details if applicable
                if let nsError = error as NSError? {
                    print("   NSError Domain: \(nsError.domain)")
                    print("   NSError Code: \(nsError.code)")
                    if !nsError.userInfo.isEmpty {
                        print("   NSError UserInfo: \(nsError.userInfo)")
                    }
                }
                
                // Log transport/parse error with attempt number
                logGeminiFailure(context: "cards.generateContent.catch", attempt: attempt + 1, response: nil, data: nil, error: error)
                
                // If it's not the last attempt, wait before retrying
                if attempt < maxRetries - 1 {
                    let backoffDelay = pow(2.0, Double(attempt)) * 5.0 // 5s, 10s, 20s
                    print("⏳ Waiting \(backoffDelay)s before retry \(attempt + 2)/\(maxRetries)...")
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                    print("🔄 Starting cards attempt \(attempt + 2)/\(maxRetries)...")
                } else {
                    print("❌ All \(maxRetries) cards attempts failed")
                }
            }
        }
        
        // Gemini cards request failed after max attempts
        throw lastError ?? NSError(domain: "GeminiError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Request failed after \(maxRetries) attempts"])
    }
    
    private func parseActivityCards(_ response: String) throws -> [ActivityCardData] {
        guard let data = response.data(using: .utf8) else {
            print("🔎 GEMINI DEBUG: parseActivityCards received non-UTF8 or empty response: \(truncate(response, max: 400))")
            throw NSError(domain: "GeminiError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid response encoding"])
        }
        
        // Need to map the response format to our ActivityCard format
        struct GeminiActivityCard: Codable {
            let startTime: String
            let endTime: String
            let category: String
            let subcategory: String
            let title: String
            let summary: String
            let detailedSummary: String
            let distractions: [GeminiDistraction]?
            
            // Make distractions optional with default nil
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                startTime = try container.decode(String.self, forKey: .startTime)
                endTime = try container.decode(String.self, forKey: .endTime)
                category = try container.decode(String.self, forKey: .category)
                subcategory = try container.decode(String.self, forKey: .subcategory)
                title = try container.decode(String.self, forKey: .title)
                summary = try container.decode(String.self, forKey: .summary)
                detailedSummary = try container.decode(String.self, forKey: .detailedSummary)
                distractions = try container.decodeIfPresent([GeminiDistraction].self, forKey: .distractions)
            }
        }
        
        struct GeminiDistraction: Codable {
            let startTime: String
            let endTime: String
            let title: String
            let summary: String
        }
        
        let geminiCards: [GeminiActivityCard]
        do {
            geminiCards = try JSONDecoder().decode([GeminiActivityCard].self, from: data)
        } catch {
            let snippet = truncate(String(data: data, encoding: .utf8) ?? "<non-utf8>", max: 1200)
            print("🔎 GEMINI DEBUG: parseActivityCards JSON decode failed: \(error.localizedDescription) bodySnippet=\(snippet)")
            throw error
        }
        
        // Convert to our ActivityCard format
        return geminiCards.map { geminiCard in
            ActivityCardData(
                   startTime: geminiCard.startTime,
                   endTime: geminiCard.endTime,
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

    // (no local logging helpers needed; centralized via LLMLogger)
    
    // MARK: - Validation Helpers
    
    private struct TimeRange {
        let start: Double  // minutes from midnight
        let end: Double
    }
    
    private func timeToMinutes(_ timeStr: String) -> Double {
        // Handle both "10:30 AM" and "05:30" formats
        if timeStr.contains("AM") || timeStr.contains("PM") {
            // Clock format - parse as date
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            
            if let date = formatter.date(from: timeStr) {
                let calendar = Calendar.current
                let components = calendar.dateComponents([.hour, .minute], from: date)
                return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
            return 0
        } else {
            // MM:SS format - convert to minutes
            let seconds = parseVideoTimestamp(timeStr)
            return Double(seconds) / 60.0
        }
    }
    
    private func mergeOverlappingRanges(_ ranges: [TimeRange]) -> [TimeRange] {
        guard !ranges.isEmpty else { return [] }
        
        // Sort by start time
        let sorted = ranges.sorted { $0.start < $1.start }
        var merged: [TimeRange] = []
        
        for range in sorted {
            if merged.isEmpty || range.start > merged.last!.end + 1 {
                // No overlap - add as new range
                merged.append(range)
            } else {
                // Overlap or adjacent - merge with last range
                let last = merged.removeLast()
                merged.append(TimeRange(start: last.start, end: max(last.end, range.end)))
            }
        }
        
        return merged
    }
    
    private func validateTimeCoverage(existingCards: [ActivityCardData], newCards: [ActivityCardData]) -> (isValid: Bool, error: String?) {
        guard !existingCards.isEmpty else {
            return (true, nil)
        }
        
        // Extract time ranges from input cards
        var inputRanges: [TimeRange] = []
        for card in existingCards {
            let startMin = timeToMinutes(card.startTime)
            var endMin = timeToMinutes(card.endTime)
            if endMin < startMin {  // Handle day rollover
                endMin += 24 * 60
            }
            inputRanges.append(TimeRange(start: startMin, end: endMin))
        }
        
        // Merge overlapping/adjacent ranges
        let mergedInputRanges = mergeOverlappingRanges(inputRanges)
        
        // Extract time ranges from output cards (Fix #1: Skip zero or negative duration cards)
        var outputRanges: [TimeRange] = []
        for card in newCards {
            let startMin = timeToMinutes(card.startTime)
            var endMin = timeToMinutes(card.endTime)
            if endMin < startMin {  // Handle day rollover
                endMin += 24 * 60
            }
            // Skip zero or very short duration cards (less than 0.1 minutes = 6 seconds)
            guard endMin - startMin >= 0.1 else {
                continue
            }
            outputRanges.append(TimeRange(start: startMin, end: endMin))
        }
        
        // Check coverage with 3-minute flexibility
        let flexibility = 3.0  // minutes
        var uncoveredSegments: [(start: Double, end: Double)] = []
        
        for inputRange in mergedInputRanges {
            // Check if this input range is covered by output ranges
            var coveredStart = inputRange.start
            var safetyCounter = 10000  // Fix #3: Safety cap to prevent infinite loops
            
            while coveredStart < inputRange.end && safetyCounter > 0 {
                safetyCounter -= 1
                // Find an output range that covers this point
                var foundCoverage = false
                
                for outputRange in outputRanges {
                    // Check if this output range covers the current point (with flexibility)
                    if outputRange.start - flexibility <= coveredStart && coveredStart <= outputRange.end + flexibility {
                        // Move coveredStart to the end of this output range (Fix #2: Force progress)
                        let newCoveredStart = outputRange.end
                        // Ensure we make at least minimal progress (0.01 minutes = 0.6 seconds)
                        coveredStart = max(coveredStart + 0.01, newCoveredStart)
                        foundCoverage = true
                        break
                    }
                }
                
                if !foundCoverage {
                    // Find the next covered point
                    var nextCovered = inputRange.end
                    for outputRange in outputRanges {
                        if outputRange.start > coveredStart && outputRange.start < nextCovered {
                            nextCovered = outputRange.start
                        }
                    }
                    
                    // Add uncovered segment
                    if nextCovered > coveredStart {
                        uncoveredSegments.append((start: coveredStart, end: min(nextCovered, inputRange.end)))
                        coveredStart = nextCovered
                    } else {
                        // No more coverage found, add remaining segment and break
                        uncoveredSegments.append((start: coveredStart, end: inputRange.end))
                        break
                    }
                }
            }
            
            // Check if safety counter was exhausted
            if safetyCounter == 0 {
                return (false, "Time coverage validation loop exceeded safety limit - possible infinite loop detected")
            }
        }
        
        // Check if uncovered segments are significant
        if !uncoveredSegments.isEmpty {
            var uncoveredDesc: [String] = []
            for segment in uncoveredSegments {
                let duration = segment.end - segment.start
                if duration > flexibility {  // Only report significant gaps
                    let startTime = minutesToTimeString(segment.start)
                    let endTime = minutesToTimeString(segment.end)
                    uncoveredDesc.append("\(startTime)-\(endTime) (\(Int(duration)) min)")
                }
            }
            
            if !uncoveredDesc.isEmpty {
                // Build detailed error message with input/output cards
                var errorMsg = "Missing coverage for time segments: \(uncoveredDesc.joined(separator: ", "))"
                errorMsg += "\n\n📥 INPUT CARDS:"
                for (i, card) in existingCards.enumerated() {
                    errorMsg += "\n  \(i+1). \(card.startTime) - \(card.endTime): \(card.title)"
                }
                errorMsg += "\n\n📤 OUTPUT CARDS:"
                for (i, card) in newCards.enumerated() {
                    errorMsg += "\n  \(i+1). \(card.startTime) - \(card.endTime): \(card.title)"
                }
                
                return (false, errorMsg)
            }
        }
        
        return (true, nil)
    }
    
    private func validateTimeline(_ cards: [ActivityCardData]) -> (isValid: Bool, error: String?) {
        for (index, card) in cards.enumerated() {
            let startTime = card.startTime
            let endTime = card.endTime
            
            var durationMinutes: Double = 0
            
            // Check if times are in clock format (contains AM/PM)
            if startTime.contains("AM") || startTime.contains("PM") {
                // Parse clock times
                let formatter = DateFormatter()
                formatter.dateFormat = "h:mm a"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                
                if let startDate = formatter.date(from: startTime),
                   let endDate = formatter.date(from: endTime) {
                    
                    var adjustedEndDate = endDate
                    // Handle day rollover (e.g., 11:30 PM to 12:30 AM)
                    if endDate < startDate {
                        adjustedEndDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
                    }
                    
                    durationMinutes = adjustedEndDate.timeIntervalSince(startDate) / 60.0
                } else {
                    // Failed to parse clock times
                    durationMinutes = 0
                }
            } else {
                // Parse MM:SS format
                let startSeconds = parseVideoTimestamp(startTime)
                let endSeconds = parseVideoTimestamp(endTime)
                durationMinutes = Double(endSeconds - startSeconds) / 60.0
            }
            
            // Check if card is too short (except for last card)
            if durationMinutes < 10 && index < cards.count - 1 {
                return (false, "Card \(index + 1) '\(card.title)' is only \(String(format: "%.1f", durationMinutes)) minutes long")
            }
        }
        
        return (true, nil)
    }
    
    private func minutesToTimeString(_ minutes: Double) -> String {
        let hours = (Int(minutes) / 60) % 24  // Handle > 24 hours
        let mins = Int(minutes) % 60
        let period = hours < 12 ? "AM" : "PM"   
        var displayHour = hours % 12
        if displayHour == 0 {
            displayHour = 12
        }
        return String(format: "%d:%02d %@", displayHour, mins, period)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func parseVideoTimestamp(_ timestamp: String) -> Int {
        // Parse timestamps like "00:00", "01:30", "00:00:00", "01:47:28"
        let components = timestamp.components(separatedBy: ":")
        
        if components.count == 2 {
            // MM:SS format
            let minutes = Int(components[0]) ?? 0
            let seconds = Int(components[1]) ?? 0
            return minutes * 60 + seconds
        } else if components.count == 3 {
            // HH:MM:SS format
            let hours = Int(components[0]) ?? 0
            let minutes = Int(components[1]) ?? 0
            let seconds = Int(components[2]) ?? 0
            return hours * 3600 + minutes * 60 + seconds
        } else {
            // Invalid format, return 0
            print("Warning: Invalid video timestamp format: \(timestamp)")
            return 0
        }
    }
    
    // Helper function to format timestamps
    private func formatTimestampForPrompt(_ unixTime: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(unixTime))
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
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
}
