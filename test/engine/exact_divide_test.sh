#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../.." && pwd)"
source "$TOP/maint/build_stamp.sh"
build_stamp exact_divide_test

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/exact_divide_test.exe"
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
        BINARY="$OUT/exact_divide_test"
        HOST_FLAGS=(-Xcompiler -fPIC)
        ;;
esac

rm -f "$BINARY"
nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 -I "$TOP/src/engine/base" -o "$BINARY" \
    "$TEST/exact_divide_test.cu" "$TOP/src/engine/base/no_rounding/exact_integer.c"
[ -f "$BINARY" ] || { echo "  build failed: nvcc could not build the test"; exit 1; }

"$BINARY"
STATUS=$?
echo "  exact divide test exit $STATUS"
exit "$STATUS"
