#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds and runs the two checks a hand editing sass.krs wants, neither of which needs a device or a CUDA toolchain:
#
#   sass_krs_assemble   every form sass.krs writes, assembled against the part's machine file
#   ruleset_read_one    one form written, to read what a construct puts out
#
#     utils/maint/engine/sass_krs_check.sh
#     utils/maint/engine/sass_krs_check.sh predicate_xor P0 P1 P2
#
# With arguments it writes that one form and stops; with none it assembles them all. The code generator is host code
# in .cu files compiled as C++, and the cubin writer is C
set -u

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CODEGEN="$TOP/src/c/transpiler/codegen"
CODEGEN_CU="$TOP/src/cu/transpiler/codegen"
CODEGEN_CU_2="$TOP/src/cu/types/file_defs/krs"
CUBIN="$TOP/src/c/transpiler/cubin"
OUT="$TOP/build/sass_krs_check"
mkdir -p "$OUT"

OBJECTS=()
for source in "$CODEGEN_CU"/*.cu "$CODEGEN_CU_2"/*.cu; do
    case "$(basename "$source")" in
        asm_printer_*.cu | codegen*.cu) continue ;;
    esac
    object="$OUT/$(basename "$source").o"
    c++ -std=c++17 -O1 -Wall -Wextra -I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$CODEGEN" -I "$CODEGEN_CU" -I "$CODEGEN_CU_2" -x c++ -c "$source" -o "$object" || exit 1
    OBJECTS+=("$object")
done
for source in "$TOP/src/c/types/file_defs/krs/sass_machine.c" "$CUBIN/sass_assemble.c"; do
    object="$OUT/$(basename "$source").o"
    cc -std=c11 -O1 -Wall -Wextra -I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$CUBIN" -c "$source" -o "$object" || exit 1
    OBJECTS+=("$object")
done

for one in sass_krs_assemble ruleset_read_one; do
    c++ -std=c++17 -O1 -Wall -I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$CODEGEN" -I "$CODEGEN_CU" -I "$CODEGEN_CU_2" -I "$CUBIN" -c "$TOP/utils/maint/engine/$one.cpp" \
        -o "$OUT/$one.o" || exit 1
    c++ -o "$OUT/$one" "$OUT/$one.o" "${OBJECTS[@]}" || exit 1
done

# the ruleset is named from the top of the tree, which is where both read it from
cd "$TOP" || exit 1
if [ "$#" -gt 0 ]; then
    "$OUT/ruleset_read_one" "$@"
    exit "$?"
fi
"$OUT/sass_krs_assemble"
