# Tool reference

Read this page only when selecting instrumentation or diagnosing a service.
Closed optional ports do not fail a run unless the experiment declared them.

| Tool | Endpoint | Use and constraint |
| --- | --- | --- |
| FTP/ftpsrv | PS5 TCP `2121` | Atomic deployment and authorized evidence retrieval. Verify bytes; reachability is not registration. |
| klog | PS5 TCP `3232` | Primary loader/kernel/system evidence. Save the stream to disk. Do not substitute a transient/source port such as `40972`. Silence alone is not a kernel panic. |
| elfldr/shsrv | PS5 TCP `9021` | Receives the title-aware launch/close controllers ([CONTROLLERS.md](CONTROLLERS.md)). Transport success is not app success. |
| ShadowMount Plus | FTP `/data/shadowmount/debug.log` | Registration, mount, start, crash, stop, kstuff, and release lifecycle. Query by exact title. |
| kstuff-lite | No service port | Execution environment. Do not change it with the app/runtime in the same experiment. |
| websrv | PS5 TCP `8080` when used | Optional HTTP/hbldr service or liveness signal. |
| MemDBG | PS5 TCP `9020` when used | Optional process/module/memory view. Start read-only; writes, stops, and breakpoints require a separate experiment. |
| PS5-Debug-NG | PS5 TCP `744` (typical) | Optional independent exception/process evidence. Attaching can alter timing. |
| Chiaki | Remote Play | Visual evidence and bounded input to one owned process/window. See [CHIAKI_INPUT.md](CHIAKI_INPUT.md). |
| IDA + PS5 plugin/MCP | Offline | Static hypotheses from hashed inputs. Decompiled code is inference, not hardware proof. |
| Checkpoint receiver | PC TCP port chosen by the project (for example `8767`) | Ordered app-owned HTTP stages. Verify the listening PID and use a run-specific path. |

Use WSL for probes, FTP, hashing, controller traffic, and log filtering. Use
Windows only for required GUI tools such as Chiaki, IDA, or ShareX.

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
| `Invoke-Ps5Cycle.ps1` | Caller; runs one deploy/launch/capture/close cycle. |
| `send-controller.sh` | Caller; launches or closes one exact title. |
| `Remove-Ps5Experiments.ps1` | Caller; removes only explicitly named experiments. |
| `Get-Ps5DownloadData.ps1` | Script acquires and releases the lock. |
| `Test-ShadowMountHealth.ps1` | Script acquires and releases the lock. |

Never call a self-locking helper while already holding the same lock.

Common environment variables:

| Variable | Used by | Meaning |
| --- | --- | --- |
| `PS5_HOST` | All PowerShell helpers | Console address when `-Ps5Host` is omitted |
| `CHIAKI_PROFILE` | `Invoke-Ps5Cycle.ps1` | chiaki-ng registered console nickname |
| `PS5_PROTECTED_TITLES` | `Remove-Ps5Experiments.ps1` | Comma-separated title IDs that must never be removed |
| `PS5_PAYLOAD_SDK` | `send-controller.sh` | PS5 Payload SDK root (default `/opt/ps5-payload-sdk`) |
| `PS5_CONTROLLER_COMPILE_ONLY` | `send-controller.sh` | `1` builds the controller without sending it |

The self-locking helpers use `Documents\PS5\lock.txt` by default; pass
`-LockPath` to share a different lock file.
