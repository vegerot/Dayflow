#!/usr/bin/env bash
set -euo pipefail

# Release helper for Dayflow: builds, signs, notarizes, and packages a DMG.
#
# Usage:
#   ./scripts/release_dmg.sh
#
# Optional env vars:
#   SCHEME           - Xcode scheme (default: Dayflow)
#   CONFIG           - Xcode configuration (default: Release)
#   DERIVED_DATA     - Derived data path (default: build)
#   APP_NAME         - App name (default: Dayflow)
#   ENTITLEMENTS     - Entitlements plist path (default: Dayflow/Dayflow/Dayflow.entitlements)
#   SIGN_ID          - Codesign identity (e.g. "Developer ID Application: Your Name (TEAMID)")
#   VOL_NAME         - DMG volume name (defaults to APP_NAME)
#   DMG_NAME         - Output DMG name (defaults to "${APP_NAME}.dmg")
#   NOTARY_PROFILE   - Saved notarytool keychain profile (optional)
#   NOTARY_APPLE_ID  - Apple ID for notarytool (optional)
#   NOTARY_TEAM_ID   - Team ID for notarytool (optional)
#   NOTARY_APP_PASSWORD - App-specific password for Apple ID (optional)
#   ASC_KEY_ID       - App Store Connect API key ID (optional)
#   ASC_ISSUER_ID    - App Store Connect Issuer ID (optional)
#   ASC_P8_PATH      - Path to .p8 private key (optional)

# Load optional per-developer config
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -f "${SCRIPT_DIR}/release.env" ]]; then
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/release.env"
fi

SCHEME=${SCHEME:-Dayflow}
CONFIG=${CONFIG:-Release}
DERIVED_DATA=${DERIVED_DATA:-build}
APP_NAME=${APP_NAME:-Dayflow}
ENTITLEMENTS=${ENTITLEMENTS:-Dayflow/Dayflow/Dayflow.entitlements}
VOL_NAME=${VOL_NAME:-$APP_NAME}
DMG_NAME=${DMG_NAME:-"${APP_NAME}.dmg"}

APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIG}/${APP_NAME}.app"
# Work in a non-iCloud temporary directory to avoid fileprovider xattrs
SANITIZED_DIR=${SANITIZED_DIR:-$(mktemp -d -t dayflow_sign)}
trap 'rm -rf "${SANITIZED_DIR}"' EXIT
SANITIZED_APP="${SANITIZED_DIR}/${APP_NAME}.app"

# Fixed project location inside repo
PROJECT_PATH=${PROJECT_PATH:-Dayflow/Dayflow.xcodeproj}
if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "ERROR: Xcode project not found at $PROJECT_PATH" >&2
  exit 1
fi

echo "[1/7] Building ${APP_NAME} (${SCHEME}|${CONFIG}) using project ${PROJECT_PATH} with code signing disabled…"
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "ERROR: Built app not found at ${APP_PATH}" >&2
  exit 1
fi

echo "[2/7] Determining Developer ID signing identity…"
SIGN_ID=${SIGN_ID:-}
if [[ -z "${SIGN_ID}" ]]; then
  # Try to pick the first available Developer ID Application identity.
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Developer ID Application/ {print $2; exit}') || true
fi
if [[ -z "${SIGN_ID}" ]]; then
  echo "ERROR: No Developer ID Application identity found. Set SIGN_ID env or import certificate." >&2
  security find-identity -v -p codesigning || true
  exit 1
fi
echo "Using signing identity: ${SIGN_ID}"

echo "[3/7] Creating sanitized copy for signing…"
rm -rf "${SANITIZED_DIR}"
mkdir -p "${SANITIZED_DIR}"
# Copy without extended attributes or resource forks
ditto --noextattr --norsrc "${APP_PATH}" "${SANITIZED_APP}"

echo "[4/7] Codesigning app with Hardened Runtime…"
# Ensure any stray metadata is gone
rm -f "${SANITIZED_APP}"/Icon? 2>/dev/null || true
find -L "${SANITIZED_APP}" -name ".DS_Store" -delete || true
if command -v xattr >/dev/null 2>&1; then
  xattr -rc "${SANITIZED_APP}" 2>/dev/null || true
fi
codesign -vvv --force --deep --strict \
  --options runtime \
  --timestamp \
  --entitlements "${ENTITLEMENTS}" \
  --sign "${SIGN_ID}" \
  "${SANITIZED_APP}"

