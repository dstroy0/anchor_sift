#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Builds test/python/periodic_energy_probe.cu, a job on the device's tessera daemon, and runs
# test/python/periodic_energy_test.py against it: measure.periodic_energy graded against
# src/engine/sims/art/periodic_energy.h, line for line.
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../.." && pwd)"
ART="$TOP/src/engine/sims/art"
DEVICE_POOL="$TOP/src/engine/runtime/device_pool"
NO_ROUNDING="$TOP/src/engine/arithmetic/no_rounding"
SCRIPTURA="$TOP/src/engine/runtime/scriptura"
source "$TOP/maint/build_stamp.sh"
source "$TOP/maint/tessera_build.sh"
build_stamp python_periodic_energy_test

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/periodic_energy_probe.exe"
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
        BINARY="$OUT/periodic_energy_probe"
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

INCLUDES=(-I "$TOP/src/engine" -I "$ART" -I "$DEVICE_POOL" -I "$NO_ROUNDING" -I "$SCRIPTURA" "${TESSERA_INCLUDES[@]}")
rm -f "$BINARY"
OBJECTS=()
SCRIPTURA_OBJECTS=()
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING"/exact_integer_{add,limbs,multiply,divide,gcd,decimal,hash}.c; do
    object="$OUT/$(basename "$source" .c)_python_periodic_energy.$EXTENSION"
    rm -f "$object"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            nvcc "${HOST_FLAGS[@]}" -Xcompiler "/std:c11 /O2" "${INCLUDES[@]}" -c "$source" -o "$object" ;;
        *)
            cc -std=c11 -O2 -fPIC "${INCLUDES[@]}" -c "$source" -o "$object" ;;
    esac
    [ -f "$object" ] || { echo "  build failed: $(basename "$source") did not compile"; exit 1; }
    OBJECTS+=("$object")
    case "$(basename "$source")" in
        scriptura*) SCRIPTURA_OBJECTS+=("$object") ;;
    esac
done
# the probe is a job on the device's tessera daemon, built beside it
tessera_build python_periodic_energy "${SCRIPTURA_OBJECTS[@]}" || exit 1

nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" "${INCLUDES[@]}" -o "$BINARY" \
    "$TEST/periodic_energy_probe.cu" "$TOP/src/engine/sims/sim_job.cu" \
    "${OBJECTS[@]}" "${TESSERA_OBJECTS[@]}" "${TESSERA_SEAL[@]}"
[ -f "$BINARY" ] || { echo "  build failed: nvcc could not build the probe"; exit 1; }
if [ "${BUILD_ONLY:-0}" = "1" ]; then
    echo "  built $BINARY"
    exit 0
fi

PROBE="$BINARY"
# a Windows Python reads a Windows path
if command -v cygpath >/dev/null 2>&1; then
    PROBE="$(cygpath -m "$PROBE")"
fi
ANCHOR_PERIODIC_ENERGY_PROBE="$PROBE" python "$TEST/periodic_energy_test.py"
STATUS=$?
echo "  python periodic energy test exit $STATUS"
exit "$STATUS"
