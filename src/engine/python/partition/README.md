# Partition

**Purpose:** Fix the unit and the scale a reading is taken at, and know which of the three ways you used.
**Scope:** `src/engine/python/partition/`

A reading is undetermined until its partition is fixed, in any dimension and in any state. A partition is fixed in one of three ways and they are not interchangeable.

**Stipulated**, chosen in advance and held. A modeling choice that adds no information and fixes a frame.

**Estimated**, by a sweep of the coarse graining, taking the value where it stops moving. This extracts what the sample already carries and can reach nothing past it.

**Supervised**, supplied as ground truth from outside the sample. Of the three, only this adds information the sample did not contain, so it lives in `oracle` instead of here.

| module | what it holds |
|---|---|
| `curves.py` | `interleaved`, `interleave`, `hilbert_order`, `spread_bits`, for carrying n dimensions through one |
| `coarsen.py` | `coarsen`, `commonest`, for keeping fewer distinctions, and a sweep of how few a result survives |

Both are shared across subjects, so both sit here in the parent. Nothing under `partition` is subject specific yet.

## Why a curve at all

A reader handed a picture row by row cannot see the second dimension, because a pixel and the one below it sit a whole width apart in the file. Being handed a width means choosing a geometry and then measuring the choice, and the picture reader returned heights instead of widths until the assignment was removed.

What the folding costs is measured and comes in two parts. Interleaving jumps whenever it crosses a block boundary, and a jump puts a step into the reading that no part of the set put there. Separately, a line cannot hold everything about a plane whatever path it takes. A Hilbert curve never jumps, so measuring along both separates them: the jumps account for about 0.43 of the shortfall and 0.57 survives a curve with nothing to blame.

The two curves do not have one winner. Hilbert is the better reading of the exponent and the worse reading of the dimension count, because a jump is a block completing and which block completes is which axis just turned over. Removing the jumps removes the dimension count with them.

## What every bound here has cost

Every bound put on a quantity in this work has had to be taken back off, and the reading improved each time. A dimension assigned per domain returned heights instead of widths. A sum stopped at 24 bits was still climbing at 64. A band fixed at eight levels read a picture spread over 160 of them as having no structure. What works is a sweep of the quantity, letting the data say where it stops mattering.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
