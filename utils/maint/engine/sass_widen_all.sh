#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Every form of the machine file turned over a bit at a time, and every operation that comes back. This is what
# sass_machine_widen adds to the machine file, asked here with nothing but nvdisasm, so the answer is in hand without
# a device
#
#     utils/maint/engine/sass_widen_all.sh [architecture]
set -u

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ARCH="${1:-SM86}"
MACHINE="$TOP/src/engine/compiler/cubin/machines/sm_86"
OUT="$TOP/build/sass_widen_all"
mkdir -p "$OUT"

awk 'NR > 1 && $1 == "form" { print $2, $4, $5 }' "$MACHINE" | sort -u >"$OUT/forms.txt"
: >"$OUT/found.txt"

while read -r operation low high; do
    bash "$TOP/utils/maint/engine/sass_widen_ask.sh" "$low" "$high" "$ARCH" >"$OUT/one.txt" 2>&1 || {
        echo "  $operation: the disassembler failed"
        continue
    }
    sed -n 's/^  \([A-Z][A-Z0-9_.]*\) *bits.*/\1/p' "$OUT/one.txt" >>"$OUT/found.txt"
done <"$OUT/forms.txt"

sort -u "$OUT/found.txt" | grep -v '^NOP$' >"$OUT/widened.txt"
awk 'NR > 1 && $1 == "form" { print $2 }' "$MACHINE" | sort -u >"$OUT/listed.txt"

echo "forms the machine file holds: $(wc -l <"$OUT/listed.txt")"
echo "operations one bit from them: $(wc -l <"$OUT/widened.txt")"
echo
echo "operations widening adds that the machine file does not hold:"
comm -23 "$OUT/widened.txt" "$OUT/listed.txt" | sed 's/^/  /'
