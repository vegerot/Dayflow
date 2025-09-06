# Dayflow

Dayflow is a macOS application that records the user's screen, analyzes the footage with the Gemini API, and displays a timeline of activities. Recordings are split into chunks, grouped into analysis batches, and processed in the background. A debug interface lets developers inspect each batch.

## Building
Open `Dayflow.xcodeproj` with Xcode 15 or later. The project targets macOS and uses SwiftUI.

## Debug View
Select **Debug** from the top segmented control to review analysis batches. The view lets you play back the full batch video and expand individual timeline cards to see their summaries. If a card or its distractions include a video summary, it is displayed inline. The Debug view also lists every LLM call for the batch showing the full request and response with JSON prettified when possible.

## Distribution (DMG signing + notarization)

We include a script and CI workflow to build, sign, notarize, and package a DMG.

- Local script: `scripts/release_dmg.sh`
  - Requires Xcode and a Developer ID Application certificate in your login keychain.
  - Optional: set up `notarytool store-credentials` once, then export `NOTARY_PROFILE` or pass Apple ID credentials via env.
  - Run: `chmod +x scripts/release_dmg.sh && ./scripts/release_dmg.sh`
  - Output: `Dayflow.dmg` (stapled if notarization credentials provided)
  - Persistent config: copy `scripts/release.env.example` → `scripts/release.env` and set `SIGN_ID`/`NOTARY_PROFILE` so you don’t need to export env vars each run.

Notes:
- Hardened Runtime is applied during codesigning by the script.
- The app’s entitlements are in `Dayflow/Dayflow/Dayflow.entitlements`.
