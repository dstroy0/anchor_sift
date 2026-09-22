# The octant lexicon

Eight regions, one letter each, and a word that a computation spells as it runs. The alphabet is
general. It reads a lit set on a boundary and knows nothing about what lit it, so the same eight
letters serve any object that can be placed on a sphere. The instance it was tested on is SHA-256,
and `tools/view/octant_lex.py` lexes that hash round by round and prints the word.

This page records what the reading does and, at greater length, what it cannot do.

Stated first, because a reader who takes one thing away should take this: the alphabet carries eight
numbers about a source with 256 degrees of freedom, and the result that looks like a success is
close to free. Neither of those is a defect in the tool. They are the size of the instrument,
counted.

## The alphabet

Choose some regions. A state writes one letter per region, the letter being the share of the lit set
sitting inside it. A step of the computation rewrites every letter at once, and the numbers tracked
across the steps are the word it spells.

**The regions are free.** They may sit at any origin, inside the object or outside it, they may
overlap each other and anything else, and they may take any shape. The same topology rules govern
them as govern the rest of the dimensions, and shape does not enter: a region has to exist, and past
that its geometry is a drawing convenience carrying nothing. The established table in
`docs/boundary-counting.md` holds that as a measurement in its own right.

Two properties do follow from choices, and it is worth keeping them apart from the reading itself.
Regions that tile without gap or overlap force the letters to add to one, which costs one degree of
freedom. Regions that overlap carry no such constraint and can therefore hold one number each.

## The instance this page uses

Eight regions cut by the sign of each coordinate. Every one has a trilateral right-angle corner at
the origin, all eight corners meet at that single point, and they tile space with no gap and no
overlap. On the boundary the same split cuts eight congruent spherical triangles, each with three
right angles and each of area `pi/2`, and the measured shares sum to 1.000000000000000.

This is the convenient case and not the general one. It was picked because it is easy to state, easy
to draw and cheap to compute, and every number below inherits the eight and the tiling from that
choice.

Nothing above mentions a hash. What lit the set is the caller's business, and
`docs/boundary-reading.md` carries the library and the placements underneath this reading.

## The size of the instrument

A reading to degree `L` carries exactly `(L+1)^2` real numbers about its source, whatever the source
is. Set that against the number of degrees of freedom in the source and the shortfall is the
blindness, before any measurement is taken.

| degree | coefficients | rank | blind | least singular value |
|---|---|---|---|---|
| 4 | 25 | 25 | 231 | 4.495 |
| 8 | 81 | 81 | 175 | 4.365 |
| 12 | 169 | 169 | 87 | 3.818 |
| 15 | 256 | 256 | 0 | 3.474e-3 |
| 16 | 289 | 256 | 0 | 1.524e-1 |

Against a 256-bit lit set, a reading to degree eight recovers 81 directions and is blind in 175. The
map reaches the rank its coefficient count allows at every degree below the source count, so the
shortfall in coefficients accounts for the blindness on its own. No sample size, no precision and no
number of beams changes it.

The eight-letter alphabet on this page is rank 8, seven free numbers once the weight is fixed, blind
in 248 of 256 directions.

Degree fifteen is the floor, where `(L+1)^2` first reaches 256. Reaching the floor is not reaching a
usable reading: the least singular value collapses to 3.5e-3 there and recovers to 1.5e-1 at
sixteen, so one degree of headroom is worth 44 times in conditioning. A reading degree picked by
counting coefficients alone lands on fifteen and reports success.

Measured at full depth and no conduction, the most favourable case, in `tools/view/frame_findings.md`.

## The instance it was tested on

Everything from here down is one instance: SHA-256 compressing a single block, with its 256 working
state bits taken as the lit set after each round. The hash is what the instrument was tried on, and
the trying is not the subject. A reader who wants the alphabet and not this hash can stop above.

## The object being read

A frame is the eight working words as the round leaves them, with nothing added back. That
distinction decides every number below, and an earlier version of this page had it wrong. The
section on the corrected reading records what moved.

The check counts which object it has instead of trusting the caller. A round only copies six of its
eight words, `b,c,d` taking `a,b,c` and `f,g,h` taking `e,f,g`, so on the working state all 378
carried words match the words they come from and on the digest none do.

## The placement under it

