# cell_tracking

This program looks at 3D microscope movies of cells and works out which cell in one frame becomes which cell in the next frame. When it has the right answers for a movie, it also tells you how many links it got right.

Follow the steps below in order. Do not skip any. Every command is typed exactly as shown.

## What you need before you start

1. **An NVIDIA graphics card.** It will not run without one. It was built on an RTX 3070.
2. **The CUDA toolkit**, which gives you a program called `nvcc`. To check you have it, open a terminal and type `nvcc --version`. If it says "not found", install the CUDA toolkit from NVIDIA first.
3. **On Windows only: Visual Studio Build Tools 2022.** `nvcc` needs it to work. You do not open it; the build script finds it on its own.
4. **Git Bash** on Windows, or any normal terminal on Linux. Every command below runs in that terminal, not in PowerShell and not in cmd.
5. **The exact integer code.** It comes with this repository, at `../../src/engine/base/no_rounding`, and the build finds it there on its own. To build against another copy, type `export ANCHOR_EXACT_ROOT=/your/path/to/no_rounding` before you build.
6. **About 90 GB of free disk space** for the compressed copy of the training movies (step 3).

## Step 1: get the data

Download the competition data from Kaggle and unpack it. You should end up with a folder that looks like this:

```
D:/kaggle_project_data/biohub_cell_tracking_data/
    train/
        44b6_0113de3b.zarr      <- a movie
        44b6_0113de3b.geff      <- the right answers for that movie
        ...
    test/
        44b6_0113de3b.zarr      <- a movie with no answers
        ...
```

This folder is called the **source**. The program only ever reads from it. It never writes into it, and you must never put anything else in it.

If your data is somewhere else, that is fine. You will tell the program where it is in step 4.

## Step 2: build the program

Open a terminal in this folder (`examples/cell_tracking`), then type:

```
bash build_driver.sh
```

Wait. It takes a few minutes. When it is done, the last line says:

```
  published .../build/track_driver.exe
```

The build also makes `tessera_daemon.exe` and copies it next to the program. Leave it there: every run uses it (see "Sharing the graphics card").

If the last line says `build failed`, read the line above it. It names the file that did not compile. Nothing half-built is left behind; you cannot run an old build by mistake.

The finished program is `../../build/track_driver.exe` (on Linux, `../../build/track_driver`), in the repository's `build/` folder, the only place in the repository any build writes to.

Each build compiles into its own `../../build/<date>_<time>_driver/` folder, then copies the program up into `../../build/`. A build folder older than a day is removed when the next build starts. Nothing else in `../../build/` is removed; `../../build/logs/` stays.

If you want the build somewhere else, put `BUILD_OUT=/some/folder` in front: `BUILD_OUT=/some/folder bash build_driver.sh`. That folder is used as it is and nothing is removed from it.

## Step 3: make the set (do this once)

The movies are big and slow to read. So first, the program copies every movie into its own compressed format, called `.kcr`. The folder it copies them into is called the **set**.

The set must **not** be inside the source folder. Put it next to it:

```
../../build/track_driver.exe --ingest --source D:/kaggle_project_data/biohub_cell_tracking_data/train D:/kaggle_project_data/biohub_cell_tracking_set/train 44b6_0113de3b
```

That line means:

- `--ingest`: copy movies into the set
- `--source ...`: where the movies are
- the next path: where the set goes
- `44b6_0113de3b`: which movie to copy. You can list as many names as you want, with spaces between them.

For each movie it prints one line like this:

```
  44b6_0113de3b            8 floors, rebuilt from the file, voxel for voxel and pixel for pixel:   396922152 bytes of   838860800,  47.3%, sealed ad3d9846d452df4db5159019b592dfec6e375a1915f88e96fa42f988e7f965ee
```

"Rebuilt from the file, voxel for voxel" means it checked the copy: it unpacked the copy and compared every single pixel against a second, fresh read of the original movie. If even one pixel is different, it deletes the copy and tells you. **You never get a bad copy.** A movie takes about 25 seconds.

When it is done, the set holds one folder per movie, with the movie's `.kcr` in it. Later parts add files beside it:

```
D:/kaggle_project_data/biohub_cell_tracking_set/train/
    44b6_0113de3b/
        44b6_0113de3b.kcr      <- the compressed movie (--ingest)
        44b6_0113de3b.knf      <- its noise floor (--run entropy or --run floor)
        44b6_0113de3b.kcs      <- its body table, when one has been written
    train.ksh                  <- every body of every movie as one number each (--run flatten)
```

The `.ksh` is named after the set's own folder: a set at `.../train` keeps it at `.../train/train.ksh`.

The right answers (`.geff`) are **not** copied. The program reads them straight from the source when it scores.

### How much space the set saves

Every movie in the competition, all 199 training movies and the 4 test movies, was copied this way on 22 September,
before the seal was added:

