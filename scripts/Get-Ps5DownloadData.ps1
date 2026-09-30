# ps5-homebrew-dev-protocol - Download-data evidence retrieval.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Retrieves one title's download0.dat while holding the shared console lock.

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^PPSA\d{5}$')]
    [string]$TitleId,
    [Parameter(Mandatory)]
    [string]$OutputPath,
    [Alias('Ps5Address')]
    [string]$Ps5Host = $env:PS5_HOST,
    [int]$FtpPort = 2121,
    [string]$FtpCredential = 'anonymous:anonymous',
    [string]$LockPath = [IO.Path]::Combine(
        [Environment]::GetFolderPath('MyDocuments'), 'PS5', 'lock.txt')
)

$ErrorActionPreference = 'Stop'
if (-not $Ps5Host) { throw 'Set -Ps5Host or the PS5_HOST environment variable.' }
$ps5Lock = [IO.Path]::GetFullPath($LockPath)
$lockToken = '{0}|pid={1}|utc={2:o}' -f 'iptv-receipt', $PID, [DateTime]::UtcNow
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $resolvedOutput) {
    throw "Refusing to replace existing receipt image: $resolvedOutput"
}
$outputDirectory = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    throw "Receipt output directory does not exist: $outputDirectory"
}

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
    $remote = "ftp://${Ps5Host}:${FtpPort}/user/download/$TitleId/download0.dat"
    & curl.exe --fail --silent --show-error --disable-epsv `
        -u $FtpCredential $remote --output $resolvedOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Could not retrieve download0.dat for $TitleId"
    }
    $file = Get-Item -LiteralPath $resolvedOutput
    if ($file.Length -eq 0) {
        Remove-Item -LiteralPath $resolvedOutput -Force
        throw "Retrieved an empty download0.dat for $TitleId"
    }
    $hash = Get-FileHash -LiteralPath $resolvedOutput -Algorithm SHA256
    Write-Host "DOWNLOAD_DATA_RETRIEVED $TitleId bytes=$($file.Length) sha256=$($hash.Hash)"
} catch {
    if (Test-Path -LiteralPath $resolvedOutput) {
        Remove-Item -LiteralPath $resolvedOutput -Force
    }
    throw
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
