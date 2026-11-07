<# .SYNOPSIS
Open the Windows hosts file in an elevated Notepad. Use -Path for a different
file.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Path = "$env:SystemRoot\System32\drivers\etc\hosts"
)

. "$PSScriptRoot\common.ps1"

try {
    $file = Get-Item -LiteralPath $Path
    if ($file.PSIsContainer) {
        throw 'The path must be a file.'
    }
    if ($PSCmdlet.ShouldProcess($file.FullName,
            'Open in Notepad as administrator')) {
        Write-Host "Opening $($file.FullName) in Notepad as administrator."
        $arguments = '"' + $file.FullName + '"'
        $process =
        Start-Process -FilePath "$env:SystemRoot\System32\notepad.exe" `
            -ArgumentList $arguments -Verb RunAs -PassThru -Wait
        if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
            throw "Notepad exited with code $($process.ExitCode)."
        }
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
