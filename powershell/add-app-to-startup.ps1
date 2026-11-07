<# .SYNOPSIS
Add an app to Windows startup so it opens automatically when you sign in.
.DESCRIPTION
Supply -Path or omit it to be prompted for an executable. Defaults to the
current
user; -Scope Machine adds it for all users and requires administrator rights.
-List is the secondary option to display existing startup entries.
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Add')]
param(
    [Parameter(Position = 0, ParameterSetName = 'Add')]
    [string]$Path,
    [Parameter(ParameterSetName = 'Add')]
    [string]$Name,
    [Parameter(ParameterSetName = 'Add')]
    [string]$Arguments = '',
    [Parameter(ParameterSetName = 'Add')]
    [ValidateSet('User', 'Machine')]
    [string]$Scope = 'User',
    [Parameter(Mandatory, ParameterSetName = 'List')]
    [Alias('Show')]
    [switch]$List,
    [switch]$AsJson
)

. "$PSScriptRoot\common.ps1"

function Get-StartupId {
    param(
        [string]$Identity
    )

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Identity)
        $digest = $sha.ComputeHash($bytes)
        $hex = [BitConverter]::ToString($digest).Replace('-', '')
        return $hex.Substring(0, 16).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-StartupFolderEntries {
    param()

    $folders = @(
        @{
            Path = [Environment]::GetFolderPath('Startup')
            Scope = 'User'
        },
        @{
            Path = [Environment]::GetFolderPath('CommonStartup')
            Scope = 'Machine'
        }
    )
    foreach ($folder in $folders) {
        if (-not $folder.Path -or -not (Test-Path -LiteralPath $folder.Path)) {
            continue
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $folder.Path -File)) {
            [pscustomobject]@{
                Id = Get-StartupId "File|$($file.FullName)"
                Name = $file.Name
                Kind = 'File'
                Scope = $folder.Scope
                Location = $file.FullName
                Command = $null
                TaskPath = $null
            }
        }
    }
}

function Get-StartupRegistryEntries {
    param()

    $keys = @(
        @{
            Prefix = 'HKCU:'
            Scope = 'User'
            Branch = 'Software\Microsoft\Windows\CurrentVersion'
        },
        @{
            Prefix = 'HKLM:'
            Scope = 'Machine'
            Branch = 'Software\Microsoft\Windows\CurrentVersion'
        },
        @{
            Prefix = 'HKLM:'
            Scope = 'Machine'
            Branch = 'Software\Wow6432Node\Microsoft\Windows\CurrentVersion'
        }
    )
    foreach ($key in $keys) {
        foreach ($suffix in @('Run', 'RunOnce')) {
            $location = "$($key.Prefix)\$($key.Branch)\$suffix"
            if (-not (Test-Path -LiteralPath $location)) {
                continue
            }
            $options = [Microsoft.Win32.RegistryValueOptions]::
            DoNotExpandEnvironmentNames
            $registry = Get-Item -LiteralPath $location
            try {
                foreach ($valueName in $registry.GetValueNames()) {
                    [pscustomobject]@{
                        Id = Get-StartupId "Registry|$location|$valueName"
                        Name = $valueName
                        Kind = 'Registry'
                        Scope = $key.Scope
                        Location = $location
                        Command = $registry.GetValue($valueName, '', $options)
                        TaskPath = $null
                    }
                }
            }
            finally {
                $registry.Dispose()
            }
        }
    }
}

function Get-StartupTaskEntries {
    param()

    try {
        $tasks = @(Get-ScheduledTask)
        foreach ($task in $tasks) {
            $startupTriggers = @($task.Triggers | Where-Object {
                    $null -ne $_ -and $_.CimClass.CimClassName -in @(
                        'MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger')
                })
            if (-not $startupTriggers.Count) {
                continue
            }
            $commands = @($task.Actions | ForEach-Object {
                    $execute = $_.PSObject.Properties['Execute']
                    $argsProperty = $_.PSObject.Properties['Arguments']
                    if ($null -ne $execute) {
                        $actionArguments = ''
                        if ($null -ne $argsProperty) {
                            $actionArguments = [string]$argsProperty.Value
                        }
                        ("$($execute.Value) $actionArguments").Trim()
                    }
                })
            [pscustomobject]@{
                Id = Get-StartupId "Task|$($task.TaskPath)|$($task.TaskName)"
                Name = $task.TaskName
                Kind = 'Task'
                Scope = $task.Principal.UserId
                Location = $task.TaskPath + $task.TaskName
                Command = $commands -join '; '
                TaskPath = $task.TaskPath
            }
        }
    }
    catch {
        Write-Warning ("Scheduled tasks could not be fully listed: " +
            "$($_.Exception.Message)")
    }
}

function Get-StartupEntries {
    Get-StartupFolderEntries
    Get-StartupRegistryEntries
    Get-StartupTaskEntries
}

try {
    if ($AsJson -and -not $List) {
        throw 'Use -List -AsJson to display startup entries as JSON.'
    }
    if ($List) {
        $entries = @(Get-StartupEntries | Sort-Object Kind, Location, Name)
        if ($AsJson) {
            Write-Result $entries -AsJson
        }
        else {
            Write-Host 'Apps configured to run at Windows startup or sign-in:'
            if ($entries.Count) {
                $entries | Format-Table Name, Kind, Scope,
                Command -AutoSize -Wrap | Write-CompactOutput
            }
            else {
                Write-Host ''
                Write-Host 'No startup entries found.'
            }
        }
        exit 0
    }
    $scopeLabel = 'your account'
    if ($Scope -eq 'Machine') {
        $scopeLabel = 'all users'
    }
    if (-not $Path) {
        Write-Host ("Add an app to Windows startup for $scopeLabel so it " +
            "opens automatically at sign-in.")
        $Path = Read-Value 'App executable path' -Required
    }
    $file = Get-Item -LiteralPath (Get-NormalizedPath $Path)
    if ($file.PSIsContainer -or $file.Extension -notin @('.exe', '.com')) {
        throw ('Choose an executable (.exe or .com). For a script, ' +
            'supply its interpreter and -Arguments.')
    }
    if (-not $Name) {
        $Name = $file.BaseName
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw 'Startup entry name must not be empty.'
    }
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if ($Scope -eq 'Machine') {
        $key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    }
    $command = '"' + $file.FullName + '"'
    if ($Arguments) {
        $command += ' ' + $Arguments
    }
    if ($command.Length -gt 260) {
        throw 'Run key command lines must not exceed 260 characters.'
    }
    if (Test-Path -LiteralPath $key) {
        $existing = Get-Item -LiteralPath $key
        try {
            if ($existing.GetValueNames() -contains $Name) {
                throw ("A startup entry named '$Name' already exists. " +
                    "It was not changed.")
            }
        }
        finally {
            $existing.Dispose()
        }
    }
    if ($PSCmdlet.ShouldProcess("Startup for $scopeLabel",
            "Add $Name with command $command")) {
        if ($Scope -eq 'Machine') {
            Assert-Administrator
        }
        if (-not (Test-Path -LiteralPath $key)) {
            $null = New-Item -Path $key -Force
        }
        $null = New-ItemProperty -LiteralPath $key -Name $Name -Value `
            $command -PropertyType String
        Write-Host "Added $Name to Windows startup for $scopeLabel."
        Write-Host 'The app will open automatically the next time you sign in.'
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
