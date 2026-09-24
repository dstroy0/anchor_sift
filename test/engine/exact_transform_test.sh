#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds and runs the ladder test at three widths: the default 128 limbs, 4096 limbs on the stack, and 4194304 bits,
# past any stack, from the heap. Extra arguments are passed to nvcc as defines (for example -DANCHOR_EXACT_TRANSFORM_LIMBS=512u).
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../.." && pwd)"
source "$TOP/maint/build_stamp.sh"
build_stamp exact_transform_test

HOST_FLAGS=()
SUFFIX=""
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        SUFFIX=".exe"
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
        HOST_FLAGS=(-Xcompiler -fPIC)
        ;;
esac

STATUS=0
for WIDTH in ${EXACT_TEST_WIDTHS:-"-DANCHOR_EXACT_LIMBS=128u" "-DANCHOR_EXACT_LIMBS=4096u" "-DANCHOR_EXACT_BITS=4194304ull"}; do
    NAME="$(echo "$WIDTH" | tr -cd '0-9')"
    BINARY="$OUT/exact_transform_test_$NAME$SUFFIX"
    rm -f "$BINARY"
    nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "$WIDTH" "$@" -I "$TOP/src/engine/base" -o "$BINARY" \
        "$TEST/exact_transform_test.cu" "$TOP/src/engine/base/no_rounding/exact_integer.c" > "$OUT/build_$NAME.log" 2>&1
    [ -f "$BINARY" ] || { echo "  build failed at $WIDTH:"; cat "$OUT/build_$NAME.log"; exit 1; }
    "$BINARY"
    RESULT=$?
    [ "$RESULT" -eq 0 ] || STATUS=$RESULT
done
echo "  exact transform test exit $STATUS"
exit "$STATUS"
