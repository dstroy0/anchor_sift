#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds bench_entropy against the tree's SHA-256 and runs it: each collision entropy estimator's bias and error
# over nine sources and four lengths, then the Renyi ladder to order five.
#
#     utils/bench/bench_entropy.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$HERE/../.." && pwd)"
OUT="$TOP/build/bench"
mkdir -p "$OUT"

cc -std=c11 -O2 -Wall -Wextra -o "$OUT/bench_entropy" "$HERE/bench_entropy.c" \
    "$TOP/src/c/includes/codecs/sha256/sha256.c" -lm || exit 1
"$OUT/bench_entropy"
