#!/usr/bin/env bash
# Cuts a baaar release from this Mac: build, notarize, package, tag, publish.
#
#   scripts/release/release.sh <version> [--dry-run]
#
# For version 0.4.0-alpha.1 it runs, in order:
#   1. build-release.sh        dist/baaar.app, Developer ID signed
#   2. notarize.sh             the bundle, then staples its ticket
#   3. make-dmg.sh             dist/baaar-v0.4.0-alpha.1.dmg and .zip from the stapled bundle
#   4. notarize.sh             the DMG, then staples it
#   5. checksum.sh             SHA-256 and the Homebrew cask
#   6. git tag v0.1.0 (signed when git has a signing key), push the tag, gh release create with the CHANGELOG section
#
# It refuses to run with uncommitted changes, when the tag already exists, when
# project.yml's MARKETING_VERSION differs, or when CHANGELOG.md has no section
# for the version. --dry-run builds and packages but skips notarization, the tag
# and the GitHub release, so it works without Apple credentials (add
# DEVELOPER_ID_APPLICATION=- to also skip the certificate).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib.sh"

DRY_RUN=0
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option $arg" ;;
    *) [[ -z "$VERSION" ]] || die "one version only"; VERSION="$arg" ;;
  esac
done
[[ -n "$VERSION" ]] || die "usage: $(basename "$0") <version> [--dry-run]"
VERSION="${VERSION#v}"
check_semver "$VERSION"
TAG="v$VERSION"
export VERSION

cd "$ROOT"
need git
need xcodegen "brew install xcodegen"
[[ $DRY_RUN -eq 1 ]] || need gh "brew install gh"

step "Preflight for baaar $VERSION"

# dist/ is this script's own output and is tolerated even when .gitignore
# does not list it yet.
DIRTY="$(git status --porcelain | grep -v '^?? dist/$' || true)"
if [[ -n "$DIRTY" ]]; then
  printf '%s\n' "$DIRTY" >&2
  die "the working tree has uncommitted changes; commit or discard them first"
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" == "main" ]] || warn "releasing from '$BRANCH', not main"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "tag $TAG already exists locally; tags are immutable, cut a new version"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  die "tag $TAG already exists on origin; tags are immutable, cut a new version"
fi

PROJECT_VERSION="$(VERSION='' project_version)"
[[ "$PROJECT_VERSION" == "$VERSION" ]] \
  || die "project.yml says MARKETING_VERSION \"$PROJECT_VERSION\"; bump it to \"$VERSION\" in a release commit first"

# The CHANGELOG section becomes the release notes. Both [vX.Y.Z] and [X.Y.Z]
# headings are accepted; the handbook uses the first.
NOTES="$DIST/release-notes-$TAG.md"
mkdir -p "$DIST"
awk -v v="$VERSION" '
  /^## \[/ { inside = ($0 ~ "^## \\[v?" v "\\]") ; next }
  inside { print }
' CHANGELOG.md | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$NOTES"
if [[ ! -s "$NOTES" ]]; then
  die "CHANGELOG.md has no '## [$TAG] - <date>' section; rename [Unreleased] before releasing"
fi
note "release notes: $NOTES ($(wc -l < "$NOTES" | tr -d ' ') lines)"

if [[ $DRY_RUN -eq 1 ]]; then
  note "dry run: notarization, the tag and the GitHub release are skipped"
else
  gh auth status >/dev/null 2>&1 || die "gh is not logged in; run: gh auth login"
fi

"$HERE/build-release.sh"
[[ $DRY_RUN -eq 1 ]] || "$HERE/notarize.sh" "$DIST/$APP_NAME.app"
"$HERE/make-dmg.sh" "$DIST/$APP_NAME.app"
[[ $DRY_RUN -eq 1 ]] || "$HERE/notarize.sh" "$DIST/$APP_NAME-v$VERSION.dmg"

CHECKSUMS="$DIST/checksums-$TAG.txt"
"$HERE/checksum.sh" "$VERSION" | tee "$CHECKSUMS"

DMG="$DIST/$APP_NAME-v$VERSION.dmg"
ZIP="$DIST/$APP_NAME-v$VERSION.zip"
{
  printf '\n### SHA-256\n\n```\n'
  shasum -a 256 "$DMG" "$ZIP" | sed "s| $DIST/| |"
  printf '```\n'
} >> "$NOTES"

if [[ $DRY_RUN -eq 1 ]]; then
  step "Dry run complete"
  note "$DMG"
  note "$ZIP"
  note "notes: $NOTES"
  note "next: scripts/release/release.sh $VERSION (without --dry-run) once Apple credentials are stored"
  exit 0
fi

step "Tagging $TAG"
# Signed when git knows a signing key; an annotated tag otherwise, like the other laaabs repositories.
if [[ -n "$(git config --get user.signingkey || true)" ]]; then
  git tag -s "$TAG" -m "baaar $VERSION" || die "could not create a signed tag"
else
  git tag -a "$TAG" -m "baaar $VERSION"
fi
git push origin "refs/tags/$TAG"

step "Publishing the GitHub release"
PRERELEASE=()
if is_prerelease "$VERSION"; then PRERELEASE=(--prerelease); fi
gh release create "$TAG" "$DMG" "$ZIP" \
  --repo "$REPO_SLUG" \
  --verify-tag \
  --title "baaar $VERSION" \
  --notes-file "$NOTES" \
  ${PRERELEASE[@]+"${PRERELEASE[@]}"}

step "Released baaar $VERSION"
note "https://github.com/$REPO_SLUG/releases/tag/$TAG"
note "next: update Casks/baaar.rb in bylaaabs/homebrew-tap with the cask printed above (also in $CHECKSUMS)"
