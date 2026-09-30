#!/usr/bin/env bash
# Build one research paper at a base commit and in the working tree, and report what the change did to the build.
#
#   sh tools/research_paper/compare_research_paper.sh <research paper directory> <base commit> <output directory>
#   sh tools/research_paper/compare_research_paper.sh PUBLIC/delta_null 5ce1632 /tmp/delta_null_compare
#
# Needs latexmk and lualatex on PATH. Nothing is written beside the source: both builds go under the output
# directory, which must not already exist. A stale log from an earlier run is then never read as this one.
#
# Each build reports its latexmk exit status, its page count, and three counts read from its log: missing
# characters, overfull boxes and undefined references. A missing character is a glyph the page silently
# dropped, which on a research paper setting Salishan orthography is a wrong page with no error.
#
# IT FAILS CLOSED. Exit 1 when either build fails or the working tree build has more missing characters,
# overfull boxes or undefined references than the base. Exit 2 on a usage error. Exit 0 otherwise.
set -u

if [ $# -ne 3 ]; then
    sed -n '2,5p' "$0"
    exit 2
fi
RESEARCH_PAPER=$1
BASE=$2
OUT=$3

REPO=$(git rev-parse --show-toplevel) || { echo "compare_research_paper: not inside a git checkout"; exit 2; }
[ -f "$REPO/$RESEARCH_PAPER/main.tex" ] || { echo "compare_research_paper: no main.tex at $REPO/$RESEARCH_PAPER"; exit 2; }
git -C "$REPO" rev-parse --verify --quiet "$BASE^{commit}" > /dev/null || { echo "compare_research_paper: $BASE is not a commit"; exit 2; }
[ ! -e "$OUT" ] || { echo "compare_research_paper: $OUT already exists; name a new directory"; exit 2; }
command -v latexmk > /dev/null || { echo "compare_research_paper: latexmk is not on PATH"; exit 2; }

mkdir -p "$OUT/base_src" "$OUT/base" "$OUT/tree" || exit 2
git -C "$REPO" archive "$BASE" "$RESEARCH_PAPER" | tar -x -C "$OUT/base_src" || { echo "compare_research_paper: export of $BASE failed"; exit 2; }
echo "repository: $REPO"
echo "research paper:       $RESEARCH_PAPER, base $BASE against the working tree"
echo "output:     $OUT"

measure() {
    label=$1 src=$2 dest=$3
    ( cd "$src" && latexmk -lualatex -interaction=nonstopmode -halt-on-error -output-directory="$dest" main.tex \
        > "$dest/latexmk_stdout.txt" 2>&1 )
    status=$?
    log=$dest/main.log
    pages=$(grep -o -E 'Output written on [^ ]+ \([0-9]+ pages' "$log" 2>/dev/null | tail -1 | grep -o -E '[0-9]+ pages')
    missing=$(grep -c -E 'Missing character' "$log" 2>/dev/null)
    overfull=$(grep -c -E 'Overfull \\[hv]box' "$log" 2>/dev/null)
    undefined=$(grep -c -E 'undefined|Undefined' "$log" 2>/dev/null)
    echo "$label: latexmk exit $status, ${pages:-no pages}, missing characters ${missing:-?}, overfull ${overfull:-?}, undefined ${undefined:-?}"
    eval "${label}_status=$status ${label}_missing=${missing:-999999} ${label}_overfull=${overfull:-999999} ${label}_undefined=${undefined:-999999}"
}

measure base "$OUT/base_src/$RESEARCH_PAPER" "$OUT/base"
measure tree "$REPO/$RESEARCH_PAPER" "$OUT/tree"

if [ "$base_status" -ne 0 ] || [ "$tree_status" -ne 0 ]; then
    echo "compare_research_paper: a build failed"
    exit 1
fi
if [ "$tree_missing" -gt "$base_missing" ] || [ "$tree_overfull" -gt "$base_overfull" ] \
    || [ "$tree_undefined" -gt "$base_undefined" ]; then
    echo "compare_research_paper: the working tree build is worse than the base"
    exit 1
fi
echo "compare_research_paper: no regression"
exit 0
