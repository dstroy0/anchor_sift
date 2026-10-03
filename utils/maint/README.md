# maint

**Purpose:** Find the tool that maintains one part of this repository, and know before adding a script where it belongs.
**Scope:** `utils/maint/`

Nothing here reads a corpus to answer a research question. That is `examples/`. Everything here acts on the repository: its records, its gates, its prose, its dependencies, its research papers, and the material it ingests.

## Every script sits in a category and none sit loose

A directory with no membership rule collects whatever nobody had a better place for, and `tools/` was that directory until it held fifty three files. Each category below states a rule, and a stated rule is what a directory needs to stay sorted. A script that satisfies no rule means the rule set is incomplete, and the fix is a new category carrying its own stated rule.

| directory    | what belongs in it                                                                                              |
| ------------ | --------------------------------------------------------------------------------------------------------------- |
| `catalog/`   | the example registry: issuing numbers, holding them, and finding an example whose description and code disagree |
| `citations/` | what this work rests on and whether it is named: the mathematics registry and the corpus crossref               |
| `corpus/`    | the private corpus's inventory, permission and signature                                                        |
| `source/`    | tools that read source text as text, without running it                                                         |
| `engine/`    | checks of one engine implementation against another                                                             |
| `deps/`      | material brought in from outside this repository                                                                |
| `tree/`      | what this repository itself contains and writes                                                                 |
| `prose/`     | the writing in this tree, measured against human writing                                                        |
| `texbuild/`  | building the theory research papers                                                                             |
| `data/`      | fetching, converting, transcribing or repairing somebody else's material                                        |
| `analysis/`  | a corpus read through `src/`, for a survey a research paper asked for                                           |
| `claims/`    | every public claim held against the latest result in the theory                                                 |

## What each holds

**`catalog/`.** `catalog.py` issues a number to every example and never reissues one. `catalog.tsv` is the registry it writes. `catalog_verify.py` points at examples whose header and code have drifted apart. A number survives a file moving and a path does not. The registry exists for that reason alone.

**`source/`.** `codemask.py` says which bytes of a C file are code. `strip_comments.py` and `readclean.py` remove comments so code can be read or rewritten without prose in the way. `dedup.py` finds the same code written twice under different names. `src2png.py` renders source to pages for surveying at image density.

**`engine/`.** `check_exact_limbs.py` checks the C limb arithmetic against python integers, which are arbitrary precision and share no code with it. A library cannot be its own oracle. Every arm of the engine is checked against a different implementation and never against a second routine in its own file. The vectorized and GPU arms are checked here as they land.

**`tree/`.** `write_survey.py` reads every script for the files it opens and reports where each one lands. The list of what this tree writes is checked instead of remembered.

**`claims/`.** `claim_check.py` reads the numbers a reader meets first, in `README.md`, every page under `docs/` and the abstract of each research paper, and asks the theory whether it still holds each one or has taken it back. A claim the theory took back ends the run with 1, and `.githooks/pre-commit` runs it whenever one of those pages or the theory is in the index. `claims_read.tsv` holds what a person has read and found sound, one row each, and a row stops matching once the answer changes.

## Paths are walked to, never counted

Every script here finds the repository by walking up until it sees `src/python`, with a guard so it stops at the filesystem root:

```python
ROOT = os.path.dirname(os.path.abspath(__file__))
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
```

Thirty nine scripts counted parent directories instead, and counting fixes a script's distance from the root. Sorting `utils/maint/` into these categories moved every one of them and would have broken all thirty nine at once. `docs_check` had the same defect twice over: it counted its own depth, and it listed prose roots that had moved, which made it read 188 files instead of 317 and still exit 0. A root that no longer exists now raises instead of reading as zero findings.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
