# ps5-homebrew-dev-protocol

An evidence-driven workflow and tooling for developing and validating native
PS5 homebrew on real hardware.

The repository gives you two things:

- **A protocol**: a short, repeatable procedure for turning a code change into
  a hardware result you can trust. You change one variable, freeze the exact
  bytes, run one bounded console cycle, and record a single classified result.
- **Automation**: scripts that deploy, launch, observe, capture, and close a
  title over the LAN without anyone touching a controller.

It was written for humans and for coding agents that work on a console. The
rules are deliberately strict so that unattended runs stay safe and their
results can be reproduced.

## Launch and close apps without a controller

A common homebrew testing loop is: close the app, redeploy it, wait for
ShadowMount Plus to register it, and launch it again. This repository automates
that loop with two small **title-aware controller payloads** sent to the ELF
loader:

| Controller | System calls | Behavior |
| --- | --- | --- |
| [`launch.c`](scripts/controllers/launch.c) | `sceUserServiceGetForegroundUser`, `sceSystemServiceLaunchApp` | Launches one title ID for the foreground user. |
| [`close.c`](scripts/controllers/close.c) | `sceLncUtilGetAppIdOfRunningBigApp`, `sceLncUtilGetAppTitleId`, `sceLncUtilKillApp` (fallback `sceSystemServiceKillApp`) | Closes the running app **only** if its title ID matches, so it never kills an unrelated game. |

The title ID is compiled into the payload, so each payload does exactly one
thing. From Linux or WSL:

```bash
export PS5_PAYLOAD_SDK=/opt/ps5-payload-sdk
scripts/send-controller.sh close  PPSA99999 <ps5-ip> 9021
scripts/send-controller.sh launch PPSA99999 <ps5-ip> 9021
```

[`ps5-cycle.sh`](scripts/ps5-cycle.sh) runs the full
lock → close → verified install → settle → launch → collect logs → unlock
cycle, one line per step. See [docs/CONTROLLERS.md](docs/CONTROLLERS.md) for
details, exit codes, and safe-shutdown guidance.

## Requirements

On the console (all started by the owner):

