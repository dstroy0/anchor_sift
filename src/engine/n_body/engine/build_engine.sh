#!/usr/bin/env bash
# cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Build the CUDA device engine as one shared library the Python side loads with ctypes.
#
#   bash engine/build_engine.sh [sm_XX ...]
#
# Modules: the exact-integer basins (engine/binomial_basins), the multi-lag agreement transform
# (engine/shift_agreement), the basin overlap (engine/basin_overlap), and the heaviest matching
# (engine/heaviest_matching). Output: build/cell_tracking_engine.dll on Windows,
# build/libcell_tracking_engine.so elsewhere. Architectures default to the one this machine carries.
# Grade after every build, pointing --root at the local volume directory:
#
#   python src/exact_track.py grade --root <volumes> --sample <name> --frame 12
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

# Removed first, so a library from an earlier build can never be loaded as though it were this one.
rm -f "$LIBRARY"

# -fmad=false: no fused multiply-add on the device. A fused operation rounds once where scipy rounds
# twice, and the residual would then differ from the host's in the last bit and move voxels across a
# cut.
# The portable references are C11 and are compiled as C11 on their own, by the same host compiler
# nvcc drives, so the objects link into the same library. The CUDA sources are C++ and never see
# the flag.
DEFINES=(-DBINOMIAL_BASINS_BUILD_DLL=1 -DBASIN_OVERLAP_BUILD_DLL=1 -DHEAVIEST_MATCHING_BUILD_DLL=1
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
    "$ROOT/engine/binomial_basins.cu" \
    "$ROOT/engine/basin_overlap.cu" \
    "$ROOT/engine/shift_agreement.cu" \
    "${PORTABLE_OBJECTS[@]}"
NVCC_STATUS=$?

# Both conditions. A zero status with no file is a linker that wrote nothing, and a file with a
# nonzero status cannot exist after the removal above unless something else wrote it.
if [ "$NVCC_STATUS" -ne 0 ] || [ ! -f "$LIBRARY" ]; then
    echo "  build failed: nvcc exited $NVCC_STATUS"
    exit 1
fi
echo "  built $LIBRARY"
