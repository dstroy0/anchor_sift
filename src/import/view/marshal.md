# Marshal: the state of the visual tools

**Purpose:** Say what the viewer set currently is, where it disagrees with itself, and what to repair
in which order. Counts are from the directory on 2026-09-11 and every split below was read off the
files, not inferred from the README.
**Scope:** `tools/view/`, 78 entries: 23 builders, 14 templates, 12 built pages sitting beside their
sources, 11 reading modules, 8 gates, 2 build artifacts, 1 registry.
**Owner:** Douglas Quigg (dstroy0) <dquigg123@gmail.com>
**Date:** 2026-09-11

## The short version

Five disagreements, and four of them are one thing seen from different sides: a second generation of
builders arrived without adopting the first generation's conventions, and nothing in the tree
required it to.

| #   | disagreement                                             | size                    |
| --- | -------------------------------------------------------- | ----------------------- |
| 1   | two launch conventions, split by generation              | 17 against 6            |
| 2   | the opening-state contract covers a minority             | 6 of 23                 |
| 3   | the registry cannot see the new builders' output         | 17 of 23 recorded       |
| 4   | the README is a generation behind the directory          | 6 builders undocumented |
| 5   | built pages sit beside their sources, two of them broken | 12 pages                |

## 1. Launch: two conventions, and the split is generational

**Group A, 17 builders.** Hand-rolled `sys.argv` parsing, output through `out_path.resolve(...)`:
`blob`, `chart`, `field`, `orrery`, `plot`, `room`, `shadow`, `sha_clock`, `sha_pairs`, `sha_room`,
`sha_sphere`, `sound`, `sources`, `sphere`, `step`, `sweep`, `voxel`.

**Group B, 6 builders.** `argparse`, and **no `out_path` at all**: `block`, `earth`, `scope`,
`spiral`, `survey`, `blind`.

Group B is exactly the set added most recently. Neither convention is wrong on its own. What is
wrong is that a reader cannot tell which one a given builder follows without opening it, and that
nothing fails when a new builder picks neither.

**One of them is a third variant and a defect, and it is mine.** `build_blind_view.py` imports
`out_path` inside a `try` and then calls `out_path.beside("blind_view.html")`. There is no `beside`
in `out_path`; the API is `resolve`. So the call raises `AttributeError` on the happy path, or the
guard swallows the import and the destination is hardcoded. Either way the builder does not honour
the convention it appears to be reaching for.

**Repair.** `argparse` is the better of the two conventions and Group B already has it. Move Group A
onto `argparse` over time, but move **all** of Group B onto `out_path.resolve` now, because that is
one line each and it is what items 3 and 5 are waiting on.

## 2. Toolkit: the shared pieces cover a minority of the set

**Opening state.** `settings.collect(sys.argv[1:])`, which is the `--set key=value` contract and the
reason an unknown key exits with the list of known ones, is called by **6 of 23**: `blob`, `field`,
`plot`, `sound`, `sweep`, `voxel`. The other seventeen have no opening-state contract, asking for
a view instead of publishing one and describing which controls to move is possible on a quarter of
the viewers.

**Template sharing is very uneven, and the record is the only place that number lives.**

| template                    | builders filling it                                   |
| --------------------------- | ----------------------------------------------------- |
| `voxel_view_template.html`  | 6: `blob`, `field`, `plot`, `sound`, `sweep`, `voxel` |
| `room_view_template.html`   | 3: `room`, `sha_clock`, `sha_room`                    |
| `sphere_view_template.html` | 2: `sha_sphere`, `sphere`                             |
| the other 11                | 1 each                                                |

So one edit to `voxel_view_template.html` reaches six pages and one edit to `room_view_template.html`
reaches three. That is the fact `manifest.py` exists to hold, and it is right to hold it.

## 3. Integration: the registry has a blind spot it did not choose

`manifest.py` is the correct instrument and it is well built. It discovers a builder's output by

```
OUTPUT = re.compile(r'out_path\.resolve\(\s*"([^"]+)"')
```

Group B never calls that, so the record carries **no output page** for six of the twenty-three
builders. `out_path.beside` would not match either, so `build_blind_view.py` is absent for a second
reason.

This is not a fault in the registry. It is item 1 showing through: a record that reads the truth out
of the code can only see the convention the code follows. Fixing item 1 fixes this with no change to
`manifest.py`.

**The record's own prose is also behind.** `manifest.py`'s docstring opens with _Seventeen builders
fill nine templates_. It is 23 and 14.

