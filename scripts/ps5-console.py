#!/usr/bin/env python3
# ps5-homebrew-dev-protocol - Console state, verified installs and evidence over FTP.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
"""One tool for the FTP side of a console cycle. Python standard library only.

  ps5-console.py state   <TITLE>                     is the title running?
  ps5-console.py install <TITLE> <folder>            upload a frozen app folder, verified
  ps5-console.py settle  <TITLE> <folder> [seconds]  watch, then compare the install again
  ps5-console.py fetch   <out-dir> <remote>...       save remote files (logs) locally
  ps5-console.py errors  [count]                     the console's newest error records

Nothing here launches, closes or signals a title; install refuses a running one.
The host comes from PS5_HOST. Optional: PS5_FTP_PORT (2121), PS5_FTP_USER and
PS5_FTP_PASSWORD (anonymous), PS5_INSTALL_ROOT (/data/homebrew).

Exit codes: 0 done, 1 a check failed, 2 usage, 3 the title is running (install),
4 the console did not answer.
"""
from ftplib import FTP, all_errors, error_perm
from pathlib import Path
from posixpath import dirname, join
import hashlib
import io
import os
import re
import socket
import sys
import time

SELF_MAGICS = (b"\x54\x14\xf5\xee", b"\x4f\x15\x3d\x1d")
ERROR_HISTORY = "/system_data/priv/error/history"
BLOCK = 256 * 1024


def fail(message, code=1):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def connect():
    host = os.environ.get("PS5_HOST") or fail("set PS5_HOST to the console's address", 2)
    port = int(os.environ.get("PS5_FTP_PORT", "2121"))
    ftp = FTP()
    try:
        ftp.connect(host, port, timeout=15)
    except ConnectionRefusedError:
        # The console is on the network but its services are not loaded, as after
        # a restart. Nothing a retry can fix: someone has to load them again.
        fail("console reachable, FTP refused: the services are not loaded (restarted?)", 4)
    except (socket.timeout, OSError) as error:
        fail(f"console not answering: {error}", 4)
    ftp.login(os.environ.get("PS5_FTP_USER", "anonymous"),
              os.environ.get("PS5_FTP_PASSWORD", "anonymous"))
    ftp.voidcmd("TYPE I")
    return ftp


def title_id(value):
    if not re.fullmatch(r"[A-Z]{4}[0-9]{5}", value):
        fail(f"invalid title ID: {value}", 2)
    return value


def names(ftp, path):
    """Directory entries with their facts, or None when the folder cannot be listed."""
    previous = ftp.pwd()
    try:
        ftp.cwd(path)
    except error_perm:
        return None
    try:
        return {name: facts for name, facts in ftp.mlsd() if name not in {".", ".."}}
    finally:
        ftp.cwd(previous)


def running(ftp, title):
    """A running title has a sandbox mounted under /mnt/sandbox."""
    sandboxes = names(ftp, "/mnt/sandbox")
    if sandboxes is None:
        fail("cannot list /mnt/sandbox: the title's state is unknown", 1)
    return sorted(name for name in sandboxes if name.startswith(title))


def readback(ftp, path):
    sink = io.BytesIO()
    ftp.retrbinary(f"RETR {path}", sink.write, blocksize=BLOCK)
    return sink.getvalue()


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def remove_if_present(ftp, path):
    try:
        ftp.sendcmd(f"DELE {path}")
    except error_perm as error:
        text = str(error).lower()
        if not (str(error).startswith("550") and ("no such" in text or "not found" in text)):
            raise


def ensure_directory(ftp, path, known):
    current = ""
    for component in path.strip("/").split("/"):
        current += f"/{component}"
        if current in known:
            continue
        try:
            ftp.mkd(current)
        except error_perm as error:
            if not str(error).startswith("550"):
                raise
        known.add(current)


