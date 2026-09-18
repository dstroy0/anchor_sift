#!/usr/bin/env bash
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Compile every vectorized arm for its target and read the instructions the assembler emitted.
#
#   bash maint/engine/verify_arm_asm.sh
#
# WHAT THIS GRADE IS AND WHAT IT IS NOT
#
# Two of these arms have hardware here and are run against the portable arm on real data. AVX-512
# and SVE have no hardware here. The strongest available check: build for the
# target, disassemble, and confirm the instructions the arm was written to use are the instructions
# that came out.
#
# That is a real result and not a guess. It rules out a header that silently fell back to scalar
# code, an intrinsic the compiler emulated instead of issuing, and a flag that was accepted and
# ignored. What it does not touch is behavior: no value is computed, nothing is compared against the
# portable arm, and a logic error inside the vector loop would pass this check untouched.
#
# So a row here reads "emits" and never "agrees". Only a run against portable earns "agrees", and
# the two words are kept apart on purpose.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/build/arm_asm"
mkdir -p "$WORK"

PASS=0
FAIL=0

# One row: compile a source for a target and require every named instruction in the output.
#
#   check <label> <compiler> <flags> <source> <objdump> <instruction>...
check() {
    local label="$1"; shift
    local compiler="$1"; shift
    local flags="$1"; shift
    local source="$1"; shift
    local dumper="$1"; shift

    printf "  %-22s " "$label"

    if ! command -v "$compiler" >/dev/null 2>&1; then
        echo "SKIPPED, no $compiler"
        return
    fi

    local object="$WORK/${label//[^A-Za-z0-9_]/_}.o"
    if ! $compiler $flags -c "$source" -o "$object" 2>"$WORK/${label//[^A-Za-z0-9_]/_}.log"; then
        echo "FAILED to compile"
        sed 's/^/      /' "$WORK/${label//[^A-Za-z0-9_]/_}.log" | head -6
        FAIL=$((FAIL + 1))
        return
    fi

    local text
    text="$($dumper -d "$object" 2>/dev/null)"
    local missing=""
    for want in "$@"; do
        if ! printf '%s' "$text" | grep -qi -- "$want"; then
            missing="$missing $want"
        fi
    done

    if [ -n "$missing" ]; then
        echo "COMPILED but did not emit:$missing"
        FAIL=$((FAIL + 1))
    else
        echo "emits $*"
        PASS=$((PASS + 1))
    fi
}

echo
echo "  Instruction selection, read off the object file. This grades emission, never behavior."
echo

ARMS="$ROOT/src/engine/c/no_rounding"

# The two arms that also have hardware here. Checked the same way so the grade is comparable, and
# separately run against portable by bench_exact_arms.
check "avx2 x86-64" gcc \
    "-O2 -mavx2 -I$ARMS -DANCHOR_EXACT_HAVE_AVX2=1" \
    "$ARMS/arm_avx2.c" objdump \
    vpcmpeqd ymm

# AVX-512: no hardware here. Emission is the whole of the grade.
check "avx512 xeon" gcc \
    "-O2 -mavx512f -mavx512bw -mavx512vl -I$ARMS -DANCHOR_EXACT_HAVE_AVX512=1" \
    "$ARMS/arm_avx512.c" objdump \
    vpcmpeqd zmm

# NEON on aarch64, cross compiled. The Pi runs this arm natively and it is separately run there.
check "neon aarch64" aarch64-linux-gnu-gcc \
    "-O2 -I$ARMS -DANCHOR_EXACT_HAVE_NEON=1" \
    "$ARMS/arm_neon.c" aarch64-linux-gnu-objdump \
    cmeq uminv

# SVE: no hardware here. Emission is the whole of the grade.
#
# whilelo and not whilelt. svwhilelt_b32 takes unsigned operands here, and the unsigned form of the
# while instruction is WHILELO, lower-than; WHILELT is the signed one. This row asked for whilelt
# first and reported the arm as not emitting it, which was correct: the arm emits whilelo. The check
# caught a wrong expectation and not wrong code, which is the case it is least likely to be
# trusted on and the one worth writing down.
check "sve neoverse" aarch64-linux-gnu-gcc \
    "-O2 -march=armv8.2-a+sve -I$ARMS -DANCHOR_EXACT_HAVE_SVE=1" \
    "$ARMS/arm_sve.c" aarch64-linux-gnu-objdump \
    whilelo cmpne ptest ld1w

echo
echo "  The steering scan arms, engine/. Same grade and the same two words: emits, never agrees."
echo

ENGINE="$ROOT/src/engine/c/engine"
# A scan arm includes anchor_sift.h, which includes exact_integer.h. Both directories are on the
# include path even though a scan arm reads no exact arithmetic.
SCAN_INC="-I$ENGINE -I$ARMS"

# AVX2 and NEON have hardware here and are run against portable by bench_steer_arms. Graded for
# emission too. The row is comparable with the arms that have no hardware.
check "scan avx2 x86-64" gcc \
    "-O2 -mavx2 $SCAN_INC -DANCHOR_STEER_HAVE_AVX2=1" \
    "$ENGINE/scan_avx2.c" objdump \
    vpcmpeqb ymm

# AVX-512: emission is the whole of the grade. The byte compare writes a mask register. The
# instruction is vpcmpeqb against a zmm operand.
check "scan avx512 xeon" gcc \
    "-O2 -mavx512f -mavx512bw $SCAN_INC -DANCHOR_STEER_HAVE_AVX512=1" \
    "$ENGINE/scan_avx512.c" objdump \
    vpcmpeqb zmm

check "scan neon aarch64" aarch64-linux-gnu-gcc \
    "-O2 $SCAN_INC -DANCHOR_STEER_HAVE_NEON=1" \
    "$ENGINE/scan_neon.c" aarch64-linux-gnu-objdump \
    cmeq addv

# SVE: emission is the whole of the grade. whilelo for the unsigned predicate, cmpeq for the byte
# compare, cntp for the population count that replaces a movemask, ld1b for the predicated load.
check "scan sve neoverse" aarch64-linux-gnu-gcc \
    "-O2 -march=armv8.2-a+sve $SCAN_INC -DANCHOR_STEER_HAVE_SVE=1" \
    "$ENGINE/scan_sve.c" aarch64-linux-gnu-objdump \
    whilelo cmpeq cntp ld1b

echo
echo "  $PASS emitted as written, $FAIL did not"
echo
[ "$FAIL" -eq 0 ]
