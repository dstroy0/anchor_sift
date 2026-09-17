# The MATLAB port

**Purpose:** Read the permutation null measure from MATLAB or Octave.
**Scope:** `evidence/sims/matlab/`

```matlab
value = anchor_sift_departure(double(uint8(text)));
```

| file | what it is |
|---|---|
| `anchor_sift_departure.m` | the permutation null measure, ported |

## What it computes

How far a sequence sits from a shuffle of itself, read through the gaps between repeated symbols, averaged over the rare half of the alphabet. A memoryless source returns about 1.00. Natural language returns 0.48 to 0.76. Below 1 means the live sequence is more dispersed than its own shuffle, which is clustering.

Runs unchanged on Octave, and needs no toolboxes.

## What it is checked against

The Python at `src/engine/python/measure/dispersion.py` is the reference, because every figure in the ledger came out of it. A port is correct when it lands inside the reseeding floor of the reference, since each language draws its null from a different generator and none of them can agree to the last digit.

Both ports have now been run and each lands inside the reference floor. The Octave port, under Octave 11.3.0, reads a departure of 0.7226 on the bytes of an English prose corpus and 0.4947 on a C source corpus, against the Python reference's 0.7192 and 0.4949, each gap smaller than the reseeding floor of about 0.006. MATLAB proper was not available to run here, and this port shares one text with Octave. Stated here so nobody has to discover it.

## One thing a port has to get right

MATLAB's `std` divides by `n-1` by default and the reference uses a population standard deviation. The second argument switches it, and `std(gaps, 1)` is what appears here. Getting that wrong shifts every ratio by `sqrt(n/(n-1))`, which is small enough to look like agreement and is still a different number.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
