# Windows Toolbox

A collection of 12 standalone Windows utilities. Start each tool through its
BAT launcher, or pass arguments from a terminal. There is currently no shared
desktop interface.

Use the **kebab-case `.bat` launchers in this folder**. Their implementations and
shared helpers live in `powershell/`. Windows 10/11 and Windows PowerShell 5.1
are the baseline; no additional PowerShell modules need installing.

The Windows API bridges live in `powershell/native/` as separate source files.
Keep that folder with the scripts; each bridge is compiled in memory when needed.
They handle saved Wi-Fi profiles, the temporary keep-awake request, and notifying
Windows when PATH changes. No separate build step is required.

## Coding conventions

Source lines are limited to 80 characters, including indentation.
`.editorconfig` records the formatting rules.

## First run

Double-click `add-powershell-to-path.bat` to update User PATH directly.
It directly adds `%SystemRoot%\System32\WindowsPowerShell\v1.0`, the built-in
Windows PowerShell folder. It checks that `powershell.exe` exists there and
avoids duplicate entries. There is no drive scan or search-root prompt.

For command-line setup with no prompts:

```bat
add-powershell-to-path.bat -Scope User -WhatIf
add-powershell-to-path.bat -Scope User
```

The setup launcher uses the built-in Windows PowerShell path to bootstrap.
Every other launcher calls `powershell.exe` directly through PATH; none searches
for an interpreter. The tools target Windows PowerShell for consistent access
to Windows modules. To add a separately installed PowerShell 7, use
`add-app-to-path.bat "C:\Program Files\PowerShell\7\pwsh.exe"`.

Open a **new terminal** after changing PATH. Existing terminals and parent
processes retain their environment; restart the terminal application if needed.
Machine PATH changes require an administrator terminal. User PATH changes do not.
To run these `.bat` tools by name from any directory, add this repository folder:

```bat
add-app-to-path.bat "C:\path\to\windows-toolbox"
```

## Arguments or prompts

Each interactive prompt is preceded by a short explanation of the operation.
Console results also start with a description of what is being displayed.
All console tables and lists use compact spacing: at most one blank line between
records or sections. A single blank line separates the heading from its results
and separates result blocks from any following notes.
`-AsJson` returns JSON without these descriptions.
Long-running console operations show their current step or a progress indicator.
Drive-health checks show the administrator request, active drive/SMART stage,
elapsed time, and completed-drive count. The administrator worker sends progress
back to the original terminal. Keep-awake shows elapsed and remaining time.
Unknown-duration queries use an activity indicator, not a made-up time
percentage. Progress is cleared on completion and omitted from JSON output.
Prompts ask only for missing required input. Windows-key and saved Wi-Fi tools
display results immediately; hosts opens its standard file.
PowerShell PATH setup defaults to User scope. Optional settings keep their
defaults: use flags such as `-AsJson`, `-Scope`, `-Destination`, or
`-Collision` to change them.
Wi-Fi defaults to all saved profiles; use `-Name` to select one. Hashing prompts
securely for the password. File organization prompts for its source folder.
Launchers pause before closing when used without arguments so results remain
readable, except the hosts editor. Supplying arguments skips the final pause.
Parameters use PowerShell-style names, such as `-Path`.
Paths containing spaces must be quoted. For detailed help, run this from
PowerShell, substituting the implementation filename for the tool you need:

```powershell
Get-Help .\powershell\add-app-to-path.ps1 -Detailed
```

