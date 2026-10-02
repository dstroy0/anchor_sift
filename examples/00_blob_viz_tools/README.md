# Viewers

Each is a Python builder plus an HTML template. The builder computes its numbers and hands them to
`generate_template.py`, which writes them into the template's one data slot as a JSON literal, inlines
the shared tools the template names, and emits a single self-contained file: no server, no install,
no fetch at run time. Standard library only.

## What is general and what belongs to this tree

The general ones take their input as an argument and open nothing else. They are the toolkit
candidates. The rest hardcode a path into this repository and are examples of the pattern,
not tools:

| general                           | reads                                       |
| --------------------------------- | ------------------------------------------- |
| `build_blob_view.py`              | any file you name                           |
| `build_field_view.py`             | any long-format table you name              |
| `build_chart_view.py`             | any table you name                          |
| `build_plot_view.py`              | an expression you type                      |
| `build_sound_view.py`             | a wav you name, or its own generated signal |
| `build_sweep_view.py`             | the same, swept across analysis settings    |
| `build_shapes_view.py`            | nothing; the page samples every shape       |
| `dsp.py` `exact.py` `settings.py` | shared, no inputs of their own              |
| `generate_template.py` `toolbox/` | shared, no inputs of their own              |

| stays here                                                           | why                                          |
| -------------------------------------------------------------------- | -------------------------------------------- |
| `build_voxel_view.py` `build_shadow_view.py` `build_sources_view.py` | open `build/bench/*.csv`, which `bench_sac` writes |
| `make_shadow_figure.py`                                              | opens `build/bench/shadows.csv`              |
| `build_step_view.py`                                                 | traces SHA-256, which is this tree's subject |

Checked by opening each one and never by pattern: `make_shadow_figure.py` reads as general to a
grep for `build/bench` because it builds the path with two nested `dirname` calls, and it is not.

## Opening state

Every general generator takes `--set key=value`, repeatable. A caller asks for a view instead of
publishing one and describing which controls to move. An unknown key exits with the list of known
ones, because a typo is otherwise silent and the page just opens looking wrong.

```
python build_blob_view.py file.bin --set shape=hilbert --set spin=0.3 --set theme=dark
python build_field_view.py data.csv --set floor=20 --set order=64 --set contrast=0.35
```

Settings cover the step and representation, the transform, the overlay, the ramp and contrast, box
opacity, the observer as yaw, pitch and distance, and spin in turns per minute.

## Solids

```
python build_blob_view.py FILE                 any binary, eight readings of its bytes
python build_field_view.py TABLE.csv           any long-format table
python build_plot_view.py "sin(x)*cos(y)"      an expression over a grid
```

All three write the same page: the data as a mesh you turn, 32 representations, 9 transforms.
Height and color are the value.

The readouts box holds the distribution. Drag it to select a range, click for one bin; matching
cells light up with a count and a share. Click a cell in the object and its value is marked on the
distribution.

## Flat charts

```
python build_chart_view.py TABLE.csv
python build_chart_view.py TABLE.csv --x time --y temperature pressure
python build_chart_view.py long.csv --split sensor --y value --kind scatter
```

Line, scatter, step, bar, area. Hover reads the nearest point, drag zooms x, double click resets,
series toggle off, y switches to log. It prints which columns it chose, making a wrong guess visible.

## One hash

```
python build_step_view.py --bit 96
```

Two SHA-256 traces, a message and the same message with one bit flipped, every intermediate kept.

## One generator, one toolbox

```
python generate_template.py foo_view_template.html --data foo.json --out foo_view.html
python generate_template.py --verify foo_view.html
python generate_template.py --check
```

A page is a template plus the tools it names. `generate_template.py` reads `<!--TOOL name-->` lines from the
template, resolves what each tool requires from `toolbox/manifest.tsv`, and inlines every piece into one file under
a label naming its toolbox path. `--verify` holds each labeled piece in a built page to its toolbox file byte for
byte. The generator and the toolbox import nothing else from this tree.

