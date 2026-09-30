# ps5-homebrew-dev-protocol - Managed IPTV validation example.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AppDirectory,
    [string]$ImagePath = '',
    [Parameter(Mandatory)]
    [ValidatePattern('^PPSA\d{5}$')]
    [string]$TitleId,
    [string]$Ps5Host = $env:PS5_HOST,
    [int]$FtpPort = 2121,
    [int]$ElfPort = 9021,
    [int]$KlogPort = 3232,
    [string]$FtpCredential = 'anonymous:anonymous',
    [string]$LockPath = ([IO.Path]::Combine(
        [Environment]::GetFolderPath('MyDocuments'), 'PS5', 'lock.txt')),
    [string]$ResultsDirectory = ([IO.Path]::GetFullPath(
        [IO.Path]::Combine($PSScriptRoot, '..', '..', 'results'))),
    [switch]$RequireUnusedRemoteTitle,
    [switch]$UseExistingRegistration,
    [switch]$RemoveRemoteImageAfterCycle,
    [string]$DownloadDataOutputPath,
    [int]$ObservationSeconds = 15
)

$ErrorActionPreference = 'Stop'
if (-not $Ps5Host) { throw 'Set -Ps5Host or the PS5_HOST environment variable.' }
if ($RemoveRemoteImageAfterCycle -and
    (-not $RequireUnusedRemoteTitle -or -not $ImagePath)) {
    throw 'Remote image cleanup requires an unused title and an explicit image path.'
}
if ($UseExistingRegistration -and $RequireUnusedRemoteTitle) {
    throw 'Existing registration and unused-title enforcement are mutually exclusive.'
}
$resolvedDownloadData = $null
if ($DownloadDataOutputPath) {
    $resolvedDownloadData = [IO.Path]::GetFullPath($DownloadDataOutputPath)
    if (Test-Path -LiteralPath $resolvedDownloadData) {
        throw "Refusing to replace existing download-data evidence: $resolvedDownloadData"
    }
    $downloadDataParent = Split-Path -Parent $resolvedDownloadData
    if (-not (Test-Path -LiteralPath $downloadDataParent -PathType Container)) {
        throw "Download-data evidence directory does not exist: $downloadDataParent"
    }
}
$ps5Lock = [IO.Path]::GetFullPath($LockPath)
$lockToken = '{0}|pid={1}|utc={2:o}' -f 'iptv-debug', $PID, [DateTime]::UtcNow

while ($true) {
    try {
        $handle = [IO.File]::Open(
            $ps5Lock,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None)
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($lockToken)
            $handle.Write($bytes, 0, $bytes.Length)
        } finally {
            $handle.Dispose()
        }
        break
    } catch [IO.IOException] {
        if (-not (Test-Path -LiteralPath $ps5Lock)) { throw }
        Start-Sleep -Seconds 15
    }
}

try {
    Write-Host "LOCK_ACQUIRED $lockToken"
    if ($RequireUnusedRemoteTitle) {
        $listing = @(& curl.exe --fail --silent --show-error --disable-epsv `
            -u $FtpCredential "ftp://${Ps5Host}:${FtpPort}/data/homebrew/")
        if ($LASTEXITCODE -ne 0) { throw 'Could not list /data/homebrew' }
        $names = @($listing | ForEach-Object {
            $fields = $_.Trim() -split '\s+', 9
            if ($fields.Count -eq 9) { $fields[8] }
        })
        if ($names -contains $TitleId -or $names -contains "$TitleId.ffpfsc") {
            throw "Remote title is already occupied: $TitleId"
        }
        Write-Host "REMOTE_TITLE_AVAILABLE $TitleId"
    }
    try {
        $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        & (Join-Path $repositoryRoot 'scripts\Invoke-Ps5Cycle.ps1') `
            -TitleId $TitleId `
            -AppDirectory $AppDirectory `
            -ImagePath $ImagePath `
            -PreviousTitleId $TitleId `
            -Ps5Host $Ps5Host `
            -FtpPort $FtpPort `
            -ElfPort $ElfPort `
            -KlogPort $KlogPort `
            -FtpCredential $FtpCredential `
            -ResultsDirectory $ResultsDirectory `
            -UseExistingRegistration:$UseExistingRegistration `
            -ObservationSeconds $ObservationSeconds
        if ($LASTEXITCODE -ne 0) {
            throw "Invoke-Ps5Cycle failed with exit code $LASTEXITCODE."
        }
        if ($resolvedDownloadData) {
            $remoteDownloadData =
                "ftp://${Ps5Host}:${FtpPort}/user/download/$TitleId/download0.dat"
            & curl.exe --fail --silent --show-error --disable-epsv `
                -u $FtpCredential $remoteDownloadData `
                --output $resolvedDownloadData
            if ($LASTEXITCODE -ne 0) {
                throw "Could not retrieve download0.dat for $TitleId"
            }
            $downloadDataFile = Get-Item -LiteralPath $resolvedDownloadData
            if ($downloadDataFile.Length -eq 0) {
                Remove-Item -LiteralPath $resolvedDownloadData -Force
                throw "Retrieved an empty download0.dat for $TitleId"
            }
            $downloadDataHash =
                Get-FileHash -LiteralPath $resolvedDownloadData -Algorithm SHA256
            Write-Host "DOWNLOAD_DATA_RETRIEVED $TitleId bytes=$($downloadDataFile.Length) sha256=$($downloadDataHash.Hash)"
        }
    } finally {
        if ($RemoveRemoteImageAfterCycle) {
            $remoteName = "$TitleId.ffpfsc"
            $listing = @(& curl.exe --fail --silent --show-error --disable-epsv `
                -u $FtpCredential "ftp://${Ps5Host}:${FtpPort}/data/homebrew/")
            if ($LASTEXITCODE -ne 0) { throw 'Could not list /data/homebrew for cleanup' }
            $names = @($listing | ForEach-Object {
                $fields = $_.Trim() -split '\s+', 9
                if ($fields.Count -eq 9) { $fields[8] }
            })
            if ($names -contains $remoteName) {
                & curl.exe --fail --silent --show-error --disable-epsv `
                    -u $FtpCredential `
                    --quote "DELE /data/homebrew/$remoteName" `
                    "ftp://${Ps5Host}:${FtpPort}/" --output NUL
                if ($LASTEXITCODE -ne 0) { throw "Could not remove $remoteName" }
                Write-Host "REMOTE_IMAGE_REMOVED $remoteName"
            } else {
                Write-Host "REMOTE_IMAGE_ALREADY_ABSENT $remoteName"
            }
        }
    }
} finally {
    if (Test-Path -LiteralPath $ps5Lock) {
        $currentToken = Get-Content -LiteralPath $ps5Lock -Raw
        if ($currentToken -eq $lockToken) {
            Remove-Item -LiteralPath $ps5Lock -Force
            Write-Host 'LOCK_RELEASED'
        } else {
            Write-Warning 'Lock ownership changed; refusing to remove it.'
        }
    }
}
