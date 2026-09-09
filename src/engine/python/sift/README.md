# Sift

**Purpose:** Discard candidates without ever losing a true occurrence, and understand why the selection rule is free.
**Scope:** `src/engine/python/sift/`, and `src/engine/c/` for the C implementation

| module | what it holds |
|---|---|
| `anchors.py` | `rarest`, `spread`, `jittered`, `cell_rarest`, `survivors`, `positions_by_symbol` |

## The proposition, and what it does not mention

Any subset of a pattern's points is a necessary condition, so no selection rule can lose a true occurrence. The proof uses no order, no dimension, no alphabet, and no interpretation of a symbol. That is why a mineral, a fold, a picture, a cipher and a sentence are one object to it, and why nothing was ported between those cases: there was nothing to port.

The converse does not hold for any proper subset, so the exact compare is irreducible and every surviving candidate has to be confirmed. Errors are therefore one directional: a discrepancy is always an over-count and is detectable without knowing the answer.

## Which means correctness cannot turn on the rule

An anchor is a condition copied out of the pattern. A position genuinely holding the pattern therefore satisfies every anchor, whatever chose it. What the rule moves is how many false candidates survive, which is cost.

`src/engine/c/bench/bench_lattice.c` measures exactly that separation: 3,421 rows, 465,546 true occurrences, none refused, across alphabets of 2 to 256 symbols, patterns of 1 to 32 points, 1 to 32 anchors, dimensions 1 through 8, a complex irrational alphabet compared over its storage, a rotated point set, a scatter, and an unordered base list. The refusal column reads `hold` on every row while the candidate column moves with the rule, the count and the geometry. The two columns are graded to different standards: a refusal is a defect, a candidate count is a cost.

## What the rules trade

| rule | filter | sizing |
|---|---|---|
| `rarest` | best measured, 15.9 alignments on English prose | worst, 20992 times |
| `spread` | weakest, 345.8 alignments | honest, 2.02 times |
| `jittered` | 337.2 alignments | 1.84 times |
| `cell_rarest` | 5.0 alignments, the best measured | median error 1.11 |

Neither of the first two dominates, and which is right depends on a term not yet in this work: whether survivors are verified and discarded or buffered and handed on. Under-provisioning is a performance question in the first case and a correctness question in the second.

`cell_rarest` is the best filter measured and is not the rule the C kernel uses.

## Where an even comb fails

Spacing the offsets evenly shares a period with whatever the domain carries. On a corpus of period sixteen every anchor lands congruent modulo sixteen, so four probes ask one question four times and the survival rate misses the histogram bound by a factor of 4096. Drawing one offset inside each cell keeps the spread and gives the anchor set no period of its own.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
