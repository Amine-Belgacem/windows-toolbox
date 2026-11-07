<# .SYNOPSIS
Show Windows, CPU, RAM, GPU, storage, and available battery information.
.DESCRIPTION
Use -BatteryReport to generate an HTML report, and -OpenReport to open it.
An existing report is never overwritten. No arguments displays information
without prompting or generating files. Unsupported optional data is reported.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$BatteryReport,
    [string]$ReportPath,
    [switch]$OpenReport,
    [switch]$AsJson
)

. "$PSScriptRoot\common.ps1"

function Get-OptionalSystemData {
    param(
        [string]$ClassName,
        [string]$Namespace = 'root/cimv2'
    )

    if (-not $AsJson) {
        $labels = @{
            Win32_Processor = 'processors'
            Win32_PhysicalMemory = 'RAM modules'
            Win32_VideoController = 'graphics'
            Win32_DiskDrive = 'physical disks'
            Win32_LogicalDisk = 'disk space'
            Win32_Battery = 'battery status'
            BatteryStaticData = 'battery design capacity'
            BatteryFullChargedCapacity = 'battery charge capacity'
        }
        $label = $ClassName
        if ($labels.ContainsKey($ClassName)) {
            $label = $labels[$ClassName]
        }
        Write-Progress -Id 75 -Activity 'Collecting system information' `
            -Status "Reading $label..." -PercentComplete -1
    }
    try {
        Get-CimInstance -Namespace $Namespace -ClassName $ClassName
    }
    catch {
        $message = "${ClassName}: $($_.Exception.Message)"
        $script:unavailable.Add($message)
        Write-Verbose $message
    }
}

function ConvertTo-BatteryHealth {
    param(
        [double]$Design,
        [double]$Full
    )

    # Firmware uses 0 or 0xffffffff for unknown capacity on some systems.
    if ($Design -le 0 -or $Full -le 0 -or $Design -eq 4294967295 -or $Full -eq
        4294967295) {
        return $null
    }
    return [math]::Round(100 * $Full / $Design, 1)
}

function Write-SystemRow {
    param(
        [string]$Label,
        $Value
    )

    $text = ([string]$Value -replace '\s+', ' ').Trim()
    if (-not $text) {
        $text = 'Not available'
    }
    $prefix = '  {0,-16} : ' -f $Label
    # Wrap explicitly so narrow consoles retain alignment rather than splitting
    # labels.
    $width = Get-ConsoleWidth -Minimum 1 -Maximum 96
    $available = [math]::Max(12, $width - $prefix.Length)
    while ($text.Length -gt $available) {
        $cut = $text.LastIndexOf(' ', $available)
        if ($cut -lt 1) {
            $cut = $available
        }
        Write-Host ($prefix + $text.Substring(0, $cut))
        $text = $text.Substring($cut).TrimStart()
        $prefix = ' ' * $prefix.Length
    }
    Write-Host ($prefix + $text)
}

function Write-SystemSection {
    param(
        [string]$Title
    )

    Write-Host ''
    Write-Host $Title.ToUpperInvariant()
}

function Format-SystemSize {
    param(
        $Value
    )

    if ($null -eq $Value -or [double]$Value -le 0) {
        return 'Not available'
    }
    return ('{0:0.##} GiB' -f [double]$Value)
}

function Write-ComputerSummary {
    param(
        $Info
    )

    Write-SystemSection 'System'
    Write-SystemRow 'Computer' $Info.Computer.Name
    Write-SystemRow 'Device' (
        "$($Info.Computer.Manufacturer) $($Info.Computer.Model)").Trim()
    Write-SystemRow 'Windows' $Info.Windows.Edition
    Write-SystemRow 'Version' `
        "$($Info.Windows.Version) (build $($Info.Windows.Build))"
    Write-SystemRow 'Last boot' $Info.Windows.LastBoot.ToString(
        'yyyy-MM-dd HH:mm')
    $uptime = (Get-Date) - $Info.Windows.LastBoot
    Write-SystemRow 'Uptime' ("{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours,
        $uptime.Minutes)
}

function Write-ProcessorSummary {
    param(
        $Info
    )

    Write-SystemSection 'CPU'
    if (-not $Info.Processors.Count) {
        Write-SystemRow 'Processor' 'Not available'
    }
    foreach ($cpu in $Info.Processors) {
        Write-SystemRow 'Processor' $cpu.Name
        Write-SystemRow 'Cores / threads' ("$($cpu.NumberOfCores) cores / " +
            "$($cpu.NumberOfLogicalProcessors) logical processors")
        if ($cpu.MaxClockSpeed -gt 0) {
            Write-SystemRow 'Reported clock' `
                "$($cpu.MaxClockSpeed) MHz (firmware value)"
        }
    }
}

function Write-MemorySummary {
    param(
        $Info
    )

    Write-SystemSection 'Memory'
    $installed = 0
    if ($Info.MemoryModules.Count) {
        $installed = ($Info.MemoryModules | Measure-Object CapacityGB -Sum).Sum
    }
    if ($installed -gt 0) {
        Write-SystemRow 'Installed RAM' (Format-SystemSize $installed)
    }
    Write-SystemRow 'Usable RAM' (Format-SystemSize $Info.Computer.TotalRAMGB)
    $index = 0
    foreach ($module in $Info.MemoryModules) {
        $index++
        $parts = @((Format-SystemSize $module.CapacityGB))
        if ($module.SpeedMHz -gt 0) {
            $parts += "$($module.SpeedMHz) MHz"
        }
        if ($module.Manufacturer) {
            $parts += $module.Manufacturer.Trim()
        }
        Write-SystemRow "Module $index" ($parts -join ' | ')
    }
}

function Write-GraphicsSummary {
    param(
        $Info
    )

    Write-SystemSection 'Graphics'
    if (-not $Info.Graphics.Count) {
        Write-SystemRow 'Adapter' 'Not available'
    }
    foreach ($gpu in $Info.Graphics) {
        Write-SystemRow 'Adapter' $gpu.Name
        Write-SystemRow 'Driver' $gpu.DriverVersion
        if ($gpu.VideoModeDescription -match '^(\d+)\s*x\s*(\d+)') {
            Write-SystemRow 'Resolution' "$($Matches[1]) x $($Matches[2])"
        }
    }
}

function Write-StorageSummary {
    param(
        $Info
    )

    Write-SystemSection 'Storage'
    $index = 0
    foreach ($disk in $Info.Disks) {
        $index++
        Write-SystemRow "Disk $index" (
            "$($disk.Model) | $(Format-SystemSize $disk.SizeGB)")
    }
    foreach ($volume in $Info.Volumes) {
        $parts = @(("{0} free / {1} total" -f (
                    Format-SystemSize $volume.FreeGB), (
                    Format-SystemSize $volume.SizeGB)))
        if ($volume.FileSystem) {
            $parts += $volume.FileSystem
        }
        if ($volume.Label) {
            $parts += $volume.Label
        }
        Write-SystemRow ("Drive " + $volume.Drive.TrimEnd(':')) (
            $parts -join ' | ')
    }
    if (-not $Info.Disks.Count -and -not $Info.Volumes.Count) {
        Write-SystemRow 'Drives' 'Not available'
    }
}

function Write-BatterySummary {
    param(
        $Info
    )

    Write-SystemSection 'Battery'
    $states = @{
        1 = 'Discharging'
        2 = 'AC power (charge state not reported)'
        3 = 'Fully charged'
        4 = 'Low'
        5 = 'Critical'
        6 = 'Charging'
        7 = 'Charging (high)'
        8 = 'Charging (low)'
        9 = 'Charging (critical)'
        11 = 'Partially charged'
    }
    if (-not $Info.Batteries.Count) {
        Write-SystemRow 'Battery' 'Not detected or not available'
    }
    foreach ($battery in $Info.Batteries) {
        Write-SystemRow 'Name' $battery.Name
        if ($null -ne $battery.ChargePercent -and $battery.ChargePercent -le
            100) {
            Write-SystemRow 'Charge' "$($battery.ChargePercent)%"
        }
        $state = 'Not reported'
        if ($null -ne $battery.StatusCode -and $states.ContainsKey(
                [int]$battery.StatusCode)) {
            $state = $states[[int]$battery.StatusCode]
        }
        Write-SystemRow 'Power status' $state
        $details = $battery
        $matching = @($Info.BatteryCapacity | Where-Object {
                $_.Name -eq $battery.Name
            })
        if ($matching.Count -eq 1) {
            $details = $matching[0]
        }
        elseif ($Info.Batteries.Count -eq 1 -and
            $Info.BatteryCapacity.Count -eq 1) {
            $details = $Info.BatteryCapacity[0]
        }
        if ($null -ne $details.HealthPercent) {
            Write-SystemRow 'Health' `
                "$($details.HealthPercent)% of original capacity"
            Write-SystemRow 'Capacity' (
                "{0:N0} / {1:N0} mWh (full charge / design)" -f `
                    $details.FullChargeCapacityMWh, $details.DesignCapacityMWh)
        }
        else {
            Write-SystemRow 'Health' 'Not reported by battery firmware'
        }
    }
    if ($Info.BatteryReport) {
        Write-SystemRow 'Full report' $Info.BatteryReport
    }
    elseif ($Info.Batteries.Count) {
        Write-SystemRow 'Full report' (
            'Run with -BatteryReport -OpenReport for the Windows ' +
            'battery report.')
    }
}

function Write-SystemNotes {
    param(
        $Info
    )

    $otherUnavailable = @($Info.UnavailableSections | Where-Object {
            $_ -notmatch '^Battery(StaticData|FullChargedCapacity):'
        } | ForEach-Object {
            ($_ -split ':', 2)[0]
        })
    if ($otherUnavailable.Count) {
        Write-SystemSection 'Notes'
        $labels = @{
            Win32_Processor = 'CPU'
            Win32_PhysicalMemory = 'RAM modules'
            Win32_VideoController = 'graphics'
            Win32_DiskDrive = 'physical disks'
            Win32_LogicalDisk = 'disk space'
            Win32_Battery = 'battery'
        }
        $names = @($otherUnavailable | ForEach-Object {
                if ($labels.ContainsKey($_)) {
                    $labels[$_]
                }
                else {
                    'additional hardware'
                }
            } | Select-Object -Unique)
        Write-SystemRow 'Unavailable' ($names -join ', ')
        Write-SystemRow 'Diagnostics' 'Use -Verbose for technical details.'
    }
}

function Write-SystemSummary {
    param(
        $Info
    )

    Write-Host 'System information: Windows, hardware, storage and battery.'
    Write-ComputerSummary $Info
    Write-ProcessorSummary $Info
    Write-MemorySummary $Info
    Write-GraphicsSummary $Info
    Write-StorageSummary $Info
    Write-BatterySummary $Info
    Write-SystemNotes $Info
}

function Get-SystemInformation {
    param()

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    $processors = @(Get-OptionalSystemData Win32_Processor |
            Select-Object Name, NumberOfCores, NumberOfLogicalProcessors,
            MaxClockSpeed)
    $memory = @(Get-OptionalSystemData Win32_PhysicalMemory | ForEach-Object {
            [pscustomobject]@{
                Slot = $_.DeviceLocator
                CapacityGB = [math]::Round($_.Capacity / 1GB, 2)
                SpeedMHz = $_.Speed
                Manufacturer = $_.Manufacturer
            }
        })
    $graphics = @(Get-OptionalSystemData Win32_VideoController |
            Select-Object Name, DriverVersion, VideoModeDescription)
    $disks = @(Get-OptionalSystemData Win32_DiskDrive | ForEach-Object {
            [pscustomobject]@{
                Model = $_.Model
                Interface = $_.InterfaceType
                SizeGB = [math]::Round($_.Size / 1GB, 2)
            }
        })
    $volumes = @(Get-OptionalSystemData Win32_LogicalDisk |
            Where-Object DriveType -eq 3 | ForEach-Object {
                [pscustomobject]@{
                    Drive = $_.DeviceID
                    Label = $_.VolumeName
                    FileSystem = $_.FileSystem
                    SizeGB = [math]::Round($_.Size / 1GB, 2)
                    FreeGB = [math]::Round($_.FreeSpace / 1GB, 2)
                }
            })
    $batteries = @(Get-OptionalSystemData Win32_Battery | ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                ChargePercent = $_.EstimatedChargeRemaining
                StatusCode = $_.BatteryStatus
                DesignCapacityMWh = $_.DesignCapacity
                FullChargeCapacityMWh = $_.FullChargeCapacity
                HealthPercent =
                ConvertTo-BatteryHealth $_.DesignCapacity $_.FullChargeCapacity
            }
        })
    $capacity = @()
    if ($batteries.Count) {
        $designs = @(Get-OptionalSystemData BatteryStaticData 'root/wmi')
        $fullCharges = @(
            Get-OptionalSystemData BatteryFullChargedCapacity 'root/wmi')
        foreach ($design in $designs) {
            $full = @($fullCharges |
                    Where-Object InstanceName -eq $design.InstanceName)
            if ($full.Count -ne 1) {
                continue
            }
            $health =
            ConvertTo-BatteryHealth $design.DesignedCapacity `
                $full[0].FullChargedCapacity
            $capacity += [pscustomobject]@{
                Instance = $design.InstanceName
                Name = $design.DeviceName
                DesignCapacityMWh = $design.DesignedCapacity
                FullChargeCapacityMWh = $full[0].FullChargedCapacity
                HealthPercent = $health
            }
        }
    }
    [pscustomobject]@{
        Computer = [pscustomobject]@{
            Name = $env:COMPUTERNAME
            Manufacturer = $computer.Manufacturer
            Model = $computer.Model
            TotalRAMGB = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
        }
        Windows = [pscustomobject]@{
            Edition = $os.Caption
            Version = $os.Version
            Build = $os.BuildNumber
            LastBoot = $os.LastBootUpTime
            UptimeHours = [math]::Round(((Get-Date) -
                    $os.LastBootUpTime).TotalHours, 2)
        }
        Processors = $processors
        MemoryModules = $memory
        Graphics = $graphics
        Disks = $disks
        Volumes = $volumes
        Batteries = $batteries
        BatteryCapacity = $capacity
        BatteryReport = $null
        UnavailableSections = @($script:unavailable.ToArray())
    }
}

function Get-BatteryReportPath {
    param(
        [string]$ReportPath
    )

    if (-not $ReportPath) {
        $ReportPath = Join-Path $PWD.Path ("battery-report-{0}-{1}.html" -f (
                Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid(
            ).ToString('N').Substring(0, 8))
    }
    $ReportPath = Get-NormalizedPath $ReportPath -Literal
    if ([IO.Path]::GetExtension($ReportPath) -ine '.html') {
        throw 'The battery report path must end in .html.'
    }
    if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($ReportPath))) {
        throw 'The report destination folder does not exist.'
    }
    if (Test-Path -LiteralPath $ReportPath) {
        throw "The report path already exists: $ReportPath"
    }

    return $ReportPath
}

function Export-BatteryReport {
    param(
        [string]$ReportPath
    )

    # Generate into a unique folder first, then publish with File.Move (no
    # overwrite).
    $reportTemp = Join-Path ([IO.Path]::GetTempPath()) (
        'quick-scripts-battery-' + [guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($reportTemp)
    try {
        $temporaryFile = Join-Path $reportTemp 'battery-report.html'
        if (-not $AsJson) {
            Write-Progress -Id 75 -Activity 'Collecting system information' `
                -Status 'Generating the Windows battery report...' `
                -PercentComplete -1
        }
        $diagnostic = @(
            & "$env:SystemRoot\System32\powercfg.exe" /batteryreport /output `
                $temporaryFile 2>&1)
        if ($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($temporaryFile)) {
            throw ("Windows could not generate a battery report: " +
                "$($diagnostic -join ' ')")
        }
        [IO.File]::Move($temporaryFile, $ReportPath)
    }
    finally {
        # Only remove files inside this run's unique, explicitly validated temp
        # folder.
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
            '\') + '\'
        $resolvedTemp = [IO.Path]::GetFullPath($reportTemp)
        if ($resolvedTemp.StartsWith($tempRoot,
                [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName(
                $resolvedTemp) -like 'quick-scripts-battery-*') {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
    }
}

try {
    if (($ReportPath -or $OpenReport) -and -not $BatteryReport) {
        throw 'Use -BatteryReport together with -ReportPath or -OpenReport.'
    }
    if (-not $AsJson) {
        Write-Host ('Collecting Windows, hardware, storage and battery ' +
            'information...')
    }

    # Optional providers append diagnostics for this report run only.
    $script:unavailable = New-Object 'System.Collections.Generic.List[string]'
    $result = Get-SystemInformation
    if ($BatteryReport) {
        if (-not $result.Batteries.Count) {
            throw 'No battery is available for a battery report.'
        }
        $path = Get-BatteryReportPath $ReportPath
        if ($PSCmdlet.ShouldProcess($path, 'Generate Windows battery report')) {
            Export-BatteryReport $path
            $result.BatteryReport = $path
            $open = $OpenReport -and $PSCmdlet.ShouldProcess(
                $path, 'Open battery report in the default browser'
            )
            if ($open) {
                Start-Process -FilePath $path
            }
        }
    }

    if ($AsJson) {
        Write-Result $result -AsJson
    }
    else {
        Write-Progress -Id 75 -Activity 'Collecting system information' `
            -Completed
        Write-Host ''
        Write-SystemSummary $result
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
finally {
    if (-not $AsJson) {
        Write-Progress -Id 75 -Activity 'Collecting system information' `
            -Completed
    }
}
