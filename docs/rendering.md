# Rendering the object under examination

**Purpose:** Render a corpus and what the engine saw of it, on host or device, under a configuration you choose, and know which parts are graded and which are not.
**Scope:** `src/engine/c/portable/anchor_raster.h`, `src/engine/c/portable/anchor_raster.c`, `src/engine/gpu/anchor_raster_cuda.cu`, `src/engine/c/bench/bench_raster.c`, `maint/engine/build_gpu_raster.ps1`

A search produces one outcome per alignment: some probe rejected it, or every probe agreed and a full compare decided it. That sequence is already an image. This renders it, with no export step between the engine state and the pixels.

## Building

The host arm builds with the rest of the engine and needs a C11 compiler and nothing else.

```sh
maint/engine/build_engine.sh
```

Both arms together need the CUDA toolkit and an MSVC host compiler.

```
maint/engine/build_gpu_raster.ps1
```

That script builds `build/engine_gpu/bench_raster.exe` and runs it. Without it the CMake build still produces `bench_raster`, linking the stub device arm in `anchor_raster.c:318-340`, which reports the device as absent and grades the host alone. An absent device is a skip and never a pass.

The script compiles the C sources with `cl /std:c11` and then has `nvcc` compile the device file and link the objects. The split is forced. `exact_limbs.h:77` uses `_Static_assert`, which does not exist in the C++ front end `nvcc` would route the C files through, and MSVC's default C mode does not carry it either.

## Configuring a render

Every option lives in one structure, and the same structure drives both arms.

```c
typedef struct
{
    size_t width;
    size_t height;
    AnchorRasterLayout layout;
    AnchorRasterChannel channel;
    AnchorRasterReduce reduce;
    uint8_t gain;
} AnchorRasterConfig;
```

A minimal render, host arm:

```c
AnchorRasterConfig config;
config.width = 256u;
config.height = 256u;
config.layout = ANCHOR_LAYOUT_ROWS;
config.channel = ANCHOR_CHANNEL_DEATH_LEVEL;
config.reduce = ANCHOR_REDUCE_MIN;
config.gain = 1u;

uint8_t *pixels = malloc(config.width * config.height);
anchor_raster_host(pixels, &config, corpus, corpus_len, needle, needle_len, probes, probe_count);
anchor_raster_write_pgm("field.pgm", pixels, config.width, config.height);
```

`anchor_raster_device` takes the same arguments and writes the same bytes. Ask `anchor_raster_device_available` first; it returns 0 in a build without the device arm, so a caller written against both links and runs either way.

## Layout, the transform applied to the object

A layout decides where an alignment lands on the page. It changes what a reader can see and changes nothing measured.

| layout | what it does | what it shows |
|---|---|---|
| `ANCHOR_LAYOUT_ROWS` | corpus order, left to right, top to bottom | run length, as horizontal streaks |
| `ANCHOR_LAYOUT_SERPENTINE` | odd rows reversed | locality across a row boundary, which rows break |
| `ANCHOR_LAYOUT_COLUMNS` | transposed through the height | a period near the width, as a vertical stripe |
| `ANCHOR_LAYOUT_DIAGONAL` | each row shifted by its index | structure aligned to either axis, by breaking both |

Every layout is a permutation of the linear cell index computed in integer arithmetic (`src/engine/c/portable/anchor_raster.c:97-137`). A permutation cannot drop or duplicate an alignment, and `bench_raster` checks that by counting filled cells, which come out equal across all four layouts.

## Channel, the quantity a pixel carries

| channel | value | reading it |
|---|---|---|
| `ANCHOR_CHANNEL_DEATH_LEVEL` | probe index that rejected the alignment | dark rejected early, bright survived to the compare |
| `ANCHOR_CHANNEL_SURVIVED` | binary | bright where every probe agreed |
| `ANCHOR_CHANNEL_RARITY` | rarity of the corpus byte, from the census the engine steers by | bright where the field is unusual |
| `ANCHOR_CHANNEL_BYTE` | the corpus byte | the object raw, with no search applied |
| `ANCHOR_CHANNEL_PROVEN` | two valued | bright where the cell provably holds no occurrence |

