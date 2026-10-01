#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$ROOT/.." && pwd)"
source "$ROOT/maint/build_stamp.sh"
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

EXACT_ROOT="${ANCHOR_EXACT_ROOT:-$ENGINE/../types/integers}"
RESIDUAL_LIMBS="$(sed -n 's/^#define ENGINE_RESIDUAL_LIMBS \([0-9]*\)u.*/\1/p' "$ENGINE"/engine_config_*.h)"
[ -n "$RESIDUAL_LIMBS" ] || { echo "  build failed: no ENGINE_RESIDUAL_LIMBS in engine_config_*.h"; exit 1; }
QUESTION_LIMBS=$((RESIDUAL_LIMBS + 1))
RECORD_LIMBS="$(sed -n 's/^#define ENGINE_RECORD_LIMBS_MAX \([0-9]*\)u.*/\1/p' "$ENGINE"/engine_config_*.h)"
[ -n "$RECORD_LIMBS" ] || { echo "  build failed: no ENGINE_RECORD_LIMBS_MAX in engine_config_*.h"; exit 1; }
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
MODULES=(c/includes/formats/stack cu/includes/formats/stack c/kcmplx cu/kcmplx
         c/engine/analysis/compression cu/engine/analysis/compression c/engine/analysis/tower
         cu/engine/analysis/tower c/engine/runtime/device_pool cu/engine/runtime/device_pool
         c/engine/analysis/entropy_history cu/engine/analysis/entropy_history c/engine/analysis/keymath
         cu/engine/analysis/keymath c/engine/analysis/key_schedule cu/engine/analysis/key_schedule
         c/engine/analysis/cycle cu/engine/analysis/cycle c/engine/runtime/radix_keys c/engine/analysis/unit_sweep
         cu/engine/analysis/unit_sweep c/engine/runtime/obsignatio cu/engine/runtime/obsignatio
         c/engine/analysis/residual cu/engine/analysis/residual c/engine/nbody/max_tree cu/engine/nbody/max_tree
         c/engine/nbody/flatten cu/engine/nbody/flatten c/engine/nbody/grow cu/engine/nbody/grow
         c/types/integerfloats/double_fields cu/types/integerfloats/double_fields c/types/integerfloats/decimal_double c/engine/runtime/scriptura
         c/engine/nbody/body_overlap cu/engine/nbody/body_overlap c/engine/nbody/heaviest_matching
         c/engine/analysis/shift_agreement cu/engine/analysis/shift_agreement c/engine/analysis/period
         cu/engine/analysis/period)
INGEST=(c/includes/formats/cfg_json c/includes/formats/zarr c/includes/codecs/zstd c/includes/codecs/inflate c/includes/codecs/deflate
        c/includes/codecs/lz4 c/includes/codecs/snappy c/includes/codecs/blosc c/includes/formats/tiff c/includes/formats/hdf5
        c/includes/codecs/zip c/includes/formats/dicom c/includes/formats/npy c/includes/formats/nrrd c/includes/formats/nifti)
MODULES+=("${INGEST[@]}")
MODULE_INCLUDES=(-I "$ENGINE" -I "$ENGINE/../../cu/engine" -I "$ENGINE/../includes/codecs/crc" -I "$ENGINE/../../cu/includes/codecs/crc")
MODULE_SOURCES=("$ENGINE/../../cu/engine"/engine_{record,residual,files,zarr,source,listing,seal,report,history}.cu)
for module in "${MODULES[@]}"; do
    folder="$(build_path "$module")"
    MODULE_INCLUDES+=(-I "$folder")
    for source in "$folder"/*.cu; do
        [ -f "$source" ] && MODULE_SOURCES+=("$source")
    done
done
PORTABLE_OBJECTS=()
for portable in c/engine/nbody/body_overlap c/engine/nbody/heaviest_matching c/engine/analysis/shift_agreement \
                c/engine/nbody/max_tree c/engine/analysis/cycle c/types/integerfloats/double_fields \
                c/types/integerfloats/decimal_double c/engine/runtime/scriptura "${INGEST[@]}"; do
    for source in "$(build_path "$portable")"/*.c; do
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
for name in exact_integer_{add,limbs,multiply,divide,gcd,decimal,hash}; do
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) EXACT_OBJECT="$OUT/${name}_portable.obj" ;;
        *) EXACT_OBJECT="$OUT/${name}_portable.o" ;;
    esac
    rm -f "$EXACT_OBJECT"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${EXACT_FLAGS[@]}" -c "$EXACT_ROOT/$name.c" \
                -o "$EXACT_OBJECT" ;;
        *)
            cc -std=c11 -O2 -g -fPIC "${EXACT_FLAGS[@]}" -c "$EXACT_ROOT/$name.c" -o "$EXACT_OBJECT" ;;
    esac
    [ -f "$EXACT_OBJECT" ] || { echo "  build failed: $name.c did not compile"; exit 1; }
    PORTABLE_OBJECTS+=("$EXACT_OBJECT")
done

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