| toolbox          | holds                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------- |
| `theme.css`      | the dark and light themes and the one set of controls: buttons, fields, sliders, switches, folding sections |
| `ui/toolbar`     | the floating toolbar: a menu button that grows into folding sections of controls       |
| `ui/bar`         | the bar the blob viz units mount: one control per setting, from the schema `settings.py` writes |
| `core/watch`     | the frame watch every looping page runs under, read in one call as `window.__loopHealth` |
| `core/`          | the device, bind groups and streaming, the sine table and angles, the settings scheme, the clock with vsync, 4 by 4 matrices |
| `volume/`        | the `.vbo`/`.ibo` object, its compaction kernels and the shared drawing code           |
| `shapes/`        | run boxes, lines, the 2D map, smooth blobs, every parametric surface and transform, the Hilbert and Morton curves, a harmonic field, a float mesh |
| `copyright.html` | the line every built page carries, stamped by `generate_template.stamp`                |

Every template here builds this way, and every page that draws frame by frame hands its loop to `core/watch`.
The engine view, the shapes gallery and the blind directions take their look and their controls from the toolbox
as well:

```
python ../cell_tracking/maint/build_engine_view.py
python build_shapes_view.py --set shape=klein --set transform=twist
python build_blind_view.py --degree 8 --count 256
```

The gallery draws every shape the toolbox makes on the shared core: every surface under every transform, the
curves as the paths they trace, and the field painted on any of them or raised from it. The engine view and the
gallery need WebGPU, Chrome 113 or later. Each has a vsync switch, on by default; off, it draws as fast as the card
finishes and reports the frames it drew per second. The blind page sets the source weights of each singular
direction beside the boundary field they produce, on equal-area maps with one scale across every direction.

The tissue room, `view/track_room.html`, is built from `track_room_template.html` with no data and served by
`view/serve_room.py`, which hands it its samples and slices.

