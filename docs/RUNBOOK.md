# PS5 homebrew runbook

Use this for one bounded development or validation case. Project history and
transient results belong in the consuming project's plan and handoff.

## 1. Define the case

Record before work:

- active goal and observable acceptance criterion;
- one changed variable and known-good control;
- title ID, firmware, host, required services, and stop condition; and
- source commit plus expected artifact paths.

Every project is an independent local Git repository. Preserve unrelated user
changes. Never mix app, runtime, loader, debugger, or protocol changes in one
experiment.

## 2. Finish offline first

Use WSL to format, lint, test, build, package, and inspect the smallest useful
change. Prefer secure C++20: RAII, unique ownership, bounded containers/views,
validated sizes and offsets, checked API results, explicit C ABI boundaries,
warnings as errors, and deterministic shutdown.

Commit the exact candidate before hardware validation. Record tool versions,
file sizes, and SHA-256 for the executable, runtime modules, metadata, and
package. A rebuild, resign, repack, or metadata edit creates a new candidate.
For cross-firmware claims, deploy the same frozen bytes everywhere and test the
safer console first.

Freeze the built folder as a candidate (`scripts/freeze-candidate.sh`) and install
the copy: a rebuild must never change what a queued cycle uploads.

Do not hold a PS5 lock during offline work.

## 3. Run one console cycle

From WSL or Linux, `scripts/ps5-cycle.sh` runs these steps as one command;
[FAST_CYCLES.md](FAST_CYCLES.md) explains how to get the most from each launch.

1. **Lock:** For shared consoles, atomically create the environment's lock with
   a unique token. If it exists, wait 15 seconds and retry. Never infer that a
   lock is stale. Dedicated-console exceptions must be written in
   `.local/ENVIRONMENT.md`.
2. **Preflight:** Probe only declared services. Normally require FTP `2121`,
   klog `3232`, and elfldr/shsrv `9021`. Establish an idle state and close only
   the exact prior title or dialog. If another title is running, it is someone's
   session: do not launch over it and do not close it.
3. **Deploy:** Upload under a temporary name, promote only after transfer,
   verify remote bytes or the immutable image hash, and wait for
   title-specific ShadowMount readiness. Install into the folder the title is
   mounted from (`ps5-console.py where`), which is not always the default one.
   Do not launch on a hash mismatch or ambiguous registration. After an upload, and after any unexpected console
   restart, wait about two minutes and compare the install again: a console can
   come back from a crash with the last files written as zero bytes.
4. **Observe:** Save klog to a file before launching the exact title. Run once
   for a bounded period, ended by the app's own ready line where it has one. Capture only evidence required by the criterion:
   ShadowMount lifecycle, the app's own log, or a declared debugger
   snapshot.
5. **Close:** Prefer an app-initiated exit, then send the title-aware close
   controller ([CONTROLLERS.md](CONTROLLERS.md)) as a safety net. Require a
   title-specific stop and, when available, runtime-layer release. Confirm
   declared services remain healthy.
6. **Unlock:** Remove the lock in `finally` only when its contents still match
   your token. Release it before analysis, editing, or rebuilding.

Replacing the files of a closed title, with nothing launched or closed, is not a
console cycle and needs no lock; the install refuses a title that is running.

The console boundary is absolute: never enter Settings, change configuration,
approve an update, start undeclared payloads, kill guessed processes, or send
input to an ambiguous screen.

## 4. Keep evidence out of context

Store raw output in `results/`; never print entire klog or ShadowMount files.
No diary or copied tool output: write only a changed decision, blocker, or
milestone, and link existing evidence.
Extract a bounded, title-specific slice, for example:

```bash
rg -a 'PPSA99999|EXEC /app0|crash|game stopped|runtime layers released' \
  results/run/*.log | tail -n 100
```

Use one physical line per milestone, targeting 200 characters or fewer:

```text
- YYYY-MM-DD | G# | commit | target | classification: highest-stage | evidence-path | next-action
```

Keep hashes, commands, and raw output in the referenced result files. Add prose
only for a safety issue or blocker that cannot fit on the line.

Stages are independent: built, packaged, remotely verified, registered,
loader entry, app checkpoint, rendering, input, filesystem, network, audio,
functional scenario, and teardown. A visible frame does not prove stability.

## 5. Classify and continue

Use exactly one state:

- `pass`: every criterion and clean teardown passed;
- `partial-pass`: named stages passed but acceptance is incomplete;
- `failed`: direct loader, runtime, functional, teardown, or health failure;
- `inconclusive`: execution occurred but evidence is missing or contaminated;
- `transport-failure`: failure occurred before a reliable execution boundary;
- `no-run`: the case was blocked before execution.

Retry identical bytes once only for a proven transport or stale-registration
failure. Do not chain unattended cycles; check service health between runs and
stop at the first anomaly. After a suspected kernel panic, preserve evidence
and analyze offline; do not automatically rerun. A refused connection means the
console restarted and its services are not loaded; a timeout means it is off
or unreachable. Neither is retried. If environment health is uncertain, run a
distributable known-good control before blaming the candidate.

For diagnosis, escalate only as needed: host inspection → app checkpoints →
klog/ShadowMount → visual evidence → read-only MemDBG/PS5-Debug-NG → validated
debugger attach → custom loader/kstuff experiment.

A proven milestone ends with current plan/handoff state, one milestone line,
and an atomic validation commit. Do not label failed or incomplete work
known-good.
