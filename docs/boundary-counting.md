# What a boundary holds, and how much of that is established

A record of what was tested, what came back, and where the testing stops being able to decide.
Every number here was produced by a tool in `tools/view` and can be produced again by running it.

## The claim

A closed surface holds a number of separable readings set by its own measure divided by the finest
detail reaching it, raised to the dimension of the surface. Shape does not enter and topology does
not enter. Only the measure and the resolution do.

Two consequences follow that the rest of the work leans on. What a region holds scales with the area
of its boundary and not with its volume. And a source at depth `d` inside a ball of radius `R`
reaches harmonic degree `l` as `(r/R)^l`, so depth sets bandwidth, and a source prints a patch of
angular size about `d/R` however small the source is.

## What is established

| claim | how far it holds | by what |
|---|---|---|
| depth sets bandwidth | exact, to four decimals | `sphere_field.py --check` |
| averaging direction away leaves only degree zero | exact, identically | `sphere_field.py --check` |
| the area law on a sphere | 2 to 40 dimensions, worst 0.0122% | `boundary_count.py --check` |
| the area law off a sphere | 2 to 19 dimensions, worst 2.4% | `torus_count.py --check` |
| shape does not enter | 3, 4 and 5 dimensions, spread 1.03 to 1.10 | `gpu_pack.py --check` |
| interior recovered from the boundary alone | 5 of 6 bodies, no false positives | `build_orrery_view.py` |
| a shift on a golden placement is a rigid screw | turn 9.9e-14, slide 0, pitch spread 4.3e-19 | `boundary_read.py --check` |
| deflection is rotation blind, torsion recovers the turn | 2.5e-14 against 1.8e-13 radians | `boundary_read.py --check` |
| a reading to degree `L` carries `(L+1)^2` numbers about its source | rank 81 of 256 at degree 8, 256 at degree 15 | `frame_findings.md` section 4.1 |
| the octant delta clears its redraw floor early and falls below it | 11.9% then 7.1% against a floor of 9.4% | `octant_lex.py --check` |
| the relocation rate holds near independence | 0.5215 across 63 pairs, range 0.421 to 0.619 | counted over the round frames |

## What is not established

**Shape independence above five dimensions.** The mode count has a closed form on a sphere and on a
flat torus and on no other shape here, and a cube has to be packed, and packing is where the compute
goes. A run stays honest only while the gap is well under the typical distance between two points on
the surface. Past that the count stops being what the geometry allows and becomes how many unusually
distant pairs the draw happened to contain. Holding to that limit at nineteen dimensions needs
candidates in the hundreds of millions against a kept set in the hundreds of thousands, and greedy
packing compares every candidate against every kept point. A spatial index would change the cost
from a product into something nearer a sum. That is the work that would settle it.

**Anisotropic interiors.** The boundary map on an anisotropic medium is invariant under any
diffeomorphism that fixes the boundary, and a whole family of interiors gives identical boundary data.
Motion does not rescue this by itself, since transforming the medium and its contents together
leaves the boundary data untouched. What rescues it is motion under a law: a diffeomorphism relabels
space, so straight-line motion curves and Keplerian orbits stop being Keplerian, and only the
untransformed world satisfies the law it was supposed to obey. The orrery recovery rests on exactly
this, which is worth stating plainly: it recovers radii from periods through Kepler, and a dynamical
law is doing work that geometry alone could not.

**Stability.** Uniqueness is not stability. Recovering detail at scale `x` needs precision growing
exponentially in `1/x`, so everything is recoverable in principle and buried under noise in practice.
This is visible in the tools and not only in the literature: the spectrum of a real blob dies by
degree 46, and past there the inversion divides by a gain already below one part in a million.

## Three defects the tests found

Each of these produced a plausible number. None announced itself.

**The half-integer arm of Gamma, off by two.** `Gamma(k + 1/2)` is root pi times the product of
`(2j - 1)/2`. Written with `(2j + 1)/2` it starts one step along and returns twice the right answer
at every odd argument, so the surface measure of every odd-dimensional sphere was doubled. The
constant then alternated high and low with the parity of the dimension. The cube never touches Gamma
and stayed flat, which pointed at it. A count computed from the area and checked against the
area would have agreed with itself.

