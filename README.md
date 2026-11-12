# Spindle: a music island for the Mac notch

Original SwiftUI app. Shows what's playing in Spotify or Apple Music in a pill at the top of the screen;
hover to expand, with artwork, progress and play/pause/skip controls.

## Run it (needs a Mac, macOS 14+, Xcode 15+)
1. Xcode > File > New > Project > macOS > App (SwiftUI), name it Spindle.
2. Delete the generated files, drag in the four .swift files from Sources/.
3. In Info.plist add:
   - `NSAppleEventsUsageDescription` = "Spindle reads the current track from Spotify and Music."
   - `NSLocationWhenInUseUsageDescription` = "Spindle uses your approximate location for the weather page."
   - `LSUIElement` = YES (hides the Dock icon)
4. Signing & Capabilities: turn OFF App Sandbox (or add the Apple Events temporary exception for
   com.spotify.client and com.apple.Music).
5. Run. Play a song in Spotify or Music, then hover the top of your screen. Approve the Automation prompt.

## Features so far
- Island: hover to expand, spring animation
- Pages (tab buttons or swipe left/right): Player, synced Lyrics (LRCLIB), Weather (MET Norway)

- Edge sliders: volume (left edge) and brightness (right edge). Hover to widen, drag to change.
  Brightness uses a private Apple framework, so it may break on new macOS versions.

- Status page (4th tab): headphone battery (L / R / Case), Mac battery and charging, Focus mode.
  A short toast appears in the island when headphones connect, charging starts or stops, or Focus turns on.
  Focus detection reads a system file, so give Spindle Full Disk Access (System Settings > Privacy & Security).

- Tool tabs: Tray, Notes, Tasks, Alarm + Counter. The pin button keeps the island open while you type.
  - Tray: drop files on the notch (it opens by itself), or copy files in Finder and they appear. Drag them back out, or right-click to remove.
  - Notes and tasks are saved automatically on your Mac.
  - Alarm rings once at the time you set; the counter is a simple tally.
- Desktop widget: turntable or colour aura. Click to switch, drag to move, menu bar > Show or hide.

- Tab row is now grouped: Player, Lyrics, Weather, Status, plus a grid button that opens the tools row
  (Tray, Notes, Tasks, Alarm, Wallpapers). The arrow on the left of that row goes back.
- Wallpapers: 12 original wallpapers painted in code (no downloads). Tap one to set it on every display.
  To add more, add a palette to `Walls.all` in Wallpapers.swift.

- Typing speed ("Keycap", tools row): live words-per-minute on a keycap that presses with each change, optional key sounds.
  Needs Accessibility permission. It counts keystrokes only and never records what you type.
- Listening diary: a 7-day bar chart, weekly total and most-played track. Stored only on this Mac.
- Beat Glow: a light around the screen edge that pulses while music plays, tinted by the album cover.
  It pulses at a steady tempo; true audio reaction needs ScreenCaptureKit (a future step). Toggle from the menu bar icon.
- Desktop widget now has three styles: turntable, record sleeve (record slides out), and aura.

## Not built
- Lock screen record and lyrics: needs private window-server APIs and breaks between macOS releases.

## Next steps
- Set your real email in the weather User-Agent (Weather.swift).
- Apple Music artwork: read artwork data from AppleScript and cache it.
- Click-through: make the panel ignore mouse events outside the pill.
- Distribute outside the Mac App Store (Developer ID + notarization).

## Build a .dmg without Xcode (needs a Mac, or GitHub's free macOS runner)
- On a Mac with Xcode command line tools: `./scripts/package.sh` creates `build/Spindle.dmg`.
- On GitHub: push this folder to a repo, open Actions > "Build Spindle dmg" > Run workflow, then download the `Spindle-dmg` artifact.
- The app is ad-hoc signed, not notarized. After downloading, right-click > Open, or run `xattr -cr /Applications/Spindle.app`.
