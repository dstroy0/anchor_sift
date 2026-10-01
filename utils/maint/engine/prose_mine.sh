#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The prose findings in the files a commit raised above their ceiling, and only those. docs_check
# reads the whole tree and prints every finding in it; this keeps the ones a hand has to fix now
#
#     utils/maint/engine/prose_mine.sh
set -u

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT="$TOP/build/prose_mine"
mkdir -p "$OUT"

python "$TOP/utils/maint/prose/docs_check" --staged --ratchet="$TOP/utils/maint/prose/prose_ratchet.tsv" \
    >"$OUT/all.txt" 2>&1

# each file the run named RISEN, which is a file whose findings a hand just added
sed -n 's/^  RISEN \([^:]*\):.*/\1/p' "$OUT/all.txt" | sort -u >"$OUT/risen.txt"
echo "files raised above their ceiling: $(wc -l <"$OUT/risen.txt")"
: >"$OUT/findings.txt"
while read -r file; do
    grep "^  prose .*/$file:" "$OUT/all.txt" | sed "s|D:/git_project/repos/owned/public/orior/||" \
        >>"$OUT/findings.txt"
done <"$OUT/risen.txt"
echo "findings to fix: $(wc -l <"$OUT/findings.txt")"
echo
cat "$OUT/findings.txt"