**A gap chosen for runtime.** The limit on how wide a packing gap may be was written down, and then
ignored while picking gaps that would make the device saturate quickly: 0.58, 0.62 and 0.66 of the
typical separation at twelve, sixteen and nineteen dimensions. The constants came back spread by
three, seven and fourteen times and read exactly like shape-dependence. They were one gap being too
wide, on every shape at once. The limit is enforced by the tool now instead of remembered.

**A remainder tested for the wrong behavior.** The error in a lattice count oscillates while its
envelope falls, so requiring each radius to beat the one before it fails on a correct count. It did:
0.0902, 0.1736, 0.0028, 0.0256 percent. Taken over a band of radii instead of at a point, the
envelope comes down by a factor of forty-eight.

## A fourth defect: the wrong quantity held small

The packing gap has to be small against the shape's own geometry. It was instead held to a fraction
of the typical distance between two points on the surface, and in high dimensions those are not the
same requirement at all.

The separation between two points drawn on a sphere concentrates near root two whatever the
dimension is. A gap held at half of that is half the radius of curvature, and a cap that wide is
nothing like the flat disc the count assumes it is. A cube's facets are flat and suffer none of it,
so the two shapes part company and the answer reads as shape-dependence. On the device that
criterion passed a twelve dimensional run whose constants spread by 2.1 times: sphere 5.37, cube
11.41, cross-polytope 8.20.

Measured against the shape instead, at a gap of 0.12 of the typical separation and therefore well
under every radius in play, the same three shapes give 0.664, 0.644 and 0.650 at three dimensions,
0.660, 0.619 and 0.640 at four, and 0.689, 0.627 and 0.658 at five. Spread 1.03, 1.07 and 1.10.

The shape half of the claim is verified there. It is also the end of what packing reaches: five
dimensions took ten million candidates for twenty thousand kept points, and the count needed to stay
in the flat regime grows the way a packing number does. No card makes that cheap at nineteen
dimensions. It is a structural limit and never a compute budget, and the exact routes on a sphere
and on a flat torus are what reach up there.

## The flat torus

The area law was checked exactly on a sphere using the closed form for how many harmonics a degree
carries. That left shape resting on packing, since a cube has no such formula.

A flat torus has one. Glue opposite edges of a square and the eigenvalues become `(2 pi / L)^2` times
the squared length of an integer vector, so counting modes below a cutoff is counting integer points
inside a ball. The count is an integer, it holds no transcendental, and it can be taken at any
dimension by raising the every-square series to a power and adding up coefficients.

This matters because a flat torus is not a sphere in any respect that could be smuggling the answer
in. It is flat where the sphere is curved, it has a hole where the sphere has none, and its symmetry
group is a lattice where the sphere's is a rotation group. The same constant comes off both.

It also connects the count to a known-hard question. The difference between the exact lattice count
and the volume of the ball is the lattice point problem, the Gauss circle problem in two
dimensions and is open in general. So the leading term of the area law is settled here and the
remainder is somebody else's open problem and not a defect in the measurement.

## Precision

The device packer decides whether a squared distance sits under a threshold, summing squared
differences across up to nineteen coordinates. The generated PTX carries `sub.f32` and `fma.rn.f32`
and the comparisons, with no approximate reciprocal, no approximate square root and no fast-math
substitution anywhere. Fusing the multiply into the add is more accurate than separating them, not
less.

Whether single precision is sufficient was measured and not argued. The same points were packed
with the running total in single and again in double, at three, eight and nineteen dimensions across
all three shapes, and every count came back identical. Single precision is exact enough for this
decision on this arrangement, which is a fact about this arrangement and not about floating point.

## Reading the dimension off a line

A periodic structure in `n` dimensions, cut at an irrational angle and projected into fewer, comes
out quasiperiodic: never one period, but several with irrational ratios between them. Penrose
tilings are a five dimensional lattice seen in two. The correspondence runs both ways, so any
quasiperiodic pattern lifts to a periodic lattice in high enough dimension.

