#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds the cell (compiler/cell) and its probe, then runs the cell test: each probe in a child process, each ending
# held to the host's rules. The probe is built with no optimization, so each question reaches the part as written
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../../../../.." && pwd)"
CELL="$TOP/src/engine/compiler/cell"
source "$TOP/utils/maint/engine/build_stamp.sh"
build_stamp cell_test

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/cell_test.exe"
        PROBE="$OUT/cell_probe.exe"
        EXTENSION=obj
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
        BINARY="$OUT/cell_test"
        PROBE="$OUT/cell_probe"
        EXTENSION=o
        ;;
esac

INCLUDES=(-I "$TOP/src/engine" -I "$CELL")
rm -f "$BINARY" "$PROBE"
OBJECTS=()
for source in "$CELL/cell.c" "$CELL/cell_names.c" "$TEST/cell_test.c"; do
    object="$OUT/$(basename "$source" .c).$EXTENSION"
    rm -f "$object"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${INCLUDES[@]}" -c "$source" -o "$object" ;;
        *)
            cc -std=c11 -O2 "${INCLUDES[@]}" -c "$source" -o "$object" ;;
    esac
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
done
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        nvcc "${HOST_FLAGS[@]}" -o "$BINARY" "${OBJECTS[@]}"
        nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /Od" -o "$PROBE" "$TEST/cell_probe.c" ;;
    *)
        cc -o "$BINARY" "${OBJECTS[@]}"
        cc -std=c11 -O0 -o "$PROBE" "$TEST/cell_probe.c" ;;
esac
[ -f "$BINARY" ] || { echo "  build failed: the cell test did not link"; exit 1; }
[ -f "$PROBE" ] || { echo "  build failed: the probe did not build"; exit 1; }

mkdir -p "$OUT/probes"
"$BINARY" "$PROBE" "$OUT/probes"
STATUS=$?
echo "  cell test exit $STATUS"
exit "$STATUS"