| Launcher | Purpose | Command-line example |
| --- | --- | --- |
| `edit-hosts.bat` | Open hosts in Notepad as administrator; Windows displays UAC | `edit-hosts.bat -Path "C:\Windows\System32\drivers\etc\hosts"` |
| `add-powershell-to-path.bat` | Add the built-in Windows PowerShell folder directly to PATH | `add-powershell-to-path.bat -Scope User` |
| `add-app-to-path.bat` | Add an app's folder to PATH so its command works in any terminal | `add-app-to-path.bat "C:\Tools\app.exe"` |
| `auto-organize-files.bat` | Sort top-level files by extension | `auto-organize-files.bat -Directory "C:\Downloads" -Collision Rename` |
| `get-windows-product-key.bat` | Firmware OEM key and Windows version | `get-windows-product-key.bat -AsJson` |
| `add-app-to-startup.bat` | Add an app to launch automatically at sign-in | `add-app-to-startup.bat "C:\Tools\app.exe"` |
| `new-wordpress-hash.bat` | Generate a UTF-8 legacy PHPass hash | `new-wordpress-hash.bat -Password "example"` |
| `get-wifi-passwords.bat` | Read saved Wi-Fi keys without parsing localized text | `get-wifi-passwords.bat -Name "Home Wi-Fi"` |
| `find-port-process.bat` | Show programs owning a local TCP/UDP port | `find-port-process.bat -Port 3000` |
| `get-system-info.bat` | Show Windows, hardware, storage, and available battery information | `get-system-info.bat -BatteryReport -OpenReport` |
| `keep-awake.bat` | Temporarily prevent idle sleep | `keep-awake.bat -Minutes 30 -KeepDisplayOn` |
| `get-drive-health.bat` | Show Windows status, direct SMART readings, and available health estimates | `get-drive-health.bat -DeviceId 0` |

Use the interactive password prompt to keep a password out of command history.
Wi-Fi keys and firmware product keys are only read when you run those tools.

## Behavior and additional examples

### Port ownership

The port finder inspects local TCP connections (including listeners) and UDP
endpoints. It does not scan other machines or terminate processes. Omit `-Port`
to be prompted. An unused port returns an empty result; a process that exits
during inspection is labeled unavailable. Executable paths can be restricted.

```bat
find-port-process.bat -Port 8080 -Protocol TCP
find-port-process.bat -Port 53 -AsJson
```

### System information and batteries

Run `get-system-info.bat` without arguments to display information immediately.
It reports physical and logical CPU counts, RAM modules, graphics drivers,
physical disks, fixed-volume free space, Windows uptime, and batteries.
Console output uses compact sections, readable labels, inline units, and battery
status descriptions. Hardware-dependent data may be unavailable; missing values
are explained rather than displayed as blank fields. Use `-Verbose` for provider
errors; JSON retains the original structured fields and diagnostic details.
Battery health is full-charge capacity divided by design capacity when the
firmware exposes valid capacities, and can exceed 100% on some batteries.
Storage/RAM sizes use GiB. The tool does not install drivers or change settings.

`-BatteryReport` generates an HTML report in the current directory. Add
`-OpenReport` to open it, or `-ReportPath` to choose its destination. Existing
files are never overwritten. Report creation requires an available battery;
some Windows configurations may require an administrator terminal. The report
is optional; ordinary system information creates no report file.

```bat
get-system-info.bat -AsJson
get-system-info.bat -BatteryReport -ReportPath "C:\Temp\battery.html" -OpenReport
get-system-info.bat -BatteryReport -WhatIf
```

### Keep awake

With no arguments, prevent idle sleep until stopped with Ctrl+C or by closing
the script. `-Minutes` sets a time limit; zero means until stopped.
`-KeepDisplayOn` also prevents the display from turning off. The request belongs
to a dedicated thread and is released on exit. Saved power-plan settings are
unchanged. Explicit sleep, lid-close policies, automatic locking, and critical
battery actions are not overridden. This tool supports `-WhatIf`.

```bat
keep-awake.bat -Minutes 45
keep-awake.bat -Minutes 45 -KeepDisplayOn
```

### Drive health

Run `get-drive-health.bat` to display all physical drives immediately, including
model, capacity, media/bus type, Windows health, and operating state. Use
`-DeviceId` for the exact physical device ID shown in the list (not `C:`).

**Windows health and direct SMART health are separate.** A Windows `Healthy`
result can coexist with CrystalDiskInfo's `Caution`, including on USB drives
with reallocated sectors. Windows' wear counter can also differ from the NVMe
SMART percentage-used value. The console labels the sources explicitly and
displays `SMART health: Not checked` when no direct query has succeeded.

