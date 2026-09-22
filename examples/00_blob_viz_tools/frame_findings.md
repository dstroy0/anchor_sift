# Findings, 2026-09-10

Raw record. Every finding from one session on the boundary reading and the viewer that draws it,
written for transcription into the documents and the book instead of as a document itself.

Ordered by kind and not by importance. Each entry carries what was measured, what it means, and
where the number came from, leaving every claim checkable against the thing that produced it.

Sections:

1. Defects that fail silently
2. Verified not defects
3. Tooling gaps
4. Measurements
5. Corrections to things I said earlier
6. Open, not fixed

---

## 1. Defects that fail silently

Every entry here shares one property, and it is the reason they are grouped: **none of them raises
an error, and none is visible in a screenshot.** A reviewer looking at something else does not find
them, and the two tools in section 3 exist for that reason.

### 1.1 A shared GPU resource freed on teardown

`dropSource()` called `dispose()` on the spray cone's geometry and its material. Both are built
once at the top level and shared by every source, and that sharing is the whole reason a source
costs one aimed point cloud instead of a new one.

**Symptom:** remove one source and the spray stops on *all* of them. No error, no warning, and the
picture simply stops moving.

**Severity: high.** A freed buffer is not a degraded buffer. The lamp beside it does own its
geometry and material, so the same function was right about one object and wrong about the other,
and that split is what made it hard to see.

**Fixed.** Removing the mesh from the scene covers everything that teardown owns.

### 1.2 A truthiness test on a string of characters

The octant share counter tested `if (!frame[k])` to skip a clear bit. A frame is a string of `"0"`
and `"1"`, and every non-empty string is truthy in this language, `"0"` included.

**Symptom:** every clear bit counted as set. The share table would have been the placement's
distribution instead of the state's, and it would have looked entirely plausible: eight numbers,
totalling one, changing as the clock advanced.

**Caught before it shipped**, by writing the comparison against `charCodeAt` out of habit and then
noticing the version above it did not.

### 1.3 The label rail sorted on a value from the previous frame

`layoutRail()` sorts labels by their target's screen position, and that position was written during
placement, which runs *after* the sort.

**Why one frame matters:** the rail's entire claim to being crossing-free is that it lays labels out
in the same left-to-right order as their targets. A stale order is a different order. On a
turning view the rail therefore produced exactly the crossings it exists to prevent, and it did so
while its own comment explained why it could not.

**Fixed** by projecting every target before the sort: project, lay out, place, untangle, draw.

### 1.4 A panel narrower than its own row contract

A control row is a label at 78px, a slider with an 84px minimum and a value at 60px, plus two 7px
gaps and 22px of padding: 258px. The panel was 248px.

**Symptom:** every slider in the panel squeezed 10px under its own stated minimum, and the flex line
overflowing its box. Written as a literal, nothing warns and the row simply shrinks.

**Fixed** by deriving the width from the contract, and a label that grows now widens the panel instead of
crushing the slider.

### 1.5 Additive blending against a pale ground

The engine arms were drawn with additive blending. They sit inside pale shells, and adding a
mid-tone color to a pale background changes almost nothing.

**Symptom:** every check said the geometry was present -- in the scene, visible, 24 segments
drawn, reaching well past the object, projecting to coordinates inside the viewport -- and the
picture showed no arms.

Worth recording as its own entry because the diagnostic path was long and every instrument along it
reported success. The fault was not in any of the things being checked.

**Fixed** with normal blending, and the depth test turned off because an arm is a frame standing
around a body.

### 1.6 Allocation on the per-frame path, five sites

Found by walking the call graph outward from the animation loop.

| site | rate | cost |
|---|---|---|
| `legendreColumn` | once per order per direction | ~6,900 arrays a second |
| `layoutRail` | once per frame | one array, one closure |
| `untangle` | once per frame | one array |
| `tracePierce` | ten times a second | one array, one closure |
| `applyEnergy` | once per tick | one `THREE.Color` |
| `magnified` | once per tick | one array |

`legendreColumn` carries the cost. It is the innermost thing on the whole reading: a reading
to degree ten calls it eleven times per direction, and the beam field evaluates one direction per
deposit on every retrace. Sixty-three deposits at ten retraces a second is close to seven thousand
short-lived arrays a second.

