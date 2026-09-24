# The engine

**Purpose:** how to use the engine: its calls and errors, one body on one lattice, n bodies across frames, the record
machine with its programs and its config, and the daemon that shares a device among processes. Every name, limit and
file below is read from this tree. The file table and the text from "The exact integer" on are anchor_sift's: its
commands and its `src/`, `maint/`, `docs/` and `build/` paths are in anchor_sift's tree.

**Scope:** `engine/`. What calls the engine lives outside it, and this file names such a caller only where the engine
itself depends on it.

## The six steps

| step | from → to | what happens |
|---|---|---|
| 1 ingest | a source → lanes | read any source format into 16-bit lanes in key order, with its side bytes |
| 2 seal | lanes → signa | the dimensional Merkle DAG over rows, planes, volumes and lanes, and the witness against the source |
| 3 lift | lanes ↔ crystal | the tower lifts the lattice into the stored stream, and lowers it back exactly |
| 4 measure | lattice → fields | the residual, the moments, the entropy windows |
| 5 partition | fields → bodies | the component tree and its cut into bodies |
| 6 relate | bodies × frames → links | overlap, matching, motion, division, the links between frames |

## Where things live

A module's place depends on whether its request carries a body count.

- `base/` never sees a body. It holds the lattice, its representation and codecs, the tower, the seal, exact
  arithmetic, the measures of the lattice itself, and the scheduler.
- `nbody/` is defined over n ≥ 1 bodies, n = 1 being its base case. There is no single-body folder, because one body
  is the case n = 1, not a separate machine.
- `daemon/` holds tessera, the one daemon per device that admits every process's device jobs
  ([daemon/README.md](daemon/README.md)).
- `prg_sch/` holds the programs and schedules that compose the two: the cfgs, the run programs and the answer key.
  [prg_sch/README.md](prg_sch/README.md) is how to write a program for the machine.
- `render/` draws any step's state as a sheet or a volume.
- `sims/` holds the simulations. Each builds a lattice whose answer is known and grades a measurement against it, on
  the device, in exact integers.

`engine.cu`, `engine.h` and `engine_config.h` sit at the top. `engine.cu` is the entry layer and the only file that
reaches every module. `engine.h` declares its calls, and `engine_config.h` the types every module shares.

# General use

## Building

The engine is CUDA C++ with C modules, compiled by `nvcc`. No script under `engine/` builds `engine.cu` itself: the
program that links the engine compiles `engine.cu` and the modules it reaches. The scripts here build and run parts of
it:

| script | builds and runs |
|---|---|
| `daemon/test/run.sh` | the tessera suite (ledger, frame, measure, job), and the daemon into the run's build directory |
| `sims/run.sh <sim> [-- arguments]` | one sim, its modules, the tessera client, and a daemon beside the sim. The sims are `nbody_lattice`, `noise_floor`, `period_power`, `root_universal`, `ask_state`, `ka_psi`, `chaitin_omega`, `fixed_pattern` and `classify_reject_recover`. Each prints its readings and exits 0 only when every check holds |
| `base/obsignatio/test/run.sh` | the seal against its test vectors (`test_vectors.json`) |
| `CMakeLists.txt` | the C side only: the exact integer, the sift, the renderer, their arms and the benches. None of the CUDA engine |

The sims pick the device architecture from `nvidia-smi` (`sm_<compute capability>`, else `sm_86`), or take it from
`SIM_ARCHES`. On Windows they embed `long_paths.manifest` into each binary; paths past 260 characters open.
`ENGINE_PATH_ROOM` is 32,768 bytes on Windows and `PATH_MAX` elsewhere, taken from `<linux/limits.h>` on Linux.

**One header this tree does not hold.** `nbody/bodies`, `nbody/group_objects`, `nbody/link_objects`,
`nbody/relate_frames`, `prg_sch/run_cfg`, `prg_sch/run_log` and `prg_sch/answer_key` include `track.h`, the tracker's
header. It declares their frame, rule and buffer types (`TreeFrame`, `TreeRules`, `EngineBuffers`, `StageClock`). A
copy of `engine/` without it builds everything else.

## Calls and results

Every call that can fail returns `ENGINE_REFUSED` (−1) on failure. On success it returns 0 or a count: the bits of a
key, the lanes swept or the bodies found. Each module has its own refusal of the same value (`CYCLE_REFUSED`,
`MAX_TREE_REFUSED`, `TESSERA_REFUSED`, …).

| purpose | calls |
|---|---|
| the lattice machine | `engine_key_imprint`, `engine_key_release` |
| the record machine | `engine_record_imprint`, `engine_record_sweep`, `engine_record_host` |
| the residual | `engine_residual`, `engine_residual_tally` |
| one frame's bodies | `engine_frame_bodies`, `engine_bodies_tally`, `engine_group_voxels` |
| sources | `engine_source_find`, `engine_source_lanes`, `engine_source_samples`, `engine_source_read` |
| the set | `engine_sample_path`, `engine_set_samples`, `engine_ingest_set`, `engine_ingest_print`, `engine_iapx_prove_set`, `engine_prove_print`, `engine_iapx_head`, `engine_iapx_load`, `engine_side_release` |
| entropy | `engine_entropy_set`, `engine_entropy_cloud`, `engine_entropy_history_read`, `engine_entropy_history_release` |
| the body table | `engine_bodies_write`, `engine_bodies_read`, `engine_bodies_release` |
| a truth graph | `engine_geff_read`, `engine_geff_release` |
| paths | `engine_directories_make`, `engine_program_directory` |
| errors and helpers | `engine_error_read`, `engine_error_clear`, `engine_percent_of`, `engine_order_keys`, `engine_sort_unique` |

`iapx` in a call's name is the crystal's old suffix. The file those calls read and write is `.kcr`
(`ENTRY_CRYSTAL_SUFFIX`, `engine.cu`).

## Errors

A call takes an `EngineError`, either as an argument or in its request, and the caller zeroes it first. It is
**first write wins**: `engine_error_raise` fills the error only while its kind is `ENGINE_ERROR_NONE`; the error
names the first thing that failed, and nothing after it overwrites that.

| field | holds |
|---|---|
| `kind` | `ENGINE_ERROR_REQUEST` (1, the caller asked for something the call refuses), `ENGINE_ERROR_RESOURCE` (2, memory, a CUDA call or a file failed; `status` is the CUDA status or `errno`) or `ENGINE_ERROR_LOGIC` (3, a check the engine proves did not hold, such as a rebuilt voxel that differs) |
| `module` | the `EngineModule` that raised it: engine 0, max_tree 1, flatten 2, decimal_double 3, unit_sweep 4, cycle 5, keymath 6, key_schedule 7, residual 8, grow 9, apxrep 10, compression 11, tower 12, entropy_history 13, zip 14, npy 15, dicom 16, obsignatio 17, tessera 18, period 19 |
| `site` | the source line of the check that failed |
| `execaddr` | the return address inside the check, the code that failed |
| `evacaddr` | the address of the object the check was about |
| `imagebase` | the loaded image's base; both addresses resolve as offsets into the binary |
| `frames`, `frame_count` | return addresses added by `engine_error_frame` as the failure passes back out, up to `ENGINE_ERROR_FRAMES` (16) |

The set, body, entropy and frame entries also keep the first error they raise in a copy for the whole process.
`engine_error_read` returns that copy, and `engine_error_clear` empties it.

# Single body: one lattice

## Sources

`engine_source_find(source, sample, …)` looks for `<source>/<sample>` with each suffix in turn: `.ome.zarr`, `.zarr`,
`.n5`, `.ome.tiff`, `.ome.tif`, `.tiff`, `.tif`, `.hdf5`, `.h5`, `.ims`, `.npz`, `.npy`, `.nhdr`, `.nrrd`, `.nii.gz`,
`.nii`, `.hdr`, `.stack`. When `source` is a file, it is an archive, and the sample names a member of it. The readers
are `base/zarr`, `zip`, `tiff`, `hdf5`, `npy`, `nrrd`, `nifti`, `dicom` and `stack`, and the codecs they call are
`base/blosc`, `zstd`, `lz4`, `snappy`, `inflate`.

`engine_source_read` reads one source whole into 16-bit lanes in t z y x order:

- **Axes.** The source's axes are named by its metadata, or by the request's `axes` string (the `.cfg`'s `input.axes`),
  one letter per axis. The letters are `t`, `z`, `y` and `x`, each used at most once. A `c` may stand only where its size
  is 1. A missing axis has extent 1.
- **Elements.** 8-bit and 16-bit integers are read. A float is refused. A signed element is offset by 2^15 exactly, and
  `lane_offset` returns 0x8000.
- **Side bytes.** Everything the source holds besides the voxels comes back in `EngineSideBytes`: each member's name,
  bytes, CRC and length, and where its pixels lie.

`engine_source_lanes` gives a sample's lane count from its shape alone and reads no voxel. `engine_source_samples`
lists a source directory's samples, sorted.

## The set and its crystal

A set is a directory with one folder per sample. The crystal of a sample is at `<set>/<sample>/<sample>.kcr`
(`engine_sample_path`), and `engine_set_samples` lists every sample that has one.

```c
EngineError error = {0};
EngineSampleRecord records[count];
EngineSetReport report = {records};
const EngineIngestRequest ingest = {source, set, samples, count, axes, &error, &report};
if (engine_ingest_set(&ingest) == ENGINE_REFUSED) { /* error names the first failure */ }
engine_ingest_print(&ingest, stdout);
```

For each sample, in the order named, `engine_ingest_set`:

1. reads the source (`engine_source_read`) and packs the side bytes (`base/deflate`);
2. lifts the lanes on the device through the tower (`tower_lift`) and codes the coefficients (`compression_encode`)
   into the stored stream;
3. seals it (`base/obsignatio`, keyed BLAKE3 at every level): a node per row, plane, volume and lane, a leaf per
   stored chunk, then the stream, the side bytes stored and inflated, the members, and the sample's root over all of
   them;
4. writes the crystal (`apxrep_input_write`), reads it back, checks every chunk and root against the seal, lowers it
   (`tower_lower`), and compares every rebuilt lane with the lanes it lifted;
5. reads the source again and compares every pixel with the rebuilt lanes.

A sample that fails any step has its file removed, and the ingest stops there. The set's root is the keyed signum over
every sample's root, in the order named, and it exists only when every sample held. `EngineSampleRecord` says how far
each sample got (`placed`, `source_read`, `crystal_written`, `crystal_read`, `held`), its floors, its bytes against
the raw 16-bit bytes, its root, and what differed if the check failed: voxels, pixels, rows and the first row, chunks
and the first chunk, roots, shape.

The tower can lay reversible lookup edges between its floors (`TowerEdge`: a permutation of a coefficient's low bits,
up to 20 bits), which `tower_lower` undoes in reverse order. The ingest lays none.

**Proving and loading.** `engine_iapx_prove_set` checks a set's crystals without the source. For each sample it
re-hashes every chunk and root, lowers the lattice, and re-seals the rebuilt lanes against the stored seal. It carries
on past a sample that fails; the report covers every sample, and it refuses if any failed. `engine_iapx_load` does
the same for one sample and returns its lanes, extent, root and side bytes. `engine_iapx_head` reads only the head: the
extent `[t, z, y, x]`.

## The residual

The residual is a lattice program run on the key machine (`base/residual`, `base/keymath`, `base/key_schedule`,
`base/cycle`). `residual_program` writes four steps:

1. `ENGINE_SMOOTH` by `smooth_orders`;
2. `ENGINE_KEEP`;
3. `ENGINE_SMOOTH` by `background_orders`;
4. `ENGINE_SCALE_SUBTRACT` by the sum of the background orders.

A smoothing of order n on an axis is n unit steps (1, 1), a binomial row that is never divided. So the residual is the
smoothed lattice times 2^(sum of background orders), minus its background-smoothed copy, exactly. Every order must be
even. Each voxel's value is `ENGINE_RESIDUAL_LIMBS` (9) 32-bit limbs.

```c
EngineResidualRequest residual = {volume, depth, height, width, {2, 2, 2}, {8, 8, 8}, ENGINE_RESIDUAL_BOTH_PROVED,
                                  &error};
const unsigned int *device_residual = NULL;
engine_residual(&residual, &device_residual);   // one frame: depth × height × width lanes from the host
```

`unit_sweep` picks the route:

- `ENGINE_RESIDUAL_BY_UNIT_SWEEP` (0): `base/unit_sweep` applies the unit steps directly.
- `ENGINE_RESIDUAL_BY_KEY` (1): the imprinted key runs on `base/cycle`.
- `ENGINE_RESIDUAL_BOTH_PROVED` (2): both run, and every lane is compared. A frame whose lanes differ is refused as a
  logic error.

The key is imprinted once and kept while the orders stay the same. The device buffers are kept while the voxel count
stays the same. The returned pointer is the engine's, valid until the next call. A frame may hold at most
2^32 − 1 lanes divided by 9. `engine_residual_tally` returns the frames run, proved and differing, and the time spent
in each route.

## One frame's bodies

`engine_frame_bodies` runs the residual, then cuts it into bodies:

1. `max_tree_objects` (device) ranks every voxel's residual value, contracts the lattice by those ranks, and picks the
   cut level: the lowest level at which the count of components is largest. Each connected component above the cut is
   one body. It fills at most `room` `EngineBody` records, refusing more, plus a label per voxel (`labels`) and one bit
   per admitted voxel (`positive_words`, (voxels + 63) / 64 words).
2. `grow_leaves` makes the bodies into `EngineLeaves`: each leaf's peak, size, sums, moments and touches.

It returns the body count. An `EngineBody` carries the moments (6), the coordinate sums (3), its residual level
(9 limbs), `peak`, `mass` and `touches`. It also carries the fields the relating steps fill: `code`, `sample`,
`frame`, `id`, `state`, `parent`, `forward`, `backward` and `velocity`. `engine_group_voxels` lists the voxels of each
leaf by the labels, in leaf order. `engine_bodies_tally` returns the frames, bodies and levels seen.

## What a sample keeps beside its crystal

| file | written by | holds |
|---|---|---|
| `<sample>.kcr` | `engine_ingest_set` | the crystal: the stored stream, the side bytes and the seal |
| `<sample>.oapx` | `engine_entropy_set` | the entropy history: windows of `ENGINE_HISTORY_WINDOW` (11) transitions per voxel, and the cloud, windows × windows |
| `<sample>.bapx` | `engine_bodies_write` | the body table: `ENGINE_BODY_WORDS` (11) words per body (peak, mass, 3 sums, 6 moments), where each frame starts, and a CRC-64 over the words |

`engine_entropy_set` loads each crystal through its proof and projects the history
(`base/entropy_history`). Each voxel's flips must keep parity with its net change, or the sample is refused ("entropy
not conserved"). It then writes the history, reads it back and compares. With `keep` set, a sample whose history was
made from the crystal's current root is skipped. `engine_entropy_cloud` reads only the cloud.

`engine_bodies_write` writes the table, reads it back and compares, and removes the file if anything differs.

`engine_geff_read` reads a truth graph stored as geff (zarr): `nodes/ids`, `nodes/props/{t,z,y,x}/values` and
`edges/ids`, all 8-byte integers.

# n bodies: across frames

A sample's frames are its t axis (`extent[0]`). Each frame is a single-body problem: its residual, and its bodies from
`engine_frame_bodies`. The n-body modules then relate two frames' bodies, or run programs over their records. The
tracker drives them frame to frame, and the tracker is not in this tree (`track.h` above).

## Relating two frames

| module | entry | takes → gives | runs on |
|---|---|---|---|
| `base/shift_agreement` | `shift_agreement_host`, `shift_agreement_run` | two frames' packed words and the axes' extents (up to 8 axes) → the agreement at every lag, by a transform modulo 998,244,353. The voxel count must be below that prime | host and device |
| `nbody/body_overlap` | `body_overlap_host`, `body_overlap_run`, `body_overlap_run_on_device` | two frames' labels and positive words under a lag → each overlapping pair of bodies (by peak) and its voxel count | host and device |
| `nbody/heaviest_matching` | `heaviest_matching_run` | the pairs and their counts → the pairs chosen, a matching of greatest weight | host |
| `nbody/climb_machine` | `climb_machine_open`, `_store`, `_pend`, `_run`, `_box`, `_core`, `_extents`, `_close` | each frame's labels, positive words, peaks and contacts, then frame pairs with a lag → each leaf's landing forward and backward, with the lags | device |
| `nbody/marginal` | `marginal_run`, `marginal_run_host` | questions over sources, each source with weighted options onto targets → exact sums per question and per option, over every arrangement (at most 2^16), in 16 limbs | host and device |
| `nbody/box_history` | `box_history_gather` | an entropy history and each body's box (6 fields) → the counts and disagreements inside each box | device |
| `nbody/max_tree` | `max_tree_slide`, `max_tree_overlap` | probe voxels, and two frames' levels under a lag → the components at each level, and how the earlier and later components pair up | device |

## Programs over body records

These modules write a program for the record machine, as an `EngineRecordStep` list with its outputs, which the caller
imprints and sweeps (next section):

| module | program | members |
|---|---|---|
| `nbody/velocity` | `velocity_program`: the change of each body's center, and whether the axes agree | earlier, later, lag |
| `nbody/division` | `division_program`: whether a parent's mass and axes hold across a child and its sibling | parent, child, sibling |
| `nbody/contact_side` | `contact_side_difference_program`, `contact_side_kept_program`: the difference of two centers, then which side a contact is kept on | one, other; before, after |
| `nbody/fingerprint` | `fingerprint_program`: a body's print from its mass, sums and moments | one |
| `nbody/print_pair` | `print_pair_program`: two prints compared over 7 bands | one |

`max_tree_layout` sets the record's fields (`MAX_TREE_FIELD_*`: 6 moments, 3 sums, peak, touches, mass, level, frame,
sample), each as wide as the lattice's extents need, and `max_tree_pack` packs a frame's bodies into those records on
the device. `flatten_set` stores a set's packed records, and `flatten_read` reads them back.

