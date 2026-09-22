# What an arm is

An arm is a region that a reading takes one letter from. This page defines the record, giving a
viewer that draws arms and a reader that measures with them one definition instead of two.

The eight sign octants used elsewhere in this tree are one arm set among many. They were chosen for
being easy to state, easy to draw and cheap to compute, and nothing about the reading requires them.

## The record

| field | required | what it holds |
|---|---|---|
| `name` | yes | a label, so the letters of a reading can be named |
| `origin` | yes | where the arm sits, as a point. Inside the object, outside it, anywhere |
| `orientation` | yes | the frame the arm is stated in |
| `weight` | yes | a real value per placement point, the arm's response to a point being lit |
| `extent` | no | a shape that generates `weight`, kept when a shape is how the arm is stated |

`weight` is the arm. Everything else is either bookkeeping or a convenience for producing it.

## Reading with a set of arms

Given arms `A` and a lit set `S`, the letter of arm `a` is the sum of `a.weight(p)` over the lit
points `p`, divided by the count of lit points. The letters together are the reading.

Writing the arms as rows of a matrix `W`, one row per arm and one column per placement point, the
reading is `W s` for the lit indicator `s`, up to that division. Every property below is a property
of `W`.

## Three kinds of arm, and one rule covering them

| kind | weights | example |
|---|---|---|
| indicator | 0 or 1 | a sign octant. The point is in the region or it is not |
| signed | -1, 0 or 1 | the difference of two overlapping arms |
| graded | any real | an arm matched to a spherical harmonic |

The indicator arm is the special case where a membership test supplies the entire weight. Nothing in
the reading distinguishes the three kinds, and a tool that handles graded arms handles all of them
while a tool assuming membership handles only the first.

## What is free, and what is required

**Free.** The origin, inside the object or outside it. The shape. Whether arms overlap each other or
anything else. How many arms there are. Whether they cover the space. Whether they are bodies at
all.

**Required.** That the arm exists, and that its orientation is known.

The same topology rules apply to arms as to the rest of the dimensions, and shape does not enter. An
arm has to be an arm, and past that its geometry carries nothing. That statement is a measurement in
its own right, recorded in the established table of `docs/boundary-counting.md` as shape
independence.

Orientation is required for a different reason from the rest. Whether arms sit disjoint or aligned
does not matter to the reading, but the derivation uses the orientation, so it has to be recorded.
The next section is where it gets used.

## The point cloud case

An arm whose extent is a set of points and not a body is a legal arm, since only existence is
required. Its `weight` is given directly, point by point, and it has no shape to state.

This is the general case and not an exotic one. A body is a compact way of writing down a weight
function; a point cloud writes the same thing out in full. Any tool built to accept a shape and
derive weights from it should also accept weights given directly, or the general case cannot be
expressed.

## The arm and the object need not share a shape

Nothing requires an arm to resemble the thing it reads. They may be represented as different shapes,
of different dimension, and there is a great deal to learn from doing so deliberately.

This works because the topology is the shape. What identifies an arm is its topology together with
its weight, and a drawing is one realization of that. Two drawings of the same topology carrying the
same weight are the same arm, however unalike they look.

**The smallest case is a line with a dwell particle on it.** The arm's support is a line, a particle
moves along it, and how long the particle dwells at each place is the weight there. A one-dimensional
arm, reading an object of any dimension, carrying a real weight exactly as the record requires. The
point cloud arm is the same idea sampled instead of continuous.

An implementation has one decision to make here and it should make it openly: a line touches few
placement points, so the rule taking the arm's support to the placement has to be stated, whether by
incidence, by nearest point, or by a kernel of some width. That rule is part of the arm and belongs
in the record beside the weight, since two arms with the same dwell and different sampling rules are
two different arms.