echo "[5/7] Verifying signature…"
codesign --verify --deep --strict --verbose=2 "${SANITIZED_APP}"
spctl -a -vvv --type execute "${SANITIZED_APP}" || true

echo "[6/7] Creating DMG…"
TMP_DIST="${SANITIZED_DIR}/dist"
rm -rf "${TMP_DIST}" "${DMG_NAME}"
mkdir -p "${TMP_DIST}"
# Stage the signed app
ditto --noextattr --norsrc "${SANITIZED_APP}" "${TMP_DIST}/${APP_NAME}.app"
# Add Applications shortcut for drag-and-drop install
ln -s /Applications "${TMP_DIST}/Applications" || true

# Optional pretty layout with background image
if [[ -n "${DMG_BG:-}" && -f "${DMG_BG}" ]]; then
  mkdir -p "${TMP_DIST}/.background"
  BG_NAME="background.png"
  cp "${DMG_BG}" "${TMP_DIST}/.background/${BG_NAME}"

  RW_DMG="${SANITIZED_DIR}/rw.dmg"
  hdiutil create -volname "${VOL_NAME}" -srcfolder "${TMP_DIST}" -ov -fs HFS+ -format UDRW "${RW_DMG}" >/dev/null
  ATTACH_OUT=$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG}")
  DEV=$(echo "$ATTACH_OUT" | awk '/^\/dev\// {print $1; exit}')
  MOUNT=$(echo "$ATTACH_OUT" | awk '/\/Volumes\// {print $3; exit}')
  sleep 1

  DMG_WINDOW_BOUNDS=${DMG_WINDOW_BOUNDS:-"{100, 100, 900, 520}"}
  DMG_ICON_SIZE=${DMG_ICON_SIZE:-128}
  DMG_APP_POS=${DMG_APP_POS:-"{420, 220}"}
  DMG_APPS_POS=${DMG_APPS_POS:-"{140, 220}"}

  osascript <<OSA
tell application "Finder"
  tell disk "${VOL_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to ${DMG_WINDOW_BOUNDS}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to ${DMG_ICON_SIZE}
    set background picture of theViewOptions to file ".background:${BG_NAME}"
    try
      set position of item "${APP_NAME}.app" of container window to ${DMG_APP_POS}
      set position of item "Applications" of container window to ${DMG_APPS_POS}
    end try
    update without registering applications
    delay 1
    close
    open
    delay 1
  end tell
end tell
OSA

  sync
  hdiutil detach "$DEV" -quiet || hdiutil detach "$MOUNT" -quiet || true
  hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_NAME}" >/dev/null
else
  hdiutil create -volname "${VOL_NAME}" -srcfolder "${TMP_DIST}" -ov -format UDZO "${DMG_NAME}"
fi

echo "[7/7] Submitting DMG for notarization…"
NOTARY_ARGS=("${DMG_NAME}")
if [[ "${NO_NOTARIZE:-0}" == "1" ]]; then
  echo "Skipping notarization: NO_NOTARIZE=1"
  NOTARY_ARGS=()
elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Using keychain profile: ${NOTARY_PROFILE}"
  NOTARY_ARGS=(submit "${DMG_NAME}" --keychain-profile "${NOTARY_PROFILE}" --wait)
elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_APP_PASSWORD:-}" ]]; then
  echo "Using Apple ID credentials for notarytool"
  NOTARY_ARGS=(submit "${DMG_NAME}" --apple-id "${NOTARY_APPLE_ID}" --team-id "${NOTARY_TEAM_ID}" --password "${NOTARY_APP_PASSWORD}" --wait)
elif [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_P8_PATH:-}" ]]; then
  echo "Using App Store Connect API key for notarytool"
  NOTARY_ARGS=(submit "${DMG_NAME}" --key "${ASC_P8_PATH}" --key-id "${ASC_KEY_ID}" --issuer "${ASC_ISSUER_ID}" --wait)
else
  echo "Skipping notarization: no credentials provided (set NOTARY_PROFILE or Apple ID or ASC_* env)."
  NOTARY_ARGS=()
fi

if [[ ${#NOTARY_ARGS[@]} -gt 0 ]]; then
  xcrun notarytool "${NOTARY_ARGS[@]}"
  echo "[7/7] Stapling notarization ticket…"
  xcrun stapler staple "${DMG_NAME}"
  xcrun stapler validate "${DMG_NAME}"
else
  echo "NOTE: DMG was NOT notarized. Provide credentials to notarize."
fi

echo "Done. Output: ${DMG_NAME}"