That turns into a measurement. The count of rationally independent periods in a one dimensional
reading equals the dimension of the lattice it was cut from. `cut_project.py --check` cuts a square
lattice at the golden slope and reads it back: two gap lengths and never three, their ratio the
golden mean to one part in ten to the fourteenth, their counts to four parts in ten thousand, no
period at any length up to half the sequence, and every strong peak named by a pair of whole numbers
against two generators. Against one generator the worst peak misses by 0.382 of it. Against two, by
six parts in ten thousand.

A boundary reading can therefore report the dimension of a structure it never had access to, by counting
how many of its periods refuse to be multiples of one another.

## The demon, priced

Laplace's demon knows the state of everything and computes the rest. It was refuted qualitatively by
quantum indeterminacy. What the work here does is price the classical failure, which turns out to be
the more useful statement.

A demon reading a boundary gets `measure / resolution^(n-1)` numbers. That is finite at any
resolution and unbounded across resolutions, so nothing stops it improving except what improvement
costs. Improvement costs exponentially: recovering detail at scale `x` needs precision growing like
the exponential of `1/x`, because the inversion divides by a gain that falls as `(r/R)^l`. In the
measurements here the spectrum dies by degree 46, and past there the division is by a number already
under one part in a million. The demon meets no wall of principle. It meets a bill.

**The distinction that matters, and it cuts against the reading this work invites.** Verifying the
area law establishes that the channel is that wide. It does not establish that the interior holds
only that much. Counted the ordinary way a volume carries `(R/x)^n` degrees of freedom while its
boundary carries `(R/x)^(n-1)`, so the boundary is short by a factor of `R/x`. The holographic
principle says the interior really is only boundary-sized and nothing is lost. That is a physical
conjecture and nothing here tests it. The pipe was measured. What has to fit through it was not.

The fork is sharp. If the holographic principle holds, a demon at the boundary has exactly enough
and its only problem is precision. If it does not, the demon is short by `R/x` however precise it
becomes, and a counting deficit is never a rounding one. No arithmetic buys it back.

There is a third pressure that applies either way. The demon is inside the region it is computing,
so its own state is written on the same boundary and counted against the same budget. A demon that
stores a description of the interior has to store it somewhere the interior can already see.

### A fourth pressure: the basis, and the object it is pointed at

The bill above is priced in precision, and precision is not the first term. It is the third.

**The basis decides how many directions come back, before precision enters.** A reading to degree
`L` carries exactly `(L+1)^2` real numbers about its source. Against a source with 256 degrees of
freedom, a demon reading to degree eight recovers 81 directions and is blind in 175, and it is blind
in them at any precision whatsoever. This is a counting shortfall of the same kind as the `R/x`
deficit and not a rounding one, so no arithmetic buys it back either. The measurement is in the
established table above: the map reaches the rank its coefficient count allows at every degree below
the source count, leaving the shortfall in coefficients to account for the blindness on its own.

That reprices the demon's problem. Raising precision moves the degree-46 wall, where the division is
already by a number under one part in a million. Raising the degree moves the rank. A demon that
buys precision without buying degree has paid the exponential bill to recover nothing it was blind
to, and the two purchases are not interchangeable.

There is a trap inside the second purchase. Degree fifteen is where `(L+1)^2` first reaches 256, and
reaching it collapses the least singular value to 3.5e-3, recovering to 1.5e-1 one degree higher. A
demon that buys the cheapest complete basis buys the worst-conditioned one, and then pays the
precision bill to undo a choice it made to save money.

**The object the basis is pointed at decides the answer before the basis does.** This one was
learned by getting it wrong here. The octant reading in the sections below returned two opposite
answers from the same instrument, the same placement and the same degree: pointed at the finalized
digest it reported a delta pinned at its noise floor and no timing information available, and
pointed at the raw working state it reported a delta clearing that floor and falling through it. The
two objects differ by adding eight constants back after each round.