| Service | Default port | Used for |
| --- | --- | --- |
| [elfldr](https://github.com/ps5-payload-dev/elfldr) or [shsrv](https://github.com/ps5-payload-dev/shsrv) | TCP `9021` | Receiving controller payloads |
| [ftpsrv](https://github.com/ps5-payload-dev/ftpsrv) | TCP `2121` | Deployment and evidence retrieval |
| [klogsrv](https://github.com/ps5-payload-dev/klogsrv) | TCP `3232` | Kernel and loader log |
| [ShadowMount Plus](https://github.com/drakmor/ShadowMountPlus) | — | Title registration and lifecycle log |

On the development PC:

- Linux or Windows with WSL, `bash`, `nc` (netcat), and `curl`;
- the [PS5 Payload SDK](https://github.com/ps5-payload-dev/sdk) (for
  `prospero-clang`);
- for the managed cycle: WSL or Linux with `bash`, `python3` and `nc`.

Remote Play is not needed. Earlier versions watched the console through chiaki-ng
to take screenshots; pictures drawn by a PC build of the app, the app's own log
and a person's eyes answer the same questions without it
([Fast console cycles](docs/FAST_CYCLES.md)). The Windows cycle that used it,
`Invoke-Ps5Cycle.ps1`, is kept only for projects that still call it.

## Quick start

1. Set your environment once per shell:

   ```bash
   export PS5_HOST=192.0.2.10                    # your console's LAN address
   export PS5_LOCK=/path/shared/lock-console.txt # one lock file per console
   ```

2. Freeze the built app folder, then run one cycle with it:

   ```bash
   scripts/freeze-candidate.sh dist/PPSA99999 ~/candidates/first-run
   scripts/ps5-cycle.sh PPSA99999 ~/candidates/first-run/PPSA99999 \
       /data/shadowmount/debug.log
   ```

3. Read the lines it prints (state before and after, install and settle checks,
   error records) and the logs it saved under `results/`.

`PS5_LAUNCH=0` installs and verifies without launching; the other switches are
listed at the top of the script and in [Tools](docs/TOOLS.md).

## The protocol in brief

1. **Plan.** Keep a plan with numbered, measurable goals (`G1`, `G2`, …) in the
   project's own Git repository.
2. **Finish offline first.** Change one variable, build and test on the host,
   commit the exact candidate, and record artifact SHA-256 hashes.
3. **Run one bounded console cycle.** Lock, preflight, deploy, verify,
   launch, capture, close, health-check, unlock.
4. **Classify and record.** Assign exactly one outcome (`pass`,
   `partial-pass`, `failed`, `inconclusive`, `transport-failure`, `no-run`)
   and write one milestone line that points to the evidence.

The full procedure is in the [runbook](docs/RUNBOOK.md).

## Safety principles

- Never open or change console Settings, and never start, approve, or install
  a system update.
- Use only services the console owner started on the local network.
- Stop on any Settings, Store, sign-in, update, or unexpected screen.
- On a shared console, hold a lock only for the duration of one console cycle
  and never remove someone else's lock.
- After a suspected kernel panic, preserve the evidence and analyze it offline
  instead of retrying.

## Repository layout

| Path | Contents |
| --- | --- |
| [`docs/RUNBOOK.md`](docs/RUNBOOK.md) | The protocol: one bounded development or validation case |
| [`docs/CONTROLLERS.md`](docs/CONTROLLERS.md) | Controller-free launch and close |
| [`docs/FAST_CYCLES.md`](docs/FAST_CYCLES.md) | Getting more from each console launch: host checks, frozen candidates, the one-command cycle, logs |
| [`docs/TOOLS.md`](docs/TOOLS.md) | Console services, debuggers, and helper scripts |
| [`docs/PROJECT_PLAN_TEMPLATE.md`](docs/PROJECT_PLAN_TEMPLATE.md) | Template for a new project plan |
| [`docs/HANDOFF_TEMPLATE.md`](docs/HANDOFF_TEMPLATE.md) | Template for handing work to another developer or agent |
| [`scripts/`](scripts) | Managed cycle, controllers, and console helpers |
| [`examples/iptv/`](examples/iptv) | An application-specific wrapper with fixtures and receipt validation, built on the legacy Windows cycle |
| [`scripts/readme-footer/`](scripts/readme-footer) | Generator for the standard footer used across BlackBearReloaded repositories |
| [`AGENTS.md`](AGENTS.md) | Instructions for coding agents |
| `results/` | Local evidence output (ignored by Git) |

## Contributing

Issues and pull requests are welcome. Keep changes small and focused, keep
scripts free of hard-coded hosts and personal paths, and do not commit
generated media, raw captures, credentials, proprietary modules, or SDK files.

<!-- bbr-footer:start -->
<!-- Generated by ps5-homebrew-dev-protocol/scripts/readme-footer. Edit the template there, not here. -->

## Credits

Built with the [PS5 Payload SDK](https://github.com/ps5-payload-dev/sdk) by John Törnblom (ps5-payload-dev).
Third-party components, authors and licenses are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

Copyright © 2026 BlackBearReloaded. Licensed under GPL-3.0-or-later; see [LICENSE](LICENSE). Third-party components keep their own licenses.

## Disclaimer

- **No affiliation.** This is an independent homebrew project. It is not
  affiliated with, endorsed by, or sponsored by Sony Interactive Entertainment.
  "PlayStation", "PS5" and related marks are trademarks of Sony Interactive
  Entertainment Inc.
- **No proprietary material.** No Sony SDK, firmware, encryption keys or
  decrypted system modules are included.
- **No warranty.** This project is provided "as is", without warranty of any
  kind, to the extent permitted by law. See sections 15 and 16 of the GPL.
- **Use at your own risk.** Running homebrew requires a modified console, which
  may void its warranty, breach the platform's terms of service, or cause data
  loss.
- **Legal use only.** Use it only with hardware, accounts and content you own.
  This project does not support or enable piracy.

## AI assistance

This project was developed with AI assistance from OpenAI and/or Anthropic tools.
<!-- bbr-footer:end -->
