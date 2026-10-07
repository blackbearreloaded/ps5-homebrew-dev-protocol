#!/usr/bin/env bash
# ps5-homebrew-dev-protocol - Freeze a built app folder as an immutable candidate.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copies a built app folder to <destination>/<TITLE>/ and writes
# <destination>/SHA256SUMS over its files. Console cycles install the copy, so
# a later rebuild cannot change what a queued or running cycle uploads, and the
# exact bytes that ran stay available for comparison.
#
# Usage: freeze-candidate.sh <built-app-folder> <destination>
# The destination must not exist: a frozen candidate is never rewritten.

set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 <built-app-folder> <destination>" >&2; exit 2; }
source_folder=${1%/}
destination=${2%/}
title=$(basename -- "$source_folder")
[[ $title =~ ^PPSA[0-9]{5}$ ]] || { echo "the app folder must be named by its title ID: $title" >&2; exit 2; }
[[ -f $source_folder/eboot.bin && -f $source_folder/sce_sys/param.json ]] ||
    { echo "$source_folder is not a built app folder" >&2; exit 2; }
[[ ! -e $destination ]] || { echo "$destination exists: choose a new name" >&2; exit 2; }

mkdir -p -- "$destination"
cp -a -- "$source_folder" "$destination/$title"
(cd -- "$destination/$title" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$destination/SHA256SUMS"
printf '%s: %s files, eboot %s
' "$destination/$title" "$(wc -l < "$destination/SHA256SUMS")"     "$(sha256sum "$destination/$title/eboot.bin" | cut -c1-16)"
