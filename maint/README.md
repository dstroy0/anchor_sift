# maint

**Purpose:** Say what belongs in this directory and what does not, leaving a new script one obvious place.
**Scope:** `maint/`, `maint/prose/`, `maint/book/`.

**Everything here operates on the repository itself.** Its records, its writing, its books, its gates. Nothing here reads a corpus to learn something about the world, and nothing here is part of the method.

## The records, and the gates over them

Each one answers the same question about a different thing: does what is written down still match what is here.

| | |
|---|---|
| `catalog.py`, `catalog_verify.py` | every example carries a number, issued once and never reissued. 98 so far |
| `citations.py` | the sources the measurements are built on, bucketed by field or by domain |
| `corpus_manifest.py` | the two signed inventories of a closed repository, one for recordings and one for everything else |
| `verify_private_sync.py` | whether what `build/` reaches is the corpus those signatures cover |
| `speech_gate.py` | no recording is held without a row saying what it is held under |
| `speech_order.py` | the order nations are approached in, drawn from a kept seed so nobody was placed by hand |
| `corpus_crossref.py` | corpus material used in this tree without the paper, the speaker or the language named beside it |
| `write_survey.py` | every file write in the tree, so nothing lands outside `build/` unnoticed |
| `get_deps.py` | what this tree depends on, and the two closed repositories it mostly cannot clone |

Four of them refuse a commit: the two manifests, the citation registry and the speech gate. All four take `--bypass`, spelled the same, and `ANCHOR_SIFT_BYPASS=1` carries it into a hook where nobody is typing arguments. A bypass says so every time.

## prose

The register checks. `docs_check.py` reads how a comment or a page is written and refuses a commit on a breaking finding. `claudese_distance.py` measures a file against two poles instead of against a pattern list. `oracle_agreement.py` asks whether the label on a fetched corpus carries any information, by seeing whether corpora sharing a label resemble each other more than a control.

`english_gate.py`, `english_sift.py`, `prose_era.py`, `prose_distance.py` and `ban_evidence.py` are the measurements those rest on.

## book

`build_theory.sh` compiles every book under `theory/`, twice each, and fails on a dropped glyph. `markdown_to_latex.py` is the converter the generated chapters go through. `math_hazards.py` and `ledger_days.tsv` check the books themselves.

## Reading a tool

`readclean.py` prints a file three ways and writes nothing: `code` with comments stripped, `blind` with the names this project chose replaced, and `claims` with each comment beside the code under it. Python, C, R and MATLAB. `readclean_mmgr.py` is the older C-only version that knows MMgr's naming grammar, kept because this one does not.

`strip_comments.py`, `codemask.py`, `dedup.py` and `src2png.py` are the rest of that toolkit: strip C comments, mask code from prose, find duplicated blocks, and render source to PNG for zooming.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-09
