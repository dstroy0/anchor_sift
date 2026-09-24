#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$ROOT/../.." && pwd)"
source "$TOP/maint/build_stamp.sh"
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
                    -Xlinker /MANIFEST:EMBED -Xlinker "/MANIFESTINPUT:$(cygpath -m "$TOP/src/engine/long_paths.manifest")")
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
echo "  exact integer: $((EXACT_LIMBS * 32)) bits, $EXACT_DIGITS digits, for a question of $QUESTION_LIMBS limbs, from $EXACT_ROOT"

FUNCTIONALS=(src/engine/prg_sch/run_cfg src/engine/base/cfg_json src/engine/prg_sch/run_log src/engine/base/stack
             src/engine/base/apxrep src/engine/base/compression src/engine/base/tower src/engine/base/entropy_history
             src/engine/base/schedule src/engine/base/keymath src/engine/base/key_schedule src/engine/base/cycle
             src/engine/base/radix_keys src/engine/base/unit_sweep src/engine/base/obsignatio src/engine/base/residual
             src/engine/nbody/max_tree src/engine/nbody/flatten examples/cell_tracking/src/track
             src/engine/base/golden_bands src/engine/prg_sch/answer_key src/engine/base/residual_survey
             src/engine/nbody/grow src/engine/base/shift_agreement src/engine/nbody/climb_machine
             src/engine/nbody/body_overlap src/engine/nbody/fingerprint src/engine/nbody/print_pair
             src/engine/nbody/velocity src/engine/nbody/division src/engine/nbody/marginal src/engine/nbody/contact_side
             src/engine/nbody/box_history src/engine/nbody/heaviest_matching src/engine/base/double_fields
             src/engine/base/decimal_double src/engine/base/scriptura src/engine/nbody/relate_frames
             src/engine/nbody/group_objects src/engine/nbody/link_objects src/engine/nbody/bodies
             examples/cell_tracking/src/score_sample examples/cell_tracking/src/coherence
             examples/00_blob_viz_tools/view/vis_png examples/cell_tracking/src/track_driver)
INGEST=(src/engine/base/zarr src/engine/base/zstd src/engine/base/inflate src/engine/base/deflate src/engine/base/lz4
        src/engine/base/snappy src/engine/base/blosc src/engine/base/tiff src/engine/base/hdf5 src/engine/base/zip
        src/engine/base/dicom src/engine/base/npy src/engine/base/nrrd src/engine/base/nifti)
FUNCTIONALS+=("${INGEST[@]}")
FUNCTIONAL_INCLUDES=(-I "$TOP/src/engine" -I "$TOP/src/engine/base" -I "$TOP/src/engine/daemon")
FUNCTIONAL_SOURCES=("$TOP/src/engine/engine.cu")
for functional in "${FUNCTIONALS[@]}"; do
    [ -d "$TOP/$functional" ] || { echo "  build failed: no $functional"; exit 1; }
    FUNCTIONAL_INCLUDES+=(-I "$TOP/$functional")
    for source in "$TOP/$functional"/*.cu; do
        [ -f "$source" ] && FUNCTIONAL_SOURCES+=("$source")
    done
done

PORTABLE_OBJECTS=()
for portable in src/engine/nbody/body_overlap src/engine/base/shift_agreement src/engine/base/cfg_json \
                src/engine/nbody/max_tree src/engine/base/cycle src/engine/nbody/heaviest_matching \
                src/engine/nbody/marginal src/engine/base/double_fields src/engine/base/decimal_double \
                src/engine/base/scriptura "${INGEST[@]}"; do
    for source in "$TOP/$portable"/*.c; do
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
for name in tessera_client tessera_paths tessera_frame tessera_self tessera_ledger tessera_measure tessera_daemon; do
    OBJECT="$OUT/${name}_portable.$OBJECT_SUFFIX"
    rm -f "$OBJECT"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${FUNCTIONAL_INCLUDES[@]}" -c "$TOP/src/engine/daemon/$name.c" -o "$OBJECT" ;;
        *)
            cc -std=c11 -O2 -g -fPIC "${FUNCTIONAL_INCLUDES[@]}" -c "$TOP/src/engine/daemon/$name.c" -o "$OBJECT" ;;
    esac
    [ -f "$OBJECT" ] || { echo "  build failed: src/engine/daemon/$name.c did not compile"; exit 1; }
    case "$name" in
        tessera_client) TESSERA_CLIENT_OBJECTS+=("$OBJECT") ;;
        tessera_paths|tessera_frame|tessera_self) TESSERA_CLIENT_OBJECTS+=("$OBJECT"); TESSERA_DAEMON_OBJECTS+=("$OBJECT") ;;
        *) TESSERA_DAEMON_OBJECTS+=("$OBJECT") ;;
    esac
done
PORTABLE_OBJECTS+=("${TESSERA_CLIENT_OBJECTS[@]}")
SEAL_OBJECT="$OUT/obsignatio_daemon.$OBJECT_SUFFIX"
DAEMON="$OUT/tessera_daemon$SUFFIX"
rm -f "$SEAL_OBJECT" "$DAEMON"
nvcc "${HOST_FLAGS[@]}" -O2 "${GENCODE[@]}" "${FUNCTIONAL_INCLUDES[@]}" -c "$TOP/src/engine/base/obsignatio/obsignatio.cu" \
    -o "$SEAL_OBJECT"
nvcc "${HOST_FLAGS[@]}" "${GENCODE[@]}" "${LINK_FLAGS[@]}" -o "$DAEMON" "${TESSERA_DAEMON_OBJECTS[@]}" \
    "${SCRIPTURA_OBJECTS[@]}" "$SEAL_OBJECT" "${DAEMON_LIBRARIES[@]}"
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