**The invariance is testable and it has been tested.** If shape is a realization of topology, then
redrawing an arm as a different shape carrying the same topology and the same weight has to leave
the reading exactly unchanged. A reading that moves under such a redraw depends on the drawing, and
that is a defect in the reading. This is a null in the sense the harness uses: a move that cannot
change the answer, whose measured residual is the reading's own grain. It is built, it holds, and
the next section reports it.

Drawing one thing several ways and keeping the reading that holds is already the discipline in this
work. Free arms extend it, because the reader can now be varied as well as the picture.

## The redraw, measured

`tools/view/arm_draw.py` draws one arm set four ways and reads the same lit set with each. The set
is the eight sign octants and one graded arm carrying the height coordinate, over the 256-point
golden placement at a lit weight of 153, where one point changing arm moves a letter by 6.536e-3.
The floor it produces is reported by `null_harness` beside the other six.

A letter is a sum, and a sum hides a pair of moves that cancel inside it. Two points swapping arms
leaves both letters where they were while the arms are no longer the arms. So the comparison runs
at three levels: the weight of each arm at each point, the count of points that changed arm, and
the letter a caller reads.

| redraw | worst weight move | points reassigned | worst letter move |
|---|---|---|---|
| point cloud, record round trip | 0 | 0 of 256 | 0 |
| dwell on a line | 0 | 0 of 256 | 0 |
| rotated frame, frame carried | 2.220e-16 | 0 of 256 | 2.168e-18 |
| algebraic recombination | no arm | no arm | 2.776e-17 |

The dwell arm is the case this section was written for. Its support is the golden spiral taken as a
curve, its dwell at each place along the curve is the weight there, and its sampling rule is
incidence at integer parameter. A one-dimensional arm reading a three-dimensional object, returning
the same letters bit for bit. The curve is written with different arithmetic from the placement, so
the agreement is not two calls to one piece of code.

Recombination is listed with no arm because it declines to measure one: each octant's letter comes
back as the letter of the two-octant arm holding it minus the letter of its sibling, from two arms
neither of which is that octant.

The floor is 2.220e-16, thirteen decades under a single point crossing, and no redraw moved the
topology at all.

**One point of the 256 is outside that statement, and a pre-check finds it before any drawing
runs.** Whether a point can cross a face is settled by the placement and the arithmetic together:
take the nearest approach of any point to any face, which for a sign octant is the smallest
coordinate in absolute value, and compare it against what the drawing rounds at. Clearance far above
the rounding means no crossing is available and a clean residual is arithmetic, established without
measuring it. Clearance at or under the rounding means the sign convention decided the answer.

On this placement the clearance is exactly zero. Index 0 has longitude `0 * GOLDEN`, the sine of
exactly zero is exactly zero, and its third coordinate is exactly zero at 64, 128, 256, 512, 1024
and 4096 points alike. Under the rotated frame its carried dot product against that face came back
at +3.123e-17, so it held its arm by the sign of a rounding residual. The default lit set leaves
index 0 dark, so the letters could not have moved for it whatever the drawings did, and the check
now runs the redraws a second time with the on-face points forced lit. They agree there too.

So the reading is independent of its drawing for 255 points by measurement and for 1 by convention,
and the pre-check prints that distinction instead of leaving a clean number to imply the stronger
claim. The pre-check is the engine's, arrived at from the arithmetic floor of a rotation null
measured at eight precisions, where the residual falls 0.9861 decades per digit against a prediction
of 1.0000.

This also refuted a claim standing in `boundary_read.octant_share`, which said a face is measure
zero on a placement of this kind. A face is measure zero for a placement drawn at random. The golden
spiral is not drawn at random, and it puts a point on a face at every size.

**Four drawings that are not redraws are held against the measurement first**, since a check that
has never caught anything has not been tested. Each is an implementation somebody would write.

| drawing that is not a redraw | points reassigned | worst letter move |
|---|---|---|
| orientation dropped | 199 of 256 | 1.961e-2 |
| normalized by the arm | 0 of 256 | 5.437e-1 |
| one face nudged | 1 of 256 | 6.536e-3 |
| record at six figures | 0 of 256 | 3.268e-9 |

