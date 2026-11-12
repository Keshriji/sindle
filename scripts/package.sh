#!/bin/bash
# Builds Spindle.app from the Swift package and wraps it in a .dmg.
# Run on a Mac (or on the GitHub macOS runner): ./scripts/package.sh
# Set SPINDLE_VERBOSE=1 for a full shell trace.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${SPINDLE_VERBOSE:-0}" = "1" ]; then set -x; fi

echo "==> Host: $(uname -m), macOS $(sw_vers -productVersion)"
swift --version || true
xcodebuild -version || true

echo "==> swift build -c release"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/Spindle"
if [ ! -f "$BIN" ]; then
  echo "error: expected executable at $BIN" >&2
  ls -la "$BIN_DIR" >&2 || true
  exit 1
fi
echo "==> Built: $(file "$BIN")"

APP="build/Spindle.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/dmg
cp "$BIN" "$APP/Contents/MacOS/Spindle"
chmod +x "$APP/Contents/MacOS/Spindle"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad-hoc, not notarized)"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"

echo "==> Packaging dmg"
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname Spindle -srcfolder build/dmg -ov -format UDZO build/Spindle.dmg

echo "Done: build/Spindle.dmg"
