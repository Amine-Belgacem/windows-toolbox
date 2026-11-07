# Input, PATH persistence, and console helpers for Windows PowerShell 5.1.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Read-Value {
    param(
        [string]$Prompt,
        [string]$Default = '',
        [switch]$Required
    )

    while ($true) {
        $label = $Prompt
        if ($Default) {
            $label += " [$Default]"
        }
        $value = Read-Host $label
        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = $Default
        }
        if (-not $Required -or -not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
        Write-Host 'A value is required.'
    }
}

function Read-Selection {
    param(
        [string]$Prompt,
        [string[]]$Choices,
        [string]$Default
    )

    while ($true) {
        $value = Read-Value "$Prompt ($($Choices -join '/'))" $Default
        if ($Choices -contains $value) {
            return $value
        }
        Write-Host "Choose one of: $($Choices -join ', ')."
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $role = [Security.Principal.WindowsBuiltInRole]::Administrator
        return $principal.IsInRole($role)
    }
    finally {
        $identity.Dispose()
    }
}

function Assert-Administrator {
    if (-not (Test-Administrator)) {
        throw 'Run this launcher from an administrator terminal.'
    }
}

function Get-NormalizedPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [switch]$Literal
    )

    $expanded = $Path
    if (-not $Literal) {
        $unquoted = $Path.Trim().Trim('"')
        $expanded = [Environment]::ExpandEnvironmentVariables($unquoted)
    }
    $full = [IO.Path]::GetFullPath($expanded)
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        $full = $full.TrimEnd('\', '/')
    }
    return $full
}

# Preserve the unexpanded value and registry type when updating PATH.
function Get-PersistentPath {
    param(
        [ValidateSet('User', 'Machine')]
        [string]$Scope = 'User'
    )

    $base = [Microsoft.Win32.Registry]::CurrentUser
    $subkey = 'Environment'
    if ($Scope -eq 'Machine') {
        $base = [Microsoft.Win32.Registry]::LocalMachine
        $subkey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    }
    $key = $base.OpenSubKey($subkey, $false)
    try {
        $value = ''
        $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        if ($null -ne $key -and $key.GetValueNames() -contains 'Path') {
            $options = [Microsoft.Win32.RegistryValueOptions]::
            DoNotExpandEnvironmentNames
            $value = [string]$key.GetValue('Path', '', $options)
            $kind = $key.GetValueKind('Path')
        }
        [pscustomobject]@{
            Value = $value
            Kind = $kind
            Subkey = $subkey
            Scope = $Scope
        }
    }
    finally {
        if ($null -ne $key) {
            $key.Dispose()
        }
    }
}

function Import-NativeType {
    param(
        [string]$TypeName,
        [string]$FileName,
        [string[]]$ReferencedAssemblies
    )

    if ($TypeName -as [type]) {
        return
    }
    $path = Join-Path $PSScriptRoot "native\$FileName"
    $parameters = @{ TypeDefinition = [IO.File]::ReadAllText($path) }
    if ($ReferencedAssemblies) {
        $parameters.ReferencedAssemblies = $ReferencedAssemblies
    }
    Add-Type @parameters
}

function Send-EnvironmentChange {
    Import-NativeType 'QuickScripts.EnvironmentBroadcast' `
        'environment-broadcast.cs'

    $result = [UIntPtr]::Zero
    $null = [QuickScripts.EnvironmentBroadcast]::SendMessageTimeout(
        [IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment',
        2, 2000, [ref]$result
    )
}

function Set-PersistentPath {
    param(
        [Parameter(Mandatory)]
        $State,
        [AllowEmptyString()]
        [string]$Value
    )

    if ($State.Scope -eq 'Machine') {
        Assert-Administrator
    }
    $machine = (Get-PersistentPath Machine).Value
    $user = (Get-PersistentPath User).Value
    if ($State.Scope -eq 'Machine') {
        $machine = $Value
    }
    else {
        $user = $Value
    }
    $configured = @($machine, $user) | Where-Object { $_ }
    $combined = [Environment]::ExpandEnvironmentVariables(
        ($configured -join ';')
    )
    if ($Value.Length -gt 32766 -or $combined.Length -gt 32766) {
        throw ('The resulting PATH is too long for Windows. ' +
            'Remove unused PATH entries before retrying.')
    }
    $base = [Microsoft.Win32.Registry]::CurrentUser
    if ($State.Scope -eq 'Machine') {
        $base = [Microsoft.Win32.Registry]::LocalMachine
    }
    $key = $base.CreateSubKey($State.Subkey)
    try {
        $key.SetValue('Path', $Value, $State.Kind)
    }
    finally {
        $key.Dispose()
    }
    $env:Path = $combined
    Send-EnvironmentChange
}

function Get-PathEntries {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    foreach ($entry in ($Value -split ';')) {
        if (-not [string]::IsNullOrWhiteSpace($entry)) {
            $entry
        }
    }
}

function Test-PathEntry {
    param(
        [string]$Entry,
        [string]$Directory
    )

    try {
        $normalizedEntry = Get-NormalizedPath $Entry
        $normalizedDirectory = Get-NormalizedPath $Directory
        return $normalizedEntry -ieq $normalizedDirectory
    }
    catch {
        return $false
    }
}

function Get-ConsoleWidth {
    param(
        [int]$Default = 96,
        [int]$Minimum = 40,
        [int]$Maximum = 0
    )

    $width = $Default
    try {
        $windowWidth = $Host.UI.RawUI.WindowSize.Width
        if ($windowWidth -gt 0) {
            $width = $windowWidth - 1
        }
    }
    catch {
        # Redirected hosts may not expose a console width.
    }
    if ($Maximum -gt 0) {
        $width = [math]::Min($width, $Maximum)
    }
    return [math]::Max($Minimum, $width)
}

function Write-Result {
    param(
        $Value,
        [switch]$AsJson
    )

    if ($AsJson) {
        ConvertTo-Json -InputObject $Value -Depth 8
    }
    else {
        $Value | Format-List | Write-CompactOutput
    }
}

function Write-CompactOutput {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    begin {
        $items = New-Object 'System.Collections.Generic.List[object]'
    }
    process {
        if ($null -ne $InputObject) {
            $items.Add($InputObject)
        }
    }
    end {
        if (-not $items.Count) {
            return
        }
        $width = Get-ConsoleWidth
        $rendered = ($items.ToArray() | Out-String -Width $width)
        $rendered = $rendered.Trim("`r", "`n")
        Write-Host ''

        $previousBlank = $false
        foreach ($line in ($rendered -split '\r?\n')) {
            $isBlank = [string]::IsNullOrWhiteSpace($line)
            if ($isBlank -and $previousBlank) {
                continue
            }
            Write-Host $line.TrimEnd()
            $previousBlank = $isBlank
        }
    }
}
