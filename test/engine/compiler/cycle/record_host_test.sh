#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The record machine's host oracle, built with no CUDA toolchain where there is none: keymath and key_schedule are
# host code in .cu files, compiled as C++; cycle.c, the exact integer's pieces and scriptura as C. On Windows nvcc
# drives MSVC, as the record tests' host objects are built there. Its lines are what two parts compare.
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../../../.." && pwd)"
CYCLE="$TOP/src/engine/compiler/cycle"
KEYMATH="$TOP/src/engine/compiler/keymath"
KEY_SCHEDULE="$TOP/src/engine/compiler/key_schedule"
NO_ROUNDING="$TOP/src/engine/arithmetic/no_rounding"
SCRIPTURA="$TOP/src/engine/runtime/scriptura"
source "$TOP/maint/build_stamp.sh"
build_stamp record_host_test

INCLUDES=(-I "$TOP/src/engine" -I "$CYCLE" -I "$KEYMATH" -I "$KEY_SCHEDULE" -I "$NO_ROUNDING" -I "$SCRIPTURA")
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/record_host_test.exe"
        EXTENSION=obj
        MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        if [ -z "$MSVC_BIN" ]; then
            MSVC_BIN="$(ls -d "/c/Program Files/Microsoft Visual Studio"/*/*/VC/Tools/MSVC/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        fi
        [ -n "$MSVC_BIN" ] || { echo "  no host compiler nvcc accepts on this platform was found."; exit 1; }
        build_c()
        {
            nvcc -ccbin "$MSVC_BIN" -Xcompiler /Zc:preprocessor -Xcompiler "/std:c11 /O2" "${INCLUDES[@]}" -c "$1" -o "$2"
        }
        build_cpp()
        {
            nvcc -ccbin "$MSVC_BIN" -Xcompiler /Zc:preprocessor -std=c++17 -O2 "${INCLUDES[@]}" -c "$1" -o "$2"
        }
        link_all()
        {
            nvcc -ccbin "$MSVC_BIN" -o "$BINARY" "$@"
        }
        ;;
    *)
        BINARY="$OUT/record_host_test"
        EXTENSION=o
        build_c()
        {
            cc -std=c11 -O2 -Wall -Wextra "${INCLUDES[@]}" -c "$1" -o "$2"
        }
        build_cpp()
        {
            c++ -std=c++17 -O2 -Wall -Wextra "${INCLUDES[@]}" -x c++ -c "$1" -o "$2"
        }
        link_all()
        {
            c++ -o "$BINARY" "$@"
        }
        ;;
esac

rm -f "$BINARY"
OBJECTS=()
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING"/exact_integer_{add,limbs,multiply,divide,gcd,decimal,hash}.c \
              "$CYCLE/cycle.c" "$TEST/record_host_test.c"; do
    object="$OUT/$(basename "$source" .c)_host.$EXTENSION"
    rm -f "$object"
    build_c "$source" "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
for source in "$KEYMATH/keymath.cu" "$KEY_SCHEDULE/key_schedule.cu"; do
    object="$OUT/$(basename "$source" .cu)_host.$EXTENSION"
    rm -f "$object"
    build_cpp "$source" "$object"
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
link_all "${OBJECTS[@]}"
[ -f "$BINARY" ] || { echo "  build failed: the test did not link"; exit 1; }

"$BINARY"
STATUS=$?
echo "  record host test exit $STATUS"
exit "$STATUS"
