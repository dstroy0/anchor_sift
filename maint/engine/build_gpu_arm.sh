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
# gets its own build and does not join the CMake one. Everything it needs is compiled here by the
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

# Removed before the build, so a previous binary cannot survive a failed compile and be run as
# though it were this one. This script did exactly that for a week: nvcc failed on a header, a
# binary from Sep 9 was still sitting here, the file existence test below passed, and the bench ran
# the stale one and reported a device engine that "agreed" with the portable engine at 1.01x. It
# agreed because it WAS the portable engine, carrying no CUDA at all, and the ratio wandering
# between 1.01x and 1.14x across runs was two runs of identical code.
rm -f "$OUT/bench_exact_gpu.exe"

# PIPESTATUS and not $?, because the pipe into grep would otherwise report grep's status and grep
# succeeds whatever nvcc did. A filter on the output must never decide whether the build passed.
nvcc -ccbin "$MSVC_BIN" -O2 $GENCODE \
    -I "$ROOT/src/engine/c/no_rounding" \
    -DANCHOR_EXACT_HAVE_CUDA=1 \
    -o "$OUT/bench_exact_gpu.exe" \
    "$ROOT/src/engine/c/no_rounding/arm_cuda.cu" \
    "$ROOT/src/engine/c/no_rounding/exact_integer.c" \
    "$ROOT/src/engine/c/no_rounding/arm_portable.c" \
    "$ROOT/src/engine/c/bench/bench_exact_arms.c" \
    2>&1 | grep -viE "^\s*$|Copyright|Microsoft \(R\)|exact_integer\.c$|arm_portable\.c$|bench_exact_arms\.c$|arm_cuda\.cu$" | head -20
NVCC_STATUS=${PIPESTATUS[0]}

# Both conditions, because each one alone has been wrong here. A status of zero with no file is a
# linker that wrote nothing; a file with a nonzero status is the stale binary this script used to
# run. Neither is a build.
if [ "$NVCC_STATUS" -ne 0 ] || [ ! -f "$OUT/bench_exact_gpu.exe" ]; then
    echo "  build failed: nvcc exited $NVCC_STATUS"
    exit 1
fi

echo "  built $OUT/bench_exact_gpu.exe"
"$OUT/bench_exact_gpu.exe"
