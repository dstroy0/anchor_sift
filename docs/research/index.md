# Research

**Purpose:** Say where the research is and how to build it.
**Scope:** `theory/`, and `tools/book/build_theory.sh`, which builds it.

The research is in `theory/`, as books. It was kept here as markdown once. Two copies of a document drift apart, and the copy a reader finds first is then wrong.

## The books

| book | what it holds |
|---|---|
| `theory/anchor_sift/` | The construction, the method, ordering anchors by rarity, and the terms. |
| `theory/workbook/` | The ledger: deductive results, hypotheses, and what was measured, filed by whether the posit held. |
| `theory/Salishan/` | Whose words the corpus holds, how wrong it could be, running the extraction, and the sources. |
| `theory/thought_experiments/` | The posits whose experiment cannot be built as written. |
| `theory/cryptography/sha256/` | Where SHA-256's structure is, where it stops, and how each null was measured. A corpus built to carry no natural structure, which makes it a contra-example. |

## Building them

```sh
sh tools/book/build_theory.sh
```

The PDFs land in `build/theory/<book>/main.pdf`. The build runs LuaLaTeX twice, because the table of contents is written on the first pass and read on the second, and it fails if any book drops a glyph.

One book on its own:

```sh
sh tools/book/build_theory.sh workbook
```

## What the split is for

The workbook holds a claim and the work that settles it. A conjecture leads the entry and the measurement follows, filed by whether the posit held or was refuted. Anything whose experiment cannot be built as written is in the thought experiments book instead.

Mixed together those read as one undifferentiated pile, and a conjecture about an unbounded carrier sitting beside a 582-row bench table discredits both. Apart, each reads as what it is.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-09
