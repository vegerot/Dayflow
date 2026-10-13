import AppKit
import Foundation

/// The frames of one batch written out as files the Claude CLI can read.
private struct ClaudeTimelineFrames {
  struct Frame {
    let capturedAt: Int
    let url: URL
  }

  let directory: URL
  let frames: [Frame]

  /// The new window: the first frame's minute to one minute after the last frame's minute.
  var windowStart: Int { frames[0].capturedAt - frames[0].capturedAt % 60 }
  var windowEnd: Int {
    let last = frames[frames.count - 1].capturedAt
    return last - last % 60 + 60
  }

  /// True when the frames are about a minute apart and no two share a minute label.
  var isOneFramePerMinute: Bool {
    guard frames.count > 1 else { return true }
    let gaps = zip(frames, frames.dropFirst()).map { $1.capturedAt - $0.capturedAt }.sorted()
    let medianGap = gaps[gaps.count / 2]
    let minutes = Set(frames.map { $0.capturedAt / 60 })
    return (45...90).contains(medianGap) && minutes.count == frames.count
  }

  func cleanup() {
    try? FileManager.default.removeItem(at: directory)
  }
}

extension ClaudeProvider {
  // MARK: - Claude one-step timeline

  static func timelineModelConfiguration() -> (model: String, reasoningEffort: String?) {
    (model: "haiku", reasoningEffort: "medium")
  }

  private static var timelineFrameMaxHeight: Int { 1080 }
  private static var timelineMaxAttempts: Int { 3 }

  /// One call that reads the batch's screenshots as separate images and writes the timeline
  /// cards, with no transcript in between. Observations are rebuilt from the cards' detail
  /// lines so recaps and chat keep their per-batch record.
  func generateTimeline(
    screenshots: [Screenshot], context: ActivityGenerationContext, batchId: Int64?
  ) async throws -> (cards: [ActivityCardData], observations: [Observation], log: LLMCall) {
    guard !screenshots.isEmpty else {
      throw NSError(
        domain: "ClaudeProvider", code: -96,
        userInfo: [NSLocalizedDescriptionKey: "No screenshots to generate a timeline from"])
    }

    let callStart = Date()
    let modelConfiguration = Self.timelineModelConfiguration()
    let model = modelConfiguration.model
    let effort = modelConfiguration.reasoningEffort
    var run: ChatCLIRunResult?
    var accumulatedUsage: TokenUsage?
    var attempt = 1

    do {
      let frames = try await Self.writeTimelineFrames(screenshots)
      defer { frames.cleanup() }

      // The window stands in for the observations the two-step path would have, so the same
      // rules decide which previous cards connect to this batch and what the cards must cover.
      let window = Observation(
        id: nil,
        batchId: batchId ?? -1,
        startTs: frames.windowStart,
        endTs: frames.windowEnd,
        observation: "",
        metadata: nil,
        llmModel: model,
        createdAt: Date()
      )
      let plan = makeClaudeCardGenerationPlan(
        observations: [window],
        context: ActivityGenerationContext(
          batchObservations: [window],
          existingCards: context.existingCards,
          currentTime: context.currentTime,
          categories: context.categories,
          hasPreviousCardWithinFiveMinutes: context.hasPreviousCardWithinFiveMinutes
        )
      )
      let previousCards = plan.context.existingCards
      let prompt = buildTimelinePrompt(
        frames: frames,
        previousCards: previousCards,
        categories: context.categories
      )

      let profile = ClaudeCLIExecutionProfile.oneStepTimeline
        .allowingReadDirectory(at: frames.directory.path)
      let sessionID = UUID().uuidString
      let sessionCleanup = ClaudeSessionCleanup(sessionID: sessionID)
      defer { sessionCleanup.cleanup() }
      var currentPrompt = prompt

      for currentAttempt in 1...Self.timelineMaxAttempts {
        attempt = currentAttempt
        let sessionMode: ClaudeCLISessionMode =
          currentAttempt == 1 ? .start(id: sessionID) : .resume(id: sessionID)
        let currentRun = try await runOptimizedClaudeTurn(
          prompt: currentPrompt,
          model: model,
          reasoningEffort: effort,
          profile: profile,
          sessionMode: sessionMode
        )
        run = currentRun
        accumulatedUsage = Self.combinedTokenUsage(accumulatedUsage, currentRun.usage)
        try validateSuccessfulClaudeProcess(currentRun)

        let cards: [ActivityCardData]
        do {
          cards = try validatedTimelineCards(
            from: currentRun,
            previousCards: previousCards,
            window: window,
            categories: context.categories,
            batchId: batchId,
            model: model,
            attempt: attempt
          )
        } catch {
          guard currentAttempt < Self.timelineMaxAttempts else { throw error }
          currentPrompt = buildTimelineCorrectionPrompt(
            validationError: error.localizedDescription,
            windowStart: formatTimestampForPrompt(frames.windowStart),
            windowEnd: formatTimestampForPrompt(frames.windowEnd)
          )
          print("[ClaudeProvider] Timeline output failed validation; continuing the same session")
          continue
        }

        let observations = timelineObservations(
          from: cards,
          windowStart: frames.windowStart,
          windowEnd: frames.windowEnd,
          batchId: batchId,
          model: model
        )
        logSuccess(
          ctx: makeCtx(
            batchId: batchId,
            operation: "generate_timeline",
            model: model,
            startedAt: callStart,
            attempt: attempt
          ),
          finishedAt: currentRun.finishedAt,
          stdout: currentRun.stdout,
          stderr: currentRun.stderr,
          responseHeaders: tokenHeaders(from: accumulatedUsage)
        )
        let llmCall = makeLLMCall(
          start: callStart,
          end: currentRun.finishedAt,
          input: currentPrompt,
          output: currentRun.stdout
        )
        return (cards, observations, llmCall)
      }

      throw NSError(
        domain: "ClaudeProvider", code: -95,
        userInfo: [NSLocalizedDescriptionKey: "No timeline cards returned."])
    } catch {
      let nsError = error as NSError
      logFailure(
        ctx: makeCtx(
          batchId: batchId,
          operation: "generate_timeline",
          model: model,
          startedAt: callStart,
          attempt: attempt
        ),
        finishedAt: run?.finishedAt ?? Date(),
        error: error,
        stdout: run?.stdout ?? nsError.userInfo["partialStdout"] as? String,
        stderr: run?.stderr ?? nsError.userInfo["partialStderr"] as? String,
        run: run,
        usage: accumulatedUsage
      )
      throw error
    }
  }

