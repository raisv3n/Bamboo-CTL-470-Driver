# BambooDriver — Linux (probably not needed)

The mainline kernel's `hid-wacom` driver already supports the CTL-470 (`USB_DEVICE_WACOM(0xDD)`),
including the switch to tablet mode and pressure. Check on the Linux machine first:

```sh
lsusb | grep 056a:00dd
sudo libinput list-devices | grep -A8 -i wacom
```

If the tablet shows up as a Wacom pen device, it already works; use the desktop's tablet settings.
Record the result (distro, kernel, what worked) in `../docs/port-notes/` either way.

Only if it does not work, see `../docs/porting.md#linux` for a user-space port (hidraw + uinput),
validated against `../shared/testdata`. CI would go in `.github/workflows/linux.yml`
(paths `linux/**`, `shared/**`; tag `linux-v*`; asset `BambooDriver-linux.tar.gz`).
