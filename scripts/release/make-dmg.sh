#!/usr/bin/env bash
# Packages a built baaar.app as a signed DMG and a zip.
#
#   scripts/release/make-dmg.sh [path/to/baaar.app]
#
# Writes dist/baaar-v<version>.dmg (620 x 420 window, background from
# Resources/dmg-background.png, baaar.app on the left, an Applications alias on
# the right) and dist/baaar-v<version>.zip (for Homebrew, and Sparkle later).
# The version is read from the bundle; VERSION= overrides it. Signing uses the
# same identity as build-release.sh (DEVELOPER_ID_APPLICATION, "-" for ad-hoc).
#
# Finder arranges the icons through AppleScript. When that is not possible
# (no Finder automation permission, a headless session) the DMG still ships,
# with a plain layout and the same Applications alias.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP="${1:-$DIST/$APP_NAME.app}"
[[ -d "$APP" ]] || die "$APP not found; run scripts/release/build-release.sh first"
VERSION="${VERSION:-$(bundle_version "$APP")}"
[[ -n "$VERSION" ]] || die "could not read CFBundleShortVersionString from $APP"
check_semver "$VERSION"

BACKGROUND="$ROOT/Resources/dmg-background.png"
[[ -f "$BACKGROUND" ]] || die "$BACKGROUND missing; run: swift scripts/render-dmg-background.swift"

VOLUME="$APP_NAME $VERSION"
DMG="$DIST/$APP_NAME-v$VERSION.dmg"
ZIP="$DIST/$APP_NAME-v$VERSION.zip"
mkdir -p "$DIST"

# Everything temporary lives outside the repository (and outside ~/Desktop).
WORK="$(mktemp -d "${TMPDIR:-/tmp}/baaar-dmg.XXXXXX")"
STAGE="$WORK/stage"
RW_DMG="$WORK/rw.dmg"
DEVICE=""
cleanup() {
  if [[ -n "$DEVICE" ]]; then hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# A volume with the same name left over from an earlier run would make
# Finder address the wrong window.
if [[ -d "/Volumes/$VOLUME" ]]; then
  step "Detaching a stale /Volumes/$VOLUME"
  hdiutil detach "/Volumes/$VOLUME" -force >/dev/null 2>&1 || die "could not detach /Volumes/$VOLUME; eject it and retry"
fi

step "Staging $VOLUME"
mkdir -p "$STAGE/.background"
ditto --norsrc "$APP" "$STAGE/$APP_NAME.app"
xattr -cr "$STAGE/$APP_NAME.app"
codesign --verify --deep --strict "$STAGE/$APP_NAME.app" || die "the staged bundle no longer verifies"
cp "$BACKGROUND" "$STAGE/.background/background.png"
ln -s /Applications "$STAGE/Applications"

step "Creating a writable image"
rm -f "$DMG" "$RW_DMG"
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGE" -fs APFS -format UDRW -ov "$RW_DMG"

step "Arranging the window"
# Not -nobrowse: Finder only scripts volumes it can see. macOS 27 marks
# hdiutil attach as deprecated in favour of diskutil image attach; it still
# works everywhere the release runs, so the notice is filtered out.
ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" 2>"$WORK/attach.err")" || true
grep -v "deprecated" "$WORK/attach.err" >&2 || true
DEVICE="$(printf '%s\n' "$ATTACH_OUT" | awk '/^\/dev\// {print $1; exit}')"
MOUNT="$(printf '%s\n' "$ATTACH_OUT" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"
[[ -n "$DEVICE" && -d "$MOUNT" ]] || die "could not attach $RW_DMG"

# Coordinates are icon centres from the top left of the content area and
# must match scripts/render-dmg-background.swift.
LAYOUT_OK=1
if ! osascript >/dev/null 2>"$WORK/osascript.err" <<EOF
tell application "Finder"
  tell disk "$VOLUME"
    open
    set theWindow to container window
    set current view of theWindow to icon view
    set toolbar visible of theWindow to false
    set statusbar visible of theWindow to false
    set pathbar visible of theWindow to false
    set bounds of theWindow to {200, 120, 820, 540}
    set theOptions to icon view options of theWindow
    set arrangement of theOptions to not arranged
    set icon size of theOptions to 128
    set text size of theOptions to 12
    set background picture of theOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" to {170, 220}
    set position of item "Applications" to {450, 220}
    update without registering applications
    delay 1
    close theWindow
  end tell
end tell
EOF
then
  LAYOUT_OK=0
  warn "Finder could not arrange the window; shipping a plain layout"
  sed 's/^/    /' "$WORK/osascript.err" >&2 || true
fi

# Finder writes .DS_Store lazily. Give it a moment, then hide the background
# folder and make sure everything is on disk before detaching.
sleep 2
SetFile -a V "$MOUNT/.background" 2>/dev/null || chflags hidden "$MOUNT/.background" 2>/dev/null || true
rm -rf "$MOUNT/.fseventsd" "$MOUNT/.Trashes" 2>/dev/null || true
sync
hdiutil detach "$DEVICE" -quiet || { sleep 2; hdiutil detach "$DEVICE" -force -quiet; }
DEVICE=""

step "Compressing $DMG"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"

step "Signing the DMG as \"$SIGN_IDENTITY\""
codesign "${SIGN_ARGS[@]}" --force "$DMG"
codesign --verify --verbose=2 "$DMG"
note "Gatekeeper (expected to reject until notarized and stapled):"
gatekeeper "$DMG" open

step "Zipping $ZIP"
rm -f "$ZIP"
ditto -c -k --keepParent --norsrc "$STAGE/$APP_NAME.app" "$ZIP"

step "Done"
note "$DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
note "$ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
[[ $LAYOUT_OK -eq 1 ]] || note "the window layout was not applied; open the DMG and check it before shipping"
