#!/usr/bin/env bash
# cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
mkdir -p "$OUT"

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        LIBRARY="$OUT/cell_tracking_engine.dll"
        MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        if [ -z "$MSVC_BIN" ]; then
            MSVC_BIN="$(ls -d "/c/Program Files/Microsoft Visual Studio"/*/*/VC/Tools/MSVC/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        fi
        if [ -z "$MSVC_BIN" ]; then
            echo "  no host compiler nvcc accepts on this platform was found."
            exit 1
        fi
        HOST_FLAGS=(-ccbin "$MSVC_BIN")
        ;;
    *)
        LIBRARY="$OUT/libcell_tracking_engine.so"
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
echo "  architectures: $ARCHES"

rm -f "$LIBRARY"

DEFINES=(-DBIRTH_SWEEP_BUILD_DLL=1 -DRESIDUAL_FIELD_BUILD_DLL=1 -DPEAK_BASINS_BUILD_DLL=1
         -DBINOMIAL_BASINS_BUILD_DLL=1 -DBASIN_OVERLAP_BUILD_DLL=1 -DHEAVIEST_MATCHING_BUILD_DLL=1
         -DSHIFT_AGREEMENT_BUILD_DLL=1)
PORTABLE_OBJECTS=()
for portable in binomial_basins basin_overlap heaviest_matching shift_agreement; do
    OBJECT="$OUT/${portable}_portable.o"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            OBJECT="$OUT/${portable}_portable.obj"
            rm -f "$OBJECT"
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${DEFINES[@]}" \
                -I "$ROOT/engine" -c "$ROOT/engine/$portable.c" -o "$OBJECT"
            ;;
        *)
            rm -f "$OBJECT"
            cc -std=c11 -O2 -fPIC -I "$ROOT/engine" -c "$ROOT/engine/$portable.c" -o "$OBJECT"
            ;;
    esac
    if [ ! -f "$OBJECT" ]; then
        echo "  build failed: engine/$portable.c did not compile"
        exit 1
    fi
    PORTABLE_OBJECTS+=("$OBJECT")
done

nvcc "${HOST_FLAGS[@]}" -O2 -fmad=false "${GENCODE[@]}" -shared \
    "${DEFINES[@]}" \
    -I "$ROOT/engine" \
    -o "$LIBRARY" \
    "$ROOT/engine/residual_field.cu" \
    "$ROOT/engine/birth_sweep.cu" \
    "$ROOT/engine/peak_basins.cu" \
    "$ROOT/engine/binomial_basins.cu" \
    "$ROOT/engine/binomial_transform.cu" \
    "$ROOT/engine/basin_overlap.cu" \
    "$ROOT/engine/shift_agreement.cu" \
    "${PORTABLE_OBJECTS[@]}"
NVCC_STATUS=$?

if [ "$NVCC_STATUS" -ne 0 ] || [ ! -f "$LIBRARY" ]; then
    echo "  build failed: nvcc exited $NVCC_STATUS"
    exit 1
fi
echo "  built $LIBRARY"
