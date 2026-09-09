#!/usr/bin/env bash
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Build the CUDA arm and grade it against the portable one.
#
#   bash maint/engine/build_gpu_arm.sh [sm_XX ...]
#
# nvcc needs a host compiler and on Windows that host compiler is MSVC, never MinGW. The rest of
# this tree builds with MinGW, and MinGW objects do not link against MSVC objects, so the GPU arm
# gets its own build rather than joining the CMake one. Everything it needs is compiled here by the
# same host compiler nvcc is driving, which is what keeps the ABI consistent inside this binary.
#
# Architectures default to the one this machine carries. Naming others compiles for them as well,
# which is how an architecture nobody here owns is checked: the code has to compile and the assembler
# has to accept it for that target, and only running it is left unverified.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/engine_gpu"
mkdir -p "$OUT"

MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
if [ -z "$MSVC_BIN" ]; then
    MSVC_BIN="$(ls -d "/c/Program Files/Microsoft Visual Studio"/*/*/VC/Tools/MSVC/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
fi
if [ -z "$MSVC_BIN" ]; then
    echo "  no MSVC host compiler found. nvcc cannot build on Windows without one."
    exit 1
fi
echo "  host compiler: $MSVC_BIN"

ARCHES="${*:-}"
if [ -z "$ARCHES" ]; then
    CAP="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' .')"
    ARCHES="sm_${CAP:-86}"
fi
echo "  architectures: $ARCHES"

GENCODE=""
for one in $ARCHES; do
    NUM="${one#sm_}"
    GENCODE="$GENCODE -gencode arch=compute_${NUM},code=${one}"
done

nvcc -ccbin "$MSVC_BIN" -O2 $GENCODE \
    -I "$ROOT/src/engine/c/portable" \
    -I "$ROOT/src/engine/gpu" \
    -DANCHOR_EXACT_HAVE_CUDA=1 \
    -o "$OUT/bench_exact_gpu.exe" \
    "$ROOT/src/engine/gpu/exact_agreement.cu" \
    "$ROOT/src/engine/c/portable/exact_limbs.c" \
    "$ROOT/src/engine/c/portable/exact_arm_portable.c" \
    "$ROOT/src/engine/c/bench/bench_exact_arms.c" \
    2>&1 | grep -viE "^\s*$|Copyright|Microsoft \(R\)|exact_limbs\.c$|exact_arm_portable\.c$|bench_exact_arms\.c$|exact_agreement\.cu$" | head -20

if [ ! -f "$OUT/bench_exact_gpu.exe" ]; then
    echo "  build failed"
    exit 1
fi

echo "  built $OUT/bench_exact_gpu.exe"
"$OUT/bench_exact_gpu.exe"
