<# .SYNOPSIS
Add built-in Windows PowerShell directly to persistent PATH, without searching.
.DESCRIPTION
Uses %SystemRoot%\System32\WindowsPowerShell\v1.0 and defaults to User scope.
Use -Scope Machine for all users or -WhatIf to preview.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('User', 'Machine')]
    [string]$Scope = 'User'
)

. "$PSScriptRoot\common.ps1"

try {
    Write-Host ("Add the built-in Windows PowerShell folder to $Scope PATH " +
        "so powershell.exe is available from any directory.")
    $directory = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0'
    if (-not [IO.File]::Exists((Join-Path $directory 'powershell.exe'))) {
        throw ("Built-in Windows PowerShell is missing from its " +
            "expected location: $directory")
    }
    $state = Get-PersistentPath $Scope
    $entries = @(Get-PathEntries $state.Value)
    if (@($entries | Where-Object {
                Test-PathEntry $_ $directory
            }).Count) {
        Write-Host ("Windows PowerShell is already in $Scope PATH. Open a " +
            "new terminal if it is not accessible yet.")
        exit 0
    }
    if ($PSCmdlet.ShouldProcess("$Scope PATH", "Add $directory")) {
        Set-PersistentPath $state (($entries + $directory) -join ';')
        Write-Host "Added Windows PowerShell to $Scope PATH: $directory"
        Write-Host 'Open a new terminal to use the updated PATH.'
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
