# Dayflow

Dayflow is a macOS application that records the user's screen, analyzes the footage with the Gemini API, and displays a timeline of activities. Recordings are split into chunks, grouped into analysis batches, and processed in the background. A debug interface lets developers inspect each batch.

## Building
Open `Dayflow.xcodeproj` with Xcode 15 or later. The project targets macOS and uses SwiftUI.

## Debug View
Select **Debug** from the top segmented control to review analysis batches. The view lets you play back the batch video, inspect the generated timeline cards, and review details of every LLM call made during processing.