The tracker-side modules are `nbody/bodies` (`assign_bodies`), `nbody/group_objects`, `nbody/link_objects` and
`nbody/relate_frames`. They need `track.h`.

# The machine (UTM): programs and the config

## Two machines on one runner

- **The lattice machine** (`engine_key_imprint`) takes `EngineStep`s (`ENGINE_SMOOTH`, `ENGINE_KEEP`,
  `ENGINE_SCALE_SUBTRACT`) and imprints them into one exact key over the lattice's three axes. The residual is its
  program.
- **The record machine** (`engine_record_imprint`, `engine_record_sweep`, `engine_record_host`) runs a straight-line
  program of exact integer steps over up to 3 members' records, one lane per output record, on the device or on the
  host. The host run uses the exact integer library, and a program is proved by the two agreeing word for word.

[prg_sch/README.md](prg_sch/README.md) is the guide to writing a program: the operations, the fields, the outputs,
the index, the tables, a worked example, and the machine's limits:

- `ENGINE_RECORD_STEPS_MAX`: 1,024 steps;
- `ENGINE_RECORD_MEMBERS_MAX`: 3 members;
- `ENGINE_RECORD_LIMBS_MOST`: 256 limbs live in the register file.

Every step is imprinted by `base/keymath`, laid out by `base/key_schedule` and run by `base/cycle`.

## The config (`.cfg`)

A run is configured by one JSON object (`prg_sch/run_cfg`, parsed by `base/cfg_json`). Examples are in `prg_sch/cfg/`.
`apply_cfg` refuses anything it does not know and names the line and column.

