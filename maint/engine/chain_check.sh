#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds and runs the two things that work off the ladder's relations, neither of which needs a device, a toolchain
# or a machine file:
#
#   kdm_write    writes a part's .kdm: every arrangement of primitives that produces each operator
#   chain_check  reads how much of a relation the ladder's own cases decide
#
#     maint/engine/chain_check.sh
#     maint/engine/chain_check.sh sm_86 src/engine/compiler/cubin/machines/sm_86.kdm
#
# With arguments it writes that part's .kdm to that path; with none it runs the check and stops.
set -u

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$TOP/build/engine"
mkdir -p "$OUT"

for one in "$TOP/maint/engine/kdm_write.c" "$TOP/test/engine/compiler/bootstrap/chain_check.c"; do
    name="$(basename "$one" .c)"
    cc -std=c11 -O2 -Wall -Wextra -o "$OUT/$name" "$one" \
        "$TOP/src/engine/compiler/bootstrap/chain_build.c" || exit 1
done

cd "$TOP" || exit 1
if [ "$#" -gt 0 ]; then
    "$OUT/kdm_write" "$@"
    exit "$?"
fi
"$OUT/chain_check"
