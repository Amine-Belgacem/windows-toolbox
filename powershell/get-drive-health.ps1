<# .SYNOPSIS
Show physical drive health from Windows and direct SMART readings.
.DESCRIPTION
No arguments displays all drives without prompting. -DeviceId selects an exact
physical device ID (not a drive letter). Direct SMART readings use optional
smartctl.exe in tools/smartmontools beside the launchers, the portable setup,
Program Files, PATH, or -SmartctlPath.
The BAT launcher uses -Elevate for administrator access when needed.
-WindowsOnly skips direct SMART queries and elevation.
Windows health and counters are not a substitute for SMART attributes.
This performs no repairs, self-tests, or write tests.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$DeviceId,
    [switch]$AsJson,
    [string]$SmartctlPath,
    [switch]$WindowsOnly,
    [switch]$Elevate,
    [Parameter(DontShow = $true)]
    [string]$ProgressFile
)

. "$PSScriptRoot\common.ps1"

function Get-DriveValue {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }
    return $null
}

function Test-DriveAccessDenied {
    param(
        $Record
    )

    if ($Record.Exception -is [UnauthorizedAccessException] -or
        $Record.CategoryInfo.Category -eq 'PermissionDenied') {
        return $true
    }
    $native = Get-DriveValue $Record.Exception 'NativeErrorCode'
    return $null -ne $native -and [string]$native -eq 'AccessDenied'
}

function Format-DriveCounter {
    param(
        $Value,
        [string]$Unit = ''
    )

    if ($null -eq $Value) {
        return 'Not reported'
    }
    return ("$Value $Unit").TrimEnd()
}