Two of those rows say something past the pass they record.

**Dropping the frame moves four fifths of the points and a few percent of the reading.** Stating the
arms in a rotated frame while reading the object in the original one sends 199 of 256 points to a
different arm, and the eight letters move by 3.92 percent in the units `octant_delta` reports. The
reading moves in 8 directions of 256 and a turn of the frame is mostly a move in the other 248. The
fault is caught with room to spare here, and a reading with a coarser floor would have to count the
reassigned points to catch it at all. This is the rank bound arriving as a practical hazard.

**A shortened record costs nothing on indicator arms and something on graded ones.** Writing the
weights at six significant figures cannot touch a 0 or a 1, and it moves the graded letter by
3.268e-9. An arm set of indicators alone would have passed that row while learning nothing from it,
and a graded arm is in the set for this reason.

## The object is as free as the arm

The freedom above is not one-sided. The object's transitions may be taken at any resolution wanted,
jagged or smooth, and either is representable.

Nothing in the reading distinguishes them. A reading takes a weight per point and a lit set, and
neither of those carries a smoothness requirement or a resolution with it. The instance in this tree
is at the jagged extreme, where a transition is a set of discrete bit flips and about 130 of 256
points change at once. A field moving continuously is at the other. The same arms read both, and the
machinery does not know which it has.

**Resolution is a choice, so it has to be recorded.** Two readings taken at different resolutions are
readings of two different objects, and the area law is stated over a resolution, so the count of
modes moves when the choice moves. Recording it costs nothing at the time and is unrecoverable
later. A resolution that was picked and not written down turns into a property the object appears to
have.

## Mutating the arm

The arm shape is a degree of freedom, and mutating it is a move available in the same way as mutating
the data. A search that only varies its input is varying one of the two things it could.

Two properties make this worth doing and not merely possible. The arm set is free in origin, shape,
overlap and count, which leaves a very large space of candidates. And the objective is already
written down: the report table above gives count, rank, least singular value and whether the set
tiles, so any proposed mutation can be scored before it is used instead of judged after.

What a mutation cannot do is beat the counting. Rank stays bounded by the number of independent
arms, and no shape recovers a direction that no arm reaches. What a mutation can do is buy
conditioning, reach directions a previous set was blind in, and cost less for the same rank. The two
measured baselines are what a proposal is scored against.

## Algebraic recombination

Overlapping arms combine. Where arm `A` contains arm `B`, the letter of `A` minus the letter of `B`
is the letter of the region `A` without `B`, computed and never measured again. Any region in the
Boolean algebra the arms generate is reachable this way, and so is any linear combination of arms.

Recombination is valid only when the overlap structure is known, and knowing the overlap structure
means knowing each arm's origin and orientation. The bookkeeping requirement above and this
capability are one requirement seen twice.

## What a set of arms can carry

The reading is a projection onto the span of the arm rows, so the count of directions it recovers is
the rank of `W` and no other quantity. Three consequences, each of which has caught somebody here.

**Rank is the count of independent arms.** Not the count of arms. Adding an arm that is a
combination of arms already present adds a letter and no information.

**Tiling costs exactly one degree of freedom, and only tiling does.** Arms that are disjoint and
cover the space force the letters to sum to one, leaving a set of `M` such arms carrying `M - 1`
free numbers at fixed weight. Overlapping arms carry no such constraint and hold `M`. The
seven-free-numbers figure quoted for the eight octants comes from their tiling and is not a property
of eight arms.

**Completeness is priced, not forbidden.** Recovering all `N` directions of an `N`-point source
takes `N` independent arms. No arrangement of geometry avoids that, and no precision substitutes for
it.

## What a proposed arm set has to report

