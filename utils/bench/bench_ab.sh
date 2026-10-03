#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds bench_ab against orior and the tree's SHA-256, and runs it. With no files it reads every arm over the
# built in corpora; given files, it reads each one's spacing, units and salience instead.
#
#     utils/bench/bench_ab.sh [file...]
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$HERE/../.." && pwd)"
SIFT="$TOP/src/c/engine/nbody/orior"
EXACT="$TOP/src/c/types/integers"
OUT="$TOP/build/bench"
mkdir -p "$OUT"

cc -std=c11 -O2 -Wall -Wextra -I "$SIFT" -I "$EXACT" -o "$OUT/bench_ab" "$HERE/bench_ab.c" \
    "$TOP/src/c/includes/codecs/sha256/sha256.c" "$SIFT/orior_core.c" "$SIFT/orior_field.c" "$SIFT/orior_steer.c" \
    "$SIFT/orior_steer_count.c" "$SIFT/orior_steer_plan.c" "$SIFT/scan.c" "$EXACT/exact_integer_add.c" \
    "$EXACT/exact_integer_multiply.c" "$EXACT/exact_integer_limbs.c" -lm || exit 1
"$OUT/bench_ab" "$@"
