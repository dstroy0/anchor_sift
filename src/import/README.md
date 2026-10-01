# Toolbox

**Purpose:** Say what each compartment of `tools/` is for, which compartment a new tool belongs in,
and what every tool in the tree answers. Sixty-four tools in eight compartments, three proofs in a
ninth that sits outside `tools/`, and the rule that decides placement stated before the lists.
**Scope:** `tools/{audit, book, chain, check, hardware, prose, radar, view}` and
`examples/proofing/`. Counts and claims below were taken from the files on 2026-09-10.
**Owner:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-10

## The Rule That Decides Placement

A tool goes in the compartment named by **what it reads**, and never by what subject it is about.

| compartment | reads                                                                | count |
| ----------- | -------------------------------------------------------------------- | ----- |
| `audit/`    | a bench's own output or binary, and grades it against something else | 6     |
| `check/`    | the hash, and asks one question of its structure                     | 9     |
| `view/`     | a state or a table, and turns it into a page or a reading            | 38    |
| `radar/`    | the residue spectrum, with a receive chain over it                   | 3     |
| `hardware/` | a circuit or a batch, simulated instead of assumed                   | 2     |
| `prose/`    | this tree's own text                                                 | 3     |
| `book/`     | the theory sources                                                   | 2     |
| `chain/`    | the network                                                          | 1     |

**Proofing is a ninth compartment and it lives outside `tools/`.** Everything that establishes a
number the rest of the work is graded against sits in `examples/proofing/`, because a proof of a
measurement is a worked run and belongs beside the other worked runs. `tools/audit/` is also
untracked in this tree by `.gitignore`, and a proof left there would not be carried at all.

| tool                                     | what it establishes                                                                                                       |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `examples/proofing/natural_constants.py` | Pi, the roots, the placement angle and the harmonic unit to any length, verified against 2,048 published bits             |
| `examples/proofing/precision_floor.py`   | That a measured floor belongs to the number format, by computing a null the law puts at exactly zero, at rising precision |
| `examples/proofing/precision_plot.py`    | Eight arms and eight precisions on one axis, fitted against a prediction with no free quantity in it                      |

The three answer one question between them: what a floor belongs to. Measured slope 0.9861 decades
per digit against a prediction of 1.0000, worst departure 0.246 decades over 55 orders of magnitude.
See `docs/reading-transforms.md` §7 and the theory chapter's `sec:precisionfloor`.

The distinction between `audit/` and `check/` gets misfiled most often. `check/` asks a question
about SHA-256 and answers it from a computation it performs itself. `audit/` asks a question about a
measurement somebody already made and answers it by re-deriving that measurement independently. A
tool that recomputes what a bench printed belongs in `audit/` even when its subject is the hash, and
`verify_renyi.py` is the worked example.

Eighteen of the sixty-six carry a `--check` entry point that tests the tool on a case whose answer is
known before it is trusted on a case whose answer is not.

## audit/ -- grading a measurement somebody already made

| tool                  | what it answers                                                                |
| --------------------- | ------------------------------------------------------------------------------ |
| `audit_constants.py`  | Was a number a bench printed already sitting in its binary as a folded literal |
| `audit_diff.py`       | Which bench outputs differ between optimisation arms, ignoring wall clock      |
| `audit_seeds.py`      | How far does each number move when only the seed changes                       |
| `conserve_headers.py` | Do the deficit measurements conserve across headers                            |
| `sweep_phase.py`      | Do the deficit ratios survive a change of window phase                         |
| `verify_renyi.py`     | Recomputes every prediction `bench_renyi` printed, independently of the binary |

This whole directory is untracked by `.gitignore:23`. A tool that grades somebody's measurement is
worth keeping locally and is not part of what this tree carries, anything whose answer the tree
depends on belongs in `examples/proofing/` instead. That distinction was found by trying to commit
three proofs into here and being refused by the ignore rule.

## check/ -- one question about the hash, answered from scratch

| tool                         | what it answers                                                                      |
| ---------------------------- | ------------------------------------------------------------------------------------ |
| `check_monotone.py`          | Does the field ever gain structure, or only lose it                                  |
| `check_ridge_common_mode.py` | What is left in the residue fold once the common mode is removed                     |
| `check_rotation_residues.py` | Are the positive residue classes the round function's own rotation amounts           |
| `check_slant.py`             | Is there structure along diagonals in the input-bit field                            |
| `check_tilt.py`              | Are the periodic spikes in the input-bit shadow real, and aligned at a tilt          |
| `check_two_sources.py`       | Do two sources share residue structure class by class                                |
| `check_word_collapse.py`     | Which message word loses its structure first                                         |
| `check_word_pairs.py`        | Is the word-pair distribution anything beyond the light cone and the register chains |
| `language_of_nature.py`      | Which of the two linear languages has grip on natural data                           |

## view/ -- states and tables, into readings and pages

Thirty-six tools, and they split three ways. `view/README.md` carries the split with the mathematics
stated for each module, since that is where the equations belong.

- **Mathematics**, standard library only where it can be: `sphere_field`, `boundary_read`,
  `reading_rank`, `boundary_count`, `torus_count`, `cut_project`, `octant_lex`,
  `quotient_coherence`, `arm_draw`, `dsp`, `exact`.
