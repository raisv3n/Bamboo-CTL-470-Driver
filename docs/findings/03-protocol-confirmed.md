# 03 — CTL-470 protocol (static + runtime confirmed)

## Mode switch

| Mode | Request | Evidence |
|---|---|---|
| Wacom (tablet) | HID SET_REPORT (bRequest 9), feature report 0x02, data `02 02`, up to 6 tries, 1.0 s timeout | `CUSBCommInterface::SetToWacomMode` ev_ac87197e… (static); accepted by device, report stream changes (runtime, `shared/testdata/wacom-mode-2.hex`) |
| HID (mouse) | same, data `02 01` | `CUSBCommInterface::SetToHIDMode` ev_9b063d2c… (static); device default at plug-in (runtime GET) |

Call chain on connect: `CCT2GraphicsTablet::DeviceStart` → `CPTKUSBGraphicsTablet::DeviceStart`
→ `SetupTablet` → `SetHidMode(true)` → `SetToWacomMode` (ev_8693215b…, ev_f3a063ce…, ev_6a6be0a4…, ev_a475cd30…).

Notes (runtime):
- GET feature 0x02 keeps returning `02 01` even in Wacom mode; it is not a reliable mode readback.
  Wacom mode is detectable by the 0xC0 status report (~every 5 s) and the absence of report 0x01.
- In Wacom mode macOS no longer moves the cursor (cursor fixed across 200 samples while 1,334 pen
  reports arrived), so the user-space driver does not need to seize the device.
- The tablet returns to HID mode after USB re-enumeration; the driver re-sends on attach and on wake.

## Pen report 0x02 (10 bytes)

| Byte | Field | Source |
|---|---|---|
| 0 | report ID 0x02 | runtime |
| 1 | 0x80 in range · 0x40 proximity (x/y valid) · 0x20 ready (pressure/buttons valid) · 0x08 eraser · 0x04 upper side switch · 0x02 lower side switch · 0x01 tip | runtime (0x80/0x40/0x20/0x02/0x01 observed); Linux `wacom_bpt_pen` (all bits) |
| 2–3 | x, little-endian, 0–14720 | runtime: top-left mark → x 0, bottom-right → 14,676 |
| 4–5 | y, little-endian, 0–9200 | runtime: top-left → y ≈180, bottom-right → 9,200 |
| 6–7 | pressure, little-endian, 10-bit (0–1023) | runtime max 914; `INTUOS_MAX_PRESSURE_POINTS` assert ev_5c43f0f2… |
| 8 | hover distance (higher = closer) | runtime 0–35 |
| 9 | 0 | runtime |

Observed flag values: `00` out, `80` in range only, `d0` far hover (proximity, not ready —
coordinates coarse, consecutive samples jump thousands of units), `f0` hover, `f1` tip,
`f2` lower switch, `f3` lower switch + tip.

Cross-check: Linux `drivers/hid/wacom_wac.c` — `wacom_features_0xDD = { "Wacom Bamboo Connect",
14720, 9200, 1023, 31, BAMBOO_PT, WACOM_INTUOS_RES, WACOM_INTUOS_RES }`.

## Other reports

- 0xC0 (10 bytes): wireless/status; wired reads `c0 00 … 00 01`.
- 0x07: version report (pen fw byte 3/4, touch fw byte 6/7) — static only.
- 0x03: tablet controls (byte 1 = 0x80) — CTL-470 has no ExpressKeys; not observed.

## Orientation

Cable on the left = default orientation; no axis inversion (runtime, `shared/testdata/topleft.hex`).

## Unverified

- Upper side switch (0x04): three presses during calibration produced no 0x04 bit.
  Mapped per decompilation/Linux; may be a worn switch or different pen.
- Eraser (0x08): CTL-470 pen has no eraser end; handled for completeness.
