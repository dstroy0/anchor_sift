# Reference

**Purpose:** Build the background a departure is measured against, out of the data itself, so no model has to be assumed.
**Scope:** `src/engine/python/reference/`

| module | what it holds |
|---|---|
| `shuffles.py` | `permuted`, `block_shuffled`, `scrambled_within` |
| `ciphers.py` | `substitute`, `repeat_key`, `keystream`, `counter`, `coset`, `seat_span` |
| `unselected.py` | `sqrt_two_digits`, `prime_gaps`, `seated`. Structure nobody produced |

`unselected.py` is the control this work went longest without, and it refuted the strong claim when it arrived. Every corpus departing from the null had been made by a person. The measure detecting arrangement and the measure detecting human production were not separated by anything measured. The gaps between primes return 0.93, outside the band every memoryless arm occupies, and nothing authored the primes.

## Why a background built from the data cannot be wrong

Drawing uniformly from the arrangements of a fixed multiset is the least committal distribution consistent with the observed histogram. That distribution is the data with one property deleted. Every other background is a model and can be false.

The constrained maximum exists and sits at a single point because entropy is strictly concave and a constraint fixing counts or marginals is linear. The background is solved for and never searched for. It therefore carries no seed, no local optimum and no variation between runs.

Where the only constraints are single symbol frequencies the maximizer factorizes, which makes the reference **memoryless by construction and not by assumption**. A memoryless corpus therefore returns 1.00: its distance from the reference is zero. Reading those rows as a baseline that happens to sit near one understates what they are.

## The results that held and the ones that did not

The results in this work that held were measured against a background built by deleting something from the data: a shuffle keeping every count and destroying every position, a corpus truncated to a common length, a generator swept over ten settings, an observed pair count substituted for two assumed marginals.

The results that failed were measured against a background that was assumed. The product rule assumed independence. The Zipf reading assumed a memoryless process would not reproduce it. The frequent half comparison assumed corpus length did not enter. A mean assumed the ratio was not heavy tailed.

## How much each one deletes

The three shuffles are graded, and each grade answers a different question. A full permutation destroys every arrangement at once and cannot say which span the structure lives at. A block shuffle keeps everything shorter than the block and destroys everything longer, and a sweep of the block width locates where a measure's signal sits. Scrambling inside blocks does the reverse: it keeps how the composition drifts across a text and destroys only the order. That separates a dependency reaching across a text from the text changing subject.

The ciphers are graded the same way, and the measured answer is that a cipher cannot remove what this reads unless its key is as long as the message. A substitution reproduces the reading to four decimals. A repeating key of length 8 splits the gaps eight ways, and averaging the eight cosets returns the plaintext value exactly. Only a full length pad erases anything.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