  // MARK: Frames

  private static func writeTimelineFrames(_ screenshots: [Screenshot]) async throws
    -> ClaudeTimelineFrames
  {
    try await Task.detached(priority: .utility) {
      let sorted = screenshots.sorted { $0.capturedAt < $1.capturedAt }
      let selected = ClaudeTranscriptionInputBuilder.evenlySpacedIndices(itemCount: sorted.count)
        .map { sorted[$0] }
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Dayflow-claude-timeline-\(UUID().uuidString)", isDirectory: true)
        .resolvingSymlinksInPath()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

      var frames: [ClaudeTimelineFrames.Frame] = []
      for (index, screenshot) in selected.enumerated() {
        let url = directory.appendingPathComponent(String(format: "frame_%02d.jpg", index + 1))
        do {
          try screenshot.writeJPEG(to: url, maxHeight: timelineFrameMaxHeight, quality: 0.85)
          frames.append(.init(capturedAt: screenshot.capturedAt, url: url))
        } catch {
          print(
            "[ClaudeProvider] Skipping unreadable timeline frame: \(error.localizedDescription)")
        }
      }

      guard !frames.isEmpty else {
        try? FileManager.default.removeItem(at: directory)
        throw NSError(
          domain: "ClaudeProvider", code: -94,
          userInfo: [
            NSLocalizedDescriptionKey: "No screenshots could be loaded for timeline generation."
          ])
      }
      return ClaudeTimelineFrames(directory: directory, frames: frames)
    }.value
  }

  // MARK: Prompt

