# maint

**Purpose:** Find the tool that maintains one part of this repository, and know before adding a script where it belongs.
**Scope:** `maint/`

Nothing here reads a corpus to answer a research question. That is `examples/`. Everything here acts on the repository: its records, its gates, its prose, its dependencies, its books, and the material it ingests.

## Every script sits in a category and none sit loose

A directory with no membership rule collects whatever nobody had a better place for, and `tools/` was that directory until it held fifty three files. Each category below states a rule, and a stated rule is what a directory needs to stay sorted. A script satisfying none of them means the rule set is incomplete, and the fix is a new category carrying its own stated rule.

| directory | what belongs in it |
|---|---|
| `catalog/` | the example registry: issuing numbers, holding them, and finding an example whose description and code disagree |
| `citations/` | what this work rests on and whether it is named: the mathematics registry and the corpus crossref |
| `corpus/` | the private corpus's inventory, permission and signature |
| `source/` | tools that read source text as text, without running it |
| `engine/` | checks of one engine implementation against another |
| `deps/` | material brought in from outside this repository |
| `tree/` | what this repository itself contains and writes |
| `prose/` | the writing in this tree, measured against human writing |
| `book/` | building the theory documents |
| `data/` | fetching, converting, transcribing or repairing somebody else's material |
| `analysis/` | a corpus read through `src/`, for a survey a book asked for |

## What each holds

**`catalog/`.** `catalog.py` issues a number to every example and never reissues one. `catalog.tsv` is the registry it writes. `catalog_verify.py` points at examples whose header and code have drifted apart. A number survives a file moving and a path does not. The registry exists for that reason alone.

**`citations/`.** `citations.py` is the register of the mathematics this work rests on, and it fails while a name is used and unregistered. `corpus_crossref.py` finds corpus material used without the paper it came from named beside it, and `--speakers` reports who the corpus rests on and who is unnamed.

**`corpus/`.** `corpus_manifest.py` reconciles the private tree against its signed inventory. `speech_gate.py` refuses recorded speech the community has not permitted. `speech_order.py` holds the drawn order nobody chose. `verify_private_sync.py` checks that what `build/` reaches is the corpus the signature covers. Each takes `--bypass`.

**`source/`.** `codemask.py` says which bytes of a C file are code. `strip_comments.py` and `readclean.py` remove comments so code can be read or rewritten without prose in the way. `dedup.py` finds the same code written twice under different names. `src2png.py` renders source to pages for surveying at image density. `readclean_mmgr.py` is the preserved C only original and `readclean_mmgr_test.py` is its test.

**`engine/`.** `check_exact_limbs.py` checks the C limb arithmetic against python integers, which are arbitrary precision and share no code with it. A library cannot be its own oracle, so every arm of the engine is checked against a different implementation and never against a second routine in its own file. The vectorized and GPU arms are checked here as they land.

**`deps/`.** `get_deps.py` clones what this repository depends on instead of carrying copies. `vendor_test_vectors.py` vendors the published SHA-256 test vectors with a manifest recording where each came from.

**`tree/`.** `write_survey.py` reads every script for the files it opens and reports where each one lands, so the list of what this tree writes is checked instead of remembered.

## Paths are walked to, never counted

Every script here finds the repository by walking up until it sees `src/engine`, with a guard so it stops at the filesystem root:

```python
ROOT = os.path.dirname(os.path.abspath(__file__))
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
```

Thirty nine scripts counted parent directories instead, and counting fixes a script's distance from the root. Sorting `maint/` into these categories moved every one of them and would have broken all thirty nine at once. `docs_check.py` had the same defect twice over: it counted its own depth, and it listed prose roots that had moved, which made it read 188 files instead of 317 and still exit 0. A root that no longer exists now raises instead of reading as zero findings.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-09
