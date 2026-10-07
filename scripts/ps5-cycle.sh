#!/usr/bin/env bash
# ps5-homebrew-dev-protocol - One console cycle from WSL or Linux, in one command.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Lock, close the title if it is open, install a frozen candidate with
# verification, let the console settle, launch once, wait (for a line of the app's
# log, when one is named), collect the logs, the kernel log and the console's error
# records, unlock. It prints one line per step, stops at the first anomaly, collects
# the evidence all the same, and never retries.
#
# Usage: ps5-cycle.sh <PPSAxxxxx> <candidate-folder> [remote-log ...]
#
# Environment:
#   PS5_HOST        console address (required)
#   PS5_LOCK        lock file shared by everyone who uses this console (required to
#                   launch or close; an install of a closed title needs none)
#   PS5_AGENT       who holds the lock, written into it (default: user@host)
#   PS5_ELF_PORT    ELF loader port (default 9021)
#   PS5_SETTLE      seconds to watch after the upload (default 130; 0 skips)
#   PS5_RUN         seconds to let the title run before collecting (default 45);
#                   with PS5_READY_LOG, the longest wait for its line
#   PS5_READY_LOG, PS5_READY_PATTERN
#                   a log file the app writes and a regular expression: the cycle goes
#                   on as soon as a new line of it matches, and fails when none does
#   PS5_KLOG        0 does not record the kernel log during the run (default 1)
#   PS5_KLOG_PORT   kernel log port (default 3232)
#   PS5_OTHER_TITLES  1 launches although another title is running (default 0)
#   PS5_LAUNCH      0 installs and verifies only (default 1)
#   PS5_CLOSE       1 closes the title after the run (default 0: leave it open)
#   PS5_LOCK_WAIT   seconds to wait for a busy lock (default 3600)
#   PS5_RESULTS     where evidence goes (default results/<title>-<time> here)
#
# The candidate is a folder made by freeze-candidate.sh: <name>/<TITLE>/ with
# <name>/SHA256SUMS beside it. The cycle refuses a folder that no longer matches.

set -uo pipefail

