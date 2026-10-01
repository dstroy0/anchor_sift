#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$ROOT/.." && pwd)"
source "$ROOT/maint/build_stamp.sh"
build_stamp driver
NAME="${DRIVER_NAME:-track_driver}"
EXTRA_DEFINES=(${DRIVER_DEFINES:-})

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/$NAME.exe"
        MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        if [ -z "$MSVC_BIN" ]; then
            MSVC_BIN="$(ls -d "/c/Program Files/Microsoft Visual Studio"/*/*/VC/Tools/MSVC/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
        fi
        if [ -z "$MSVC_BIN" ]; then
            echo "  no host compiler nvcc accepts on this platform was found."
            exit 1
        fi
        HOST_FLAGS=(-ccbin "$MSVC_BIN" -Xcompiler /Zc:preprocessor -Xcompiler -Z7)
        LINK_FLAGS=(-Xlinker -DEBUG -Xlinker -OPT:REF -Xlinker -OPT:ICF
                    -Xlinker /MANIFEST:EMBED -Xlinker "/MANIFESTINPUT:$(cygpath -m "$ENGINE/../../cu/long_paths.manifest")")
        ;;
    *)
        BINARY="$OUT/$NAME"
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
echo "  exact integer: $((EXACT_LIMBS * 32)) bits, $EXACT_DIGITS digits, for a question of $QUESTION_LIMBS limbs, from $EXACT_ROOT"

FUNCTIONALS=(cell_tracking/src/run_cfg c/includes/formats/cfg_json cell_tracking/src/run_log
             c/includes/formats/stack cu/includes/formats/stack c/kcmplx cu/kcmplx
             c/engine/analysis/compression cu/engine/analysis/compression c/engine/analysis/tower
             cu/engine/analysis/tower c/engine/runtime/device_pool cu/engine/runtime/device_pool
             c/engine/analysis/entropy_history cu/engine/analysis/entropy_history
             c/engine/analysis/noise_detector cu/engine/analysis/noise_detector c/engine/runtime/schedule
             cu/engine/runtime/schedule c/engine/analysis/keymath cu/engine/analysis/keymath
             c/engine/analysis/key_schedule cu/engine/analysis/key_schedule c/engine/analysis/cycle
             cu/engine/analysis/cycle c/transpiler/codegen cu/transpiler/codegen cu/types/file_defs/krs
             c/engine/runtime/radix_keys c/engine/analysis/unit_sweep cu/engine/analysis/unit_sweep
             c/engine/runtime/obsignatio cu/engine/runtime/obsignatio c/engine/analysis/residual
             cu/engine/analysis/residual c/engine/nbody/max_tree cu/engine/nbody/max_tree c/engine/nbody/flatten
             cu/engine/nbody/flatten cell_tracking/src/track c/engine/analysis/golden_bands
             cu/engine/analysis/golden_bands cell_tracking/src/answer_key c/engine/analysis/residual_survey
             cu/engine/analysis/residual_survey c/engine/nbody/grow cu/engine/nbody/grow
             c/engine/analysis/shift_agreement cu/engine/analysis/shift_agreement c/engine/nbody/climb_machine
             cu/engine/nbody/climb_machine c/engine/nbody/body_overlap cu/engine/nbody/body_overlap
             c/engine/nbody/fingerprint cu/engine/nbody/fingerprint c/engine/nbody/print_pair
             cu/engine/nbody/print_pair c/engine/nbody/velocity cu/engine/nbody/velocity c/engine/nbody/division
             cu/engine/nbody/division c/engine/nbody/marginal cu/engine/nbody/marginal
             c/engine/nbody/contact_side cu/engine/nbody/contact_side c/engine/nbody/box_history
             cu/engine/nbody/box_history c/engine/nbody/heaviest_matching c/types/integerfloats/double_fields cu/types/integerfloats/double_fields
             c/types/integerfloats/decimal_double c/engine/runtime/scriptura cell_tracking/src/relate_frames
             cell_tracking/src/group_objects cell_tracking/src/link_objects cell_tracking/src/bodies
             cell_tracking/src/score_sample cell_tracking/src/coherence cell_tracking/src/peaks
             cell_tracking/src/scan cell_tracking/src/sort cell_tracking/src/divide cell_tracking/src/faces
             cell_tracking/src/output orior/examples/00_blob_viz_tools/view/vis_png
             cell_tracking/src/track_driver)
INGEST=(c/includes/formats/zarr c/includes/codecs/zstd c/includes/codecs/inflate c/includes/codecs/deflate c/includes/codecs/lz4
        c/includes/codecs/snappy c/includes/codecs/blosc c/includes/formats/tiff c/includes/formats/hdf5 c/includes/codecs/zip
        c/includes/formats/dicom c/includes/formats/npy c/includes/formats/nrrd c/includes/formats/nifti)
