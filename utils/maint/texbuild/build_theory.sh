#!/usr/bin/env sh
# Build every theory research paper under theory/ with XeLaTeX, into build/theory/<research_paper>/.
#
#   Usage:  sh utils/maint/texbuild/build_theory.sh [<research_paper> ...]
#
# Two passes, because the table of contents is written on the first and read on the second. The
# engine is xelatex and not pdflatex: these research papers quote Salishan orthography, IPA and Greek, and
# pdflatex stops with a fatal error on the first Greek letter it meets. It is xelatex and not
# lualatex because arXiv runs xelatex and does not run lualatex, and a local build on a different
# engine from the archive's proves nothing about the archive's.
#
# Every output lands under build/. Nothing is written beside the source.
#
# A missing glyph is reported by the engine as "Missing character" and is otherwise silent: the
# letter is dropped from the PDF and the run still succeeds. This script counts them and fails when
# any research paper drops one, because a research paper about a language that drops a letter of it is wrong.

set -e

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
MIKTEX="/c/Users/Douglas/AppData/Local/Programs/MiKTeX/miktex/bin/x64"
if [ -d "$MIKTEX" ]; then
    PATH="$MIKTEX:$PATH"
    export PATH
fi

# Every directory under theory/ holding a main.tex. A new research paper builds by being created. The four
# names were listed here once, and a research paper added after that line was written would not have built.
if [ $# -gt 0 ]; then
    RESEARCH_PAPERS=$*
else
    # Two depths, because a research paper sits on a shelf and may sit under a subject directory too:
    # theory/<shelf>/<research_paper>/ as most do, and theory/theory/<subject>/<research_paper>/ as the cryptography
    # one does. The shelves are theory/, workbooks/ and thought_experiments/. The path below
    # theory/ is kept, and not the basename, since the loop below joins that back onto
    # $ROOT.
    RESEARCH_PAPERS=$(for one in "$ROOT"/theory/*/*/main.tex "$ROOT"/theory/*/*/*/main.tex; do
        [ -f "$one" ] || continue
        one_dir=$(dirname "$one")
        echo "${one_dir#"$ROOT"/theory/}"
    done)
fi
STATUS=0

for research_paper in $RESEARCH_PAPERS; do
    src="$ROOT/theory/$research_paper"
    out="$ROOT/build/theory/$research_paper"
    if [ ! -f "$src/main.tex" ]; then
        echo "  no such research paper: $research_paper"
        STATUS=1
        continue
    fi
    # \include writes each chapter's .aux under the output directory at the chapter's own path,
    # and xelatex does not make the directory.
    mkdir -p "$out/chapters" "$out/frontmatter"
    cd "$src"
    for pass in 1 2; do
        if ! xelatex -interaction=nonstopmode -file-line-error \
                -output-directory="$out" main.tex > "$out/pass$pass.log" 2>&1; then
            echo "  $research_paper: xelatex failed on pass $pass, see $out/pass$pass.log"
            grep -m 5 -E "^[^ ]+\.tex:[0-9]+:" "$out/main.log" 2>/dev/null || true
            STATUS=1
        fi
    done

    if [ ! -f "$out/main.pdf" ]; then
        echo "  $research_paper: no PDF produced"
        STATUS=1
        continue
    fi

    # grep -c exits 1 when it counts nothing. The count is taken with the exit ignored. Piping
    # through wc keeps a single number even when the log is absent.
    dropped=$(grep -c "^Missing character" "$out/main.log" 2>/dev/null | head -n 1)
    dropped=${dropped:-0}
    bytes=$(wc -c < "$out/main.pdf")
    printf "  %-20s %8s bytes, %s dropped glyphs\n" "$research_paper" "$bytes" "$dropped"
    if [ "$dropped" != "0" ]; then
        grep "^Missing character" "$out/main.log" | sed "s/^/      /" | sort -u | head -n 12
        STATUS=1
    fi
done

exit $STATUS
