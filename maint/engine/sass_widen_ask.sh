#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# One form of the machine file turned over a bit at a time and decoded, printed as the operation each turned bit
# gives. This is sass_machine_widen asked by hand, with nothing but nvdisasm: it says whether the spellings sass.krs
# writes by analogy are reachable from an encoding the part really ran
#
#     maint/engine/sass_widen_ask.sh <low> <high> [architecture]
#     maint/engine/sass_widen_ask.sh 0x000000070600720c 0x000fe40003f06070
set -u

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOW="$1"
HIGH="$2"
ARCH="${3:-SM86}"

if ! command -v nvdisasm >/dev/null 2>&1; then
    TOOLKIT="$(ls -d "/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v"*/bin 2>/dev/null | tail -1)"
    [ -n "$TOOLKIT" ] || {
        echo "nvdisasm is not on PATH and no toolkit was found."
        exit 1
    }
    PATH="$TOOLKIT:$PATH"
fi

OUT="$TOP/build/sass_widen_ask"
mkdir -p "$OUT"
BINARY="$OUT/turned.bin"

python "$TOP/maint/engine/sass_turn_bits.py" "$LOW" "$HIGH" "$BINARY" || exit 1

# the disassembler refuses the whole batch where any one encoding is illegal, and names each it refused by its
# address: those are dropped and the rest asked again, as sass_decode does
if ! nvdisasm --binary "$ARCH" "$BINARY" >"$OUT/turned.out" 2>&1; then
    REFUSED="$(sed -n 's/.*at address 0x\([0-9a-f]*\).*/\1/p' "$OUT/turned.out" | sort -u | tr '\n' ',')"
    [ -n "$REFUSED" ] || {
        echo "nvdisasm exited naming no encoding it refused:"
        head -5 "$OUT/turned.out"
        exit 1
    }
    echo "the part refuses $(echo "$REFUSED" | tr ',' '\n' | grep -c .) of the 129 encodings; asking for the rest"
    echo
    python "$TOP/maint/engine/sass_turn_bits.py" "$LOW" "$HIGH" "$BINARY" --without "$REFUSED" || exit 1
    nvdisasm --binary "$ARCH" "$BINARY" >"$OUT/turned.out" 2>&1 || {
        echo "nvdisasm refused the batch again:"
        head -5 "$OUT/turned.out"
        exit 1
    }
fi

echo "the encoding given decodes as:"
grep -m1 -o '/\*0000\*/.*;' "$OUT/turned.out" | sed 's|/\*0000\*/||' | sed 's/^/  /'
echo
echo "the operations its turned bits give, each with the bits that give it:"
sed -n 's|^\s*/\*\([0-9a-f]*\)\*/\s*\(@!\?P[0-9T]* \)\?\([A-Z][A-Z0-9_.]*\).*|\1 \3|p' "$OUT/turned.out" |
    awk '{ bit = (strtonum("0x" $1) / 16) - 1; if (bit >= 0) { where[$2] = where[$2] " " bit } }
         END { for (operation in where) { printf "  %-28s bits%s\n", operation, where[operation] } }' |
    sort