Direct SMART reading uses [smartmontools](https://www.smartmontools.org/)
`smartctl.exe` with JSON support. Version 7.5 is provided in
`tools/smartmontools` beside the launchers, extracted from the official release
after checking the installer SHA-256 against the WinGet manifest. Keep that
folder when moving the collection. It is resolved relative to the script,
including in an administrator session; it does not rely on the current directory
or account. No background service or system-wide installer was run. Lookup also
supports the earlier per-user portable setup, a standard Program Files install,
PATH, or an explicit `-SmartctlPath`. Upstream license and source links are in
`tools/smartmontools`. If no reader is found, the tool stops with an actionable
error; Windows-only reporting requires an explicit `-WindowsOnly`.

The BAT launcher requests administrator access through Windows UAC when needed
so USB SMART queries can succeed. Results return to the original window; JSON
output is preserved. `-WindowsOnly` skips elevation and direct SMART queries.
When invoking the PS1 directly, use `-Elevate` or an administrator terminal.
Serial-number matching maps a drive to its Windows physical-drive path.
When the mapping is ambiguous, the tool refuses the SMART query. Device
autodetection is used; some USB bridges and RAID controllers require specialized
options that this wrapper does not yet expose.

The SMART assessment flags nonzero ATA reallocated (05), pending (C5), and
uncorrectable (C6) sector counts even when the device's overall SMART check
passes. NVMe data includes percentage used, estimated endurance remaining,
critical warnings, media errors, temperature, and powered-on hours when reported.
This is a focused assessment, not a full reimplementation of CrystalDiskInfo's
vendor-specific rules. Estimated endurance remaining is not a broad guarantee
of drive health or time remaining.

`Estimated health` uses the NVMe endurance value for supported SSDs. For HDDs
identified by their reported rotation rate, it applies the six published default
weights and penalty limits in [Hard Disk Sentinel's documented data-field
method](https://www.hdsentinel.com/help/en/52_cond.html), rounded to one decimal.
The method name is shown beside the percentage. All six inputs are required;
missing inputs or failed SMART reads leave the estimate unavailable. A failed
overall SMART health check overrides the estimate to 0%. This is a transparent
software score, not a manufacturer-reported lifespan or a promise to match
Sentinel's vendor-specific modes, custom offsets, or current internal rules.
The separate `Caution`/`Bad` assessment remains visible beside the score.

When available, Windows readings include current temperature, rated maximum
temperature, estimated wear used, power-on hours, and uncorrected read/write
errors. A rated maximum of zero is treated as an unsupported placeholder.
Missing readings remain `Not reported`, not zero. A reported wear value
of 100% means the estimated wear limit has been reached; it is not a percentage
of remaining life. Some drives/controllers expose no counters, and some require
an administrator terminal. Access failures keep the basic drive status visible;
use `-Verbose` for technical details. JSON keeps numeric readings, nulls for
missing fields, and counter-access diagnostics.

This is a read-only report, not a repair tool or prediction of remaining life.
`Healthy` means the current status reported by Windows. Reported warnings do
not turn a successful query into a script failure. Unknown device IDs and failed
drive enumeration return exit code 1.

```bat
get-drive-health.bat
get-drive-health.bat -DeviceId 0
get-drive-health.bat -AsJson
get-drive-health.bat -WindowsOnly
get-drive-health.bat -SmartctlPath "C:\Program Files\smartmontools\bin\smartctl.exe"
```

References: [Windows physical drive status](https://learn.microsoft.com/en-us/powershell/module/storage/get-physicaldisk),
[reliability counter definitions](https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/msft-storagereliabilitycounter),
[smartctl options and exit bits](https://github.com/smartmontools/smartmontools/blob/main/src/smartctl.8.in),
and [CrystalDiskInfo health rules](https://crystalmark.info/en/software/crystaldiskinfo/crystaldiskinfo-health-status/).

### File organization

The default destination is `AutoSort` inside the chosen source. Existing names
receive numbered suffixes; `-Collision Skip` leaves collisions at the source.
Files are never overwritten. Unrecognized extensions and subfolders are left
alone. Failed moves are reported and cause exit code 1.

```bat
auto-organize-files.bat -Directory "C:\Downloads" -Destination "D:\Sorted" -WhatIf
```

### Add an app to PATH

Run `add-app-to-path.bat` and enter an app executable or its folder. Adding an
executable adds its containing folder, so you can run the app by command name
from any terminal. There is no action menu. You can also supply the path directly.
Executable inputs support `.exe`, `.com`, `.bat`, and `.cmd`; a folder input is
useful for a directory containing multiple tools. The folder is added once,
without replacing existing PATH entries or changing the registry value type.

The default is **User PATH** (your account). `-Scope Machine` targets **System
PATH** (all users) and requires an administrator terminal. Open a new terminal
after adding an app. To inspect the selected PATH without changing it, use the
secondary `-ShowPath` option. This tool adds entries; it does not remove them.

```bat
add-app-to-path.bat "C:\Program Files\My App\app.exe"
add-app-to-path.bat -Path "C:\Tools" -WhatIf
add-app-to-path.bat -ShowPath
add-app-to-path.bat -ShowPath -Scope Machine
```

### Add an app to startup

Run `add-app-to-startup.bat` and enter an executable. It adds the app to the
current user's Run registry key so it opens automatically at sign-in. There is
no action menu. The entry name defaults to the executable's name; `-Name` and
`-Arguments` are optional. Executable paths are quoted, and existing entries
with the same name are not overwritten. `-Scope Machine` adds the app for all
users and requires an administrator terminal. To start a script, supply its
interpreter as `-Path` and the script path in `-Arguments`.

The secondary `-List` option displays existing startup entries without changing
them; `-List -AsJson` returns structured data. Listing includes Startup folder
files, Run/RunOnce registry values, and boot/logon tasks. It is not an inventory
of every Windows startup mechanism or Task Manager's enabled/disabled state.
This tool adds apps or lists entries; it does not remove or edit existing entries.

```bat
add-app-to-startup.bat "C:\Program Files\My App\app.exe"
add-app-to-startup.bat -Path "C:\Tools\app.exe" -Name "My App" -WhatIf
add-app-to-startup.bat -List
add-app-to-startup.bat -List -AsJson
```

Empty startup lists are serialized as `[]` in JSON mode.

### Information and passwords

Firmware OEM keys may be absent on digital-license systems; they are not
necessarily the currently installed product key.

The hash tool generates legacy `$P$` PHPass hashes with UTF-8 passwords and a
cryptographic random salt for compatibility. Use WordPress's own password tools
for normal account management.

Wi-Fi retrieval uses the native WLAN API. Profile names and passwords containing
colons, commas, Unicode, or exclamation marks are preserved. Run as administrator
if Windows restricts access to cleartext keys. Open/enterprise profiles may not
have a stored shared key. The tool creates no temporary credential files.

```bat
get-wifi-passwords.bat -All -AsJson
```

## Preview and exit codes

Tools that change files or settings support `-WhatIf` to preview and `-Confirm`
to request confirmation. `edit-hosts` previews opening the editor; edits made
inside Notepad remain under your control. Information tools return success as
0 and failures as 1. The launchers preserve the script exit code.
Wi-Fi retrieval also returns 1 when a selected profile's key cannot be retrieved;
profiles without a shared key, such as open networks, are reported normally.

## Original names

| Previous file | Replacement launcher |
| --- | --- |
| `AutoSortFiles.bat` | `auto-organize-files.bat` |
| `GetWindowsProductKey.bat` | `get-windows-product-key.bat` |
| `pathset.bat` | `add-app-to-path.bat` |
| `startman.ps1` | `add-app-to-startup.bat` |
| `WifiPasswordReveal-exp.bat` | `get-wifi-passwords.bat` |
| `wphash.ps1` | `new-wordpress-hash.bat` |

Historical source credits: the previous Wi-Fi batch file credited Elias
Bachaalany / Batchography, and the previous startup script credited GitHub
Copilot (MIT). The replacement implementations were rewritten for this
collection.

References: [Windows WLAN API](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/),
[WordPress password hashing](https://developer.wordpress.org/reference/functions/wp_hash_password/).
