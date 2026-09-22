# Reading a lit set on a boundary

`tools/view/boundary_read.py` takes a set of lit points on a sphere and returns three readings of
where those points sit, how they push the boundary, and how they twist it. Nothing in the module
knows what a lit point means, so the same code serves a hash state, a solar system or a file of
bytes without changing. The caller supplies the meaning.

This page is written for someone lifting the module into another tree. Every number below came from
`python tools/view/boundary_read.py --check` and can be produced again by running it.

## What has to come with it

Two files and the standard library. `boundary_read.py` reaches into `sphere_field.py` at a single
call, `legendre_column`, and `sphere_field.py` imports `math` and `sys`. There is no third
dependency, no build step and nothing to install.

Two further files are worth taking and neither is required to run anything. `null_harness.py`
measures the floor under each reading and imports both of the others. Lift it if the readings are
going to carry thresholds, since the alternative is choosing them. `arm_draw.py` holds the arm
record and several drawings of one arm set, and the harness imports it for the redraw floor. Lift
that one if the reader is going to take arms as data.

## Placements

A placement decides where index `k` sits on the sphere. The choice shapes what can be read, so both
of them are offered and neither is a default.

| placement | where index `k` goes | what it is good for |
|---|---|---|
| `golden_place(count)` | height `1 - 2(k + 0.5)/count`, longitude `k gamma` | even coverage with no seam and no pole pile |
| `ring_place(rings, width)` | `rings` latitudes of equal width, `width` longitudes on each | a shift along a ring is a pure rotation |

`golden_place` carries the property the screw below depends on: one step in the index is one fixed
rigid move, the same move everywhere along the spiral. `ring_place` puts its latitudes at the
interiors of the bands, so no ring lands on a pole where every point of it would pile into one
place. Pick the ring placement when the operation under test is a rotation and the golden placement
when the operation is a shift of the index.

`as_angles(points)` converts either one into the colatitude and longitude pairs the readings want.

## Readings

All three readings come off one table. `complex_coefficients(angles, live, top)` sums the boundary
coefficients of the lit set once, and the two harmonic readings take that table apart in different
directions.

| reading | call | what it answers |
|---|---|---|
| deflection | `deflection(table, top)` | how much power the lit set carries at each degree |
| torsion | `torsion(table, top)` | the phase of the same coefficients, by degree and order |
| octant share | `octant_share(points, live)` | what fraction of the set sits in each of the eight octants |

Moving every longitude by `alpha` multiplies the entry at order `m` by `exp(-i m alpha)`. The
magnitude holds still and the phase moves by `m alpha`. Deflection reads the magnitudes and torsion
reads the phases, and a turn moves the phases while leaving the magnitudes alone.

## Choosing between deflection and torsion

Deflection is blind to a rotation by construction. Power per degree is a magnitude, and a magnitude
does not record how the object was turned. Torsion measures the turn, and its sign gives the
handedness.

The check moves a lit set along its rings by seven different amounts and reads both:

| reading | what it did under a rotation |
|---|---|
| deflection | moved by 2.5e-14 of itself, which is nothing |
| torsion | recovered the angle to 1.8e-13 radians, sign included |

The split is exact in both directions, so the choice is not a matter of taste. A caller whose
operations are rotations reads the twist. A caller who wants a quantity that holds still while the
object turns reads the push. A caller who does not yet know which of those they have should read
both and keep whichever one carries a signal.

`turn_between(before, after, order=1)` performs the recovery, returning radians in the direction the
longitudes run. Order one is asked by default because it pins the angle down without a wrap of its
own; a higher order divides the angle and returns it only up to its own fraction of a turn. It
returns `None` when neither set has a usable entry at that order, which is a real outcome and not an
error to swallow.

## The octant reading

`octant_share(points, live)` splits space into eight regions by the sign of each coordinate. Every
region has a trilateral right-angle corner at the origin, all eight corners meet at that one point,
and on the boundary the same split cuts eight congruent spherical triangles of area `pi/2` each, by
Girard, totalling `4 pi`. The measured shares sum to 1.000000000000000.

The eight sign frames are not all the same kind of move. Their determinants split four at `+1` and
four at `-1`, so half are rotations of the first octant and half carry a mirror. A caller reading
handedness off this split should know it is there before relying on it.

`octant_delta(before, after)` reports how much of the reading moved between two shares, as a
percentage of the whole. It is halved, because a share that leaves one octant arrives in another and
the two ends of a single move would otherwise be counted twice.

Eight regions is a small alphabet, and how small is a counting fact and not a judgment. The
reading is rank 8, seven free numbers once the weight is fixed, and against a source with 256
degrees of freedom it moves in 8 directions and is blind in 248. A caller should know that number before
building on this call, and should know that distinctness under such a reading is close to free: seven
reals separate any few dozen arbitrary states whether or not the seven carry anything.

`docs/octant-lexicon.md` records what the alphabet did when it was pointed at a computation,
including a conclusion that was withdrawn when the object it read turned out to be the wrong one.

## The screw

`screw_of(count, amount)` returns the rigid move that shifting every index by `amount` comes to on a
golden placement: a turn, an axial slide, and the pitch, the slide per unit of turn.

