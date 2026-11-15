#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
CHECK_DIR="$ROOT_DIR/build/checks"
APP_BUNDLE="$CHECK_DIR/ModelCheck.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/zh-Hans.lproj"
cat > "$CHECK_DIR/model-bridge.h" <<'EOF'
#import <Foundation/Foundation.h>
#import "../../ShadowsocksX-NG/Configure.h"
#import "../../ShadowsocksX-NG/Utils.h"
EOF
xcrun clang -fobjc-arc -mmacosx-version-min=14.0 -include Cocoa/Cocoa.h -c ShadowsocksX-NG/Utils.m -o "$CHECK_DIR/model-utils.o"
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 -import-objc-header "$CHECK_DIR/model-bridge.h" \
  Diagnostics/*.swift ShadowsocksX-NG/ServerProfile.swift Tests/AppModel/ModelCheck.swift \
  "$CHECK_DIR/model-utils.o" -framework AppKit -framework CoreImage \
  -o "$APP_BUNDLE/Contents/MacOS/ModelCheck"
cp ShadowsocksX-NG/zh-Hans.lproj/Localizable.strings "$APP_BUNDLE/Contents/Resources/zh-Hans.lproj/"
cat > "$APP_BUNDLE/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.sadlll.ssng.ModelCheck</string>
<key>CFBundleExecutable</key><string>ModelCheck</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string></array>
</dict></plist>
EOF
"$APP_BUNDLE/Contents/MacOS/ModelCheck"
