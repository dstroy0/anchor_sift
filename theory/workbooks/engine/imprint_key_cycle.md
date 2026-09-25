# Imprint, key, cycle

**Purpose:** State why the engine spends a program's serial work once and then only zips it over a set, so a later session reads the imprint, the key and the cycle as one picture and knows which parts a proof already holds.
**Scope:** `engine/base/keymath/`, `engine/base/key_schedule/`, `engine/base/cycle/`, and the residual program `residual_program` (`engine/base/residual/`) states and `engine_residual` in `engine/engine.cu` imprints.

## The atom

Atom is the storage class and what it holds: the whole of the smallest thing under inspection, at whatever scale that thing is. A frame can be an atom, a letter, a part of a cell, a literal atom, a basketball. In the residual today it is one frame. Its lanes are its sixteen bit samples in raster order, lane i at place 2^(16 i). So the frame is one exact integer, the stored stack is that integer's limbs, and nothing is converted to hold it.

## 1. Imprint: transitivity makes a chain one thing

A step carries a value to a value. Steps chain transitively: if T1 carries a to b and T2 carries b to c, then T2∘T1 carries a to c, and composition does not care how the chain is bracketed:

    T3(T2(T1(atom))) = (T3∘T2∘T1)(atom)

So the chain can be composed first, on a stand-in, and applied after. The stand-in is the impulse: the null holding one unit. For a linear, shift-invariant step, whatever the chain does to the impulse is everything it does to any atom:

    T(atom) = T(impulse) * atom

The chain's response to the impulse is its **key**. Imprinting is pushing the impulse through the program once. A binomial smoothing of order n is n unit steps [1 1]. The impulse comes out as Pascal's row, by construction and not from a table. The residual's program is: smooth narrow, keep, smooth wide, then 2^g times the kept value less the running one. It imprints to

    key = 2^g * B_narrow  -  B_wide * B_narrow

That is two separable terms, each one exact row per axis. For the orders asked of it so far the key's weights reach about 2^126, so they are exact integers as wide as they grow.

**What transitivity requires.** a→b and b→c give a→c only when the b that T1 hands over is exactly the b that T2 takes in. Every step has to be closed and exact: its output lands in the same exact set, at the width the next step reads, with nothing rounded, truncated or wrapped at the hand-off. With 64 bit rounding, (a∘b)∘c and a∘(b∘c) differ, and the imprinted key would not be the chain. With exact integers they are the same number. The imprint sizes every lane to its proven bound for this reason: a lane below 2^m under a row summing to S stays below 2^(m + bits(S−1)).

## 2. AND: a key is a pattern of masks

Multiplying by a constant is a series of masks. n·4 is n shifted by 2, and n·5 is (n shifted by 2) plus n. A key weight w applied to a lane x is

    w · x = sum over the set bits b of w of (x shifted by b)

Each set bit of the key selects one shifted copy of the array, and applying the key is ANDing that pattern against the atom and summing what it selects. Deriving the pattern is the expensive part: every serial step, and every costly operation in the program. It happens once, on the impulse. After that each atom costs one application of the key, not one pass per step.

Keys compose into keys: the key of A then B is B's key applied to A's key. Two imprinted operations ANDed together are therefore one key again, and a chain of any length costs every later atom the same as one operation. That is the compression of time. Because a composed key is itself a step, it can be a step in another program. That is the recursion engine two runs on a cfg from the scheduler.

**Order of operations is enforced.** Composition regroups freely (it is associative) but does not reorder freely: it is not commutative once pointwise steps and linear steps are mixed. The scheduler composes keys only in program order, and reorders two steps only where it is proven they commute. Proven means, for example, two centred symmetric rows under the same mirror fold.

The same holds for the atom read as an integer. With lanes L bits wide, the atom is A = Σ v_i 2^(L i) and the key is an integer K placed at the same strides. When L is wide enough that no lane carries into the next, the lanes of A·K are the smoothed values. **The residual of a whole frame is one product of two exact integers.** A separable key factors as K = K_z · K_y · K_x, and by associativity the product is three sparse multiplications, one per axis. Those are the cycle's three sweeps.

Anything periodic is imprinted the same way. Modulo is a wave, so one period is known and the rest is a shift. The mirror fold at the edges repeats with period twice the line: one period per axis is laid down once as a table of offsets, and every tap reads its offset there. A lane's digits z y x repeat with the lane: a thread divides once for its first lane, and after that adds the grid stride's own digits with carries.

## 3. Run it over the set continuously

The key does not depend on the atom, and imprinting fixes every lane width before any atom is seen, so nothing about the set needs a second look. The set streams through:

- One launch covers every lane of every atom in a slab.
- The grid is held at a barrier between the sweeps.
- The last sweep folds every term into each output lane in two's complement.

The key stays resident, the atoms flow past it, and the output of one slab is the input the next stage reads while the cycle moves on.

**Nothing is agglomerated.** Arithmetic is exact, discrimination is unlimited, and the machine does not halt, so there is no error in the traditional sense to average away. No step merges, clusters, averages or rounds a lane toward its neighbours. Every tap's product accumulates into exact columns and the whole sum is kept.

## Where the noise sits

The wide background term is the medium's own scattering, its turbidity. Nephelometry across a dilution series reads that turbidity as the fluid's mean entropic flux, and that whole number is noise to us. The key subtracts it whole, so what the residual keeps is only structure standing above the medium.

## What a proof holds

- **Imprint.** The residual imprints once to two terms. Its lanes need 286 bits and are held in 9 limbs (288).
- **Exact against the old residual.** Over all 25 samples, every lane of every frame was compared with the residual the smoothing passes and the transform computed. 0 of 10,485,760,000 lanes differ, over 2,500 frames. The passes and the transform are gone, and `engine_residual` now runs the same key.
- **Speed.** 31 ms a frame, against 24.5 ms for the passes it replaced. The next saving is the scheduler's: keep the binomial key factored as [1 1]^n, so a sweep is neighbour additions with no multiplies, and compute the shared factor B_narrow once for both terms.
- **Not yet built: pointwise steps.** Square, square root, and division (square's complement) are mask patterns too. A pointwise step imprints on its alphabet: every value a lane can hold, pushed through once. A mask generator for the scheduler will emit those masks, and the scheduler will verify each one exactly before a cycle uses it. The cycle carries only linear steps today.
