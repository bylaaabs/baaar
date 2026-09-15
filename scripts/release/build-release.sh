#!/usr/bin/env bash
# Builds the release baaar.app: Developer ID signed, hardened runtime, timestamped.
#
#   scripts/release/build-release.sh
#
# Writes dist/baaar.app and build/xcodebuild-release.log. Environment:
#   VERSION                   overrides MARKETING_VERSION from project.yml
#   DEVELOPER_ID_APPLICATION  signing identity (default "Developer ID Application";
#                             "-" signs ad-hoc for a local dry run)
#   DERIVED_DATA              build folder, outside the repository (see lib.sh)
#   DIST                      output folder (default dist/)
#
# The build number (CURRENT_PROJECT_VERSION) is the commit count, so it grows
# with every release without anyone editing project.yml.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

need xcodegen "brew install xcodegen"
need xcodebuild "install Xcode 26 or later"

VERSION="$(project_version)"
check_semver "$VERSION"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD)"
ARCHIVE="$DERIVED_DATA/baaar.xcarchive"
APP="$DIST/$APP_NAME.app"
LOG="$ROOT/build/xcodebuild-release.log"

case "$DERIVED_DATA" in
  "$HOME/Desktop"/*|"$ROOT"/*)
    die "DERIVED_DATA=$DERIVED_DATA is under ~/Desktop or the repository; codesign rejects bundles built there" ;;
esac

if [[ "$SIGN_IDENTITY" != "-" ]] \
  && ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  die "no valid identity matching \"$SIGN_IDENTITY\" in the keychain. Set DEVELOPER_ID_APPLICATION to the exact name, or \"-\" for an ad-hoc dry run"
fi

step "baaar $VERSION (build $BUILD_NUMBER), signing as \"$SIGN_IDENTITY\""
cd "$ROOT"
xcodegen generate --quiet
mkdir -p "$ROOT/build" "$DIST"
rm -rf "$ARCHIVE" "$APP"

step "Archiving with Xcode (log: build/xcodebuild-release.log)"
if ! xcodebuild \
  -project baaar.xcodeproj \
  -scheme baaar \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE" \
  archive \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="${OTHER_CODE_SIGN_FLAGS:---timestamp}" \
  > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" >&2 || tail -40 "$LOG" >&2
  die "xcodebuild archive failed"
fi
grep -E "warning:" "$LOG" | grep -v "appintentsmetadataprocessor" | sort -u || true

ARCHIVED_APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
[[ -d "$ARCHIVED_APP" ]] || die "archive has no $APP_NAME.app at $ARCHIVED_APP"

step "Exporting $APP"
# ditto keeps the signature and symlinks intact; --norsrc leaves Finder
# metadata behind so nothing from the source volume travels with the bundle.
ditto --norsrc "$ARCHIVED_APP" "$APP"

step "Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E "^(Authority=|Identifier=|TeamIdentifier=|Timestamp=|Runtime Version=|flags=)" | sed 's/^/    /'
# Captured rather than piped into grep -q: with pipefail, grep closing the pipe early
# kills codesign with SIGPIPE and the whole pipeline reads as a failure.
SIGNATURE="$(codesign --display --verbose=4 "$APP" 2>&1)"
if [[ "$SIGNATURE" != *"flags="*"runtime"* ]]; then
  die "hardened runtime is not enabled on $APP"
fi

note "Gatekeeper (expected to reject until the build is notarized and stapled):"
gatekeeper "$APP"

step "Built $APP"
note "version $(bundle_version "$APP"), build $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
note "dSYMs: $ARCHIVE/dSYMs"
