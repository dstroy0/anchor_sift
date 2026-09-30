# Rendering the object under examination

**Purpose:** Render a corpus and what the engine saw of it, as a sheet or as a volume, on whichever arm the machine has and preferring the device, and know which parts are graded and which are not.
**Scope:** `src/engine/c/render/anchor_raster.h`, `src/engine/c/render/anchor_raster.c`, `src/engine/c/render/raster_cuda.cu`, `src/engine/c/bench/bench_raster.c`, `maint/engine/build_gpu_raster.ps1`

A search produces one outcome per alignment: some probe rejected it, or every probe agreed and a full compare decided it. That sequence is already an image. This renders it, with no export step between the engine state and the pixels, in two and in three dimensions.

## The entry to call, and why it prefers the device

There are two arms behind each renderer, a host arm in C and a device arm in CUDA, and they produce the same bytes. The choice between them affects speed alone, and a caller does not make it. Call the dispatch, and it takes the device where one is present and falls back to the host where none is:

- `anchor_raster_render` for a sheet (`src/engine/c/render/anchor_raster.c:296`).
- `anchor_volume_render` for a volume (`src/engine/c/render/anchor_raster.c:539`).

Both ask `anchor_raster_device_available` or `anchor_volume_device_available` first, call the device arm, and fall back to the host arm if the device refuses. A render then happens whenever either arm can do it. The single-arm entries stay public because a grader has to call one specific arm and compare it against the other. A caller that does not care should use the dispatch.

## Building

A machine carrying a device renders on it by default. On Windows:

```
maint\engine\build_engine.ps1
```

Everywhere else:

```sh
maint/engine/build_engine.sh
```

Either one detects the toolchain, compiles the device arm where it can, builds the engine and runs the graders.

Three things have to line up for the device arm, and a bare `cmake` configure does none of them. `nvcc` drives a host compiler, which on Windows is MSVC reaching PATH through vcvars. The PowerShell script imports that environment and the shell script detects its absence and skips CUDA instead of failing. The Visual Studio generator compiles `.cu` only where the toolkit installed its MSBuild integration, which a normal install often skips and which makes CMake stop with "No CUDA toolset found". Ninja is used where it is available. And `nvcc` is frequently not on PATH even where the toolkit is installed. Both scripts search the standard locations.

Where any of that is missing the build still succeeds with the host arms and reports what it skipped. The stub arms in `anchor_raster.c` are linked instead, the `device_available` calls return 0, and the dispatch entries fall back. A skipped device is always reported.

`maint/engine/build_gpu_raster.ps1` remains for building the device arm alone against a fixed architecture. It is not needed for an ordinary build.

## Configuring a sheet render

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

A minimal render through the dispatch:

```c
AnchorRasterConfig config;
config.width = 256u;
config.height = 256u;
config.layout = ANCHOR_LAYOUT_ROWS;
config.channel = ANCHOR_CHANNEL_DEATH_LEVEL;
config.reduce = ANCHOR_REDUCE_MIN;
config.gain = 1u;

uint8_t *pixels = malloc(config.width * config.height);
anchor_raster_render(pixels, &config, corpus, corpus_len, needle, needle_len, probes, probe_count);
anchor_raster_write_pgm("field.pgm", pixels, config.width, config.height);
```

`anchor_raster_host` and `anchor_raster_device` take the same arguments and write the same bytes. A grader calls one specific arm; a caller calls `anchor_raster_render`.

## Layout, the transform applied to the object

A layout decides where an alignment lands on the page. It changes what a reader can see and changes nothing measured.

| layout                     | what it does                               | what it shows                                      |
| -------------------------- | ------------------------------------------ | -------------------------------------------------- |
| `ANCHOR_LAYOUT_ROWS`       | corpus order, left to right, top to bottom | run length, as horizontal streaks                  |
| `ANCHOR_LAYOUT_SERPENTINE` | odd rows reversed                          | locality across a row boundary, which rows break   |
| `ANCHOR_LAYOUT_COLUMNS`    | transposed through the height              | a period near the width, as a vertical stripe      |
| `ANCHOR_LAYOUT_DIAGONAL`   | each row shifted by its index              | structure aligned to either axis, by breaking both |

