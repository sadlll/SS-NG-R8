#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODEL_APP="$ROOT_DIR/build/checks/UpdaterModelCheck.app"
FRAMEWORKS="$ROOT_DIR/build/Build/Products/Release"
test -d "$FRAMEWORKS/Sparkle.framework"
mkdir -p "$MODEL_APP/Contents/MacOS" "$MODEL_APP/Contents/Resources/zh-Hans.lproj"
python3 - "$MODEL_APP" <<'PY'
from pathlib import Path
import plistlib,sys
info=plistlib.loads(Path('ShadowsocksX-NG/Info.plist').read_bytes())
info.update(CFBundleIdentifier='com.sadlll.ssng.UpdaterModelCheck',CFBundleExecutable='UpdaterModelCheck',CFBundleDevelopmentRegion='zh-Hans',CFBundleLocalizations=['zh-Hans'])
info.pop('NSMainNibFile',None);info.pop('NSPrincipalClass',None)
Path(sys.argv[1]+'/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
cp ShadowsocksX-NG/zh-Hans.lproj/Localizable.strings "$MODEL_APP/Contents/Resources/zh-Hans.lproj/"
xcrun swiftc -swift-version 5 -target arm64-apple-macos14.0 \
  -F "$FRAMEWORKS" -framework Sparkle -framework AppKit \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  ShadowsocksX-NG/VersionChecker.swift Tests/AppModel/UpdaterModelCheck.swift \
  -o "$MODEL_APP/Contents/MacOS/UpdaterModelCheck"
"$MODEL_APP/Contents/MacOS/UpdaterModelCheck"
