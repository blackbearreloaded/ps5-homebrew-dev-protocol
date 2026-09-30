# Chiaki observation and input

Read this only when a test requires Remote Play, automated controller input, screenshots, or audio capture. Follow [RUNBOOK.md](RUNBOOK.md) for the experiment lifecycle and console lock.

## Boundary and launch

- Use only an already configured Chiaki-ng profile. Never change PS5 settings, registration, networking, accounts, or update state.
- Close unrelated Chiaki-ng windows before the case. Launch a single owned process and retain its PID/window identity.
- A typical Windows launch is:

  ```powershell
  & "C:\Program Files\chiaki-ng\chiaki.exe" stream PROFILE PS5_HOST
  ```

- Do not send input until the intended title is visibly streaming and the observed `[GAME] started: TITLE_ID` count has increased for this launch.
- Stop on an ambiguous target or any settings, update, store, or sign-in screen.
- At cleanup, close only the Chiaki process created for the case.

## Keyboard input

Common default mappings are:

| Key | Controller |
| --- | --- |
| Enter | Cross |
| Backspace | Circle |
| Backslash | Square |
| C | Triangle |
| Arrow keys | D-pad |
| 2 / 3 | L1 / R1 |
| 1 / 4 | L2 / R2 |
| [ / ] | Left stick horizontal |
| Insert / Delete | Left stick vertical |

Restore and focus exactly one validated Chiaki window. For automation, send paired key-down/key-up events using the mapped virtual-key scan code. Never broadcast input, use global `SendKeys`, or target every matching window. Prove one harmless key before attempting a sequence.

## Virtual gamepad

When keyboard mapping is insufficient, create the virtual Xbox 360 controller before launching Chiaki-ng. Reset and update its state, then use a bounded press/update/wait/release/update cycle. Typical mappings are A=Cross, B=Circle, X=Square, Y=Triangle, with the Xbox D-pad mapped directly.

Tool completion proves only that the virtual device received the command. Pair it with application-side input evidence or a visible state change. Do not install or reconfigure a virtual-gamepad driver during a console test. Treat analog input as a separate acceptance case.

## Screenshots and audio

- Prefer ShareX active-window or region capture, or an operator photo when Remote Play is unavailable. Record the title ID and timestamp with the evidence.
- GPU-backed surfaces can produce black or stale desktop captures. A capture limitation is not application failure; use an operator-observed checkpoint or photo.
- Record audio with an already configured ShareX, OBS, or host audio-capture path targeting Chiaki/system output. Keep samples short and record the capture source/device.
- Silence is meaningful only after the same capture path passes a known-good control.
- Store media under the case directory in `results/`; do not embed or print large binary evidence in an agent transcript.

## Evidence and cleanup

Correlate automated input with the exact title, artifact hash, lifecycle event, and application checkpoint. Finish by closing the tested title, confirming runtime release, closing the owned Chiaki process, checking required services, and releasing the console lock.