**None of these drops a frame.** They raise the collection rate, and a collection landing inside a
retrace stutters the picture somewhere unrelated to its cause.

**All six fixed**, reused buffers with named comparators. One caution recorded with the fix: a
reused Legendre buffer must be cleared to its used length, because a stale value in a slot the
recursion does not reach becomes a wrong harmonic, and a quiet one.

### 1.7 Two independent times on one slider

`dwell` drove which half of the light budget is spent, how long a particle's tail is, **and** how
long the boundary holds what it recorded. The first two belong to the moving thing. The third
belongs to the surface.

**Consequence:** asking for a longer tail also wiped the boundary's memory, and a short-tailed
particle writing a long-lived record was not a state the page could be put into. A reader could not
have discovered this; the control simply did not exist.

**Fixed**, two axes.

### 1.8 Conduction pinned at the build value

Depth is one of the two kernels between a source and the boundary and conduction is the other, and
only depth had a control. `tau` was whatever the build chose, with no way to move it.

**Fixed**, and the slider's ceiling is *derived* from the build value so its home position lands on
exactly the tau the page was generated with. Picked as a round number it would land near it, and the
page would open a couple of percent away from its own reading with nothing saying so.

---

## 2. Verified not defects

Recorded because each one costs a reader the same time to clear, and clearing it twice is waste.

**`markMesh.count = mark`** is bounded. `layMark` returns early at `mark >= MARK_MAX`, so the count
can never exceed the buffer. This is the site that *did* fail once, at a buffer of sixty against a
bundle wanting more, so it reads as suspicious and is now correct.

**`stoppers.count` and `passers.count`** are bounded. Both meshes are sized `COUNT`, and every bit
lands in exactly one of the two lists, so the two counts total `COUNT` and neither can exceed it.

**`buildBeamField` and `sized()`** allocate only when the requested width differs from the held
one. That is the correct pattern and never a finding. An audit reports them because a pattern cannot
see the guard.

---

## 3. Tooling gaps

### 3.1 Nothing parsed the page's own script

The builders check that the template did not leave a script tag open. That is the only thing about
the script they check.

**A page whose tags balance and whose JavaScript does not parse therefore builds without
complaint**,
writes its file, prints its summary and reports its digest -- and then renders a blank canvas,
because the whole script died on the first token that did not fit. Every edit to a 3,546 line
template was one typo away from that, discoverable only by opening the page, and nobody opens it
once the builder has said it succeeded.

**Closed:** `tools/view/script_check.py`. Nine templates, every one parses, the largest 3,546 lines.
A missing `node` is reported and never treated as a pass, because a check that cannot run is not a
check that passed.

### 3.2 Nothing looked for allocation or for disposal of a shared resource

Two faults of that class were found in one afternoon and **neither was found by looking for it.**

**Closed:** `tools/view/frame_audit.py`. It walks the call graph from the frame loop outward, and a
helper three calls deep is reported at the depth it sits at, and it fails on a disposal of anything
built once at the top level. It reports allocations without failing on them, because a site's cost
depends on how often it runs, and a reader decides that where a pattern cannot.

### 3.3 The name guard covers one tree

The guard lives outside this tree, at a machine-local path the hook reads from an untracked file,
and it is enforced by a pre-commit hook in this tree only.
A copy promoted into the shared toolkit lands outside its reach.

**Shape:** a check that silently stops applying to code that did not change. Same shape as the gate
roots gap a peer captain found: a whole directory in none of three root lists, and the run that
found it read 61 files and called them all clean.

**Not fixed.** It is a decision about the shared toolkit and not mine to make.

### 3.4 The pre-commit hook covers four trees and not six

It gates `docs`, `theory`, `README.md` and the prose. It does not gate `tools` or `src`.

**Not fixed.**

---

## 4. Measurements

### 4.1 The rank of a boundary reading

**A reading to degree L carries exactly (L+1)^2 real numbers about its source, whatever the source
is.** The lit set has 256 degrees of freedom.

| degree | coefficients | rank | blind | least kept |
|---|---|---|---|---|
| 4 | 25 | 25 | 231 | 4.495 |
| 8 | 81 | 81 | 175 | 4.365 |
| 12 | 169 | 169 | 87 | 3.818 |
| 15 | 256 | 256 | 0 | 3.474e-3 |
| 16 | 289 | 256 | 0 | 1.524e-1 |