Every layout is a permutation of the linear cell index computed in integer arithmetic (`src/engine/c/render/anchor_raster.c:118`). A permutation cannot drop or duplicate an alignment, and `bench_raster` checks that by counting filled cells, which come out equal across all four layouts.

## Channel, the quantity a pixel carries

| channel                      | value                                                           | reading it                                          |
| ---------------------------- | --------------------------------------------------------------- | --------------------------------------------------- |
| `ANCHOR_CHANNEL_DEATH_LEVEL` | probe index that rejected the alignment                         | dark rejected early, bright survived to the compare |
| `ANCHOR_CHANNEL_SURVIVED`    | binary                                                          | bright where every probe agreed                     |
| `ANCHOR_CHANNEL_RARITY`      | rarity of the corpus byte, from the census the engine steers by | bright where the field is unusual                   |
| `ANCHOR_CHANNEL_BYTE`        | the corpus byte                                                 | the object raw, with no search applied              |
| `ANCHOR_CHANNEL_PROVEN`      | two valued                                                      | bright where the cell provably holds no occurrence  |

The proof channel differs in kind from the other four. A probe set is a sound filter. It never loses a true occurrence and it does admit alignments that are not one. The negative direction is therefore certain and the positive is not, and a cell where no alignment survived is proven to hold no occurrence.

It reduces as a conjunction, a cell staying proven only while every alignment under it was refuted. Conjunction is associative and commutative. The channel rides `ANCHOR_REDUCE_MIN` with no new reduction rule. It is monotone under refinement, since adding a probe only removes survivors, and a render never retracts a claim. It also inherits the planner's anytime property. Stop the descent anywhere and render, and every proven pixel is still proven. A death level from a half-built plan describes the plan. A proof from a half-built plan describes the object.

Brightness is not presence anywhere in this renderer and least of all here. `ANCHOR_RASTER_PROVEN` is brighter than `ANCHOR_RASTER_UNDETERMINED` and means the opposite of an occurrence. `ANCHOR_RASTER_MATCH` is the only value entitled to assert one.

Every channel is an integer read off engine state (`src/engine/c/render/anchor_raster.c:161`). None is computed in floating point and none is normalized against the image. A pixel then means the same thing in two rasters taken at different sizes.

## Reduction, and the constraint on adding one

Several alignments reach one cell whenever the object is larger than the raster. `ANCHOR_REDUCE_MIN` keeps the darkest and `ANCHOR_REDUCE_MAX` keeps the brightest.

Both are associative and commutative. That lets the device reduce with `atomicMin` or `atomicMax` in scheduler order and still reach the host's answer. A rule selecting by arrival, such as first or last writer, would make the device result depend on scheduling and could not be graded against the host at all. The header states that as a `@warning` on the enum (`src/engine/c/render/anchor_raster.h:101`), and it governs anything added to it.

## The volume, the same render in three dimensions

A volume is the sheet render with a third extent and its own set of layouts. It carries the raster's channel, reduce and gain by reference to the same enums. A channel means one thing across both, and no second definition of it exists to drift.

```c
typedef struct
{
    size_t width;
    size_t height;
    size_t depth;
    AnchorVolumeLayout layout;
    AnchorRasterChannel channel;
    AnchorRasterReduce reduce;
    uint8_t gain;
} AnchorVolumeConfig;
```

```c
AnchorVolumeConfig config;
config.width = 32u;
config.height = 32u;
config.depth = 32u;
config.layout = ANCHOR_VOLUME_MORTON;
config.channel = ANCHOR_CHANNEL_DEATH_LEVEL;
config.reduce = ANCHOR_REDUCE_MAX;
config.gain = 1u;

uint8_t *voxels = malloc(config.width * config.height * config.depth);
anchor_volume_render(voxels, &config, corpus, corpus_len, needle, needle_len, probes, probe_count,
                     NULL);
anchor_volume_write_raw("field.raw", voxels, &config);
```

