<# .SYNOPSIS
Generate a legacy WordPress PHPass hash with a UTF-8 password and secure random
salt.
.DESCRIPTION
Without -Password, prompt securely. Modern WordPress uses bcrypt by default;
this utility produces the legacy $P$ format for compatibility.
#>
[CmdletBinding()]
param(
    [string]$Password
)

. "$PSScriptRoot\common.ps1"

function ConvertTo-PhpassBase64 {
    param(
        [byte[]]$Bytes
    )

    $alphabet =
    './0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    $output = New-Object Text.StringBuilder
    $value = 0
    $bits = 0
    foreach ($byte in $Bytes) {
        $value = $value -bor ([int]$byte -shl $bits)
        $bits += 8
        while ($bits -ge 6) {
            $null = $output.Append($alphabet[$value -band 63])
            $value = $value -shr 6
            $bits -= 6
        }
    }
    if ($bits -gt 0) {
        $null = $output.Append($alphabet[$value -band 63])
    }
    return $output.ToString()
}

function New-PhpassHash {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Password,
        [Parameter(Mandatory)]
        [ValidatePattern('^[./0-9A-Za-z]{8}$')]
        [string]$Salt
    )

    $md5 = [Security.Cryptography.MD5]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Password)
        $digest = $md5.ComputeHash([Text.Encoding]::ASCII.GetBytes($Salt) +
            $bytes)
        for ($i = 0; $i -lt 8192; $i++) {
            $digest = $md5.ComputeHash($digest + $bytes)
        }
        return '$P$B' + $Salt + (ConvertTo-PhpassBase64 $digest)
    }
    finally {
        $md5.Dispose()
    }
}

function Read-HashPassword {
    param()

    $secure = Read-Host 'Password' -AsSecureString
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
            $secure)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
        $secure.Dispose()
    }
}

function New-PhpassSalt {
    param()

    $bytes = New-Object byte[] 6
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($bytes)
    }
    finally {
        $random.Dispose()
    }
    return ConvertTo-PhpassBase64 $bytes
}

try {
    if (-not $PSBoundParameters.ContainsKey('Password')) {
        Write-Host ('Generate a legacy WordPress password hash. Your ' +
            'password will not be displayed.')
        $Password = Read-HashPassword
    }
    if ([string]::IsNullOrEmpty($Password)) {
        throw 'Password must not be empty.'
    }
    $salt = New-PhpassSalt
    $hash = New-PhpassHash -Password $Password -Salt $salt
    Write-Host 'Generated legacy WordPress password hash:'
    Write-Host ''
    Write-Output $hash
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
finally {
    $Password = $null
}
