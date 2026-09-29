#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# the checkers of cell_tracking/src/check, each one C file read apart from the program: points_check (S0 and S1's
# .readings and .points) and output_check (S11's nodes file and submission against the .points and .links). Host work
# alone, with no engine and no device
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$ROOT/.." && pwd)"
source "$ROOT/maint/build_stamp.sh"
build_stamp check
CHECK="$ROOT/src/check"
TOOLS=(points_check output_check)

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        SUFFIX=.exe
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
        SUFFIX=
        ;;
esac

for tool in "${TOOLS[@]}"; do
    BINARY="$OUT/$tool$SUFFIX"
    rm -f "$BINARY"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            # fopen and the like are the standard's, which the checkers keep over the _s forms
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2 /W4 /D_CRT_SECURE_NO_WARNINGS" -o "$BINARY" \
                "$CHECK/$tool.c" ;;
        *)
            cc -std=c11 -O2 -Wall -Wextra -o "$BINARY" "$CHECK/$tool.c" ;;
    esac
    STATUS=$?
    if [ "$STATUS" -ne 0 ] || [ ! -f "$BINARY" ]; then
        echo "  build failed: $tool.c did not build (exit $STATUS)"
        exit 1
    fi
    echo "  built $BINARY"
done
for tool in "${TOOLS[@]}"; do
    build_publish "$OUT/$tool$SUFFIX" || exit 1
done
