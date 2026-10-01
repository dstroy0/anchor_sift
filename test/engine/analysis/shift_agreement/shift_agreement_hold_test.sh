#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../../../.." && pwd)"
SHIFT="$TOP/src/engine/analysis/shift_agreement"
DEVICE_POOL="$TOP/src/engine/runtime/device_pool"
source "$TOP/maint/engine/build_stamp.sh"
build_stamp shift_agreement_hold_test

HOST_FLAGS=()
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        BINARY="$OUT/shift_agreement_hold_test.exe"
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
        BINARY="$OUT/shift_agreement_hold_test"
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

INCLUDES=(-I "$TOP/src/engine" -I "$SHIFT" -I "$DEVICE_POOL")
rm -f "$BINARY"
# the test is host arithmetic: it links the module's device code but asks nothing of the device, and is no job
nvcc "${HOST_FLAGS[@]}" -std=c++17 -O2 "${GENCODE[@]}" "${INCLUDES[@]}" -o "$BINARY" \
    "$TEST/shift_agreement_hold_test.cu" "$SHIFT"/shift_agreement_{kernels,run}.cu "$DEVICE_POOL/device_pool.cu"
[ -f "$BINARY" ] || { echo "  build failed: nvcc could not build the test"; exit 1; }
if [ "${BUILD_ONLY:-0}" = "1" ]; then
    echo "  built $BINARY"
    exit 0
fi

"$BINARY"
STATUS=$?
echo "  shift_agreement hold test exit $STATUS"
exit "$STATUS"