Measured at full depth and no conduction, the most favourable case: both kernels sit below one and
both are diagonal, so either can only shrink a singular value. The map reaches the rank its
coefficient count allows at every degree below the source count, leaving the shortfall in coefficients as the
entire cause of the blindness.

Three consequences, each a number:

- **Degree eight recovers 81 of 256.** No sample size, no precision and no number of beams completes
  it.
- **Degree fifteen is the floor**, where (L+1)^2 first reaches 256. Below it the blindness is forced
  by counting alone.
- **Reaching the floor is not reaching a usable reading.** The least singular value collapses to
  3.5e-3 at fifteen and recovers to 1.5e-1 at sixteen. One degree of headroom is worth 44x in
  conditioning.

**The eight-letter alphabet is rank 8**, seven free numbers at fixed weight, blind in 248 of 256
directions.

### 4.2 The basis, and what does not limit it

Orthonormal to 2.2e-14 at degree 15 under exact quadrature (Gauss-Legendre in the cosine of the
colatitude, trapezoid in longitude, both at orders that integrate a product of two degree-L
harmonics exactly). Degrees 4 and 8 read 2.2e-14 and 1.8e-14.

**Precision is not what holds the reading at degree eight.** The degree is a choice.

### 4.3 The screw

At N = 256 over six shift amounts: worst turn error 9.948e-14 rad, worst slide error exactly 0,
pitch -0.003255258, **spread of the pitch 4.337e-19**.

The pitch is `-2/(N*gamma)`, independent of the shift amount, so one axis and one pitch describe
every amount. This is an identity and the numbers are the check on the arithmetic.

### 4.4 Deflection against torsion

Under one rotation: deflection moved by **2.539e-14**, torsion recovered the angle to **1.803e-13**
radians.

Power per degree is invariant under all of SO(3), because the degree-l subspace carries a unitary
irreducible representation. Phase moves by exactly `-m*alpha`, sign included, and the sign is the
handedness.

### 4.5 The octant tiling

Eight congruent spherical triangles, three right angles each, area `pi/2` by Girard, eight of them
totalling `4*pi`. Measured shares total **1.000000000000000**. Determinants split **4 at +1 and 4 at
-1**, so the eight frames divide evenly between rotations of the first and rotations with a mirror
in them.

### 4.6 The delta, on the state

| | delta | against the floor |
|---|---|---|
| first eight rounds | 11.9% | 1.27x |
| last rounds | 7.1% | 0.76x |
| redraw floor, unrelated states | 9.4% | 1.00x |

Twist between round one and round sixty-four: 4.715210 rad.

### 4.7 The object read, against the object intended

Carried words matching, over the six words each round copies:

| read | matching |
|---|---|
| the round's working state | **378 of 378** |
| the finalized digest | **0 of 378** |

The finalization adds the initial vector back modulo 2^32 and destroys the structure being looked
for.

### 4.8 The beam in the field

Field span: **6.993** object alone, **6.66** at a low coupling gain, **14.45** at the chosen gain of
six. Returning the gain to zero restores 6.993 exactly.

The dip is destructive interference. Two fields on one boundary add, and adding can subtract, and a
beam can hide part of an object as easily as reveal it.

---

## 5. Corrections to things I said earlier

**On the degree ceiling.** I said `legendre_column`'s mantissa sets the degree ceiling on every
harmonic reading, and made it the first priority of the precision work. The basis measurement says
otherwise: it is orthonormal to 2.2e-14 at degree fifteen, the degree a complete reading
needs. The mantissa argument holds only for readings much deeper than that. **The priority argument
was wrong and the reading degree is a choice, not a precision limit.**

**On coherence.** I reported sixty-four distinct signatures from sixty-four rounds as coherence. The
rank says seven free numbers, and seven reals separate sixty-four arbitrary states whether or not
the seven carry meaning. **The separation was free and I reported it as a result.**

**On the octant delta.** Three assertions withdrawn before the fourth stood, each asserting a
*level* -- a ramp, a stationary value, a floor -- for a quantity that has a *trend*.

