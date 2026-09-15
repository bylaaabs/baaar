#!/usr/bin/env bash
# Notarizes one or more signed files with Apple and staples the tickets.
#
#   scripts/release/notarize.sh dist/baaar.app
#   scripts/release/notarize.sh dist/baaar-v0.4.0-alpha.1.dmg
#
# Accepts .app (zipped for the upload, the bundle itself gets stapled), .dmg and
# .pkg (stapled in place) and .zip (submitted; a zip cannot carry a ticket, the
# bundle inside must have been stapled before zipping).
#
# Credentials, one of:
#   - a keychain profile: NOTARY_PROFILE (default "baaar"), stored once with
#       xcrun notarytool store-credentials baaar --key AuthKey.p8 --key-id ID --issuer UUID
#   - an App Store Connect API key: APPSTORE_CONNECT_API_KEY_PATH (.p8),
#     APPSTORE_CONNECT_API_KEY_ID and APPSTORE_CONNECT_API_ISSUER_ID.
# The API key envs win when all three are set (that is what CI does).
#
# On a rejection the notary log is printed, which names every file Apple
# objected to.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || die "usage: $(basename "$0") <file> [file...]"
need xcrun "install Xcode"
for TARGET in "$@"; do
  [[ -e "$TARGET" ]] || die "$TARGET does not exist"
  case "$TARGET" in
    *.app|*.dmg|*.pkg|*.zip) ;;
    *) die "don't know how to notarize $TARGET (expected .app, .dmg, .pkg or .zip)" ;;
  esac
done

if [[ -n "${APPSTORE_CONNECT_API_KEY_PATH:-}" && -n "${APPSTORE_CONNECT_API_KEY_ID:-}" && -n "${APPSTORE_CONNECT_API_ISSUER_ID:-}" ]]; then
  [[ -f "$APPSTORE_CONNECT_API_KEY_PATH" ]] || die "APPSTORE_CONNECT_API_KEY_PATH=$APPSTORE_CONNECT_API_KEY_PATH does not exist"
  CREDS=(--key "$APPSTORE_CONNECT_API_KEY_PATH" --key-id "$APPSTORE_CONNECT_API_KEY_ID" --issuer "$APPSTORE_CONNECT_API_ISSUER_ID")
  CRED_KIND="API key $APPSTORE_CONNECT_API_KEY_ID"
else
  NOTARY_PROFILE="${NOTARY_PROFILE:-baaar}"
  CREDS=(--keychain-profile "$NOTARY_PROFILE")
  CRED_KIND="keychain profile \"$NOTARY_PROFILE\""
  if ! xcrun notarytool history "${CREDS[@]}" >/dev/null 2>&1; then
    die "no notary credentials. Either store a profile once:
    xcrun notarytool store-credentials $NOTARY_PROFILE --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer uuid>
  or export APPSTORE_CONNECT_API_KEY_PATH, APPSTORE_CONNECT_API_KEY_ID and APPSTORE_CONNECT_API_ISSUER_ID"
  fi
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/baaar-notarize.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

submit() {
  local upload="$1"
  local log="$WORK/submit-$(basename "$upload").log"
  local id status
  step "Submitting $(basename "$upload") with $CRED_KIND"
  # --wait blocks until Apple answers, usually one to five minutes. A failure
  # is handled below from the transcript, so the log can be fetched.
  xcrun notarytool submit "$upload" "${CREDS[@]}" --wait --timeout 30m 2>&1 | tee "$log" || true
  id="$(awk '/^ *id: / {print $2; exit}' "$log")"
  status="$(awk '/^ *status: / {s=$2} END {print s}' "$log")"
  if [[ "$status" != "Accepted" ]]; then
    printf '\nnotarization of %s ended with status "%s"\n' "$upload" "${status:-unknown}" >&2
    if [[ -n "$id" ]]; then
      printf 'notary log for %s:\n' "$id" >&2
      xcrun notarytool log "$id" "${CREDS[@]}" >&2 || true
    fi
    exit 1
  fi
  note "accepted, submission $id"
}

staple() {
  step "Stapling $(basename "$1")"
  xcrun stapler staple "$1"
  xcrun stapler validate "$1"
}

for TARGET in "$@"; do
  case "$TARGET" in
    *.app)
      [[ -d "$TARGET" ]] || die "$TARGET is not a bundle"
      codesign --verify --deep --strict "$TARGET" || die "$TARGET is not validly signed; notarization would be rejected"
      UPLOAD="$WORK/$(basename "$TARGET" .app).zip"
      ditto -c -k --keepParent --norsrc "$TARGET" "$UPLOAD"
      submit "$UPLOAD"
      staple "$TARGET"
      note "Gatekeeper:"
      gatekeeper "$TARGET" exec
      ;;
    *.dmg|*.pkg)
      submit "$TARGET"
      staple "$TARGET"
      note "Gatekeeper:"
      gatekeeper "$TARGET" open
      ;;
    *.zip)
      submit "$TARGET"
      note "a zip cannot be stapled; the bundle inside carries its own ticket if it was stapled before zipping"
      ;;
  esac
done

step "Notarized: $*"
