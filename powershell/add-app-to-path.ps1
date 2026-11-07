<# .SYNOPSIS
Add an app's folder to PATH so the app can run from any terminal.
.DESCRIPTION
Supply an executable or app folder, or omit -Path to be prompted. Defaults to
User PATH; -Scope Machine targets System PATH and requires administrator rights.
-ShowPath is the secondary, read-only option for listing PATH entries.
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Add')]
param(
    [Parameter(Position = 0, ParameterSetName = 'Add')]
    [Alias('Directory')]
    [string]$Path,
    [Parameter(Mandatory, ParameterSetName = 'Show')]
    [Alias('List')]
    [switch]$ShowPath,
    [ValidateSet('User', 'Machine')]
    [string]$Scope = 'User'
)

. "$PSScriptRoot\common.ps1"

function Get-AppPathDirectory {
    param(
        [string]$Path
    )

    $app = Get-Item -LiteralPath (Get-NormalizedPath $Path) -Force
    if ($app.PSIsContainer) {
        $directory = $app.FullName
    }
    else {
        if ($app.Extension -notin @('.exe', '.com', '.bat', '.cmd')) {
            throw ('Choose an app executable (.exe, .com, .bat, .cmd), ' +
                'or its folder.')
        }
        $directory = $app.DirectoryName
    }
    if ($directory.Contains(';')) {
        throw ('A folder containing a semicolon cannot be represented ' +
            'as one PATH entry.')
    }

    return $directory
}

try {
    $scopeLabel = 'User PATH (your account)'
    if ($Scope -eq 'Machine') {
        $scopeLabel = 'System PATH (all users)'
    }
    $state = Get-PersistentPath $Scope
    $entries = @(Get-PathEntries $state.Value)
    if ($ShowPath) {
        Write-Host "Folders in ${scopeLabel}:"
        Write-Host ''
        if ($entries.Count) {
            $entries
        }
        else {
            Write-Host 'No folders are configured in this PATH.'
        }
        exit 0
    }
    if (-not $Path) {
        Write-Host ("Add an app to $scopeLabel so you can run it from any " +
            "directory.")
        $Path = Read-Value 'App executable or app folder' -Required
    }
    $directory = Get-AppPathDirectory $Path
    if (@($entries | Where-Object {
                Test-PathEntry $_ $directory
            }).Count) {
        Write-Host "This app's folder is already in ${scopeLabel}: $directory"
        exit 0
    }
    if ($PSCmdlet.ShouldProcess($scopeLabel, "Add app folder $directory")) {
        Set-PersistentPath $state (($entries + $directory) -join ';')
        Write-Host "Added app folder to ${scopeLabel}: $directory"
        Write-Host 'Open a new terminal to run the app by its command name.'
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
