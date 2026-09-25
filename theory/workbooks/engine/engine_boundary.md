# The engine's boundary

**Purpose:** Two rulings on what the engine may hold, with the dates they were made and what prompted them, so no later build crosses either.
**Scope:** everything under `engine/`.

## The engine carries no cell tracking (Doug, 23 September)

Never put cell-specific tracking into the engine. Doug had said it at length before this ruling.

Restated 25 September (Doug): "absolutely anything to do with tracking microorganisms goes into cell tracking, not into the engine." Basins (binomial_basins' steepest-ascent cut, basin_overlap) are tracking, a concept only: they live in cell_tracking/src and drive the engine's generic calls (engine_residual, grow_leaves, linking). They were deleted from the engine on his order, and they are not to be put back there; the question is closed.

- The engine holds math only: trees, cuts, overlaps, fields, exact integers. Nothing in engine/ may name or know about cells, divisions, daughters, key cells, moves, merges, appear/disappear, or grading against the answer key.
- Cell semantics and oracle grading go in cell_tracking/. They compose the engine's generic outputs there.
- Before adding any field, kernel or request member under engine/, check it names a mathematical object, not a biological one. If unsure, ask Doug first.

What prompted it: in the 9c/9d overlap work, max_tree got
- the division_voxels and key_voxels requests;
- the key_parted, key_caught, key_present, key_apart, key_cells_present and key_cells_alone fields, and the disappear, appear, divisions and merges fields;
- the division and key-cell kernels.

engine/base/oracle/score_sample also got the key-division and key-cell grading.

## The engine is optimized for no scale (Doug, 23 September)

Doug: "what we want to avoid is optimizing the engine for any particular scale, which is what you have been consistently doing that I have been having you rip out over and over, it's dangerous".

- The engine is optimized for no scale. Never write a size, spacing, binomial order, entropy window, jitter width, cell size, voxel size, chunk size tuned to data, or memory fraction into engine/. Each comes in the request or is read from the data.
- A word's width or a file format's specification is not a scale. Where a word is too narrow, raise a request error or report `needed_bits`. Never round, clip, or cap to fit.
- The engine table's "scale audit" ([engine_table.md](engine_table.md)) lists every scale still in the machine, as debts. Check it before adding any constant under engine/, and add to it rather than hiding one.
- The cell table and the engine table stay separate documents. They are optimized against each other only through their interface sections, never merged.