function Write-DriveStep {
    param(
        [string]$Text,
        [int]$Completed = 0,
        [int]$Total = 0
    )

    if ($ProgressFile) {
        try {
            $update = @{
                Text = $Text
                Completed = $Completed
                Total = $Total
            } | ConvertTo-Json -Compress
            [IO.File]::WriteAllText($ProgressFile, $update,
                [Text.Encoding]::UTF8)
        }
        catch {
            Write-Verbose "Could not update progress: $($_.Exception.Message)"
        }
    }
    elseif (-not $AsJson) {
        Write-Host $Text
        $percent = -1
        if ($Total -gt 0) {
            $percent = [int](100.0 * $Completed / $Total)
        }
        Write-Progress -Id 71 -Activity 'Checking drive health' -Status `
            $Text -PercentComplete $percent
    }
}

function Find-Smartctl {
    param(
        [string]$Path,
        [string]$ScriptDirectory = $PSScriptRoot
    )

    if ($Path) {
        $file = Get-Item -LiteralPath $Path
        if ($file.PSIsContainer -or $file.Extension -ine '.exe') {
            throw 'SmartctlPath must identify smartctl.exe.'
        }
        return $file.FullName
    }
    foreach ($candidate in @(
            (Join-Path $ScriptDirectory '..\tools\smartmontools\smartctl.exe'),
            (Join-Path $env:LOCALAPPDATA `
                'QuickScripts\smartmontools\smartctl.exe'),
            (Join-Path $env:ProgramFiles 'smartmontools\bin\smartctl.exe')
        )) {
        if ([IO.File]::Exists($candidate)) {
            return $candidate
        }
    }
    $command =
    Get-Command smartctl.exe -CommandType Application -ErrorAction `
        SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }
    return $null
}

function Get-HddHealthEstimate {
    param(
        [array]$Attributes
    )

    # Published default "Analyse data field" weights, not HDSentinel's
    # vendor-specific mode.
    # https://www.hdsentinel.com/help/en/52_cond.html
    $rules = @(
        @{
            Id = 5
            Weight = 1.0
            Limit = 70.0
        }, @{
            Id = 7
            Weight = 0.5
            Limit = 20.0
        },
        @{
            Id = 10
            Weight = 3.0
            Limit = 60.0
        }, @{
            Id = 196
            Weight = 0.6
            Limit = 30.0
        },
        @{
            Id = 197
            Weight = 0.6
            Limit = 48.0
        }, @{
            Id = 198
            Weight = 1.0
            Limit = 70.0
        }
    )
    $score = 100.0
    $missing = @()
    foreach ($rule in $rules) {
        $matchingRecords = @($Attributes | Where-Object {
                [int](Get-DriveValue $_ 'id') -eq $rule.Id
            })
        $raw = $null
        if ($matchingRecords.Count -eq 1) {
            $rawRecord = Get-DriveValue $matchingRecords[0] 'raw'
            $raw = Get-DriveValue $rawRecord 'value'
        }
        if ($null -eq $raw) {
            $missing += $rule.Id
            continue
        }
        $count = [uint64]$raw -band 65535
        $penalty = [math]::Min([double]$rule.Limit, [double]$count *
            [double]$rule.Weight)
        $score *= (100.0 - $penalty) / 100.0
    }
    $percent = $null
    if (-not $missing.Count) {
        $percent = [math]::Round($score, 1)
    }
    [pscustomobject]@{
        Percent = $percent
        Method = 'Documented HDS default SMART weighting (estimate)'
        MissingAttributes = @($missing)
    }
}

function Get-SmartAssessment {
    param(
        $Data,
        [int]$ExitCode
    )

    $health = 'Unknown'
    $reasons = @()
    $smart = Get-DriveValue $Data 'smart_status'
    $passed = Get-DriveValue $smart 'passed'
    $nvme = Get-DriveValue $Data 'nvme_smart_health_information_log'
    $ata = Get-DriveValue (Get-DriveValue $Data 'ata_smart_attributes') 'table'
    $rotation = Get-DriveValue $Data 'rotation_rate'
    $media = $null
    $healthEstimate = $null
    $estimateMethod = $null
    $missingEstimateAttributes = @()
    if ($null -ne $nvme) {
        $media = 'SSD'
    }
    elseif ($null -ne $rotation) {
        if ($rotation -eq 0) {
            $media = 'SSD'
        }
        elseif ($rotation -gt 0) {
            $media = 'HDD'
        }
    }
    if ($media -eq 'HDD') {
        $estimate = Get-HddHealthEstimate -Attributes @($ata)
        $healthEstimate = $estimate.Percent
        $estimateMethod = $estimate.Method
        $missingEstimateAttributes = $estimate.MissingAttributes
    }
    $reallocated = $null
    $pending = $null
    $uncorrectable = $null
    foreach ($attribute in @($ata)) {
        if ($null -eq $attribute) {
            continue
        }
        $raw = Get-DriveValue (Get-DriveValue $attribute 'raw') 'value'
        switch ([int](Get-DriveValue $attribute 'id')) {
            5 {
                $reallocated = $raw
            }
            197 {
                $pending = $raw
            }
            198 {
                $uncorrectable = $raw
            }
        }
    }
    if ($null -ne $reallocated -and $reallocated -gt 0) {
        $reasons += "$reallocated reallocated sectors"
    }
    if ($null -ne $pending -and $pending -gt 0) {
        $reasons += "$pending pending sectors"
    }
    if ($null -ne $uncorrectable -and $uncorrectable -gt 0) {
        $reasons += "$uncorrectable uncorrectable sectors"
    }
    $used = Get-DriveValue $nvme 'percentage_used'
    $remaining = $null
    if ($null -ne $used -and $used -ge 0) {
        $remaining = [math]::Max([double]0, 100.0 - [double]$used)
        if ($used -ge 100) {
            $reasons += 'NVMe estimated endurance limit reached'
        }
    }
    if ($media -eq 'SSD' -and $null -ne $remaining) {
        $healthEstimate = $remaining
        $estimateMethod =
        'NVMe estimated endurance remaining (100 - percentage used)'
    }
    $critical = Get-DriveValue $nvme 'critical_warning'
    if ($null -ne $critical -and $critical -ne 0) {
        $reasons += ('NVMe critical warning: 0x{0:X2}' -f [int]$critical)
    }
    $mediaErrors = Get-DriveValue $nvme 'media_errors'
    if ($null -ne $mediaErrors -and $mediaErrors -gt 0) {
        $reasons += "$mediaErrors NVMe media/data integrity errors"
    }
    if (($ExitCode -band 16) -ne 0) {
        $reasons += `
            'A pre-failure SMART attribute is at or below its threshold'
    }
    if (($ExitCode -band 32) -ne 0) {
        $reasons += 'SMART records an attribute below threshold in the past'
    }
    if (($ExitCode -band 64) -ne 0) {
        $reasons += 'The device error log contains records'
    }
    if (($ExitCode -band 128) -ne 0) {
        $reasons += 'The self-test history contains failures'
    }
    # smartctl exit codes are a bitmask: a SMART warning is not a failed
    # invocation.
    $readFailed = ($ExitCode -band 7) -ne 0
    if ($null -ne $passed -and $passed -eq $true -and -not $readFailed) {
        $health = 'Passed'
    }
    if ($reasons.Count) {
        $health = 'Caution'
    }
    if (($null -ne $passed -and $passed -eq $false) -or ($ExitCode -band
            8) -ne 0) {
        $health = 'Bad'
        $reasons += 'Device SMART overall-health check failed'
    }
    if ($readFailed) {
        $reasons += 'Some SMART commands failed; readings may be incomplete'
    }
    if ($readFailed) {
        $healthEstimate = $null
    }
    elseif ($health -eq 'Bad') {
        $healthEstimate = 0
        $estimateMethod = 'SMART overall-health failure'
    }
    $status = 'Checked'
    if ($readFailed) {
        $status = 'Partial'
    }
    if ($null -eq $passed -and $null -eq $nvme -and $null -eq $ata) {
        $status = 'Unavailable'
        $health = 'Not checked'
    }
    elseif ($null -eq $nvme -and $null -eq $ata -and $health -eq 'Passed') {
        $status = 'Partial'
        $health = 'Overall check passed; detailed attributes unavailable'
    }
    [pscustomobject]@{
        Status = $status
        Health = $health
        Reasons = @($reasons)
        MediaType = $media
        RotationRateRPM = $rotation
        EstimatedHealthPercent = $healthEstimate
        HealthEstimateMethod = $estimateMethod
        MissingHealthAttributes = @($missingEstimateAttributes)
        Model = Get-DriveValue $Data 'model_name'
        Serial = Get-DriveValue $Data 'serial_number'
        TemperatureC = Get-DriveValue (
            Get-DriveValue $Data 'temperature') 'current'
        PowerOnHours = Get-DriveValue (
            Get-DriveValue $Data 'power_on_time') 'hours'
        PercentageUsed = $used
        EnduranceRemainingPercent = $remaining
        ReallocatedSectors = $reallocated
        PendingSectors = $pending
        UncorrectableSectors = $uncorrectable
        NvmeMediaErrors = $mediaErrors
        CriticalWarning = $critical
    }
}