def verify(ftp, path, data):
    """How the uploaded bytes were confirmed; raises on an unexplained difference."""
    got = readback(ftp, path)
    if got == data:
        return "sha256"
    if data[:4] in SELF_MAGICS:
        # ftpsrv's SELF command switches between a signed file and its ELF view.
        toggled = False
        raw = None
        try:
            ftp.sendcmd("SELF")
            toggled = True
            raw = readback(ftp, path)
        except all_errors:
            pass
        if raw == data:
            return "sha256 (stored SELF)"  # Stored-bytes mode stays on for this session.
        if toggled:
            try:
                ftp.sendcmd("SELF")
            except all_errors:
                pass
        if ftp.size(path) == len(data) and got[:4] == b"\x7fELF":
            return "size only (the server returns an ELF view)"
    raise RuntimeError(f"readback of {path} differs: {len(got)} bytes, {sha256(got)[:16]}")


def candidate_files(folder):
    """The folder's files, with the two that make the app startable last."""
    critical = [folder / "eboot.bin", folder / "sce_sys/param.json"]
    files = sorted(item for item in folder.rglob("*") if item.is_file())
    for item in critical:
        if item not in files:
            fail(f"missing {item}", 2)
    for item in files:
        relative = item.relative_to(folder).as_posix()
        if any(c in relative for c in "\r\n") or ".." in relative.split("/"):
            fail(f"unsafe path: {relative!r}", 2)
    return [item for item in files if item not in critical] + critical, critical


def install_root(title):
    return join(os.environ.get("PS5_INSTALL_ROOT", "/data/homebrew"), title)


def command_state(arguments):
    title = title_id(arguments[0])
    with connect() as ftp:
        print("running" if running(ftp, title) else "closed")


def command_install(arguments):
    title, folder = title_id(arguments[0]), Path(arguments[1])
    files, critical = candidate_files(folder)
    root = install_root(title)
    with connect() as ftp:
        if running(ftp, title):
            fail(f"{title} is running; close it before replacing its files", 3)
        known = set()
        uploaded = unchanged = 0
        weaker = []
        for item in files:
            relative = item.relative_to(folder).as_posix()
            remote = join(root, relative)
            data = item.read_bytes()
            # Unchanged files are left alone; a signed file is always sent, since
            # its readback may be an ELF view that cannot be compared.
            if item not in critical and data[:4] not in SELF_MAGICS:
                try:
                    if ftp.size(remote) == len(data) and readback(ftp, remote) == data:
                        unchanged += 1
                        continue
                except all_errors:
                    pass
            temporary = join(dirname(remote), f".{relative.rsplit('/', 1)[-1]}.upload")
            ensure_directory(ftp, dirname(remote), known)
            remove_if_present(ftp, temporary)
            ftp.storbinary(f"STOR {temporary}", io.BytesIO(data), blocksize=BLOCK)
            try:
                label = verify(ftp, temporary, data)
            except Exception:
                remove_if_present(ftp, temporary)
                raise
            remove_if_present(ftp, remote)
            ftp.rename(temporary, remote)
            uploaded += 1
            if label.startswith("size only"):
                weaker.append(relative)
        mismatches = []
        for item in files:
            relative = item.relative_to(folder).as_posix()
            try:
                size = ftp.size(join(root, relative))
            except all_errors as error:
                size = f"error {error}"
            if size != item.stat().st_size:
                mismatches.append(relative)
        stale = []

        def walk(path, prefix=""):
            for name, facts in (names(ftp, path) or {}).items():
                relative = f"{prefix}{name}"
                if facts.get("type") == "dir":
                    walk(join(path, name), f"{relative}/")
                elif not (folder / relative).is_file():
                    stale.append(relative)

        walk(root)
        param_ok = readback(ftp, f"{root}/sce_sys/param.json") == critical[1].read_bytes()
        started = bool(running(ftp, title))
    eboot = sha256(critical[0].read_bytes())[:16]
    print(f"installed {title}: {uploaded} sent, {unchanged} unchanged, {len(files)} files; "
          f"eboot {eboot}; size mismatches {len(mismatches)}; not in this build {len(stale)}; "
          f"size-only checks {len(weaker)}")
    for label, items in (("mismatch", mismatches), ("not in this build", stale)):
        for relative in items[:10]:
            print(f"  {label}: {relative}")
    if mismatches or not param_ok:
        fail("the installed files differ from the candidate: do not launch", 1)
    if started:
        fail(f"{title} started while its files were being replaced", 1)