`anchor_volume_write_raw` writes the block as raw unsigned bytes beside a text sidecar naming the extents, the layout and the channel, because Netpbm has no volume container and inventing one would make this tree the only reader of its own output.

The four volume layouts each map an alignment index to a voxel, and each wraps the index into the block first so the map is a bijection on it.

| layout                  | what it does                                                                                                                                                             |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ANCHOR_VOLUME_SLABS`   | corpus order, filling one sheet before the next                                                                                                                          |
| `ANCHOR_VOLUME_BOUSTRO` | every other row reversed and every other slab's rows reversed. Consecutive alignments stay adjacent across both boundaries                                               |
| `ANCHOR_VOLUME_MORTON`  | the bits of x, y and z interleaved. Locality holds on all three axes at once and the block reads as a solid. Requires the extents to be powers of two and refuses others |
| `ANCHOR_VOLUME_HELIX`   | slab major with each slab's rows sheared by its depth index, and a feature at a fixed corpus offset winds through the block                                              |

`anchor_volume_cell_for` returns the block size where the layout refuses a configuration, which is Morton on extents that are not all powers of two and any unknown layout. The host returns 0 for the whole render in that case, and the device carries the same refusal into its parallel form through a flag a thread sets when its alignment maps out of range.

## What is graded

`bench_raster` renders every combination of layout and channel for both the sheet and the volume, and compares the host arm against the device arm byte for byte. The raster is integer valued. Agreement is exact and one differing pixel or voxel is a defect. Where no device is present, the run prints the device as absent and grades the host alone. Every row then reads `host only` in its agreement column and `ok` in its verdict, and the run exits 0 (`src/engine/c/bench/bench_raster.c:203-230`, `:359-385`, `:420`). A zero exit shows device agreement only when the run printed the device as present.

The sheet: twenty combinations, four layouts by five channels, each written as a PGM. Measured on this machine, 65536 bytes of corpus, 65513 alignments, a 256 by 256 raster, needle length 24, against an RTX 3070 at `sm_86`: twenty of twenty host and device identical, every layout filling 65513 cells.

The volume: twenty combinations into a 32 by 32 by 32 block. Measured on the same machine and corpus: twenty of twenty host and device identical, every combination filling all 32768 voxels with zero collisions, which confirms each layout is a bijection onto the block.

The device arms carry their own copy of the transform and the channel, because the two arms are built by different compilers that cannot link, the same split `maint/engine/build_gpu_arm.sh` documents for the exact arm. Where a device is present, the grader compares outputs on every configuration, and a divergence between the copies fails a row. A `@warning` states this at `src/engine/c/render/raster_cuda.cu:29`.

## Frame rate, and what the number is

A pixel costs the alignment under it. The renderer costs what the search costs. A steered probe set rejects most alignments on the first read and renders faster for the same reason it searches faster.

Measured over 200 frames each, death level channel, rows layout, same object, on the `/O2` build:

| probe set          | probes | frames | seconds | frames per second |
| ------------------ | ------ | ------ | ------- | ----------------- |
| spatial, unsteered | 4      | 200    | 0.344   | 581.4             |
| steered coarms     | 2      | 200    | 0.268   | 746.3             |

Both rows are the host renderer. The timing loop calls `anchor_raster_host` (`src/engine/c/bench/bench_raster.c:265-268`). No device frame rate has been measured. Compiler optimization accounts for the difference between these figures and the ones a Debug CMake build reports.

## What is not checked here

The device arms are graded for agreement only. A render that uploads the corpus every frame pays a transfer the host does not, and nothing here measures whether the device wins once that is counted.

The sweep runs one object size against one raster size, both powers of two, with alignments larger than the cell count. Rectangles, sizes no raster divides, and alignments below the cell count are unexercised, and the column layout carries a fallback for an index that leaves the raster (`src/engine/c/render/anchor_raster.c:142-144`) which no test reaches.

Gain applies to the death level channel alone and the sweep runs it at one.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
