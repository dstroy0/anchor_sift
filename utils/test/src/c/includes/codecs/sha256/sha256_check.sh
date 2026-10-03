#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds sha256_check and holds the tree's SHA-256 (src/c/includes/codecs/sha256) to NIST's published vectors, the
# byte and bit message files and the Monte chain, vendored under utils/test/src/cu/transpiler/qasm/vectors.
#
#     utils/test/src/c/includes/codecs/sha256/sha256_check.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$HERE/../../../../../../.." && pwd)"
VECTORS="$TOP/utils/test/src/cu/transpiler/qasm/vectors"
OUT="$TOP/build/sha256"
mkdir -p "$OUT"

cc -std=c11 -O2 -Wall -Wextra -o "$OUT/sha256_check" "$HERE/sha256_check.c" \
    "$TOP/src/c/includes/codecs/sha256/sha256.c" || exit 1
"$OUT/sha256_check" "$VECTORS/nist_cavp_sha256shortmsg.rsp" "$VECTORS/nist_cavp_sha256longmsg.rsp" \
    "$VECTORS/nist_cavp_bit_sha256shortmsg.rsp" "$VECTORS/nist_cavp_bit_sha256longmsg.rsp" \
    --monte "$VECTORS/nist_cavp_sha256monte.rsp"
