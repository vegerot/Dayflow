import Foundation

struct OllamaPromptOverrides: Codable, Equatable {
    var summaryBlock: String?
    var titleBlock: String?

    var isEmpty: Bool {
        [summaryBlock, titleBlock].allSatisfy { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty
        }
    }
}

enum OllamaPromptPreferences {
    private static let overridesKey = "ollamaPromptOverrides"
    private static let store = UserDefaults.standard

    static func load() -> OllamaPromptOverrides {
        guard let data = store.data(forKey: overridesKey) else {
            return OllamaPromptOverrides()
        }
        guard let overrides = try? JSONDecoder().decode(OllamaPromptOverrides.self, from: data) else {
            return OllamaPromptOverrides()
        }
        return overrides
    }

    static func save(_ overrides: OllamaPromptOverrides) {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        store.set(data, forKey: overridesKey)
    }

    static func reset() {
        store.removeObject(forKey: overridesKey)
    }
}

enum OllamaPromptDefaults {
    static let summaryBlock = """
          SUMMARY GUIDELINES:
          - Write in first person without using "I" (like a personal journal entry)
          - 2-3 sentences maximum
          - Include specific details (app names, search topics, etc.)
          - Natural, conversational tone

          GOOD EXAMPLES:
          "Managed Mac system preferences focusing on software updates and accessibility settings. Browsed Chrome searching for iPhone wireless charging info while
          checking Twitter and Slack messages."

          "Configured GitHub Actions pipeline for automated testing. Quick Slack check interrupted focus, then back to debugging deployment issues."

          "Researched React performance optimization techniques in Chrome, reading articles about useMemo patterns. Switched between documentation tabs and took notes in
           Notion about component re-rendering."

          "Updated Xcode project dependencies and resolved build errors in SwiftUI views. Tested app on simulator while responding to client messages about timeline
          changes."

          "Browsed Instagram and TikTok while listening to Spotify playlist. Responded to personal messages on WhatsApp about weekend plans."

          "Researched vacation destinations on travel websites and compared flight prices. Checked weather forecasts for different cities while reading travel reviews."

          BAD EXAMPLES:
          - "The user did various computer activities" (too vague, wrong perspective, never say the user)
          - "I was working on my computer doing different tasks" (uses "I", not specific)
          - "Spent time on multiple applications and websites" (generic, no details)
    """

    static let titleBlock = """
        TITLE GUIDELINES:
        Write like you're texting a friend. Keep it conversational and within 5-8 words (lean short).
        Focus on ONE standout activity; you may mention one other equally dominant action, but phrase it as a quick "and/while" or dash connection (never a comma list).
        Lead with an active verb or app + action, and include at most one supporting detail (app, medium, or topic). If you mention two activities, make it clear they both mattered without sounding like a checklist.
        Describe what you were doing with the app/site; never just list tool names or open windows.
        ⚠️ ONLY use details that exist in the summary — never invent context.

        GOOD EXAMPLES:
        "Debugged auth flow in VS Code"
        "YouTube rabbit hole on gaming drama"
        "Reviewing Figma designs"
        "Slack catching up during deploy wait"
        "Tweaked React hooks for dashboard"

        BAD EXAMPLES (with explanations):

        ✗ "React coded, games streamed, tweets checked"
          WHY BAD: Lists three different activities; no focus or clear takeaway.

        ✗ "User engaging in video calls, software updates, and browsing system preferences"
          WHY BAD: Too long (11 words), formal "engaging", says "User" instead of natural first-person

        ✗ "Browsing and Browsing, Responding to Slack"
          WHY BAD: Repetitive "Browsing and Browsing", unclear what was browsed, awkward phrasing

        ✗ "(Debugging & Coding) User's Time Spans"
          WHY BAD: Weird parentheses format, formal "Time Spans", says "User's" instead of natural language

        ✗ "Working on computer tasks and applications"
          WHY BAD: Completely generic, "working on" is lazy, could describe any computer use
        ✗ "GitHub Desktop + terminal logs"
          WHY BAD: Only lists tools; doesn't explain the action or intent
    """
}

struct OllamaPromptSections {
    let summary: String
    let title: String

    init(overrides: OllamaPromptOverrides) {
        self.summary = OllamaPromptSections.compose(defaultBlock: OllamaPromptDefaults.summaryBlock, custom: overrides.summaryBlock)
        self.title = OllamaPromptSections.compose(defaultBlock: OllamaPromptDefaults.titleBlock, custom: overrides.titleBlock)
    }

    private static func compose(defaultBlock: String, custom: String?) -> String {
        let trimmed = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultBlock : trimmed
    }
}
