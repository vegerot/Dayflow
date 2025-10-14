import Foundation

struct GeminiPromptOverrides: Codable, Equatable {
    var titleBlock: String?
    var summaryBlock: String?
    var detailedBlock: String?

    var isEmpty: Bool {
        let values = [titleBlock, summaryBlock, detailedBlock]
        return values.allSatisfy { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty
        }
    }
}

enum GeminiPromptPreferences {
    private static let overridesKey = "geminiPromptOverrides"
    private static let store = UserDefaults.standard

    static func load() -> GeminiPromptOverrides {
        guard let data = store.data(forKey: overridesKey) else {
            return GeminiPromptOverrides()
        }
        guard let overrides = try? JSONDecoder().decode(GeminiPromptOverrides.self, from: data) else {
            return GeminiPromptOverrides()
        }
        return overrides
    }

    static func save(_ overrides: GeminiPromptOverrides) {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        store.set(data, forKey: overridesKey)
    }

    static func reset() {
        store.removeObject(forKey: overridesKey)
    }
}

enum GeminiPromptDefaults {
    static let titleBlock = """
Title guidelines:
Write titles like you're texting a friend about what you did. Natural, conversational, direct, specific.

Rules:
- Be specific and clear (not creative or vague)
- Keep it short - aim for 5-10 words
- Don't reference other cards or assume context
- Include main activity + distraction if relevant
- Include specific app/tool names, not generic activities
- Use specific verbs: "Debugged Python" not "Worked on project"

Good examples:
- "Debugged auth flow in React"
- "Excel budget analysis for Q4 report"
- "Zoom call with design team"
- "Booked flights on Expedia for Denver trip"
- "Watched Succession finale on HBO"
- "Grocery list and meal prep research"
- "Reddit rabbit hole about conspiracy theories"
- "Random YouTube shorts for 30 minutes"
- "Instagram reels and Twitter scrolling"

Bad examples:
- "Early morning digital drift" (too vague/poetic)
- "Fell down a rabbit hole after lunch" (too long, assumes context)
- "Extended Browsing Session" (too formal)
- "Random browsing and activities" (not specific)
- "Continuing from earlier" (references other cards)
- "Worked on DayFlow project" (too generic - what specifically?)
- "Browsed social media and shopped" (which platforms? for what?)
- "Refined UI and prompts" (which tools? what UI?)
"""

    static let summaryBlock = """
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
"""

    static let detailedSummaryBlock = """
Detailed Summary guidelines:
The detailedSummary field must provide a minute-by-minute timeline of activities within the card's duration. This is a granular activity log showing every context switch and time spent.

Format rules:
- Use exact time ranges in "H:MM AM/PM - H:MM AM/PM" format
- One activity per line
- Keep descriptions short and specific (2-5 words typical)
- Include app/tool names
- Show ALL context switches, even brief ones
- Order chronologically
- No narrative text, just the timeline

Structure:
"[startTime] - [endTime] [specific activity in tool/app]"

Examples of good detailedSummary format:
"7:00 AM - 7:30 AM writing notion doc
7:30 AM - 7:35 AM responding to slack DMs
7:35 AM - 7:38 AM scrolling x.com
7:38 AM - 7:45 AM writing notion doc
7:45 AM - 8:05 AM coding in Cursor and iterm
8:05 AM - 8:08 AM checking gmail
8:08 AM - 8:25 AM debugging in VS Code
8:25 AM - 8:30 AM Stack Overflow research"

"2:15 PM - 2:18 PM opened Figma
2:18 PM - 2:45 PM designing landing page mockups
2:45 PM - 2:47 PM quick Twitter check
2:47 PM - 3:10 PM continued Figma designs
3:10 PM - 3:15 PM exporting assets
3:15 PM - 3:30 PM implementing in Next.js"

Bad examples (DO NOT DO):
- "Worked on various tasks throughout the session" (not granular)
- "Started with email, then moved to coding" (narrative, not timeline)
- "15 minutes on email, 30 minutes coding" (duration-based, not time-based)
- Missing specific times or tools
"""
}

struct GeminiPromptSections {
    let title: String
    let summary: String
    let detailedSummary: String

    init(overrides: GeminiPromptOverrides) {
        self.title = GeminiPromptSections.compose(defaultBlock: GeminiPromptDefaults.titleBlock, custom: overrides.titleBlock)
        self.summary = GeminiPromptSections.compose(defaultBlock: GeminiPromptDefaults.summaryBlock, custom: overrides.summaryBlock)
        self.detailedSummary = GeminiPromptSections.compose(defaultBlock: GeminiPromptDefaults.detailedSummaryBlock, custom: overrides.detailedBlock)
    }

    private static func compose(defaultBlock: String, custom: String?) -> String {
        let trimmed = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultBlock : trimmed
    }
}
