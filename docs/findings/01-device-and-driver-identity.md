# 01 — Device and legacy driver identity

## Device (observed, live USB/IORegistry on macOS 26.6.2, arm64)

| Field | Value |
|---|---|
| USB product name | CTL-470 (Bamboo Pen / Bamboo Connect, 3rd gen, ~2011) |
| Vendor ID | 0x056A (1386) Wacom Co.,Ltd. |
| Product ID | 0x00DD (221) |
| bcdDevice | 0x0102 |
| Link speed | 12 Mb/s (full speed) |
| Current macOS binding | `AppleUserHIDEventDriver` (generic HID mouse) |

### Interface 0 — HID report descriptor (observed)

```
05010902a10185010901a100050919012905150025019505750181029501750381010501
093009311581257f750895028106c0c0050d0901a1018502a1000600ff0901150026ff00
750895098102c0090185029501b102090185039501b102090185049501b10209018505950
1b102090185109502b102090185119510b102090185139501b102090185209501b102090
185219501b10209018514951fb102090185309501b11f090185319504b11f85c00900950
98102c0
```

Decoded:

- **Report 0x01 (input)** — Generic Desktop Mouse: 5 buttons, X/Y relative int8.
  Default/boot mode; this is why the pen moves the cursor today without pressure.
- **Report 0x02 (input, 9 bytes)** — vendor page 0xFF00 inside a Digitizer
  (0x0D/0x01) collection. Raw Wacom pen packet once the tablet is in tablet mode.
- **Feature reports** — 0x02, 0x03, 0x04, 0x05 (1 byte), 0x10 (2), 0x11 (16),
  0x13, 0x20, 0x21 (1), 0x14 (31), 0x30 (1, volatile), 0x31 (4, volatile).
- **Report 0xC0 (input, 9 bytes)** — vendor.

Inference (to confirm in the binary): the driver writes a feature report
(likely 0x02) to switch from mouse mode to Wacom tablet mode, after which
report 0x02 carries x/y/pressure/proximity/buttons.

### Interface 1 — vendor channel (observed)

```
0600ff0980a10285027508953f1500260010810185037508953f8101c0
```

Vendor page 0xFF00 usage 0x80: input reports 0x02 and 0x03, 63 bytes each.
Likely the touch channel shared with CTH (pen+touch) models; CTL-470 is pen-only.

## Legacy driver artifacts (downloaded from Wacom's official CDN)

| File | SHA-256 | Signature |
|---|---|---|
| `PenTablet_5.3.7-6.dmg` | 9de34abf8a8697e9d04a54503d5d73174e8b0ca6096d9b5011f5f7f1dd152c10 | Developer ID Installer: Wacom Technology Corp., notarized, ts 2016-10-11 |
| `WacomTablet_6.3.15-3.dmg` | eda52482d9c59bf93661ed3e333475d2039480ed9ce51cef70302e5dc8e3da58 | Developer ID Installer: Wacom Technology Corp., notarized, ts 2015-12-16 |

Sources:
- https://cdn.wacom.com/U/productsupport/Drivers/Mac/Consumer/PenTablet_5.3.7-6.dmg
- https://cdn.wacom.com/u/productsupport/drivers/mac/professional/WacomTablet_6.3.15-3.dmg

### Structure (observed, expanded with `pkgutil --expand-full`, nothing installed)

- `Pen Tablet.kext` / `Wacom Tablet.kext` contain **no code** — only an
  IOKitPersonality binding Apple's `IOHIDEventDriver` to VendorID 1386 with
  `SupportsInk = 1`.
- All protocol logic lives in user space:
  `PenTabletDriver.app/Contents/Resources/TabletDriver.app/Contents/MacOS/TabletDriver`
  (x86_64 only, SHA-256 1c86a02f018d70d5e66efe05f99a400e05fb65e8399d94537762de05c002d767),
  with model tables in `TabletDriver.rsrc`.
- Class names in strings: `CETGraphicsTablet`, `CFTGraphicsTablet`,
  `CIntuosGraphicsTablet`, `CTIGraphicsTablet`, `CUDGraphicsTablet`.

Consequence: a replacement needs no kext. A user-space IOHIDManager process
can do what TabletDriver did.

## Open questions

- [x] Exact feature report + value that enables tablet mode for PID 0x00DD — `02 02` (see 03)
- [x] Byte layout of input report 0x02 (x, y, pressure, proximity, tool, buttons) — see 03
- [x] Logical max x/y and pressure for CTL-470 — 14720 × 9200, 1023 (see 03)
- [x] Which `C*GraphicsTablet` class handles PID 0x00DD — `CCT2GraphicsTablet` (see 02)
