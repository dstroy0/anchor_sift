#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$HERE/../.." && pwd)"
ENGINE="$TOP/src/engine/base/no_rounding"
source "$TOP/maint/build_stamp.sh"
build_stamp cell_shift
rm -f "$OUT/cell_shift.exe"

if [ ! -d "$ENGINE" ]; then
    echo "  the engine's exact integer not found at $ENGINE"
    exit 1
fi

MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
CAP="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' .')"
ARCH="${1:-sm_${CAP:-86}}"

if command -v nvcc >/dev/null 2>&1 && [ -n "$MSVC_BIN" ] && [ -n "$CAP" ]; then
    echo "  device engine, $ARCH"
    nvcc -ccbin "$MSVC_BIN" -O2 -gencode "arch=compute_${ARCH#sm_},code=${ARCH}" \
        -I "$ENGINE" \
        -DANCHOR_EXACT_HAVE_CUDA=1 \
        -o "$OUT/cell_shift.exe" \
        "$HERE/src/cell_shift.c" \
        "$ENGINE/arm_cuda.cu" \
        "$ENGINE/exact_integer.c" \
        "$ENGINE/arm_portable.c"
    STATUS=$?
else
    echo "  portable engine only: no nvcc, no host compiler, or no device"
    cc -O2 -std=c11 -I "$ENGINE" \
        -o "$OUT/cell_shift.exe" \
        "$HERE/src/cell_shift.c" \
        "$ENGINE/exact_integer.c" \
        "$ENGINE/arm_portable.c"
    STATUS=$?
fi

if [ $STATUS -ne 0 ] || [ ! -f "$OUT/cell_shift.exe" ]; then
    echo "  build failed with status $STATUS"
    exit 1
fi
echo "  built $OUT/cell_shift.exe"
build_publish "$OUT/cell_shift.exe" || exit 1
