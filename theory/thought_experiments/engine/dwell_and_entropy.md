# Dwell and entropy rate

## Dwell

A run in a binary sequence is a maximal block of equal bits, and a bit's dwell is the length of the run it sits in: how many steps it holds its value. Dwell is a property of a sequence. One state does not determine it, and a single instant carries none. The sequence and the pair (first value, sequence of run lengths) determine each other. The histogram of dwells does not determine the sequence, because it forgets the order of the runs.

## The two-state chain

A bit that flips with probability $p$ at each step has geometric runs with mean dwell $1/p$. Its entropy rate is

$$H(p) = -p \log_2 p - (1 - p)\log_2(1 - p).$$

For $p \le 1/2$ each of the two determines the other. Long dwell goes with a low entropy rate and short dwell with a high one. For $p > 1/2$, $H(p) = H(1 - p)$, and one entropy rate matches two mean dwells.

## Renewal processes

Let the runs of 0 have independent lengths with law $D_0$ and the runs of 1 independent lengths with law $D_1$. A pair of runs carries $H(D_0) + H(D_1)$ bits and occupies $\mathbb{E}[D_0] + \mathbb{E}[D_1]$ steps on average. By the renewal reward theorem the entropy rate per step is their ratio:

$$h = \frac{H(D_0) + H(D_1)}{\mathbb{E}[D_0] + \mathbb{E}[D_1]}.$$

With one law $D$ for every run, $h = H(D)/\mathbb{E}[D]$. Geometric runs with parameter $p$ have $H(D) = H(p)/p$ and $\mathbb{E}[D] = 1/p$, and the formula returns the two-state chain's $H(p)$. The entropy of point processes goes back to [McFadden](#src:McFadden-1965), and [Gao, Kontoyiannis and Bienenstock](#src:Gao-Kontoyiannis-Bienenstock-2008) estimate the entropy of binary renewal sequences this way.

The derived direction runs from dwell to entropy. The dwell laws fix the entropy rate, and the entropy rate does not fix the dwell laws.

## No arrow in the rate

Reversing a sequence reverses the order of its runs and keeps their lengths. A stationary process has the same block entropies read in either direction, as in [Cover and Thomas](#src:Cover-Thomas-2006). Neither dwell nor the entropy rate carries a direction of time. A direction needs a process that is not stationary, such as entropy rising from a low start, or a record of an earlier sweep to compare against.

## The dwell bench

On one set of bits:

1. From each bit's runs, build the histograms of runs of 0 and runs of 1, and compute $h$ from the renewal formula.
2. Separately, estimate the entropy rate directly: from block entropies, $H(X_1 \ldots X_k) - H(X_1 \ldots X_{k-1})$ as $k$ grows, or from a Lempel–Ziv compressor, whose rate converges to the entropy rate of a stationary ergodic source, as [Ziv and Lempel](#src:Ziv-Lempel-1978) proved.
3. If the two agree within their error bars, the bits behave as a renewal process and dwell carries their entropy rate. If they differ, the runs are not independent, which is a measurement too.

A bit that never flips has no completed run and gives no dwell law.

## Status

The engine's entropy history counts the flips of each bit of each voxel in each window, as the [engine workbook](#src:Quigg-engine-workbook) records. The run lengths the bench needs are not recorded, and the bench is not built.