The engine view draws what the tracker writes. The sample is open: a mouse intestinal organoid imaged by light-sheet
over time, from "Reference OME-Zarr for 3D time-lapse light-sheet microscopy with nuclei tracking",
doi:10.5281/zenodo.22078388, under CC BY 4.0. `fetch_open_sample.py` fetches it, checks it against the record's MD5
and lays its raw OME-Zarr out as `build/data/source/organoid_001.ome.zarr`, with the record's nucleus tracks beside it
in voxels as the answer key, `organoid_001.geff`. Ingest turns the image into a crystal,
`build/data/set/organoid_001/organoid_001.kcr`, reading the nuclei on channel 1 (`input.channel` in the `.cfg`).
A tracker run with an object output, `--object <directory>` or `"object"` in the `.cfg`, writes the sample's `.vbo`
(header, frames, leaves, cells, runs and the run's `.cfg`) and `.ibo` (links and edges). `base.cfg` writes them to
`build/view/data`, and `view/serve_room.py` serves that folder at `data/`, lists it at `/objects` and serves the raw
slices from the source beside it:

```
cd ../cell_tracking
python maint/fetch_open_sample.py
bash build_driver.sh
../build/track_driver.exe --cfg base.cfg --ingest
../build/track_driver.exe --cfg base.cfg
python ../00_blob_viz_tools/view/serve_room.py
```

Then open `http://127.0.0.1:8733/engine_view.html`.

## On representations

A representation decides where a cell sits. Joining the ends of an axis says the last value is next
to the first, which is a period the picture adds. The plane joins nothing. Keep the reading that
holds up when it is drawn several ways.

## Boundaries

What a closed surface can hold, and what can be read back off it. These carry checks that fail.
Run the check before trusting the picture.

```
python sphere_field.py --check          the harmonics, the depth law, the null
python boundary_count.py --check        the area law on a sphere, exactly, to 40 dimensions
python torus_count.py --check           the same law on a flat torus, by counting lattice points
```

A source at radius r inside a ball reaches harmonic degree l as (r/R)^l. Depth sets bandwidth and
a source prints a patch of angular size about d/R however small it is. A spot on a boundary is
always wider than the thing that made it. Counting the modes that survive gives an area law: the
count goes as the surface measure over the resolution, raised to the dimension of the surface, and
never as the volume.

```
python build_sphere_view.py FILE        a blob written onto the inside of a scattering ball
python build_orrery_view.py             a known system inside, derived back from the boundary alone
python build_room_view.py               a dark room, a carried beam, and a shell you can pass through
```

`build_sphere_view.py` ships the placement you asked for alongside the same sources placed at
random, on the same axes. A symbol has a rareness without anyone choosing anything; it does not have
a direction. Whatever supplies one is a choice, and a degree where the chosen map beats the null
is the only place worth reading.

`build_orrery_view.py` writes the interior down first and then shows only the surface, and a viewer
that draws a convincing picture and recovers the wrong radius is caught in the same glance. Recovery
is a harmonic-sum periodogram across six patches, and a period is believed where three independent
axes agree on it.

`build_room_view.py` puts the reader inside, because the outside of one shell is the inside of the
next. The shell is a window to whoever is outside and a wall to everything within. Dwell sorts the
light by how long it stayed: early light went straight and prints an edge, late light arrives from
everywhere and fills the shadow it would have cast.

### On the card

```
powershell build_pack.ps1               builds the packer, importing vcvars for nvcc
python gpu_pack.py --check              shape against shape, packed on the device
```

Spherical harmonics settle the dimension half of the area law and live only on spheres. Shape has
to be packed. The device counts and does nothing else: every measure, constant and verdict is
computed on the host from closed forms that never read a count.

A packing count means something only while the gap stays well under the typical distance between two
points on the surface. Past that the count stops being what the geometry allows and becomes how many
unusually distant pairs the draw happened to hold. The tool enforces that limit and errors instead of reporting
a row outside it, which is worth more than the row.

## The mathematics

The pages are drawings of what these modules compute. A page shows what a reading
carries; the module decides what a reading can carry at all, and `reading_rank.py` puts a ceiling on
that which no amount of drawing moves.

### sphere_field.py -- the boundary field

A source of strength `q` at radius `r` and direction `n` contributes to the boundary coefficients

```
a_lm += q K_l(r) Y*_lm(n),      K_l(r) = (r/R)^l exp(-l(l+1) tau)
```

so the map from sources to coefficients is **linear** and a field of many sources is a sum that
never needs solving. Both factors of the kernel are diagonal in the degree: depth reweights degree
by degree, conduction does the same, and neither moves power between degrees. That diagonality is
Laplace's, and it reduces all of the physics between a source and the boundary to one number per
degree. `theory/workbooks/orior/reading-transforms.md` tabulates every transform with this property and the one that
lacks it.

Power per degree is `P_l = sum over m of a_lm^2`, invariant under all of `SO(3)` because the
degree-`l` subspace carries a unitary irreducible representation of the rotation group.

**Synthesis is separable and the saving is large.** The sum splits into a Legendre part depending
only on the colatitude and a trigonometric part depending only on the longitude. A grid therefore costs
`rows x 121 + points x 21` instead of `points x 121`: under a million multiplications where the
direct form takes twenty million.

`legendre_column` climbs the diagonal and then recurs in degree, which holds every intermediate at
unit scale. Built from factorials instead it overflows above degree 150 and loses digits long before
that, and it loses them quietly, with the low degrees staying right while the fine structure goes
wrong.

Also here: Gauss-Legendre quadrature, the zonal profile and cap radius of a single source, whether
two sources overlap at a level, and `live_modes` against a floor that a caller supplies.

### boundary_read.py -- lit points on a boundary

The golden placement puts index `k` of `N` at height `1 - 2(k + 1/2)/N` and longitude `k gamma`, with
`gamma = pi (3 - sqrt 5)`.

**An index shift is one rigid screw.** Shifting every index by `n` advances longitude by `n gamma`
and height by `-2n/N`, a rotation about the polar axis composed with a slide along it, of pitch

```
slide / turn = (-2n/N) / (n gamma) = -2 / (N gamma)
```

**independent of `n`**. One axis and one pitch therefore describe every shift amount, and the
amounts differ only in how far along the one helix they travel. Measured at `N = 256` over six
amounts: worst turn error `9.948e-14` radians, worst slide error exactly zero, pitch spread
`4.337e-19`.

**Deflection and torsion are an exact split.** Turning the lit set by `alpha` about the polar axis
sends `a_lm` to `a_lm exp(-i m alpha)`. The magnitude `P_l` does not move. Deflection is
intrinsic and cannot see how the object is turned. The phase `arg a_lm` moves by exactly
`-m alpha`, sign included. Torsion recovers the angle and its sign is the handedness. Measured:
deflection moved `2.539e-14`, torsion recovered the angle to `1.803e-13` radians.

**A face is not measure zero on this placement.** A face is measure zero for a placement drawn at
random, and the golden spiral is not drawn at random: index 0 has longitude `0 * gamma`, exactly zero. Its third coordinate is exactly zero
and it sits on the `z` face at every size checked from 64 through 4096. The shares sum to one because
the convention assigns every point to exactly one octant.

### reading_rank.py -- what a reading cannot carry

**A reading to degree `L` carries exactly `(L+1)^2` real numbers about its source, whatever the
source is.** The lit set here has 256 degrees of freedom. Where `(L+1)^2 < 256` the reading is a
linear map of rank at most `(L+1)^2` from a 256-dimensional space and its null space has dimension
at least the shortfall. Every direction in that null space is a change to the object that moves no
coefficient at all.

| degree | coefficients | rank | blind   | least kept |
| ------ | ------------ | ---- | ------- | ---------- |
| 8      | 81           | 81   | **175** | 4.365      |
| 12     | 169          | 169  | 87      | 3.818      |
| 15     | 256          | 256  | **0**   | 3.474e-3   |
| 16     | 289          | 256  | 0       | 1.524e-1   |

**Completeness of count and health of conditioning are separate properties.** Degree 15 is where
`(L+1)^2` first reaches 256, and its least kept singular value collapses three decades below the
values beside it; one degree of headroom buys a factor of 44 in conditioning.

`depth_rank` therefore reports **absent** and **present but badly conditioned** as different
outcomes, since one is a wall and the other is a bill. `gram_residual` establishes that precision is
not the limit: the basis is orthonormal to `2.2e-14` at degree 15 under exact quadrature. The
reading degree is a choice.

### boundary_count.py -- the area law, by two routes

The claim: a boundary holds a number of separable readings set by its own measure divided by the
finest detail reaching it, raised to the dimension of the boundary, and **shape does not enter**.

The test is real because the two routes share no step. One counts by packing, dropping points on the
surface and keeping those further than one resolution from everything already kept, a direct measure
of how many distinguishable places the surface has. The other takes the measure in closed form from
the shape's own geometry. Neither reads the other. A packing count that tracked the volume, or a
shape whose corners held more readings than its faces, would show up as a constant that moves.
Checked on a sphere, a cube and an octahedron, and in dimensions two through six.

### torus_count.py -- the same law, exactly, on a shape that shares nothing with a sphere

Glue the opposite edges of a square. The Laplacian's eigenvalues on the result are `(2 pi / L)^2`
times the squared length of an integer vector. Counting modes below a cutoff is counting integer
points inside a ball. The number of integer vectors of squared length exactly `m` in `d` dimensions
is the coefficient of `q^m` in the `d`-th power of the series carrying a term for every square.
The count is whole numbers throughout with no transcendental in it, at any dimension.

A flat torus is not a sphere in any respect that could smuggle the answer in: flat where the sphere
is curved, holed where the sphere is not, and its symmetry group is a lattice where the sphere's is a
rotation group. The same constant off both is shape and topology failing to matter, arrived at
exactly instead of sampled.

### cut_project.py -- reading a dimension off a line

A periodic structure in `n` dimensions, sliced at an irrational angle and projected into fewer, comes
out quasiperiodic: never one period, but several with irrational ratios between them. Penrose tilings
are a five-dimensional lattice seen in two, icosahedral quasicrystals six seen in three, and the
correspondence runs both ways, any quasiperiodic pattern lifts to a periodic lattice in high
enough dimension. That gives a measurement:

```
the count of rationally independent periods in a one dimensional reading
  equals the dimension of the lattice it was cut from
```

Two independent periods means a two-dimensional lattice at minimum. One means the thing was already
periodic and nothing was hidden. A boundary reading can therefore report the dimension of a structure it
never had access to, by counting how many of its periods refuse to be multiples of one another. A
square lattice cut at the golden slope gives the Fibonacci chain, checked against exact values.

### octant_lex.py -- the eight-letter alphabet

Split space by the sign of each coordinate. The eight regions tile with no gap and no overlap, and on
the boundary they cut eight spherical triangles with **three** right angles each. By Girard's
theorem the area of a spherical triangle is its angle excess,

```
A = 3 pi / 2 - pi = pi / 2,      8 x pi/2 = 4 pi
```

the area of the sphere. The tiling is exact and the pieces congruent. No letter is larger than
another by construction; the measured shares total `1.000000000000000`.

The alphabet is the fraction of the lit set in each octant, one word of eight numbers per state. It
is **rank 8, blind in 248 of 256 directions**, and at fixed weight the shares carry one constraint
and leave seven free numbers. Seven real numbers will separate sixty-four arbitrary states whether or
not the seven mean anything. Distinctness at that sample size is not evidence.

### quotient_coherence.py -- how much of a change the alphabet could see

A difference `d` between two states is visible only in the row space of the reading map. With `P` the
projection onto that row space, the visible fraction is

```
||P d||^2 / ||d||^2
```

and coherence has to be defined on the quotient by the null space, or it counts invisible differences
as differences.

**The baseline depends on the constraint and the two answers differ.** For unconstrained differences
it is `8/256`. For weight-preserving differences it is `7/255`, because the eight octant indicators
sum to the all-ones vector, all-ones lies in the row space and one dimension of the difference
space is spent. Verified over 20,000 draws: `0.03132` unconstrained against a predicted `8/256 =
0.03125`, and `0.02751` weight-preserving against a predicted `7/255 = 0.02745`.

### arm_draw.py -- does a reading depend on how the arm was drawn

One arm drawn several ways, read against the same lit set. A reading that changes when only the
drawing changes is reporting the drawing.

**Compared at three levels, and the aggregate alone is one level too few.** A letter is a sum, and a
sum hides a pair of moves that cancel inside it: two points swapping arms leaves both letters exactly
where they were while the arms are no longer the arms. So the per-point weight, the count of points
reassigned, and the letter are all reported.

| redraw                         | weight    | points reassigned | letter    |
| ------------------------------ | --------- | ----------------- | --------- |
| point cloud, record round trip | 0         | 0 of 256          | 0         |
| dwell on a line                | 0         | 0 of 256          | 0         |
| rotated frame, frame carried   | 2.220e-16 | 0 of 256          | 2.168e-18 |
| algebraic recombination        | no arm    | no arm            | 2.776e-17 |

**A clearance pre-check decides the rotated case before it is run.** Min over placement points of the
distance to the nearest arm face is `0.000e+00` at index 0, structurally, at every size from 64 to 4096. A crossing is therefore available and a clean result is not established by clearance; under the
carried rotation index 0 held its arm by a dot product of `+3.123e-17`, three parts in `1e17` from
going the other way. The claim the module makes is therefore the narrow one: independent of its
drawing for 255 points by measurement and for one by convention, printed as that split.

**The frame fault is smaller in the letters than it has any right to be.** Stating the arms in a
rotated frame while reading the object in the original one sends **199 of 256** points to a different
arm, and the eight letters move **3.92 percent**. Four fifths of the points relocate and the reading
barely registers it, because the move lives mostly in the 248 directions the alphabet is blind in.
That is the rank bound arriving as a hazard somebody could ship, and it is why the point count is
reported beside the letter.

### dsp.py and exact.py -- two transforms, and why there are two

`dsp.py` is the fast path: FFT, windows and signal sources, standard library only, shared by
`build_sound_view.py` and `build_sweep_view.py`.

`exact.py` is for when float64 is the thing being measured. A double carries 53 bits of mantissa,
putting the arithmetic's own noise floor around 300 dB down, far below anything in a recording and
far above nothing. When the question is what the analysis invents instead of what the signal
contains, the transform has to be quieter than the effect being looked for. Everything in it is
`decimal.Decimal` at a precision the caller chooses, and pi, sine and cosine are computed there
instead of looked up, because `math` has no more precision to give than the double it returns.

Cost grows steeply: a 256-point transform at 1024 bits is seconds and a 4096-point transform at the
same precision is minutes. That is the price of the floor, and it is why the fast path stays the
default.

`examples/proofing/precision_floor.py` is this module's argument applied to the boundary reading, and it
reaches the same conclusion by measurement: the residual of a rotation null falls 0.9861 decades per
digit of precision against a prediction of exactly 1.0000. A reported floor of `4.005e-16`
belongs to float64 and not to the reading.

## The gates

| tool                    | what it refuses                                                                                                                                                |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `null_harness.py`       | A threshold picked by judgment. Runs a move that changes nothing and reads the residual, after proving itself against a deliberately broken null. Six floors. |
| `grid_error.py`         | The drawn picture standing in for the field. Measures the mesh against exact evaluation.                                                                       |
| `script_check.py`       | A page whose script does not parse, and a page with a frame loop and no watch on it.                                                                           |
| `parity_check.py`       | The bar and the scheme judging one setting two ways, and a frame watch that does not report a throw or a loop that stops.                                      |
| `generate_template.py`  | A built page whose toolbox pieces differ from the toolbox, and a template with two data slots or a script left open.                                           |
| `data_check.py`         | A page whose script reads a key its own data does not carry, with no guard on the read.                                                                        |
| `inert_report.py`       | Refuses nothing. Prints which of a page's optional features came out inert, telling a reader before they open it.                                              |
| `frame_audit.py`        | An allocation on the per-frame path, and a disposal of something built once.                                                                                   |
| `gpu_pack.py`           | The device packer's answers, graded across shapes and dimensions.                                                                                              |
| `out_path.py`           | A tool writing its page beside itself.                                                                                                                         |
| `settings.py`           | An unknown `--set` key, which is otherwise silent.                                                                                                             |
| `make_shadow_figure.py` | Renders the residue shadow as a character map for the research paper.                                                                                                    |

**`grid_error.py` in one line.** Interpolating a wave of length `lambda` over a step `h` is wrong by
about `(pi h / lambda)^2 / 2`, and a degree-`l` harmonic has length `360/l` degrees. At degree 10 on
the 36 by 72 grid the value error is 5.9 percent of the picture's contrast at worst and 1.1 percent
typical, while the **surface normal** is 7.47 degrees off at the median and 47.15 degrees off at the
95th percentile. Shading reads the gradient and a linear interpolant's gradient is constant inside a
triangle. The normal is the column that shows. Halving the step divides the error by 3.95 against
a predicted 4.

**`null_harness.py` and what its floors are.** The power-under-rotation floor reads `4.005e-16`.
That is the correct threshold to hand a caller running in float64, and it is not a property of the
boundary: the law puts that residual at exactly zero. See `precision_floor.py`.

**`inert_report.py` prints a receipt, and it fails nothing. That distinction is the design.** A room
page built without a `clock` key is not defective. Every read of that key in the template is
guarded, a clock-less room is a supported mode, and `data_check` is right to pass it. What a
reader needs is to be told which half of the page is asleep. This prints `this page has no
clock, no sources` and returns nothing anybody can fail on. It reports guarded absences only,
because an unguarded one is `data_check`'s finding and reporting it twice would grade one page by
two rules. The guard analysis is imported from `data_check` for the same reason.
