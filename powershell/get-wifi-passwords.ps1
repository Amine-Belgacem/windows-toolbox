<# .SYNOPSIS
Read saved Wi-Fi profiles using the Windows WLAN API, without plaintext
temporary files.
.DESCRIPTION
With no arguments, display all saved profiles. Use -Name to select one.
Cleartext keys may require an administrator terminal. Open and enterprise
profiles may have no stored key.
#>
[CmdletBinding()]
param(
    [string]$Name,
    [switch]$All,
    [switch]$AsJson
)

. "$PSScriptRoot\common.ps1"

try {
    if ($Name -and $All) {
        throw 'Use either -Name or -All.'
    }
    $native = @{
        TypeName = 'QuickScripts.WifiReader'
        FileName = 'wifi-reader.cs'
        ReferencedAssemblies = @('System.Xml', 'System.Core')
    }
    Import-NativeType @native
    $profiles = @([QuickScripts.WifiReader]::Read($Name))
    if ($Name -and -not $profiles.Count) {
        throw "Saved Wi-Fi profile not found: $Name"
    }
    if (-not $AsJson) {
        Write-Host 'Saved Wi-Fi profiles and available stored passwords:'
    }
    if ($AsJson) {
        Write-Result $profiles -AsJson
    }
    elseif ($profiles.Count) {
        $profiles | Format-List @{
            Label = 'Network'
            Expression = { $_.Name }
        }, @{
            Label = 'Adapter'
            Expression = { $_.Interface }
        }, @{
            Label = 'Password'
            Expression = {
                if ($_.Password) {
                    $_.Password
                }
                else {
                    'Not available'
                }
            }
        }, Status | Write-CompactOutput
    }
    else {
        Write-Host ''
        Write-Host 'No saved Wi-Fi profiles found.'
    }
    if (@($profiles | Where-Object {
                $_.Status -ne 'Available' -and $_.Status -ne
                'No stored shared key (open or enterprise profile)'
            }).Count) {
        exit 1
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