  private func buildTimelinePrompt(
    frames: ClaudeTimelineFrames,
    previousCards: [ActivityCardData],
    categories: [LLMCategoryDescriptor]
  ) -> String {
    let userName = NSFullUserName()
      .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    let perMinute = frames.isOneFramePerMinute

    var prompt = ClaudeTimelinePrompt.template
      .replacingOccurrences(
        of: ClaudeTimelinePrompt.categoriesPlaceholder, with: categoriesSection(from: categories)
      )
      .replacingOccurrences(
        of: ClaudeTimelinePrompt.languagePlaceholder,
        with: LLMOutputLanguagePreferences.languageInstruction(forJSON: true) ?? ""
      )
    if userName.isEmpty {
      prompt = prompt.replacingOccurrences(
        of: ClaudeTimelinePrompt.nameGiven, with: ClaudeTimelinePrompt.nameMissing)
    }
    if !perMinute {
      prompt = prompt.replacingOccurrences(
        of: ClaudeTimelinePrompt.perMinuteFrames, with: ClaudeTimelinePrompt.irregularFrames)
    }

    let previousCardsData = try? JSONEncoder().encode(previousCards)
    let previousCardsJSON = previousCardsData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

    let labelFormatter = DateFormatter()
    labelFormatter.dateFormat = perMinute ? "h:mm a" : "h:mm:ss a"
    labelFormatter.locale = Locale(identifier: "en_US_POSIX")
    labelFormatter.timeZone = TimeZone.current
    let frameLines = frames.frames.map { frame in
      let label = labelFormatter.string(
        from: Date(timeIntervalSince1970: TimeInterval(frame.capturedAt)))
      return "Frame at " + label + ": " + frame.url.path
    }.joined(separator: "\n")

    // Explicit concatenation keeps screen-derived text in previous cards from being interpolated.
    var text = prompt.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\nINPUTS:\n"
    if !userName.isEmpty {
      text += "User: " + userName + "\n"
    }
    text += "Previous cards: " + previousCardsJSON + "\n"
    text +=
      "New screenshots: " + String(frames.frames.count) + " frames, covering "
      + formatTimestampForPrompt(frames.windowStart) + " to "
      + formatTimestampForPrompt(frames.windowEnd) + ". Each is a local image file:\n"
    text += frameLines + "\n\n"
    text +=
      "Tool requirement: use Read exactly once on every listed file before answering. "
      + "Do not narrate or summarize individual frames before the answer.\n\n"
    text += ClaudeTimelinePrompt.outputBlock
    return text
  }

  private func buildTimelineCorrectionPrompt(
    validationError: String, windowStart: String, windowEnd: String
  ) -> String {
    """
    The previous JSON output has validation errors. Fix it using the screenshots and context already in this conversation.

    Issues:
    \(validationError)

    Requirements:
    - Return the FULL corrected JSON array, not a diff.
    - The cards together must cover the previous cards' time and the new window, \(windowStart) to \(windowEnd), with no gaps and no overlaps, and must not extend past \(windowEnd).
    - Every card except the last must be 10 to 60 minutes long. Fold a shorter stretch into the neighbouring card and keep its detail lines.
    - Keep the detailedSummary lines that were correct; only change what the issues require.
    - Do not reread files or use tools. Output JSON only, with no code fences or extra text.
    """
  }

  // MARK: Validation

  private func validatedTimelineCards(
    from run: ChatCLIRunResult,
    previousCards: [ActivityCardData],
    window: Observation,
    categories: [LLMCategoryDescriptor],
    batchId: Int64?,
    model: String,
    attempt: Int
  ) throws -> [ActivityCardData] {
    let parsedCards = try parseCards(from: run.stdout, stderr: run.stderr)
    let normalizedCards = normalizeCards(parsedCards, descriptors: categories)
    let (isValid, validationError) = validateClaudeTimeCoverage(
      existingCards: previousCards,
      requiredObservations: [window],
      newCards: normalizedCards
    )
    guard isValid else {
      let detail = validationError ?? "Timeline cards failed validation."
      AnalyticsService.shared.captureValidationFailure(
        provider: "chat_cli",
        providerID: providerID,
        operation: "generate_timeline",
        validationType: "time_coverage",
        attempt: attempt,
        model: model,
        batchId: batchId,
        errorDetail: detail
      )
      throw NSError(
        domain: "ClaudeProvider", code: -93,
        userInfo: [NSLocalizedDescriptionKey: detail])
    }
    return normalizedCards
  }