def command_settle(arguments):
    """After a crash a console can lose what was written just before it, leaving
    files of zero bytes. Watch for a while, then compare the install again."""
    title, folder = title_id(arguments[0]), Path(arguments[1])
    window = int(arguments[2]) if len(arguments) > 2 else 130
    files, critical = candidate_files(folder)
    root = install_root(title)
    watched = critical
    start = time.time()
    failures = 0
    while time.time() - start < window:
        try:
            with connect() as ftp:
                ftp.sendcmd("SELF")  # a new session shows signed files as their ELF view
                ok = all(ftp.size(join(root, item.relative_to(folder).as_posix())) ==
                         item.stat().st_size for item in watched)
        except SystemExit:
            ok = False
        except all_errors:
            ok = False
        failures = 0 if ok else failures + 1
        if failures >= 3:
            fail("the console stopped answering or the files changed while settling", 1)
        time.sleep(min(15, max(0, window - (time.time() - start))))
    wrong = []
    with connect() as ftp:
        ftp.sendcmd("SELF")
        for item in files:
            relative = item.relative_to(folder).as_posix()
            data = item.read_bytes()
            try:
                same = ftp.size(join(root, relative)) == len(data)
                if same and item in watched:
                    same = readback(ftp, join(root, relative)) == data
            except all_errors:
                same = False
            if not same:
                wrong.append(relative)
    print(f"settled {window} s: {len(files)} files compared, {len(wrong)} differ; "
          f"eboot {sha256(critical[0].read_bytes())[:16]}")
    for relative in wrong[:10]:
        print(f"  differs: {relative}")
    if wrong:
        fail("the installed build no longer matches the candidate: do not launch", 1)


def command_fetch(arguments):
    """Saves each remote file that exists; a missing one is reported, not an error."""
    out = Path(arguments[0])
    out.mkdir(parents=True, exist_ok=True)
    with connect() as ftp:
        for remote in arguments[1:]:
            target = out / remote.strip("/").replace("/", "_")
            try:
                with open(target, "wb") as sink:
                    ftp.retrbinary(f"RETR {remote}", sink.write, blocksize=BLOCK)
                print(f"saved {remote} -> {target} ({target.stat().st_size} bytes)")
            except all_errors as error:
                target.unlink(missing_ok=True)
                print(f"absent {remote} ({str(error)[:60]})")


def command_errors(arguments):
    """The newest error records: compare the first line before and after a run."""
    count = int(arguments[0]) if arguments else 3
    with connect() as ftp:
        entries = names(ftp, ERROR_HISTORY)
    if entries is None:
        fail(f"cannot list {ERROR_HISTORY}", 1)
    records = sorted(((facts.get("modify") or "", name) for name, facts in entries.items()
                      if name.endswith(".json")), reverse=True)
    print(f"error records: {len(records)}; newest: "
          f"{' '.join(f'{name}@{stamp}' for stamp, name in records[:count]) or 'none'}")


COMMANDS = {"state": (command_state, 1), "install": (command_install, 2),
            "settle": (command_settle, 2), "fetch": (command_fetch, 2),
            "errors": (command_errors, 0)}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS or \
            len(sys.argv) - 2 < COMMANDS[sys.argv[1]][1]:
        fail(__doc__.strip(), 2)
    try:
        COMMANDS[sys.argv[1]][0](sys.argv[2:])
    except all_errors as error:
        fail(f"FTP failure: {error}", 4)
