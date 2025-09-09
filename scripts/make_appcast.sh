#!/usr/bin/env bash
set -euo pipefail

# Generate a minimal Sparkle appcast.xml with one <item>.
# This expects you to supply the EdDSA signature (from Sparkle's sign_update),
# a direct download URL (e.g. a GitHub Releases asset URL), and the versioning.
#
# Usage:
#   scripts/make_appcast.sh \
#     --dmg Dayflow.dmg \
#     --url https://github.com/you/repo/releases/download/v1.2.3/Dayflow.dmg \
#     --short 1.2.3 \
#     --build 123 \
#     --signature <BASE64_EDDSA_SIG> \
#     [--msv 13.0] \
#     [--notes https://github.com/you/repo/releases/tag/v1.2.3] \
#     [--out build/appcast.xml]

DMG=""
URL=""
SHORT_VER=""
BUILD_VER=""
SIG=""
MSV=""
NOTES=""
OUT="build/appcast.xml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg) DMG="$2"; shift 2 ;;
    --url) URL="$2"; shift 2 ;;
    --short) SHORT_VER="$2"; shift 2 ;;
    --build) BUILD_VER="$2"; shift 2 ;;
    --signature) SIG="$2"; shift 2 ;;
    --msv) MSV="$2"; shift 2 ;;
    --notes) NOTES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$DMG" || -z "$URL" || -z "$SHORT_VER" || -z "$BUILD_VER" || -z "$SIG" ]]; then
  echo "Missing required args. Run with --dmg --url --short --build --signature" >&2
  exit 1
fi

if [[ ! -f "$DMG" ]]; then
  echo "DMG not found: $DMG" >&2
  exit 1
fi

LEN=$(stat -f%z "$DMG" 2>/dev/null || wc -c <"$DMG")
DATE_RFC=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S %z")

mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Dayflow Updates</title>
    <language>en</language>
    <item>
      <title>Version ${SHORT_VER}</title>
      <pubDate>${DATE_RFC}</pubDate>
      <enclosure url="${URL}"
                 sparkle:version="${BUILD_VER}"
                 sparkle:shortVersionString="${SHORT_VER}"
                 length="${LEN}"
                 type="application/octet-stream"
                 sparkle:edSignature="${SIG}"/>
$( if [[ -n "$MSV" ]]; then echo "      <sparkle:minimumSystemVersion>${MSV}</sparkle:minimumSystemVersion>"; fi )
$( if [[ -n "$NOTES" ]]; then echo "      <releaseNotesLink>${NOTES}</releaseNotesLink>"; fi )
    </item>
  </channel>
  </rss>
XML

echo "Wrote appcast: $OUT"

