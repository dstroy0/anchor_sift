# The header carries what nobody put there

A block header has no field for who built it or what shape their day was in. Twenty-eight bits of
the version are a fixed protocol value and BIP320 hands sixteen of the rest to miners as scratch
space, to be swept and discarded. A timestamp is only required to beat a median and sit inside a
two hour window. Neither field is supposed to say anything.

Both do. The scratch space is non-uniform by a factor of three hundred against its own calibrated
null, and the timestamps record the network's clocks disagreeing with each other by as much as five
minutes. Neither pattern was chosen by anyone, and both are legible in public data.

This document states what was measured, what the measurement rules out, and the mechanism left
standing.

## Proving the instrument first

The corpus is a thousand consecutive blocks, heights 965111 to 966110. Before anything was measured
the reader was checked against the chain: each header rebuilt from its recorded fields, hashed
twice, compared to the block id.

    1000 of 1000 reproduced exactly

A statistic taken with an instrument that cannot reproduce a known answer is worth nothing.

Every threshold below is the null's own largest excursion over the same number of cells. Reporting
the loudest of thirty-two cells against a one-cell threshold is the ordinary way to manufacture a
finding, so the null is asked for its loudest too.

## The version window

Sixteen bits of the version field move and sixteen are frozen. The ones that move are exactly bits
13 through 28, exactly the window BIP320 reserves, with nothing moving outside it and nothing frozen
inside. That much is the protocol working as written. The finding is the shape within the window.

A swept counter predicts a share of one half at every bit below its range. Every one of the sixteen
bits falls short of that, and the shortfall widens across the window:

| bit | share | z against a flat counter |
| --- | --- | --- |
| 13 | 0.4190 | -5.12 |
| 15 | 0.4510 | -3.10 |
| 18 | 0.3970 | -6.51 |
| 21 | 0.3020 | -12.52 |
| 24 | 0.2830 | -13.72 |
| 27 | 0.2330 | -16.89 |
| 28 | 0.1750 | -20.55 |

Sixteen consecutive bits, every one negative, running to twenty standard errors. Over the whole
window:

    chi-square against uniform, 15 degrees of freedom:  2882.8
    the same statistic on a uniform draw of the same size:  9.9

A null of that size lands near fifteen and landed at 9.9, so the instrument reads its own floor
correctly and the corpus sits three hundred times above it.

The distribution is bimodal with isolated spikes. Mass piles at both ends of the window at once -
the value zero holds forty-eight blocks, 0xffff holds thirty-four - with further spikes on exact
powers of two. Twenty values out of sixty-five thousand hold better than a quarter of the corpus.

## What the version window is not

A lopsided histogram says nothing about who produced it. The obvious reading is that each value
names the software that emitted the block. That reading was tested twice and failed twice.

**Persistence.** An emitter mines many blocks over a period, so if a version value named one, equal
values would clump along the chain. The count of adjacent height pairs sharing a value was five.
The same count after shuffling the labels over the same blocks, two thousand times, was 7.2 with a
scatter of 2.6. The observed count sits eight tenths of a standard error below chance.

**Transfer.** A label that names a machine should separate fields it was not taken from:

| field | separation | shuffles reaching it |
| --- | --- | --- |
| timestamp mod 64 | +0.89 sd | 169 of 1000 |
| nonce popcount | -0.52 sd | 631 of 1000 |
| nonce high byte | -0.21 sd | 481 of 1000 |

Nothing transfers, and 530 of the 616 distinct signatures appear in exactly one block. The window
does not identify emitters, and a document claiming it did would contradict two of its own tests.

The mechanism left standing explains the shape without appealing to identity. The field is re-rolled
continuously during search, and a winning block records wherever the roll stood when it landed. The
distribution is a picture of where implementations spend their time, not of who is searching. Zero
is where a counter starts, 0xffff is a mask, 0xfff8 is that mask with three bits cleared, and the
powers of two are single-bit states. Those are conventions, arrived at independently, and the piles
sit exactly on them. The pattern is collective, not personal.

## Clock disagreement

The timestamps carry a second, physical effect, and three readings separate it from the effects
around it.

**The mining process is clean.** Block finding at fixed difficulty is a Poisson process, so the gaps
should be exponential. They are, without fitting anything:

    sd / mean    0.9839      an exponential is 1.0000 exactly
    median       429.0 s     predicted 424.1
    mean         611.8 s     target 600.0

