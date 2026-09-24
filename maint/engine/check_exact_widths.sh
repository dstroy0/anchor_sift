#!/usr/bin/env bash
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Grade the exact integer at every width a build may select, 1 limb to 32768, which is 32 bits to
# 1048576 bits.
#
#   bash maint/engine/check_exact_widths.sh [--from N] [--to N] [--gpu]
#
#   --from N   narrowest limb count to grade (default 1)
#   --to N     widest limb count to grade (default 32768)
#   --gpu      also build and grade the CUDA arm at each width, through build_gpu_arm.sh
#
# Needs cmake, a C11 compiler and python on PATH. --gpu also needs what build_gpu_arm.sh needs:
# nvcc and an MSVC host compiler on Windows. No network and no submodule.
#
# At each power of two limb count this configures its own build tree under build/exact_widths/,
# builds bench_exact, bench_exact_arms and test_steer at that width, and runs three graders:
#
#   rows    bench_exact's limb results checked against python integers by check_exact_limbs.py
#   arms    every host arm graded against portable by bench_exact_arms
#   steer   test_steer, the engine's consumer of the exact integer
#
# The engine itself needs 8 limbs. Its dispatch rule reaches 143 bits on a 64 bit census, and
# src/engine/nbody/anchor_sift/anchor_sift.c refuses a narrower width at compile time. Below 8 limbs the steer
# column reads "-", since there is no engine at that width to grade. The exact integer is graded at
# every width regardless.
#
# The digit floor passed at each width is the largest the width holds, capped at the 1024 the
# header declares. A width below 4096 bits cannot hold 1024 digits, and exact_integer.h refuses it
# unless the build names a floor it does hold. The largest floor d satisfies d * 3322 < 1000 * bits,
# the same test the header's assert makes.
#
# The run shrinks as the width grows, and every width costs about the same. At 32768 limbs one
# position is 128 KiB, and the 4096 positions used at 128 limbs would be 512 MiB.
#
# One line per width, and a nonzero exit naming every width where any grader failed. A width that
# did not build counts as a failure. A binary that never ran reports zero disagreements, and that
# zero grades nothing.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/exact_widths"

from=1
to=32768
gpu=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --from)
            [ "$#" -ge 2 ] || { echo "  --from needs a value"; exit 1; }
            from="$2"
            shift 2
            ;;
        --to)
            [ "$#" -ge 2 ] || { echo "  --to needs a value"; exit 1; }
            to="$2"
            shift 2
            ;;
        --gpu)
            gpu=1
            shift
            ;;
        *)
            echo "  unknown argument: $1"
            exit 1
            ;;
    esac
done

for tool in cmake python; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "  $tool is not on PATH"
        exit 1
    fi
done

generator=""
if command -v ninja >/dev/null 2>&1; then
    generator="-G Ninja"
fi
compiler="-DCMAKE_C_COMPILER=${CC:-gcc}"

mkdir -p "$OUT"
failed=""

printf "  %-7s %-9s %-7s %-10s %-6s %-6s %s\n" "limbs" "bits" "digits" "positions" "rows" "arms" \
    "steer$( [ "$gpu" -eq 1 ] && echo '  gpu')"

limbs=1
while [ "$limbs" -le "$to" ]; do
    if [ "$limbs" -lt "$from" ]; then
        limbs=$((limbs * 2))
        continue
    fi

    bits=$((limbs * 32))
    digits=$(( (1000 * bits - 1) / 3322 ))
    if [ "$digits" -gt 1024 ]; then
        digits=1024
    fi
    positions=$(( 524288 / limbs ))
    if [ "$positions" -gt 4096 ]; then
        positions=4096
    fi
    if [ "$positions" -lt 64 ]; then
        positions=64
    fi

    tree="$OUT/$limbs"
    log="$tree.log"
    rows_file="$tree.rows"
    rows="fail"
    arms="fail"
    steer="fail"
    device="-"
    targets="bench_exact bench_exact_arms"
    if [ "$limbs" -ge 8 ]; then
        targets="$targets test_steer"
    else
        steer="-"
    fi

    # Unquoted. An empty generator has to expand to no argument at all, and quoted it would pass an
    # empty one. The target list expands to one argument per target.
    # shellcheck disable=SC2086
    if cmake -S "$ROOT/src/engine" -B "$tree" $generator $compiler -DCMAKE_BUILD_TYPE=Release \
           -DANCHOR_SKIP_CUDA=ON -DANCHOR_EXACT_LIMBS="$limbs" -DANCHOR_EXACT_DIGITS="$digits" \
           > "$log" 2>&1 \
       && cmake --build "$tree" --target $targets >> "$log" 2>&1; then

        bin="$tree"
        [ -d "$tree/Release" ] && bin="$tree/Release"

        # The checker reads the width from the rows' first line. Its contract check compares the
        # header's defaults against python, and a build setting its own width leaves those defaults
        # unchanged. The check holds at every width and still fails if either side's default drifts.
        if "$bin/bench_exact" > "$rows_file" 2>> "$log" \
           && python "$ROOT/maint/engine/check_exact_limbs.py" "$rows_file" >> "$log" 2>&1; then
            rows="ok"
        fi

        if "$bin/bench_exact_arms" "$positions" >> "$log" 2>&1; then
            arms="ok"
        fi

        if [ "$steer" != "-" ] && (cd "$bin" && ./test_steer >> "$log" 2>&1); then
            steer="ok"
        fi
    else
        echo "  $limbs limbs did not build, see $log"
    fi

    if [ "$gpu" -eq 1 ]; then
        device="fail"
        if bash "$ROOT/maint/engine/build_gpu_arm.sh" --limbs "$limbs" --digits "$digits" \
               --positions "$positions" > "$tree.gpu.log" 2>&1; then
            device="ok"
        fi
    fi

    printf "  %-7s %-9s %-7s %-10s %-6s %-6s %-6s %s\n" "$limbs" "$bits" "$digits" "$positions" \
        "$rows" "$arms" "$steer" "$( [ "$gpu" -eq 1 ] && echo "$device")"

    # A dash is a grader with nothing to grade at this width and never a failure. Every other value
    # than ok is.
    if [ "$rows" != "ok" ] || [ "$arms" != "ok" ] || { [ "$steer" != "ok" ] && [ "$steer" != "-" ]; } \
       || { [ "$gpu" -eq 1 ] && [ "$device" != "ok" ]; }; then
        failed="$failed $limbs"
    fi

    limbs=$((limbs * 2))
done

if [ -n "$failed" ]; then
    echo ""
    echo "  failed at limbs:$failed (logs in $OUT)"
    exit 1
fi
echo ""
echo "  every width graded clean"
