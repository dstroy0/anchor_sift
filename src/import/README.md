# Toolbox

**Purpose:** Say what each compartment of `tools/` is for, which compartment a new tool belongs in,
and what every tool in the tree answers. Twenty-six tools in seven compartments, three proofs in an
eighth that sits outside `tools/`, and the rule that decides placement stated before the lists.
**Scope:** `tools/{audit, book, chain, check, hardware, prose, radar}` and
`examples/proofing/`. Counts and claims below were taken from the files on 2026-09-10.
**Owner:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-10

## The Rule That Decides Placement

A tool goes in the compartment named by **what it reads**, and never by what subject it is about.

| compartment | reads                                                                | count |
| ----------- | -------------------------------------------------------------------- | ----- |
| `audit/`    | a bench's own output or binary, and grades it against something else | 6     |
| `check/`    | the hash, and asks one question of its structure                     | 9     |
| `radar/`    | the residue spectrum, with a receive chain over it                   | 3     |
| `hardware/` | a circuit or a batch, simulated instead of assumed                   | 2     |
| `prose/`    | this tree's own text                                                 | 3     |
| `book/`     | the theory sources                                                   | 2     |
| `chain/`    | the network                                                          | 1     |

**Proofing is an eighth compartment and it lives outside `tools/`.** Everything that establishes a
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

## audit/ -- grading a measurement somebody already made

| tool                  | what it answers                                                                |
| --------------------- | ------------------------------------------------------------------------------ |
| `audit_constants.py`  | Was a number a bench printed already sitting in its binary as a folded literal |
| `audit_diff.py`       | Which bench outputs differ between optimization arms, ignoring wall clock      |
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

`docs_check.py` and `build_theory.sh` are symbolic links into `anchor_sift`. One banned table and
one build script serve both trees. **`build_theory.sh` currently dangles**, because `maint/book/`
there became `maint/tex_book/`. Repairing it needs elevation and touches two repositories.

**Do not reach around that dangling link to the script at its own path.** It sets
`ROOT=$(dirname "$0")/../..`, and running it there builds `anchor_sift`'s theory tree and reports a
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
python examples/proofing/precision_plot.py --check     the precision line, gated on its slope
python examples/proofing/natural_constants.py --check  2,048 published bits, recomputed from the primes
```
