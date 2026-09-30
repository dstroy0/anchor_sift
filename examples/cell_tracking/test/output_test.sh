#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../.." && pwd)"
OUTPUT="$TOP/cell_tracking/src/output"
SORT="$TOP/cell_tracking/src/sort"
SCAN="$TOP/cell_tracking/src/scan"
DIVIDE="$TOP/cell_tracking/src/divide"
FACES="$TOP/cell_tracking/src/faces"
source "$TOP/cell_tracking/maint/build_stamp.sh"
build_stamp output_test

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/output_test.exe"
        MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        if [ -z "$MSVC_BIN" ]; then
            MSVC_BIN="$(ls -d "/c/Program Files/Microsoft Visual Studio"/*/*/VC/Tools/MSVC/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        fi
        if [ -z "$MSVC_BIN" ]; then
            echo "  no host compiler nvcc accepts on this platform was found."
            exit 1
        fi
        HOST_FLAGS=(-ccbin "$MSVC_BIN" -Xcompiler /Zc:preprocessor)
        ;;
    *)
        BINARY="$OUT/output_test"
        HOST_FLAGS=(-Xcompiler -fPIC)
        ;;
esac

INCLUDES=(-I "$ENGINE" -I "$OUTPUT" -I "$SORT" -I "$SCAN" -I "$DIVIDE" -I "$FACES")
rm -f "$BINARY"
# the test is host work: the output reads and writes files and asks nothing of the device. It is no job
nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 -DOUTPUT_TEST_FAULTS "${INCLUDES[@]}" -o "$BINARY" "$TEST/output_test.cu" "$OUTPUT/output_graph.cu"
[ -f "$BINARY" ] || { echo "  build failed: nvcc could not build the test"; exit 1; }
if [ "${BUILD_ONLY:-0}" = "1" ]; then
    echo "  built $BINARY"
    exit 0
fi

# the synthetic set's samples are written under the build directory
mkdir -p "$OUT/output_test_set"
"$BINARY" "$OUT/output_test_set"
STATUS=$?
echo "  output test exit $STATUS"
exit "$STATUS"