| t (s) | observed survival | exponential |
| --- | --- | --- |
| 60 | 0.9184 | 0.9066 |
| 600 | 0.3698 | 0.3751 |
| 2400 | 0.0196 | 0.0198 |

This is the control for everything below. A corpus whose intervals did not follow the exponential
would put every other reading in doubt.

**The clocks tick correctly.** A clock read once per second spreads its low bits evenly, and these
do: the loudest of the eight low bits reaches 3.10 standard errors against a calibrated null of
3.35, which is inside. The timestamps' residues mod ten give a chi-square of 9.9 on nine degrees of
freedom, which is where a fair clock lands.

**The clocks disagree about the time.** Thirty-one of 999 blocks, 3.10 per cent, record a timestamp
earlier than their own parent. That cannot happen if the network's clocks agree. The protocol allows
it, so the count is a direct measurement of the disagreement with no model in between. The deepest
is height 965370, three hundred and four seconds before its parent.

The three readings together locate the effect precisely. The process is clean and the clocks tick
correctly, so what is left is offset: machines that keep good time and hold the wrong time.

The offsets are large. They run from two seconds to 304, and the shape over the whole set is broad:
binned at a minute, nine, three, seven, three, eight and one.

That breadth rules out the first mechanism worth suspecting. NTP holds a machine within
milliseconds, and even a deep stratum accumulates seconds at worst, so a five minute offset is four
orders of magnitude past anything a synchronisation tree produces. These clocks are not badly
synchronised. They are not synchronised.

It also rules out the second. Miners may move a timestamp as search space, which would tie it to the
version window, the other field moved the same way. It does not: the rolled version against the
timestamp mod 600, mod 64, and its low bit gives -0.021, -0.006 and -0.028 against a band of 0.063.

One lead is worth recording without claiming it. Blocks that reverse carry a mean rolled version of
7159 against 14772 for the rest, which a permutation null puts at 2.09 standard errors. On a single
test named in advance that would be worth something. As one of several run here it does not clear a
largest-of-many bar, so it is a question for a longer corpus.

An earlier draft of this document reported a narrow band near 280 seconds among the deepest
reversals. That band was an artifact of printing the eight largest values of a sorted list, which
are close together by construction. The full set above shows no such band. It is recorded here
because the error is instructive: a statistic read off the top of a sort is a statistic about
sorting.

## Integrating longer

A statistic that is real and stationary sharpens as the square root of the count. Noise does not
sharpen at all. That difference is the whole reason to integrate, and it tests a result without
needing a new idea, so the readings above were repeated on seven times the corpus - 6980 blocks,
48.2 days - with the predictions written down first.

| reading | at N=1000 | predicted at N=6980 | observed |
| --- | --- | --- | --- |
| version window chi-square | 2882.8 | 20122 | 17723 |
| bit 13 z | -5.12 | -13.53 | -11.63 |
| bit 18 z | -6.51 | -17.20 | -15.56 |
| bit 24 z | -13.72 | -36.25 | -34.06 |
| bit 28 z | -20.55 | -54.29 | -51.09 |
| reversal rate | 3.10% | 3.1%, a rate does not scale | 2.98% |
| interval sd / mean | 0.9839 | near 1.0, a shape does not scale | 0.9879 |

Every prediction landed, within six to fourteen per cent on the scaling ones and on the nose for the
two that were predicted not to move. The version window effect is real, stationary, and grows the
way a signal grows.

The one lead did not resolve. Reversing blocks carrying a lower rolled version read -2.09 standard
errors at a thousand blocks, which predicts -5.52 at this depth. It read -2.64: larger, but nothing
like square root growth. It is neither confirmed nor dead and wants a deeper corpus, not a verdict.

The reversal population is now readable at 208 reversals rather than 31. Binned by minute it runs
72, 37, 22, 30, 20, 23, 4 across zero to seven minutes - broad and decaying, with no discrete bands.
That shape is the second argument against stratum error, independent of the argument from scale.

## A daily cycle, and what its phase would mean

Within a difficulty epoch the target is fixed, so blocks arrive at a rate proportional to the
hashrate then running. Anything that moves hashrate on a daily cycle therefore moves the count of
blocks in that hour, and electricity is priced on exactly such a cycle.

Grouped by hour of day in UTC, the counts swing 27.5 per cent peak to trough, with a chi-square of
36.62 on 23 degrees of freedom. A multinomial null over the same count and the same bins gives a
mean of 22.95 and a ninety-fifth percentile of 35.10, so 108 of 3000 draws reached the observed
value: p = 0.036. By day of week the swing is 13.8 per cent at p = 0.052. Both are marginal, and
neither is worth a claim on its own.

