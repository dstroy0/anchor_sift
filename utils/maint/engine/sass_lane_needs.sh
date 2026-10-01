#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds and runs sass_lane_needs: which forms a real lane asks sass.krs for, and which of those it leaves empty.
# No device and no CUDA toolchain; the record programs are the host oracle's own
#
#     utils/maint/engine/sass_lane_needs.sh
set -u

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CYCLE="$TOP/src/engine/compiler/cycle"
CYCLE_CU="$TOP/src/cu/engine/analysis/cycle"
CODEGEN="$TOP/src/engine/compiler/codegen"
CODEGEN_CU="$TOP/src/cu/transpiler/codegen"
CODEGEN_CU_2="$TOP/src/cu/types/file_defs/krs"
KEYMATH="$TOP/src/engine/compiler/keymath"
KEYMATH_CU="$TOP/src/cu/engine/analysis/keymath"
KEY_SCHEDULE="$TOP/src/engine/compiler/key_schedule"
KEY_SCHEDULE_CU="$TOP/src/cu/engine/analysis/key_schedule"
NO_ROUNDING="$TOP/src/engine/arithmetic/no_rounding"
SCRIPTURA="$TOP/src/engine/runtime/scriptura"
CUBIN="$TOP/src/engine/compiler/cubin"
OUT="$TOP/build/sass_lane_needs"
mkdir -p "$OUT"

INCLUDES=(-I "$TOP/src/engine" -I "$TOP/src/engine/codecs/crc" -I "$TOP/src/cu/includes/codecs/crc" -I "$CYCLE" -I "$CYCLE_CU" -I "$CODEGEN" -I "$CODEGEN_CU" -I "$CODEGEN_CU_2" -I "$KEYMATH" -I "$KEYMATH_CU"
    -I "$KEY_SCHEDULE" -I "$KEY_SCHEDULE_CU" -I "$NO_ROUNDING" -I "$SCRIPTURA" -I "$CUBIN" -I "$TOP/utils/test/engine/compiler/cycle")
OBJECTS=()
for source in "$CUBIN/sass_machine.c" "$CUBIN/sass_assemble.c"; do
    object="$OUT/$(basename "$source").o"
    cc -std=c11 -O2 -Wall -Wextra -I "$TOP/src/engine" -I "$CUBIN" -c "$source" -o "$object" || exit 1
    OBJECTS+=("$object")
done
# cycle.c is the host oracle that runs a lane, which nothing here does: only the encoder and the layout are wanted,
# and on this host cycle.c wants __ehdr_start, which the linker gives an ELF and not a PE
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING"/exact_integer_{add,limbs,multiply,divide,gcd,decimal,hash}.c; do
    object="$OUT/$(basename "$source" .c).o"
    cc -std=c11 -O2 -Wall -Wextra "${INCLUDES[@]}" -c "$source" -o "$object" || exit 1
    OBJECTS+=("$object")
done
# the assembly printer and the device's code generator run on the record machine and call the host oracle, the
# cycle.c left out above; nothing here writes a lane, it only decides one
for source in "$KEYMATH_CU/keymath.cu" "$KEY_SCHEDULE_CU/key_schedule.cu" "$CODEGEN_CU"/*.cu "$CODEGEN_CU_2"/*.cu \
    "$TOP/utils/maint/engine/sass_lane_needs.cpp"; do
    case "$(basename "$source")" in
        asm_printer_*.cu | codegen*.cu) continue ;;
    esac
    object="$OUT/$(basename "$source").o"
    c++ -std=c++17 -O2 -Wall "${INCLUDES[@]}" -x c++ -c "$source" -o "$object" || exit 1
    OBJECTS+=("$object")
done
c++ -o "$OUT/sass_lane_needs" "${OBJECTS[@]}" -lpthread || exit 1

# the ruleset is named from the top of the tree, which is where the generator reads it from
cd "$TOP" || exit 1
"$OUT/sass_lane_needs"
