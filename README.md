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

## Sparkle Updates

Sparkle is integrated via Swift Package Manager. We expose a small Settings block that shows the current version and a "Check for updates" action; the updater auto-checks daily and auto-downloads updates in the background.

What you must set up once:
- Generate an Ed25519 keypair with Sparkle’s `generate_keys` and put the public key into `Dayflow/Dayflow/Info.plist` under `SUPublicEDKey`.
- Decide where to host the appcast (recommend GitHub Pages or `docs/appcast.xml` on the default branch) and set `SUFeedURL` accordingly.

Key management tips:
- Store the private key PEM in macOS Keychain as a Generic Password so you don’t keep a file around:
  - `security add-generic-password -a $USER -s com.dayflow.sparkle.ed25519 -w "$(cat /path/to/ed25519_private.pem)" -U`
  - Then sign releases with: `./scripts/sparkle_sign_from_keychain.sh Dayflow.dmg com.dayflow.sparkle.ed25519`

Simple release flow (manual):
1) Build/sign/notarize the DMG:
   - `./scripts/release_dmg.sh` → outputs `Dayflow.dmg`.
2) Sign the DMG with Sparkle to get the EdDSA signature:
   - `sign_update Dayflow.dmg` (from Sparkle’s distribution tools). Copy the `edSignature` value.
3) Publish a GitHub Release and upload `Dayflow.dmg`. Copy the direct asset URL (the `…/releases/download/vX.Y.Z/Dayflow.dmg` link).
4) Generate/update the appcast:
   - `./scripts/make_appcast.sh --dmg Dayflow.dmg --url <asset-url> --short <shortVersion> --build <build> --signature <base64-sig> --msv 13.0 --out build/appcast.xml`
- Commit/push the appcast to your chosen location (e.g. `docs/appcast.xml`).

## One-Button Release

Run a single command to bump version, build/sign, publish the Release, and prepend the appcast entry.

Usage:
- Default (bumps minor): `./scripts/release.sh`
- Major bump: `./scripts/release.sh --major`
- Patch bump: `./scripts/release.sh --patch`
- Dry run: `./scripts/release.sh --dry-run`

What it does:
- Reads current `CFBundleShortVersionString`/`CFBundleVersion` from `Dayflow/Dayflow/Info.plist`.
- Bumps version (minor by default) and build (+1) and commits.
- Builds, signs, and optionally notarizes via `scripts/release_dmg.sh`.
- Signs the DMG using Sparkle’s `sign_update`:
  - Default: reads your private key from login Keychain (account `ed25519`).
  - CI fallback: set `SPARKLE_PRIVATE_KEY` (base64 secret exported by `generate_keys -x`).
- Creates a draft GitHub Release and uploads the DMG via `gh`.
- Prepends a new `<item>` to `docs/appcast.xml` via `scripts/update_appcast.sh`, commits, pushes, and then undrafts the Release.

Prereqs:
- `gh` CLI authenticated (`gh auth status`).
- Sparkle CLI tools installed (`sign_update`).
- Private key generated with Sparkle `generate_keys` in your login Keychain (default account `ed25519`).
- GitHub Pages enabled for `docs/`.
- `SUFeedURL` points to `https://dayflow.so/appcast.xml` (Webflow redirects to Pages).

Decisions to make:
- Feed hosting: GitHub Pages (`https://<user>.github.io/<repo>/appcast.xml`) or raw file in repo (`https://raw.githubusercontent.com/<org>/<repo>/main/docs/appcast.xml`).
- Channels: a single stable feed now; add a separate beta feed later if desired.
- Frequency: default daily checks; change in `UpdaterManager` if you want more/less.
- Install behavior: we default to auto-download; to auto-install without prompts, implement a custom Sparkle user driver.
