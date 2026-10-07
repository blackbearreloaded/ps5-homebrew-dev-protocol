#!/usr/bin/env bash
# ps5-homebrew-dev-protocol - One console cycle from WSL or Linux, in one command.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Lock, close the title if it is open, install a frozen candidate with
# verification, let the console settle, launch once, wait, collect the logs and
# the console's error records, unlock. It prints one line per step and stops at
# the first anomaly; it never retries.
#
# Usage: ps5-cycle.sh <PPSAxxxxx> <candidate-folder> [remote-log ...]
#
# Environment:
#   PS5_HOST        console address (required)
#   PS5_LOCK        lock file shared by everyone who uses this console (required)
#   PS5_AGENT       who holds the lock, written into it (default: user@host)
#   PS5_ELF_PORT    ELF loader port (default 9021)
#   PS5_SETTLE      seconds to watch after the upload (default 130; 0 skips)
#   PS5_RUN         seconds to let the title run before collecting (default 45)
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
: "${PS5_LOCK:?set PS5_LOCK to the lock file shared for this console}"
[[ $title =~ ^PPSA[0-9]{5}$ ]] || { echo "invalid title ID: $title" >&2; exit 2; }
[[ -f $candidate/eboot.bin ]] || { echo "no eboot.bin in $candidate" >&2; exit 2; }
port=${PS5_ELF_PORT:-9021}
out=${PS5_RESULTS:-$here/../results/$title-$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -p "$out"
export PS5_HOST

# The lock: created atomically, removed only while it still holds our token.
token="${PS5_AGENT:-$(id -un)@$(hostname)}|$title|utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)|$$"
release() {
    if [[ -f $PS5_LOCK && $(tr -d '\r\n' < "$PS5_LOCK") == "$token" ]]; then
        rm -f -- "$PS5_LOCK"
        echo "lock released"
    fi
}
trap release EXIT
deadline=$((SECONDS + ${PS5_LOCK_WAIT:-3600}))
until (set -o noclobber; printf '%s' "$token" > "$PS5_LOCK") 2>/dev/null; do
    ((SECONDS < deadline)) || { echo "lock busy: $(head -c 100 "$PS5_LOCK")"; exit 3; }
    sleep 15
done
echo "lock acquired"

step() { echo "== $*"; }
stop() { echo "STOP: $*"; exit "${code:-1}"; }

# The candidate is what was frozen (freeze-candidate.sh writes the manifest).
sums=$(cd -- "$candidate/.." && pwd)/SHA256SUMS
[[ -f $sums ]] || stop "no SHA256SUMS beside $candidate: freeze the candidate first"
(cd -- "$candidate" && sha256sum -c --quiet "$sums") || stop "the candidate differs from its SHA256SUMS"

state=$("${console[@]}" state "$title") || { code=4 stop "the console is not answering; nothing was sent"; }
step "before: $state; $("${console[@]}" errors 1)"
if [[ $state == running ]]; then
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

if [[ ${PS5_LAUNCH:-1} == 1 ]]; then
    bash "$here/send-controller.sh" launch "$title" "$PS5_HOST" "$port" > /dev/null 2>&1 ||
        stop "the launch controller was not delivered"
    step "launched $(date -u +%H:%M:%SZ); waiting ${PS5_RUN:-45} s"
    sleep "${PS5_RUN:-45}"
    state=$("${console[@]}" state "$title") || { code=4 stop "the console stopped answering after the launch: do not retry"; }
    step "after ${PS5_RUN:-45} s: $state"
    if [[ ${PS5_CLOSE:-0} == 1 && $state == running ]]; then
        bash "$here/send-controller.sh" close "$title" "$PS5_HOST" "$port" > /dev/null 2>&1
        sleep 6
        step "closed: $("${console[@]}" state "$title")"
    fi
fi

((${#logs[@]} == 0)) || "${console[@]}" fetch "$out" "${logs[@]}"
step "after: $("${console[@]}" errors 1)"
echo "evidence: $out"