The 256 state bits go onto a golden placement. One index of shift on that placement is a rigid
screw: turn 2.399963 radians, axial slide -0.007812, pitch -0.003255258. The pitch holds for every
amount, so one helix carries them all, and where a shifted bit lands is fixed once the amount is
known. `docs/boundary-reading.md` carries that measurement and the library it came from.

## The word

Compressing the empty message, read to degree eight. The delta is the share of the reading that
moved since the round before.

| round | oct0 | oct1 | oct2 | oct3 | oct4 | oct5 | oct6 | oct7 | delta |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 0.142 | 0.126 | 0.126 | 0.102 | 0.102 | 0.150 | 0.157 | 0.094 | 0.0% |
| 2 | 0.122 | 0.174 | 0.122 | 0.078 | 0.130 | 0.113 | 0.113 | 0.148 | 12.9% |
| 3 | 0.171 | 0.111 | 0.120 | 0.137 | 0.103 | 0.103 | 0.145 | 0.111 | 14.0% |
| 4 | 0.111 | 0.103 | 0.128 | 0.120 | 0.154 | 0.120 | 0.103 | 0.162 | 12.8% |
| 8 | 0.156 | 0.117 | 0.141 | 0.133 | 0.117 | 0.078 | 0.102 | 0.156 | 8.5% |
| 16 | 0.135 | 0.143 | 0.151 | 0.151 | 0.095 | 0.079 | 0.111 | 0.135 | 10.6% |
| 24 | 0.137 | 0.137 | 0.085 | 0.111 | 0.120 | 0.128 | 0.137 | 0.145 | 7.5% |
| 32 | 0.095 | 0.127 | 0.143 | 0.095 | 0.127 | 0.143 | 0.151 | 0.119 | 10.1% |
| 48 | 0.136 | 0.127 | 0.127 | 0.085 | 0.127 | 0.102 | 0.153 | 0.144 | 12.4% |
| 64 | 0.150 | 0.129 | 0.114 | 0.121 | 0.129 | 0.114 | 0.143 | 0.100 | 5.9% |

The digest at the end is `e3b0c442...7852b855`, the published value for the empty message. That is
the check that the trace is the hash and not something shaped like one.

## The delta against its floor

The delta averages 11.9% over the first eight rounds and 7.1% over the last eight.

Two unrelated states of the same weight differ by 9.4% in this same alphabet. That figure is the
redraw level, and `redraw_level` computes it by drawing 200 pairs of independent states at the
matched weight and averaging the delta between them. Without it the delta is a number with no scale.

| quantity | value |
|---|---|
| redraw level | 9.4% |
| delta, first eight rounds | 11.9%, or 1.27 times the floor |
| delta, last eight rounds | 7.1%, or 0.76 times the floor |
| first round under the floor | 5 |
| weight range across the run | 108 to 140 lit bits |

The early rounds move the reading further than two unrelated states do. A reading whose delta clears
its own independence level is not reporting counting noise, because counting noise is the level it
cleared.

Two cautions on that, both of which bound it.

The fall is a trend in the means and not a monotone series. The per-round deltas over the first
eight rounds run 12.9, 14.0, 12.8, 8.4, 11.9, 14.9, 8.5 and 12.0, so round 5 is the first crossing
and not the last time the delta sits high.

Naming the move is not part of the measurement. A move that carries mass from octant to octant
instead of mixing it will raise the delta above independence, and a rigid relabeling of the indices
is such a move. Reading the early excess as the register shift is a reading of why, and it has not
been measured. What is measured is that the excess is present on the working state and absent on the
digest.

## How much of each change the alphabet could see

The delta says the reading moved. It does not say how much of the change the reading was able to
move for, and those are different questions. A reading is a linear map, two states give the same
letters exactly when their difference lies in its kernel, and the part of a change lying there is
invisible however large it is.

The visible fraction answers the second question: the share of a difference lying in the row space
of the reading, which for eight indicator arms holds the per-octant totals of the change and
discards the rest.

| | visible fraction | against an unstructured draw |
|---|---|---|
| first eight rounds | 0.0397 | 1.48 times |
| last eight rounds | 0.0138 | 0.51 times |
| mean over all 63 pairs | 0.0278 | 1.04 times |

