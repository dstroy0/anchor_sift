# n-body tracking on the core engine

**Purpose:** Track many bodies through time as a configuration of the core engine, not as a second engine beside it.
**Scope:** `src/engine/n_body/`, and the core parts it calls: the shift-agreement detector and its number-theoretic transform, the partition and reference, the measure, and the sift.

n-body tracking is the natural fork of this engine. A frame is a field of points carrying values, the same representation every domain uses, and tracking asks which point in the next frame is the same body as one in this frame. The reference implementation is an exact-integer tracker over a series of 3D microscopy volumes: no floating point value is formed, the volume is handed to the engine as raw bytes, and everything after is integers. On a labelled 25-sample benchmark over 40 frames it links 96.7 percent of the answer key's 2511 edges correctly with none of the labelled endpoints missed. That tracker carries its own copy of the engine. This directory is the fork that calls the core engine instead, so one engine reads both a corpus and a volume.

## What is shared and what is promoted

The core engine and the reference tracker share two things: exact-integer arithmetic with no float and no rounding, and the shift-agreement idea, a period or an offset read from how often a shift agrees with itself. They do not yet share code. The core carries no number-theoretic transform, no watershed, no basin overlap and no assignment matching. So the fork promotes the tracker's exact engines into this directory, where they become core-engine code configured for tracking, instead of calling functions that do not exist.

| tracking stage | where it comes from |
|---|---|
| view motion between frames | an exact multi-lag number-theoretic transform modulo 998244353, promoted here as the core's exact all-lag agreement engine |
| basins over the residual | a binomial-smoothing residual and a steepest-ascent watershed in exact limbs, promoted here |
| overlap between consecutive frames | shared positive voxels with the view motion removed, promoted here |
| the heaviest one-to-one matching | a min-cost assignment on integer costs, promoted here |
| the growing tree, the linker, the scoring | the n-body configuration, specific to tracking, and the part that never generalizes into the core |

The core's own shift-agreement reader is a different construction. It reads a single lag and it forms floats. This directory keeps the exact integer multi-lag transform the tracker needs and does not route through it.

## What stays out

The volumes are fetched, never committed, the same rule the Salishan corpus follows. The reference tracker fetches and lists them; nothing here redistributes them.

## Status

This is the fork target and the port is staged, so this directory does not yet reproduce the reference tracker's score on its own. The port lands one stage at a time, and each stage is graded against the reference so the number never regresses. First the settled exact code is relocated here byte for byte and graded device against host and end to end at the reference's 96.7 percent. Then the multi-lag transform is named the core's exact agreement engine, and the overlap, the matching and the basins follow. Where a stage is not yet done it is named here and not described as done.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-17