| key | holds |
|---|---|
| `scheme` | `"cell_tracking.cfg"` |
| `version` | 1 |
| `floor` | `{"entropy": true or false}` |
| `track` | the tracker's rules, each true or false (`pick`, `share`, `agree`, `unbound`, `cast`, `parallax`, `arc`, `settle`, `focus`, `web`, `damp`, `dish`, `vote`, `mutual`, `tower`, `mass`, `forest`, `cohere`, `accrue`, `merge_split`, `merge_target`, `forward_only`, `keep_view`, `resolve`, `sticky`, `motion_check`). Also `climb` (`off`, `machine`, `host` or `check`), `null_draws` (below 4,096) and `arms` (below 64) |
| `input` | `source` (the dataset's directory), `set` (where the crystals live), `axes` (t z y x c, or null), `samples` (a list of names), `first` (how many samples to take when none are named), `species`, `voxel_pm` (z y x in picometers), `membrane_pm` |
| `output` | each a path or null. `edges`, `coherence`, `pool` and `nodes` are TSV files, opened with their header rows. `export` and `object` are directories. `vis` is a directory, and the run writes an `index.html` in it |
| `view` | the renderer's settings, kept as written |

`write_cfg` writes the effective config back in the same form, leaving out `arms`. `input.set`'s refusal message still says `.iapx`; the set holds `.kcr`.

`prg_sch/run_log` names the run log and records each run's rules. `prg_sch/answer_key` holds a truth graph's nodes and
edges sorted for lookup. `base/schedule`'s `schedule_program` measures the device's free memory and plans against two
thirds of it. It splits each sample's frames into chunks that fit, with consecutive chunks sharing one frame. It then
writes each chunk as a stage, with the bytes it needs, as JSON to the path the caller sets in `g_schedule_path`
(`nbody_program/program.json` in [prg_sch/README.md](prg_sch/README.md)). Nothing reads that plan back yet.

# The daemon and device sharing

[daemon/README.md](daemon/README.md) is the full guide: starting the daemon, submitting, what each ticket means, the
job test, Linux, and the service files. In short:

- **One daemon per device.** Every process that wants the device's memory submits a job to it
  (`tessera_job_submit`) and declares the bytes it needs. The daemon admits jobs while their bytes fit the device's
  measured headroom; several run at once. A client that finds no daemon starts one from `daemon_path`, and the
  daemon exits once it has been idle for the idle time.
- **The ticket.** An admitted job runs and is then released (`tessera_job_release`). A job **held** (`asked`)
  declared more than its signum's kept peak: override it (`tessera_job_override`) or wait (`tessera_job_wait`). A job
  **lost** was held past its holding time: write its precalc into `lost_path`, then call `tessera_job_precalc_kept`.
- **The signum** is the BLAKE3 root of the job's request: the same request gives the same signum. On release, the
  job's measured peak and run time are kept under its signum.
- **Sweeps.** The daemon measures each running job every `sweep_microseconds`. A job that holds more than its
  reservation is grown to match and told. Growth never stops a running job, but nothing new is admitted while the
  device is overcommitted.
- **Sealed state.** The history is one 48-byte record per signum plus a 32-byte seal (obsignatio's keyed BLAKE3). The
  daemon refuses a history whose seal fails, whose length is wrong, or that has no seal. Every ticket in lost and found
  ends with a seal line.
- **The frame** between client and daemon is 128 bytes (`TESSERA_FRAME_BYTES`).

**The reservation, as the code stands.** The working tree reserves each job the larger of its declaration and its
signum's kept peak (`tessera_ledger_wants`, `daemon/tessera_ledger.c`). Admission, the head's shadow, the backfill's
spare and the reservation all use that figure. Doug's stated rule is different: "We reserve what they ask for and then
if it cost less we remember that for next time". The max rule is uncommitted and not approved by him, and it is waiting
on his decision.

## Where it runs

| | Windows | Linux | Linux under WSL 2 |
|---|---|---|---|
| endpoint | `\\.\pipe\tessera-<uuid>` | `$TESSERA_RUNTIME`, else `$XDG_RUNTIME_DIR`, else `/tmp`, then `/tessera-<uuid>.sock` | the same as Linux |
| one daemon | `FILE_FLAG_FIRST_PIPE_INSTANCE` | a lock file, and a live endpoint answering | the same as Linux |
| measures | each job's pid, through the PDH counter under WDDM | each job's pid, through NVML | each client reports its own bytes through dxcore (`tessera_self.c`), and the daemon runs in reported mode (`tessera_self_paravirtual` reads `/proc/sys/kernel/osrelease`) |
| service | none: the first client starts it | systemd user units `daemon/service/tessera@.socket` and `tessera@.service`, one instance per device UUID, with the socket handed over as fd 3 | the same as Linux |

In a container, mount the host's socket and name its folder with `TESSERA_RUNTIME`. The daemon reads a client's pid
with `SO_PEERCRED`, the pid in the host's namespace. Native Linux (NVML by pid) has not run here, because this
machine has no native Linux NVIDIA driver.

## The sims as jobs

Every sim that uses the device submits one job (`sims/sim_job.cu`) before its first device allocation, and
`sim_close` releases it. The signum is over the sim's name and arguments. The declaration is the buffers the sim names
for itself. The daemon is `$TESSERA_DAEMON`, else the `tessera_daemon` beside the sim, which `sims/run.sh` builds
there. With `TESSERA_OVERRIDE` set to any value, a declaration over the kept peak is admitted. `ask_state` and `ka_psi`
never touch the device, and they submit nothing.

## Every file and its steps

| file | steps |
|---|---|
| `engine.cu`, `engine.h`, `engine_config.h` | 1–6: the entries and the shared types |
| `CMakeLists.txt` | builds the exact integer, the sift, the renderer, their arms and the repository's `bench/`; the CUDA arms join wherever a CUDA compiler is found, and `bench_lattice` wherever the C compiler has C99 `_Complex`, which MSVC's does not |
| `base/stack/stack.{cu,h}` | 1 |
| `base/zarr/zarr.{c,h}`, `base/zip/zip.{c,h}`, `base/dicom/dicom.{c,h}`, `base/npy/npy.{c,h}`, `base/nrrd/nrrd.{c,h}`, `base/nifti/nifti.{c,h}`, `base/tiff/tiff.{c,h}`, `base/hdf5/hdf5.{c,h}` | 1: the source readers |
| `base/blosc/blosc.{c,h}`, `base/zstd/zstd.{c,h}`, `base/lz4/lz4.{c,h}`, `base/snappy/snappy.{c,h}`, `base/inflate/inflate.{c,h}` | 1: the codecs the readers call |
| `base/deflate/deflate.{c,h}` | 1, 3: packs the side bytes the crystal stores |
| `base/cfg_json/cfg_json.{c,h}` | 1, and the runs: JSON metadata and cfgs |
| `base/double_fields/double_fields.{c,h}`, `base/decimal_double/decimal_double.{c,h}` | 1, 6: a source's floating and decimal fields made exact |
| `base/obsignatio/obsignatio.{cu,h}`, `base/obsignatio/test/` | 2 |
| `base/crc.h`, `base/crc_key.h` | 2, 3: the CRC-64 checks the seal is replacing (stage B) |
| `base/apxrep/apxrep.{cu,h}` | 2, 3: frames the crystal, its seal and the other engine files |
| `base/compression/compression.{cu,h}`, `base/tower/tower.{cu,h}` | 3: the tower can lay reversible lookup edges between its floors (`TowerEdge`, a permutation of a coefficient's low bits), which `tower_lower` undoes in reverse order |
| `base/residual/residual.{cu,h}`, `base/residual_survey/residual_survey.{cu,h}`, `base/unit_sweep/unit_sweep.{cu,h}` | 4 |
| `base/entropy_history/entropy_history.{cu,h}` | 4 |
| `base/shift_agreement/shift_agreement.{c,cu,h}` | 4, 6: the lag at which two frames agree |
| `base/period/period.{cu,h}` | 4: the period of each axis of one lattice, with the exact counts that decide it |
| `base/golden_bands/golden_bands.{cu,h}` | 5: the bands a value falls into |
| `base/cycle/cycle.{c,cu,h}`, `base/keymath/keymath.{cu,h}`, `base/key_schedule/key_schedule.{cu,h}`, `base/radix_keys/radix_keys.h` | 4, 5, 6: the imprinted key machine every exact pass runs on |
| `base/no_rounding/` | 4, 5, 6: the exact integer and its arms |
| `base/scriptura/scriptura.{c,h}`, `base/scriptura/scriptura_arm.h`, `base/scriptura/scriptura_arm_<set>.c` | 1–6: every report's formatting and memory scans, one memory arm per instruction set, chosen once at first use |
| `base/schedule/schedule.{cu,h}` | 1–6: the program's stages against the device |
| `daemon/tessera.h`, `daemon/tessera_frame.c`, `daemon/tessera_ledger.{c,h}`, `daemon/tessera_measure.{c,h}`, `daemon/tessera_self.c`, `daemon/tessera_client.c`, `daemon/tessera_daemon.c`, `daemon/tessera_paths.c`, `daemon/test/` | 1–6: the device scheduler every step's device work passes through. The daemon is built and run by `test/run.sh`, and `tessera_job_test` drives the client against it end to end (24 checks, 0 failed). The history and the lost tickets are sealed, and a damaged, cut or unsealed history is refused. Every sim that uses the device submits a job (`sims/sim_job.cu`). Under WSL 2 each client reports its own device bytes through dxcore (`tessera_self.c`), and the daemon runs in reported mode. [daemon/README.md](daemon/README.md) covers submitting jobs and starting the daemon |
| `render/anchor_raster.{c,h}`, `render/raster_cuda.cu` | 4–6: renders a step's state as a sheet or a volume |
| `nbody/max_tree/max_tree.{c,cu,h}`, `nbody/grow/grow.{cu,h}`, `nbody/bodies/bodies.{cu,h}`, `nbody/group_objects/group_objects.{cu,h}` | 5 |
| `nbody/flatten/flatten.{cu,h}` | 5: the bodies' magnitudes flattened and stored |
| `nbody/fingerprint/fingerprint.{cu,h}`, `nbody/print_pair/print_pair.{cu,h}` | 6: a body's print, and a pair of prints |
| `nbody/body_overlap/body_overlap.{c,cu,h}`, `nbody/heaviest_matching/heaviest_matching.{c,h}`, `nbody/link_objects/link_objects.{cu,h}`, `nbody/relate_frames/relate_frames.{cu,h}` | 6 |
| `nbody/velocity/velocity.{cu,h}`, `nbody/division/division.{cu,h}`, `nbody/contact_side/contact_side.{cu,h}`, `nbody/box_history/box_history.{cu,h}`, `nbody/climb_machine/climb_machine.{cu,h}`, `nbody/climb_machine/spiral_table.h`, `nbody/marginal/marginal.{c,cu,h}` | 6 |
| `nbody/anchor_sift/` | 6: the sift, its scan arms per instruction set |
| `prg_sch/run_cfg/run_cfg.{cu,h}`, `prg_sch/run_log/run_log.{cu,h}`, `prg_sch/cfg/`, `prg_sch/nbody_program/` | the runs that compose steps 1–6 |
| `prg_sch/answer_key/answer_key.{cu,h}` | 6: a truth graph's nodes and edges, held sorted |
| `sims/run.sh`, `sims/sim.h` | the sims' build, their checks and keyed draws, and exact rationals printed through the exact integer |
| `sims/sim_camera.h` | 1: the camera law on the device. Electrons are the background, a ramp, a planted period and moving ellipsoid bodies. Shot noise is Binomial(4S, ½) − S, which has Poisson's mean and variance exactly. Read noise is Binomial(4r², ½) − 2r². A per-voxel fixed pattern and an integer gain are added. Each body's truth is its mass and coordinate sums a frame, proved against a host walk of its box |
| `sims/nbody_lattice/` | 5, 6: moving and dividing bodies with their truth, the camera law's two moments against the planted law, and `--out <dir>` for `lattice.npy` and `truth.tsv` |
| `sims/noise_floor/` | 4: the Kolmogorov mock (linear-generator noise recovered by Berlekamp–Massey), the linear complexity of every bit plane, the photon transfer curve with motion removed by the truth and by the data alone, and the neighbor coherence of frame differences |
| `sims/period_power/` | 4: `period_read` on planted periods from no plant to a strong one, at 8 and 19 draws: its power, which multiple it reads, and the false-period rate on the unplanted axes |
| `sims/root_universal/` | 3: the tower with reversible lookup edges between its floors, on camera-law volumes. Random edge programs rebuild every lane through lift, code, wipe, decode and lower. Two edges on one floor fold into the table that composes them, in order, and a floor between them blocks the fold. It also measures what an unfitted edge costs the coder, by table width and by floor |
| `sims/ask_state/` | a qubit carried exactly as the answer distribution of a complete ask, in exact rationals on the exact integer. There are two asks: a rational tetrahedral one, and the true SIC in Q(√3), where the square root is carried by its relation (√3)² = 3. State to answers to state is exact, and the phase falls out of the ask. The valid set holds the pure states on its boundary. The crossing rule has negative weights. It also counts how many distributions of a grid are states |
| `sims/ka_psi/` | Kolmogorov's inner function ψ, exactly (Braun and Griebel 2009, section 2). Grid values are exact integers. Values at depth are sparse sums c·γ^−β(L), where the exponent β(L) is an integer that is never expanded. It reproduces Sprecher's counterexample (2.5) exactly. It checks Köppen's ψ in both readings of the carried midpoint, (2.9) and (2.7) as printed: on every point of D_1 to D_5, the scale step matches the level recursion, ψ is strictly increasing, the least gap is γ^−β(L), and the widest gap is the gap the recursion predicts. The chained step is then checked symbolically to level 60 (n = 2) and level 38 (n = 3). The widest gap stays under 2^−(L−1)/γ; ψ is continuous. The sim then tests separation: ξ = Σα_pψ(x_p) on every point of D_k^n (up to 10^6 points), with the α tails bounded. Lemma 3.4 fails at k = 1: ξ(0.1, 0) − ξ(0, 0.9) = 1/10 − (9/10)α₂ < γ^−2, and the supports of Lemma 3.8 overlap there. The corrected bound |µ_k| ≥ γ^−nβ(k) − Σε_{k,p} keeps the supports apart at every k, symbolically to depth, when the ramp is γ^−(β(k+1)+2). It also checks that the m + 1 shifts never share a gap |
| `sims/chaitin_omega/` | Chaitin's Ω for Tromp's binary lambda calculus, where a closed term halts when it has a normal form. Every closed term up to L bits is unranked from exact counts, checked against a parse of every code up to 22 bits, and run by normal-order reduction on the device, one term to a thread (or on 16 host threads with `cpu`). The device takes every decision the host's run takes, in the same order, under budgets of at most 256 steps and 256 tokens. A halt, loop or growth proof found inside those budgets is found at the same step inside larger ones, since a run is deterministic and its budgets only stop it. So every term that reaches a device budget, or outgrows the device's room, is handed back and run by the host under the full budgets. The host's own run of every term through 30 bits must give the same fates and busy beavers, record holders included. With `--ledger <path>` the run is planned as jobs, each length cut every 2^28 terms in rank order. Each finished job's exact tally is written as one flushed line. A rerun under the same budgets keeps every whole line and runs only the jobs missing from it; a stopped run resumes and a longer L costs only the new lengths. A line cut short by a stop, or one whose fates don't sum to its job's count, is run again. Reaching a normal form proves a halt. Brent's watcher proves a loop when a term returns to a state it held. A term is proven to grow forever when a part of it, reduced by head steps alone, returns at its own head as that part applied to new arguments. Such a part has no head normal form; the term has no normal form. Every other run exits either out of steps or out of the space it was given. With a million steps, no term through 30 bits ran out of steps; every unresolved term had outgrown its space. An unresolved term is also checked for a simple type, found by Hindley's unification with an occurs check. A typable term is strongly normalizing (Tait); a type proves the halt without running any step or writing the normal form. None of the 374 terms unresolved through 30 bits has one: they are self-applications. The same check runs as a cross-check: no term proven to loop or to grow forever may have a type, and none does. The mass past L is counted with directed rounding, not run. Normal forms past L add to the lower bound, and the closed mass past L, bounded by the parse's tail, adds to the upper. At L = 30 (2,048 steps and tokens), 647,463 terms give 0.122543 ≤ Ω ≤ 0.125993, which proves 2 bits. With 200,000 steps and 16,384 tokens, 213 of the 587 unresolved terms are proven to grow forever: 47 run out of steps and 327 outgrow the space. At L = 40 (2,048 steps and tokens, before the growth proof), 283,817,255 terms (488,151 proven loops, 474,630 open) give 0.124071 ≤ Ω ≤ 0.125990. That is still 2 bits, with 1/8 inside the bracket. On the device at L = 44 (256 steps and 256 tokens; at 36 bits they move the upper bound by +2.18e-8, about 2^-25.5, against a gap of 0.00240, about 2^-8.7), 3,392,860,908 terms in 28 s give 0.124438573589 ≤ Ω ≤ 0.125987962504, with the first typed halt. The upper bound barely moves with L, since it falls only by proven non-halting mass; bit 3 can settle only from below, and only if Ω ≥ 1/8. The busy beaver table (the most steps to halt, and BB λ, the largest normal form, each with its record holder term) equals BusyBeaverWiki's BB λ (OEIS A333479) at every length through 33 bits under the default budgets. Under any budgets it is checked to be at most the published value, and equal to it at every length where every term halted |
| `sims/art/periodic_energy.h`, `sims/art/fixed_pattern.cu`, `sims/art/classify_reject_recover.cu` | 4: anchor_sift's ART-4-005 and ART-4-007 on the device. The phase dispersion ratio is exact, against a drawn null band. The fixed pattern is removed to the bit by two routes (phase sums and a reduced-fraction Welford) beside a broken third. The repeat mode's consensus is by count and by median, with negative controls and the static-feature floor |

## The exact integer, and the arms that read it

`base/no_rounding/exact_integer.{c,h}` holds an exact integer as a fixed width array of 32 bit limbs. The directory name states what the arithmetic is for. It removes rounding, and a comparison is then exact. It is the same value anchor_sift's `src/engine/python/representation/exact.py` ingests, in a different transform: Python carries the arbitrary precision form, this carries the fixed width form, and a GPU carries the same fixed width form one warp to a number. No arm gets its own arithmetic doctrine.

Fixed width is the only bound the representation has, and it is declared instead of discovered. The default is 128 limbs, 4096 bits, holding the 1024 decimal digits the Python side ingests at (`base/no_rounding/exact_integer.h`, `ANCHOR_EXACT_LIMBS`). This tree's build fits it to 256 limbs, from `ENGINE_RECORD_LIMBS_MOST`. A build selects any power of two from 1 limb up, given in limbs or in bits (`ANCHOR_EXACT_BITS`), with no ceiling, and the header refuses any other width at compile time. Every arm is graded from 1 limb to 32768 by `check_exact_widths.sh`, and the portable reference to 4,194,304 bits by `test/exact_transform_test`. A power of two keeps the top magnitude bit at one fixed position as the width doubles. The sign is held apart from the limbs. A value that will not fit returns `ANCHOR_EXACT_WILL_NOT_FIT` instead of wrapping.

In this tree's copy the width has no ceiling. A build names it in bits (`ANCHOR_EXACT_BITS`) or in 32-bit limbs (`ANCHOR_EXACT_LIMBS`): any power of two from 32 bits up. The one not given follows from the other, and static asserts refuse a width that is not a power of two, is below 32 bits, or where the two names disagree. `ANCHOR_EXACT_DIGITS`, when not given, is the most decimal digits the width holds, up to the 1024 the Python side ingests at; the default 4096-bit build is unchanged. A call's width-sized working copies are one room, placed at compile time: on the stack up to `ANCHOR_EXACT_STACK_LIMBS` (4096 limbs), and from the heap beyond it. A room that cannot be held returns `ANCHOR_EXACT_WILL_NOT_FIT`; no width is bounded by a stack. The caller still holds its own values; at widths past the stack it holds them from the heap.

Multiplication is a ladder. Long multiplication runs below `ANCHOR_EXACT_KARATSUBA_LIMBS`. Karatsuba runs from there: three half products, with unbalanced operands cut into slices of the shorter. Once both operands reach `ANCHOR_EXACT_TRANSFORM_LIMBS`, the Schönhage–Strassen transform takes over. It works in the ring 2^n + 1, where 2 is a root of unity; every twiddle of the transform is a shift and nothing is rounded. The pieces are weighted by ψ = 2^(n′/2^k), whose 2^k-th power is −1, which turns the cyclic transform into the negacyclic product the ring needs. The pointwise products recurse. The depth of each split is chosen by an integer cost model, which falls back to Karatsuba when that is cheaper. `anchor_exact_multiply_transform` runs the transform at any size, for tests and timing. The rungs are measured in `test/exact_transform_test`, balanced operands on this host (x86-64, MSVC -O2), seconds per product:

| limbs | long | Karatsuba | transform |
|---|---|---|---|
| 512 | 3.6e-4 | 2.0e-4 | 3.0e-4 |
| 2048 | 4.3e-3 | 1.1e-3 | 1.5e-3 |
| 4096 | 1.8e-2 | 3.3e-3 | 4.0e-3 |
| 8192 | 7.4e-2 | 1.1e-2 | 1.1e-2 |
| 16384 | | 3.3e-2 | 2.3e-2 |
| 32768 | | 1.0e-1 | 6.7e-2 |
| 65536 | | 2.5e-1 | 1.4e-1 |

Karatsuba beats long multiplication from 64 limbs, and it is 6.6× faster at 8192. The transform meets Karatsuba near 8192 limbs, which is `ANCHOR_EXACT_TRANSFORM_LIMBS`'s default, and it leads by 1.85× at 65,536. At a 4M-bit width a call on small operands costs about 1e-4 s, because each call touches the whole fixed width. Static asserts hold Karatsuba's rung at 4 limbs or more and the transform's at or above it.

Division is as exact as multiplication. `anchor_exact_divide` is Knuth's algorithm D in base 2^32. It returns the quotient rounded toward zero and a remainder carrying the numerator's sign; numerator = quotient · divisor + remainder. `anchor_exact_divide_exact` handles a division known to leave no remainder. It shifts the divisor's twos out, multiplies by the inverse of its odd part modulo 2^(32·limbs), and masks. The inverse comes from Newton's step x(2 − dx), which doubles the bits that are right; each step works only to the doubled precision, on the ladder; 2 − t is t's two's complement plus two. The quotient is multiplied back, and a remainder is refused as `ANCHOR_EXACT_NOT_EXACT`. `anchor_exact_gcd` is Lehmer's (Knuth's algorithm L). The leading 32 bits run Euclid's steps in words while the quotient is certain, and their cofactors then advance both values in one pass, about thirty bits at a time; the last two words finish in a word. It returns a status. A zero divisor returns `ANCHOR_EXACT_BY_ZERO`. The sims' rationals (`sims/sim_rational.h`) use the gcd and the exact division to keep every value in lowest terms at any width. Once the divisor and the quotient both reach `ANCHOR_EXACT_NEWTON_LIMBS` (8192), division switches to Newton's reciprocal. The reciprocal is grown at half precision, taken one Newton step and corrected exactly, and the quotient is then one product on the ladder. On the Karatsuba ladder alone, long division leads up to 4096 limbs, and Newton is 1.21× ahead at 8192, 1.06× at 16384, 1.81× at 32768 and 2.44× at 65536. The same four divisions are key primitives of the record machine (`ENGINE_RECORD_QUOTIENT`, `_REMAINDER`, `_GCD`, `_EXACT_QUOTIENT`). The device runs them on the register arrays with scratch that only a program that divides carries.

```
cmake -S src/engine/c -B build/engine_c -G Ninja -DANCHOR_EXACT_LIMBS=32768
cmake -S src/engine/c -B build/engine_c -G Ninja -DANCHOR_EXACT_LIMBS=4 -DANCHOR_EXACT_DIGITS=38
bash maint/engine/check_exact_widths.sh
bash maint/engine/check_exact_widths.sh --gpu
```

A width below 4096 bits cannot hold the 1024 digit floor. A narrower build names the floor it does hold, 38 digits at 128 bits. The engine needs 8 limbs. Its dispatch rule reaches 143 bits on a 64 bit census, and `nbody/anchor_sift/anchor_sift.c:23-39` refuses a narrower width by name. The exact integer and every arm build and grade down to 1 limb. `check_exact_widths.sh` builds each width in its own tree under `build/exact_widths/` and grades it three ways: the rows of `bench_exact` against Python integers, every host arm against portable, and `test_steer` from 8 limbs up. `--gpu` adds the CUDA arm through `build_gpu_arm.sh`, which prints whether the device itself answered as well as whether the arm agreed.

The run shrinks as the width grows, from 4096 positions at 128 limbs and below to 64 from 8192 limbs up. At the widest width one position is 128 KiB on the host and twice that on the device.

An **arm** is one implementation of the operations the measure asks for. Every arm answers the same counts, and the portable C11 one is the reference. Where two disagree, one of them has a defect and nothing about the difference is a tradeoff.

Every arm is one file in `base/no_rounding/`, named for its instruction set. The set of arms is a directory listing.

| file                              | arm                        | instruction                                         |
| --------------------------------- | -------------------------- | --------------------------------------------------- |
| `base/no_rounding/arm_portable.c` | `portable`                 | none, C11 alone                                     |
| `base/no_rounding/arm_avx2.c`     | `avx2-win` or `avx2-linux` | `vpcmpeqd` on `ymm`, eight limbs at once            |
| `base/no_rounding/arm_avx512.c`   | `avx512-unrun`             | `vpcmpeqd` on `zmm` against a mask, sixteen at once |
| `base/no_rounding/arm_neon.c`     | `neon`                     | `cmeq` and `uminv`, four limbs at once              |
| `base/no_rounding/arm_sve.c`      | `sve-unrun`                | `whilelo`, `cmpne`, whatever length the part has    |
| `base/no_rounding/arm_cuda.cu`    | `cuda`                     | one position per thread, not one limb per lane      |

The AVX2 arm is one file for every x86 build. It carries both detection paths, MSVC's `cpuid` and the builtin GCC and Clang share, and reports the operating system in its own name so two builds running the same instructions are still told apart in a row. Every arm asks the processor at run time before it is used, because the build machine and the running machine are not the same machine.

### Three grades, and they are never interchanged

**agrees** means the arm was run on real hardware and compared against portable item by item. **builds** means it compiled for a target and real machine code was confirmed generated. **emits** means the object file was disassembled and the instructions it was written to use were confirmed present.

```
bash maint/engine/verify_arm_asm.sh     what each arm emits
bash maint/engine/verify_gpu_arch.sh    what the CUDA arm generates, per architecture
./build/engine_c/bench_exact_arms 8192  what each arm answers, against portable
```

Reading emitted instructions rules out a header that silently fell back to scalar code, an intrinsic the compiler emulated instead of issuing, and a flag that was accepted and ignored. It says nothing about behavior. AVX-512 and SVE have no hardware in this project and carry `unrun` in their own names for that reason. A row of results then cannot show one beside a run arm without the difference being visible.

That check has already caught one thing. The SVE row first reported no `whilelt` emitted. The cause was a wrong expectation and not wrong code: `svwhilelt_b32` on unsigned operands emits `whilelo`, since `WHILELT` is the signed form.

### Every arm runs one algorithm

The measure asks the set for membership: is there a point exactly one lag away carrying the same value. That is a hash lookup, and `anchor_exact_agreement_using` is the only implementation of it in the tree. An arm supplies its equality test and contributes nothing further.

It was not at first, and the numbers that produced are worth recording. Every arm carried its own ordered search, portable included. A full comparison then ran at each step of a binary search, and the vector arms looked very strong against it. AVX2 read **3.44x**. Moving portable alone to the hash dropped it to **1.75x**, which measured nothing, because the two arms were running different algorithms by then. Moving every arm to the hash gives **1.19x**. That is the figure, being the only one where the sole difference is the instruction.

A vector arm timed against a reference doing work the problem never asked for is measuring its own speedup at a benchmark.

### What was measured

Run against portable, agreeing on every lag at every size:

| arm          | machine                    | 1,024     | 8,192          | 65,536 |
| ------------ | -------------------------- | --------- | -------------- | ------ |
| `avx2-win`   | MinGW gcc 13.2, this host  | 1.38x     | 1.20x          | 1.19x  |
| `avx2-linux` | WSL gcc 14.2               | 1.24x     | 1.26x          | 1.41x  |
| `avx2-linux` | WSL clang 20.1             | 1.15x     | 1.11x          | 1.11x  |
| `neon`       | Pi 5, Cortex-A76, gcc 14.2 | 1.16x     | 1.12x          | 1.10x  |
| `cuda`       | RTX 3070, compute 8.6      | **0.34x** | 1.29x at 4,096 | 8.63x  |

Widening the comparison is worth ten to forty percent. It cannot reach three times, because the comparison is no longer most of the work: the hash probe and the memory it touches are.

**These are host clock timings and the host is not quiet.** `clock()` on this platform measures wall time. Anything else running on the machine moves the numbers. Another session was running processor work in bursts through the afternoon and reported it, and that report is the only reason it is known. Every CUDA figure above is a median of five runs taken on an idle card; the spread across those five is 0.29 to 0.45 at a thousand positions and 7.82 to 9.13 at sixty five thousand. A lone run is worth about ten percent either way. The gcc-14 row is a median of five for the same reason, taken after one run read 0.89x, an outright loss.

Device side timing through CUDA events would be immune to this and the host arms would still not be. Both arms of a ratio run back to back in one process. Load moves them together and mostly cancels. The medians landed within ten percent of the single runs they replaced for that reason.

**Read the CUDA row from the left.** It **runs slower at a thousand positions**, breaks even near four thousand, and runs eight times faster at sixty five thousand. The bus sets the crossover. This arm copies the whole run to the device before it computes anything. The loss at small sizes is a property of the transfer and travels with the arm wherever it goes. Sizing a workload from the 8.63x alone would put it where the arm is three times slower than doing nothing special.

A ratio holds only against the portable arm in **that same build**. The CUDA driver is compiled by MSVC and the CMake one by MinGW, and their portable arms are not the same object. A number in one row therefore does not compare to a number in another.

The CUDA arm generates real SASS for ten architectures, Turing through every Blackwell target and Hopper's HBM3 part. Only compute 8.6 has hardware here and only it is run.

## What is here

| file                                                                | what it is                                                                        |
| ------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `nbody/anchor_sift/anchor_sift.{c,h}`                               | the search, the steering and the portable scan, with no clock and no output       |
| `nbody/anchor_sift/scan_<set>.c`                                    | one wide scan arm per instruction set                                             |
| `base/no_rounding/`                                                 | the exact integer and every arm that reads it, one file per instruction set       |
| `render/anchor_raster.{c,h}`, `render/raster_cuda.cu`               | the direct renderer, host and device                                              |
| `../bench/bench_corpora.{c,h}`                                      | the generated corpora and the two statistics a dispatch decision reads            |
| `../bench/bench_lattice.c`                                          | soundness, where the claim actually lives                                         |
| `../bench/bench_scaling.c`                                          | what the sift costs per alignment as the corpus grows                             |
| `../bench/bench_dispatch.c`                                         | which arm to run, and what the two thresholds should be                           |
| `../bench/bench_coherence.c`                                        | at what scale the corpus agrees with itself, read before the search               |
| `../bench/bench_raster.c`                                           | renders every sheet and volume configuration and grades host against device       |
| `../bench/bench_scriptura.c`                                        | every scriptura memory arm against the C runtime's own routine, size by size      |
| `../test/scriptura_arm_test.c`                                      | every scriptura memory arm against a byte loop, operation by operation            |
| `../test/period_test.cu`, `../test/period_test.sh`                  | the period reading against a host reference, lag by lag and axis by axis          |
| `../test/record_table_test.cu`, `../test/record_table_test.sh`      | the record lookup table (`ENGINE_RECORD_TABLE`) against the ordinary ops as oracles: a table filled by an ops program reproduces it lane for lane on device and host, tables compose in order, and register reuse leaves the output unchanged |
| `../test/exact_divide_test.cu`, `../test/exact_divide_test.sh`      | the exact integer's division. Long division rebuilds numerator = quotient · divisor + remainder over 200,000 edge-shaped trials to 8 limbs and 4,000 at every width, with the remainder below the divisor and the signs of truncation. It also holds in a case that runs the add-back step. Exact division returns the quotient of every product, for odd and even divisors, and refuses a value one past a product. The gcd divides both values, contains their shared factor and leaves coprime cofactors, and it equals Euclid's on the long division. A zero divisor is refused |
| `../test/record_divide_test.cu`, `../test/record_divide_test.sh`    | the division record operations (`ENGINE_RECORD_QUOTIENT`, `_REMAINDER`, `_GCD`, `_EXACT_QUOTIENT`) on the register bit arrays. The device's own long division, Euclid and multiply-and-mask quotient must equal the host's, the exact integer library, word for word. This holds over 4,096 signed 160-bit lanes in the 64-limb file and 512 lanes of 2,048-bit numerators in the 256-limb file, including the add-back case. Every decoded lane meets numerator = quotient · divisor + remainder and the gcd's divisibility, and every exact quotient returns its factor. A zero divisor and an inexact quotient refuse on both sides, and a step reading a later one is refused at imprint |
| `../test/record_guide_test.cu`, `../test/record_guide_test.sh`      | the worked example of [prg_sch/README.md](prg_sch/README.md), run as written: bodies moved by x + v · dt over one shared time-step record paired in by the index, with the side of the origin. It checks the imprint's derived widths (32, 33, 1) and the packed outputs (bits 0 to 33 and 34 to 35 of a 2-limb record). The device must equal the host word for word over 1,000 bodies, with every value decoded exact. A step reading itself is refused at imprint, and an index past its member at the sweep. 11 checks, 0 failed |
| `../test/exact_transform_test.cu`, `../test/exact_transform_test.sh` | the multiplication ladder, at three widths: 128 limbs, 4096 limbs (stack rooms), and 4,194,304 bits (heap rooms, four times past the old ceiling). The ladder, and the transform alone, both equal a long multiplication kept in the test, balanced and unbalanced, keyed and all-ones, across every rung boundary up to half the width (65,536-limb operands at 4M bits). Each product divides back to its factors, exactly and with a remainder, and the gcd holds a factor. Each rung is timed; the crossovers are measured. Extra arguments reach nvcc as defines |
| `../test/tower_edge_test.cu`, `../test/tower_edge_test.sh`          | the tower's reversible lookup edges: one edge, edges stacked on one floor and edges on every floor all lift and lower back to the exact lanes. The edges change the crystal. A table that is not a permutation, a width out of range and a floor past the collapsed floor are all refused, and a refusal leaves no state behind. A Bennett edge, (x, y) → (x, y ⊕ f(x)), carries a lossy f (|x|, a comparison) as a permutation of the widened field: it round-trips, f(x) reads out of the carrier, and the same f laid bare is refused |
| `../bench/bench_sift.c`                                             | candidates, skip distance and anchor independence over byte strings. Not wired up |
| `../bench/bench_entropy.c`, `bench_ab.c`, `bench_cycles.c`          | not wired up                                                                      |

Nothing under `src/` comes from anywhere else, and nothing under `deps/` is a copy any more. `mmgr_sha256.{c,h}` is MMgr's test support, at `deps/mmgr/test/support/`. Run `python maint/deps/get_deps.py` to clone what this tree depends on. The three unwired drivers that include it get that directory on their include path when somebody wires them up. Nothing built here needs it, since `bench_corpora` fills every corpus with splitmix64.

`bench_corpora` is shared so the scaling bench and the dispatch bench cannot disagree about what skewed means. One measures a rate against a prediction and the other scores a rule with a clock, and a rule scored on corpora the prediction never saw is a rule scored against nothing.

## Rendering

`render/` turns engine state into an image, as a sheet or a volume, with no export step between the state and the pixels. Each renderer has a host arm in C and a device arm in CUDA that produce the same bytes. A caller uses the dispatch and does not choose an arm. `anchor_raster_render` for a sheet and `anchor_volume_render` for a volume both prefer the device where one is present and fall back to the host where none is. Where a device is present, `bench_raster` grades the two arms against each other byte for byte on every configuration, twenty sheet combinations and twenty volume combinations, and a single differing pixel or voxel is a defect. `docs/rendering.md` is the guide: the configuration structures, the layouts and channels, what each is checked against, and what is not checked.

## bench_lattice, where the soundness claim is tested

Its core takes a base list, a displacement list, and a callback answering whether two positions carry the same symbol. The core has no dimension parameter because the geometry is entirely inside the base list, and no symbol type because it only ever asks whether two agree. A core that cannot see either one cannot depend on either one.

**3,421 rows, 465,546 true occurrences, none refused.** Alphabets of 2 to 256 symbols, patterns of 1 to 32 points, 1 to 32 anchors up to and including every point being one, dimensions 1 through 8, a complex alphabet with irrational parts compared over its storage, a rotated point set, a scatter no rectangle covers, three anchor rules that share nothing, and an order check against a permuted base list.

Occurrences are planted, and they have to be. A pattern of `p` points over `L` symbols occurs by chance about `positions / L^p` times, which is already under one at eight points over sixteen symbols. A row that checked nothing is not evidence that anything held.

## bench_scaling, and what it settles

Reads and cycles come from two builds of one source, because counting perturbs the timing it would sit beside. `ANCHOR_SIFT_COUNT_READS` is inert at its default. The timed build is the object it was without the counters.

### The asymptotic question, and what the sweep answers

**Does the cost per alignment depend on N?** No. Across 1024 times in corpus length, the three corpora give the same answer.

| corpus     | probes per alignment, 4 KB to 4 MB | verifications per alignment |
| ---------- | ---------------------------------- | --------------------------- |
| uniform    | 1.003611 → 1.003923                | 0.000000 throughout         |
| skewed     | 1.380587 → 1.376459                | 0.013459 → 0.013260         |
| periodic16 | 1.188197 → 1.187501                | 0.062732 → 0.062500         |

Nothing drifts. The sift is linear in N with a constant that belongs to the distribution. The total work is `O(N)` per needle and the coefficient is fixed by `H2` before the search starts. The small rise in the uniform column is the entropy estimate filling out, from `H2 = 7.9189` at 4 KB to `7.9999` at 4 MB, and the probe rate tracks it to the fourth place.

**Is the histogram bound right?** It is exact where the corpus has no arrangement and it is wrong by a bounded constant where it has one, and in both cases the error is flat in N.

- Uniform: predicted `1 + 2^-8 = 1.003906`, measured 1.003923. Nothing survives to verification.
- Skewed: measured 0.013260 against a predicted 0.011917, a ratio of 1.11 that holds at every length. The excess belongs to the 32 needles, not to the corpus: the survival of a needle is the product of its four anchor symbol probabilities, that product is heavy tailed on a skewed alphabet, and the same 32 needles are used at every N. A fixed sample cannot drift.
- Periodic16: predicted `2^-16`, measured exactly `1/16`, a ratio converging on 4096.

**So the failure is asymptotically well behaved too.** Where the bound breaks it breaks to a constant and not to a growing function of N. The sift stays `O(N)`; it filters less than the histogram promised and it filters by a fixed factor less.

### Why periodic16 misses by exactly 4096

The ratio converges from above as N grows: 4111, 4100, 4097, 4096, 4096, 4096.

The reason is not that the anchor offsets collide. At a needle length of 64 they are 0, 23, 46 and 53, which are 0, 7, 14 and 5 modulo sixteen, and no two of them agree. The reason is that a corpus of period sixteen is a single orbit under translation. Position `p` carries `p mod 16`. A needle taken at offset `s` therefore has `needle[o] = (s + o) mod 16`, and an alignment at `at` matches that anchor when `(at + o) ≡ (s + o) mod 16`. The offset cancels. Whatever offset an anchor was placed at, it tests `at ≡ s (mod 16)`. Four probes therefore ask one question four times, and one alignment in sixteen survives all of them.

The probe count confirms the mechanism to four places. One probe always runs, it succeeds one time in sixteen, and the three behind it then succeed for certain, which is `1 + 3/16 = 1.1875`. Measured: 1.187501.

## bench_coherence, the reading taken before the search

The miss above does not have to be met. It can be computed before the search, from one pass over lags that is cheap next to the search itself.

Where `k` anchors collapse onto one independent probe, the histogram overstates the filter by exactly `2^((k-1) * H2)`. For four anchors on a corpus of period sixteen at `H2 = 4.0`, that is `2^12 = 4096`.

| corpus     | H2    | period found | agrees | at chance | margin |
| ---------- | ----- | ------------ | ------ | --------- | ------ |
| uniform    | 7.999 | none         |        | 0.0039    | 0.0001 |
| skewed     | 1.598 | none         |        | 0.3336    | 0.0007 |
| periodic16 | 4.000 | **16**       | 1.0000 | 0.0625    | 1.0000 |

| corpus     | independent anchors | histogram says | coherence says | measured    | off histogram    | off coherence    |
| ---------- | ------------------- | -------------- | -------------- | ----------- | ---------------- | ---------------- |
| uniform    | 4                   | 0.000000000    | 0.000000000    | 0.000000000 | nothing survived | nothing survived |
| skewed     | 4                   | 0.011789708    | 0.011789708    | 0.013251748 | 1.1              | 1.12             |
| periodic16 | 1                   | 0.000015259    | 0.062500000    | 0.062503577 | **4096.2**       | **1.00**         |

The period is recovered with nothing supplied. Each candidate is scored against its own multiples, not by taking the tallest lag: a period of sixteen agrees with itself at 32, 48 and 64 alike, and which of those stands tallest is settled by noise. Scoring against multiples is the same reading `measure.periodicity.sequence_period` performs in the Python engine, where it was caught against a period chemistry fixes at three. The two share no code.

**What this changes about the order of operations.** Coherence is read first and everything downstream follows from it: how many anchors carry information, what spacing keeps them off one residue class, and which of the two predictions to believe. Collision entropy is permutation invariant. No bound built from H2 alone can see arrangement, because a corpus and its own shuffle carry identical H2. Coherence is the reading that can, and it takes one pass.

### Setting the anchor count from the recovered size

`anchor_sift_run` takes the plan and places the anchors the coherence reading calls for. Where a period is found the anchors after the first refute nothing the first did not already refute. The count drops to one.

| corpus     | anchors placed | probes per alignment at 4 | at the chosen count | saved     | survivors |
| ---------- | -------------- | ------------------------- | ------------------- | --------- | --------- |
| uniform    | 4              | 1.003932                  | 1.003932            | 0.0%      | unmoved   |
| skewed     | 4              | 4.000000                  | 4.000000            | 0.0%      | unmoved   |
| periodic16 | 1              | 1.187511                  | 1.000000            | **15.8%** | unmoved   |

Survivors have to stay put and do. The anchors dropped were refuting nothing. The bench checks it on every row instead of assuming it.

**Be clear about the size of this.** Fifteen percent of the probes is a few percent of the search, because the probes are one byte each and the verification behind them reads the whole needle. The reason to read coherence first is not this saving. It is that a corpus with a period cannot be filtered below `1/P` by anchors, however many are placed, and knowing that before the search is the difference between choosing a different discriminator and probing four times over for one bit.

**What it does not settle.** The periodic corpus here is a clean single orbit, the extreme case. On a clean orbit no anchor spacing helps, since the offset cancels out of the test entirely. A real corpus carries partial coherence, and the collapse would be partial with it. The spacing is computed and reported but not acted on: justifying that needs a partially coherent corpus, and there is not one here. `anchor_sift_anchors_for` returns 1 on any corpus that clears the detection floor, where a partially coherent corpus would want a count somewhere between one and four.

That is permutation invariance in the open. The histogram sees sixteen symbols at H2 exactly 4.0 and cannot see that the positions are one orbit, and no statistic of that order can.

**The verification floor was an artifact of a small corpus.** At 2789 bytes, one guaranteed occurrence per needle is a large share of the alignments. The arms converged. At 4 MB the 32 guaranteed occurrences sit in 134 million alignment tests and the floor is gone.

## bench_dispatch, which chose the rule the kernel now ships

The dispatcher used to branch on needle length alone. It never read `plan->collision_entropy` or `plan->distinct_symbols`. `ANCHOR_SIFT_FLAT_SHARE` and the whole of `two_to_the()` were unreachable, and the compiler said so on every build.

The repair was not to switch to the documented rule, because the documented rule is also wrong. `bench_dispatch` sweeps both thresholds over every combination instead of scoring the two that were written by hand, and it reports what it finds per corpus as well as overall.

| rule                                | picked fastest | cycles given up |
| ----------------------------------- | -------------- | --------------- |
| always inorder                      | 25 of 42       | 258,444,233     |
| always free                         | 17 of 42       | 54,159,531      |
| needle length alone, as shipped     | 21 of 42       | 178,923,873     |
| flatness then length, as documented | 33 of 42       | 153,483,501     |
| flatness alone                      | 41 of 42       | 1,975,242       |

**The flatness threshold survives the sweep and the needle length ceiling does not.** Every threshold from 0.34 to 0.96 scores identically, because the three corpora read 0.96, 0.33 and 1.00 and nothing lies between them. The 0.85 the kernel carried sits inside that interval and stays. The ceiling of 16 is beaten by having no ceiling: the free order arm is faster on a skewed corpus at every needle length from 4 to 256, by 2.95 times on average and 3.42 times at its widest.

Counting rows is the weaker of the two scores and both are printed. A rule that gets a row wrong where the arms differ by one percent has cost one percent, and cycles given up is what a dispatcher exists to minimize. On that score the shipped rule was giving up ninety times what the fixed one gives up.

Per corpus, for a caller who holds one:

| corpus     | flatness | run this         | free arm at  |
| ---------- | -------- | ---------------- | ------------ |
| uniform    | 0.9639   | `anchor_inorder` | no length    |
| skewed     | 0.3320   | `anchor_free`    | every length |
| periodic16 | 1.0000   | `anchor_inorder` | no length    |

## One defect left, unfixed because it is a decision

**Horspool is gone from the kernel and the older drivers still call it.** `bench_cycles.c` puts `anchor_sift_horspool` in its arms table. That driver does not compile, because no such symbol exists in the tree.

Horspool was also the wrong comparison. It needs an ordered index set and a shift table the size of the alphabet; the sift needs neither. Timing the two side by side on a byte line runs the sift in the one domain where discarding order gains nothing.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-24
