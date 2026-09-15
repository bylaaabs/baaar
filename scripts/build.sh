#!/usr/bin/env bash
# Builds baaar.app. --install copies it to /Applications (System Settings only
# lists privacy grants for apps in a regular location) and relaunches it.
# DerivedData lives outside the project: files synced under ~/Desktop carry
# extended attributes that make codesign reject the bundle.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/baaar-cli}"

xcodegen generate --quiet
mkdir -p build
if ! xcodebuild \
  -project baaar.xcodeproj \
  -scheme baaar \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development}" \
  build > build/xcodebuild.log 2>&1; then
  grep -E "error:" build/xcodebuild.log >&2 || tail -30 build/xcodebuild.log >&2
  exit 1
fi
grep -E "warning:" build/xcodebuild.log | grep -v "appintentsmetadataprocessor" | sort -u || true

APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/baaar.app"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x baaar 2>/dev/null || true
  rm -rf /Applications/baaar.app
  ditto "$APP" /Applications/baaar.app
  open /Applications/baaar.app
  echo "Installed /Applications/baaar.app"
fi
