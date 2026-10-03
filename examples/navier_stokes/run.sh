#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds axis_heat on the host and runs it on the cfg named: bash run.sh cfg/water_20c.cfg
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$ROOT/.." && pwd)"
SRC="$(cd "$TOP/../src" && pwd)"
CFG="${1:-}"
[ -n "$CFG" ] && [ -f "$CFG" ] || { echo "  usage: run.sh <cfg>"; exit 2; }
source "$TOP/../utils/maint/engine/build_stamp.sh"
build_stamp navier_stokes

SIMS_CU="$SRC/sims/cu"
TOWER="$SIMS_CU/types/integers/exponential_integral"
SCRIPTURA="$SRC/c/engine/runtime/scriptura"
NO_ROUNDING="$SRC/c/types/integers"
CFG_JSON="$SRC/c/includes/formats/cfg_json"
DAEMON_DIRECTORY="$SRC/c/engine/runtime/daemon"
OBSIGNATIO="$SRC/c/engine/runtime/obsignatio"
OBSIGNATIO_CU="$SRC/cu/engine/runtime/obsignatio"
[ -f "$TOWER/exponential_integral.h" ] || { echo "  build failed: no exponential_integral.h under $TOWER"; exit 1; }

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/axis_heat.exe"
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
        BINARY="$OUT/axis_heat"
        EXTENSION=o
        HOST_FLAGS=(-Xcompiler -fPIC)
        ;;
esac

# SIM_EXACT_LIMBS sets the exact integer's width in 32-bit limbs, a power of two, for every object linked
WIDTH=()
if [ -n "${SIM_EXACT_LIMBS:-}" ]; then
    WIDTH=(-DANCHOR_EXACT_LIMBS="${SIM_EXACT_LIMBS}u")
fi
INCLUDES=(-I "$SRC/c/engine" -I "$SIMS_CU" -I "$TOWER" -I "$SCRIPTURA" -I "$NO_ROUNDING" -I "$CFG_JSON"
          -I "$DAEMON_DIRECTORY" -I "$OBSIGNATIO" -I "$OBSIGNATIO_CU")

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
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING"/exact_integer_{add,limbs,multiply,divide,gcd,decimal,hash}.c \
              "$CFG_JSON/cfg_json.c"; do
    object="$OUT/$(basename "$source" .c).$EXTENSION"
    build_object "$source" "$object"
    OBJECTS+=("$object")
done
# sim_close releases a tessera job, and axis_heat submits none: the client is linked and never asked
for name in tessera_client_{socket,jobs} tessera_paths tessera_frame tessera_self; do
    object="$OUT/$name.$EXTENSION"
    build_object "$DAEMON_DIRECTORY/$name.c" "$object"
    OBJECTS+=("$object")
done
for name in obsignatio_{hash,seal}; do
    object="$OUT/$name.$EXTENSION"
    rm -f "$object"
    nvcc "${HOST_FLAGS[@]}" -O2 "${WIDTH[@]}" "${INCLUDES[@]}" -c "$OBSIGNATIO_CU/$name.cu" -o "$object"
    [ -f "$object" ] || { echo "  build failed: $name.cu did not compile"; exit 1; }
    OBJECTS+=("$object")
done

rm -f "$BINARY"
nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${WIDTH[@]}" "${INCLUDES[@]}" -o "$BINARY" \
    "$ROOT/src/axis_heat/axis_heat.cu" "$TOWER/exponential_integral_series.cu" "$SIMS_CU/sim_job.cu" "${OBJECTS[@]}"
[ -f "$BINARY" ] || { echo "  build failed: nvcc could not build axis_heat"; exit 1; }

"$BINARY" "$CFG"
STATUS=$?
echo "  axis_heat exit $STATUS"
exit "$STATUS"
