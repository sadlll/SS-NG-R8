#!/bin/bash
set -euo pipefail
APP_BUNDLE="${1:?usage: sign_app.sh path/to/App.app}"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
# Sign Sparkle's helpers individually; --deep can discard their required entitlements.
if [ -d "$SPARKLE_FRAMEWORK" ]; then
  for nested in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --preserve-metadata=entitlements \
      "$SPARKLE_FRAMEWORK/Versions/B/$nested"
  done
fi
for framework in "$APP_BUNDLE"/Contents/Frameworks/*.framework; do
  [ -d "$framework" ] || continue
  /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --preserve-metadata=entitlements "$framework"
done
for helper in "$APP_BUNDLE"/Contents/Library/LoginItems/*.app; do
  [ -d "$helper" ] || continue
  /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" "$helper"
done
for resource in "$APP_BUNDLE"/Contents/Resources/*; do
  [ -f "$resource" ] || continue
  if [[ "$(/usr/bin/file -b "$resource")" == *Mach-O* ]]; then
    /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" "$resource"
  fi
done
if [ "$SIGNING_IDENTITY" = "-" ]; then
  /usr/bin/codesign --force --sign - "$APP_BUNDLE"
else
  /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP_BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
