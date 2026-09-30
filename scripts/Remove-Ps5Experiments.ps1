# ps5-homebrew-dev-protocol - Explicit remote experiment cleanup.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Removes named remote experiment trees under /data/homebrew while refusing
# protected known-good controls. Protected title IDs come from
# -ProtectedTitleId or the comma-separated PS5_PROTECTED_TITLES variable.

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^PPSA\d{5}$')]
    [string[]]$TitleId,

    [string]$Ps5Host = $env:PS5_HOST,
    [int]$FtpPort = 2121,
    [string]$FtpCredential = 'anonymous:anonymous',

    [ValidatePattern('^PPSA\d{5}$')]
    [string[]]$ProtectedTitleId = @(
        "$env:PS5_PROTECTED_TITLES" -split '[,\s]+' | Where-Object { $_ })
)

$ErrorActionPreference = 'Stop'
if (-not $Ps5Host) { throw 'Set -Ps5Host or the PS5_HOST environment variable.' }
$protected = @($ProtectedTitleId)

function Invoke-FtpList([string]$RemotePath) {
    $url = "ftp://${Ps5Host}:${FtpPort}${RemotePath}/"
    $lines = & curl.exe --fail --silent --show-error --disable-epsv -u $FtpCredential $url
    if ($LASTEXITCODE -ne 0) { throw "FTP listing failed: $RemotePath" }
    return @($lines)
}

function Invoke-FtpCommand([string]$Command) {
    & curl.exe --fail --silent --show-error --disable-epsv -u $FtpCredential `
        --quote $Command "ftp://${Ps5Host}:${FtpPort}/" --output NUL
    if ($LASTEXITCODE -ne 0) { throw "FTP command failed: $Command" }
}

function Remove-FtpTree([string]$RemotePath) {
    foreach ($line in Invoke-FtpList $RemotePath) {
        $parts = $line -split '\s+', 9
        if ($parts.Count -lt 9) { continue }
        $name = $parts[8]
        if ($name -in @('.', '..')) { continue }
        $child = "$RemotePath/$name"
        if ($parts[0].StartsWith('d')) {
            Remove-FtpTree $child
        } else {
            Invoke-FtpCommand "DELE $child"
        }
    }
    Invoke-FtpCommand "RMD $RemotePath"
}

foreach ($id in $TitleId) {
    if ($id -in $protected) { throw "Refusing to remove protected control: $id" }
    $remote = "/data/homebrew/$id"
    if ($PSCmdlet.ShouldProcess("ftp://${Ps5Host}:${FtpPort}$remote", 'recursively remove experiment upload')) {
        Remove-FtpTree $remote
        [pscustomobject]@{ titleId = $id; removed = $remote; localCopyPreserved = $true }
    }
}
