<# .SYNOPSIS
Show the firmware OEM key and installed Windows version. Digital licenses may
have no firmware key.
#>
[CmdletBinding()]
param(
    [switch]$AsJson
)

. "$PSScriptRoot\common.ps1"

try {
    $service = Get-CimInstance -ClassName SoftwareLicensingService
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $result = [pscustomobject]@{
        FirmwareOemProductKey = $service.OA3xOriginalProductKey
        Windows = $os.Caption
        Version = $os.Version
        Build = $os.BuildNumber
    }
    if (-not $AsJson) {
        Write-Host `
            'Windows version and firmware OEM product key (if available):'
    }
    if ($AsJson) {
        Write-Result $result -AsJson
    }
    else {
        $result | Format-List @{
            Label = 'Windows'
            Expression = {
                $_.Windows
            }
        }, @{
            Label = 'Version'
            Expression = {
                $_.Version
            }
        }, @{
            Label = 'Build'
            Expression = {
                $_.Build
            }
        }, @{
            Label = 'Firmware OEM key'
            Expression = {
                if ($_.FirmwareOemProductKey) {
                    $_.FirmwareOemProductKey
                }
                else {
                    'Not available (a digital license may not have one)'
                }
            }
        } | Write-CompactOutput
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