[[ $# -ge 2 ]] || { sed -n '5,25p' "${BASH_SOURCE[0]}" >&2; exit 2; }
title=$1
candidate=${2%/}
shift 2
logs=("$@")
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
console=(python3 "$here/ps5-console.py")
: "${PS5_HOST:?set PS5_HOST to the console address}"
[[ -n ${PS5_LOCK:-} || ${PS5_LAUNCH:-1} == 0 ]] ||
    { echo "set PS5_LOCK to the lock file shared for this console" >&2; exit 2; }
[[ $title =~ ^PPSA[0-9]{5}$ ]] || { echo "invalid title ID: $title" >&2; exit 2; }
[[ -f $candidate/eboot.bin ]] || { echo "no eboot.bin in $candidate" >&2; exit 2; }
port=${PS5_ELF_PORT:-9021}
out=${PS5_RESULTS:-$here/../results/$title-$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -p "$out"
export PS5_HOST

# The lock: created atomically, removed only while it still holds our token.
token="${PS5_AGENT:-$(id -un)@$(hostname)}|$title|utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)|$$"
klog_pid=
release() {
    # Our own recorder only, by its process ID: never by a pattern.
    [[ -z $klog_pid ]] || kill "$klog_pid" 2>/dev/null
    if [[ -n ${PS5_LOCK:-} && -f $PS5_LOCK && $(tr -d '\r\n' < "$PS5_LOCK") == "$token" ]]; then
        rm -f -- "$PS5_LOCK"
        echo "lock released"
    fi
}
trap release EXIT
if [[ -n ${PS5_LOCK:-} ]]; then
    deadline=$((SECONDS + ${PS5_LOCK_WAIT:-3600}))
    until (set -o noclobber; printf '%s' "$token" > "$PS5_LOCK") 2>/dev/null; do
        ((SECONDS < deadline)) || { echo "lock busy: $(head -c 100 "$PS5_LOCK")"; exit 3; }
        sleep 15
    done
    echo "lock acquired"
else
    echo "no lock: files only, nothing is launched or closed"
fi

step() { echo "== $*"; }
stop() { echo "STOP: $*"; exit "${code:-1}"; }

# The candidate is what was frozen (freeze-candidate.sh writes the manifest).
sums=$(cd -- "$candidate/.." && pwd)/SHA256SUMS
[[ -f $sums ]] || stop "no SHA256SUMS beside $candidate: freeze the candidate first"
(cd -- "$candidate" && sha256sum -c --quiet "$sums") || stop "the candidate differs from its SHA256SUMS"

state=$("${console[@]}" state "$title") || { code=4 stop "the console is not answering; nothing was sent"; }
errors_before=$("${console[@]}" errors 1)
step "before: $state; $errors_before; mounted from: $("${console[@]}" where "$title")"
# Another title on screen is someone's session: nothing is launched over it.
others=$("${console[@]}" titles | sed -e 's/^running: //' -e "s/\\b$title\\b//g" -e 's/none//' | xargs)
if [[ ${PS5_LAUNCH:-1} == 1 && -n $others && ${PS5_OTHER_TITLES:-0} != 1 ]]; then
    stop "another title is running ($others): not launching over it"
fi
if [[ $state == running ]]; then
    [[ -n ${PS5_LOCK:-} ]] || stop "the title is running: close it, or set PS5_LOCK so the cycle may"
    bash "$here/send-controller.sh" close "$title" "$PS5_HOST" "$port" > /dev/null 2>&1
    for _ in $(seq 20); do
        sleep 2
        [[ $("${console[@]}" state "$title") == closed ]] && break
    done
    [[ $("${console[@]}" state "$title") == closed ]] || stop "the title did not close"
    sleep 5
    step "closed the running title"
fi

"${console[@]}" install "$title" "$candidate" || stop "install failed: not launching"
if [[ ${PS5_SETTLE:-130} != 0 ]]; then
    "${console[@]}" settle "$title" "$candidate" "${PS5_SETTLE:-130}" || stop "settle check failed: not launching"
fi

# From here on a problem does not end the cycle at once: the logs of a run that went
# wrong are the ones worth having.
problem=
if [[ ${PS5_LAUNCH:-1} == 1 ]]; then
    offset=0
    [[ -z ${PS5_READY_LOG:-} ]] || offset=$("${console[@]}" size "$PS5_READY_LOG")
    if [[ ${PS5_KLOG:-1} == 1 ]] && command -v nc > /dev/null; then
        nc "$PS5_HOST" "${PS5_KLOG_PORT:-3232}" > "$out/klog.txt" 2>/dev/null &
        klog_pid=$!
    fi
    bash "$here/send-controller.sh" launch "$title" "$PS5_HOST" "$port" > /dev/null 2>&1 ||
        stop "the launch controller was not delivered"
    started=$SECONDS
    if [[ -n ${PS5_READY_LOG:-} && -n ${PS5_READY_PATTERN:-} ]]; then
        step "launched $(date -u +%H:%M:%SZ); waiting up to ${PS5_RUN:-45} s for /$PS5_READY_PATTERN/"
        ready=$("${console[@]}" wait "$PS5_READY_LOG" "$PS5_READY_PATTERN" "${PS5_RUN:-45}" "$offset" 2>&1) ||
            problem="not ready: $ready"
        step "${problem:-$ready}"
    else
        step "launched $(date -u +%H:%M:%SZ); watching for ${PS5_RUN:-45} s"
        # A title that ends early is known at once, not after the whole wait.
        while ((SECONDS - started < ${PS5_RUN:-45})); do
            sleep 5
            [[ $("${console[@]}" state "$title" 2>/dev/null) == running ]] || break
        done
    fi
    state=$("${console[@]}" state "$title") || { state=unknown; problem="the console stopped answering after the launch: do not retry"; }
    step "after $((SECONDS - started)) s: $state"
    if [[ ${PS5_CLOSE:-0} == 1 && $state == running ]]; then
        bash "$here/send-controller.sh" close "$title" "$PS5_HOST" "$port" > /dev/null 2>&1
        sleep 6
        step "closed: $("${console[@]}" state "$title")"
    fi
    if [[ -n $klog_pid ]]; then
        kill "$klog_pid" 2>/dev/null
        klog_pid=
        step "kernel log: $(wc -l < "$out/klog.txt") lines, $(grep -a -c "$title" "$out/klog.txt") naming $title"
    fi
fi

((${#logs[@]} == 0)) || "${console[@]}" fetch "$out" "${logs[@]}"
errors_after=$("${console[@]}" errors 1)
step "after: $errors_after"
[[ $errors_after == "$errors_before" ]] || echo "NEW ERROR RECORD since the cycle began: read it before the next launch"
echo "evidence: $out"
[[ -z $problem ]] || stop "$problem"
