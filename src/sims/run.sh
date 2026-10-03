#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

SIMS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIMS_CU="$SIMS/cu"
TOP="$(cd "$SIMS/.." && pwd)"
SIM="${1:-}"
shift || true
case "$SIM" in
    nbody_lattice|knf_identity|noise_floor|noise_terms|noise_root|period_power|root_universal|ask_state|ka_psi|chaitin_omega|goodstein|pi_tower|pi_plane|exponential_integral|omega_computer|floor_match|floor_track|fixed_pattern|classify_reject_recover) ;;
    *)
        echo "  usage: run.sh nbody_lattice|knf_identity|noise_floor|noise_terms|noise_root|period_power|root_universal|ask_state|ka_psi|chaitin_omega|goodstein|pi_tower|pi_plane|exponential_integral|omega_computer|floor_match|floor_track|fixed_pattern|classify_reject_recover [-- sim arguments]"
        exit 2
        ;;
esac
SIM_ARGUMENTS=()
if [ "${1:-}" = "--" ]; then
    shift
    SIM_ARGUMENTS=("$@")
fi

SCRIPTURA="$TOP/c/engine/runtime/scriptura"
NO_ROUNDING="$TOP/c/types/integers"
PERIOD="$TOP/c/engine/analysis/period"
PERIOD_CU="$TOP/cu/engine/analysis/period"
TOWER="$TOP/c/engine/analysis/tower"
TOWER_CU="$TOP/cu/engine/analysis/tower"
DEVICE_POOL="$TOP/c/engine/runtime/device_pool"
DEVICE_POOL_CU="$TOP/cu/engine/runtime/device_pool"
COMPRESSION="$TOP/c/engine/analysis/compression"
COMPRESSION_CU="$TOP/cu/engine/analysis/compression"
CYCLE="$TOP/c/engine/analysis/cycle"
CYCLE_CU="$TOP/cu/engine/analysis/cycle"
CODEGEN="$TOP/c/transpiler/codegen"
CODEGEN_CU="$TOP/cu/transpiler/codegen"
CODEGEN_CU_2="$TOP/cu/types/file_defs/krs"
KEYMATH="$TOP/c/engine/analysis/keymath"
KEYMATH_CU="$TOP/cu/engine/analysis/keymath"
KEY_SCHEDULE="$TOP/c/engine/analysis/key_schedule"
KEY_SCHEDULE_CU="$TOP/cu/engine/analysis/key_schedule"
ENTROPY_HISTORY="$TOP/c/engine/analysis/entropy_history"
ENTROPY_HISTORY_CU="$TOP/cu/engine/analysis/entropy_history"
NOISE_DETECTOR="$TOP/c/engine/analysis/noise_detector"
NOISE_DETECTOR_CU="$TOP/cu/engine/analysis/noise_detector"
# utils/maint/ is at the repository's root, one above src/
source "$(cd "$TOP/.." && pwd)/utils/maint/engine/build_stamp.sh"
build_stamp "sim_$SIM"