**On saturation.** Overturned by the object, not the statistic: every version of that measurement
read the finalized digest.

---

## 6. Open, not fixed

**The room clipping at distance, with a named suspect and the toggle that settles it.** Straight
edges cut the room's sphere when the observer stands well outside it. Ruled out by measurement, and
each of these stays ruled out: frustum culling, since the room is in the frustum at every distance
from 7.1 to 312; the camera's far plane, at 432 against 1200; back-face culling, since `wallStuff`
is already `DoubleSide`; and the light's falloff distance at 192.

The suspect is the shadow, and it was missed because the wrong dimension of it was checked. The
sources are `THREE.PointLight` with `castShadow` true, and a point light's shadow in this library is
a **cube** map: six faces rendered through one ninety-degree camera, `near` 0.35, `far` 264, bias
-0.0022, on a room of radius 120 that has `receiveShadow` true. The six face boundaries land on the
room's inner sphere as seams, and a seam on a sphere is a straight edge. The earlier check compared
the shadow camera's far plane against the room's far wall, 192 against 139, which says nothing about
where the faces meet.

It also predicts the distance dependence without needing a second mechanism. From inside the room a
reader sees one face's worth of wall. From outside, and the observer travels to `ROOM * 2.6`, the
whole sphere is in view and every seam is visible at once.

**This is a hypothesis and the tree already carries the control that decides it.** Four predictions,
in the order they are worth running:

1. **Turn shadow casting off.** The `cast` checkbox already drives `light.castShadow` for every
   source. If the edges go, it is the shadow and nothing else. If they stay, this section is wrong.
2. **Move a source and hold the observer still.** The cube is oriented in the light's frame, so a
   shadow seam moves with the source. A tessellation or depth artifact is fixed to the room.
3. The pattern should carry cube symmetry, meeting at eight points, and should not line up with the
   room's own 72 by 48 tessellation.
4. Raising `SHADOW_MAP` should soften the edges without removing them, and changing `shadow.bias`
   should move them.

Prediction 2 is the discriminator: whether the pattern belongs to the light or to the room. Written
down before running any of it, because a cause named from reading the source is a guess until the
suspect is switched off and something disappears.

**The null calibration.** Closed. `tools/view/null_harness.py` ships a known-null move per reading
and reports its residual, and it proves itself on a deliberately broken null before it will report
any floor at all. Three of the six nulls come back exactly zero. The one worth carrying forward is
the power reading under rotation at 4.005e-16, since `sphere_field.power` has claimed independence
of orientation in its own docstring since it was written and nothing had tested it.

**The 1e-16 claim in the item above was wrong, and it was mine.** I wrote that integer counts over
an integer weight have a true null near 1e-16 and called `coherence()` ten decades coarse. The grain
is not 1e-16. It is exactly zero: identical integer counts over an identical integer weight give
identical floats, and there is no residual to allow for.

The live statement is better than the one it replaces. At fixed weight the smallest move the reading
can register is 1/weight, about 6.5e-3 here, and a threshold at 1e-6 sits far below anything the
reading is able to do and filters nothing, because there is nothing to filter. Across states of
differing weight two signatures can approach arbitrarily closely -- 62/124 and 63/126 are both
exactly one half -- so the threshold does have a job, and the job is deciding which unequal-weight
states count as the same signature. **That is a modelling choice and it is currently stated as
precision.**

Recorded this way because the correction came from measuring the null instead of reasoning about it,
and the harness exists for that reason.

**Coherence on the quotient.** Still open. Computed on the raw signature, counting invisible
directions as though they were visible. The rank work says exactly which directions those are, so
the measurement is now well posed: decompose each state-to-state difference into the part lying in
the reading's row space and the part lying in its null space, and report the visible fraction. For
the eight-letter alphabet the row space is the span of the eight octant indicators, so the visible
part of a difference is its per-octant means, and no other component of it. A difference drawn at random would
put about 8 of 256 of its energy there.

**The reading above degree eight.** Not run on the hash.

**The packing spread of 1.03 to 1.10**, which carries no error bar at all.

**Shape independence**, holding only at dimensions three to five and untested outside them.

**The include map** for the seven benches, needed before the set can be adopted file by file.

**The name guard and the hook roots**, sections 3.3 and 3.4.
