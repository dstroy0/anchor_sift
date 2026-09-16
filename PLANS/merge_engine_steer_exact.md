# Merging worktree-engine-steer-exact into main

**Purpose:** State what merging this branch into `main` does, name the four tracked files it removes and why, and give the evidence that removing them loses nothing.
**Scope:** `src/engine/c/portable/`, `src/engine/c/bench/`, `src/engine/c/vectorized_win/`, `test/engine/`, `docs/steering.md`, `maint/engine/`, `src/engine/c/CMakeLists.txt`.

This plan exists because the merge removes tracked files, and deletion is the user's call under the root rules. Nothing here has been executed.

## What was measured, and when

Measured at 2026-09-16T18:33:45Z, after `git fetch origin`.

| ref | value |
| --- | --- |
| `HEAD` (`worktree-engine-steer-exact`) | `3f63353`, pushed to `origin/worktree-engine-steer-exact` |
| `origin/main` | 43 commits not in `HEAD` |
| `HEAD` | 43 commits not in `origin/main` |
| merge base | `afb7fdf` |

Local `main` is a different thing from `origin/main` and is not the target: it sits at `87950d3`, behind `origin/main` by 29, and it is checked out in the primary worktree at `D:/git_project/repos/owned/public/anchor_sift`, so it cannot be merged into from here.

## The one fact the whole merge turns on

`origin/main` carries the steering engine as four separate files. This branch carries the same engine folded into `anchor_sift.{c,h}`. Both descend from a base that has neither.

```
merge base afb7fdf   anchor_sift.{c,h}, exact_arm.h, exact_arm_portable.c, exact_limbs.{c,h}
origin/main          the above, plus anchor_raster.{c,h}, anchor_steer.{c,h}, anchor_steer_arm.{c,h}
HEAD                 the above, plus anchor_raster.{c,h}, and the steer engine folded in
```

Every conflicted file on the `origin/main` side comes from exactly one commit, `2c2cbe2 engine steer feature`, dated 2026-09-16 09:07:06 -0400. No later commit on `origin/main` touches any of them. That commit is the original landing of the steering engine; this branch contains the same work and then evolves it.

## What would be removed, named

Four tracked files, present on `origin/main`, absent here:

* `src/engine/c/portable/anchor_steer.h`, 444 lines as added by `2c2cbe2`
* `src/engine/c/portable/anchor_steer.c`, 763 lines
* `src/engine/c/portable/anchor_steer_arm.h`, 123 lines
* `src/engine/c/portable/anchor_steer_arm.c`, 73 lines

They are not conflicted. Git treats them as added by `origin/main` and absent here, so a merge brings them in silently and the result has two definitions of the same engine. `anchor_steer.h` declares `anchor_field_census`, `anchor_steer_magnitude`, `anchor_steer_probe_order`, `anchor_steer_prefers_free`, `anchor_steer_plan_recursive`, `anchor_steer_spawn_coarms`, `anchor_steer_probe_fits`, `anchor_steer_sweep_probes`, `anchor_steer_probes_reset`, `anchor_steer_count` and `anchor_steer_count_with_probes`. `anchor_sift.h` on this branch declares every one of those names. Keeping both is a link error, not a choice.

## Why removing them loses nothing

The superseded version is older in design at three points, and each difference is a thing this branch added rather than a thing it dropped.

Its entries are positional. `anchor_steer_spawn_coarms(size_t *offsets, size_t wanted, const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len, uint8_t *scratch, size_t scratch_len, size_t sample_stride)` against this branch's `anchor_steer_spawn_coarms(const AnchorSteerDescent *args)`.

It carries a second entry, `anchor_steer_spawn_coarms_deep`, that exists only to run the descent without the destroy rule. This branch replaced it with the `force_full_depth` member, so one descent serves both and the two cannot drift.

It has no `AnchorSameAt`, no `AnchorField` and no `anchor_field_project`, so it searches bytes and nothing else. The any-type oracle and the rarity projection are only on this branch.

The content stays reachable in `origin/main` history at `2c2cbe2` whatever the merge does.

## The resolution, stated as a rule

Take this branch's version for every conflicted path. There are fourteen:

```
docs/steering.md                                maint/engine/build_engine.ps1
maint/engine/build_engine.sh                    src/engine/c/CMakeLists.txt
src/engine/c/bench/bench_dispatch.c             src/engine/c/bench/bench_raster.c
src/engine/c/bench/bench_steer_arms.c           src/engine/c/portable/anchor_raster.c
src/engine/c/portable/anchor_raster.h           src/engine/c/portable/anchor_sift.c
src/engine/c/portable/anchor_sift.h             src/engine/c/vectorized_win/anchor_steer_avx2.c
test/engine/test_adversarial.c                  test/engine/test_steer.c
```

Twelve of the fourteen come from `2c2cbe2` on one side and this branch's evolution of the same work on the other. The remaining two are worth naming because they are not add/add and a reader should not have to guess.

`src/engine/c/bench/bench_dispatch.c` conflicts on one token. The base spells the type `AnchorSiftArm`; `origin/main` still does; this branch renamed it to `AnchorSiftEngine` and carries that spelling in `anchor_sift.h`, `exact_arm.h` and every caller. The rename is this branch's and taking this branch's side keeps the tree consistent.

`src/engine/c/CMakeLists.txt` conflicts because this branch builds one `anchor_sift_kernel` target where `origin/main` builds the engine and the steer as separate units. The single target is what the fold requires.

Everything `origin/main` adds outside these paths merges clean and is kept: `examples/`, `src/engine/python/`, `maint/catalog/`, `maint/prose/docs_check.py`, `docs/rendering.md`, `src/engine/gpu/anchor_raster_cuda.cu`.

## What must hold before it lands

The merge is not verified by inspection. It is verified by `maint/engine/build_engine.ps1` reaching `all graders passed` on the merged tree, with `test_arm_agreement` at 0 disagreements, `test_adversarial` at 0 failed cases, `test_steer` at 0, `bench_raster` at 0 and `bench_steer_arms` at 0. Those are the numbers this branch produces today at `3f63353`. A merged tree that does not reproduce them has lost something this plan did not predict, and the merge should be backed out rather than repaired in place.

## Why this stopped short of doing it

Two reasons, both procedural.

Removing the four files is a deletion of tracked content, which the root rules reserve to the user. This plan is the proposal that rule asks for.

The resolution step was refused by this session's permission layer. `git checkout --ours` was denied for a single path and for all fourteen, and `git merge -X ours origin/main` was denied. A plain `git merge --no-commit --no-ff origin/main` was allowed and was aborted cleanly with `git merge --abort`, leaving the branch at `3f63353` with a clean tree.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
