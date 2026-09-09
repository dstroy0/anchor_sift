# Anchor Sift Research Ledger

**Purpose:** Say where the ledger lives and what it holds, for a reader who arrived here looking for it.
**Scope:** `theory/workbook/`, holding the ledger, and `tools/book/build_theory.sh`, which builds it.

The ledger moved into the workbook. It is `theory/workbook/chapters/chapter_anchor_sift_ledger.tex`, and the book around it is `theory/workbook/main.tex`.

## What it holds

Every result this work has settled, filed by what settles it. A deductive result is carried by a proof. A measured result is carried by a number, its corpus, and the tool that produced it, and it is filed by whether the posit survived. A hypothesis is a claim whose experiment can be built and has not been run yet. Anything whose experiment cannot be built as written is not in the ledger at all; it is in `theory/thought_experiments/`.

That partition is the point of the document. Mixed together, a conjecture about an unbounded carrier sits beside a 582-row bench table and neither reads as what it is.

## Reading it

Build the book and read the PDF:

```sh
sh tools/book/build_theory.sh workbook
```

The result lands in `build/theory/workbook/main.pdf`. The build runs LuaLaTeX twice, because the table of contents is written on the first pass and read on the second, and it fails if any book drops a glyph.

Nothing here is a second copy of the ledger. One fact is stated once, and a page that restated the ledger would be a page that disagrees with it later.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-09
