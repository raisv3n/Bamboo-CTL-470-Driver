# BambooDriver — macOS

Native menu-bar app (Swift, universal arm64 + x86_64, macOS 14+). No kext, DriverKit entitlement
or Rosetta — public IOKit HID and CoreGraphics APIs only, so it runs on macOS 27 Golden Gate.

## Build, test, install

```sh
tools/make-signing-cert.sh   # once per Mac: stable signing identity (keeps Accessibility across rebuilds)
./build.sh                   # → build/BambooDriver.app
tests/run.sh                 # decoder vs shared/testdata golden files
./install.sh                 # → /Applications, starts it; it registers itself to open at login
./package.sh                 # → dist/BambooDriver.zip (app + install.sh) for another Mac
```

Version: `VERSION` in `build.sh`. Release: push to `main`, then push tag `macos-v<VERSION>`;
`.github/workflows/macos.yml` tests, packages and publishes `BambooDriver-macos.zip`.

### Signing

Local builds are signed with the self-signed "BambooDriver Local Signing" identity, so the
Accessibility grant survives rebuilds on this Mac. Release builds from CI are **ad-hoc signed**:
the signing key is deliberately kept off GitHub, because anyone holding it could sign an app that
inherits BambooDriver's Accessibility permission. After installing an update from Releases,
re-enable BambooDriver under Accessibility (remove the old entry, add the new app).

The app is not notarized; `install.sh` clears the quarantine flag. If opened directly from a download
instead, use System Settings → Privacy & Security → Open Anyway.

## Menu

Connection status · Map Tablet To (All Displays / Main Display) · Keep Proportions · Open at Login · Quit.

## Source

| File | Role |
|---|---|
| `BambooDriver/Tablet.swift` | IOHIDManager matching, mode switch (`02 02` / `02 01`), report decode |
| `BambooDriver/PenFilter.swift` | One Euro smoothing, click snap |
| `BambooDriver/PenEventPoster.swift` | presence/tip/button state → CGEvent tablet events, screen mapping |
| `BambooDriver/main.swift` | menu bar, settings, login item, wake handling |
| `tools/hidprobe.swift` | read-only probe; `--wacom-mode --listen N` records reports |

Debug: `BAMBOO_DEBUG=1 /Applications/BambooDriver.app/Contents/MacOS/BambooDriver` prints each sample
(quit the menu-bar copy first).

## Troubleshooting

- **Pen does nothing**: Accessibility not granted to this build. Remove BambooDriver from the
  Accessibility list, re-add `/Applications/BambooDriver.app`, relaunch. Ad-hoc builds lose the
  grant on every rebuild — that looks like a broken driver, not a permission problem.
- **Cursor stuck after quitting**: the tablet stays in tablet mode if the app was killed rather
  than quit; unplug/replug or relaunch the app.
