#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Searches the part for a writing of each ladder relation in one instruction (interface_sass_writings.c). Every form of
# the machine file that writes a register from registers alone is written into a cubin of its own, held to cubin_safe,
# run on the part through interface_sass_run over every case at once, and read back against each relation; the forms
# that give a relation every case's word are gathered into interface_sass_writings.md.
#
#     utils/test/src/c/transpiler/interface/interface_sass_writings.sh [<earlier run folder>]
#
# The earlier run, for its pattern cubin and frame, defaults to the newest under build/ and the harness's build.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$HERE/../../../../../.." && pwd)"
CUB="$TOP/src/c/transpiler/cubin"
INT="$TOP/src/c/transpiler/interface"
KRS="$TOP/src/c/types/file_defs/krs"
BOOT="$TOP/src/c/transpiler/bootstrap"
OUT="$TOP/build/writings"
CUDA="/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.3"
# the seconds a runner pass is given before it is cut off. A pass runs every cubin past the last refusal, and a cubin
# that never ends is cut off with it
CAP=120
mkdir -p "$OUT"
rm -f "$OUT"/form_*.cubin "$OUT/answers.txt"

RUN="${1:-}"
if [ -z "$RUN" ]; then
    RUN="$(ls -d "$TOP"/build/*/sass/form_0.text "$TOP"/../build/harness/*/sass/form_0.text 2>/dev/null | sort | tail -1)"
    RUN="${RUN%/sass/form_0.text}"
fi
[ -f "$RUN/sass/form_0.cubin" ] && [ -f "$RUN/sass/form_0.text" ] || { echo "  no earlier run with sass/form_0"; exit 1; }

INCLUDES=(-I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$CUB" -I "$INT" -I "$KRS" -I "$BOOT")
cc -std=c11 -O1 -Wall "${INCLUDES[@]}" -o "$OUT/interface_sass_writings" "$HERE/interface_sass_writings.c" \
    "$CUB/sass_assemble.c" "$CUB/cubin_write.c" "$CUB/cubin_safe.c" "$KRS/sass_machine.c" || exit 1
# the runner holds every cubin to cubin_safe on the host before the driver is handed it
cc -std=c11 -O1 -Wall -I "$CUDA/include" -o "$OUT/interface_sass_run" "$HERE/interface_sass_run.c" \
    "$CUB/cubin_safe.c" "$CUB/cubin_write.c" "$CUB/sass_assemble.c" "$KRS/sass_machine.c" \
    -L "$CUDA/lib/x64" -lcuda 2>/dev/null || { echo "  the runner did not link against the CUDA driver"; exit 1; }

MACHINE="$CUB/machines/sm_86"
WIN_OUT="$(cygpath -m "$OUT")"
"$OUT/interface_sass_writings" "$(cygpath -m "$RUN")/sass/form_0.cubin" "$(cygpath -m "$RUN")/sass/form_0.text" \
    "$(cygpath -m "$MACHINE")" "$WIN_OUT" || exit 1

first=0
guard=0
while :; do
    timeout "$CAP" "$OUT/interface_sass_run" "$(cygpath -m "$MACHINE")" "$WIN_OUT/list.txt" "$first" \
        "$WIN_OUT/answers.txt" "$WIN_OUT/cases.txt"
    status=$?
    last="$(tail -1 "$OUT/answers.txt" 2>/dev/null | cut -d' ' -f1)"
    case "$status" in
        0) break ;;
        3) first=$(( last + 1 )) ;;
        124) hung=$(( ${last:--1} + 1 )); echo "$hung hung timeout" >> "$OUT/answers.txt"; first=$(( hung + 1 )) ;;
        *) echo "  the runner exited $status"; exit 1 ;;
    esac
    guard=$(( guard + 1 ))
    [ "$guard" -gt 2000 ] && { echo "  the runner was started 2000 times"; exit 1; }
done

"$OUT/interface_sass_writings" read "$WIN_OUT" "$(cygpath -m "$HERE")/interface_sass_writings.md"
