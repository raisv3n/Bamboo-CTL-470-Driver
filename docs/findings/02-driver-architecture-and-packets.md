# 02 — Legacy driver architecture and packet routing

Target: `PenTabletDriver.app/Contents/MacOS/PenTabletDriver` from Pen Tablet 5.3.7-6
(x86_64, SHA-256 31842a918ef52ef6a7856ab73d85538a3b30183d2dfaa182115bc46cee8d7c79).
Analyzed with REA 6.7.0 + Ghidra 12.1.4. Snapshot: `PenTabletDriver-5.3.7-6.rea-snapshot` (local only, not in git).

The nested `TabletDriver.app` is only an event router (`CRouteTable`); it imports
no IOKit HID/USB APIs and is not involved in the device protocol.

## Class chain for CTL-470 (observed in decompilation)

```
CCT2GraphicsTablet            ("CT2" = 3rd-gen Bamboo, CTL/CTH-x70)
  └─ CKestrelGraphicsTablet   (MakeTabletVote delegate)
  └─ CPTKUSBGraphicsTablet    (Intuos4 "PTK" USB protocol)
pen: CCT2PressureStylusPine → CIntuosStylusTransducer → CIntuosTransducer
```

| Fact | Evidence | Type |
|---|---|---|
| `CCT2GraphicsTablet::Init` sets USB packet size to **10** bytes | ev_c3de1eb5… | observed (static) |
| `DeviceStart` = `CPTKUSBGraphicsTablet::DeviceStart` then `GetVersionReport` | ev_8693215b… | observed (static) |
| `SetHidMode` / `SetScanMode` / `SetDataRateMode` delegate to `CPTKUSBGraphicsTablet` when not wireless | ev_461c4e16…, ev_a78ab000…, ev_f1448784… | observed (static) |
| `MakeTabletVote` votes nay on 0x0d,0x30,0x31,0x2a,0x28,0x20, then defers to Kestrel | ev_1362df95… | observed (static); meaning of IDs unknown |

## `CCT2GraphicsTablet::ProcessDataPacket` routing (ev_4ee0810e…)

Byte 0 is the HID report ID.

| Report ID | Meaning | Handling |
|---|---|---|
| 0xC0 | Wireless kit status | byte 9 bit0 = connected, bit1 = battery present; byte 8 = battery (bit6 = touch switch off); bytes 5–7 = wireless ID |
| 0x07 | Version report (10 or 16 bytes) | byte 3 = pen fw major, byte 4 hi/lo nibble = pen fw minor/rev; byte 6/7 = touch fw |
| 0x03 | Tablet controls (byte 1 must be 0x80) | bytes 2.. padded to 10 → `CPTKUSBGraphicsTablet::ProcessTabletControls` |
| other (0x02) | Pen data, 10 bytes | `CPTKUSBGraphicsTablet::ProcessDataPacket` |
| empty | — | out-of-proximity |

## Pen (`CCT2PressureStylusPine`, ev_5c43f0f2…, ev_28907a0e…)

- Packets decoded as Intuos **type 0xE0** (`CIntuosTransducer::DecodeTypeE0`).
- Pressure is < 1024 (asserted `INTUOS_MAX_PRESSURE_POINTS`): 10-bit.
- Buttons: 1 = tip, 2 = barrel (lower side switch), 3 = barrel2 (upper side switch).
- Eraser is created by the generic stylus (`CreateEraserButton` exists on CT stylus).

## Live device state (observed with `macos/tools/hidprobe`, GET only)

```
feature 0x02 = 02 01     feature 0x03 = 03 00     feature 0x04 = 04 00
feature 0x13 = 13 00     feature 0x20 = 20 00     feature 0x21 = 21 00
0x05 0x10 0x11 0x14 0x30 0x31 → kIOReturnUnsupported (0xe0005000)
```

## Follow-up

Mode switch, pen report layout and coordinate range were resolved in `03-protocol-confirmed.md`.
