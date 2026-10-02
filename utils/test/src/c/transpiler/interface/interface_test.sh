#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds the interface (compiler/interface) and its probe, then runs the interface test: each probe in a probe process, each ending
# held to the host's rules. The probe is built with no optimization, so each question reaches the part as written
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../../../../../.." && pwd)"
INTERFACE="$TOP/src/c/transpiler/interface"
source "$TOP/utils/maint/engine/build_stamp.sh"
build_stamp interface_test

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/interface_test.exe"
        PROBE="$OUT/interface_probe.exe"
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
        BINARY="$OUT/interface_test"
        PROBE="$OUT/interface_probe"
        EXTENSION=o
        ;;
esac

INCLUDES=(-I "$TOP/src/c/engine" -I "$TOP/src/cu/engine" -I "$INTERFACE")
rm -f "$BINARY" "$PROBE"
OBJECTS=()
for source in "$INTERFACE/interface.c" "$INTERFACE/interface_names.c" "$TEST/interface_test.c"; do
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
        nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /Od" -o "$PROBE" "$TEST/interface_probe.c" ;;
    *)
        cc -o "$BINARY" "${OBJECTS[@]}"
        cc -std=c11 -O0 -o "$PROBE" "$TEST/interface_probe.c" ;;
esac
[ -f "$BINARY" ] || { echo "  build failed: the interface test did not link"; exit 1; }
[ -f "$PROBE" ] || { echo "  build failed: the probe did not build"; exit 1; }

mkdir -p "$OUT/probes"
"$BINARY" "$PROBE" "$OUT/probes"
STATUS=$?
echo "  interface test exit $STATUS"
exit "$STATUS"
