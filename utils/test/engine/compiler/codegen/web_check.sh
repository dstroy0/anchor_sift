#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The alphabet web and the word web read once each and held to what a tree is (web_check.c). Both are headers of the
# compiler's own, so this needs no device, no CUDA toolchain and no ruleset
set -u

TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$TEST/../../../../.." && pwd)"
CODEGEN="$TOP/src/engine/compiler/codegen"
source "$TOP/utils/maint/engine/build_stamp.sh"
build_stamp web_check

BINARY="$OUT/web_check"
rm -f "$BINARY"
cc -std=c11 -O2 -Wall -Wextra -I "$CODEGEN" -o "$BINARY" "$TEST/web_check.c"
[ -f "$BINARY" ] || { echo "  build failed: web_check.c did not compile"; exit 1; }

"$BINARY"
STATUS=$?
echo "  web check exit $STATUS"
exit "$STATUS"
