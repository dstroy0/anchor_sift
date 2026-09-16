# Experimental

**Purpose:** Hold work that has no walk through a corpus yet, so it is visible without being mistaken for a stage.
**Scope:** `examples/0_experimental/`

Six readings, each taking a filter from another field and running it on this engine's terms. None
reads a corpus, which is why they are here and not at a subject stage.

| file | field | what it shows |
|---|---|---|
| `bloom_is_the_sift_theorem.py` | databases | a Bloom filter is the anchor cascade's theorem, with the same one-directional error |
| `hamming_corrects_by_selecting.py` | coding theory | a parity syndrome corrects by selecting the codeword its necessary conditions leave standing |
| `collaborative_filter.py` | recommender systems | a missing entry predicted from the neighbourhood that shares its known values |
| `morphology_opening_and_closing.py` | image morphology | erosion and dilation rejecting a speckle by rank, with no threshold |
| `invariant_consensus_rejects_outliers.py` | robust estimation | the inliers are mutually compatible, so they are a clique, and rejecting outliers is finding it |
| `theil_sen_robust_trend.py` | robust statistics | a median over pairwise slopes recovers the trend exactly where least squares is dragged off it |

The last two share a floor and it is the same floor. A necessary condition cannot refuse a large
enough accident: outliers that conspire into a consistent set bigger than the truth take the clique,
and a conspiracy whose pairs outnumber the clean ones takes the median. Both files sweep that floor
rather than quoting it, and both also sweep the benign case where the outliers merely scatter, because
a method with two ways to fail has two floors and one figure is the wrong shape for that.

Each carries a positive control, two routes shown able to disagree, a drawn null, and a stated floor.
A file earns a subject stage once it reads that subject's corpus; until then it earns this directory.

Everything in `examples/` sits at `<subject>/<stage>/`, and a file only earns that path once it is clear which corpus it reads and where in the walk it sits. Something that reads no corpus in particular, or sits between two stages, or was written to try an idea that has not been placed yet, goes here until one of those is settled.

## What belongs here

A script that answers a question nobody has assigned to a subject. A first attempt at a stage that does not exist for any subject yet. A reading whose corpus has not been fetched.

## What does not

**A failure does not belong here.** A stage that was tried and did not work is evidence and it stays in its subject beside the readings that came after it. The Dravidian family failing to appear under a codepoint reading sits in `language/4_measure`, next to the two readings that repaired it, because a reader who finds only the repair does not know what it repaired.

**A fetcher does not belong here.** Acquiring a corpus is not a stage of reading one. Those are in `maint/data/fetch/`.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
