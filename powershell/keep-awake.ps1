<# .SYNOPSIS
Temporarily prevent idle sleep, optionally keeping the display on. Stop with
Ctrl+C.
.DESCRIPTION
With no arguments, stay active until stopped. -Minutes limits the duration.
The request is released on exit; the saved power plan is never modified.
This does not override manual sleep, lid-close policies, or critical battery
actions.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Alias('Minutes')]
    [ValidateRange(0, 10080)]
    [double]$DurationMinutes = 0,
    [switch]$KeepDisplayOn
)

. "$PSScriptRoot\common.ps1"

function New-AwakeSession {
    param(
        [bool]$Display
    )

    Import-NativeType 'QuickScripts.AwakeSession' 'awake-session.cs'
    return New-Object QuickScripts.AwakeSession($Display)
}

$session = $null
try {
    $description = 'Prevent idle sleep until stopped with Ctrl+C'
    if ($DurationMinutes -gt 0) {
        $description = "Prevent idle sleep for $DurationMinutes minute(s)"
    }
    if ($KeepDisplayOn) {
        $description += ' and keep the display on'
    }
    if ($PSCmdlet.ShouldProcess('This computer', $description)) {
        $session = New-AwakeSession -Display $KeepDisplayOn.IsPresent
        Write-Host "$description."
        Write-Host `
            'The temporary request will be released when this script exits.'
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $lastSecond = -1
        while ($DurationMinutes -eq 0 -or $timer.Elapsed.TotalMinutes -lt
            $DurationMinutes) {
            $second = [int][math]::Floor($timer.Elapsed.TotalSeconds)
            if ($second -ne $lastSecond) {
                $status = 'Active - elapsed ' + $timer.Elapsed.ToString(
                    'hh\:mm\:ss') + '. Ctrl+C to stop.'
                $percent = -1
                if ($DurationMinutes -gt 0) {
                    $remaining = [TimeSpan]::FromSeconds([math]::Max(
                            [double]0, $DurationMinutes * 60 -
                            $timer.Elapsed.TotalSeconds))
                    $status += ' Remaining ' + $remaining.ToString('hh\:mm\:ss')
                    $percent = [int][math]::Min([double]99, 100.0 *
                        $timer.Elapsed.TotalMinutes / $DurationMinutes)
                }
                Write-Progress -Id 74 -Activity `
                    'Keeping this computer awake' -Status $status `
                    -PercentComplete $percent
                $lastSecond = $second
            }
            Start-Sleep -Milliseconds 200
        }
        Write-Host 'The keep-awake duration has ended.'
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
finally {
    if ($null -ne $session) {
        $session.Dispose()
    }
    Write-Progress -Id 74 -Activity 'Keeping this computer awake' -Completed
}