Read the split and never the mean. The early changes sit in the directions the alphabet can see
above what chance would put there, the late changes sit in its blind directions below what chance
would put there, and the mean is those two cancelling. Taken alone the mean reports that the reading
catches an arbitrary few percent, and that reading of it is an artifact of averaging.

The early to late ratio is 2.88, against 1.68 for the delta over the same split, on 8 pairs at each
end. The direction is clear and the sample is small, and the ratio should be quoted with the 8 in
the same breath.

**The two routes share no denominator, and one of them was raised as an objection to the other.**
The delta divides counts by a weight moving 4.3 bits a round, and `docs/finer-alphabet.md` records
that moving denominator as the reason the delta's trend might be bookkeeping instead of arrangement.
The visible fraction is a ratio of two norms of one difference vector in raw counts and carries no
such term. It shows the trend larger, so the denominator was damping the effect and not producing
it.

The control arm is what licenses reading any of this. Differences with no structure in them must
return the fraction the row space predicts, and for differences that hold the weight that figure is
7 of 255 and not 8 of 256: such a difference sums to zero, the all-ones direction lies inside the
row space since the eight indicators add to it, and the difference lives in the hyperplane
orthogonal to all-ones. Measured over 200 draws the control returns 0.0267 against a predicted
0.0275. `tools/view/quotient_coherence.py` refuses to report the measurement at all when the control
misses.

## The reading that was corrected

An earlier version of this page reported the alphabet as saturated: the delta sitting at the redraw
level from round one, no room left to show mixing take hold, and eight letters called too coarse for
the question. That was measured on the wrong object.

Frames came from `digest_after`, which adds the initial values back into the working state before
returning. Every frame was therefore a finalized digest, and the feed-forward is a mixing step
applied after the round, hiding the round's own structure. The count gives it away: on the working
state all 378 carried words survive and on the digest none do.

So the saturation was a property of the digest sequence and not of the alphabet. `rounds_of` reads
the working state by default now and keeps the digest to compare against. The coarseness statement
was withdrawn, and the counting statement in the size of the instrument replaces it, since that one
holds whatever object is read.

## The distinctness result is close to free

Sixty-four rounds wrote sixty-four distinct signatures, a coherence of 100%, with no collisions.
This is not evidence that the letters carry meaning, and it should not be presented as a finding.

The rank says why in one line. Seven free numbers separate sixty-four arbitrary states nearly
always, whether or not the seven carry anything about the source. Distinctness here reports the
resolution of a float and not a property of SHA-256, and any count of distinct signatures quoted
without the rank beside it is quoting the float.

It is computed because the complement would have been informative. A collision is a null
permutation: a move this reading cannot see. None occurred, which rules that out and establishes
nothing beyond it.

What would be evidence: a signature that predicts the round it came from.

## The churn is not stationary

An earlier version of this page reported the arrangement moving at a constant rate from the first
round to the last, and an earlier version of the check asserted first that the delta grows as the
mixing takes hold and then that it holds level. It does neither. It falls, and it crosses the floor
on the way down. Both readings were taken on the digest, where the feed-forward had flattened the
run before the alphabet saw it.

## The twist

Torsion is the reading that does carry position, and it does not bin anything. The twist between
round 1 and round 64 reads 4.715210 radians. Read `docs/boundary-reading.md` for why a phase
recovers an angle to 1.8e-13 radians while a magnitude reads a rotation as nothing at all.

That figure sits under the same rank bound as everything else here. A phase recovers the turn it is
given; it does not add coefficients to the reading.

## What a finer alphabet would need

Refining the cells raises the coefficient count, and the counting table above is the bar it has to
clear. A subdivision that leaves more cells than there are points to write into them has bought dead
symbols, and one that reaches the rank floor has bought a reading whose conditioning collapses.

`docs/finer-alphabet.md` works through the candidate.

## Running it

```
python tools/view/octant_lex.py --check
python tools/view/octant_lex.py --message "abc"
python tools/view/octant_lex.py --read digest
python tools/view/octant_lex.py --top 12
```

`--check` holds the trace to the published digest, holds the eight letters to a sum of one, counts
the carried words to confirm which object it is reading, and holds the delta to clearing the floor
early and falling across the run. `--read digest` reproduces the withdrawn reading, and its own
check asserts that no carried word survives there.
