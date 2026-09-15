#!/usr/bin/env bash
# Shared pieces for scripts/release/*. Source it, do not run it.
#
# Every release script agrees on these:
#   ROOT           the repository
#   DIST           where shippable files land (dist/, ignored by git)
#   DERIVED_DATA   Xcode's build folder, outside the repository. Files under
#                  ~/Desktop carry extended attributes that make codesign
#                  reject a bundle, so never point it back inside the repo.
#   SIGN_IDENTITY  the Developer ID Application identity; "-" means ad-hoc,
#                  which is only good for a local dry run.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST="${DIST:-$ROOT/dist}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/baaar-release}"
SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-Developer ID Application}"
APP_NAME="baaar"
BUNDLE_ID="com.laaabs.baaar"
REPO_SLUG="bylaaabs/baaar"

step() { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is not installed${2:+ ($2)}"
}

# MARKETING_VERSION from project.yml, unless VERSION is already set.
project_version() {
  if [[ -n "${VERSION:-}" ]]; then
    printf '%s\n' "$VERSION"
    return
  fi
  local v
  v="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([^"[:space:]]*\)"\{0,1\}.*/\1/p' "$ROOT/project.yml" | head -1)"
  [[ -n "$v" ]] || die "MARKETING_VERSION not found in project.yml (set VERSION= to override)"
  printf '%s\n' "$v"
}

# CFBundleShortVersionString of a built bundle.
bundle_version() {
  local plist="$1/Contents/Info.plist"
  [[ -f "$plist" ]] || die "$plist not found; is $1 a bundle?"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null
}

# SemVer with an optional pre-release: 0.4.0, 0.4.0-alpha.1, 1.2.3-rc.2.
check_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]] \
    || die "'$1' is not a version like 0.4.0 or 0.4.0-alpha.1"
}

is_prerelease() {
  [[ "$1" =~ (alpha|beta|rc) ]]
}

# codesign arguments for the chosen identity. --timestamp needs a real
# identity; ad-hoc has none.
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  SIGN_ARGS=(--sign -)
else
  SIGN_ARGS=(--sign "$SIGN_IDENTITY" --timestamp)
fi

# Gatekeeper's verdict. It says "rejected" until the ticket is notarized and
# stapled, so callers decide whether that is an error.
gatekeeper() {
  spctl -a -vv -t "${2:-exec}" "$1" 2>&1 | sed 's/^/    /' || true
}
