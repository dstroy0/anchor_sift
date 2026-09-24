#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$ROOT/../.." && pwd)"
source "$TOP/maint/build_stamp.sh"
build_stamp engine

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
        HOST_FLAGS=(-ccbin "$MSVC_BIN" -Xcompiler /Zc:preprocessor -Xcompiler -Z7)
        LINK_FLAGS=(-Xlinker -DEBUG -Xlinker -OPT:REF -Xlinker -OPT:ICF)
        ;;
    *)
        LIBRARY="$OUT/libcell_tracking_engine.so"
        HOST_FLAGS=(-Xcompiler -fPIC -g)
        LINK_FLAGS=()
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

EXACT_ROOT="${ANCHOR_EXACT_ROOT:-$TOP/src/engine/base/no_rounding}"
RESIDUAL_LIMBS="$(sed -n 's/^#define ENGINE_RESIDUAL_LIMBS \([0-9]*\)u.*/\1/p' "$TOP/src/engine/engine_config.h")"
[ -n "$RESIDUAL_LIMBS" ] || { echo "  build failed: no ENGINE_RESIDUAL_LIMBS in engine_config.h"; exit 1; }
QUESTION_LIMBS=$((RESIDUAL_LIMBS + 1))
RECORD_LIMBS="$(sed -n 's/^#define ENGINE_RECORD_LIMBS_MOST \([0-9]*\)u.*/\1/p' "$TOP/src/engine/engine_config.h")"
[ -n "$RECORD_LIMBS" ] || { echo "  build failed: no ENGINE_RECORD_LIMBS_MOST in engine_config.h"; exit 1; }
[ "$RECORD_LIMBS" -gt "$QUESTION_LIMBS" ] && QUESTION_LIMBS="$RECORD_LIMBS"
FITTED_LIMBS=1
while [ "$FITTED_LIMBS" -lt "$QUESTION_LIMBS" ]; do
    FITTED_LIMBS=$((FITTED_LIMBS * 2))
done
EXACT_LIMBS="${ANCHOR_EXACT_LIMBS:-$FITTED_LIMBS}"
EXACT_DIGITS=$(( (EXACT_LIMBS * 32 * 1000 - 1) / 3322 ))
if [ "$EXACT_DIGITS" -gt 1024 ]; then
    EXACT_DIGITS=1024
fi
[ -f "$EXACT_ROOT/exact_integer.h" ] || { echo "  build failed: no exact_integer.h under $EXACT_ROOT"; exit 1; }
EXACT_FLAGS=(-I "$EXACT_ROOT" "-DANCHOR_EXACT_LIMBS=${EXACT_LIMBS}u" "-DANCHOR_EXACT_DIGITS=${EXACT_DIGITS}u")

DEFINES=(-DBODY_OVERLAP_BUILD_DLL=1 -DHEAVIEST_MATCHING_BUILD_DLL=1
         -DSHIFT_AGREEMENT_BUILD_DLL=1)
MODULES=(engine/base/stack engine/base/apxrep engine/base/compression engine/base/tower engine/base/entropy_history
         engine/base/keymath engine/base/key_schedule engine/base/cycle engine/base/radix_keys engine/base/unit_sweep
         engine/base/obsignatio engine/base/residual engine/nbody/max_tree engine/nbody/flatten engine/nbody/grow
         engine/base/double_fields engine/base/decimal_double engine/base/scriptura engine/nbody/body_overlap
         engine/nbody/heaviest_matching engine/base/shift_agreement engine/base/period)
INGEST=(engine/base/cfg_json engine/base/zarr engine/base/zstd engine/base/inflate engine/base/deflate engine/base/lz4
        engine/base/snappy engine/base/blosc engine/base/tiff engine/base/hdf5 engine/base/zip engine/base/dicom
        engine/base/npy engine/base/nrrd engine/base/nifti)
MODULES+=("${INGEST[@]}")
MODULE_INCLUDES=(-I "$TOP/src/engine" -I "$TOP/src/engine/base")
MODULE_SOURCES=("$TOP/src/engine/engine.cu")
for module in "${MODULES[@]}"; do
    MODULE_INCLUDES+=(-I "$TOP/src/$module")
    for source in "$TOP/src/$module"/*.cu; do
        [ -f "$source" ] && MODULE_SOURCES+=("$source")
    done
done
PORTABLE_OBJECTS=()
for portable in engine/nbody/body_overlap engine/nbody/heaviest_matching engine/base/shift_agreement \
                engine/nbody/max_tree engine/base/cycle engine/base/double_fields engine/base/decimal_double \
                engine/base/scriptura "${INGEST[@]}"; do
    for source in "$TOP/src/$portable"/*.c; do
        name="$(basename "$source" .c)"
        OBJECT="$OUT/${name}_portable.o"
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*)
                OBJECT="$OUT/${name}_portable.obj"
                rm -f "$OBJECT"
                nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${DEFINES[@]}" \
                    "${MODULE_INCLUDES[@]}" "${EXACT_FLAGS[@]}" -c "$source" -o "$OBJECT"
                ;;
            *)
                rm -f "$OBJECT"
                cc -std=c11 -O2 -g -fPIC "${MODULE_INCLUDES[@]}" "${EXACT_FLAGS[@]}" -c "$source" -o "$OBJECT"
                ;;
        esac
        if [ ! -f "$OBJECT" ]; then
            echo "  build failed: $portable/$name.c did not compile"
            exit 1
        fi
        PORTABLE_OBJECTS+=("$OBJECT")
    done
done
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) EXACT_OBJECT="$OUT/exact_integer_portable.obj" ;;
    *) EXACT_OBJECT="$OUT/exact_integer_portable.o" ;;
esac
rm -f "$EXACT_OBJECT"
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${EXACT_FLAGS[@]}" -c "$EXACT_ROOT/exact_integer.c" -o "$EXACT_OBJECT" ;;
    *)
        cc -std=c11 -O2 -g -fPIC "${EXACT_FLAGS[@]}" -c "$EXACT_ROOT/exact_integer.c" -o "$EXACT_OBJECT" ;;
esac
[ -f "$EXACT_OBJECT" ] || { echo "  build failed: exact_integer.c did not compile"; exit 1; }
PORTABLE_OBJECTS+=("$EXACT_OBJECT")

nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 -fmad=false "${GENCODE[@]}" -shared \
    "${LINK_FLAGS[@]}" "${DEFINES[@]}" \
    "${MODULE_INCLUDES[@]}" "${EXACT_FLAGS[@]}" \
    -o "$LIBRARY" \
    "${MODULE_SOURCES[@]}" \
    "${PORTABLE_OBJECTS[@]}"
NVCC_STATUS=$?

if [ "$NVCC_STATUS" -ne 0 ] || [ ! -f "$LIBRARY" ]; then
    echo "  build failed: nvcc exited $NVCC_STATUS"
    exit 1
fi
echo "  built $LIBRARY"
build_publish "$LIBRARY" || exit 1
