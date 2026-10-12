#!/bin/bash
#
# release.sh — archive, sign, export, and (optionally) notarize Ghostwriter.
#
# This script stores no personal data (no team IDs, names, or Apple IDs).
# Values are auto-detected from the local keychain or provided via
# environment variables:
#
#   EXPORT_METHOD   Export method. Default: developer-id (distribution
#                   outside the App Store). Use "development" to produce a
#                   locally-runnable .app when no Developer ID certificate
#                   is installed.
#   TEAM_ID         Apple Developer team ID. Auto-detected from the matching
#                   signing certificate when omitted.
#   NOTARY_PROFILE  Keychain notary profile. When set, the exported app is
#                   zipped, notarized, and stapled. One-time setup:
#                     xcrun notarytool store-credentials NOTARY_PROFILE \
#                       --apple-id <apple-id> --team-id <team> \
#                       --password <app-specific-password>
#   CONFIGURATION   Build configuration. Default: Release.
#
set -euo pipefail

SCHEME="${SCHEME:-ghostwriter}"
CONFIGURATION="${CONFIGURATION:-Release}"
EXPORT_METHOD="${EXPORT_METHOD:-developer-id}"
TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ghostwriter.xcodeproj"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
ZIP_PATH=""

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found in PATH"
[[ -d "$PROJECT_PATH" ]] || die "project not found at $PROJECT_PATH"

case "$EXPORT_METHOD" in
  developer-id)
    security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application" \
      || die "no 'Developer ID Application' certificate installed for developer-id export.
       Join the Apple Developer Program and create one, or build a locally-runnable
       app instead:  EXPORT_METHOD=development $0"
    ;;
  development | app-store) ;;
  *) die "unsupported EXPORT_METHOD '$EXPORT_METHOD' (use developer-id, development, or app-store)" ;;
esac

# The team ID lives in the certificate's organizational unit (OU).
detect_team_id() {
  local cert_name
  case "$EXPORT_METHOD" in
    developer-id) cert_name="Developer ID Application" ;;
    *) cert_name="Apple Development" ;;
  esac
  security find-certificate -c "$cert_name" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU=\([A-Z0-9]\{10\}\).*/\1/p'
}

if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID="$(detect_team_id || true)"
fi

# Newer Xcode versions renamed the plist value for development-signed exports.
EXPORT_METHOD_PLIST="$EXPORT_METHOD"
if [[ "$EXPORT_METHOD" == "development" ]]; then
  EXPORT_METHOD_PLIST="debugging"
fi

# ---------------------------------------------------------------------------
# Archive
# ---------------------------------------------------------------------------
say "Archiving $SCHEME ($CONFIGURATION) → $ARCHIVE_PATH"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -quiet \
  archive

# ---------------------------------------------------------------------------
# Export (exportOptions.plist is generated here so the repo stays clean)
# ---------------------------------------------------------------------------
say "Exporting signed app (method: $EXPORT_METHOD, team: ${TEAM_ID:-auto})"
OPTIONS_PLIST="$BUILD_DIR/exportOptions.plist"
TEAM_XML=""
if [[ -n "$TEAM_ID" ]]; then
  TEAM_XML="$(printf '\n\t<key>teamID</key>\n\t<string>%s</string>' "$TEAM_ID")"
fi
cat > "$OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>$EXPORT_METHOD_PLIST</string>
	<key>signingStyle</key>
	<string>automatic</string>$TEAM_XML
</dict>
</plist>
EOF

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$OPTIONS_PLIST" \
  -quiet

APP_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.app' -print -quit)"
[[ -n "$APP_PATH" ]] || die "export finished but no .app was produced in $EXPORT_DIR"

say "Code signature"
codesign -dv "$APP_PATH" 2>&1 | grep -E "Authority=|TeamIdentifier=" || true

# ---------------------------------------------------------------------------
# Notarize (optional)
# ---------------------------------------------------------------------------
if [[ -n "$NOTARY_PROFILE" ]]; then
  say "Notarizing with profile '$NOTARY_PROFILE'"
  ZIP_PATH="${APP_PATH%.app}.zip"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  say "Stapled notarization ticket to app bundle"
else
  say "Skipping notarization (set NOTARY_PROFILE to enable)"
fi

say "Done — artifacts"
echo "  .app:    $APP_PATH"
if [[ -n "$ZIP_PATH" ]]; then
  echo "  .zip:    $ZIP_PATH"
fi
echo "  archive: $ARCHIVE_PATH"