function Read-DriveSmart {
    param(
        [string]$Program,
        $Disk,
        [array]$WindowsDisks
    )

    $serial = [string](Get-DriveValue $Disk 'SerialNumber')
    $matchingRecords = @()
    if ($serial.Trim()) {
        $matchingRecords = @($WindowsDisks | Where-Object {
                $candidate = [string](Get-DriveValue $_ 'SerialNumber')
                $candidate.Trim() -and ($candidate -replace '\s', '') -ieq (
                    $serial -replace '\s', '')
            })
    }
    # Storage Spaces device IDs and Windows physical-drive numbers can differ.
    # Never query a guessed /dev/pdN and risk assigning another drive's SMART
    # data.
    if ($matchingRecords.Count -ne 1) {
        throw ('Cannot safely map this drive to a Windows physical ' +
            'drive by serial number.')
    }
    $index = Get-DriveValue $matchingRecords[0] 'Index'
    if ($null -eq $index -or [string]$index -notmatch '^\d+$') {
        throw 'Windows did not report a valid physical drive number.'
    }
    $arguments = @('-a', '-j', "/dev/pd$index")
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $Program @arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($code -lt 0 -or $code -gt 255) {
        throw "smartctl could not run (exit code $code)."
    }
    try {
        $data = ($output -join "`n") | ConvertFrom-Json
    }
    catch {
        throw ('smartctl did not return valid JSON. A version ' +
            'supporting -j is required.')
    }
    Get-SmartAssessment -Data $data -ExitCode $code
}

