# Controller-free launch and close

This page describes how the repository launches and closes a PS5 title from a
development PC, without selecting it with a controller. It is the mechanism
behind [`Invoke-Ps5Cycle.ps1`](../scripts/Invoke-Ps5Cycle.ps1) and can be used on
its own.

## How it works

[`send-controller.sh`](../scripts/send-controller.sh) compiles a tiny payload
with the PS5 Payload SDK and streams it to the ELF loader on the console. The
title ID is fixed at compile time (`-DBOOTSTRAP_TITLE_ID="PPSA99999"`), so every
payload targets exactly one title and accepts no input from the network.

### Launch

[`launch.c`](../scripts/controllers/launch.c):

1. `sceUserServiceInitialize`
2. `sceUserServiceGetForegroundUser` — the app starts for the signed-in user
   currently in front of the console
3. `sceSystemServiceLaunchApp(title_id, argv, &context)`
4. `sceUserServiceTerminate`

The title must already be installed or registered (for example by ShadowMount
Plus). Launching an unregistered title fails.

### Close

[`close.c`](../scripts/controllers/close.c):

1. `sceLncUtilGetAppIdOfRunningBigApp` finds the foreground application.
2. `sceLncUtilGetAppTitleId` reads its title ID.
3. Only if the title ID matches, `sceLncUtilKillApp` terminates it.
4. Otherwise it falls back to `sceSystemServiceGetAppId(title_id)` followed by
   `sceSystemServiceKillApp(app_id, -1, 0, 0)`.

Because of the title check, sending `close PPSA99999` never terminates a
different game that happens to be running.

## Usage

Requirements: `bash`, `nc`, `timeout`, and the PS5 Payload SDK
(`$PS5_PAYLOAD_SDK`, default `/opt/ps5-payload-sdk`). On the console, an ELF
loader such as elfldr or shsrv must listen on the payload port (usually
`9021`).

```bash
scripts/send-controller.sh close  PPSA99999 <ps5-ip> 9021
scripts/send-controller.sh launch PPSA99999 <ps5-ip> 9021
```

To build without sending, for example to inspect or reuse the ELF:

```bash
PS5_CONTROLLER_COMPILE_ONLY=1 scripts/send-controller.sh launch PPSA99999 - -
```

The script prints the path of the built ELF and exits.

## A typical redeploy loop

```text
close title  →  upload new build (FTP)  →  wait for ShadowMount registration
             →  launch title  →  observe (klog, screenshots)  →  close title
```

`Invoke-Ps5Cycle.ps1` implements this loop, including hash verification of a
pre-built image, waiting for the ShadowMount `installed game` or `mount.lnk`
event, capturing klog from the moment of launch, and confirming the ShadowMount
`runtime layers released` event after the close.

## What success means

A zero exit status from `send-controller.sh` only means the payload was
delivered. The loader does not report the payload's own result back to the PC.
Confirm the effect from the console's logs instead:

| Action | Evidence |
| --- | --- |
| Launch | klog `launchApp(PPSA99999)` then `EXEC /app0/eboot.bin`; ShadowMount `[GAME] started: PPSA99999` |
| Close | ShadowMount `[LINK] runtime layers released: PPSA99999` |

## Shut down gracefully when you can

The close controller terminates the process immediately; the app gets no
chance to flush files, stop threads, or release GPU and audio resources. That
is acceptable for occasional runs, but repeated kills of a title that is still
rendering are harder on the system. We have seen a kernel panic after a long
unattended series of such cycles; the cause was not established, but it is a
good reason to be conservative.

Recommended practice for automated test runs:

- Give the app its own exit path (a test-complete condition, a dev-only button
  combination, or a trigger file) and let it return from `main` first.
- Send the close controller afterwards as a safety net, when the title is idle
  or already gone.
- Run one cycle at a time, check that the console services still respond
  between cycles, and stop at the first anomaly such as a close that never
  produces `runtime layers released`.

## Credits

`launch.c` is adapted from `launch_app()` in
[shsrv](https://github.com/ps5-payload-dev/shsrv), and the `close.c` fallback
follows `sys_launch_title()` in
[websrv](https://github.com/ps5-payload-dev/websrv), both by John Törnblom
(GPL-3.0-or-later). See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
