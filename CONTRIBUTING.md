# Contributing

**Purpose:** Know what a contribution here looks like, what the checks are, and which rule is not negotiable.
**Scope:** the whole repository

## The condition that comes before everything

**A tool for language that comes out of this work requires a human to review its output.** The tools here can regenerate language and can produce predictive speech, and whether a regenerated form is still somebody's language belongs to a native speaker and not to an algorithm.

A contribution that removes a person from that loop, or that makes it easier to skip them, is not accepted. This is not a style preference and there is no version of the repository where it is relaxed.

## What a contribution is

This is a research body with code attached. Three kinds of change are useful:

**A measurement.** A number with its conditions attached: what corpus, what length, what it was measured against, and what the floor was. A ratio with no denominator is not a result. Every figure in `docs/research/anchor-sift-ledger.md` names the tool that produced it, and a new one does the same.

**A correction.** The ledger keeps its own corrections and it is the most valuable thing in the repository. A claim that turns out to be wrong stays on the page beside the measurement that killed it. If you find a figure that does not reproduce, the contribution is the demonstration, not a quiet edit.

**A precedent.** Several results here are rediscoveries of published work. This repository has been wrong about priority before, at Montemurro and Zanette, and the entry says so. If you know the prior art for something claimed here, that is worth more than a patch.

## What is not in the repository

The 20 hand extraction tables under `docs/research/Salishan/pure_corpus/` are not carried in git. Every row is a form transcribed out of a published paper, so the tables are those papers' text and not this work's to redistribute. `refs.md` gives the address of every source paper, and the tables go to anyone who has the papers and asks.

The derivations built on them are here in full: the ledger, the bound, the checks and the code.

The corpora, page renders and audio under `build/` are also absent and run to about 1.9 GB. `tools/dev_env/Salishan/get_papers.py` fetches the papers and the tools rebuild the rest.

## Checks

**Prose.** The writing standard is checked instead of remembered:

```sh
python tools/dev_env/docs_check.py docs
python tools/dev_env/docs_check.py docs --strict
```

Breaking findings are an empty table, an em dash, and a link to a file that is not there. Those stop a commit. Prose findings are printed and let through, because the prose backlog predates the check.

Turn the hook on once per clone:

```sh
git config core.hooksPath .githooks
```

**The kernel.** C11 and nothing else. No Python, no device toolchain:

```sh
cmake -S bench -B build/bench -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/bench
./build/bench/bench_ancorae_cycles
```

Every arm has to agree with `anchor_sift_naive` on every row. A row printing `DIFFER` is a defect and its timing means nothing, because a measurement of an arm returning the wrong answer is a measurement of the wrong program.

**The ports.** `ports/R/` and `ports/matlab/` carry the permutation null measure. The Python in `tools/dev_env/proof_conservation.py` is the reference: a port is correct when it lands inside the reseeding floor of it, since each language draws its null from a different generator and none of them can agree to the last digit.

## Writing

Prose here is plain. One fact per sentence, subject and verb and object, no em dashes, American spellings. `docs/research/terms.md` says which words are the field's and which this work minted, and the field's word wins wherever one exists.

`docs/research/Salishan/pure_corpus/README.md` is generated from `paper_config.py` by `pure_corpus_index.py`, which keeps a speaker's name typed in exactly one place. Do not edit it by hand.

## Licensing

Contributions fall under the same terms the repository carries: AGPL-3.0-or-later, or a negotiated commercial license, or an educator's license issued to a person. The root `README.md` states the scheme in full.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-04
