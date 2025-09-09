#!/usr/bin/env bash
set -euo pipefail

# Sign an update archive with Sparkle using a private key stored in macOS Keychain
# as a Generic Password whose secret value is the PEM contents of the
# Ed25519 private key (output of Sparkle's generate_keys).
#
# Usage:
#   scripts/sparkle_sign_from_keychain.sh <archive> [service-name]
#
# Example:
#   scripts/sparkle_sign_from_keychain.sh Dayflow.dmg com.dayflow.sparkle.ed25519
#
# Requirements: Sparkle's `sign_update` must be in PATH.

ARCHIVE=${1:?"Usage: $0 <archive> [service-name]"}
SERVICE=${2:-com.dayflow.sparkle.ed25519}

if ! command -v sign_update >/dev/null 2>&1; then
  echo "ERROR: sign_update not found in PATH. Install Sparkle's Command Line Tools." >&2
  exit 1
fi

TMP=$(mktemp -t sparkle_priv_XXXXXX)
trap 'rm -f "$TMP"' EXIT

# Fetch the PEM content from keychain
if ! security find-generic-password -s "$SERVICE" -w > "$TMP" 2>/dev/null; then
  echo "ERROR: Could not find Keychain item with service '$SERVICE'." >&2
  echo "Create one with: security add-generic-password -a $USER -s $SERVICE -w \"\$(cat path/to/ed25519_private.pem)\" -U" >&2
  exit 1
fi

if ! grep -q "BEGIN PRIVATE KEY" "$TMP"; then
  echo "ERROR: Keychain secret doesn't look like a PEM private key (missing BEGIN PRIVATE KEY)." >&2
  exit 1
fi

echo "Signing $ARCHIVE using Keychain item '$SERVICE'…" >&2
sign_update --ed25519-private-key-file "$TMP" "$ARCHIVE"