## 4. Docs: the README describes the previous generation

`README.md` states thirty-eight files and compartments of 11 mathematics, 17 builders and 10 gates.
The directory holds 78 entries and 23 builders.

The two newest **gates** are documented: `data_check.py` and `inert_report.py`, including the
distinction that one refuses and the other prints a receipt. The six newest **builders** are not
mentioned anywhere, nor are their templates, nor `manifest.py`, nor `viewers.json`.

Their module docstrings are not the gap. Each is substantial: `block` 23 lines, `spiral` 28, `survey`
32, `scope` 37. The gap is that the directory's own documentation never learned they exist, a
reader who starts at the README is told about seventeen builders and finds twenty-three.

## 5. More, since there are more

**Twelve built pages sit beside their sources.** `sources_view`, `shadow_view`, `step_view`,
`voxel_view`, `room_view`, `sha_clock_view`, `sha_room_view`, `scope_view`, `earth_view`,
`block_view`, `survey_view`, `spiral_view`. Three of those duplicate pages that now build correctly
into `build/view/`, a reader who opens the one in `tools/view` gets a stale page with no error
anywhere.

**Two of them are known broken.** The README records `step_view.html` and `voxel_view.html` failing
`data_check` with `DATA DOES NOT PARSE AS JSON`.

**One builder cannot run at all.** `build_blind_view.py` opens
`blind_view_template.html`, which does not exist in the directory. Mine, unfinished, and it will
raise on any invocation.

**Build artifacts in the source directory.** `pack_shapes.exe` and `pack_shapes.ptx`, outputs of
`pack_shapes.cu`.

**All of the above is visible through the anchor_sift link.** `tools/view` is linked into
`anchor_sift/examples/00_blob_viz_tools/view`, where loose files in the holder are a recorded
breakage, so every stray page above is exposed twice.

## Repair order

1. **Group B onto `out_path.resolve`.** Six one-line changes. Fixes launch, fixes the registry's
   blind spot, and stops six more loose pages appearing.
2. **Finish or delete `build_blind_view.py`.** It cannot run. Write `blind_view_template.html` or
   remove the builder; a half-present tool is worse than an absent one.
3. **Remove the twelve loose pages**, after 1 so they stop returning. Deleting generated files from a
   tracked directory is a decision about the tree, so it needs your word.
4. **Rewrite the README's inventory** and correct `manifest.py`'s docstring count. Both are one pass.
5. **Extend `settings.collect` to the other seventeen builders**, or state in the README that the
   opening-state contract belongs to the six that have it. Either is honest; the present silence is
   not.
6. **Move Group A onto `argparse`.** Largest and least urgent, and nothing else waits on it.

## The daemon and the split are one project

Stated as two requests, they are one, and the reason is mechanical rather than stylistic.

**ES modules do not load from `file://`.** A browser refuses a module script over the file protocol,
so the moment the room template becomes `type="module"` it stops opening as a local file and needs
something serving it. So _split it up_ and _make it a daemon_ are the same decision: the split
cannot ship without the server, and the server has no purpose until the split.

**What the daemon buys beyond that.** Items 1, 2 and 3 of this document disappear rather than get
repaired. Twenty-three launch paths collapse to one daemon and a route per viewer, so there is no
second convention to drift into. Opening state stops being a `--set` contract bolted onto six
builders and becomes a query the route already parses. And `manifest.py` stops inferring output
paths from a regex over source code, because a route declares its own.

**What it costs, and it is not nothing.** Today every page is one self-contained file: no server, no
install, no fetch at run time, openable in five years and sendable to somebody. A module-split page
served by a daemon is none of those. That property is stated as a feature in the README and it is
the property that makes a page a deliverable rather than a session. So the daemon wants a **bake**
path kept alongside it: one command that inlines the modules and the data back into a single file,
for anything that has to travel. Without that, the split trades a thing you can hand someone for a
thing you have to run.

### The fork in the road, and it needs a decision before any code

A daemon serving live readings gets its numbers one of two ways.

**Shell out to the Python.** One implementation of the mathematics, which is the tree's own rule.
Slower per request, and the daemon becomes a process manager.

**Port the readings to JavaScript.** Fast, and it puts a second implementation of a statistic in the
tree, which is the failure the CUDA bench's own header names as mode fifteen.

**That second implementation already exists and nothing checks it.** `room_view_template.html`
carries `legendreColumn` and `harmonicsAt`; `sphere_field.py` carries `legendre_column` and
`harmonics_at`. Two independent codings of the same recurrence, in two languages, with no test
comparing their output. The room viewer has been drawing from the JavaScript copy this whole time
and the measured results come from the Python one.

