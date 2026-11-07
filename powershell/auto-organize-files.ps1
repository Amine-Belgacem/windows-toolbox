<# .SYNOPSIS
Sort top-level files by extension. Existing files are renamed or skipped, never
overwritten.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Directory,
    [string]$Destination,
    [ValidateSet('Rename', 'Skip')]
    [string]$Collision = 'Rename'
)

. "$PSScriptRoot\common.ps1"

function Get-FileCategoryLookup {
    param()

    $categories = [ordered]@{
        Images = 'jpg jpeg png gif webp bmp tif tiff svg avif heic'
        Archives = 'zip rar 7z tar gz bz2 xz tgz'
        Executables = 'exe msi msp msix msixbundle appx appxbundle com scr'
        Books = 'pdf epub mobi azw azw3 djvu fb2 cbz cbr'
        Documents = ('doc docx xls xlsx xlsm ppt pptx pps ppsx txt rtf odt ' +
            'ods odp csv md')
        'Disk-Images' =
        'iso img dmg nrg mdf mds vhd vhdx vdi vmdk qcow qcow2 wim esd'
    }
    $lookup = @{}
    foreach ($category in $categories.Keys) {
        foreach ($extension in $categories[$category].Split(' ')) {
            $lookup['.' + $extension] = $category
        }
    }

    return $lookup
}

function Get-OrganizedFileTarget {
    param(
        $File,
        [string]$Folder,
        [string]$Collision
    )

    $target = Join-Path $folder $file.Name
    if (Test-Path -LiteralPath $target) {
        if ($Collision -eq 'Skip') {
            return $null
        }
        $suffix = 1
        do {
            $target = Join-Path $folder ("{0} ({1}){2}" -f $file.BaseName,
                $suffix, $file.Extension)
            $suffix++
        } while (Test-Path -LiteralPath $target)
    }

    return $target
}

try {
    if (-not $Directory) {
        Write-Host 'Move supported files into folders grouped by file type.'
        $Directory = Read-Value 'Folder to organize' $PWD.Path -Required
    }
    $source = Get-Item -LiteralPath $Directory
    if (-not $source.PSIsContainer) {
        throw 'Directory must be a folder.'
    }
    if (-not $Destination) {
        $Destination = Join-Path $source.FullName 'AutoSort'
    }
    $Destination = Get-NormalizedPath $Destination
    if ($Destination -ieq (Get-NormalizedPath $source.FullName)) {
        throw 'Source and destination must be different folders.'
    }
    $lookup = Get-FileCategoryLookup
    $moved = 0
    $skipped = 0
    $failed = 0
    $planned = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $source.FullName -File)) {
        if (-not $lookup.ContainsKey($file.Extension)) {
            continue
        }
        $folder = Join-Path $Destination $lookup[$file.Extension]
        $target = Get-OrganizedFileTarget $file $folder $Collision
        if (-not $target) {
            $skipped++
            continue
        }
        if ($PSCmdlet.ShouldProcess($file.FullName, "Move to $target")) {
            try {
                $null = [IO.Directory]::CreateDirectory($folder)
                # File.Move fails if a destination appears concurrently; it
                # never overwrites.
                [IO.File]::Move($file.FullName, $target)
                $moved++
            }
            catch {
                $failed++
                Write-Warning "$($file.Name): $($_.Exception.Message)"
            }
        }
        else {
            $planned++
        }
    }
    Write-Host 'File organization results:'
    [pscustomobject]@{
        Moved = $moved
        Skipped = $skipped
        Failed = $failed
        NotMoved = $planned
        Destination = $Destination
    } | Format-List Moved, Skipped, Failed, @{
        Label = 'Not moved'
        Expression = { $_.NotMoved }
    }, Destination | Write-CompactOutput
    if ($failed) {
        exit 1
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
