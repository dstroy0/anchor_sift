#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The construction set of the register lane's VHDL, measured where GHDL and Yosys are on the path
# (vhdl_construction_set.cpp): each form alone synthesized, its cost its longest path, written as vhdl.kcs under the
# build's output. The emitter, keymath, key_schedule and krep are host code in .cu files and the tool C++, compiled as
# C++; cycle.c, exact_integer.c and scriptura as C.
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
build_stamp vhdl_construction_set

command -v ghdl > /dev/null 2>&1 || { echo "  not run: GHDL is not on the path"; exit 0; }
command -v yosys > /dev/null 2>&1 || { echo "  not run: Yosys is not on the path"; exit 0; }
INCLUDES=(-I "$TOP/src/engine" -I "$TOP/src/engine/base" -I "$CYCLE" -I "$EMIT" -I "$KEYMATH" -I "$KEY_SCHEDULE"
          -I "$KREP" -I "$NO_ROUNDING" -I "$SCRIPTURA")
BINARY="$OUT/vhdl_construction_set"
rm -f "$BINARY"
OBJECTS=()
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING/exact_integer.c" "$CYCLE/cycle.c"; do
    object="$OUT/$(basename "$source" .c)_kcs.o"
    rm -f "$object"
    cc -std=c11 -O2 -Wall -Wextra "${INCLUDES[@]}" -c "$source" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
for source in "$KEYMATH/keymath.cu" "$KEY_SCHEDULE/key_schedule.cu" "$EMIT"/emit*.cu "$KREP/krep.cu" \
              "$TEST/vhdl_construction_set.cpp"; do
    object="$OUT/$(basename "$source")_kcs.o"
    rm -f "$object"
    c++ -std=c++17 -O2 -Wall -Wextra "${INCLUDES[@]}" -x c++ -c "$source" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
c++ -o "$BINARY" "${OBJECTS[@]}" -lpthread
[ -f "$BINARY" ] || { echo "  build failed: the tool did not link"; exit 1; }

WORK="$OUT/kcs_work"
rm -rf "$WORK"
mkdir -p "$WORK"
"$BINARY" "$WORK" "$EMIT/rulesets/vhdl.krs" "$OUT/vhdl.kcs"
STATUS=$?
rm -rf "$WORK"
echo "  vhdl construction set exit $STATUS"
exit "$STATUS"