A demon in that position is not short of precision and not short of coefficients. It is answering a
different question, and nothing in its own accounting shows the substitution, because the reading
still runs, still returns eight numbers that sum to one, and still produces a digest that checks
against the published value. The check that caught it counts a property the object must have: a
round only copies six of its eight words, so the carried words survive on the state and cannot
survive on the digest. Naming the object and testing the name is cheap. Both readings above cost the
same to take and one of them was worth nothing.

So the ordering for anything priced this way is: name the object and test the name, then choose the
degree against conditioning, then buy precision. Precision bought first is bought against a question
nobody has confirmed anyone is asking.

## The nesting, both directions

Every boundary is inside another one and everything a boundary holds is a boundary of its own. The
outside of a shell is the inside of the next shell out, and the contents of a shell are shells with
contents. Running outward: the cloud is inside its shell, the shell is inside the room, the room is
inside whatever holds the room, and in this case what holds it is a universe. Running inward: each
light is a closed surface, its own constituents are confined by it, and their traces smear across it
exactly as the cloud's traces smear across the shell.

Neither direction terminates on its own, and both terminate for the reader.

Downward it stops at resolution. A constituent's smear on its own small surface subtends less than
the finest detail the boundary between it and the observer can carry, so below that it is not there
to be seen, and drawing it anyway would be inventing detail no boundary holds. The recursion
stopping where resolution stops is the area law applied to the picture instead of stated about it.

Upward it stops at whatever the observer is inside. There is no vantage point outside everything,
since standing outside one boundary places the observer inside the next, and the viewer puts the
reader inside for that reason. Stepping back from a wall does not escape a
boundary. It changes which boundary is being read.

**What this is and is not.** One level was measured. A source at depth reaches degree l as (r/R)^l,
the count on that boundary follows the area law, and the same constant comes off different shapes.
That the arrangement repeats at every scale is a structural claim about the shape of the account and
never a result taken from it. It follows if the same physics holds at every scale, and that premise
was assumed and never measured.

## A lit set on the boundary, read three ways

The counting above says how many separable readings a boundary holds. This section is about reading
one lit set placed on it: where the points sit, how they push the boundary, and how they twist it.
`tools/view/boundary_read.py` holds the geometry and `docs/boundary-reading.md` is its guide. Every
number below came from `boundary_read.py --check` and `octant_lex.py --check`.

### A shift is one rigid screw

On a golden placement, shifting every index by the same amount comes to a rigid screw: a turn of
`n gamma`, an axial slide of `-2n/N`, and a pitch of `-2/(N gamma)`.

| held to | measured |
|---|---|
| the turn the screw predicts | worst error 9.9e-14 radians |
| the slide the screw predicts | worst error exactly 0 |
| the pitch across six amounts | spread 4.3e-19 |

The pitch does not depend on the amount, so one axis and one helix carry every shift. The indices a
shift runs off the end of return as a second rigid arm, a full axial extent away from where the
screw alone would put them. Where a lit point lands is fixed once the amount is known.

### Deflection and torsion split exactly

On an equal-ring placement a shift along a ring is a pure rotation, which makes it the placement to
test a rotation on. Both harmonic readings come off one coefficient table, and under that rotation
they behave as opposites.

| reading | under a rotation |
|---|---|
| deflection, the power per degree | moved by 2.5e-14 of itself |
| torsion, the phase of the same coefficients | recovered the angle to 1.8e-13 radians, sign included |

Deflection is rotation blind by construction, since power per degree is a magnitude and a magnitude
does not record how the object was turned. Torsion carries which point sits where, and its sign
gives the handedness. A caller reads the twist when the operations are rotations and reads the push
when the quantity has to survive being turned.

### The alphabet is bounded by counting, not by statistics

Splitting the boundary into eight octants and reading the share of the lit set in each gives an
alphabet of eight letters. How much such a reading can carry is settled before any measurement: a
reading to degree `L` carries exactly `(L+1)^2` real numbers about its source, whatever the source
is.

| degree | coefficients | rank | blind, against 256 | least singular value |
|---|---|---|---|---|
| 8 | 81 | 81 | 175 | 4.365 |
| 12 | 169 | 169 | 87 | 3.818 |
| 15 | 256 | 256 | 0 | 3.474e-3 |
| 16 | 289 | 256 | 0 | 1.524e-1 |

