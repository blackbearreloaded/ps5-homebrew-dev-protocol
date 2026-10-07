# Fast console cycles

The [runbook](RUNBOOK.md) says what one console cycle must do. This page is about doing it
quickly and getting the most from each launch. Every item comes from repeated cycles on
real consoles; read it when a project is about to test on hardware more than once.

The cost to keep down is launches, not minutes. Each launch and each close is a chance to
lose the console for a while, and a lost console costs everyone who shares it far more than
a slow build.

## 1. Answer on the PC what the PC can answer

- **Draw the interface on the PC.** Build the app's screens for the host with a software
  OpenGL (or the app's CPU renderer) and write a picture of every state to disk. A picture
  per state, read before any console run, replaces most console screenshots, costs no
  launch, and can be checked on every pull request.
- **Check layout by rule, not by eye.** A host run can walk every screen in every language
  and fail when text leaves its box. Do it there, not with a controller.
- **Script the model.** Drive the app's state machine on the PC with a pretend network or
  device and assert the outcomes. Hardware is for what only hardware has: the loader, the
  decoder, the display, timing.
- **Stand in for the far side with a file.** A feature that waits on something remote (a
  newer release to update to, a server's answer, a catalog entry) is slow to test against
  the real thing. Let a development build read the same answer from a small file in its
  data folder when one is there: `ps5-console.py put` sends it, each state takes one
  launch, and the real service is needed only for the final run.
- **Test input handling as a function.** Feed recorded controller samples to the code that
  turns them into the app's buttons, sticks and motion, and assert what comes out. A
  mapping, a rotation or a dead zone is then proven before anyone holds a controller.

## 2. Freeze what you are going to run

A cycle installs a *candidate*: a copy of the built app folder that is never rewritten.

```bash
scripts/freeze-candidate.sh dist/PPSA99999 ~/candidates/menu-fix-1
```

- The copy has a `SHA256SUMS` beside it; the cycle refuses a folder that no longer matches.
- **Never rebuild into a folder that a queued or running cycle will read.** A build that
  finishes during the upload installs a mixture. Freezing makes that impossible.
- Keep the candidate until its question is closed: it is the only exact record of what ran.
- **Make the build say what it is.** Write a short label (a pull request number and commit,
  or a test name) into the app folder at build time, show it somewhere in the app, and log
  it at start. Two builds with the same version are otherwise indistinguishable on the
  console.

## 3. One command per cycle

```bash
export PS5_HOST=192.0.2.10 PS5_LOCK=/path/shared/lock-console-a.txt
scripts/ps5-cycle.sh PPSA99999 ~/candidates/menu-fix-1/PPSA99999 \
    /data/myapp/logs/app.log /data/shadowmount/debug.log
```

[`ps5-cycle.sh`](../scripts/ps5-cycle.sh) does the runbook's cycle from WSL or Linux and
prints one line per step:

1. takes the lock atomically, with a token, and releases it on any exit;
2. reads whether the title is running, and the console's newest error record;
3. closes the title if it is open, and requires it to be closed;
4. installs with [`ps5-console.py install`](../scripts/ps5-console.py): each file goes to
   a temporary name, is read back and compared, and only then replaces its destination,
   with `eboot.bin` and `param.json` last;
5. watches the console for a while and compares the whole install again (section 4);
6. launches once, waits, reads the state again;
7. fetches the logs named on the command line and the newest error record;
8. stops at the first anomaly and never retries.

It replaces the files of a title the console already knows. A title installed for the
first time must be registered first (ShadowMount Plus picks it up from its scan folder);
launching an unregistered title fails.

Write a cycle as a script file and run the file. Long commands passed inline through
another shell (PowerShell to WSL, SSH) lose their quoting in ways that are slow to find.
Run a long cycle in the background and read its output when it ends; do not poll it.

`PS5_LAUNCH=0` installs and verifies without launching. That is enough when a person is
going to test by hand, and it needs no launch from you at all. It needs no lock either
when the title is closed: nothing is launched or closed, and the install refuses a title
that is running.

- **Wait for a line, not for a time.** Name a log the app writes and what it says when it is
  ready (`PS5_READY_LOG`, `PS5_READY_PATTERN`): the cycle goes on the moment a new line
  matches and fails by itself when none does. A fixed wait is either too long every time
  or too short once. Without a log, the cycle still notices a title that ended early.
- **The kernel log is recorded for you.** The cycle saves it for the length of the run
  (`klog.txt` in the evidence folder) and says how many lines name the title. A crash is
  written there and often nowhere else.
- **Evidence survives a failed run.** When the launch goes wrong the cycle still fetches the
  logs and the error record before it stops: those are the logs worth reading.
- **Nothing is launched over another title.** A title someone else left running is their
  session. The cycle lists what is running (`ps5-console.py titles`) and stops before the
  install when it is not alone.
- **Shell paths between Windows and WSL.** From Git Bash, a `/mnt/c/...` argument is
  rewritten into a Windows path before WSL sees it; set `MSYS_NO_PATHCONV=1` for that
  command or call it from PowerShell. Never stop a background helper by a name pattern
  (`pkill -f`): the pattern also matches the shell running the command. Keep its process
  ID and stop that.

## 4. Verify the install twice

- **A running title is a mounted sandbox.** `ps5-console.py state PPSA99999` lists
  `/mnt/sandbox` and answers `running` or `closed`: no input, no screenshot, no guess.
- **Read back what you upload.** A transfer that reports success can still have stored
  something else. Signed files need care: a new FTP session may return an ELF view of a
  signed file, so compare the stored bytes (ftpsrv's `SELF` command) or fall back to size.
- **Let the console settle, then compare again.** After a crash, a console can come back
  with the files written just before it as zero bytes, and the app then "cannot start"
  for a reason that has nothing to do with the build. Waiting about two minutes after an
  upload and comparing the install again catches this before a launch is spent on it.
  Hold the lock through that wait.
- **After any unexpected restart, verify the install before the next launch**, even if
  you did not upload anything.
- **Send the files to where the title really is.** ShadowMount Plus mounts a title from
  whichever scan folder holds it: internal storage, a USB drive, extended storage, or an
  image. `ps5-console.py where PPSA99999` reads the link it keeps
  (`/user/app/<TITLE>/mount.lnk`, or `mount_img.lnk` for an image) and prints the source.
  The install refuses to write anywhere else, and refuses an image: files sent to a folder
  that is not mounted install nothing, and the launch then tests the old build.
- **An app's own folder is where it is mounted, not where it was copied.** Inside the app,
  `/app0` is gone once the app has filesystem access; the mounted copy is at
  `/system_ex/app/<TITLE>`. Look there before any fixed folder, and an app runs from every
  place it can be installed.
- **Permissions are part of the install.** The console only starts an app whose files are
  open to every user (mode 0777), which is how files arrive over FTP. A release archive
  that stores 0644 and is unpacked with permissions kept gives "Can't start the game or
  app" (CE-107750-0). Store 0777 in the archive, and have anything that unpacks on the
  console set it.

## 5. Make each launch answer several questions

- **Self-running builds.** A compile-time switch that makes the app do the test by itself
  (open the screen, start the stream, run the benchmark) and then stay in a known state
  turns a cycle into install, launch, read the log. No input channel is needed, and the
  run is the same every time.
- **A log the app owns.** Write to a file in a folder that survives updates and restarts,
  flush it on a timer, and prefix lines with fixed tags so one `grep` finds them. Log, at
  least: the build's label, where storage ended up, each start-up stage with the
  milliseconds since launch, and every result code at the boundaries that fail on hardware
  (display, decoder, audio, network, shutdown). A buffered log that is only flushed at
  exit holds nothing when the exit is the failure.
- **Numbers, not impressions.** "First frame after 483 ms" compares across builds; "it
  felt slower" does not.
- **A start-up trace that outlives the app.** Write one line per start-up step, with the
  system software version and the build's label, to the kernel log as well as to the file,
  from the first instruction on. When the app closes before its own log exists, the
  kernel log still says how far it got, and a tester on another console can send it.
- **Know where the log is in each mode.** A sandboxed app writes inside its sandbox; the
  same app with filesystem access writes to its data folder. Log the folder at start and
  give the cycle both paths: the one that does not exist is reported as absent.
- **Say when a mode switches on.** Behaviour that depends on what the running content asks
  for (a controller style, a display mode, a codec path) should log one line when it
  engages and when it lets go. "It did nothing" and "it did the wrong thing" then read
  differently in the log.
- **A command file for scripted sessions.** A development build can poll a small file in
  its data folder a few times a second and act on what it finds: press a button, open a
  screen, save a picture, quit. With `ps5-console.py put` and `wait`, one launch walks a
  whole screen flow, each step answered by a log line. Keep it out of release builds.
- **Let the app take its own pictures.** On such a command the app reads back the frame it
  has just drawn and writes it to a folder; `ps5-console.py fetch <out> /data/myapp/shots/`
  collects them. They show what the console drew, need no capture device, and line up with
  the log by name.
- **Plan the reading before the launch.** Decide which lines will answer the question, put
  them in the build, and fetch only those files.

## 6. Read the console's own record

- **Error records.** `ps5-console.py errors` prints how many records the console holds
  under `/system_data/priv/error/history` and the newest ones. The cycle prints the newest
  before and after: a new entry is a system-level error from the run, even when the app's
  own log ends quietly.
- **A log that stops is evidence.** When the last line is ordinary and nothing follows, the
  failure happened after it; say that, and do not fill the gap with a guess.
- **Refused is not the same as silent.** A connection *refused* means the console is on the
  network but its services are not loaded: it restarted, and someone has to load them
  again. A *timeout* means it is off or unreachable. `ps5-console.py` reports which.
  Neither is fixed by trying again.

## 7. Spend launches deliberately

- Set a launch budget before a session and stop at it. Many launch and close pairs in a
  short time have preceded consoles dropping off the network more than once.
- Prefer a title that exits by itself to one that must be force-closed. Leave a title
  running at the end of a cycle when nothing requires closing it.
- One changed variable per launch still holds. The economy is in asking more of each run,
  not in changing more at once.
- After a console stops answering: no retry, no second attempt "to check". Record what
  ran, report it, and wait for whoever owns the console.

## 8. Hand a build to a person without a launch

When the remaining question is how something looks or feels, install with `PS5_LAUNCH=0`,
say exactly what to try and what each outcome means, and let the person launch it. Ask them
for the two facts logs cannot give: what they did just before a failure, and how they
closed the app. Then fetch the log.

- **Write the brief as steps with outcomes.** What to open, what to press, and for each
  thing that can go wrong, what it would mean ("reversed: a sign; a quarter off: the mode
  did not switch on, send the log"). One sitting then decides the next change.
- **Say what you could not verify.** Motion, feel, sound and anything that needs hands are
  unproven until a person tries them, however sound the reasoning. Name the assumption the
  result rests on, and build it so that the likely miss is a one-line change.
- **Ask how it behaves today first.** How the person has to hold, press or wait with the
  current build is a measurement of the present state, and often settles a doubt before
  the fix is installed.

## 9. Help from consoles you cannot reach

Reports come from system software versions and set-ups nobody on the project owns.

- **Ship the trace in every build.** The start-up trace of section 5 costs nothing and turns
  "it crashes on my console" into a file that names the step.
- **Ask for three things:** the app's log folder, the kernel log of one start, and where the
  app is installed (internal storage, USB, an image) with the loader and mount tool
  versions. The last one explains more failures than the first two.
- **Hand out a labelled diagnostic build**, not instructions to change settings. Its label in
  the log says which build produced each report.
- **Compare with a working console's trace line by line.** The first line that differs or is
  missing is the place to look.