| | bytes |
|---|---|
| the movies as they came, as plain 16-bit pixels | 170,288,742,400 |
| the same movies as `.kcr` | 63,555,427,780 |
| saved | 106,733,314,620 |

So the set was **37.3%** of the size of the movies, and every pixel still comes back exactly. The smallest copy
was 28.6% of its movie (`6bba_705ec2c9`) and the largest 50.3% (`44b6_a2bb48bb`).

With the seal, a copy is larger. `44b6_0113de3b` was 341,008,288 bytes (40.6%) on 22 September and is
396,922,152 bytes (47.3%) when ingested on 24 September. That is 16.4% more. The seal's measured cost is 5.4% of
a crystal; it doesn't explain the whole difference. The set has not been re-measured.

To see it come back yourself, unpack every copy from the copy alone and check it:

```
../../build/track_driver.exe --run kcr-prove D:/kaggle_project_data/biohub_cell_tracking_set/train 44b6_0113de3b
```

It prints one line per movie, naming the root of its seal, which it checks node by node. It also prints a total
for all of them, and the set's root over every movie's root.

**This is nowhere near as small as it can get.** Right now the `.kcr` keeps the camera's noise exactly as it is, bit for bit. That noise is most of what is left: the lowest five bits of every pixel flip in about half of all frames, like a coin, everywhere in the movie. But that noise is not random. It is the same for a given movie every time; it can be worked out instead of stored. When those noise patterns are worked out and applied to the whole set at once, those bits no longer have to be kept, and the copy shrinks toward its true floor. That work is waiting deliberately. The first job is the tracking itself: finding every cell, following it, and catching when it divides or dies. Squeezing the files further comes after.

### What movie formats it can read

You do not have to use zarr. Any of these work, and they all end up as the same `.kcr`:

| format | file or folder name |
|---|---|
| zarr (version 2 or 3) | `name.zarr` folder |
| N5 | `name.n5` folder |
| OME-Zarr | `name.ome.zarr` folder |
| TIFF, BigTIFF, OME-TIFF, ImageJ TIFF | `name.tif`, `name.tiff`, `name.ome.tif` |
| HDF5 | `name.h5`, `name.hdf5` |
| NumPy | `name.npy`, `name.npz` |
| NRRD | `name.nrrd`, `name.nhdr` |
| NIfTI | `name.nii`, `name.nii.gz`, `name.hdr` + `name.img` |

The pixels must be whole numbers, 8 or 16 bits, not negative. If they are not, the program refuses the movie and tells you why. It never guesses.

The program needs to know which direction in the file is time (`t`), depth (`z`), up-down (`y`) and left-right (`x`). Most files say so themselves. If yours does not, the program stops and asks you to name them. Add `--axes` with the letters in the order the file stores them, for example `--axes tzyx`.

## Step 4: tell the program where everything is

Settings live in `.cfg` files. `base.cfg` in this folder has every setting. Ready-made ones are in `cfg/`, also in this folder.

Open the `.cfg` you want in a text editor and find the `input` part:

```
  "input": {
    "source": "D:/kaggle_project_data/biohub_cell_tracking_data/train",
    "set": "D:/kaggle_project_data/biohub_cell_tracking_set/train",
    "axes": null,
    "samples": [],
    "first": 2,
    ...
```

- `source`: the folder from step 1
- `set`: the folder from step 3
- `axes`: leave it `null` unless step 3 told you to name the axes
- `samples`: the movies to run, like `["44b6_0113de3b", "44b6_0b24845f"]`. Leave it `[]` to use `first` instead.
- `first`: when `samples` is empty, run this many movies from the set, in name order

Use forward slashes `/` in paths, even on Windows.

## Step 5: run it

From this folder:

```
../../build/track_driver.exe --cfg cfg/one.cfg
```

You will see one line per movie, then a total:

```
  sample                   edges  correct/branched/wrong/no link/missed
  44b6_0113de3b            50     38/0/12/0/0   100 frames, ...

  POOLED over 50 ground truth edges:
    correct link              38   76.0%
    target among branches      0   0.0%
    wrong link                12   24.0%
    no link made               0   0.0%
    endpoint undetected        0   0.0%
```

What the rows mean:

| row | meaning |
|---|---|
| correct link | it linked the cell to the right cell in the next frame |
| target among branches | it linked the cell to the right cell, but also to other cells |
| wrong link | it linked the cell to the wrong cell |
| no link made | it did not link the cell to anything |
| endpoint undetected | it never found the cell at all |

For a test movie there are no right answers; it prints `no answer key ...; run unscored` and the counts stay at 0. That is normal.

Every run also adds one line to `logs/track_driver.log` beside the program, which is `../../build/logs/track_driver.log` for the one the build publishes; you can compare runs later. `--log <file>` puts it somewhere else.

### Changing a setting without editing the file

Anything you type **after** `--cfg` wins over the file. For example, to run just one other movie:

```
../../build/track_driver.exe --cfg cfg/one.cfg D:/kaggle_project_data/biohub_cell_tracking_set/train 44b6_0b24845f
```

