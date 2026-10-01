#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The compiler on the device held to the compiler on the host (codegen_test.cu): the layout, each language's
# forms as the lane runs and cut into states, and the text. The test is one job on the device's tessera daemon, built
# beside it.
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../../../../../.." && pwd)"
CYCLE="$TOP/src/c/engine/analysis/cycle"
CYCLE_CU="$TOP/src/cu/engine/analysis/cycle"
CODEGEN="$TOP/src/c/transpiler/codegen"
CODEGEN_CU="$TOP/src/cu/transpiler/codegen"
CODEGEN_CU_2="$TOP/src/cu/types/file_defs/krs"
KEYMATH="$TOP/src/c/engine/analysis/keymath"
KEYMATH_CU="$TOP/src/cu/engine/analysis/keymath"
KEY_SCHEDULE="$TOP/src/c/engine/analysis/key_schedule"
KEY_SCHEDULE_CU="$TOP/src/cu/engine/analysis/key_schedule"
NO_ROUNDING="$TOP/src/c/types/integers"
SCRIPTURA="$TOP/src/c/engine/runtime/scriptura"
source "$TOP/utils/maint/engine/build_stamp.sh"
source "$TOP/utils/maint/engine/tessera_build.sh"
build_stamp codegen_device_test

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/codegen_device_test.exe"
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
        BINARY="$OUT/codegen_device_test"
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

INCLUDES=(-I "$TOP/src/c/engine" -I "$TOP/src/c/includes/codecs/crc" -I "$TOP/src/cu/includes/codecs/crc" -I "$CYCLE" -I "$CYCLE_CU" -I "$CODEGEN" -I "$CODEGEN_CU" -I "$CODEGEN_CU_2" -I "$KEYMATH" -I "$KEYMATH_CU"
          -I "$KEY_SCHEDULE" -I "$KEY_SCHEDULE_CU" -I "$NO_ROUNDING" -I "$SCRIPTURA" "${TESSERA_INCLUDES[@]}")
rm -f "$BINARY"
OBJECTS=()
SCRIPTURA_OBJECTS=()
for source in "$SCRIPTURA"/*.c "$NO_ROUNDING"/exact_integer_{add,limbs,multiply,divide,gcd,decimal,hash}.c \
              "$CYCLE/cycle.c"; do
    object="$OUT/$(basename "$source" .c)_codegen_device.$EXTENSION"
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
# the test is a job on the device's tessera daemon, built beside it
tessera_build codegen_device "${SCRIPTURA_OBJECTS[@]}" || exit 1

nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" "${INCLUDES[@]}" -o "$BINARY" \
    "$TEST/codegen_test.cu" "$TOP/src/sims/cu/sim_job.cu" "$CYCLE_CU"/cycle*.cu "$CODEGEN_CU"/*.cu "$CODEGEN_CU_2"/*.cu \
    "$KEYMATH_CU/keymath.cu" "$KEY_SCHEDULE_CU/key_schedule.cu" "${OBJECTS[@]}" "${TESSERA_OBJECTS[@]}" "${TESSERA_SEAL[@]}"
[ -f "$BINARY" ] || { echo "  build failed: nvcc could not build the test"; exit 1; }

"$BINARY"
STATUS=$?
echo "  codegen device test exit $STATUS"
exit "$STATUS"
