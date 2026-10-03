#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Builds cubin_safe_check and holds cubin_safe to one case a rule against the part's machine file, then reads every
# cubin named on the host. Nothing goes to a device.
#
#     utils/test/src/c/transpiler/cubin/cubin_safe_check.sh [<cubin>...]
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$HERE/../../../../../.." && pwd)"
CUB="$TOP/src/c/transpiler/cubin"
KRS="$TOP/src/c/types/file_defs/krs"
OUT="$TOP/build/cubin_safe"
mkdir -p "$OUT"

cc -std=c11 -O2 -Wall -Wextra -o "$OUT/cubin_safe_check" "$HERE/cubin_safe_check.c" "$CUB/cubin_safe.c" \
    "$CUB/cubin_write.c" "$CUB/sass_assemble.c" "$KRS/sass_machine.c" || exit 1
"$OUT/cubin_safe_check" "$CUB/machines/sm_86" "$@"
STATUS=$?
echo "  cubin safe check exit $STATUS"
exit "$STATUS"