| quantity | why it is asked for |
|---|---|
| count of arms | the ceiling on letters |
| rank of `W` | the ceiling on information, and the binding one |
| least singular value | what an inversion of the reading costs |
| whether the set tiles | decides whether one degree of freedom is spent on the sum |
| orientation of each arm | required for recombination, and cheap to record at build time |

Reporting the count without the rank is the error this table exists to prevent.

## Two measured baselines

Any proposed set is compared against these.

**The sign octants, as they are actually placed.** Eight indicator arms over a 256-point golden
placement. Cross products exactly zero, self products 31, 32 and 33. So the convenience is perfectly
conditioned and small: it is orthogonal, it carries rank 8, seven free at fixed weight, and it is
blind in 248 of 256 directions. Count is its whole limitation and conditioning is no part of it.

**Two hundred and fifty-six signed arms.** Each one the difference of two complementary point
clouds, taken from the rows of a Sylvester matrix of order 256. Cross products exactly zero in
integer arithmetic, self products all 256, every singular value 16.0, condition number exactly 1.
Rank 256, complete, and perfectly conditioned.

| arm set | arms | rank | blind | least singular value |
|---|---|---|---|---|
| sign octants | 8 | 8 | 248 | orthogonal, self products 31 to 33 |
| Sylvester point clouds | 256 | 256 | 0 | 16.0, condition number 1 |
| harmonics to degree 14 | 225 | 225 | 31 | 1.75 |
| harmonics to degree 15 | 256 | 256 | 0 | 3.474e-3 |
| harmonics to degree 16 | 289 | 256 | 0 | 1.524e-1 |
| harmonics to degree 17 | 324 | 256 | 0 | 2.52 |

The harmonic rows carry a notch at degree fifteen. The exactly complete degree is conditioned five
hundred times worse than the incomplete degree below it, because at fifteen the map is only just
square and its last direction is nearly dependent on the others. One degree of redundancy repairs
it. The notch appears at fifteen at every depth measured.

So an arm set chosen by counting coefficients does not merely choose badly among good options. At
degree fifteen it chooses something beaten by a cheaper reading that makes no claim to completeness.

## Depth, and what it does to a set

Depth does not change which arms are good. A source at radius fraction `r` reaches degree `l` with
gain `(r/R)^l`, and across the degrees that multiplies a whole column by close to a constant without
reordering it. Every depth measured carries the same shape: the notch at fifteen, recovered by
seventeen, flat after. Depth sets the price and the arm set sets the structure, and the choice does
not couple them.

What depth does decide is where extra arms stop being delivered. At `r/R = 0.40` the least live
singular value reads 7.605e-7 at degree 20 and 7.606e-7 at degrees 24, 28 and 32, identical to seven
figures, so the marginal value of every degree past twenty is zero. An optimizer counting those
coefficients is counting something nothing delivers.

Past a certain depth the directions are not merely expensive, they are absent. Directions go missing
at `r/R = 0.10` and not above it. Reading the same limit off the amplification instead, an arm
carrying the inverse gain amplifies the measured floor of 4.005e-16 by the same factor it amplifies
the signal, and a source deeper than `r/R = 0.094` cannot supply degree fifteen at any precision and
under any arm design. The two figures come from methods that share no code.

## Arms matched to a representation

Since the forward representation is known, an arm can be shaped as its inverse. The arm matched to
degree `l` and order `m` carries that harmonic's own pattern divided by the gain at that degree, so
the deconvolution becomes the arm's geometry instead of a step applied to measured numbers.

This moves the amplification onto known geometry, computable once at any precision, and off the
measurement. It creates no information the gain removed. The limits in the section above are where
it stops, and they are the limits to design against.

## Ownership

The generalization is Douglas's: arms of any origin, any shape, overlapping, with orientation known
for the derivation, recombining algebraically, and the point cloud case. The depth and degree sweep
is the engine's. The orthogonality measurements, the amplification limit and this schema are this
document's.
