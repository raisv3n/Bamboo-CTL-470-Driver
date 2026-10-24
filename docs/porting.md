# Porting guide

How to bring BambooDriver to another OS. Start with `docs/protocol.md` (what the device does and
how the driver must behave); this page is about *where each piece lives* on each platform.

## What a port consists of

| Piece | macOS implementation | Portable? |
|---|---|---|
| Decode report 0x02 | `macos/BambooDriver/Tablet.swift` → `PenSample.decode` | Pure logic — port verbatim |
| Filtering, click snap, double-click | `macos/BambooDriver/PenFilter.swift`, `PenEventPoster.swift` (state handling) | Pure logic — port verbatim |
| Find device, send feature report, read input reports | IOHIDManager (`Tablet.swift`) | Platform API |
| Inject pen events with pressure | CGEvent tablet events (`PenEventPoster.swift`) | Platform API |
| Run at login, settings, tray/menu | SMAppService, NSStatusItem, UserDefaults (`main.swift`) | Platform API |
| Permissions | Accessibility (event posting) | Platform-specific |

Keep the pure-logic part a separate module in each port so it can run the golden tests.

## Validating a port

1. Run your decoder over every `shared/testdata/*.hex` (one report per line) and compare with
   `*.decode.expected.jsonl` — exact match, same field names.
2. Run your behaviour model with a synthetic 5 ms clock and compare with `*.events.expected.jsonl`.
   Positions are normalised 0..1 and rounded to 4 decimals.
3. Record a new capture on the real tablet with the platform's probe tool, add it to
   `shared/testdata/`, run `python3 shared/reference/bamboo_reference.py regen`, and commit both.

If a platform needs a behaviour change, change `docs/protocol.md` and the reference script first,
regenerate golden files, then update every port (and note it in `docs/port-notes/`).

## Linux

**Check first whether you need a port at all.** The mainline kernel driver `hid-wacom` supports this
tablet (`USB_DEVICE_WACOM(0xDD)`, "Wacom Bamboo Connect", 14720×9200, 1023 pressure), switches it
to tablet mode itself, and exposes it through libinput — GNOME/KDE tablet settings then just work.

```sh
lsusb | grep 056a:00dd
sudo libinput list-devices | grep -A8 -i wacom
xsetwacom --list devices          # X11 only
```

Only if that fails (old kernel, unusual distro), a user-space port would use:
- device: `hidraw` (`/dev/hidrawN`, `HIDIOCSFEATURE` ioctl for `02 02`, `read()` for reports) or hidapi;
  udev rule granting the user access to `056a:00dd`.
- injection: `uinput` virtual device with `ABS_X`/`ABS_Y`/`ABS_PRESSURE`, `BTN_TOOL_PEN`,
  `BTN_TOUCH`, `BTN_STYLUS`, `BTN_STYLUS2`, `INPUT_PROP_DIRECT` off (pen tablet), resolution 100/mm.
  libinput then applies its own smoothing/mapping, so rules 2, 4, 7 of the protocol may be left to it.
- the in-kernel driver must be unbound or it will own the device.

## Windows

Two routes, in order of preference:

1. **Wacom's legacy driver** may still install on Windows 10/11 x64 (Bamboo driver 5.3.x). It will
   not work on Windows on ARM. If it works, no port is needed.
2. **User-space port** (no kernel driver, no driver signing):
   - device: Windows exposes each HID top-level collection separately. The mouse collection
     (report 0x01) is opened exclusively by Windows, but report 0x02 and the feature reports sit in
     the **digitizer** collection (usage page 0x0D), which user mode can open.
     Use SetupAPI/`HidD_GetHidGuid` to find `VID_056A&PID_00DD` with usage page 0x0D,
     `HidD_SetFeature(handle, {0x02, 0x02}, 2)` for tablet mode, overlapped `ReadFile` for reports.
     hidapi (`hid_send_feature_report`, `hid_read`) wraps the same calls.
   - injection: `CreateSyntheticPointerDevice(PT_PEN, 1, POINTER_FEEDBACK_DEFAULT)` +
     `InjectSyntheticPointerInput` (Windows 10 1809+). `POINTER_PEN_INFO.pressure` takes 0–1024,
     `penFlags` carries `PEN_FLAG_BARREL` (lower switch) and `PEN_FLAG_ERASER`; Windows Ink apps
     (Krita, Photoshop in Windows Ink mode, OneNote) get pressure. Coordinates are physical screen
     pixels, so declare the process per-monitor DPI aware.
   - middle click (upper switch): there is no pen flag; send `SendInput` with
     `MOUSEEVENTF_MIDDLEDOWN/UP` instead.
   - start at login: per-user `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` value;
     tray icon via `Shell_NotifyIcon`.
   - In tablet mode Windows stops getting mouse reports, so the cursor only moves via injection —
     same as macOS.

A Rust implementation (`hidapi` + `windows` crates) fits the existing Hoardini Windows port tooling;
the decode/filter module can be shared with a Linux user-space port if one is ever needed.

## Repository conventions for ports

- Each platform lives in its own top-level folder (`macos/`, `windows/`, `linux/`) with its own
  README, build script and probe tool. Shared material goes in `docs/` and `shared/`.
- Each platform has its own CI workflow (`.github/workflows/<platform>.yml`) path-filtered to its
  folder plus `shared/**`, and its own release tag prefix: `macos-v*`, `windows-v*`, `linux-v*`.
  Release assets are named `BambooDriver-<platform>.zip` so releases never collide.
- Work on each OS's own machine, push to the same `main` branch (pull first — other platforms may
  have pushed). Touching another platform's folder from a different machine is fine for docs, but
  build/test changes there should be made on that platform.
- Line endings are normalised by `.gitattributes` (LF everywhere except `*.ps1`, `*.bat`, `*.cmd`, `*.sln`).
- After each session, add `docs/port-notes/YYYY-MM-DD.md` describing behaviour changes in
  platform-neutral terms so the other ports can follow.
