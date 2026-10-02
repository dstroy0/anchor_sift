#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The record machine's lane as VHDL held to the host oracle, where GHDL is on the path: the code generator, keymath and
# key_schedule and krep are host code in .cu files and the test C++, compiled as C++; cycle.c, the exact integer's
# pieces and scriptura as C. GHDL analyzes and runs each program's lane in a work folder in the system's temporary folder. Where
# the build's output holds vhdl.kcs (vhdl_construction_set.sh), the lane is cut by that construction set as well.
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../../../../../../.." && pwd)"
CYCLE="$TOP/src/c/engine/analysis/cycle"
CYCLE_CU="$TOP/src/cu/engine/analysis/cycle"
CODEGEN="$TOP/src/c/transpiler/codegen"
CODEGEN_CU="$TOP/src/cu/transpiler/codegen"
CODEGEN_CU_2="$TOP/src/cu/types/file_defs/krs"
KEYMATH="$TOP/src/c/engine/analysis/keymath"
KEYMATH_CU="$TOP/src/cu/engine/analysis/keymath"
KEY_SCHEDULE="$TOP/src/c/engine/analysis/key_schedule"
KEY_SCHEDULE_CU="$TOP/src/cu/engine/analysis/key_schedule"
KREP="$TOP/src/c/types/file_defs/krep"
KREP_CU="$TOP/src/cu/types/file_defs/krep"
NO_ROUNDING="$TOP/src/c/types/integers"
SCRIPTURA="$TOP/src/c/engine/runtime/scriptura"
source "$TOP/utils/maint/engine/build_stamp.sh"
build_stamp record_vhdl_test

command -v ghdl > /dev/null 2>&1 || { echo "  not run: GHDL is not on the path"; exit 0; }
INCLUDES=(-I "$TOP/src/c/engine" -I "$TOP/src/c/includes/codecs/crc" -I "$TOP/src/cu/includes/codecs/crc" -I "$CYCLE" -I "$CYCLE_CU" -I "$CODEGEN" -I "$CODEGEN_CU" -I "$CODEGEN_CU_2" -I "$KEYMATH" -I "$KEYMATH_CU"
          -I "$KEY_SCHEDULE" -I "$KEY_SCHEDULE_CU" -I "$KREP" -I "$KREP_CU" -I "$NO_ROUNDING" -I "$SCRIPTURA")
BINARY="$OUT/record_vhdl_test"
rm -f "$BINARY"
OBJECTS=()
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING"/exact_integer_{add,limbs,multiply,divide,gcd,decimal,hash}.c \
              "$CYCLE/cycle.c"; do
    object="$OUT/$(basename "$source" .c)_vhdl.o"
    rm -f "$object"
    cc -std=c11 -O2 -Wall -Wextra "${INCLUDES[@]}" -c "$source" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
for source in "$KEYMATH_CU/keymath.cu" "$KEY_SCHEDULE_CU/key_schedule.cu" "$CODEGEN_CU"/*.cu "$CODEGEN_CU_2"/*.cu "$KREP_CU"/krep_{io,sections}.cu \
              "$TEST/record_vhdl_test.cpp"; do
    object="$OUT/$(basename "$source")_vhdl.o"
    rm -f "$object"
    c++ -std=c++17 -O2 -Wall -Wextra "${INCLUDES[@]}" -x c++ -c "$source" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
c++ -o "$BINARY" "${OBJECTS[@]}" -lpthread
[ -f "$BINARY" ] || { echo "  build failed: the test did not link"; exit 1; }

# the work folder is the system's own temporary folder, not the build's output: a synthesis writes its Verilog in small
# pieces, and a drive the system shares with another (WSL's /mnt) takes each one slowly
WORK="$(mktemp -d "${TMPDIR:-/tmp}/record_vhdl.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# where Yosys is on the path too, each lane is synthesized as well
SYNTHESIS=()
if command -v yosys > /dev/null 2>&1; then
    SYNTHESIS=(--synthesis)
fi
CONSTRUCTION=()
if [ -f "$OUT/vhdl.kcs" ]; then
    CONSTRUCTION=(--construction "$OUT/vhdl.kcs")
fi
"$BINARY" "$WORK" "$TEST/record_vhdl_bench.vhd" "${SYNTHESIS[@]}" "${CONSTRUCTION[@]}"
STATUS=$?
echo "  record vhdl test exit $STATUS"
exit "$STATUS"