The proof channel differs in kind from the other four. A probe set is a sound filter, so it never loses a true occurrence and it does admit alignments that are not one. The negative direction is therefore certain and the positive is not, and a cell where no alignment survived holds no occurrence as a proof rather than as a summary.

It reduces as a conjunction, a cell staying proven only while every alignment under it was refuted, and conjunction is associative and commutative, so it rides `ANCHOR_REDUCE_MIN` with no new reduction rule. It is monotone under refinement, since adding a probe only removes survivors, so a render never retracts a claim. And it inherits the planner's anytime property: stop the descent anywhere, render, and every proven pixel is still proven. A death level from a half-built plan describes the plan. A proof from a half-built plan describes the object.

Brightness is not presence anywhere in this renderer and least of all here. `ANCHOR_RASTER_PROVEN` is brighter than `ANCHOR_RASTER_UNDETERMINED` and means the opposite of an occurrence. `ANCHOR_RASTER_MATCH` is the only value entitled to assert one.

Every channel is an integer read off engine state (`src/engine/c/portable/anchor_raster.c:139-183`). None is computed in floating point and none is normalized against the image, so a pixel means the same thing in two rasters taken at different sizes.

## Reduction, and the constraint on adding one

Several alignments reach one cell whenever the object is larger than the raster. `ANCHOR_REDUCE_MIN` keeps the darkest and `ANCHOR_REDUCE_MAX` keeps the brightest.

Both are associative and commutative, which is what lets the device reduce with `atomicMin` or `atomicMax` in scheduler order and still reach the host's answer. A rule selecting by arrival, such as first or last writer, would make the device result depend on scheduling and could not be graded against the host at all. The header states that as a `@warning` on the enum and it governs anything added to it.

## What is graded

`bench_raster` renders all twenty combinations of layout and channel, writes each as a PGM, and compares the host raster against the device one byte for byte. The raster is integer valued, so agreement is exact and one differing pixel is a defect. Measured on this machine, 65536 bytes of corpus, 65513 alignments, a 256 by 256 raster, needle length 24, built by `maint/engine/build_gpu_raster.ps1` against an RTX 3070 at `sm_86`: twenty of twenty identical, and every layout filled 65513 cells.

The device arm reimplements the transform and the channel rather than linking the host's, because the two are built by different compilers that cannot link. The grader comparing outputs on every configuration is what keeps the copies honest, and the file says so in a `@warning` (`src/engine/gpu/anchor_raster_cuda.cu:30-33`).

## Frame rate, and what the number is

A pixel costs the alignment under it, so the renderer costs what the search costs. A steered probe set rejects most alignments on the first read and renders faster for the same reason it searches faster.

Measured over 200 frames each, death level channel, rows layout, same object, on the `/O2` build produced by `build_gpu_raster.ps1`:

| probe set | probes | frames | seconds | frames per second |
|---|---|---|---|---|
| spatial, unsteered | 4 | 200 | 0.344 | 581.4 |
| steered coarms | 2 | 200 | 0.268 | 746.3 |

**This is the host renderer in both rows.** The timing loop calls `anchor_raster_host` (`src/engine/c/bench/bench_raster.c:236-241`). No device frame rate has been measured, and the difference between these figures and the ones a Debug CMake build reports is compiler optimization rather than hardware.

## What is not checked here

The device arm is graded for agreement and not for speed. A render that uploads the corpus every frame pays a transfer the host does not, and nothing here measures whether the device wins once that is counted.

The sweep runs one object size against one raster size, both powers of two, with alignments larger than the cell count. Rectangles, sizes no raster divides, and alignments below the cell count are unexercised, and the column layout carries a fallback for an index that leaves the raster (`src/engine/c/portable/anchor_raster.c:117-121`) which no test reaches.

Gain applies to the death level channel alone and the sweep runs it at one.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