The phase is the interesting part, and it was noticed after looking rather than predicted, so it is
a hypothesis here and not a result. The counts run high across 08:00 to 11:00 UTC and low across
18:00 to 23:00. Those are 02:00 to 05:00 and 12:00 to 17:00 in United States Central time: the
overnight trough when power is cheapest, and the afternoon peak when it is dearest and when fleets
exposed to grid pricing curtail.

**The phase now has its own test, and it passes.** It needed one: a chi-square is invariant to
relabelling the bins, so the p = 0.036 above fires identically whatever hour the trough lands in and
never spoke to the phase at all. An amplitude with a null and a phase without one is exactly how the
retracted per-pool claim below went wrong, and the two sat one section apart.

`tools/chain/phase_replication.py` splits the corpus and asks whether both halves put the trough in
the same place. The interleaved split, even heights against odd, decides it: both halves span the
same epochs, the same difficulty and the same population, so nothing but noise can separate them.

| split | half one trough | half two trough | apart | chance this close |
|---|---|---|---|---|
| even against odd heights | 22:00 UTC | 22:00 UTC | 0 h | p = 0.047 |
| first half against second | 22:00 UTC | 22:00 UTC | 0 h | p = 0.037 |

Chance puts two troughs that close about one time in twenty-two; the null is drawn multinomially at
each half's own total, because the three-hour smoothing correlates neighbouring bins and the
distance distribution is nothing like uniform on 0 to 12.

Two things worth reading off it. The **trough** is the stable feature and the **peak** is not: the
peak moves from 08:00 to 13:00 between the time halves while the trough does not move at all, so the
trough is what any phase claim should be built on. And this says nothing about migration in either
direction: the corpus spans 48 days and each half 24, while mining geography moves over years. Two
halves three weeks apart agreeing is what a stable phase looks like *and* what an unmeasurably slow
migration looks like. Separating those needs years of corpus, not this one.

That phase carries geography. A miner's cycle follows its own local time, so a population spread
evenly around the globe cancels to nothing in UTC and produces no daily signal at all. A signal
exists only because the distribution is uneven, and the hour at which the trough falls is a
longitude-weighted average of where the hashrate actually sits. The amplitude says how concentrated
it is.

Which makes the cycle a measurement rather than a curiosity: track its phase over years and it
traces the migration of mining around the planet, from public data, with no need to ask anyone where
their machines are.

## The instrument needs a known answer before its silence means anything

Hashrate dips are the same measurement read at a shorter scale, and the same corpus flagged none:
of 95 windows of 144 blocks, with a Poisson floor of 8.3 per cent on a window mean, not one ran
three floors slow or fast. That negative is worth nothing on its own. An instrument that has never
been shown to detect a real event cannot be believed when it reports none, and 48 days of ordinary
operation is not a test.

The chain supplies the test. Global hashrate fell by roughly half across May to July 2021 when
mining was banned in China, and recovered over the following months as fleets moved, principally to
North America. It is dated, documented, enormous, and independent of anything being fitted here. So:

    if hashrate-from-intervals is an instrument, it must show the 2021 collapse and the recovery

with two checks alongside it. The ban forced the largest downward difficulty retargets in the
chain's history, which are dated and public, so the detector has to place those correctly too - and
retargets change intervals by design, so any window straddling one must be excluded or it will read
as an event that is really a rule.

The migration gives the daily cycle its own known answer at the same time. Hashrate moved from
around longitude 105 east to around 100 west, which is close to half the planet, so the phase of
the daily cycle has to shift by most of twelve hours across 2021. A cycle that does not move when
the miners demonstrably moved is not measuring the miners.

## Reproducing it

    python tools/chain/fetch_deep.py --blocks 20000
    python tools/view/build_scope_view.py

The measurements are the field scan, the distribution rake, the two emitter tests, the three jitter
readings, the integration against written predictions, and the daily and weekly cycles.

## Errors made and corrected here

Two are worth recording, because both were caught by a null rather than by judgment.

The first was a band. An earlier draft reported the deepest reversals clustering near 280 seconds,
which was an artifact of printing the eight largest values of a sorted list: the largest values of a
sorted list are close together by construction. The full population shows no band.

The second was a null with no variance in it. The first daily reading shuffled the hour labels and
recounted, which returns identical counts every time, because permuting a list does not change its
multiset. It printed a null of 36.6 with a standard deviation of 0.00, and a null that cannot vary
is not testing anything. The multinomial null above replaced it, and it is what moved the reading
from meaningless to marginal.

