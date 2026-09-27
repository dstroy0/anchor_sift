#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds the cell (base/cell) and its PTX probe, which writes its kernels from ptx.krs through the emitter's ruleset
# reader (base/emit), then runs the cell's PTX test: the membership queries and the illegal operations, each question a
# process of its own
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../.." && pwd)"
CELL="$TOP/src/engine/base/cell"
EMIT="$TOP/src/engine/base/emit"
source "$TOP/maint/build_stamp.sh"
build_stamp cell_ptx_test

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/cell_ptx_test.exe"
        PROBE="$OUT/cell_ptx_probe.exe"
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
        BINARY="$OUT/cell_ptx_test"
        PROBE="$OUT/cell_ptx_probe"
        EXTENSION=o
        HOST_FLAGS=(-Xcompiler -fPIC)
        ;;
esac

ARCHES="${*:-}"
if [ -z "$ARCHES" ]; then
    CAP="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' .')"
    ARCHES="sm_${CAP:-86}"
fi
GENCODE=()
for one in $ARCHES; do
    GENCODE+=(-gencode "arch=compute_${one#sm_},code=${one}")
done

INCLUDES=(-I "$TOP/src/engine" -I "$CELL")
rm -f "$BINARY" "$PROBE"
OBJECTS=()
for source in "$CELL/cell.c" "$TEST/cell_ptx_test.c"; do
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
nvcc "${HOST_FLAGS[@]}" -o "$BINARY" "${OBJECTS[@]}"
[ -f "$BINARY" ] || { echo "  build failed: the cell's PTX test did not link"; exit 1; }
nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" -I "$TOP/src/engine" -o "$PROBE" "$TEST/cell_ptx_probe.cu" \
    "$EMIT"/emit*.cu -lnvrtc -lnvJitLink
[ -f "$PROBE" ] || { echo "  build failed: the PTX probe did not build"; exit 1; }

mkdir -p "$OUT/probes" "$OUT/probes_flagless"
"$BINARY" "$PROBE" "$OUT/probes"
STATUS=$?
echo "  cell ptx test exit $STATUS"

# again in a ruleset whose carry chains and product are constructs of more basic forms, with no instruction that
# sets or reads the condition code (test/engine/rulesets/flagless)
FLAGLESS="$TEST/rulesets/flagless"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) FLAGLESS="$(cygpath -m "$FLAGLESS")" ;;
esac
CYCLE_RULESETS="$FLAGLESS" "$BINARY" "$PROBE" "$OUT/probes_flagless"
FLAGLESS_STATUS=$?
echo "  cell ptx test in the flagless ruleset exit $FLAGLESS_STATUS"
[ "$FLAGLESS_STATUS" -eq 0 ] || STATUS=1
exit "$STATUS"