  // MARK: Observations

  /// Rebuilds per-batch observations from the detail lines the cards carry for the new window,
  /// falling back to one observation per card when no line can be read.
  private func timelineObservations(
    from cards: [ActivityCardData],
    windowStart: Int,
    windowEnd: Int,
    batchId: Int64?,
    model: String
  ) -> [Observation] {
    func clipped(start: Int, end: Int, text: String) -> Observation? {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      let resolvedEnd = end <= start ? start + 60 : end
      guard !trimmed.isEmpty, start < windowEnd, resolvedEnd > windowStart else { return nil }
      let clippedStart = max(start, windowStart)
      return Observation(
        id: nil,
        batchId: batchId ?? -1,
        startTs: clippedStart,
        endTs: max(min(resolvedEnd, windowEnd), clippedStart + 1),
        observation: trimmed,
        metadata: nil,
        llmModel: model,
        createdAt: Date()
      )
    }

    var observations: [Observation] = []
    for card in cards {
      for line in card.detailedSummary.components(separatedBy: .newlines) {
        guard let detail = Self.parseTimelineDetailLine(line),
          let start = Self.timelineEpoch(forClock: detail.start, nearest: windowStart),
          let end = Self.timelineEpoch(forClock: detail.end, nearest: windowStart),
          let observation = clipped(start: start, end: end, text: detail.text)
        else { continue }
        observations.append(observation)
      }
    }

    if observations.isEmpty {
      for card in cards {
        guard let start = Self.timelineEpoch(forClock: card.startTime, nearest: windowStart),
          let end = Self.timelineEpoch(forClock: card.endTime, nearest: windowStart),
          let observation = clipped(start: start, end: end, text: card.title + ": " + card.summary)
        else { continue }
        observations.append(observation)
      }
    }

    return observations.sorted { ($0.startTs, $0.endTs) < ($1.startTs, $1.endTs) }
  }

  private static let timelineDetailLineRegex = try? NSRegularExpression(
    pattern:
      #"^\s*[-•*]?\s*(\d{1,2}:\d{2}\s*[APap][Mm])\s*[-–—]\s*(\d{1,2}:\d{2}\s*[APap][Mm])\s*:?\s*(.+)$"#
  )

  static func parseTimelineDetailLine(_ line: String) -> (start: String, end: String, text: String)?
  {
    guard let regex = timelineDetailLineRegex,
      let match = regex.firstMatch(
        in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
      let start = Range(match.range(at: 1), in: line),
      let end = Range(match.range(at: 2), in: line),
      let text = Range(match.range(at: 3), in: line)
    else { return nil }
    return (String(line[start]), String(line[end]), String(line[text]))
  }

  /// Resolves an "h:mm AM" label to the epoch second nearest the batch, across midnight if needed.
  static func timelineEpoch(
    forClock clock: String, nearest anchor: Int, calendar: Calendar = .current
  ) -> Int? {
    let compact = clock.uppercased().filter { !$0.isWhitespace }
    guard compact.count >= 5 else { return nil }
    let meridiem = compact.suffix(2)
    let parts = compact.dropLast(2).split(separator: ":")
    guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
      (1...12).contains(hour), (0...59).contains(minute), meridiem == "AM" || meridiem == "PM"
    else { return nil }
    let minutesOfDay = (hour % 12 + (meridiem == "PM" ? 12 : 0)) * 60 + minute

    let anchorDate = Date(timeIntervalSince1970: TimeInterval(anchor))
    let midnight = calendar.startOfDay(for: anchorDate)
    let candidates = [-1, 0, 1].compactMap { dayOffset -> Int? in
      guard let day = calendar.date(byAdding: .day, value: dayOffset, to: midnight),
        let date = calendar.date(byAdding: .minute, value: minutesOfDay, to: day)
      else { return nil }
      return Int(date.timeIntervalSince1970)
    }
    return candidates.min { abs($0 - anchor) < abs($1 - anchor) }
  }
}
