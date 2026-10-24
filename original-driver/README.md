# Original Wacom driver (not in git)

Wacom's installers are copyrighted and stay out of the repository (`.gitignore`). To reproduce the
reverse-engineering setup, download them from Wacom's CDN into this folder:

| File | SHA-256 |
|---|---|
| [PenTablet_5.3.7-6.dmg](https://cdn.wacom.com/U/productsupport/Drivers/Mac/Consumer/PenTablet_5.3.7-6.dmg) | 9de34abf8a8697e9d04a54503d5d73174e8b0ca6096d9b5011f5f7f1dd152c10 |
| [WacomTablet_6.3.15-3.dmg](https://cdn.wacom.com/u/productsupport/drivers/mac/professional/WacomTablet_6.3.15-3.dmg) | eda52482d9c59bf93661ed3e333475d2039480ed9ce51cef70302e5dc8e3da58 |

Expand without installing:

```sh
hdiutil attach -nobrowse -readonly -mountpoint /tmp/pt PenTablet_5.3.7-6.dmg
pkgutil --expand-full "/tmp/pt/Install Wacom Tablet.pkg" extracted/5.3.7-6
hdiutil detach /tmp/pt
```

The protocol logic is in
`extracted/5.3.7-6/content.pkg/Payload/Library/Application Support/Tablet/PenTabletDriver.app/Contents/MacOS/PenTabletDriver`
(class `CCT2GraphicsTablet`). See `docs/findings/`.
