#!/usr/bin/env bash
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Compile the CUDA arm for every architecture worth carrying and read the SASS that came out.
#
#   bash maint/engine/verify_gpu_arch.sh
#
# WHAT THIS GRADE IS AND WHAT IT IS NOT
#
# One device is present here, an RTX 3070 at compute 8.6, and the arm is run against the portable
# arm on it. Every other architecture below has no hardware here, so the check is the one available:
# compile for that target, then disassemble the cubin and confirm real SASS for that architecture
# came out rather than an empty section or a PTX-only stub that would be JIT compiled later.
#
# That rules out a target the toolkit accepted and did not generate for, an intrinsic unavailable on
# that architecture, and a silent fallback to a lower compute capability. It says nothing about
# behavior, since nothing is run.
#
# Rows read "builds" and never "agrees". Only the run on the 3070 earns "agrees", and Ampere is the
# only line in this file that has it.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/build/gpu_arch"
mkdir -p "$WORK"

MSVC_BIN="$(ls -d "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/VC/Tools/MSVC"/*/bin/Hostx64/x64 2>/dev/null | tail -1)"
if [ -z "$MSVC_BIN" ]; then
    echo "  no MSVC host compiler found. nvcc cannot build on Windows without one."
    exit 1
fi

# Architecture, and the part it is there for. Ampere is the one with hardware here.
ARCHES="
sm_75:Turing_T4
sm_80:Ampere_A100_HBM2e
sm_86:Ampere_RTX3070_present
sm_89:Ada_L40S
sm_90:Hopper_H100_HBM3
sm_100:Blackwell_B100_B200_HBM3e
sm_103:Blackwell_B300
sm_110:Blackwell_next
sm_120:Blackwell_RTX50
sm_121:Blackwell_RTX50_refresh
"

PASS=0
FAIL=0

echo
echo "  CUDA arm across architectures. This grades that real SASS was generated, never behavior."
echo
printf "  %-8s %-30s %s\n" "arch" "part" "verdict"

for row in $ARCHES; do
    arch="${row%%:*}"
    part="${row##*:}"
    num="${arch#sm_}"
    cubin="$WORK/$arch.cubin"

    printf "  %-8s %-30s " "$arch" "$part"

    if ! nvcc -ccbin "$MSVC_BIN" -O2 -cubin \
        -gencode "arch=compute_${num},code=${arch}" \
        -I "$ROOT/src/engine/c/portable" -I "$ROOT/src/engine/gpu" \
        -DANCHOR_EXACT_HAVE_CUDA=1 \
        -o "$cubin" "$ROOT/src/engine/gpu/exact_agreement.cu" >"$WORK/$arch.log" 2>&1; then
        echo "FAILED to compile"
        grep -iE "error" "$WORK/$arch.log" | head -3 | sed 's/^/      /'
        FAIL=$((FAIL + 1))
        continue
    fi

    # A cubin that compiled but holds no instructions for the kernel would pass a build check and
    # fail on the part. cuobjdump reads the generated SASS back out, which is the thing being
    # claimed.
    lines="$(cuobjdump -sass "$cubin" 2>/dev/null | grep -c "agreement_kernel")"
    total="$(cuobjdump -sass "$cubin" 2>/dev/null | grep -cE "^\s+/\*[0-9a-f]+\*/")"
    if [ "${lines:-0}" -eq 0 ] || [ "${total:-0}" -lt 32 ]; then
        echo "built but no kernel SASS"
        FAIL=$((FAIL + 1))
        continue
    fi

    echo "builds, $total SASS instructions"
    PASS=$((PASS + 1))
done

echo
echo "  $PASS generated real SASS, $FAIL did not"
echo "  only sm_86 has hardware here and is separately run against the portable arm"
echo
[ "$FAIL" -eq 0 ]
