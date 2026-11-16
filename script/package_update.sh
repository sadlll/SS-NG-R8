#!/bin/bash
set -euo pipefail
umask 077
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:?usage: package_update.sh App.app output-dir vX.Y.Z}"
OUTPUT_DIR="${2:?missing output directory}"
RELEASE_TAG="${3:?missing release tag}"
SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-$ROOT_DIR/build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
KEY_DIR="$(mktemp -d -t ss-ng-update-signing)"
trap 'rm -rf -- "$KEY_DIR"' EXIT
KEY_FILE="$KEY_DIR/private-key"
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY_FILE"
else
  "$SPARKLE_TOOLS_DIR/generate_keys" --account sadlll.SS-NG-R8.updates -x "$KEY_FILE"
fi
chmod 600 "$KEY_FILE"
mkdir -p "$OUTPUT_DIR"
STAGING_DIR="$KEY_DIR/publish"
mkdir "$STAGING_DIR"
ZIP_NAME="ShadowsocksX-NG-R8-${RELEASE_TAG}-arm64.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$STAGING_DIR/$ZIP_NAME"
NOTES="$ROOT_DIR/docs/releases/$RELEASE_TAG.md"
if [ -f "$NOTES" ]; then cp "$NOTES" "$STAGING_DIR/${ZIP_NAME%.zip}.md"; fi
"$SPARKLE_TOOLS_DIR/generate_appcast" --ed-key-file "$KEY_FILE" --embed-release-notes \
  --download-url-prefix "https://github.com/sadlll/SS-NG-R8/releases/download/$RELEASE_TAG/" \
  --link "https://github.com/sadlll/SS-NG-R8/releases/tag/$RELEASE_TAG" "$STAGING_DIR"
"$SPARKLE_TOOLS_DIR/sign_update" --ed-key-file "$KEY_FILE" --verify "$STAGING_DIR/appcast.xml"
xcrun swift "$ROOT_DIR/script/verify_update.swift" "$APP_BUNDLE/Contents/Info.plist" "$STAGING_DIR/appcast.xml" "$STAGING_DIR/$ZIP_NAME" "$RELEASE_TAG"
# Exercise rejection paths without changing the published files or exposing the signing key.
mkdir "$KEY_DIR/negative"
python3 - "$STAGING_DIR/$ZIP_NAME" "$KEY_DIR/negative/$ZIP_NAME" "$STAGING_DIR/appcast.xml" "$KEY_DIR/tampered.xml" <<'PY'
from pathlib import Path
import sys
archive=bytearray(Path(sys.argv[1]).read_bytes());archive[len(archive)//2]^=1
Path(sys.argv[2]).write_bytes(archive)
feed=Path(sys.argv[3]).read_text();assert 'ShadowsocksX-NG' in feed
Path(sys.argv[4]).write_text(feed.replace('ShadowsocksX-NG','Tampered-ShadowsocksX-NG',1))
PY
if xcrun swift "$ROOT_DIR/script/verify_update.swift" "$APP_BUNDLE/Contents/Info.plist" "$STAGING_DIR/appcast.xml" "$KEY_DIR/negative/$ZIP_NAME" "$RELEASE_TAG" > "$KEY_DIR/archive-negative.log" 2>&1; then
  echo 'ERROR: modified update archive was accepted' >&2; exit 1
fi
python3 - "$APP_BUNDLE/Contents/Info.plist" "$KEY_DIR/wrong-key.plist" <<'PY'
from pathlib import Path
import base64, plistlib, sys
info=plistlib.loads(Path(sys.argv[1]).read_bytes())
info['SUPublicEDKey']=base64.b64encode(bytes(32)).decode()
Path(sys.argv[2]).write_bytes(plistlib.dumps(info))
PY
if xcrun swift "$ROOT_DIR/script/verify_update.swift" "$KEY_DIR/wrong-key.plist" "$STAGING_DIR/appcast.xml" "$STAGING_DIR/$ZIP_NAME" "$RELEASE_TAG" > "$KEY_DIR/key-negative.log" 2>&1; then
  echo 'ERROR: update archive with incorrect public key was accepted' >&2; exit 1
fi
if "$SPARKLE_TOOLS_DIR/sign_update" --ed-key-file "$KEY_FILE" --verify "$KEY_DIR/tampered.xml" > "$KEY_DIR/feed-negative.log" 2>&1; then
  echo 'ERROR: modified update feed was accepted' >&2; exit 1
fi
(cd "$STAGING_DIR" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")
cp "$STAGING_DIR/$ZIP_NAME" "$STAGING_DIR/$ZIP_NAME.sha256" "$STAGING_DIR/appcast.xml" "$OUTPUT_DIR/"
echo 'Signed update package verified; modified archive, feed and incorrect key rejected'
