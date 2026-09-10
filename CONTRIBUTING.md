# Contributing

**Purpose:** Know what a contribution here looks like, what the checks are, and which rule is not negotiable.
**Scope:** the whole repository

## The condition that comes before everything

**A tool for language that comes out of this work requires a human to review its output.** The tools here can regenerate language and can produce predictive speech, and whether a regenerated form is still somebody's language belongs to a native speaker and not to an algorithm.

A contribution that removes a person from that loop, or that makes it easier to skip them, is not accepted. This is not a style preference and there is no version of the repository where it is relaxed.

## What a contribution is

This is a research body with code attached. Three kinds of change are useful:

**A measurement.** A number with its conditions attached: what corpus, what length, what it was measured against, and what the floor was. A ratio with no denominator is not a result. Every figure in `theory/workbook` names the tool that produced it, and a new one does the same.

**A correction.** The ledger keeps its own corrections and it is the most valuable thing in the repository. A claim that turns out to be wrong stays on the page beside the measurement that killed it. If you find a figure that does not reproduce, the contribution is the demonstration, not a quiet edit.

**A precedent.** Several results here are rediscoveries of published work. This repository has been wrong about priority before, at Montemurro and Zanette, and the entry says so. If you know the prior art for something claimed here, that is worth more than a patch.

## What is not in the repository

The 20 hand extraction tables under `theory/Salishan/` are not carried in git. Every row is a form transcribed out of a published paper, so the tables are those papers' text and not this work's to redistribute. `refs.md` gives the address of every source paper, and the tables go to anyone who has the papers and asks.

The derivations built on them are here in full: the ledger, the bound, the checks and the code.

The corpora, page renders and audio under `build/` are also absent and run to about 1.9 GB. `maint/data/salishan/get_papers.py` fetches the papers and the tools rebuild the rest.

## Checks

**Prose.** The writing standard is checked instead of remembered:

```sh
python maint/prose/docs_check.py docs
python maint/prose/docs_check.py docs --strict
```

Breaking findings are an empty table, an em dash, and a link to a file that is not there. Those stop a commit. Prose findings are printed and let through, because the prose backlog predates the check.

Turn the hook on once per clone:

```sh
git config core.hooksPath .githooks
```

**A contribution's own prose.** The condition at the top of this file had no check attached to it. This is that check:

```sh
python maint/prose/submission_check.py <path to the contribution>
```

It reads the prose of a submission and reports two things. Any model vendor named in it, which catches only the careless case. And how often it reaches for the 285 phrases `docs_check.py` bans, as a rate per hundred thousand words, against the rate a human research writer carries for the same list. That baseline is 387.9, counted over 759,815 words of the papers under `build/papers`, and it is summed from the same table the findings come from so the two cannot disagree.

Two poles calibrate it. A page written deliberately in the machine register measures 12.5 times the human rate. Three Salishan papers measure 0.5, 0.6 and 0.9.

Read the word count before the ratio. The denominator is the prose left after code, math and markup come out, and a submission that is mostly a word list or interlinear glosses will count high and rate low.

It reports and it does not decide. Nothing in it prints a verdict, and a hook that rejected a contribution on its output would automate away the person the rule at the top of this file exists to require. A low number is not evidence of anything either: the rates are a floor, and anyone who knows the list can write around it.

**The kernel.** C11 and nothing else. No Python, no device toolchain:

```sh
cmake -S bench -B build/bench -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/bench
./build/bench/bench_ancorae_cycles
```

Every arm has to agree with `anchor_sift_naive` on every row. A row printing `DIFFER` is a defect and its timing means nothing, because a measurement of an arm returning the wrong answer is a measurement of the wrong program.

**The ports.** `ports/R/` and `ports/matlab/` carry the permutation null measure. The Python in `examples/proofs/posits/proof_conservation.py` is the reference: a port is correct when it lands inside the reseeding floor of it, since each language draws its null from a different generator and none of them can agree to the last digit.

## Writing

Prose here is plain. One fact per sentence, subject and verb and object, no em dashes, American spellings. `theory/anchor_sift` says which words are the field's and which this work minted, and the field's word wins wherever one exists.

`theory/Salishan` is generated from `paper_config.py` by `pure_corpus_index.py`, which keeps a speaker's name typed in exactly one place. Do not edit it by hand.

## Licensing

Contributions fall under the same terms the repository carries: AGPL-3.0-or-later, or a negotiated commercial license, or an educator's license issued to a person. The root `README.md` states the scheme in full.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-04
