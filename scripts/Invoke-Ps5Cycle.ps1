# ps5-homebrew-dev-protocol - Automated PS5 validation cycle.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Uploads, launches, observes, records, and closes one title through the
# approved LAN-only investigation services.

<#
.SYNOPSIS
Runs one bounded deploy, launch, observe, and close cycle for a PS5 title.

.DESCRIPTION
Closes an optional previous title, uploads the app directory or a pre-built
FFPFSC image over FTP, waits for ShadowMount Plus to register the title,
launches it with the title-aware launch controller, captures klog and chiaki-ng
screenshots, closes it with the close controller, and writes a result record
to the results directory. The caller owns any shared-console lock.

.PARAMETER TitleId
Title ID to deploy and launch, for example PPSA99999.

.PARAMETER AppDirectory
Built app directory containing eboot.bin and sce_sys\param.json.

.PARAMETER ImagePath
Optional FFPFSC image to upload instead of the loose app directory.

.PARAMETER PreviousTitleId
Optional title to close before deploying.

.PARAMETER Ps5Host
Console address. Defaults to the PS5_HOST environment variable.

.PARAMETER ChiakiNickname
Registered chiaki-ng console nickname. Defaults to the CHIAKI_PROFILE
environment variable.

.PARAMETER UseExistingRegistration
Skip the upload and verify that the remote image matches ImagePath.

.EXAMPLE
$env:PS5_HOST = '192.0.2.10'; $env:CHIAKI_PROFILE = 'MyConsole'
.\scripts\Invoke-Ps5Cycle.ps1 -TitleId PPSA99999 -AppDirectory C:\build\PPSA99999
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^PPSA\d{5}$')]
    [string]$TitleId,

    [Parameter(Mandatory)]
    [string]$AppDirectory,

    [string]$ImagePath = '',

    [ValidatePattern('^PPSA\d{5}$')]
    [string]$PreviousTitleId,

    [string]$Ps5Host = $env:PS5_HOST,
    [int]$FtpPort = 2121,
    [int]$ElfPort = 9021,
    [int]$KlogPort = 3232,
    [string]$FtpCredential = 'anonymous:anonymous',
    [string]$ChiakiExecutable = 'C:\Program Files\chiaki-ng\chiaki.exe',
    [string]$ChiakiNickname = $env:CHIAKI_PROFILE,
    [string]$ResultsDirectory =
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'results'),
    [int]$RegistrationTimeoutSeconds = 75,
    [int]$StreamStartupTimeoutSeconds = 15,
    [int]$VideoReadyTimeoutSeconds = 30,
    [int]$RuntimeReleaseTimeoutSeconds = 45,
    [switch]$UseExistingRegistration,
    [switch]$SkipVideoReadiness,
    [switch]$PreserveExistingChiaki,
    [int]$ObservationSeconds = 10
)