## What would settle the open question

Pool identity is recoverable from a block, though not from the fields used here: it sits in the
coinbase transaction's tag, in plaintext, the basis explorers use to attribute blocks.
The corpus in `tools/chain/blocks.json` does not carry it, so emitters had to be inferred above,
and inference is what failed.

With attribution fetched alongside the headers the question becomes supervised. Given the pool that
mined each block, do named pools separate on header fields at all, and does the clock offset
population belong to one of them? That is a stronger experiment than either reported here, and the
negative result above is the reason to run it.

## Where the ideas came from

Almost nothing here is new machinery. The contribution is pointing existing instruments at a
dataset they are not usually pointed at, and the instruments belong to other people.

The detection chain is radar's. Estimating the background under a cell from an order statistic of
its neighbours, so that other targets sitting in the training cells cannot mask the one being
tested, is Rohling's ordered-statistic CFAR [7]. Naming the waveform before opening the data and
projecting onto it is matched filtering, and the reason that projection carries no
multiple-comparison penalty.

The diffusion question and its statistic are Webster and Tavares', who defined the strict avalanche
criterion while looking for design principles for DES-like ciphers [3]. The measurement of SHA-256
against it round by round, including the Bonferroni-relaxed threshold and the finding that Sigma1,
integer addition, Choose and the message scheduler carry diffusion earliest, is Vaughn and
Borowczak's [4][5]; `src/bench/bench_sac.cu` in this tree exists to reproduce their numbers, and the
asymmetry between Sigma1 and Sigma0 reported above is consistent with what they found.

The fields being read were specified by other people too, and reading them correctly means reading
their specifications. The sixteen bits at 13 through 28 are reserved by BIP320 [6]; the Stratum
extension that negotiates and rolls them is BIP310, by Pavel Moravec and Jan Capek [8]; the
signalling scheme those bits were taken out of is BIP9 [9]. The header itself, the double hash, and
the difficulty rule are Nakamoto's [1], and SHA-256 is FIPS 180-4 [2] on the Merkle-Damgard
construction [10].

Two more: the argument that a swept field could be evaluated all at once, and the higher-order
differential that tests it, is standard algebraic cryptanalysis - a Boolean function of degree below
k sums to zero over any k-dimensional affine subspace. And the claim that a kilobyte of program
plus the logarithm of an index is the whole information content of a constant's digits is
Kolmogorov's and Chaitin's; the formula that makes it operational for pi, giving a digit at any
position without the digits before it, is Bailey, Borwein and Plouffe's [11].

The data is Blockstream's and mempool.space's public APIs [12][13], read only.

## References

1. Nakamoto, S. (2008). *Bitcoin: A Peer-to-Peer Electronic Cash System.*
2. National Institute of Standards and Technology (2015). *FIPS PUB 180-4: Secure Hash Standard.*
3. Webster, A. F. and Tavares, S. E. (1986). "On the Design of S-Boxes." *Advances in Cryptology -
   CRYPTO '85*, Springer-Verlag, pp. 523-534.
4. Vaughn, R. and Borowczak, M. (2024). "Strict Avalanche Criterion of SHA-256 and
   Sub-Function-Removed Variants." *Cryptography* 8(3), 40.
5. Vaughn, R. and Borowczak, M. (2026). "Relaxation of Strict Avalanche Criterion on All SHA-256
   Sub-Function Combinations." *Cryptography* 10(3), 32. doi:10.3390/cryptography10030032
6. BIP320, *nVersion bits for general purpose use.* Reserves bits 13 to 28, mask 0x1fffe000.
7. Rohling, H. (1983). "Radar CFAR Thresholding in Clutter and Multiple Target Situations." *IEEE
   Transactions on Aerospace and Electronic Systems* 19, pp. 608-621.
8. Moravec, P. and Capek, J. BIP310, *Stratum protocol extensions*, which specifies version rolling.
9. BIP9, *Version bits with timeout and delay.*
10. Merkle, R. C. and Damgard, I. B. (1989), independently, at CRYPTO '89.
11. Bailey, D. H., Borwein, P. B. and Plouffe, S. (1997). "On the Rapid Computation of Various
    Polylogarithmic Constants." *Mathematics of Computation* 66(218), pp. 903-913.
12. Blockstream Esplora API, `blockstream.info/api`.
13. mempool.space API, `mempool.space/api`.
