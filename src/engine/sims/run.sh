#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

SIMS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$SIMS/../.." && pwd)"
SIM="${1:-}"
shift || true
case "$SIM" in
    nbody_lattice|knf_identity|noise_floor|noise_terms|noise_root|period_power|root_universal|ask_state|ka_psi|chaitin_omega|goodstein|pi_tower|pi_plane|omega_computer|floor_match|floor_track|fixed_pattern|classify_reject_recover) ;;
    *)
        echo "  usage: run.sh nbody_lattice|knf_identity|noise_floor|noise_terms|noise_root|period_power|root_universal|ask_state|ka_psi|chaitin_omega|goodstein|pi_tower|pi_plane|omega_computer|floor_match|floor_track|fixed_pattern|classify_reject_recover [-- sim arguments]"
        exit 2
        ;;
esac
SIM_ARGUMENTS=()
if [ "${1:-}" = "--" ]; then
    shift
    SIM_ARGUMENTS=("$@")
fi

SCRIPTURA="$TOP/engine/base/scriptura"
NO_ROUNDING="$TOP/engine/base/no_rounding"
PERIOD="$TOP/engine/base/period"
TOWER="$TOP/engine/base/tower"
DEVICE_POOL="$TOP/engine/base/device_pool"
COMPRESSION="$TOP/engine/base/compression"
CYCLE="$TOP/engine/base/cycle"
KEYMATH="$TOP/engine/base/keymath"
KEY_SCHEDULE="$TOP/engine/base/key_schedule"
ENTROPY_HISTORY="$TOP/engine/base/entropy_history"
NOISE_DETECTOR="$TOP/engine/base/noise_detector"
source "$TOP/maint/build_stamp.sh"
build_stamp "sim_$SIM"

case "$SIM" in
    fixed_pattern|classify_reject_recover) SOURCE="$SIMS/art/$SIM.cu" ;;
    *) SOURCE="$SIMS/$SIM/$SIM.cu" ;;
esac
MODULE_SOURCES=()
if [ "$SIM" = "period_power" ]; then
    MODULE_SOURCES+=("$PERIOD/period.cu" "$DEVICE_POOL/device_pool.cu")
fi
if [ "$SIM" = "root_universal" ]; then
    MODULE_SOURCES+=("$TOWER/tower.cu" "$DEVICE_POOL/device_pool.cu" "$COMPRESSION/compression.cu")
fi
if [ "$SIM" = "knf_identity" ]; then
    MODULE_SOURCES+=("$ENTROPY_HISTORY/entropy_history.cu")
fi
# noise_terms reads each planted volume back through the noise detector's volume readings
if [ "$SIM" = "noise_terms" ]; then
    MODULE_SOURCES+=("$NOISE_DETECTOR/noise_detector.cu")
fi
# noise_root finds each planted term as a box's root noise, pricing it through the tower and compression's coder
if [ "$SIM" = "noise_root" ]; then
    MODULE_SOURCES+=("$NOISE_DETECTOR/noise_detector.cu" "$TOWER/tower.cu" "$DEVICE_POOL/device_pool.cu"
                     "$COMPRESSION/compression.cu")
fi
if [ "$SIM" = "floor_match" ] || [ "$SIM" = "floor_track" ]; then
    MODULE_SOURCES+=("$TOWER/tower.cu" "$DEVICE_POOL/device_pool.cu")
fi
# chaitin_omega runs its reduction, and pi_tower its BBP terms, as programs on the engine's record machine
HOST_SOURCES=()
if [ "$SIM" = "chaitin_omega" ] || [ "$SIM" = "pi_tower" ]; then
    MODULE_SOURCES+=("$CYCLE/cycle.cu" "$KEYMATH/keymath.cu" "$KEY_SCHEDULE/key_schedule.cu")
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
        LONG_PATHS=(-Xlinker /MANIFEST:EMBED -Xlinker "/MANIFESTINPUT:$(cygpath -m "$TOP/engine/long_paths.manifest")")
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

DAEMON_DIRECTORY="$TOP/engine/daemon"
OBSIGNATIO="$TOP/engine/base/obsignatio"
INCLUDES=(-I "$TOP/engine" -I "$SIMS" -I "$SCRIPTURA" -I "$NO_ROUNDING" -I "$PERIOD" -I "$TOWER" -I "$DEVICE_POOL"
          -I "$COMPRESSION" -I "$CYCLE" -I "$KEYMATH" -I "$KEY_SCHEDULE" -I "$DAEMON_DIRECTORY" -I "$OBSIGNATIO")
if [ "$SIM" = "knf_identity" ]; then
    INCLUDES+=(-I "$TOP/engine/base" -I "$ENTROPY_HISTORY")
fi
if [ "$SIM" = "noise_terms" ] || [ "$SIM" = "noise_root" ]; then
    INCLUDES+=(-I "$NOISE_DETECTOR")
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
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING/exact_integer.c" "${HOST_SOURCES[@]}"; do
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
for name in tessera_client tessera_paths tessera_frame tessera_self tessera_ledger tessera_measure tessera_daemon; do
    object="$OUT/${name}_sim.$EXTENSION"
    build_object "$DAEMON_DIRECTORY/$name.c" "$object"
    case "$name" in
        tessera_client) OBJECTS+=("$object") ;;
        tessera_paths|tessera_frame|tessera_self) OBJECTS+=("$object"); DAEMON_OBJECTS+=("$object") ;;
        *) DAEMON_OBJECTS+=("$object") ;;
    esac
done
SEAL_OBJECT="$OUT/obsignatio_sim.$EXTENSION"
rm -f "$SEAL_OBJECT"
nvcc "${HOST_FLAGS[@]}" -O2 "${GENCODE[@]}" "${WIDTH[@]}" "${INCLUDES[@]}" -c "$OBSIGNATIO/obsignatio.cu" -o "$SEAL_OBJECT"
[ -f "$SEAL_OBJECT" ] || { echo "  build failed: obsignatio.cu did not compile"; exit 1; }
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) DAEMON="$OUT/tessera_daemon.exe"; DAEMON_LIBRARIES=(-lpdh) ;;
    *) DAEMON="$OUT/tessera_daemon"; DAEMON_LIBRARIES=(-ldl -lpthread) ;;
esac
rm -f "$DAEMON"
nvcc "${HOST_FLAGS[@]}" "${GENCODE[@]}" "${LONG_PATHS[@]}" -o "$DAEMON" "${DAEMON_OBJECTS[@]}" "${SCRIPTURA_OBJECTS[@]}" \
    "$SEAL_OBJECT" "${DAEMON_LIBRARIES[@]}"
[ -f "$DAEMON" ] || { echo "  build failed: the tessera daemon did not link"; exit 1; }

nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" "${WIDTH[@]}" "${INCLUDES[@]}" "${LONG_PATHS[@]}" -o "$BINARY" \
    "$SOURCE" "$SIMS/sim_job.cu" "${MODULE_SOURCES[@]}" "${OBJECTS[@]}" "$SEAL_OBJECT"
[ -f "$BINARY" ] || { echo "  build failed: nvcc could not build $SIM"; exit 1; }

"$BINARY" "${SIM_ARGUMENTS[@]}"
STATUS=$?
echo "  $SIM exit $STATUS"
exit "$STATUS"
