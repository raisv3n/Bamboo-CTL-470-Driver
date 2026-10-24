# CTL-470 protocol and driver behaviour (platform-neutral)

The single source of truth for every port. Code-level reference: `shared/reference/bamboo_reference.py`.
Evidence for each fact: `docs/findings/01–03`.

## Device

| | |
|---|---|
| USB vendor / product | 0x056A / 0x00DD ("CTL-470", Bamboo Pen / Bamboo Connect, 2011) |
| Speed | USB full speed (12 Mb/s) |
| Interface 0 | HID: mouse (report 0x01), digitizer collection with pen report 0x02, feature reports 0x02–0x31, status 0xC0 |
| Interface 1 | HID vendor page 0xFF00, 63-byte reports 0x02/0x03 — touch channel on CTH models; unused on CTL-470 |
| Active area | 0–14720 × 0–9200 (100 units ≈ 1 mm), cable on the left = normal orientation |
| Pressure | 10-bit, 0–1023 |

Interface 0 report descriptor (hex) is in `docs/findings/01-device-and-driver-identity.md`.

## 1. Switch to tablet mode

The tablet powers up in **mouse mode** (relative report 0x01, no pressure).
Send a HID **SET_REPORT / feature** on interface 0:

| Mode | Report ID | Payload (incl. report ID) |
|---|---|---|
| Tablet ("Wacom") | 0x02 | `02 02` |
| Mouse ("HID") | 0x02 | `02 01` |

- Retry up to 6 times (the original driver does; ~50 ms apart is fine).
- Re-send on every attach and after system wake: the tablet reverts to mouse mode after USB reset.
- Send `02 01` on clean shutdown so the tablet stays usable as a mouse without the driver.
- GET_REPORT of 0x02 is **not** a reliable readback (returns `02 01` in either mode). Tablet mode is
  recognisable by report 0xC0 arriving about every 5 s and report 0x01 stopping.

## 2. Pen report 0x02 (10 bytes)

| Byte | Content |
|---|---|
| 0 | 0x02 |
| 1 | flags: `0x80` in range · `0x40` proximity · `0x20` ready · `0x08` eraser · `0x04` upper side switch · `0x02` lower side switch · `0x01` tip |
| 2–3 | x, little-endian — valid only when `0x40` |
| 4–5 | y, little-endian — valid only when `0x40` |
| 6–7 | pressure, little-endian, mask to 10 bits — valid only when `0x20` |
| 8 | hover distance (larger = closer, 0–~35) |
| 9 | 0 |

Typical flag bytes: `00` gone · `80` in range, no position · `d0` far hover (position coarse) ·
`f0` hover · `f1` tip down · `f2` lower switch · `f3` lower switch + tip.

Other reports on interface 0: 0xC0 status (wired: `c0 00 … 00 01`), 0x07 firmware versions,
0x03 tablet controls (not used by CTL-470). Ignore them.

## 3. Driver behaviour

These rules made the pen feel right during testing; ports should reproduce them
(`events` mode of the reference script is the executable spec).

1. **Presence** — the pen is present only when *proximity and ready* (`flags & 0x60 == 0x60`).
   Far-hover packets (`d0`) have coordinates that jump thousands of units; do not move the cursor on them.
   On leaving presence: release any held buttons, then signal proximity-exit, then reset filters.
2. **Smoothing** — One Euro filter on x and y independently, in tablet units:
   `min_cutoff = 1.0 Hz`, `beta = 0.02`, `d_cutoff = 1.0 Hz`, dt floor 1 ms. Reset on presence change.
3. **Tip** — tip is down when flag `0x01` is set *and* pressure > 8.
4. **Click snap** — on tip-down, hold the reported position at the touch-down point for 150 ms or
   until the pen travels ≥ 250 units (2.5 mm), whichever comes first; after that, track freely
   until tip-up. Turns tap wobble (~1 mm) into clean clicks without delaying strokes noticeably.
5. **Double-click** — consecutive tip-downs within the system double-click interval *and*
   within 300 tablet units (3 mm) increase the click count. Measure in tablet units, not pixels.
6. **Buttons** — tip → primary click; lower side switch → secondary (right) click;
   upper side switch → middle click. Only one state change is emitted per report (tip first).
7. **Mapping** — normalise x/y over the full tablet. With "keep proportions" (default on), use the
   centred tablet region whose aspect ratio matches the target screen area, clamp outside it.
   Targets: all displays (union) or main display.
8. **Pressure** — `pressure / 1023`, sent only while the tip is down (0 on hover).

## Open questions

- Upper side switch never produced `0x04` on the test pen; mapping follows the original driver and Linux.
- Tilt: not reported by this model.