# every sim's folder lies under cu/, at the place in the tree its subject has, and carries the sim's name
case "$SIM" in
    fixed_pattern|classify_reject_recover) SOURCES=("$SIMS/cu/engine/analysis/art$SIM.cu") ;;
    *)
        FOLDER="$(find "$SIMS_CU" -type d -name "$SIM" | head -1)"
        [ -n "$FOLDER" ] || { echo "  no folder named $SIM under $SIMS_CU"; exit 2; }
        SOURCES=("$FOLDER"/*.cu)
        ;;
esac
NOISE_DETECTOR_SOURCES=("$NOISE_DETECTOR_CU"/noise_detector_{flicker,lines,lines_summary,neighbors,clips,pixels}.cu
                        "$NOISE_DETECTOR_CU"/noise_detector_{moments,ladder,crosstalk,structure,halves,root}.cu)
MODULE_SOURCES=()
if [ "$SIM" = "period_power" ]; then
    MODULE_SOURCES+=("$PERIOD_CU"/period_{measure,select}.cu "$DEVICE_POOL_CU/device_pool.cu")
fi
if [ "$SIM" = "root_universal" ]; then
    MODULE_SOURCES+=("$TOWER_CU/tower.cu" "$TOWER_CU/tower_record.cu" "$TOWER_CU/tower_run.cu" "$DEVICE_POOL_CU/device_pool.cu" "$COMPRESSION_CU/compression.cu")
fi
if [ "$SIM" = "knf_identity" ]; then
    MODULE_SOURCES+=("$ENTROPY_HISTORY_CU/entropy_history.cu")
fi
# noise_terms reads each planted volume back through the noise detector's volume readings, and noise_floor fits its
# transfer curves by the detector's line over the level
if [ "$SIM" = "noise_terms" ] || [ "$SIM" = "noise_floor" ]; then
    MODULE_SOURCES+=("${NOISE_DETECTOR_SOURCES[@]}")
fi
# noise_root finds each planted term as a box's root noise, pricing it through the tower and compression's coder
if [ "$SIM" = "noise_root" ]; then
    MODULE_SOURCES+=("${NOISE_DETECTOR_SOURCES[@]}" "$TOWER_CU/tower.cu" "$TOWER_CU/tower_record.cu" "$TOWER_CU/tower_run.cu" "$DEVICE_POOL_CU/device_pool.cu"
                     "$COMPRESSION_CU/compression.cu")
fi
if [ "$SIM" = "floor_match" ] || [ "$SIM" = "floor_track" ]; then
    MODULE_SOURCES+=("$TOWER_CU/tower.cu" "$TOWER_CU/tower_record.cu" "$TOWER_CU/tower_run.cu" "$DEVICE_POOL_CU/device_pool.cu")
fi
# chaitin_omega runs its reduction, and pi_tower its BBP terms, as programs on the engine's record machine
HOST_SOURCES=()
if [ "$SIM" = "chaitin_omega" ] || [ "$SIM" = "pi_tower" ]; then
    MODULE_SOURCES+=("$CYCLE_CU/cycle_compile_cache.cu" "$CYCLE_CU/cycle_compile.cu" "$CYCLE_CU/cycle_compile_route.cu" "$CYCLE_CU/cycle_compile_toolchain.cu" "$CYCLE_CU/cycle_launch.cu" "$CYCLE_CU/cycle_prelude.cu" "$CYCLE_CU/cycle_record.cu" "$CYCLE_CU/cycle_record_launch.cu" "$CYCLE_CU/cycle_sweep.cu" "$CODEGEN_CU/asm_printer_layout.cu" "$CODEGEN_CU/asm_printer_program.cu" "$CODEGEN_CU/c_target.cu" "$CODEGEN_CU/code_generator.cu" "$CODEGEN_CU/code_generator_entries.cu" "$CODEGEN_CU/codegen.cu" "$CODEGEN_CU/codegen_lowering.cu" "$CODEGEN_CU/codegen_output.cu" "$CODEGEN_CU/codegen_reader.cu" "$CODEGEN_CU/codegen_rules.cu" "$CODEGEN_CU/ptx_target.cu" "$CODEGEN_CU_2/ruleset_flat.cu" "$CODEGEN_CU/sass_target.cu" "$CODEGEN_CU/target_parse.cu" "$CODEGEN_CU/target_rulesets.cu" "$CODEGEN_CU/vhdl_target.cu" "$CODEGEN_CU/yosys_script.cu" "$KEYMATH_CU/keymath.cu" "$KEY_SCHEDULE_CU/key_schedule.cu")
    HOST_SOURCES+=("$CYCLE/cycle.c")
fi

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/$SIM.exe"
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
        LONG_PATHS=(-Xlinker /MANIFEST:EMBED -Xlinker "/MANIFESTINPUT:$(cygpath -m "$TOP/cu/long_paths.manifest")")
        ;;
    *)
        BINARY="$OUT/$SIM"
        EXTENSION=o
        HOST_FLAGS=(-Xcompiler -fPIC)
        LONG_PATHS=()
        ;;
esac

ARCHES="${SIM_ARCHES:-}"
if [ -z "$ARCHES" ]; then
    CAP="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' .')"
    ARCHES="sm_${CAP:-86}"
fi
GENCODE=()
for one in $ARCHES; do
    GENCODE+=(-gencode "arch=compute_${one#sm_},code=${one}")
done

DAEMON_DIRECTORY="$TOP/c/engine/runtime/daemon"
OBSIGNATIO="$TOP/c/engine/runtime/obsignatio"
OBSIGNATIO_CU="$TOP/cu/engine/runtime/obsignatio"
INCLUDES=(-I "$TOP/c/engine" -I "$SIMS" -I "$SIMS_CU" -I "$SCRIPTURA" -I "$NO_ROUNDING" -I "$PERIOD" -I "$PERIOD_CU" -I "$TOWER" -I "$TOWER_CU" -I "$DEVICE_POOL"
          -I "$COMPRESSION" -I "$CYCLE" -I "$CYCLE_CU" -I "$KEYMATH" -I "$KEYMATH_CU" -I "$KEY_SCHEDULE" -I "$KEY_SCHEDULE_CU" -I "$DAEMON_DIRECTORY" -I "$OBSIGNATIO" -I "$OBSIGNATIO_CU")
if [ "$SIM" = "knf_identity" ]; then
    INCLUDES+=(-I "$TOP/c/includes/codecs/crc" -I "$TOP/cu/includes/codecs/crc" -I "$ENTROPY_HISTORY")
fi
if [ "$SIM" = "noise_terms" ] || [ "$SIM" = "noise_root" ] || [ "$SIM" = "noise_floor" ]; then
    INCLUDES+=(-I "$NOISE_DETECTOR" -I "$NOISE_DETECTOR_CU")
fi
# SIM_EXACT_LIMBS sets the exact integer's width in 32-bit limbs, a power of two, for every object the sim links
WIDTH=()
if [ -n "${SIM_EXACT_LIMBS:-}" ]; then
    WIDTH=(-DANCHOR_EXACT_LIMBS="${SIM_EXACT_LIMBS}u")
fi
rm -f "$BINARY"
build_object()
{
    local source="$1"
    local object="$2"
    rm -f "$object"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${WIDTH[@]}" "${INCLUDES[@]}" -c "$source" -o "$object" ;;
        *)
            cc -std=c11 -O2 -fPIC "${WIDTH[@]}" "${INCLUDES[@]}" -c "$source" -o "$object" ;;
    esac
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
}
OBJECTS=()
SCRIPTURA_OBJECTS=()
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING"/exact_integer_{add,limbs,multiply,divide,gcd,decimal,hash}.c \
              "${HOST_SOURCES[@]}"; do
    object="$OUT/$(basename "$source" .c)_sim.$EXTENSION"
    build_object "$source" "$object"
    OBJECTS+=("$object")
    case "$(basename "$source")" in
        scriptura*) SCRIPTURA_OBJECTS+=("$object") ;;
    esac
done

# a sim that uses the device is a job on the device's tessera daemon: the client goes into the sim, and the daemon
# is built beside it, where the sim starts it when none answers
DAEMON_OBJECTS=()
for name in tessera_client_{socket,jobs} tessera_paths tessera_frame tessera_self tessera_ledger tessera_measure \
            tessera_daemon_{state,admission,peers,main}; do
    object="$OUT/${name}_sim.$EXTENSION"
    build_object "$DAEMON_DIRECTORY/$name.c" "$object"
    case "$name" in
        tessera_client_*) OBJECTS+=("$object") ;;
        tessera_paths|tessera_frame|tessera_self) OBJECTS+=("$object"); DAEMON_OBJECTS+=("$object") ;;
        *) DAEMON_OBJECTS+=("$object") ;;
    esac
done
SEAL_OBJECTS=()
for name in obsignatio_{hash,seal}; do
    object="$OUT/${name}_sim.$EXTENSION"
    rm -f "$object"
    nvcc "${HOST_FLAGS[@]}" -O2 "${GENCODE[@]}" "${WIDTH[@]}" "${INCLUDES[@]}" -c "$OBSIGNATIO_CU/$name.cu" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $name.cu did not compile"; exit 1; }
    SEAL_OBJECTS+=("$object")
done
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) DAEMON="$OUT/tessera_daemon.exe"; DAEMON_LIBRARIES=(-lpdh) ;;
    *) DAEMON="$OUT/tessera_daemon"; DAEMON_LIBRARIES=(-ldl -lpthread) ;;
esac
rm -f "$DAEMON"
nvcc "${HOST_FLAGS[@]}" "${GENCODE[@]}" "${LONG_PATHS[@]}" -o "$DAEMON" "${DAEMON_OBJECTS[@]}" "${SCRIPTURA_OBJECTS[@]}" \
    "${SEAL_OBJECTS[@]}" "${DAEMON_LIBRARIES[@]}"
[ -f "$DAEMON" ] || { echo "  build failed: the tessera daemon did not link"; exit 1; }

nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" "${WIDTH[@]}" "${INCLUDES[@]}" "${LONG_PATHS[@]}" -o "$BINARY" \
    "${SOURCES[@]}" "$SIMS/cu/sim_job.cu" "${MODULE_SOURCES[@]}" "${OBJECTS[@]}" "${SEAL_OBJECTS[@]}"
[ -f "$BINARY" ] || { echo "  build failed: nvcc could not build $SIM"; exit 1; }

"$BINARY" "${SIM_ARGUMENTS[@]}"
STATUS=$?
echo "  $SIM exit $STATUS"
exit "$STATUS"
