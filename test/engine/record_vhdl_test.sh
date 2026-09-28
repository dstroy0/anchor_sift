#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The record machine's lane as VHDL held to the host oracle, where GHDL is on the path: the emitter, keymath and
# key_schedule and krep are host code in .cu files and the test C++, compiled as C++; cycle.c, exact_integer.c and
# scriptura as C. GHDL analyzes and runs each program's lane in a work folder under the build's output. Where the
# build's output holds vhdl.kcs (vhdl_construction_set.sh), the lane is cut by that construction set as well.
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../.." && pwd)"
CYCLE="$TOP/src/engine/base/cycle"
EMIT="$TOP/src/engine/base/emit"
KEYMATH="$TOP/src/engine/base/keymath"
KEY_SCHEDULE="$TOP/src/engine/base/key_schedule"
KREP="$TOP/src/engine/base/krep"
NO_ROUNDING="$TOP/src/engine/base/no_rounding"
SCRIPTURA="$TOP/src/engine/base/scriptura"
source "$TOP/maint/build_stamp.sh"
build_stamp record_vhdl_test

command -v ghdl > /dev/null 2>&1 || { echo "  not run: GHDL is not on the path"; exit 0; }
INCLUDES=(-I "$TOP/src/engine" -I "$TOP/src/engine/base" -I "$CYCLE" -I "$EMIT" -I "$KEYMATH" -I "$KEY_SCHEDULE"
          -I "$KREP" -I "$NO_ROUNDING" -I "$SCRIPTURA")
BINARY="$OUT/record_vhdl_test"
rm -f "$BINARY"
OBJECTS=()
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING/exact_integer.c" "$CYCLE/cycle.c"; do
    object="$OUT/$(basename "$source" .c)_vhdl.o"
    rm -f "$object"
    cc -std=c11 -O2 -Wall -Wextra "${INCLUDES[@]}" -c "$source" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
for source in "$KEYMATH/keymath.cu" "$KEY_SCHEDULE/key_schedule.cu" "$EMIT"/emit*.cu "$KREP/krep.cu" \
              "$TEST/record_vhdl_test.cpp"; do
    object="$OUT/$(basename "$source")_vhdl.o"
    rm -f "$object"
    c++ -std=c++17 -O2 -Wall -Wextra "${INCLUDES[@]}" -x c++ -c "$source" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
c++ -o "$BINARY" "${OBJECTS[@]}" -lpthread
[ -f "$BINARY" ] || { echo "  build failed: the test did not link"; exit 1; }

WORK="$OUT/vhdl_work"
rm -rf "$WORK"
mkdir -p "$WORK"
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
rm -rf "$WORK"
echo "  record vhdl test exit $STATUS"
exit "$STATUS"