The map reaches the rank its coefficient count allows at every degree below the source count, so the
shortfall in coefficients accounts for the blindness on its own. No sample size and no precision
changes it. The eight-letter alphabet is rank 8, seven free numbers once the weight is fixed, blind
in 248 of 256 directions.

Degree fifteen is the floor, where `(L+1)^2` first reaches 256, and reaching the floor is not
reaching a usable reading. The least singular value collapses to 3.5e-3 there and recovers to
1.5e-1 at sixteen, so one degree of headroom is worth 44 times in conditioning. A reading degree
chosen by counting coefficients alone lands on the worst usable degree available.

The companion result is easy to misread. Sixty-four rounds wrote sixty-four distinct signatures, a
coherence of 100%, with no collisions. The rank says why that is close to free: seven free numbers
separate sixty-four arbitrary states nearly always, whether or not the seven carry anything about
the source. Distinctness here reports the resolution of a float and not a property of the object
being read. It is computed because a collision would have been informative, being a move the reading
cannot see. None occurred, which rules that out and establishes nothing past it.

Any count of distinct signatures quoted without the rank beside it is quoting the float.

### The delta clears its floor early and falls through it

| reading | value |
|---|---|
| round-to-round delta, first eight rounds | 11.9%, or 1.27 times the floor |
| two unrelated states of the same weight | 9.4% |
| round-to-round delta, last eight rounds | 7.1%, or 0.76 times the floor |
| first round under the floor | 5 |

The early rounds move the reading further than two unrelated states do, and the late rounds move it
less. A delta above its own independence level is not counting noise, because counting noise is the
level it cleared.

The fall is a trend in the means and not a monotone series: the first eight per-round deltas run
12.9, 14.0, 12.8, 8.4, 11.9, 14.9, 8.5 and 12.0. Round 5 is the first crossing and not the last time
the delta sits high.

Naming the move is not part of the measurement. A move carrying mass from octant to octant instead
of mixing it will raise the delta above independence, and a rigid relabeling of the indices is such
a move. Reading the early excess that way is a reading of why and has not been measured.

An earlier version of this section reported the opposite: the delta sitting at the redraw level from
round one, the churn stationary, and the alphabet too coarse to time a computation. Those were
measured on finalized digests, since `digest_after` adds the initial values back into the working
state before returning, and that feed-forward is a mixing step applied after the round. The count
gives it away, since a round only copies six of its eight words: on the working state all 378
carried words survive and on the digest none do. `docs/octant-lexicon.md` carries the withdrawal in
full.

### How much of each change the reading could see

The delta says the reading moved. It does not say how much of the change the reading was able to
move for. Two states give the same letters exactly when their difference lies in the kernel of the
map, and a change lying there is invisible however large it is.

| | visible fraction | against an unstructured draw |
|---|---|---|
| first eight rounds | 0.0397 | 1.48 times |
| last eight rounds | 0.0138 | 0.51 times |
| mean over all 63 pairs | 0.0278 | 1.04 times |

The split is the finding and the mean is not. Early changes sit in the visible directions above
chance, late changes sit in the blind ones below chance, and the mean is those cancelling. The early
to late ratio is 2.88 against the delta's 1.68 over the same split, on 8 pairs at each end, and the
sample size belongs in the same breath as the ratio.

**The two routes share no denominator, and the denominator was the objection.** The delta divides
counts by a weight that moves 4.3 bits a round, which was raised as the reason its trend might be
bookkeeping. The visible fraction is a ratio of two norms of one difference vector in raw counts,
with no such term, and it shows the trend larger. So the moving denominator was damping the effect
and not producing it.

A control arm runs first and licenses the rest. Unstructured differences must return the fraction
the row space predicts, 7 of 255 for differences holding the weight, and they return 0.0267 against
0.0275 over 200 draws. `tools/view/quotient_coherence.py` refuses to report the measurement when the
control misses.

### The relocation rate holds near independence

Counting the lit points that actually move, across all 63 consecutive pairs of working states:

