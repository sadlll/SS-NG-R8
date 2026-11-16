#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
APP_NAME="ShadowsocksX-NG"
APP_BUNDLE="$ROOT_DIR/build/Build/Products/Debug/$APP_NAME.app"
case "$MODE" in
  run|--build-only|--verify|--debug|--logs|--telemetry) ;;
  *) echo "usage: $0 [--build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
if [ "$MODE" != "--build-only" ]; then
  /usr/bin/osascript -e 'tell application id "com.qiuyuzhou.ShadowsocksX-NG" to quit' 2>/dev/null || true
fi
xcodebuild -workspace ShadowsocksX-NG.xcworkspace -scheme ShadowsocksX-NG \
  -configuration Debug -derivedDataPath build ARCHS=arm64 \
  MACOSX_DEPLOYMENT_TARGET=14.0 CODE_SIGNING_ALLOWED=NO build
if [ "$MODE" = "--build-only" ]; then exit 0; fi
# Local ad-hoc signing allows launching the development bundle on Apple Silicon.
"$ROOT_DIR/script/sign_app.sh" "$APP_BUNDLE"
if [ "$MODE" = "--debug" ]; then
  exec /usr/bin/lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi
/usr/bin/open -n "$APP_BUNDLE"
case "$MODE" in
  --verify) sleep 2; /usr/bin/pgrep -x "$APP_NAME" >/dev/null ;;
  --logs|--telemetry) exec /usr/bin/log stream --info --style compact --predicate 'process == "ShadowsocksX-NG"' ;;
esac
