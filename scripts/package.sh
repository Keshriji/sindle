#!/bin/bash
# Builds Spindle.app from the Swift package and wraps it in a .dmg.
# Run on a Mac (or on the GitHub macOS runner): ./scripts/package.sh
# Set SPINDLE_VERBOSE=1 for a full shell trace.
#
# Signing, all optional and read from the environment:
#   SPINDLE_SIGN_IDENTITY   codesigning identity name or SHA-1 (default "-" = ad-hoc)
#   SPINDLE_KEYCHAIN        keychain that holds that identity
#   SPINDLE_TIMESTAMP       1 to ask Apple for a secure timestamp (Developer ID only)
#   SPINDLE_NOTARY_APPLE_ID / SPINDLE_NOTARY_TEAM_ID / SPINDLE_NOTARY_PASSWORD
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

echo "==> Signing"
SIGN_ID="${SPINDLE_SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --deep)
if [ "$SIGN_ID" = "-" ]; then
  echo "    ad-hoc: macOS sees a new code requirement on every launch, so Screen Recording"
  echo "    is granted again each time. Set SPINDLE_SIGN_IDENTITY to avoid that."
  SIGN_ARGS+=(--sign -)
else
  echo "    identity: $SIGN_ID"
  SIGN_ARGS+=(--sign "$SIGN_ID" --identifier com.example.spindle --options runtime)
  if [ -n "${SPINDLE_KEYCHAIN:-}" ]; then SIGN_ARGS+=(--keychain "$SPINDLE_KEYCHAIN"); fi
  if [ "${SPINDLE_TIMESTAMP:-0}" = "1" ]; then SIGN_ARGS+=(--timestamp); else SIGN_ARGS+=(--timestamp=none); fi
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# Write down what macOS keys the permission on. If this changes between builds the grant
# is thrown away, so it belongs in the log and in the release notes.
DR="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
{
  echo "identity: $SIGN_ID"
  echo "designated requirement: $DR"
  printf 'dr_sha256 %s\n' "$(printf '%s' "$DR" | shasum -a 256 | cut -d' ' -f1)"
} | tee build/signature.txt

if [ -n "${SPINDLE_NOTARY_APPLE_ID:-}" ] && [ -n "${SPINDLE_NOTARY_TEAM_ID:-}" ] && [ -n "${SPINDLE_NOTARY_PASSWORD:-}" ]; then
  echo "==> Notarizing"
  ditto -c -k --keepParent "$APP" build/notarize.zip
  xcrun notarytool submit build/notarize.zip \
    --apple-id "$SPINDLE_NOTARY_APPLE_ID" \
    --team-id "$SPINDLE_NOTARY_TEAM_ID" \
    --password "$SPINDLE_NOTARY_PASSWORD" --wait
  xcrun stapler staple "$APP"
  rm -f build/notarize.zip
  echo "==> Notarized and stapled"
else
  echo "==> Not notarized (no notary credentials): right-click > Open on first launch"
fi

echo "==> Packaging dmg"
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname Spindle -srcfolder build/dmg -ov -format UDZO build/Spindle.dmg

echo "Done: build/Spindle.dmg"
