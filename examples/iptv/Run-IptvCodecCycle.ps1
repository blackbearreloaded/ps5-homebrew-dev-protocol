# ps5-homebrew-dev-protocol - Controlled IPTV codec acceptance example.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AppDirectory,
    [Parameter(Mandatory)]
    [string]$ProjectRoot,
    [string]$FixtureDirectory = (Join-Path $PSScriptRoot 'fixtures'),
    [string]$Ps5Host = $env:PS5_HOST,
    [int]$FtpPort = 2121,
    [int]$ElfPort = 9021,
    [int]$KlogPort = 3232,
    [string]$FtpCredential = 'anonymous:anonymous',
    [string]$LockPath = ([IO.Path]::Combine(
        [Environment]::GetFolderPath('MyDocuments'), 'PS5', 'lock.txt')),
    [string]$ResultsDirectory = ([IO.Path]::GetFullPath(
        [IO.Path]::Combine($PSScriptRoot, '..', '..', 'results'))),
    [ValidatePattern('^PPSA\d{5}$')]
    [string]$DisposableTitleId = 'PPSA88001',
    [int]$ObservationSeconds = 95
)

$ErrorActionPreference = 'Stop'
if (-not $Ps5Host) { throw 'Set -Ps5Host or the PS5_HOST environment variable.' }
$app = (Resolve-Path -LiteralPath $AppDirectory).Path
$fixtures = (Resolve-Path -LiteralPath $FixtureDirectory).Path
$trigger = Join-Path $fixtures 'iptv-autotest.txt'
if (-not (Test-Path -LiteralPath $trigger -PathType Leaf)) {
    throw "Missing codec trigger: $trigger (copy iptv-autotest.txt.example and replace HOST_IP)"
}

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$tempApp = Join-Path $tempParent ("ps5-iptv-codec-{0}" -f $PID)
$tempImage = "$tempApp.ffpfsc"
$tempDownloadData = "$tempApp-download0.dat"
$tempReceiptDirectory = "$tempApp-receipts"
$projectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$results = [IO.Path]::GetFullPath($ResultsDirectory)
$server = $null
try {
    if ((Test-Path -LiteralPath $tempApp) -or
        (Test-Path -LiteralPath $tempImage)) {
        throw "Refusing to reuse temporary codec artifacts: $tempApp"
    }
    New-Item -ItemType Directory -Path $tempApp | Out-Null
    Copy-Item -Path (Join-Path $app '*') -Destination $tempApp -Recurse
    Copy-Item -LiteralPath $trigger -Destination (Join-Path $tempApp 'iptv-autotest.txt')

    $paramPath = Join-Path $tempApp 'sce_sys\param.json'
    $param = Get-Content -LiteralPath $paramPath -Raw | ConvertFrom-Json
    $numericId = $DisposableTitleId.Substring(4)
    $param.titleId = $DisposableTitleId
    $param.conceptId = $numericId
    $param.contentId = "UP9000-${DisposableTitleId}_00-PS5IPTVAPP000001"
    $param | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $paramPath -Encoding utf8

    $mkpfsPython = & (Join-Path $projectRoot 'tools\setup-mkpfs-tooling.ps1')
    & $mkpfsPython -m mkpfs pack folder --no-adjust-output-file-extension `
        --version PS5 --verify $tempApp $tempImage
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to package disposable IPTV codec image."
    }

    $server = Start-Process -FilePath 'python' -PassThru -WindowStyle Hidden `
        -WorkingDirectory $fixtures -ArgumentList @(
            '-m', 'http.server', '8088', '--bind', '0.0.0.0',
            '--directory', $fixtures
        )
    Start-Sleep -Seconds 1
    $server.Refresh()
    if ($server.HasExited) { throw 'Controlled IPTV HTTP server failed to start.' }

    $runStarted = Get-Date
    & (Join-Path $PSScriptRoot 'Run-IptvCycle.ps1') `
        -AppDirectory $tempApp `
        -ImagePath $tempImage `
        -TitleId $DisposableTitleId `
        -Ps5Host $Ps5Host `
        -FtpPort $FtpPort `
        -ElfPort $ElfPort `
        -KlogPort $KlogPort `
        -FtpCredential $FtpCredential `
        -LockPath $LockPath `
        -ResultsDirectory $results `
        -RequireUnusedRemoteTitle `
        -RemoveRemoteImageAfterCycle `
        -DownloadDataOutputPath $tempDownloadData `
        -ObservationSeconds $ObservationSeconds
    if ($LASTEXITCODE -ne 0) {
        throw "Locked IPTV codec cycle failed with exit code $LASTEXITCODE."
    }

    $resultFile = Get-ChildItem -LiteralPath $results -Filter "$DisposableTitleId-*-result.json" -File |
        Where-Object LastWriteTime -ge $runStarted |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $resultFile) { throw 'Codec cycle produced no result record.' }
    $result = Get-Content -LiteralPath $resultFile.FullName -Raw | ConvertFrom-Json
    if ($result.outcome -ne 'entered-eboot') {
        throw "Codec cycle did not enter eboot: $($result.outcome)"
    }

    if (-not (Test-Path -LiteralPath $tempDownloadData -PathType Leaf)) {
        throw 'Codec cycle produced no download-data evidence.'
    }
    $dotnet = (Get-Command dotnet).Source
    $ufs2Assembly = & (Join-Path $projectRoot 'tools\setup-ffpkg-tooling.ps1') `
        -Dotnet $dotnet
    $previousRollForward = $env:DOTNET_ROLL_FORWARD
    try {
        $env:DOTNET_ROLL_FORWARD = 'Major'
        & $dotnet $ufs2Assembly extract $tempDownloadData `
            $tempReceiptDirectory /iptv-autotest-receipts.txt
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not extract the codec receipt archive.'
        }
    } finally {
        $env:DOTNET_ROLL_FORWARD = $previousRollForward
    }
    $extractedReceipt =
        Join-Path $tempReceiptDirectory 'iptv-autotest-receipts.txt'
    if (-not (Test-Path -LiteralPath $extractedReceipt -PathType Leaf)) {
        throw 'The codec receipt archive is missing from download0.dat.'
    }
    $evidenceReceipt =
        $resultFile.FullName -replace '-result\.json$', '-codec-receipts.txt'
    if (Test-Path -LiteralPath $evidenceReceipt) {
        throw "Refusing to replace codec receipt evidence: $evidenceReceipt"
    }
    Copy-Item -LiteralPath $extractedReceipt -Destination $evidenceReceipt
    $lines = @(Get-Content -LiteralPath $evidenceReceipt)
    if ($lines.Count -eq 0 -or $lines[0] -ne 'IPTV_AUTOTEST_RECEIPTS_V1') {
        throw 'Invalid codec receipt archive header.'
    }
    foreach ($index in 1..2) {
        $begin = "IPTV_AUTOTEST_BEGIN index=$index"
        $end = "IPTV_AUTOTEST_END index=$index result=0"
        $beginAt = [Array]::IndexOf($lines, $begin)
        $endAt = [Array]::IndexOf($lines, $end)
        if ($beginAt -lt 0 -or $endAt -le $beginAt) {
            throw "Missing matched codec markers for test $index."
        }
        $section = @($lines[($beginAt + 1)..($endAt - 1)])
        if ($section.Count -eq 0 -or $section[0] -ne 'IPTV_RECEIPT_V1') {
            throw "Codec test $index has no persisted receipt."
        }
        $fields = @{}
        foreach ($line in $section) {
            if ($line -match '^([^=]+)=(.*)$') {
                $fields[$Matches[1]] = $Matches[2]
            }
        }
        $expectedCodec = $index
        $required = @{
            result = '0'
            codec = "$expectedCodec"
            native_cleanup = '0'
            decoder_output_in_frame_pool = '1'
            zero_copy_pointer_match = '1'
            hardware_validated = '1'
            stream_acceptance_validated = '1'
        }
        foreach ($name in $required.Keys) {
            if ($fields[$name] -ne $required[$name]) {
                throw "Codec receipt $index has invalid $name`: $($fields[$name])"
            }
        }
        foreach ($counter in @(
            'video_access_units', 'decoded_frames', 'presented_frames',
            'audio_decoded_frames', 'audio_output_grains'
        )) {
            [uint64]$progress = 0
            if (-not [uint64]::TryParse($fields[$counter], [ref]$progress) -or
                $progress -eq 0) {
                throw "Codec receipt $index has no $counter progress."
            }
        }
    }
    Write-Host "IPTV_CODEC_ACCEPTANCE_OK $DisposableTitleId receipts=$evidenceReceipt"
} finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force
    }
    if (Test-Path -LiteralPath $tempApp) {
        $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $tempApp).Path)
        if (-not $resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -or
            $resolved -eq $tempParent) {
            throw "Refusing to remove unexpected temporary path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    if (Test-Path -LiteralPath $tempImage) {
        $resolvedImage = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $tempImage).Path)
        if (-not $resolvedImage.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetExtension($resolvedImage) -ne '.ffpfsc') {
            throw "Refusing to remove unexpected temporary image: $resolvedImage"
        }
        Remove-Item -LiteralPath $resolvedImage -Force
    }
    if (Test-Path -LiteralPath $tempDownloadData) {
        $resolvedDownloadData =
            [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $tempDownloadData).Path)
        if (-not $resolvedDownloadData.StartsWith(
                $tempParent, [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetExtension($resolvedDownloadData) -ne '.dat') {
            throw "Refusing to remove unexpected download-data path: $resolvedDownloadData"
        }
        Remove-Item -LiteralPath $resolvedDownloadData -Force
    }
    if (Test-Path -LiteralPath $tempReceiptDirectory) {
        $resolvedReceiptDirectory =
            [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $tempReceiptDirectory).Path)
        if (-not $resolvedReceiptDirectory.StartsWith(
                $tempParent, [StringComparison]::OrdinalIgnoreCase) -or
            $resolvedReceiptDirectory -eq $tempParent) {
            throw "Refusing to remove unexpected receipt path: $resolvedReceiptDirectory"
        }
        Remove-Item -LiteralPath $resolvedReceiptDirectory -Recurse -Force
    }
}
