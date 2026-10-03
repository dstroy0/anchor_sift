#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Finds a form's fields on the part, not by reading a disassembler (interface_sass_probe_fields.c). For each
# instruction a ruleset uses, each of its operation bits is turned over one at a time, run on the part through
# interface_sass_run, and labeled against the runs the machine file records; the labels are gathered into
# interface_sass_fields.md.
#
#     utils/test/src/c/transpiler/interface/interface_sass_fields.sh [<instructions>] [<earlier run folder>]
#
# The instructions default to the forms sass.krs uses, which sass_krs_assemble writes to build/unprinted with a third
# argument. The earlier run, for its pattern cubin, frame and PTX probe, defaults to the newest under build/.
#
# This runs turned-over instructions on the part, and a turned bit can make a backward branch, a loop that never ends
# and hangs the part. The display watchdog then resets the part, and under the run's load that reset can hold a kernel
# DPC past its watchdog and stop the whole machine with a DPC_WATCHDOG_VIOLATION. The per-pass timeout cap below ends
# the waiting process but cannot clear a part the kernel has already wedged. Run this watched, not unattended, and only
# where losing the machine to a reset is acceptable. The contexts that reach such a loop, and the bound an ask carries
# against them, are P9 of theory/workbooks/engine/query_protocol_table.md.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$HERE/../../../../../.." && pwd)"
CUB="$TOP/src/c/transpiler/cubin"
INT="$TOP/src/c/transpiler/interface"
KRS="$TOP/src/c/types/file_defs/krs"
OUT="$TOP/build/fields"
CUDA="/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v13.3"
# the seconds a single runner pass is given before it is cut off: a bit-flip that turns the instruction into a loop
# that never ends hangs the part until the display watchdog resets it, and the cap ends the waiting runner without
# clearing the part
CAP=6
mkdir -p "$OUT"

INSTR="${1:-$TOP/build/unprinted/sass_krs_writings.txt}"
[ -f "$INSTR" ] || { echo "  no instructions at $INSTR; run sass_krs_assemble with a third argument"; exit 1; }

RUN="${2:-}"
if [ -z "$RUN" ]; then
    RUN="$(ls -d "$TOP"/build/*/sass/form_0.text 2>/dev/null | sort | tail -1)"
    RUN="${RUN%/sass/form_0.text}"
fi
[ -f "$RUN/sass/form_0.cubin" ] && [ -f "$RUN/sass/form_0.text" ] || { echo "  no earlier run with sass/form_0"; exit 1; }

INCLUDES=(-I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$CUB" -I "$INT" -I "$KRS")
cc -std=c11 -O1 -Wall "${INCLUDES[@]}" -o "$OUT/interface_sass_probe_fields" \
    "$INT/interface.c" "$INT/interface_names.c" "$CUB/sass_assemble.c" "$CUB/cubin_write.c" "$KRS/sass_machine.c" \
    "$HERE/interface_sass_probe_fields.c" || exit 1
cc -std=c11 -O1 -Wall -I "$CUDA/include" -o "$OUT/interface_sass_run" "$HERE/interface_sass_run.c" \
    -L "$CUDA/lib/x64" -lcuda 2>/dev/null || { echo "  the runner did not link against the CUDA driver"; exit 1; }

WIN="$(cygpath -m "$TOP")"
PATTERN="$(cygpath -m "$RUN")/sass/form_0.cubin"
FRAME="$(cygpath -m "$RUN")/sass/form_0.text"
MACHINE="$CUB/machines/sm_86"
RECORD="$HERE/interface_sass_fields.md"
ANSWERS="$OUT/answers.txt"
ONE="$OUT/one.txt"
REC="$OUT/one.md"

SUMMARY="$OUT/summary.tsv"
: > "$SUMMARY"
forms=0
seen=""
while IFS= read -r line; do
    trimmed="$(printf '%s' "$line" | sed 's/\t/ /g; s/;[[:space:]]*$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/  */ /g')"
    case "$trimmed" in
        "" | "IADD3 R8"*) continue ;;
    esac
    case "$seen" in
        *"|$trimmed|"*) continue ;;
    esac
    seen="$seen|$trimmed|"
    printf '%s\n' "$trimmed" > "$ONE"
    # the list from the form before is cleared first: a form that does not assemble writes no list and is passed over,
    # never run on the cubins of the one before it
    rm -f "$OUT/list.txt"
    "$OUT/interface_sass_probe_fields" "$PATTERN" "$FRAME" "$MACHINE" "$(cygpath -m "$OUT")" "$ONE" > /dev/null || continue
    [ -f "$OUT/list.txt" ] || continue
    rm -f "$ANSWERS"
    first=0
    guard=0
    while :; do
        timeout "$CAP" "$OUT/interface_sass_run" "$(cygpath -m "$OUT")/list.txt" "$first" "$ANSWERS"
        status=$?
        last="$(tail -1 "$ANSWERS" 2>/dev/null | cut -d' ' -f1)"
        case "$status" in
            0) break ;;
            3) first=$(( last + 1 )) ;;
            124) hung=$(( ${last:--1} + 1 )); echo "$hung hung timeout" >> "$ANSWERS"; first=$(( hung + 1 )) ;;
            *) break ;;
        esac
        guard=$(( guard + 1 ))
        [ "$guard" -gt 200 ] && break
    done
    "$OUT/interface_sass_probe_fields" read "$MACHINE" "$ONE" "$ANSWERS" "$REC" 2>/dev/null \
        | grep '^FORMFIELDS' >> "$SUMMARY" || continue
    forms=$(( forms + 1 ))
done < "$INSTR"

{
    printf '# Every used form'"'"'s fields, found on the part\n\n'
    printf 'Written by `interface_sass_fields.sh` whole on every run. Each form a ruleset uses has every operation bit\n'
    printf 'turned over one at a time and run on the part through `interface_sass_run`, and each bit labeled against the\n'
    printf 'runs the machine file records. A read bit outside every recorded run is a bit the part reads that the\n'
    printf 'machine file gives no operand: a modifier of the operation, or an operand it does not print.\n\n'
    printf '| form | refused | inside a run | outside every run | unread | bits outside |\n'
    printf '|---|---|---|---|---|---|\n'
    awk -F'\t' '{printf "| `%s` | %s | %s | %s | %s | %s |\n", $2, $3, $4, $5, $6, $7}' "$SUMMARY"
} > "$RECORD"

echo "  interface sass fields: $forms forms, the record written to $RECORD"
