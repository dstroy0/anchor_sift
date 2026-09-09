# What of delta null can be measured

**Purpose:** Separate the part of the delta null idea that has already been tested from the part that has not, so neither half borrows credit from the other.
**Scope:** `docs/research/delta-null.md`, `src/engine/c/bench/bench_lattice.c`

The idea is filed as wacky and it is. It keeps its own theory instead of sitting with the thought experiments because it is wacky in a particular way: most of its claims name something a bench can refuse.

## Three claims, and where each one stands

**Invariance under translation, permutation, and change of coordinate representation. Measured, and it holds.** This is not an argument, it is what `bench_lattice` sweeps: 3,421 rows over alphabets of 2 to 256 symbols, patterns of 1 to 32 points, dimensions 1 through 8, a rotated point set, a scatter no rectangle covers, a complex alphabet with irrational parts compared over its storage, and an order check against a permuted base list. 465,546 true occurrences, none refused. The core takes a base list, a displacement list, and a callback answering whether two positions carry the same symbol, so it has no dimension parameter and no symbol type, and a core that cannot see either one cannot depend on either one.

**Hitting the boundary once permanently excludes the point. Measured, and it holds.** The contrapositive is Proposition 1: any subset of a pattern's points is a necessary condition. A failure at one anchor refutes the alignment and no later evidence can restore it. Every arm in the kernel rests on that, and a bench running two arms against the exact compare checks it on every row.

**The volume is recoverable from its boundary. Measured, and it fails.** This is the Laplace's demon half, and the title is named for it. Proposition 2 is the answer: the converse fails for any proper subset of the points, and that is why the exact compare is irreducible and why the arms have to verify what their anchors admitted. A boundary that excludes is not a boundary that determines.

## So the demon can refuse and cannot predict

The strong form is dead and the measurement that killed it was already in the tree before the idea was written down. What is left is the weak form, and the weak form is the algorithm: an anchor set is a boundary, crossing it is final, and crossing it does not tell you what was on the other side.

That is worth keeping because it is a real constraint and not a disappointment. A filter that refutes cheaply and determines nothing is the shape the whole construction has, and it is the reason soundness is free while completeness costs a full compare.

## What is not testable here

The holographic claim in physics is about a bound on the information a region can hold. Nothing in this repository measures that, and the resemblance is an analogy. The analogy earns its place only where it produced the three claims above, two of which were checkable and one of which was already checked and refused.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
