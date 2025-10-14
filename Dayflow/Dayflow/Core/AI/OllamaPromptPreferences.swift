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
        Write like you're texting a friend about what you did today. Keep it 5-8 words maximum.
        Be specific about what you actually did, not generic descriptions.
        ⚠️ ONLY use details that exist in the summary - don't add information that wasn't mentioned.

        GOOD EXAMPLES:
        "Fixed CORS bugs in API endpoints"
        "Mac settings while researching chargers"
        "Wrote docs, kept checking Twitter"
        "iPhone wireless charging research session"
        "Debugged auth flow, tested endpoints"
        "Reddit rabbit hole about React patterns"

        BAD EXAMPLES (with explanations):

        ✗ "User engaging in video calls, software updates, and browsing system preferences"
          WHY BAD: Too long (11 words), formal "engaging", says "User" instead of natural first-person

        ✗ "Browsing and Browsing, Responding to Slack"
          WHY BAD: Repetitive "Browsing and Browsing", unclear what was browsed, awkward phrasing

        ✗ "Browsing social media and coding project updates"
          WHY BAD: Generic "browsing social media", vague "project updates", doesn't match actual activity

        ✗ "(Debugging & Coding) User's Time Spans"
          WHY BAD: Weird parentheses format, formal "Time Spans", says "User's" instead of natural language

        ✗ "User Engages in Social Media Activities"
          WHY BAD: Formal corporate speak ("engages", "activities"), says "User", too generic

        ✗ "Working on computer tasks and applications"
          WHY BAD: Completely generic, "working on" is lazy, could describe any computer use
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
