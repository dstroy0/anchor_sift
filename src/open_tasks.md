# Open tasks

**Purpose:** What is open in the engine work, where the work for each item is, and what finishes it, for whoever
picks it up.
**Scope:** The items beside `engine_plan.md`. The plan says what the engine is and why; this file says what is left
to do and how. An item that is done comes out of this file.

## First

1. **Ask the part how it loops (plan, Open 14).** This is the next piece of work. The probe ask that puts each candidate in `loop_back`'s place to
   the part is not written. The plan gives the design. What the existing pieces need from it:
   - `sass_cubin_answer` in `utils/test/engine/compiler/cell/cell_sass_probe_ask.c` passes fixed input words; the
     loop ask needs N as word 0.
   - The pattern kernel `form_0` loads word 0 into R0 and word 1 into R7, and stores R7 as the first answer word.
   - Candidates fill register operands with a register the loop does not keep (it keeps R0, R2 to R5, R7, R9 and
     P0).
   - A mode of `cell_sass_probe_main.c` that reads the machine file already learned (`sass_machine_read`) and an
     existing pattern folder runs the ask alone, without the 50-minute relearn.

## Branches waiting to land

2. **`cu-tree-loops`: paths the cu move left behind.** It repoints:
   - `.cu` paths built from a loop variable, `"$OBSIGNATIO/$name.cu"`, in `src/engine/quantum/qasm/build.sh`,
     `src/sims/run.sh` and `utils/test/engine/runtime/daemon/run.sh`, to their `_CU` directory;
   - `"$QASM/qasm_bitstring.cu"` in both qasm `run.sh`, where `QASM` comes from the `build.sh` they source;
   - includes of a header in the other half of a directory the move split: 26 `.cu` files
     under `src/cu/` name the header by its path;
   - `utils/maint/engine/build_gpu_raster.ps1`, which builds `raster.cu` and `raster_entry.cu` from `src/cu/engine/render`.

   `qasm` and `daemon` pass on it. To finish: run every suite on the branch and compare each with the tree before the
   move, `8b5d77b0`. Four fail on both trees for reasons outside the move: `cell_ptx` (NVRTC gives no header, 10 of
   10 checks), `ruleset_read` (4 of 59 checks), `engine_c` (the CMake cache in `build/engine_c` names another
   checkout's paths) and the three suites that run under WSL. Run a suite's script with Git Bash: `bash` on the
   Windows path is WSL's, which has no nvcc.

3. **`cu-ports-2`: reading SASS back, the loop check, and the branch distance.** In
   `src/engine/compiler/cubin/sass_assemble.{c,h}`:
   - `sass_encoding_read` reads an encoding back into its instruction through the machine file's forms, with no
     disassembler;
   - `sass_loop_walk` checks one emitted instruction as a loop's way back, on or off, and never changes it;
   - a branch's distance is placed from bit 34 in four-byte steps; bits 32 and 33 belong to the operation (`BRA`,
     `BRA.U`, `BRA.DIV`).

   The plan's "Functions on every part" section has the design and what was checked. To finish: run `cell_sass`
   (about 50 minutes), `cell_ptx` and the codegen suites on the branch to confirm the assembler's other output is
   unchanged. Ordinary branches encode the same bits as before; only a form with bits set at 32 or 33 changes.

## Engine work

4. **Every computing function in `cu/` (plan, Open 13).** One of 132 is done (`double_fields`). The rest are rows
   in `TREE_LAYOUT_PLAN.tsv`, listed by `python utils/maint/engine/tree_layout_check.py --write`. A function with
   no branch and no loop is a record program held 1:1 against its original, as `double_fields_test.cu` does. A
   function with loops, `decimal_double` the first, waits on item 3.

5. **Open 1: the query-protocol ask on `host_entry.h`, and the run channel made of those asks.** The plan's Open 1
   has the state. Closing it takes NVRTC, nvJitLink and the CUDA runtime out of the loop.

## Decisions for Doug

6. **Python's copy of `double_fields`.** No Python ruleset exists, and `L*` has not learned Python. Until it has,
   the Python copy is written by hand from the same record program, or waits.

7. **From `TREE_LAYOUT_PLAN.md`:**
   - the Python import root: 155 files put `src/engine/python` on `sys.path` and import its parts by name, and 29
     import `exact` or `constants` from `representation`, which move to `types/integers`;
   - the tracker's copies in `src/engine` that differ from `examples/cell_tracking`'s: `run_cfg.cu` by 142 lines,
     `run_cfg.h` by 12, and six split files in `link_objects` and `relate_frames` with no file of their name in the
     tracker;
   - one name for each function held under two names in 16 modules (render, the daemon, qasm, `types/integers`
     and others, listed in the plan's "Functions under two names").

   The c stage and the python stage of the move follow the same steps as the cu stage.

## Upkeep

9. **Comments in `src/`:** the pass that rewrites comments against the voice oracle and takes history out of them,
   and the batches of history comments that need Doug's approval before they change.
10. **The manifest's signature:** Doug re-signs it; nobody else does.
11. **Generated provenance lines:** four still name `maint/` paths that are now under `utils/maint/`.
12. **Words for `utils/maint/prose/voice.tsv`:** coins, contends, descends, overflow, prints, prune, sixteenths,
    steered, wrongly, and the possessives ladder's, link's, noise's, spread's, term's and remainder's. Doug adds
    the terms of art; the prose passes then run again with `--offlist`.
13. **Re-read the comment, README and date edits in `src/engine` against the tree.**
14. **Peer pull requests:** review each as it opens and merge it once it holds.
