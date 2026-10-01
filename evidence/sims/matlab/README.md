# The MATLAB port

**Purpose:** Read the permutation null measure from MATLAB or Octave.
**Scope:** `evidence/sims/matlab/`

```matlab
value = orior_departure(double(uint8(text)));
```

| file | what it is |
|---|---|
| `orior_departure.m` | the permutation null measure, ported |

## What it computes

How far a sequence sits from a shuffle of itself, read through the gaps between repeated symbols, averaged over the rare half of the alphabet. In the Python reference's recorded figures a memoryless source returns about 1.00 and natural language 0.48 to 0.76; no run of this port prints them. Below 1 means the live sequence is more dispersed than its own shuffle, which is clustering.

Runs unchanged on Octave, and needs no toolboxes.

## What it is checked against

The Python at `src/engine/python/measure/dispersion.py` is the reference, because every figure in the ledger came out of it. `evidence/proofs/posits/proof_conservation.py` computes the same rare half. Each language draws its null from its own generator. No port agrees with the reference to the last digit.

One draw against one draw does not settle a port. Each carries its own reseeding floor. The two differ by about 1.4 floors in spread: a correct port lands outside one floor of the reference about half the time, and a shift smaller than a floor cannot be told from none. The mean over reseeds on both sides narrows that by the square root of the seeds, to about 0.4 of a floor at 12.

The Octave port has been run, under Octave 11.3.0. It reads a departure of 0.7226 on the bytes of an English prose corpus and 0.4947 on a C source corpus, against the Python reference's 0.7192 and 0.4949: gaps of 0.0034 and 0.0002 against a reseeding floor of about 0.006. No run of the R port is recorded here. MATLAB proper was not available to run here, and this port shares one text with Octave. Stated here so nobody has to discover it.

## One thing a port has to get right

MATLAB's `std` divides by `n-1` by default and the reference uses a population standard deviation. The second argument switches it, and `std(gaps, 1)` is what appears here. Getting that wrong scales each symbol's spread by `sqrt(m/(m-1))` for its m gaps, and the departure would not show it: the live sequence and its shuffle hold the same count of each symbol and the same number of gaps, and the factor cancels in every ratio. The spreads themselves are what would differ from the reference's.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
