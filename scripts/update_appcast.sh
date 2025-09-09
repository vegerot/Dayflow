#!/usr/bin/env bash
set -euo pipefail

# Prepend a new item to an existing Sparkle appcast.xml (or create one if missing).
# Inputs mirror make_appcast.sh but this script preserves prior items.
#
# Usage:
#   scripts/update_appcast.sh \
#     --dmg Dayflow.dmg \
#     --url https://github.com/you/repo/releases/download/v1.2.3/Dayflow.dmg \
#     --short 1.2.3 \
#     --build 123 \
#     --signature <BASE64_EDDSA_SIG> \
#     [--msv 13.0] \
#     [--notes https://github.com/you/repo/releases/tag/v1.2.3] \
#     [--out docs/appcast.xml]

DMG=""
URL=""
SHORT_VER=""
BUILD_VER=""
SIG=""
MSV=""
NOTES_LINK=""
OUT="docs/appcast.xml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg) DMG="$2"; shift 2 ;;
    --url) URL="$2"; shift 2 ;;
    --short) SHORT_VER="$2"; shift 2 ;;
    --build) BUILD_VER="$2"; shift 2 ;;
    --signature) SIG="$2"; shift 2 ;;
    --msv) MSV="$2"; shift 2 ;;
    --notes) NOTES_LINK="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$DMG" || -z "$URL" || -z "$SHORT_VER" || -z "$BUILD_VER" || -z "$SIG" ]]; then
  echo "Missing required args. See script header for usage." >&2
  exit 1
fi

if [[ ! -f "$DMG" ]]; then
  echo "DMG not found: $DMG" >&2
  exit 1
fi

LEN=$(stat -f%z "$DMG" 2>/dev/null || wc -c <"$DMG")
DATE_RFC=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S %z")

TITLE="Dayflow Updates"
LANG="en"

mkdir -p "$(dirname "$OUT")"

TMP_NEW=$(mktemp -t appcast_new_XXXX.xml)
trap 'rm -f "$TMP_NEW"' EXIT

cat > "$TMP_NEW" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>${TITLE}</title>
    <language>${LANG}</language>
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
$( if [[ -n "$NOTES_LINK" ]]; then echo "      <releaseNotesLink>${NOTES_LINK}</releaseNotesLink>"; fi )
    </item>
XML

if [[ -f "$OUT" ]]; then
  # Append existing <item> blocks from the current appcast
  awk '/<item>/,/<\/item>/' "$OUT" >> "$TMP_NEW" || true
fi

cat >> "$TMP_NEW" <<XML
  </channel>
  </rss>
XML

mv "$TMP_NEW" "$OUT"

# Make sure GitHub Pages serves files as-is (no Jekyll)
OUT_DIR=$(dirname "$OUT")
if [[ "$OUT_DIR" == *"docs"* ]]; then
  touch "$OUT_DIR/.nojekyll"
fi

echo "Updated appcast: $OUT"