FUNCTIONALS+=("${INGEST[@]}")
FUNCTIONAL_INCLUDES=(-I "$ENGINE" -I "$ENGINE/../../cu/engine" -I "$ENGINE/../includes/codecs/crc" -I "$ENGINE/../../cu/includes/codecs/crc" -I "$ENGINE/runtime/daemon")
FUNCTIONAL_SOURCES=("$ENGINE/../../cu/engine"/engine_{record,residual,files,zarr,source,listing,seal,report,history}.cu)
for functional in "${FUNCTIONALS[@]}"; do
    folder="$(build_path "$functional")"
    [ -d "$folder" ] || { echo "  build failed: no $functional"; exit 1; }
    FUNCTIONAL_INCLUDES+=(-I "$folder")
    for source in "$folder"/*.cu; do
        [ -f "$source" ] && FUNCTIONAL_SOURCES+=("$source")
    done
done

PORTABLE_OBJECTS=()
for portable in c/engine/nbody/body_overlap c/engine/analysis/shift_agreement c/includes/formats/cfg_json \
                c/engine/nbody/max_tree c/engine/analysis/cycle c/engine/nbody/heaviest_matching c/engine/nbody/marginal \
                c/types/integerfloats/double_fields c/types/integerfloats/decimal_double c/engine/runtime/scriptura \
                "${INGEST[@]}"; do
    for source in "$(build_path "$portable")"/*.c; do
        name="$(basename "$source" .c)"
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*) OBJECT="$OUT/${name}_portable.obj" ;;
            *) OBJECT="$OUT/${name}_portable.o" ;;
        esac
        rm -f "$OBJECT"
        case "$(uname -s)" in
            MINGW*|MSYS*|CYGWIN*)
                nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${FUNCTIONAL_INCLUDES[@]}" "${EXACT_FLAGS[@]}" -c "$source" -o "$OBJECT" ;;
            *)
                cc -std=c11 -O2 -g -fPIC "${FUNCTIONAL_INCLUDES[@]}" "${EXACT_FLAGS[@]}" -c "$source" -o "$OBJECT" ;;
        esac
        [ -f "$OBJECT" ] || { echo "  build failed: $portable/$name.c did not compile"; exit 1; }
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

# every run of the driver is a job on the device's tessera daemon: the client goes into the driver, and the daemon
# is built and published beside it, where the driver starts it when none answers
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) SUFFIX=.exe; OBJECT_SUFFIX=obj; DAEMON_LIBRARIES=(-lpdh) ;;
    *) SUFFIX=; OBJECT_SUFFIX=o; DAEMON_LIBRARIES=(-ldl -lpthread) ;;
esac
SCRIPTURA_OBJECTS=()
for object in "${PORTABLE_OBJECTS[@]}"; do
    case "$(basename "$object")" in
        scriptura*) SCRIPTURA_OBJECTS+=("$object") ;;
    esac
done
TESSERA_CLIENT_OBJECTS=()
TESSERA_DAEMON_OBJECTS=()
for name in tessera_client_{socket,jobs} tessera_paths tessera_frame tessera_self tessera_ledger tessera_measure \
            tessera_daemon_{state,admission,peers,main}; do
    OBJECT="$OUT/${name}_portable.$OBJECT_SUFFIX"
    rm -f "$OBJECT"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${FUNCTIONAL_INCLUDES[@]}" \
                -c "$ENGINE/runtime/daemon/$name.c" -o "$OBJECT" ;;
        *)
            cc -std=c11 -O2 -g -fPIC "${FUNCTIONAL_INCLUDES[@]}" -c "$ENGINE/runtime/daemon/$name.c" -o "$OBJECT" ;;
    esac
    [ -f "$OBJECT" ] || { echo "  build failed: c/engine/runtime/daemon/$name.c did not compile"; exit 1; }
    case "$name" in
        tessera_client_*) TESSERA_CLIENT_OBJECTS+=("$OBJECT") ;;
        tessera_paths|tessera_frame|tessera_self) TESSERA_CLIENT_OBJECTS+=("$OBJECT"); TESSERA_DAEMON_OBJECTS+=("$OBJECT") ;;
        *) TESSERA_DAEMON_OBJECTS+=("$OBJECT") ;;
    esac
done
PORTABLE_OBJECTS+=("${TESSERA_CLIENT_OBJECTS[@]}")
DAEMON="$OUT/tessera_daemon$SUFFIX"
rm -f "$DAEMON"
SEAL_OBJECTS=()
for name in obsignatio_{hash,seal}; do
    SEAL_OBJECT="$OUT/${name}_daemon.$OBJECT_SUFFIX"
    rm -f "$SEAL_OBJECT"
    nvcc "${HOST_FLAGS[@]}" -O2 "${GENCODE[@]}" "${FUNCTIONAL_INCLUDES[@]}" -c "$ENGINE/../../cu/engine/runtime/obsignatio/$name.cu" \
        -o "$SEAL_OBJECT"
    SEAL_OBJECTS+=("$SEAL_OBJECT")
done
nvcc "${HOST_FLAGS[@]}" "${GENCODE[@]}" "${LINK_FLAGS[@]}" -o "$DAEMON" "${TESSERA_DAEMON_OBJECTS[@]}" \
    "${SCRIPTURA_OBJECTS[@]}" "${SEAL_OBJECTS[@]}" "${DAEMON_LIBRARIES[@]}"
[ -f "$DAEMON" ] || { echo "  build failed: the tessera daemon did not link"; exit 1; }
echo "  built $DAEMON"

rm -f "$BINARY"
nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 -fmad=false "${GENCODE[@]}" "${EXTRA_DEFINES[@]}" \
    "${LINK_FLAGS[@]}" "${FUNCTIONAL_INCLUDES[@]}" "${EXACT_FLAGS[@]}" \
    -o "$BINARY" \
    "${FUNCTIONAL_SOURCES[@]}" \
    "${PORTABLE_OBJECTS[@]}"
STATUS=$?
if [ "$STATUS" -ne 0 ] || [ ! -f "$BINARY" ]; then
    echo "  build failed: nvcc exited $STATUS"
    exit 1
fi
echo "  built $BINARY"
build_publish "$DAEMON" || exit 1
build_publish "$BINARY" || exit 1
