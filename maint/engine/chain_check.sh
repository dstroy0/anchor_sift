#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds and runs the things that work off the ladder's relations and the query protocol's ask, none of which needs
# a device, a toolchain or a machine file:
#
#   kdm_write     writes a part's .kdm: every arrangement of primitives that produces each operator
#   chain_check   reads how much of a relation the ladder's own cases decide
#   gate_descent  runs the gate as anchor_sift's descent and checks it against every arrangement asked every case
#   ask_order_check  holds the known order of asks to its exact claims and measures the contention read
#   query_ask_check  holds the ask to what it answers at addresses whose state is known, and finds a clock
#
#     maint/engine/chain_check.sh
#     maint/engine/chain_check.sh sm_86 src/engine/compiler/cubin/machines/sm_86.kdm
#
# With arguments it writes that part's .kdm to that path; with none it runs every check and stops.
set -u

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$TOP/build/engine"
mkdir -p "$OUT"

for one in "$TOP/maint/engine/kdm_write.c" "$TOP/test/engine/compiler/bootstrap/chain_check.c"; do
    name="$(basename "$one" .c)"
    cc -std=c11 -O2 -Wall -Wextra -o "$OUT/$name" "$one" \
        "$TOP/src/engine/compiler/bootstrap/chain_build.c" || exit 1
done

# the descent is anchor_sift's own, and anchor_sift reads exact integers
SIFT="$TOP/src/engine/nbody/anchor_sift"
EXACT="$TOP/src/engine/arithmetic/no_rounding"
cc -std=c11 -O2 -Wall -Wextra -I"$SIFT" -I"$EXACT" -o "$OUT/gate_descent" \
    "$TOP/test/engine/compiler/bootstrap/gate_descent.c" "$TOP/src/engine/compiler/bootstrap/chain_build.c" \
    "$SIFT/anchor_sift_core.c" "$SIFT/anchor_sift_field.c" "$SIFT/anchor_sift_steer.c" \
    "$SIFT/anchor_sift_steer_count.c" "$SIFT/anchor_sift_steer_plan.c" "$SIFT/scan_portable.c" \
    "$EXACT/exact_integer_add.c" "$EXACT/exact_integer_multiply.c" "$EXACT/exact_integer_limbs.c" || exit 1
cc -std=c11 -O2 -Wall -Wextra -o "$OUT/ask_order_check" "$TOP/test/engine/compiler/bootstrap/ask_order_check.c" \
    "$TOP/src/engine/compiler/bootstrap/ask_order.c" \
    "$EXACT/exact_integer_add.c" "$EXACT/exact_integer_multiply.c" "$EXACT/exact_integer_limbs.c" || exit 1
cc -std=c11 -O2 -Wall -Wextra -o "$OUT/query_ask_check" "$TOP/test/engine/compiler/bootstrap/query_ask_check.c" \
    "$TOP/src/engine/compiler/bootstrap/query_ask.c" || exit 1

cd "$TOP" || exit 1
if [ "$#" -gt 0 ]; then
    "$OUT/kdm_write" "$@"
    exit "$?"
fi
"$OUT/chain_check" || exit 1
"$OUT/gate_descent" || exit 1
"$OUT/ask_order_check" || exit 1
"$OUT/query_ask_check"