The first path after the flags is the set, and every word after it is a movie name.

## The two steps: ingest, then run

The program does two different jobs, and they never mix.

1. **`--ingest`** makes the set (step 3). It is its own step and runs nothing else. The program refuses `--ingest` together with `--run`; you cannot re-copy movies you already copied by accident.
2. **`--run <part>`** works on a set that is already made. Name one part after each `--run`. You can give `--run` as many times as you like, and the parts run in the order you typed them. If one part fails, the parts after it do not run.

| part | what it does |
|---|---|
| `schedule` | work out how many frames fit on your graphics card at once and write the plan to the path given by `--plan` |
| `kcr-prove` | unpack every copy in the set from the copy alone and check that every node of its seal holds |
| `entropy` | work out the noise floor of each movie and store it next to its `.kcr` as `.knf` |
| `floor` | lay down that noise floor, keeping a `.knf` that already matches its `.kcr`. If the `.cfg` turns `floor` on, this part runs first without being asked |
| `flatten` | turn every body in every frame of the set into one number and save them all as the set's `.ksh` (`<set>/<set folder name>.ksh`) |
| `track` | link the cells and score the links (step 5). This is what runs when you give no `--run` at all |
| `fingerprint` | read the set's `.ksh`, give every body a print, and check the prints on the graphics card against the same work done on the processor |

For example, to check every copy, lay down the noise floor, and then track, in that order:

```
../../build/track_driver.exe --cfg cfg/one.cfg --run kcr-prove --run floor --run track
```

Other flags:

| flag | what it does |
|---|---|
| `--plan plan.json` | where `--run schedule` writes its plan |
| `--cfg-out used.cfg` | save the exact settings the run used; you can run it again later |
| `--log path` | write the run log somewhere else |
| `--override` | let a job run even though it declares more memory than its request's kept peak (see below) |

## Sharing the graphics card

Every run goes through **tessera**, the one scheduler for your graphics card
([../../src/engine/daemon/README.md](../../src/engine/daemon/README.md)). `--ingest` is one job, and so is each `--run` part. Before
the part starts, the program asks tessera for room on the card. The part runs only once tessera admits it, and when
the part ends the program releases the job. If no tessera is running, the program starts the `tessera_daemon.exe`
beside it. The daemon closes by itself a few seconds after the last job ends.

Each job:

- **declares** the largest movie's size in 16-bit pixels.
- **is keyed** by the part's name and the whole settings file the run used. So the same run on the same movies is
  the same job every time.
- **is measured** on the card while it runs. Tessera keeps the most it ever held, its **peak**.

You see a line when a job starts and one when it ends:

```
  tessera: ingest admitted, 838860800 bytes reserved
  tessera: ingest released, peak 5091037184 bytes, more than it declared
```

"More than it declared" is expected the first time. A movie's pixels are a fraction of what a part holds on the
card. From then on, the same run is reserved its kept peak, not its declaration. So the second time it says, for
example, `kcr-prove admitted, 3958566912 bytes reserved`.

If a job declares more than its kept peak, tessera holds it and asks. The program then waits for its holding time
(2 seconds), and the job is lost: the part fails and says so. Its ticket is appended, sealed, to tessera's lost and found log, `hst/lnf.log` in tessera's state folder; the
message names the file. Run it
again with `--override` to let it run anyway.

If the program cannot reach tessera or start it (`the daemon (...) did not take the job`), nothing runs. There is no
way to run without it.

## When something goes wrong

| you see | what to do |
|---|---|
| `nvcc: command not found` | install the CUDA toolkit |
| `no host compiler nvcc accepts on this platform was found` | install Visual Studio Build Tools 2022 (Windows) |
| `no exact_integer.h under ...` | set `ANCHOR_EXACT_ROOT` (see "What you need") |
| `no source for it under ...` | the movie name is wrong, or `source` points at the wrong folder |
| `its .kcr in ... did not load and prove` | you have not done step 3 for that movie, or `set` points at the wrong folder |
| `the source's N axes are not all named t z y x` | add `--axes` (see step 3) |
| `usage: track_driver ...` | it did not get a set or any movie names; check the `input` part of the `.cfg` |
| `tessera: ... the daemon (...) did not take the job` | `tessera_daemon.exe` is missing from beside the program (rebuild), or its history was refused (the daemon names the file; see [../../src/engine/daemon/README.md](../../src/engine/daemon/README.md)) |
| `tessera: ... was held past its holding time and lost` | the job declared more than its kept peak; rerun with `--override` if that is meant |

## Where the results are written up

Every measured result, what was tried and what it gave, is in `../../theory/workbooks/cell_tracking/ledger.md`. What the tracker does for each part of the problem and what it still needs to do is in `../../theory/workbooks/cell_tracking/cell_tracking_table.md`; the engine it runs on has its own table, `../../theory/workbooks/engine/engine_table.md`.
