# Keys, explained from the ground up

**Purpose:** Explain, from first principles and with this engine's own numbers, the ideas a programmer's defaults push against hardest: that a whole program becomes one small exact object, that applying it is AND and add, that any number of operations can fit in a key of fixed size, that a check costs no pass of its own, and that exact arithmetic has no floor. Each was resisted in this project before it was built, and each held once built. They are explained here thoroughly so the next reader does not have to be argued into them.
**Scope:** `engine/base/keymath/`, `engine/base/key_schedule/`, `engine/base/cycle/`, `engine/base/crc.h`, and every place a key is folded into a pass. The ledger's statuses ([README.md](README.md)) apply to every claim.

## 0. Why these ideas get resisted

Ordinary code is written as instructions: do this, then this, to every input, every time. The cost of a program is its steps times its inputs, and nobody questions that. A key breaks that product. The steps are paid once, on one stand-in, and every input after that costs one application, whatever the program's length. That sounds like something for nothing; it gets doubted, then hedged, then argued down to "an optimization that works for some cases". It is not an optimization. It is what composition *is* once every step is exact.

The second default is floating point. Most code rounds at every step and treats the error as noise to be managed. Under rounding, none of what follows holds, and so it looks like it cannot hold. The engine does not round, and so it does.

## 1. Transitivity, carried all the way

Everything here is one property used without stopping. If a step carries a to b and the next carries b to c, the two together carry a to c:

    a → b,  b → c   ⇒   a → c

Composition does not care how the chain is bracketed:

    T3(T2(T1(x))) = (T3 ∘ T2 ∘ T1)(x)

So the whole chain can be composed first, before any input exists, into one map, and that map applied afterwards. A chain of a thousand steps and a chain of one step then cost an input the same: one application of the composed map.

**The condition, and why it is everything.** a → b and b → c give a → c only where the b one step hands over is *exactly* the b the next step takes in. If a step rounds its output, the next step receives a b′ ≠ b, and the chain is no longer one map: (T3 ∘ T2) ∘ T1 and T3 ∘ (T2 ∘ T1) give different numbers, and composing first is no longer the same as running the steps. For that reason every step in this engine is closed and exact: integers as wide as they grow, nothing rounded, truncated or wrapped at a hand off. Under that condition transitivity holds for chains of any length, and the whole chain collapses to one object.

## 2. The imprint: run the program once, on the impulse

The stand-in that composing needs is the **impulse**: the null holding one unit at one place. For a program of linear, shift invariant steps (smoothings, keeps, scaled subtractions), any input is a sum of shifted, scaled impulses, and so:

    program(input) = key ∗ input,    where  key = program(impulse)

Push the impulse through the program once and keep what comes out. That is the **key**. It is not a summary or an approximation of the program: it *is* the program, as one object.

In the engine (`keymath_imprint`): a binomial smoothing of order n is n unit steps [1 1]; pushed through, the impulse comes out as Pascal's row, by construction. The residual's program (smooth narrow, keep, smooth wide, subtract from 2^g times the kept) imprints to two separable terms:

    key = 2^g · B_narrow − B_wide · B_narrow

**Proved:** applied to all 25 samples, 0 of 10,485,760,000 lanes differ from the residual computed step by step.

## 3. Applying a key is AND and add

A key weight w times a value x is a pattern of masks. Every set bit b of w selects one copy of x shifted left by b, and the copies are added:

    w · x = Σ over set bits b of w of (x << b)

    5 · x = (x << 2) + x         (5 = 101 in binary)

So applying a key is ANDing its bit pattern against the input, to select shifted copies, and adding what was selected. Deriving the pattern is the expensive part: every serial step of the program, spent once, on the impulse. After that, every input costs one pass of masks and adds.

Two keys applied one after the other are one key: the second applied to the first. Two imprinted operations ANDed together are therefore one key again, and a chain of any length costs every later input the same as one step. **That is the compression of time.**

**Order is kept.** Composition regroups freely (it is associative) but does not reorder freely: a keep and a later subtraction from what was kept do not commute. The imprint takes steps in program order, and the scheduler reorders two steps only where they are proved to commute.

## 4. Unbounded operations in a small key

This is the claim that gets refused on sight; here it is exactly, with the engine's numbers.

**What a key's size depends on.** A key's size depends on the program's *reach*: how far one input's influence spreads, and how wide the exact weights grow. It does not depend at all on how many times the program is applied, or on how many inputs pass through it. Apply the key to one voxel or to a trillion: the key is the same bytes.

**The residual's key, measured.** Its weights are 1,130 words, 4,520 bytes, plus a 256 byte term table. The chain it replaces takes 268 unit steps at every voxel (2 + 34 + 34 narrow, 6 + 96 + 96 wide). Per sample that is 268 × 4,194,304 voxels × 100 frames = 112,407,347,200 unit step applications. None of them is ever run. The 4.5 KB key does all of them, and its answer is the step by step answer, lane for lane.