So the duplication is not a risk the daemon would introduce. It is a liability the daemon is the
occasion to resolve, and the cheapest first move is a cross-check: evaluate both at the same
directions and degrees and report the worst disagreement. If they agree to the arithmetic floor, the
port is already done and the daemon can serve the JavaScript. If they do not, that is a finding about
every picture drawn so far.

### Where the daemon sits: engine to browser, and the browser holds nothing

The daemon is an engine component and not a viewer utility. Its job is the boundary between the
engine and the browser, so the browser is a display and the engine owns everything upstream of the
pixel. Two consequences follow, and one of them is not built.

**The representation is unbounded in output resolution.** A field is held as `(L+1)^2` real numbers,
121 at the ceiling the clock runs to, and those numbers reconstruct it at _any_ sample count. The
same 121 coefficients answer a thumbnail and an eight-thousand-pixel render. There is no resolution
in the representation at all, so nothing has to be re-encoded, re-meshed or re-exported to draw the
same reading larger. That is the compression claim, and it is a property of the basis rather than a
codec: the only thing that grows with the picture is the number of times the sum is evaluated.

**Antialiasing is exact rather than sampled, and this is the part worth stating carefully.** A pixel
wants the field averaged over the solid angle it covers. Supersampling estimates that average at `k`
samples for cost `k` and reaches it only in the limit. On a band-limited field the average is
available in closed form, because convolution on the sphere is multiplication in degree: averaging
against any kernel that is a function of the Laplacian is `a_lm -> K_l a_lm`, with no sampling
anywhere. Taking `K` to be the heat kernel of angular width `sigma` gives

```
tau_pixel = sigma^2 / 2
```

and one evaluation of the prefiltered field **is** the pixel's exact solid-angle average. By the
semigroup property the times add, so this is one addend in a `tau` the chain already applies and
costs nothing beyond it. The width comes from the screen-space derivative of the direction, so it
varies per pixel: a continuous level of detail with no mip chain and no transitions between levels.

**Marked as not built, and the mark is the point.** `docs/reading-transforms.md` lists this as T5 and
`not built`, alongside T10, the closed-form gradient. A search across `src/` and the CUDA tools for a
rasterizer, a framebuffer or an antialiasing path returns nothing. So the mathematics is derived and
the motivation is measured, and no engine in this tree currently produces a pixel.

The measured motivation, from `grid_error.py`: the present path draws the field through a 36 by 72
vertex mesh and lets the rasterizer interpolate, which at degree 10 puts the **surface normal** 7.47
degrees off at the median and 47.15 degrees off at the 95th percentile. Shading reads the gradient,
and a linear interpolant's gradient is constant inside a triangle. A per-pixel evaluation has no
interpolation error in either the value or the gradient, because there is no interpolation.

Two limits belong with it. The heat kernel is isotropic and a pixel's footprint near the silhouette
is stretched, a single `sigma` over-blurs across the short axis. And the exactness holds for a
band-limited field: the boundary reading is band-limited by construction, while the room's corners
and the arms are not, so those keep conventional coverage antialiasing.

### Order, if this is the direction

1. **Cross-check the two harmonic implementations.** Cheap, and it decides the fork above.
2. **Keep the six one-line `out_path` repairs anyway.** They stop the bleeding while the daemon is
   built, and a loose page appearing during a refactor is noise in the diff nobody needs.
3. **Split the room template against the 38 banner sections**, behind the two checkers that now
   exist. `OCT_SIGNS` dies here, since `docs/arm-records.md` makes its comment false.
4. **The daemon, with routes replacing builders**, and the bake path in the same commit as the first
   route so the self-contained property is never absent from the tree.
5. **Vectorizing last**, per the survey, and for its reason: a vectorized loop that drops a term
   still draws a picture and no checker in this tree reads a picture.

Items 5 and 6 of the repair order above are void if this goes ahead. Moving Group A onto `argparse`
and extending `settings.collect` to seventeen builders are both work on a launch path the daemon
replaces.

## Not settled

The phrase _perfect square_ came up while this was being marshalled and it has two readings in this
work. The reading width `(L+1)^2` is always a perfect square, which is the rank bound. The source
count 256 is also one, and the blind grid drew it as 16 by 16. Which of the two the viewer set is
meant to be squaring is a question for the owner and is not recorded anywhere in this directory.
