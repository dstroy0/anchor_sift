#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Asks the part what the bits the disassembler does not print do (interface_sass_probe_unprinted.c), and writes
# interface_sass_unprinted.md beside this script whole.
#
# The runner, the pattern cubin and the frame's text are an earlier SASS probe run's: the newest folder under build/
# whose sass/ holds form_0.cubin and form_0.text, and the PTX probe that run built beside it. Nothing is compiled
# for the device and no disassembler is run.
#
#     utils/test/src/c/transpiler/interface/interface_sass_unprinted.sh [--forms] [<earlier run folder>]
#
# With --forms, every form holding an operand it does not print is asked instead, and interface_sass_unprinted_forms.md
# is written.
set -u

FORMS=""
RECORD="utils/test/src/c/transpiler/interface/interface_sass_unprinted.md"
if [ "${1:-}" = "--forms" ]; then
    FORMS="forms"
    RECORD="utils/test/src/c/transpiler/interface/interface_sass_unprinted_forms.md"
    shift
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$HERE/../../../../../.." && pwd)"
CUBIN="$TOP/src/c/transpiler/cubin"
INTERFACE="$TOP/src/c/transpiler/interface"
KRS_C="$TOP/src/c/types/file_defs/krs"
OUT="$TOP/build/unprinted"
mkdir -p "$OUT"

RUN="${1:-}"
if [ -z "$RUN" ]; then
    RUN="$(ls -d "$TOP"/build/*/sass/form_0.text 2>/dev/null | sort | tail -1)"
    RUN="${RUN%/sass/form_0.text}"
fi
[ -f "$RUN/sass/form_0.cubin" ] && [ -f "$RUN/sass/form_0.text" ] || { echo "  no earlier run with sass/form_0.cubin and sass/form_0.text"; exit 1; }
RUNNER="$(ls "$RUN"/*_ptx_probe.exe "$RUN"/*_ptx_probe 2>/dev/null | head -1)"
[ -n "$RUNNER" ] || { echo "  no PTX probe in $RUN"; exit 1; }

OBJECTS=()
for source in "$INTERFACE/interface.c" "$INTERFACE/interface_names.c" "$KRS_C/sass_machine.c" "$CUBIN/sass_assemble.c" \
              "$CUBIN/cubin_write.c" "$HERE/interface_sass_probe_unprinted.c"; do
    object="$OUT/$(basename "$source" .c).o"
    cc -std=c11 -O1 -Wall -I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$CUBIN" -I "$INTERFACE" -I "$KRS_C" \
        -c "$source" -o "$object" || exit 1
    OBJECTS+=("$object")
done
cc -o "$OUT/interface_sass_probe_unprinted" "${OBJECTS[@]}" || exit 1

cd "$TOP" || exit 1
"$OUT/interface_sass_probe_unprinted" "$RUNNER" "$RUN/sass/form_0.cubin" "$RUN/sass/form_0.text" \
    "$CUBIN/machines/sm_86" "$OUT" "$RECORD" $FORMS
