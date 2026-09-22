# A finer alphabet, and what it would buy

The eight-letter octant reading carries eight numbers about a source with 256 degrees of freedom.
`docs/octant-lexicon.md` carries that count and the reading it bounds. The obvious repair is a finer
alphabet, and the candidate on the table is to subdivide each octant's spherical triangle, giving
`8 * 4^k` cells at depth `k`.

This note works out what that would buy before anyone spends the compute on it.

## The answer

Subdividing does not repair the reading, and the argument that settles it is counting, not
statistics. The placement holds 256 points, and past a certain depth there are more cells than there
are points to write into them.

| `k` | cells | placement slots per cell |
|---|---|---|
| 0 | 8 | 32 |
| 1 | 32 | 8 |
| 2 | 128 | 2 |
| 3 | 512 | 0.5 |

At `k = 3` there are twice as many cells as placement points, so most letters can never be written
at all and the alphabet carries dead symbols. At `k = 2` the cell count equals the typical lit count,
each cell holds two placement slots, and the reading has stopped being a coarse-graining: it is close
to a permuted list of which bits are lit. On a 256-point placement `k = 2` is the last depth that
means anything, and by then the object being read is no longer a distribution over regions.

Raising the placement's point count moves the ceiling but not the problem, since the redraw level
below is set by the ratio of cells to lit points and that ratio is what the subdivision changes.

## The same ceiling, counted on the reading instead of the placement

The table above counts cells against placement points. The harmonic reading gives the same ceiling
from the other side, and the two agree.

A reading to degree `L` carries exactly `(L+1)^2` real numbers about its source. Against 256 degrees
of freedom, degree eight is rank 81 and blind in 175 directions, degree fifteen is where `(L+1)^2`
first reaches 256, and the least singular value collapses to 3.5e-3 there before recovering to
1.5e-1 at sixteen. Refinement raises the count of numbers a reading carries; it does not raise the
count past the source, and it makes the inversion worse on the way through the floor.

A finer alphabet is therefore bounded twice, once by how many cells the placement can fill and once
by how many numbers the degree can carry, and neither bound is statistical. `tools/view/frame_findings.md`
holds the rank measurement.

## The scaling expectation

Separately from the ceiling, a finer alphabet is expected to raise the delta and the redraw level
together, leaving their ratio where it was.

The floor half of that is solid. Two independent states of the same weight give a level that grows
as the square root of the cell count, which is ordinary redraw statistics and needs no assumption
about the function being read. The delta half is only an expectation: a round's movement
behaves like a partial redraw, so it is expected to scale the same way. An attempt to derive that
equality is recorded below, along with the reason it does not stand.

## A derivation that did not hold

The argument was that the delta equals the floor times `sqrt(s)`, where `s` is the fraction of the
lit set a round sends to fresh positions, on the grounds that points which did not move cancel cell
by cell and leave the same calculation over `s n` points. The cell count then cancels between the
two expressions and the ratio depends on `s` alone.

**The hole.** A share is a count divided by the weight, and the weight changes every round. On the
working state it ranges from 108 to 140 lit bits and moves by 4.3 bits per round on average, which
is 3.5% of the weight. A change in the denominator moves all eight shares even for points that never
moved, so the cancellation the argument rests on does not happen.

**The test.** Predicting `s` from the ratio squared and counting the lit points that actually moved,
over all 63 consecutive pairs, with the digest column kept beside it because the earlier version of
this note was measured there:

| quantity | working state | finalized digest |
|---|---|---|
| correlation of predicted against counted | 0.105 | 0.068 |
| worst predicted `s` | 3.633, an impossible value | 3.508 |
| observed ratio, per pair | 0.382 to 1.906 | 0.507 to 1.873 |

As a per-pair estimator it fails on either object, and it returns values above one where no fraction
can go. Changing the object moved every figure and changed no conclusion. Running it on both objects
earned that much.

**What holds.** On the mean, with both sides in the same units, the law's central claim stays close.
The counted relocation in the law's own units averages 1.0172, whose square root is 1.0085, against
an observed mean ratio of 1.0361. The two agree to 2.7%.

The units matter and were the source of an earlier disagreement about this: a set difference between
two states of weight `n2` out of `N` saturates at `1 - n2/N`, about one half, and never at one, and a
raw set difference of 0.5 already means complete independence. Comparing `sqrt(0.5) = 0.707` against
a ratio near 1.0 compares two different quantities.

So the mean prediction survives and the per-round estimator does not. Neither outcome supports using
this argument as the reason a finer alphabet fails, and the two ceilings above are the reasons to
give.

## The constant that replaced it

The counted relocation is close to constant, the useful finding to come out of the test.

| quantity | working state | finalized digest |
|---|---|---|
| set difference between consecutive states | mean 0.5215, range 0.421 to 0.619 | mean 0.4969 |
| the same in matched units, where 1.0 is independence | 1.0172 | 0.9976 |
| bits differing between consecutive states | mean 129.9 of 256 | mean 127.7 |
| what a coin would give | 128.0 | 128.0 |

Every round relocates the lit set about as completely as an independent draw would, from the first
round onward, with the working state sitting 1.7% above independence and the digest 0.2% below it.
Reading `s` off the ratio is therefore estimating something that barely varies, and the backwards
reading carries correspondingly little.

An earlier version of this note put worked examples in a table, `s = 0.45` at round 1 to 2 and
`s = 0.91` across the first eight. Both were wrong, and they were wrong in a way worth naming: they
came from reading the ratio off aggregate percentages instead of per pair, and they bracketed the
true value by accident.

## What a frame actually is

Worth stating, because it bounds every result above, and because an earlier version of this section
had it backwards.

A frame is the eight working words as the round leaves them, with nothing added back. `rounds_of`
reads that by default. It can also return the finalized digest under `--read digest`, where
`digest_after` adds the initial values back into the working state before returning, and that
feed-forward is a mixing step applied after the round.

The two objects are told apart by counting and not by assertion. A round only copies six of its
eight words, `b,c,d` taking `a,b,c` and `f,g,h` taking `e,f,g`. Over sixty-three transitions that is
378 carried words, and on the working state all 378 match the words they come from while on the
digest none do.

That count also settles a question this section previously recorded as closed the wrong way. The
register shift is present in the working state exactly, since matching all 378 carried words is what
being a register shift means. The earlier text reported the shift as invisible, on a test that
undid the word shift and found 108.9 of 224 bits differing against a coin's 112.0 with no exact
match in sixty-four rounds. That test was run on digest frames, and it was measuring the
feed-forward.

What is not established is a link between the shift and the octant delta. The delta's early excess
over the redraw floor is measured, and a rigid relabeling of indices is the kind of move that
produces such an excess, but attributing the excess to the register shift is a reading of why and
has not been measured. The two statements sit at different levels and only the first is a count.

## What would settle the subdivision

One run at `k = 1` and `k = 2`, each with its own redraw level computed at the matched weight,
reporting the ratio and not the delta. Two ratios near the `k = 0` value confirm the expectation. A
ratio that falls with `k` refutes it cheaply, and the two ceilings still stand either way.

Ownership: the subdivision candidate and the run are the engine's. The refutation of the `sqrt(s)`
derivation is the engine's, and the rank bound is the engine's. The reproduction, the units
correction, the object correction and the reruns above are this document's.