**The CRC key: 2^48 steps in 24 KiB.** A CRC is linear over GF(2). Its advance across 2^k zero bytes is a 64 × 64 bit matrix, and squaring the matrix doubles the distance. The key holds 48 of them: 48 × 64 columns × 8 bytes = 24,576 bytes. With them the register is carried across any run of up to 2^48 bytes (about 281 trillion byte steps) in at most 48 matrix applications. **Proved:** the folded CRC of 44b6_0113de3b equals the CRC taken byte by byte, 363bf8bdffac8f29.

**Periodic operations: infinitely many steps in one period.** Anything that repeats is known entirely from one period. Modulo is a wave. The mirror fold at a frame's edges repeats with period twice the line, and the cycle lays one period down once as a table and reads every tap from it. The two's complement expansion of 1/d, for odd d, is eventually periodic with period the order of 2 modulo d; division by d is one period of limbs, repeated. In each case the operation applied without end is held completely in one period.

**Where it does not hold, stated plainly.** A key cannot be smaller than the program's reach. Smoothing of order n has a row of n + 1 taps, and a longer smoothing has a longer row. The reach bounds the key. It does not bound how many times the key is applied or how many steps it stands for.

| claim | status |
|---|---|
| the residual's 268 step chain is one key of 4,776 bytes, exact on every lane | proved: 0 of 10,485,760,000 lanes differ |
| a CRC over up to 2^48 bytes from a 24 KiB key | proved against the byte by byte CRC |
| one period of a periodic operation holds all of it | built for the mirror fold; theory for division by limb inverse |
| a key's size does not depend on how many inputs pass through it | built: the same key runs every frame of every sample |

## 5. key : transform → product, in one cycle

A check or a filter is a key too, and it does not need a pass of its own. Fold it into the pass that already touches the data. The tower's widen reads every voxel once; the CRC is taken there. The narrow writes every rebuilt voxel once; the rebuilt sample's CRC is taken there. The product comes out of the same pass.

This also keeps transitivity. The transform and the check are one product: the transform holds AND the check holds, or neither does. A check run in a separate pass checks a different moment than the transform happened in.

**The check is the test, compressed in time.** Comparing a sample pixel for pixel is 419,430,400 comparisons. Its CRC is one 64 bit number, and two samples with equal CRCs are equal pixel for pixel, short of a chance of 2^−64. **Measured:** the proof at will re-proves all 25 samples from their files alone in 19 to 33 s, reading no .stack.

## 6. Exact arithmetic has no floor

Floating point has a floor: below some relative size, a difference is lost. Exact integers have none. Every width is proved before a run from the program's own bounds: a lane below 2^m under a row whose weights sum to S stays below 2^(m + bits of S − 1). Nothing then can round, and nothing can wrap.

Two consequences follow, and both are used.

- **Ties are broken deterministically, never by noise.** In the component tree every face's key carries its own name in the lowest limb; no two keys ever tie. The smallest possible difference decides, and it decides the same way on every machine: the Windows and Linux builds give byte identical edges.
- **The medium is subtracted exactly.** The wide term, the medium's own scattering, is subtracted whole; what the residual keeps is only what stands above it. Under rounding the subtraction would leave a residue of rounding, and that residue would read as structure.

## 7. The noise is read, never modeled

The residue left after the bodies are subtracted is the sample's own field noise. It is deterministic, constant for that sample, and unique to it. It is held whole in the .iapx, never bounded, fitted, thresholded or thrown away. Where the engine needs a background to stand a body against, it reads one. The null draws climb the same body toward frames far off in time, where only the field noise can answer. A body is real where it stands above that reading. No distribution is assumed, and no random number is drawn anywhere in the tracker.

**Measured:** across the 25 44b6 samples, the low five bit planes are set in about 46% of frames at nearly every voxel, with no anchor anywhere. That is the floor, read directly from the data, and it is the same test the entropy section of [noise_sieve_tower.md](noise_sieve_tower.md) states.

## 8. Where the chain lives

| step | module | what it holds |
|---|---|---|
| the math | `keymath` | the program's vocabulary, the impulse, the imprint; exact integers as wide as they grow; no device |
| the schedule | `key_schedule` | the key laid out for the machine: sweep order, every lane width proved, scratch, columns, weights |
| the run | `cycle` | the laid out key held on the device and run over a set of atoms in one cooperative launch |
| a key over GF(2) | `crc` | the CRC's byte table and advance operators, generated and held at compile time to the published check value |
| a fold into a pass | `tower` | the CRC taken in the widen and the narrow, costing no pass of its own |