| quantity | working state | finalized digest |
|---|---|---|
| set difference between consecutive states | mean 0.5215, range 0.421 to 0.619 | mean 0.4969 |
| the same in matched units, where 1.0 is independence | 1.0172 | 0.9976 |
| bits differing between consecutive states | mean 129.9 of 256 | mean 127.7 |
| what a coin would give | 128.0 | 128.0 |
| weight range across the run | 108 to 140 | 104 to 143 |
| mean change in weight per round | 4.3 bits | 9.0 bits |

A set difference between two states of weight `n` out of `N` saturates at `1 - n/N`, about one half
here, and never at one. A raw 0.5 therefore already means complete independence, and comparing a raw
figure against 1.0 compares two different quantities. That units point settled an earlier
disagreement and is the reason both columns are given in matched units as well as raw.

Consecutive states relocate the lit set about as completely as independence allows, from the first
round onward. The working state sits 1.7% above independence and the digest 0.2% below it, and the
digest's weight moves twice as far per round. That second figure is the feed-forward adding a moving
denominator on top of the round's own work. `docs/finer-alphabet.md` records the estimator that was
tried against this rate and the two reasons it failed.

## The viewers

Three pages carry the same argument in a form that can be looked at. Each writes a self-contained
file: no server, no fetch at run time, nothing to install.

`build_sphere_view.py FILE` writes a blob onto the inside of a scattering ball. A symbol's rareness
sets how hot it is and how deep it sits, so rare symbols ride near the shell and print small sharp
circles while common ones sit deep and print broad warmth. It ships the placement asked for
alongside the same sources placed at random, on the same axes, because a symbol has a rareness
without anyone choosing anything and does not have a direction. Whatever supplies one is a choice,
and a degree where the chosen map beats the null is the only place worth reading.

`build_orrery_view.py` writes a system of known radii down first and then shows only its boundary.
The interior is hidden by default, since it is the answer sheet the recovery is graded against.
Recovery is a harmonic-sum periodogram across six patches, and a period is believed where three
independent axes agree on it: five of six bodies, no false positives.

`build_room_view.py` is the dimensional viewer. The reader stands inside a dark room holding a shell
holding a cloud of confined lights, because the outside of one shell is the inside of the next and
there is no vantage point that is not inside something. The shell can be a sphere, a cube, an
octahedron or a cone, swapped under the cloud while it moves so the same population carries on
against a different wall. It squashes to a disc. A carried beam casts shadows of whatever stops it,
and beam energy decides what that is, so raising it switches shadows off one at a time. Dwell sorts
the light by how long it stayed inside. Zooming in crosses the shell and leaves the reader among the
lights; zooming out puts the room's own wall in front of them and fades it, so the wall becomes the
surface being read.

**What a reading of that field now contains.** The carried beam deposits into the same field as the
objects, through the same depth kernel, and the two sum. A boundary reading taken there is therefore
no longer the object alone, and any document quoting one has to say whether the beam is in it.

The gain is a slider with zero as the control, and the field returns to its exact former span when
it is turned back:

| beam gain | field span |
|---|---|
| off, the object alone | 6.993 |
| low | 6.66 |
| six, the chosen value | 14.45 |
| returned to zero | 6.993 |

The dip at low gain is the part worth keeping. Two fields on one boundary add, and adding can
subtract, and a beam can hide part of an object as readily as show it. A reading that got brighter is
not thereby a reading that got better. The control returning the span exactly turns that into an
answerable question instead of a matter of opinion.

## Running any of it

```
python tools/view/sphere_field.py --check      depth, conduction, direction
python tools/view/boundary_count.py --check    the area law on a sphere, exactly
python tools/view/torus_count.py --check       the area law on a flat torus, exactly
python tools/view/cut_project.py --check       a lattice dimension read off one line
powershell tools/view/build_pack.ps1           builds the device packer
python tools/view/gpu_pack.py --check          shape against shape, on the card

python tools/view/build_sphere_view.py FILE    a blob on the inside of a scattering ball
python tools/view/build_orrery_view.py         a known interior, derived back from its boundary
python tools/view/build_room_view.py           the dimensional viewer
```
