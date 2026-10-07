# Tool reference

Read this page only when selecting instrumentation or diagnosing a service.
Closed optional ports do not fail a run unless the experiment declared them.

| Tool | Endpoint | Use and constraint |
| --- | --- | --- |
| FTP/ftpsrv | PS5 TCP `2121` | Atomic deployment and authorized evidence retrieval. Verify bytes; reachability is not registration. |
| klog | PS5 TCP `3232` | Primary loader/kernel/system evidence. Save the stream to disk. Do not substitute a transient/source port such as `40972`. Silence alone is not a kernel panic. |
| elfldr/shsrv | PS5 TCP `9021` | Receives the title-aware launch/close controllers ([CONTROLLERS.md](CONTROLLERS.md)). Transport success is not app success. |
| Sandbox mounts | FTP `/mnt/sandbox` | A running title has a `<TITLE>_*` entry: the state check that needs no input (`ps5-console.py state`, and `titles` for everything that runs; `NPXS…` entries are the system's own). |
| Mount link | FTP `/user/app/<TITLE>/mount.lnk`, `mount_img.lnk` | The folder or image ShadowMount Plus mounted the title from (`ps5-console.py where`). Install there, not to a fixed folder. |
| Mounted app | `/system_ex/app/<TITLE>` | The running title's own files as an app with filesystem access sees them, whatever the source. |
| Error records | FTP `/system_data/priv/error/history` | One JSON file per system error. Compare the newest before and after a run (`ps5-console.py errors`). |
| ShadowMount Plus | FTP `/data/shadowmount/debug.log` | Registration, mount, start, crash, stop, kstuff, and release lifecycle. Query by exact title. |
| kstuff-lite | No service port | Execution environment. Do not change it with the app/runtime in the same experiment. |
| websrv | PS5 TCP `8080` when used | Optional HTTP/hbldr service or liveness signal. |
| MemDBG | PS5 TCP `9020` when used | Optional process/module/memory view. Start read-only; writes, stops, and breakpoints require a separate experiment. |
| PS5-Debug-NG | PS5 TCP `744` (typical) | Optional independent exception/process evidence. Attaching can alter timing. |
| IDA + PS5 plugin/MCP | Offline | Static hypotheses from hashed inputs. Decompiled code is inference, not hardware proof. |
| Checkpoint receiver | PC TCP port chosen by the project (for example `8767`) | Ordered app-owned HTTP stages. Verify the listening PID and use a run-specific path. |

Use WSL for probes, FTP, hashing, controller traffic, and log filtering. Use
Windows only for required GUI tools such as IDA.

Useful bounded commands:

```bash
nc -z -w 3 PS5_HOST 2121
timeout 30 nc PS5_HOST 3232 > results/run/klog.txt
curl --fail --silent --show-error -u anonymous:anonymous \
  ftp://PS5_HOST:2121/data/shadowmount/debug.log \
  -o results/run/shadowmount.log
```

Choose the least invasive evidence source that can answer the question. More
debuggers are not automatically better: logging, notifications, attaches, and
breakpoints can change timing, memory layout, and process state.

## Repository helpers

| Script | Lock owner |
| --- | --- |
| `Invoke-Ps5Cycle.ps1` | Caller. Legacy Windows cycle that captures screenshots through chiaki-ng Remote Play; kept for projects that still call it. New work uses `ps5-cycle.sh`. |
| `ps5-cycle.sh` | Script acquires and releases the lock; one cycle from WSL or Linux: close, verified install, settle, launch, wait for the app's line, logs and kernel log. With `PS5_LAUNCH=0` and a closed title it takes no lock. |
| `ps5-console.py` | None needed: `state`, `titles`, `where`, `size`, `wait`, `errors` and `fetch` only read; `install` refuses a running title and a folder the title is not mounted from; `put` writes one named file. |
| `freeze-candidate.sh` | None: local only. Copies a built folder and writes its `SHA256SUMS`. |
| `send-controller.sh` | Caller; launches or closes one exact title. |
| `Remove-Ps5Experiments.ps1` | Caller; removes only explicitly named experiments. |
| `Get-Ps5DownloadData.ps1` | Script acquires and releases the lock. |
| `Test-ShadowMountHealth.ps1` | Script acquires and releases the lock. |

Never call a self-locking helper while already holding the same lock.

Error codes that have had one cause each so far:

| Code | Seen when | Check |
| --- | --- | --- |
| CE-107750-0 ("Can't start the game or app") | The app's files are not open to every user | Modes are 0777 on the console; the release archive stores 0777 |
| CE-118038-1 ("Can't start") | Files written just before a crash came back as zero bytes | `ps5-console.py settle`, then install again |

Common environment variables:

| Variable | Used by | Meaning |
| --- | --- | --- |
| `PS5_HOST` | All PowerShell helpers, `ps5-cycle.sh`, `ps5-console.py` | Console address when `-Ps5Host` is omitted |
| `PS5_LOCK` | `ps5-cycle.sh` | Lock file shared by everyone who uses that console |
| `PS5_SETTLE`, `PS5_RUN`, `PS5_LAUNCH`, `PS5_CLOSE` | `ps5-cycle.sh` | Seconds to watch after the upload (130), seconds to run (45), `0` to install only, `1` to close after the run |
| `PS5_READY_LOG`, `PS5_READY_PATTERN` | `ps5-cycle.sh` | A log the app writes and a regular expression: go on when a new line matches, fail after `PS5_RUN` seconds without one |
| `PS5_KLOG`, `PS5_KLOG_PORT` | `ps5-cycle.sh` | `0` does not record the kernel log during the run; its port (`3232`) |
| `PS5_OTHER_TITLES` | `ps5-cycle.sh` | `1` launches although another title is running |
| `PS5_FTP_PORT`, `PS5_FTP_USER`, `PS5_FTP_PASSWORD`, `PS5_INSTALL_ROOT` | `ps5-console.py` | FTP endpoint and the folder titles are installed under (`/data/homebrew`) |
| `PS5_INSTALL_UNCHECKED` | `ps5-console.py` | `1` installs to `PS5_INSTALL_ROOT` whatever the mount link says |
| `CHIAKI_PROFILE` | `Invoke-Ps5Cycle.ps1` (legacy) | chiaki-ng registered console nickname |
| `PS5_PROTECTED_TITLES` | `Remove-Ps5Experiments.ps1` | Comma-separated title IDs that must never be removed |
| `PS5_PAYLOAD_SDK` | `send-controller.sh` | PS5 Payload SDK root (default `/opt/ps5-payload-sdk`) |
| `PS5_CONTROLLER_COMPILE_ONLY` | `send-controller.sh` | `1` builds the controller without sending it |

The self-locking helpers use `Documents\PS5\lock.txt` by default; pass
`-LockPath` to share a different lock file.