- **Page builders**, seventeen of them, each turning one kind of input into one page.
- **Gates and support**: `null_harness`, `grid_error`, `frame_audit`, `script_check`, `gpu_pack`,
  `out_path`, `settings`, `make_shadow_figure`.

## radar/, hardware/, prose/, book/, chain/

| tool                           | what it answers                                                          |
| ------------------------------ | ------------------------------------------------------------------------ |
| `radar/radar_assay.py`         | Does removing a sub-function remove its residues                         |
| `radar/radar_receive.py`       | A receive chain applied to the residue spectrum                          |
| `radar/sei_round_constants.py` | Does the per-round modulation carry the round constants                  |
| `hardware/batch_invariant.py`  | Which bits are guaranteed invariant across a batch of consecutive nonces |
| `hardware/compressor_test.py`  | How far a change travels through a real compressor tree                  |
| `prose/docs_check.py`          | The prose standard, applied to the text these files carry                |
| `prose/printed_check.py`       | The same standard, applied to the text these tools print                 |
| `prose/gate.py`                | Both of the above in one command, over `.cu`, `.cpp` and `.html` as well |
| `book/build_bibliography.py`   | The book's bibliography, from the citations registry, pinned to a commit |
| `book/build_theory.sh`         | Every theory book, two passes of LuaLaTeX, into `build/theory/`          |
| `chain/fetch_blocks.py`        | Recent block headers from a public explorer, as a corpus                 |

`docs_check.py` and `build_theory.sh` are symbolic links into `anchor_sift`, so one banned table and
one build script serve both trees. **`build_theory.sh` currently dangles**, because `maint/book/`
there became `maint/tex_book/`. Repairing it needs elevation and touches two repositories.

**Do not reach around that dangling link to the script at its own path.** It sets
`ROOT=$(dirname "$0")/../..`, so running it there builds `anchor_sift`'s theory tree and reports a
plausible byte count while touching nothing here. Compile this tree by calling `lualatex` directly
from the book's own directory with `-output-directory` pointed at `build/theory/<book>`.

## What The Prose Gate Could Not See, In One List

Three gaps, and they are one defect wearing three extensions. In each case the gate returned a clean
result over files it had never opened, and a gate cannot report that failure on itself.

| gap                                                 | what was unread                                                                     | found by                                                     |
| --------------------------------------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `.cu` and `.cpp` absent from the checked extensions | 50 C-family source files, against the 12 named by `.c` and `.h`                     | handing it a `.cu` path and getting "2 files checked" from 3 |
| `.html` absent                                      | every viewer template, 301 findings across six, 217 in the room template alone      | handing it four templates and getting "no files were read"   |
| printed text read in `.py` alone                    | every C and C++ string literal, including 56 lines already edited by hand in `src/` | reading a bench's own output after a clean gate run          |

`prose/gate.py` closes the first two by extending the table's extension tuple for the length of a
run and saying in its output that it did. The third is open: `printed_check.py` parses Python to
find the literals handed to `say`, `print` and `stdout.write`, and nothing yet reads the arguments of
`std::printf`.

All three belong upstream in `anchor_sift/maint/prose/docs_check.py`, where one line serves every
tree at once, and `gate.py` is the local stand-in until that lands.

## Running Every Gate

```sh
python tools/prose/gate.py                       prose in the files and in what they print
python tools/view/script_check.py --check        every viewer template parses, every loop is watched
python tools/view/data_check.py --check          no page reads a data key its own JSON lacks
python tools/view/inert_report.py --check        which optional features a built page leaves inert
python tools/view/null_harness.py --floors       the measured floors, after the harness proves itself
python examples/proofing/precision_plot.py --check     the precision line, gated on its slope
python examples/proofing/natural_constants.py --check  2,048 published bits, recomputed from the primes
python tools/view/grid_error.py --check          the drawn picture against the field it approximates
```

## Two Grouping Defects, One Repaired

Both are in `view/` and both were the same defect at different ages.

**Ten of seventeen builders wrote their page beside their own source. All seventeen now call
`out_path.resolve`.** Each converted builder was run twice, with `VIEW_OUT` set and on the default,
to check that both paths resolve. `build_blob_view.py` given `README.md` used to drop
`README_view.html` in the repository root and now lands it under `build/view/`. Four of the ten
carried no `--out` flag; their default was routed through `out_path` and no flag was invented for
them, since adding one is a change of interface and not a conversion.

**Seven built pages are still sitting in `tools/view/`,** left from before the conversion. Every one
now has a counterpart under `build/view/`, so none of them is the only copy of anything. The three
oldest are stale by hours; the four that existed nowhere else were rebuilt by the conversion and
match to within a byte or two, the difference being content that is not fixed between runs.
`tools/view/README.md` carries the sizes.

**Why the seven are a hazard and not untidiness.** A reader who opens
`tools/view/sha_clock_view.html` gets a page ten hours old with no error anywhere. And `tools/view`
is linked into `anchor_sift/examples/00_blob_viz_tools/view`, where loose files in the holder are a
known breakage.

They are not removed here. Removing generated pages from a tracked directory is a decision about the
tree and not a repair, so it is Douglas's.
