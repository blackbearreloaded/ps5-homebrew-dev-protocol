# ps5-homebrew-dev-protocol - ShadowMount activity check.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Compares two locked ShadowMount log snapshots without changing console state.

[CmdletBinding()]
param(
    [Alias('Ps5Address')]
    [string]$Ps5Host = $env:PS5_HOST,
    [int]$FtpPort = 2121,
    [string]$FtpCredential = 'anonymous:anonymous',
    [string]$LockPath = [IO.Path]::Combine(
        [Environment]::GetFolderPath('MyDocuments'), 'PS5', 'lock.txt'),
    [int]$ObservationSeconds = 20
)

$ErrorActionPreference = 'Stop'
if (-not $Ps5Host) { throw 'Set -Ps5Host or the PS5_HOST environment variable.' }
$ps5Lock = [IO.Path]::GetFullPath($LockPath)
$lockToken = '{0}|pid={1}|utc={2:o}' -f 'shadowmount-health', $PID, [DateTime]::UtcNow
$first = Join-Path ([IO.Path]::GetTempPath()) "shadowmount-health-$PID-first.log"
$second = Join-Path ([IO.Path]::GetTempPath()) "shadowmount-health-$PID-second.log"
$remote = "ftp://${Ps5Host}:${FtpPort}/data/shadowmount/debug.log"

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
    foreach ($sample in @($first, $second)) {
        & curl.exe --fail --silent --show-error --disable-epsv `
            -u $FtpCredential $remote --output $sample
        if ($LASTEXITCODE -ne 0) { throw 'Could not retrieve ShadowMount debug.log' }
        if ($sample -eq $first) { Start-Sleep -Seconds $ObservationSeconds }
    }
    $firstHash = (Get-FileHash -LiteralPath $first -Algorithm SHA256).Hash
    $secondHash = (Get-FileHash -LiteralPath $second -Algorithm SHA256).Hash
    $tail = @(Get-Content -LiteralPath $second | Select-Object -Last 8)
    if ($firstHash -eq $secondHash) {
        $tail
        Write-Error "SHADOWMOUNT_STALLED sha256=$secondHash"
        exit 2
    }
    $tail
    Write-Host "SHADOWMOUNT_HEALTHY sha256=$secondHash"
} finally {
    foreach ($sample in @($first, $second)) {
        if (Test-Path -LiteralPath $sample) {
            Remove-Item -LiteralPath $sample -Force
        }
    }
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
