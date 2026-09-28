#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The record machine's lane as C source held to the host oracle off the device (record_c_test.cpp): the emitter,
# keymath and key_schedule are host code in .cu files and the test C++, compiled as C++; cycle.c, exact_integer.c and
# scriptura as C. Each program's lane is built by the host's C++ compiler and run in a work folder under the build's
# output.
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../.." && pwd)"
CYCLE="$TOP/src/engine/base/cycle"
EMIT="$TOP/src/engine/base/emit"
KEYMATH="$TOP/src/engine/base/keymath"
KEY_SCHEDULE="$TOP/src/engine/base/key_schedule"
NO_ROUNDING="$TOP/src/engine/base/no_rounding"
SCRIPTURA="$TOP/src/engine/base/scriptura"
source "$TOP/maint/build_stamp.sh"
build_stamp record_c_test

INCLUDES=(-I "$TOP/src/engine" -I "$TOP/src/engine/base" -I "$CYCLE" -I "$EMIT" -I "$KEYMATH" -I "$KEY_SCHEDULE"
          -I "$NO_ROUNDING" -I "$SCRIPTURA")
BINARY="$OUT/record_c_test"
rm -f "$BINARY"
OBJECTS=()
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING/exact_integer.c" "$CYCLE/cycle.c"; do
    object="$OUT/$(basename "$source" .c)_c.o"
    rm -f "$object"
    cc -std=c11 -O2 -Wall -Wextra "${INCLUDES[@]}" -c "$source" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
for source in "$KEYMATH/keymath.cu" "$KEY_SCHEDULE/key_schedule.cu" "$EMIT"/emit*.cu "$TEST/record_c_test.cpp"; do
    object="$OUT/$(basename "$source")_c.o"
    rm -f "$object"
    c++ -std=c++17 -O2 -Wall -Wextra "${INCLUDES[@]}" -x c++ -c "$source" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
c++ -o "$BINARY" "${OBJECTS[@]}" -lpthread
[ -f "$BINARY" ] || { echo "  build failed: the test did not link"; exit 1; }

WORK="$OUT/c_work"
rm -rf "$WORK"
mkdir -p "$WORK"
"$BINARY" "$WORK" c++
STATUS=$?
rm -rf "$WORK"
echo "  record c test exit $STATUS"
exit "$STATUS"
