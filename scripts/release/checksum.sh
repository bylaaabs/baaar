#!/usr/bin/env bash
# Prints SHA-256 checksums for the release files and the Homebrew cask to paste
# into bylaaabs/homebrew-tap/Casks/baaar.rb.
#
#   scripts/release/checksum.sh [version]
#
# The version defaults to MARKETING_VERSION in project.yml (or VERSION=). The
# cask downloads the zip, as the other laaabs. casks do, and passes brew style
# ("desc" must not name the platform, auto_updates goes before depends_on).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VERSION="${1:-$(project_version)}"
check_semver "$VERSION"
DMG="$DIST/$APP_NAME-v$VERSION.dmg"
ZIP="$DIST/$APP_NAME-v$VERSION.zip"
for f in "$DMG" "$ZIP"; do
  [[ -f "$f" ]] || die "$f not found; run scripts/release/make-dmg.sh first"
done

sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
DMG_SHA="$(sha "$DMG")"
ZIP_SHA="$(sha "$ZIP")"

cat <<EOF
SHA-256
$DMG_SHA  $(basename "$DMG")
$ZIP_SHA  $(basename "$ZIP")

Homebrew cask: bylaaabs/homebrew-tap/Casks/baaar.rb
----------------------------------------------------------------------
cask "baaar" do
  version "$VERSION"
  sha256 "$ZIP_SHA"

  url "https://github.com/$REPO_SLUG/releases/download/v#{version}/baaar-v#{version}.zip",
      verified: "github.com/$REPO_SLUG/"
  name "baaar"
  desc "Native menu bar manager"
  homepage "https://github.com/$REPO_SLUG"

  # No Sparkle yet: brew upgrade is the only update path.
  auto_updates false
  # baaar runs on macOS 27 only. Homebrew 7.0 names it :golden_gate, which
  # parses as ">= 27"; older Homebrew does not know the symbol.
  depends_on macos: :golden_gate

  app "baaar.app"

  zap trash: [
    "~/Library/Caches/$BUNDLE_ID",
    "~/Library/Logs/baaar",
    "~/Library/Preferences/$BUNDLE_ID.plist",
    "~/Library/Saved Application State/$BUNDLE_ID.savedState",
  ]
end
----------------------------------------------------------------------
EOF
