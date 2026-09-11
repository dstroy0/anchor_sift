#!/usr/bin/env sh
# Build every theory book under theory/ with LuaLaTeX, into build/theory/<book>/.
#
#   Usage:  sh maint/texbuild/build_theory.sh [<book> ...]
#
# Two passes, because the table of contents is written on the first and read on the second. The
# engine is lualatex and not pdflatex: these books quote Salishan orthography, IPA and Greek, and
# pdflatex stops with a fatal error on the first Greek letter it meets.
#
# Every output lands under build/. Nothing is written beside the source.
#
# A missing glyph is reported by the engine as "Missing character" and is otherwise silent: the
# letter is dropped from the PDF and the run still succeeds. This script counts them and fails when
# any book drops one, because a book about a language that drops a letter of it is wrong.

set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
MIKTEX="/c/Users/Douglas/AppData/Local/Programs/MiKTeX/miktex/bin/x64"
if [ -d "$MIKTEX" ]; then
    PATH="$MIKTEX:$PATH"
    export PATH
fi

# Every directory under theory/ holding a main.tex. A new book builds by being created. The four
# names were listed here once, and a book added after that line was written would not have built.
if [ $# -gt 0 ]; then
    BOOKS=$*
else
    # Two depths, because a book may sit under a subject directory: theory/<book>/ as most do, and
    # theory/<subject>/<book>/ as the cryptography one does. What is kept is the path below theory/
    # and not the basename, since that is what the loop below joins back onto $ROOT.
    BOOKS=$(for one in "$ROOT"/theory/*/main.tex "$ROOT"/theory/*/*/main.tex; do
        [ -f "$one" ] || continue
        one_dir=$(dirname "$one")
        echo "${one_dir#"$ROOT"/theory/}"
    done)
fi
STATUS=0

for book in $BOOKS; do
    src="$ROOT/theory/$book"
    out="$ROOT/build/theory/$book"
    if [ ! -f "$src/main.tex" ]; then
        echo "  no such book: $book"
        STATUS=1
        continue
    fi
    mkdir -p "$out"
    cd "$src"
    for pass in 1 2; do
        if ! lualatex -interaction=nonstopmode -file-line-error \
                -output-directory="$out" main.tex > "$out/pass$pass.log" 2>&1; then
            echo "  $book: lualatex failed on pass $pass, see $out/pass$pass.log"
            grep -m 5 -E "^[^ ]+\.tex:[0-9]+:" "$out/main.log" 2>/dev/null || true
            STATUS=1
        fi
    done

    if [ ! -f "$out/main.pdf" ]; then
        echo "  $book: no PDF produced"
        STATUS=1
        continue
    fi

    # grep -c exits 1 when it counts nothing, so the count is taken with the exit ignored. Piping
    # through wc keeps a single number even when the log is absent.
    dropped=$(grep -c "^Missing character" "$out/main.log" 2>/dev/null | head -n 1)
    dropped=${dropped:-0}
    bytes=$(wc -c < "$out/main.pdf")
    printf "  %-20s %8s bytes, %s dropped glyphs\n" "$book" "$bytes" "$dropped"
    if [ "$dropped" != "0" ]; then
        grep "^Missing character" "$out/main.log" | sed "s/^/      /" | sort -u | head -n 12
        STATUS=1
    fi
done

exit $STATUS
