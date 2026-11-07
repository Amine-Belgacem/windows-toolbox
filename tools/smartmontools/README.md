# SMART reader

This folder contains the unmodified smartmontools 7.5 Windows x64 SMART reader
and drive database used by `get-drive-health.bat`.

Preserve the `tools/smartmontools/` path beneath the folder containing the BAT
launchers when moving Windows Toolbox. The drive-health script resolves this
bundled reader relative to its own location, including when run as administrator.
The bundled reader does not depend on the current directory, user profile, or
PATH.

Files were extracted from the official release installer without running its
installer or installing the smartd service. The installer SHA-256 was verified
against Microsoft's WinGet manifest:

`896337fcc253220614cf8cdbd5cf2321c5aa326a37a04160a672a281e6104c70`

`COPYING.txt` contains the upstream GPL license; `AUTHORS.txt` lists the authors.

- [Official release and source](https://github.com/smartmontools/smartmontools/releases/tag/RELEASE_7_5)
- [Corresponding source tree](https://github.com/smartmontools/smartmontools/tree/RELEASE_7_5)
- [Package provenance](package.json)
