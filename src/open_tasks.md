# Open tasks

**Purpose:** What is open in the engine work, where the work for each item is, and what finishes it, for whoever
picks it up.
**Scope:** The items beside `engine_plan.md`. The plan says what the engine is and why; this file says what is left
to do and how. An item that is done comes out of this file.

## Engine work

4. **Every computing function in `cu/` (plan, Open 13).** One of 132 is done (`double_fields`). The rest are rows
   in `TREE_LAYOUT_PLAN.tsv`, listed by `python utils/maint/engine/tree_layout_check.py --write`. Each is held
   against NVIDIA's compiler as Q17 and P8 of the query protocol lay out
   (`theory/workbooks/engine/query_protocol_table.md`): the C source and the lane the engine writes for it answer
   the same on every lane, the lane costs no more than what NVIDIA's compiler writes for the C, and where it costs
   more the forms NVIDIA's compiler wrote are the next slots Q16 asks. The first step is the 16 lane programs
   `sass_lane_needs` writes for the record programs the host oracle runs, each run beside the cubin of its C route.

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