function Invoke-AdminDriveReport {
    param(
        [string]$ReaderPath,
        [string]$SelectedDevice,
        [string]$ToolScript,
        [bool]$ShowProgress = $false
    )

    $temporaryFolder = Join-Path ([IO.Path]::GetTempPath()) (
        'quick-scripts-drive-report-' + [guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($temporaryFolder)
    $outputFile = Join-Path $temporaryFolder 'report.json'
    $statusFile = Join-Path $temporaryFolder 'progress.json'
    $errorFile = Join-Path $temporaryFolder 'error.txt'
    try {
        if (-not $ToolScript) {
            $ToolScript = Join-Path $PSScriptRoot 'get-drive-health.ps1'
        }
        $config = @{
            Script = $ToolScript
            Reader = $ReaderPath
            Device = $SelectedDevice
            Output = $outputFile
            StatusFile = $null
            ErrorFile = $errorFile
        }
        if ($ShowProgress) {
            $config.StatusFile = $statusFile
        }
        $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((
                    ConvertTo-Json $config -Compress)))
        # Only Base64 is embedded in executable text; paths and arguments remain
        # JSON data.
        $worker = @'
$ErrorActionPreference = 'Stop'
$config = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(
        '__PAYLOAD__')) | ConvertFrom-Json
$parameters = @{
    AsJson = $true
    SmartctlPath = $config.Reader
}
if ($config.Device) {
    $parameters.DeviceId = $config.Device
}
if ($config.StatusFile) {
    $parameters.ProgressFile = $config.StatusFile
}
try {
    $data = @(& $config.Script @parameters 2>&1)
    $errors = @($data | Where-Object {
            $_ -is [System.Management.Automation.ErrorRecord]
        })
    if ($errors.Count) {
        $details = @($errors |
                ForEach-Object { $_.Exception.Message }) -join `
            [Environment]::NewLine
        [IO.File]::WriteAllText($config.ErrorFile, $details)
        exit 1
    }
    $json = $data -join [Environment]::NewLine
    if (-not $json.TrimStart().StartsWith('[')) {
        throw 'Administrator query returned no valid drive report.'
    }
    $null = $json | ConvertFrom-Json
    [IO.File]::WriteAllText($config.Output, $json, (
            New-Object Text.UTF8Encoding($false)))
    exit 0
}
catch {
    [IO.File]::WriteAllText($config.ErrorFile, ($_ | Out-String))
    exit 1
}
'@
        $worker = $worker.Replace('__PAYLOAD__', $payload)
        $encoded = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($worker))
        if ($ShowProgress) {
            Write-Host ('Requesting administrator access. Approve the ' +
                'Windows prompt to continue.')
            Write-Progress -Id 71 -Activity 'Checking drive health' -Status `
                'Waiting for Windows administrator approval...' `
                -PercentComplete -1
        }
        $process =
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle `
            Hidden -ArgumentList @('-NoLogo', '-NoProfile',
            '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -PassThru
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $frames = @('|', '/', '-', [string][char]92)
        $frame = 0
        $lastText = ''
        while (-not $process.HasExited) {
            if ($ShowProgress) {
                $status = $lastText
                $percent = -1
                if (-not $status) {
                    $status = 'Starting administrator drive query...'
                }
                if ([IO.File]::Exists($statusFile)) {
                    try {
                        $update = [IO.File]::ReadAllText($statusFile) |
                            ConvertFrom-Json
                        $status = $update.Text
                        if ($update.Total -gt 0) {
                            $percent = [int](100.0 * $update.Completed /
                                $update.Total)
                        }
                    }
                    catch { } `
                        # The writer may be replacing a partial JSON record.
                }
                if ($lastText -ne $status) {
                    Write-Host $status
                    $lastText = $status
                }
                $elapsed = $timer.Elapsed.ToString('mm\:ss')
                Write-Progress -Id 71 -Activity `
                    "Checking drive health $($frames[$frame % 4])" -Status `
                    "$status (elapsed $elapsed)" -PercentComplete $percent
                $frame++
            }
            Start-Sleep -Milliseconds 150
        }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0 -or -not [IO.File]::Exists($outputFile)) {
            $details = 'The administrator drive query did not complete.'
            if ([IO.File]::Exists($errorFile)) {
                $details = [IO.File]::ReadAllText($errorFile).Trim()
            }
            throw $details
        }
        $parsed = Get-Content -Raw -LiteralPath $outputFile | ConvertFrom-Json
        if ($ShowProgress) {
            Write-Host ("Drive check complete (elapsed " +
                "$($timer.Elapsed.ToString('mm\:ss'))).")
        }
        foreach ($row in @($parsed)) {
            $row
        }
    }
    finally {
        # These are the exact file and directory created above; no recursive
        # deletion.
        if ([IO.File]::Exists($outputFile)) {
            [IO.File]::Delete($outputFile)
        }
        if ([IO.File]::Exists($statusFile)) {
            [IO.File]::Delete($statusFile)
        }
        if ([IO.File]::Exists($errorFile)) {
            [IO.File]::Delete($errorFile)
        }
        if ([IO.Directory]::Exists($temporaryFolder)) {
            [IO.Directory]::Delete($temporaryFolder)
        }
        if ($ShowProgress) {
            Write-Progress -Id 71 -Activity 'Checking drive health' -Completed
        }
    }
}

function Get-DriveReliability {
    param(
        $Disk
    )

    $counter = $null
    $diagnostic = $null
    $counterStatus = 'NotReported'
    try {
        $counters = @(
            Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction Stop)
        if ($counters.Count -eq 1) {
            $counter = $counters[0]
        }
    }
    catch {
        $diagnostic = $_.Exception.Message
        $counterStatus = 'Unavailable'
        if (Test-DriveAccessDenied $_) {
            $counterStatus = 'AccessDenied'
        }
        Write-Verbose "Drive $($disk.DeviceId) counters: $diagnostic"
    }
    $values = @{}
    foreach ($field in @('Temperature', 'TemperatureMax', 'Wear',
            'PowerOnHours', 'ReadErrorsUncorrected',
            'WriteErrorsUncorrected')) {
        $values[$field] = Get-DriveValue $counter $field
    }
    # Zero is not a useful rated operating maximum and is commonly a
    # placeholder.
    if ($null -ne $values.TemperatureMax -and $values.TemperatureMax -le 0) {
        $values.TemperatureMax = $null
    }
    if (@($values.Values | Where-Object {
                $null -ne $_
            }).Count) {
        $counterStatus = 'Available'
    }

    [pscustomobject]@{
        Values = $values
        Status = $counterStatus
        Diagnostic = $diagnostic
    }
}

function Get-PhysicalDriveReport {
    param(
        $Disk,
        [string]$Reader,
        [array]$WindowsDisks,
        [bool]$OnlyWindows,
        [int]$Completed,
        [int]$Total
    )

    $label = "Drive $($Disk.DeviceId) ($($Disk.FriendlyName))"
    Write-DriveStep "$label - reading Windows reliability counters..." `
        $Completed $Total
    $reliability = Get-DriveReliability $Disk
    $values = $reliability.Values
    $counterStatus = $reliability.Status
    $diagnostic = $reliability.Diagnostic

    $health = [string](Get-DriveValue $disk 'HealthStatus')
    if (-not $health) {
        $health = 'Not reported'
    }
    $operations = @((Get-DriveValue $disk 'OperationalStatus') |
            ForEach-Object {
                [string]$_
            })
    $size = Get-DriveValue $disk 'Size'
    $sizeGiB = $null
    if ($null -ne $size -and $size -gt 0) {
        $sizeGiB = [math]::Round($size / 1GB, 2)
    }
    $smart = $null
    $smartDiagnostic = $null
    $smartMessage =
    'Not checked: smartctl.exe is not available; Windows summary only'
    if ($OnlyWindows) {
        $smartMessage = 'Not checked: Windows-only mode'
    }
    elseif ($Reader) {
        Write-DriveStep "$label - reading SMART attributes..." $Completed $Total
        try {
            $smart = Read-DriveSmart -Program $Reader -Disk $disk `
                -WindowsDisks $windowsDisks
            $smartMessage = $smart.Health
            if ($smart.Reasons.Count) {
                $smartMessage += ' - ' + ($smart.Reasons -join '; ')
            }
            if ($smart.Status -eq 'Unavailable') {
                $smartMessage += (
                    '; try an administrator terminal or check USB ' +
                    'bridge support')
            }
        }
        catch {
            $smartDiagnostic = $_.Exception.Message
            Write-Verbose "Drive $($disk.DeviceId) SMART: $smartDiagnostic"
            $smartMessage = (
                'Not checked: direct SMART query unavailable; use ' +
                '-Verbose for details')
        }
    }
    [pscustomobject]@{
        DeviceId = [string]$disk.DeviceId
        Model = [string](Get-DriveValue $disk 'FriendlyName')
        MediaType = $(if ($null -ne $smart -and $smart.MediaType) {
                $smart.MediaType
            }
            else {
                [string](Get-DriveValue $disk 'MediaType')
            })
        BusType = [string](Get-DriveValue $disk 'BusType')
        SizeGiB = $sizeGiB
        HealthStatus = $health
        OperationalStatus = $operations
        TemperatureC = $values.Temperature
        RatedMaxTemperatureC = $values.TemperatureMax
        WearPercent = $values.Wear
        PowerOnHours = $values.PowerOnHours
        UncorrectedReadErrors = $values.ReadErrorsUncorrected
        UncorrectedWriteErrors = $values.WriteErrorsUncorrected
        CounterStatus = $counterStatus
        CounterDiagnostic = $diagnostic
        Smart = $smart
        SmartSummary = $smartMessage
        SmartDiagnostic = $smartDiagnostic
    }
}

function Get-DriveReports {
    param(
        [string]$Reader,
        [string]$SelectedDevice,
        [bool]$OnlyWindows
    )

    $windowsDisks = @()
    if ($Reader) {
        Write-DriveStep 'Matching physical drives to their device paths...'
        try {
            $windowsDisks = @(Get-CimInstance -ClassName Win32_DiskDrive)
        }
        catch {
            Write-Verbose `
                "SMART drive mapping unavailable: $($_.Exception.Message)"
        }
    }

    Write-DriveStep 'Finding physical drives...'
    try {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object DeviceId)
    }
    catch {
        Write-Verbose $_.Exception.Message
        throw ('Windows could not read physical drive information. ' +
            ('Try an administrator terminal; use -Verbose for ' +
            'technical details.'))
    }
    if ($SelectedDevice) {
        $disks = @($disks | Where-Object {
                [string]$_.DeviceId -ieq $SelectedDevice
            })
        if (-not $disks.Count) {
            throw ("No physical drive matches device ID '$SelectedDevice'. " +
                'Run without -DeviceId to list available drives.')
        }
    }

    $completed = 0
    foreach ($disk in $disks) {
        $parameters = @{
            Disk = $disk
            Reader = $Reader
            WindowsDisks = $windowsDisks
            OnlyWindows = $OnlyWindows
            Completed = $completed
            Total = $disks.Count
        }
        Get-PhysicalDriveReport @parameters
        $completed++
        $label = "Drive $($disk.DeviceId) ($($disk.FriendlyName))"
        Write-DriveStep "$label - complete ($completed of $($disks.Count))" `
            $completed $disks.Count
    }
}

function Write-DriveReport {
    param(
        [array]$Rows
    )

    Write-Host `
        'Physical drive health: Windows status and direct SMART readings:'
    if (-not $rows.Count) {
        Write-Host ''
        Write-Host ('No physical drives were reported by the Windows storage ' +
            'provider.')
    }
    else {
        $rows | Format-List @{
            Label = 'Device ID'
            Expression = { $_.DeviceId }
        },
        @{
            Label = 'Drive'
            Expression = {
                if ($null -ne $_.Smart -and
                    $_.Smart.Model) { $_.Smart.Model } elseif (
                    $_.Model) { $_.Model } else {
                    'Not reported'
                }
            }
        },
        @{
            Label = 'Type / bus'
            Expression = {
                $parts = @(@($_.MediaType, $_.BusType) | Where-Object { $_ })
                if ($parts.Count) {
                    $parts -join ' / '
                }
                else {
                    'Not reported'
                }
            }
        },
        @{
            Label = 'Capacity'
            Expression = {
                Format-DriveCounter $_.SizeGiB 'GiB'
            }
        },
        @{
            Label = 'Windows health'
            Expression = { $_.HealthStatus }
        },
        @{
            Label = 'SMART health'
            Expression = { $_.SmartSummary }
        },
        @{
            Label = 'Estimated health'
            Expression = {
                if ($null -ne $_.Smart -and $null -ne
                    $_.Smart.EstimatedHealthPercent) {
                    "$($_.Smart.EstimatedHealthPercent)%"
                }
                elseif ($null -ne $_.Smart -and
                    $_.Smart.MissingHealthAttributes.Count) {
                    'Not available: required SMART attributes missing'
                }
                else {
                    'Not reported'
                }
            }
        },
        @{
            Label = 'Estimate method'
            Expression = {
                if ($null -ne $_.Smart -and
                    $_.Smart.HealthEstimateMethod) {
 `
                        $_.Smart.HealthEstimateMethod
                }
                else {
                    'Not available'
                }
            }
        },
        @{
            Label = 'Operating state'
            Expression = {
                if ($_.OperationalStatus.Count) {
                    $_.OperationalStatus -join ', '
                }
                else {
                    'Not reported'
                }
            }
        },
        @{
            Label = 'Temperature'
            Expression = {
                if ($null -ne $_.Smart -and $null -ne $_.Smart.TemperatureC) {
                    Format-DriveCounter $_.Smart.TemperatureC 'C (SMART)'
                }
                else {
                    Format-DriveCounter $_.TemperatureC 'C (Windows)'
                }
            }
        },
        @{
            Label = 'Rated max temp'
            Expression = {
                Format-DriveCounter $_.RatedMaxTemperatureC 'C'
            }
        },
        @{
            Label = 'Wear (Windows)'
            Expression = {
                if ($_.MediaType -eq 'HDD') {
                    'Not applicable to HDD lifespan'
                }
                elseif ($null -ne $_.WearPercent) {
                    "$($_.WearPercent)% reported; not direct NVMe SMART data"
                }
                else {
                    'Not reported'
                }
            }
        },
        @{
            Label = 'Wear (SMART)'
            Expression = {
                if ($_.MediaType -eq 'HDD') {
                    'Not applicable (mechanical drive)'
                }
                elseif ($null -ne $_.Smart -and $null -ne
                    $_.Smart.PercentageUsed) {
                    ("$($_.Smart.PercentageUsed)% used; " +
                    "$($_.Smart.EnduranceRemainingPercent)% " +
                    "estimated endurance remaining")
                }
                else {
                    'Not available'
                }
            }
        },
        @{
            Label = 'Sector warnings'
            Expression = {
                if ($null -eq $_.Smart) {
                    'Not checked'
                }
                elseif ($null -eq $_.Smart.ReallocatedSectors -and $null -eq
                    $_.Smart.PendingSectors -and $null -eq
                    $_.Smart.UncorrectableSectors) {
                    'Not applicable or not reported'
                }
                else {
                    'Reallocated: {0}; pending: {1}; uncorrectable: {2}' -f (
                        Format-DriveCounter $_.Smart.ReallocatedSectors), (
                        Format-DriveCounter $_.Smart.PendingSectors), (
                        Format-DriveCounter $_.Smart.UncorrectableSectors)
                }
            }
        },
        @{
            Label = 'Powered on'
            Expression = {
                if ($null -ne $_.Smart -and $null -ne $_.Smart.PowerOnHours) {
                    Format-DriveCounter $_.Smart.PowerOnHours 'hours (SMART)'
                }
                else {
                    Format-DriveCounter $_.PowerOnHours 'hours (Windows)'
                }
            }
        },
        @{
            Label = 'Read errors'
            Expression = {
                Format-DriveCounter $_.UncorrectedReadErrors 'uncorrected'
            }
        },
        @{
            Label = 'Write errors'
            Expression = {
                Format-DriveCounter $_.UncorrectedWriteErrors 'uncorrected'
            }
        },
        @{
            Label = 'Extra readings'
            Expression = {
                switch ($_.CounterStatus) {
                    AccessDenied {
                        'Access denied; try an administrator terminal'
                    }
                    Unavailable {
                        ('Unavailable from this drive/controller; ' +
                        'use -Verbose for details')
                    }
                    NotReported {
                        'Not exposed by this drive/controller'
                    }
                    default {
                        ('Available; individual readings may ' +
                        'still be unreported')
                    }
                }
            }
        } | Write-CompactOutput
    }
    Write-Host ''
    Write-Host ('Windows Healthy/OK can coexist with SMART cautions, ' +
        'including reallocated sectors.')
    Write-Host ('Direct SMART queries require smartctl and supported ' +
        'hardware, usually with administrator access.')
}

try {
    if (-not $AsJson) {
        Write-Host ('Checking physical drives and SMART health. ' +
            'This can take a few seconds...')
    }
    if ($WindowsOnly -and $SmartctlPath) {
        throw 'Use either WindowsOnly or SmartctlPath.'
    }

    $reader = $null
    if (-not $WindowsOnly) {
        $reader = Find-Smartctl $SmartctlPath
    }
    if (-not $WindowsOnly -and -not $reader) {
        throw ('SMART reader missing. Restore ' +
            'tools\smartmontools\smartctl.exe beside these scripts, ' +
            'or use -SmartctlPath. Use -WindowsOnly explicitly for a ' +
            'Windows summary without SMART checks.')
    }
    if ($reader) {
        Write-Verbose "SMART reader: $reader"
    }

    $requiresAdmin = (
        $Elevate -and -not $WindowsOnly -and $reader -and
        -not (Test-Administrator)
    )
    if ($requiresAdmin) {
        $parameters = @{
            ReaderPath = $reader
            SelectedDevice = $DeviceId
            ShowProgress = -not $AsJson
        }
        $rows = @(Invoke-AdminDriveReport @parameters)
    }
    else {
        $parameters = @{
            Reader = $reader
            SelectedDevice = $DeviceId
            OnlyWindows = $WindowsOnly.IsPresent
        }
        $rows = @(Get-DriveReports @parameters)
    }

    if ($AsJson) {
        Write-Result $rows -AsJson
    }
    else {
        Write-Progress -Id 71 -Activity 'Checking drive health' -Completed
        Write-Host ''
        Write-DriveReport $rows
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
finally {
    if (-not $AsJson) {
        Write-Progress -Id 71 -Activity 'Checking drive health' -Completed
    }
}
