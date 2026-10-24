# BambooDriver

Keeps an old Wacom Bamboo **CTL-470** (USB 056A:00DD) working after Wacom stopped supporting it.
The protocol was reverse engineered from Wacom's last Mac driver (Pen Tablet 5.3.7-6, 2016) and
confirmed on the real tablet.

| Platform | Status | Folder |
|---|---|---|
| macOS 14+ (built for macOS 27 Golden Gate), Apple silicon and Intel | Working, v0.2.0 | [`macos/`](macos/) |
| Windows | Not started — see porting guide | [`windows/`](windows/) |
| Linux | Likely supported by the kernel already | [`linux/`](linux/) |

## Install on a Mac

1. Download `BambooDriver-macos.zip` from [Releases](../../releases) and unzip it.
2. In Terminal, run the `install.sh` inside the folder (drag it into the Terminal window, press Return).
   It copies the app to /Applications, clears the download quarantine and starts it.
3. Allow **BambooDriver** in System Settings → Privacy & Security → **Accessibility**.
   After installing a newer release, remove the old BambooDriver entry there and add the new app
   (release builds are ad-hoc signed, so macOS treats each version as a new app).

It runs in the menu bar (pencil icon) and opens at login. Quitting it returns the tablet to plain
mouse mode.

## Repository layout

| Path | Contents |
|---|---|
| `macos/` | Swift menu-bar driver, build/package/install scripts, HID probe, golden tests |
| `windows/`, `linux/` | Port folders (READMEs with plans) |
| `docs/protocol.md` | Platform-neutral protocol + required driver behaviour — start here for ports |
| `docs/porting.md` | Per-platform APIs, validation, repo conventions |
| `docs/findings/` | Reverse-engineering evidence (REA + Ghidra) |
| `docs/port-notes/` | Per-session handoff notes between platforms |
| `shared/testdata/` | Raw captures from the real tablet + golden decode/event files |
| `shared/reference/` | Reference decoder/behaviour model (Python, stdlib only) |
| `original-driver/` | Wacom's installers — not in git, see its README |

## Releases

Each platform releases independently with its own tag prefix: `macos-v0.2.0`, `windows-v…`, `linux-v…`.
Pushing a `macos-v*` tag that matches `VERSION` in `macos/build.sh` builds, tests and publishes
`BambooDriver-macos.zip`.

## Legal

Not affiliated with Wacom. Wacom's driver binaries are not redistributed here; the protocol was
studied for interoperability with hardware the author owns.
