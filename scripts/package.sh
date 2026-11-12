#!/bin/bash
# Builds Spindle.app from the Swift package and wraps it in a .dmg. Run on a Mac (or the GitHub macOS runner).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Spindle"
rm -rf build && mkdir -p build/Spindle.app/Contents/MacOS build/Spindle.app/Contents/Resources build/dmg
cp "$BIN" build/Spindle.app/Contents/MacOS/Spindle
cp Info.plist build/Spindle.app/Contents/Info.plist
codesign --force --deep --sign - build/Spindle.app          # ad-hoc signature (not notarized)
cp -R build/Spindle.app build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -volname Spindle -srcfolder build/dmg -ov -format UDZO build/Spindle.dmg
echo "Done: build/Spindle.dmg"
