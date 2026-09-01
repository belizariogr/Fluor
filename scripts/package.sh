#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
DERIVED="$ROOT/build"
APP_NAME="Fluor.app"
SPARKLE="$ROOT/Fluor/Sparkle.framework"

TEAM="${DEVELOPMENT_TEAM:-3Z7C3Q7NMT}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development}"

if [[ ! -d "$SPARKLE" ]]; then
  echo "error: missing $SPARKLE" >&2
  echo "Copy Sparkle.framework into Fluor/ before packaging." >&2
  exit 1
fi

mkdir -p "$DIST"

xcodebuild \
  -project "$ROOT/Fluor.xcodeproj" \
  -scheme Fluor \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  DEVELOPMENT_TEAM="$TEAM" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  build

RELEASE_APP="$DERIVED/Build/Products/Release/$APP_NAME"
if [[ ! -d "$RELEASE_APP" ]]; then
  echo "error: build succeeded but $RELEASE_APP was not produced" >&2
  exit 1
fi

rm -rf "$DIST/$APP_NAME"
ditto "$RELEASE_APP" "$DIST/$APP_NAME"

echo "Built $DIST/$APP_NAME"
defaults read "$DIST/$APP_NAME/Contents/Info.plist" CFBundleIdentifier
defaults read "$DIST/$APP_NAME/Contents/Info.plist" CFBundleShortVersionString
defaults read "$DIST/$APP_NAME/Contents/Info.plist" CFBundleVersion
codesign -dv "$DIST/$APP_NAME" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier)=' || true