On 256 points the pitch is `-0.003255258` whatever the amount is. Across the six amounts the check
tries, the spread between the largest pitch and the smallest is 4.3e-19. That is the floating point
grain and carries no dependence on the amount. One axis and one pitch therefore serve every shift,
and a shift comes to a slide of the whole pattern along one fixed helix.

`wrap_arm(count, amount)` names the indices a shift runs off the end of. They return as a second
rigid arm, a full axial extent away from where the screw alone would put them. A shift is the screw
plus that arm, and where a lit point lands is fixed once the amount is known.

## What it costs

`complex_coefficients` is the expensive call. It walks the lit set once per order and computes a
Legendre column per point, so the work grows as the lit count times `top` squared. Degree eight over
a few hundred lit points is immediate. A caller wanting a much higher degree should form the table
once and hand it to both readings, the shape the module is already written in.

`legendre_column` climbs the diagonal and then recurs in degree, keeping every intermediate at unit
scale. Computing the same values from factorials overflows above degree about 150 and loses digits
well before that, and it fails quietly: the low degrees stay right while the fine structure goes
wrong. The recurrence is there to prevent a picture that looks plausible and is not.

## Choosing the degree

The degree is a choice about how much a reading carries, and not a limit the arithmetic imposes. The
basis measures orthonormal to 2.2e-14 at degree fifteen under exact quadrature, and to 1.8e-14 at
degree eight, so precision is not what holds a reading at any degree a caller is likely to want. The
overflow above is a real ceiling and it sits an order of magnitude beyond that.

What does bound the reading is counting. A reading to degree `L` carries exactly `(L+1)^2` real
numbers about its source, and against a source with `N` degrees of freedom it is blind in `N -
(L+1)^2` directions at any precision whatsoever.

| degree | coefficients | rank against 256 | blind | least singular value |
|---|---|---|---|---|
| 8 | 81 | 81 | 175 | 4.365 |
| 12 | 169 | 169 | 87 | 3.818 |
| 15 | 256 | 256 | 0 | 3.474e-3 |
| 16 | 289 | 256 | 0 | 1.524e-1 |

Pick the degree against the last column and never against the second. The smallest complete basis is
degree fifteen, where `(L+1)^2` first reaches 256, and it is the worst-conditioned usable one: the
least singular value collapses to 3.5e-3 there and recovers to 1.5e-1 one degree higher, putting the
worth of a single degree of headroom at 44 times in conditioning. A caller who picks the cheapest complete basis
pays for that saving in precision afterwards.

## The floors these readings sit on

Every reading here has a move that cannot change it, and running that move gives the reading's own
grain in the units it reports. `tools/view/null_harness.py` ships one such move per reading and
reports the residual. A threshold is then measured and never picked.

| reading | the move that cannot change it | residual |
|---|---|---|
| deflection | a rotation of the whole set | 2.539e-14 |
| torsion | a rotation by a whole turn | exactly 0 |
| octant share | a lit point relabelled inside its own octant | exactly 0 |
| octant delta | a reading against itself | exactly 0 |
| screw pitch | changing the shift amount | 4.337e-19 |
| spectrum power | a rotation of the sources | 4.005e-16 |
| a reading over arms | the arms redrawn as different shapes at the same weight | 2.220e-16 |

The last row is a null over the reader instead of over the object. An arm is identified by its
topology together with its weight, and a shape is one realization of that, so drawing the arms
differently while holding the weight cannot move a letter. `tools/view/arm_draw.py` draws one set
four ways, including as a line with a dwell particle on it, and no placement point changed arm under
any of them. `docs/arm-records.md` reports it in full.

Three of the seven are exactly zero and not merely small, because the moves are exact on integers. The
octant reading has no continuum of small changes at all: a share is a count over a weight and both
are integers, and at fixed weight the smallest change it can register is `1/weight`. Two states of
*differing* weight can still give shares arbitrarily close together, leaving a caller who compares
across weights to make a modelling choice about which states count as the same. Say that plainly
instead of calling it a tolerance.

The companion measurement is not a null. Torsion recovers a known angle to 1.803e-13 radians, which
asks whether the reading moves the right amount when something did happen. A null asks whether it
holds still when nothing did. A reading wants both answers and they are different questions.

## Running the check

```
python tools/view/boundary_read.py --check
python tools/view/null_harness.py --check
python tools/view/arm_draw.py --check
```

The first holds the placement to the screw it should be, holds deflection and torsion to their
opposite behavior under a rotation, and holds the eight octant shares to a sum of one.

The second measures the floors above, and before it reports any of them it hands itself a move that
is not a null while declaring that it is, and a genuine null of the same shape. It has to catch the
first and stay quiet on the second, and it withholds every floor and fails if either misbehaves. A
checker that has never caught its own defect is a checker nobody has tested.

The third reports the redraw row at each of its three levels and holds four drawings that are not
redraws against itself first. It is called by the second, so running it separately is for reading
the detail and not for coverage.

Exit status is zero when all of them pass. Running any of the modules without `--check` prints its
own documentation, since all of them are libraries and have no work of their own to do.
