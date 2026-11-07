<# .SYNOPSIS
Show TCP connections and UDP endpoints using a local port, including their
owning processes.
.DESCRIPTION
Omit -Port to be prompted. This inspects local ports; it does not scan remote
hosts.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$Port,
    [ValidateSet('Both', 'TCP', 'UDP')]
    [string]$Protocol = 'Both',
    [switch]$AsJson
)

. "$PSScriptRoot\common.ps1"

function Get-PortEndpoints {
    param(
        [int]$Port,
        [string]$Protocol
    )

    # Query all endpoints so an unused port is an ordinary empty result, not a
    # CIM error.
    $endpoints = @()
    if ($Protocol -in @('Both', 'TCP')) {
        $endpoints += @(Get-NetTCPConnection |
                Where-Object LocalPort -eq $Port | ForEach-Object {
                    [pscustomobject]@{
                        Protocol = 'TCP'
                        LocalAddress = $_.LocalAddress
                        LocalPort = $_.LocalPort
                        State = [string]$_.State
                        RemoteAddress = $_.RemoteAddress
                        RemotePort = $_.RemotePort
                        ProcessId = $_.OwningProcess
                    }
                })
    }
    if ($Protocol -in @('Both', 'UDP')) {
        $endpoints += @(Get-NetUDPEndpoint |
                Where-Object LocalPort -eq $Port | ForEach-Object {
                    [pscustomobject]@{
                        Protocol = 'UDP'
                        LocalAddress = $_.LocalAddress
                        LocalPort = $_.LocalPort
                        State = 'Bound'
                        RemoteAddress = $null
                        RemotePort = $null
                        ProcessId = $_.OwningProcess
                    }
                })
    }

    return $endpoints
}

function Get-EndpointProcess {
    param(
        [int]$ProcessId
    )

    $process = $null
    $name = 'Unavailable (exited or restricted)'
    $path = $null
    try {
        $process = Get-Process -Id $ProcessId
        $name = $process.ProcessName
        try {
            $path = $process.Path
        }
        catch { } `
            # Process metadata may be restricted even when its name is visible.
    }
    catch { } # The owner can exit between endpoint enumeration and inspection.
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
    [pscustomobject]@{
        Name = $name
        Path = $path
    }
}

try {
    if (-not $PSBoundParameters.ContainsKey('Port')) {
        Write-Host 'Find which program is using a local TCP or UDP port.'
        $number = 0
        do {
            $value = Read-Value 'Port number (1-65535)' -Required
        }
        until ([int]::TryParse($value, [ref]$number) -and $number -ge 1 -and
            $number -le 65535)
        $Port = $number
    }
    $rows = @()
    $endpoints = @(Get-PortEndpoints $Port $Protocol)
    foreach ($endpoint in $endpoints) {
        $owner = Get-EndpointProcess $endpoint.ProcessId
        $rows += [pscustomobject]@{
            Protocol = $endpoint.Protocol
            LocalAddress = $endpoint.LocalAddress
            LocalPort = $endpoint.LocalPort
            State = $endpoint.State
            ProcessId = $endpoint.ProcessId
            ProcessName = $owner.Name
            ExecutablePath = $owner.Path
            RemoteAddress = $endpoint.RemoteAddress
            RemotePort = $endpoint.RemotePort
        }
    }
    $rows = @($rows | Sort-Object Protocol, LocalAddress, ProcessId)
    if ($AsJson) {
        Write-Result $rows -AsJson
    }
    else {
        Write-Host "Local port $Port and its owning processes:"
        if ($rows.Count) {
            $rows | Format-List Protocol, @{
                Label = 'Local address'
                Expression = {
                    $_.LocalAddress
                }
            }, @{
                Label = 'Local port'
                Expression = {
                    $_.LocalPort
                }
            }, State, @{
                Label = 'Process ID'
                Expression = {
                    $_.ProcessId
                }
            }, @{
                Label = 'Program'
                Expression = {
                    $_.ProcessName
                }
            }, @{
                Label = 'Executable'
                Expression = {
                    if ($_.ExecutablePath) {
                        $_.ExecutablePath
                    }
                    else {
                        'Not available'
                    }
                }
            }, @{
                Label = 'Remote endpoint'
                Expression = {
                    if ($_.Protocol -eq 'UDP') {
                        'Not applicable (UDP)'
                    }
                    else {
                        "$($_.RemoteAddress):$($_.RemotePort)"
                    }
                }
            } | Write-CompactOutput
        }
        else {
            Write-Host ''
            Write-Host "No $Protocol endpoints currently use this local port."
        }
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