$ErrorActionPreference = 'Stop'
if (-not $Ps5Host) { throw 'Set -Ps5Host or the PS5_HOST environment variable.' }
if (-not $ChiakiNickname) {
    throw 'Set -ChiakiNickname or the CHIAKI_PROFILE environment variable.'
}
$app =(Resolve-Path -LiteralPath $AppDirectory).Path
$image = if ($ImagePath) { (Resolve-Path -LiteralPath $ImagePath).Path } else { '' }
if ($image -and -not (Test-Path -LiteralPath $image -PathType Leaf)) {
    throw "Image file not found: $image"
}
if ($UseExistingRegistration -and -not $image) {
    throw 'Existing-registration runs require the expected image for remote hash verification.'
}
foreach ($relative in @('eboot.bin', 'sce_sys\param.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $app $relative))) {
        throw "Missing required app file: $relative"
    }
}
$libcPath = Join-Path $app 'sce_module\libc.prx'
New-Item -ItemType Directory -Force -Path $ResultsDirectory | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$prefix = Join-Path $ResultsDirectory "$TitleId-$stamp"
$controllerWindows = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'send-controller.sh')).Path.Replace('\', '/')
$controller = (wsl.exe wslpath -a -- $controllerWindows).Trim()
if ($LASTEXITCODE -ne 0 -or -not $controller) {
    throw 'Could not translate the controller script path for WSL'
}
$chiakiStream = $null
$evidenceWarnings = [Collections.Generic.List[string]]::new()
$existingChiaki = @(Get-Process chiaki -ErrorAction SilentlyContinue)
if ($existingChiaki) {
    if ($PreserveExistingChiaki) {
        throw 'A Chiaki process already exists; close it or omit -PreserveExistingChiaki'
    }
    $existingChiaki | Stop-Process
    Start-Sleep -Seconds 1
}

function Start-ChiakiStream {
    if (-not (Test-Path -LiteralPath $ChiakiExecutable)) {
        throw "Chiaki executable not found: $ChiakiExecutable"
    }
    $process = Start-Process -FilePath $ChiakiExecutable -PassThru -ArgumentList @(
        'stream', $ChiakiNickname, $Ps5Host
    )
    $deadline = (Get-Date).AddSeconds($StreamStartupTimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 250
        $process.Refresh()
        if ($process.HasExited) { throw 'Chiaki stream exited before its window appeared' }
    } while ($process.MainWindowHandle -eq 0 -and (Get-Date) -lt $deadline)
    if ($process.MainWindowHandle -eq 0) { throw 'Chiaki stream window did not appear' }
    Start-Sleep -Seconds 2
    return $process
}

function Ensure-ChiakiStream {
    $chiakiStream.Refresh()
    if ($chiakiStream.HasExited -or $chiakiStream.MainWindowHandle -eq 0) {
        if (-not $chiakiStream.HasExited) {
            Stop-Process -Id $chiakiStream.Id
            Start-Sleep -Seconds 1
        }
        $script:chiakiStream = Start-ChiakiStream
        $evidenceWarnings.Add('Chiaki stream reconnected for evidence capture')
    }
    if (-not $SkipVideoReadiness) { Wait-ChiakiVideo }
}

function Invoke-Controller([string]$Mode, [string]$TargetTitle) {
    & wsl.exe bash $controller $Mode $TargetTitle $Ps5Host $ElfPort
    if ($LASTEXITCODE -ne 0) {
        throw "$Mode controller failed for $TargetTitle"
    }
}

function Get-ShadowMountLog {
    $url = "ftp://${Ps5Host}:${FtpPort}/data/shadowmount/debug.log"
    $text = & curl.exe --fail --silent --show-error --disable-epsv -u $FtpCredential $url
    if ($LASTEXITCODE -ne 0) { throw 'Could not read ShadowMount Plus log' }
    return ($text -join "`n")
}

function Test-TitleRuntimeActive([string]$Text, [string]$TargetTitle) {
    $started = $Text.LastIndexOf("[GAME] started: $TargetTitle")
    $released = $Text.LastIndexOf("[LINK] runtime layers released: $TargetTitle")
    return $started -ge 0 -and $released -lt $started
}

function Wait-TitleRuntimeRelease([string]$TargetTitle) {
    $deadline = (Get-Date).AddSeconds($RuntimeReleaseTimeoutSeconds)
    do {
        $text = Get-ShadowMountLog
        $started = $text.LastIndexOf("[GAME] started: $TargetTitle")
        $released = $text.LastIndexOf("[LINK] runtime layers released: $TargetTitle")
        if ($started -ge 0 -and $released -gt $started) { return }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw "ShadowMount did not confirm runtime release for $TargetTitle"
}

function Save-ChiakiScreenshot([string]$Path) {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    if (-not ('ChiakiWindow' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ChiakiWindow {
    [StructLayout(LayoutKind.Sequential)] public struct RECT {
        public int Left, Top, Right, Bottom;
    }
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, UIntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool altTab);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
}
'@
    }
    $chiakiStream.Refresh()
    if ($chiakiStream.HasExited -or $chiakiStream.MainWindowHandle -eq 0) {
        throw 'Managed Chiaki stream window is unavailable'
    }
    [void][ChiakiWindow]::ShowWindowAsync($chiakiStream.MainWindowHandle, 9)
    # Foreground activation can be denied when another Qt/Win32 window owns the
    # input queue. Raise Chiaki temporarily so CopyFromScreen cannot capture an
    # overlapping window even when SetForegroundWindow is ignored.
    $screen = [Windows.Forms.SystemInformation]::VirtualScreen
    [void][ChiakiWindow]::SetWindowPos($chiakiStream.MainWindowHandle, [IntPtr](-1),
        $screen.X, $screen.Y, $screen.Width, $screen.Height, 0x40)
    [ChiakiWindow]::SwitchToThisWindow($chiakiStream.MainWindowHandle, $true)
    [void][ChiakiWindow]::SetForegroundWindow($chiakiStream.MainWindowHandle)
    Start-Sleep -Milliseconds 500
    if ([ChiakiWindow]::GetForegroundWindow() -ne $chiakiStream.MainWindowHandle) {
        # Qt may assign foreground ownership to an internal/owned stream window.
        # The restored top-level rectangle is still capturable with CopyFromScreen.
        $evidenceWarnings.Add('Chiaki foreground ownership used an internal window handle')
    }
    $rect = [ChiakiWindow+RECT]::new()
    if (-not [ChiakiWindow]::GetWindowRect($chiakiStream.MainWindowHandle, [ref]$rect)) {
        throw 'Could not locate the managed Chiaki stream window'
    }
    $size = [Drawing.Size]::new($rect.Right - $rect.Left, $rect.Bottom - $rect.Top)
    $bitmap = [Drawing.Bitmap]::new($size.Width, $size.Height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        try {
            $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $size)
        } catch {
            $screenCaptureError = $_.Exception.Message
            $dc = $graphics.GetHdc()
            try {
                if (-not [ChiakiWindow]::PrintWindow(
                    $chiakiStream.MainWindowHandle, $dc, 2)) {
                    throw "PrintWindow returned false after CopyFromScreen failed: $screenCaptureError"
                }
            } finally {
                $graphics.ReleaseHdc($dc)
            }
            $evidenceWarnings.Add(
                "Chiaki screenshot used PrintWindow fallback: $screenCaptureError")
        }
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
        [void][ChiakiWindow]::SetWindowPos($chiakiStream.MainWindowHandle, [IntPtr](-2), 0, 0, 0, 0, 0x43)
    }
    return $chiakiStream
}

function Handle-CrashResult {
    $before = "$prefix-before-dismiss.png"
    try { [void](Save-ChiakiScreenshot $before) } catch {
        $evidenceWarnings.Add("before-dismiss screenshot: $($_.Exception.Message)")
    }
    try {
        $shell = New-Object -ComObject WScript.Shell
        if (-not $shell.AppActivate($chiakiStream.Id)) {
            throw 'Could not focus the Chiaki crash dialog'
        }
        Start-Sleep -Milliseconds 300
        $shell.SendKeys('{ENTER}')
        Start-Sleep -Seconds 2
    } catch {
        $evidenceWarnings.Add("crash-dialog dismissal: $($_.Exception.Message)")
    }
    try {
        $runtimeLog = Get-ShadowMountLog
        if (Test-TitleRuntimeActive $runtimeLog $TitleId) {
            Invoke-Controller close $TitleId
            Wait-TitleRuntimeRelease $TitleId
        } else {
            Write-Host "CRASH_RUNTIME_ALREADY_RELEASED $TitleId"
        }
    } catch {
        $evidenceWarnings.Add("runtime release after crash: $($_.Exception.Message)")
    }
    try {
        Ensure-ChiakiStream
        [void](Save-ChiakiScreenshot "$prefix-after-crash.png")
    } catch {
        $evidenceWarnings.Add("after-crash screenshot: $($_.Exception.Message)")
    }
}

function Wait-ChiakiVideo {
    $probe = "$prefix-stream-probe.png"
    $deadline = (Get-Date).AddSeconds($VideoReadyTimeoutSeconds)
    $lastCaptureError = ''
    do {
        try {
            [void](Save-ChiakiScreenshot $probe)
            $bitmap = [Drawing.Bitmap]::FromFile($probe)
            try {
                $bright = 0
                $samples = 0
                for ($y = 48; $y -lt $bitmap.Height; $y += 32) {
                    for ($x = 16; $x -lt $bitmap.Width; $x += 32) {
                        $pixel = $bitmap.GetPixel($x, $y)
                        if ([Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B)) -gt 40) { $bright++ }
                        $samples++
                    }
                }
                if ($samples -gt 0 -and ($bright / $samples) -ge 0.03) { return }
            } finally {
                $bitmap.Dispose()
            }
        } catch {
            # Foreground ownership can be briefly unavailable while Chiaki connects.
            $lastCaptureError = $_.Exception.Message
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw "Chiaki did not display a non-loading PS5 video frame. Last capture error: $lastCaptureError"
}

try {
if ($PreviousTitleId) {
    Invoke-Controller close $PreviousTitleId
    Start-Sleep -Seconds 2
}

$shadowBaseline = Get-ShadowMountLog
if ($UseExistingRegistration) {
    $remoteProbe = Join-Path ([IO.Path]::GetTempPath()) `
        ("ps5-existing-{0}-{1}.ffpfsc" -f $TitleId, $PID)
    try {
        if (Test-Path -LiteralPath $remoteProbe) {
            throw "Refusing to reuse remote verification file: $remoteProbe"
        }
        $imageUrl = "ftp://${Ps5Host}:${FtpPort}/data/homebrew/$TitleId.ffpfsc"
        & curl.exe --fail --silent --show-error --disable-epsv -u $FtpCredential `
            $imageUrl --output $remoteProbe
        if ($LASTEXITCODE -ne 0) { throw "Remote image download failed: $imageUrl" }
        $expectedHash = (Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash
        $remoteHash = (Get-FileHash -LiteralPath $remoteProbe -Algorithm SHA256).Hash
        if ($remoteHash -ne $expectedHash) {
            throw "Remote image hash mismatch for $TitleId."
        }
        Write-Host "REMOTE_IMAGE_VERIFIED $TitleId $remoteHash"
    } finally {
        if (Test-Path -LiteralPath $remoteProbe) {
            Remove-Item -LiteralPath $remoteProbe -Force
        }
    }
} elseif ($image) {
    $imageUrl = "ftp://${Ps5Host}:${FtpPort}/data/homebrew/$TitleId.ffpfsc"
    & curl.exe --fail --silent --show-error --disable-epsv -u $FtpCredential `
        -T $image $imageUrl
    if ($LASTEXITCODE -ne 0) { throw "Image upload failed: $image" }
} else {
    $ftpRoot = "ftp://${Ps5Host}:${FtpPort}/data/homebrew/$TitleId"
    Get-ChildItem -LiteralPath $app -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($app.Length).TrimStart('\').Replace('\', '/')
        & curl.exe --fail --silent --show-error --disable-epsv -u $FtpCredential --ftp-create-dirs -T $_.FullName "$ftpRoot/$relative"
        if ($LASTEXITCODE -ne 0) { throw "Upload failed: $relative" }
    }
}

$installed = "NOTIFY: installed game $TitleId"
$mounted = "[LINK] mount.lnk created: /user/app/$TitleId/mount.lnk ->"
if ($UseExistingRegistration) {
    $shadowLog = $shadowBaseline
    if (-not ($shadowLog.Contains($installed) -or $shadowLog.Contains($mounted))) {
        $shadowLog | Set-Content -LiteralPath "$prefix-shadowmount-registration-failed.log"
        throw "ShadowMount has no registration evidence for $TitleId; do not launch"
    }
    Write-Host "EXISTING_REGISTRATION_CONFIRMED $TitleId"
} else {
    $deadline = (Get-Date).AddSeconds($RegistrationTimeoutSeconds)
    do {
        $shadowLog = Get-ShadowMountLog
        $shadowDelta = if ($shadowLog.StartsWith($shadowBaseline)) {
            $shadowLog.Substring($shadowBaseline.Length)
        } else {
            $shadowLog
        }
        if ($shadowDelta.Contains($installed) -or $shadowDelta.Contains($mounted)) { break }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $deadline)
    if (-not ($shadowDelta.Contains($installed) -or $shadowDelta.Contains($mounted))) {
        $shadowLog | Set-Content -LiteralPath "$prefix-shadowmount-registration-failed.log"
        throw "ShadowMount did not confirm $TitleId; do not launch"
    }
}
$shadowLog | Set-Content -LiteralPath "$prefix-shadowmount.log"
$chiakiStream = Start-ChiakiStream
if ($SkipVideoReadiness) {
    $evidenceWarnings.Add('Chiaki video readiness skipped by caller')
} else {
    Wait-ChiakiVideo
}

$client = [Net.Sockets.TcpClient]::new()
$client.Connect($Ps5Host, $KlogPort)
$stream = $client.GetStream()
$buffer = [byte[]]::new(65536)
$drainUntil = (Get-Date).AddMilliseconds(800)
do {
    while ($stream.DataAvailable) { [void]$stream.Read($buffer, 0, $buffer.Length) }
    Start-Sleep -Milliseconds 50
} while ((Get-Date) -lt $drainUntil)

Invoke-Controller launch $TitleId
$captured = [Text.StringBuilder]::new()
$observeUntil = (Get-Date).AddSeconds($ObservationSeconds)
do {
    while ($stream.DataAvailable) {
        $count = $stream.Read($buffer, 0, $buffer.Length)
        if ($count -gt 0) {
            [void]$captured.Append([Text.Encoding]::UTF8.GetString($buffer, 0, $count))
        }
    }
    Start-Sleep -Milliseconds 100
} while ((Get-Date) -lt $observeUntil)
$client.Dispose()
$klog = $captured.ToString()
$launchMarker = "launchApp($TitleId)"
$launchIndex = $klog.LastIndexOf($launchMarker)
if ($launchIndex -ge 0) { $klog = $klog.Substring($launchIndex) }
$klog | Set-Content -LiteralPath "$prefix-klog.log"
$postShadowLog = Get-ShadowMountLog
$postShadowLog | Set-Content -LiteralPath "$prefix-shadowmount-after-launch.log"
$rtldDiagnostic = @($postShadowLog -split "`n" | Where-Object {
    $_ -match "PPSA$($TitleId.Substring(4))|dynlib_|\[rtld\]"
} | Select-Object -Last 5)

if ($klog -match 'PRX_SCE_MODULE_LOAD_ERROR|0xA0020102') {
    $outcome = 'loader-error'
    Handle-CrashResult
} elseif ($klog -match 'A user thread receives a fatal signal|App Crash') {
    $outcome = if ($klog -match 'EXEC /app0/eboot.bin') { 'runtime-crash-after-eboot' } else { 'runtime-crash-before-eboot' }
    Handle-CrashResult
} elseif ($klog -match 'EXEC /app0/eboot.bin') {
    $outcome = 'entered-eboot'
    try {
        Ensure-ChiakiStream
        [void](Save-ChiakiScreenshot "$prefix-running.png")
    } catch {
        $evidenceWarnings.Add("running screenshot: $($_.Exception.Message)")
    }
    Invoke-Controller close $TitleId
    try { Wait-TitleRuntimeRelease $TitleId } catch {
        $evidenceWarnings.Add("runtime release after close: $($_.Exception.Message)")
    }
    try {
        Ensure-ChiakiStream
        [void](Save-ChiakiScreenshot "$prefix-after-close.png")
    } catch {
        $evidenceWarnings.Add("after-close screenshot: $($_.Exception.Message)")
    }
} else {
    $outcome = 'inconclusive'
    try { [void](Save-ChiakiScreenshot "$prefix-inconclusive.png") } catch {
        $evidenceWarnings.Add("inconclusive screenshot: $($_.Exception.Message)")
    }
    if (Test-TitleRuntimeActive $postShadowLog $TitleId) {
        try {
            Invoke-Controller close $TitleId
            Wait-TitleRuntimeRelease $TitleId
        } catch {
            $evidenceWarnings.Add("runtime cleanup after inconclusive result: $($_.Exception.Message)")
        }
    }
}

$result = [ordered]@{
    titleId = $TitleId
    outcome = $outcome
    timestamp = $stamp
    appDirectory = $app
    imagePath = $image
    imageSha256 = if ($image) { (Get-FileHash $image -Algorithm SHA256).Hash } else { '' }
    ebootSha256 = (Get-FileHash (Join-Path $app 'eboot.bin') -Algorithm SHA256).Hash
    libcSha256 = if (Test-Path -LiteralPath $libcPath -PathType Leaf) {
        (Get-FileHash $libcPath -Algorithm SHA256).Hash
    } else {
        $null
    }
    evidenceWarnings = @($evidenceWarnings)
    rtldDiagnostic = @($rtldDiagnostic)
}
$result | ConvertTo-Json | Set-Content -LiteralPath "$prefix-result.json"
[pscustomobject]$result
} finally {
    if ($chiakiStream -and -not $chiakiStream.HasExited) {
        Stop-Process -Id $chiakiStream.Id
    }
}
