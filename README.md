# theory_bucket

**Purpose:** Author the theory books in one place, and know which direction a change travels between
here and the release before making one.
**Scope:** the seven books at this repository's root. The anchor_sift workbook is not one of them and
is not here.

## The flow

This repository is upstream. `anchor_sift` is downstream and carries these books in its tree as a
git subtree under `theory_bucket/`, so they ship with the release and a clone gets them without a
second fetch.

```
theory_bucket  (here, authored)
      |
      |  git subtree pull --prefix=theory_bucket
      v
anchor_sift/theory_bucket/  (release, read only)
```

`anchor_sift` main is downstream only. A change typed into `anchor_sift/theory_bucket/` is lost the
next time that subtree is pulled, the same way an edit to any generated file is lost. Bring the
change here, open a pull request against `main`, and pull it down after it merges.

## What is here

| book | what it is |
| --- | --- |
| `Salishan` | the corpus work, whose tables are speakers' words written down |
| `cryptography/sha256` | the SHA-256 readings, refutations included |
| `crystallography` | the lattice work |
| `delta_null` | the null construction |
| `millennium` | the Navier-Stokes and Euler reading |
| `precision` | the relation search and what precision costs |
| `thought_experiments` | the boundary arguments |

## What is not here, and why

The anchor_sift workbook stays in `anchor_sift` at `theory/workbook/`. It is the book about that
engine, it moves when that engine moves, and separating the two would put a book in one repository
and its subject in another.

Two chapters in this tree are generated and say so in their own first lines. Edit the generator, not
the chapter:

* `Salishan/chapters/chapter_Salishan_pure_corpus_README.tex`, from
  `anchor_sift/maint/data/salishan/hand_extraction/pure_corpus_index.py`.
* `cryptography/sha256/chapters/chapter_sources.tex`, from `tools/book/build_bibliography.py` in the
  BTCminer tree, reached through the `btc` remote in anchor_sift's `.git/config`.

## Building

Each book is a directory holding `main.tex`, `preamble.tex`, `chapters/` and `frontmatter/`. Nothing
lands beside the source: build with `-output-directory` pointed under `anchor_sift/build/theory/`.
The one upward path in the tree, the figure guard in `cryptography/sha256/chapters/chapter_boundary.tex`,
resolves against that build directory and depends on a book sitting three levels below the repository
root, which is where these sit both here and downstream.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-11
