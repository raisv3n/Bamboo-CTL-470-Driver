# BambooDriver — Windows (not started)

Placeholder for the Windows port. Build it on a Windows machine and push to the same repo.

Before writing code, read:
1. `../docs/protocol.md` — device protocol and required behaviour
2. `../docs/porting.md#windows` — Windows APIs for each piece (HID digitizer collection,
   `HidD_SetFeature`, `InjectSyntheticPointerInput` with `PT_PEN`), and whether a port is needed at all
3. `../docs/port-notes/` — behaviour changes made since the last port session

Checklist:
- [ ] Try Wacom's legacy Bamboo driver first (x64 only); stop here if it works
- [ ] Probe tool: list HID collections for `VID_056A&PID_00DD`, send `02 02`, dump report 0x02
- [ ] Decoder + filter module passing `shared/testdata` golden files
- [ ] Pen injection with pressure; verify in a Windows Ink app
- [ ] Tray icon, start at login, mapping options
- [ ] `.github/workflows/windows.yml` (paths `windows/**`, `shared/**`; tag `windows-v*`;
      asset `BambooDriver-windows.zip`)
