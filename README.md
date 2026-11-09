# Windows Toolbox

A collection of 12 standalone Windows utilities. Start each tool through its
BAT launcher, or pass arguments from a terminal. There is currently no shared
desktop interface.

Use the **kebab-case `.bat` launchers in this folder**. Their implementations and
shared helpers live in `powershell/`. Windows 10/11 and Windows PowerShell 5.1
are the baseline; no additional PowerShell modules need installing.

Keep the `powershell/` folder with the launchers. No build step is required.

## First run

If `powershell.exe` is missing from PATH, run `add-powershell-to-path.bat` to add the built-in Windows PowerShell folder to User PATH.

For command-line setup with no prompts:

```bat
add-powershell-to-path.bat -Scope User -WhatIf
add-powershell-to-path.bat -Scope User
```

To add a separately installed PowerShell 7, use
`add-app-to-path.bat "C:\Program Files\PowerShell\7\pwsh.exe"`.

Open a **new terminal** after changing PATH. Existing terminals and parent
processes retain their environment; restart the terminal application if needed.
Machine PATH changes require an administrator terminal. User PATH changes do not.
To run these `.bat` tools by name from any directory, add this repository folder:

```bat
add-app-to-path.bat "C:\path\to\windows-toolbox"
```

## Arguments or prompts

Double-click a launcher for interactive use, or pass arguments to skip prompts for supplied values. Paths containing spaces must be quoted. Use `-AsJson` for structured output.

For detailed help, substitute the tool's PowerShell filename:

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
Hardware-dependent readings may be unavailable. Use `-Verbose` for provider errors or `-AsJson` for structured readings.
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
`-KeepDisplayOn` also prevents the display from turning off. Saved power-plan settings are unchanged. Explicit sleep, lid-close policies, automatic locking, and critical
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

Direct SMART queries use the bundled `smartctl.exe` in `tools/smartmontools`; keep that folder with the launchers. Use `-SmartctlPath` for another installation or `-WindowsOnly` to skip direct SMART checks.

The BAT launcher requests administrator access when needed. When running the PS1 directly, use `-Elevate` or an administrator terminal. Some USB bridges and RAID controllers may not support the available query modes.

The report distinguishes Windows status, SMART warnings, and estimated health. NVMe estimates reflect reported endurance; supported HDD estimates use [Hard Disk Sentinel's documented method](https://www.hdsentinel.com/help/en/52_cond.html). Missing inputs leave the estimate unavailable. These are read-only observations, not a prediction of remaining life or a repair operation.

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
from any terminal. You can also supply the path directly.
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
current user's Run registry key so it opens automatically at sign-in. The entry name defaults to the executable's name; `-Name` and
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

### Information and passwords

Firmware OEM keys may be absent on digital-license systems; they are not
necessarily the currently installed product key.

The hash tool generates legacy `$P$` PHPass hashes with UTF-8 passwords and a
cryptographic random salt for compatibility. Use WordPress's own password tools
for normal account management.

Run Wi-Fi retrieval as administrator if Windows restricts access to saved keys. Open and enterprise profiles may not have a stored shared key.

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

## Credits

Historical source credits: the previous Wi-Fi batch file credited Elias
Bachaalany / Batchography, and the previous startup script credited GitHub
Copilot (MIT). The replacement implementations were rewritten for this
collection.

References: [Windows WLAN API](https://learn.microsoft.com/en-us/windows/win32/api/wlanapi/),
[WordPress password hashing](https://developer.wordpress.org/reference/functions/wp_hash_password/).
