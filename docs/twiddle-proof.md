# The twiddle constants, proved, not copied

A number theoretic transform is a sum of powers of one constant. Its correctness rests entirely on
that constant having the order it is supposed to have, and that order is rarely verified. Below:
what verification costs, what it catches, and why it can be made a proof rather than a test.

Run it with `python examples/proofing/twiddle_proof.py --check`.

## What a twiddle constant is

The transform of a sequence of length `n` over the integers modulo `q` is

    p̂_j = Σ_i p_i · ω^(i·j)

where `ω` is an `n`-th root of unity modulo `q`. The powers of `ω` that the butterflies evaluate are
the **twiddle constants**. In the Cooley–Tukey butterfly they enter as

    c = a + b·w
    d = a − b·w

and in the Gentleman–Sande butterfly as `c = a + b`, `d = (a − b)·w`. A transform of length `2^k` is
`k` stages of `n/2` butterflies, so the twiddles are touched more often than any other value in the
computation and are the only inputs that are supposed to be constant.

## The attack, and why it works

Ravi, Yang, Bhasin, Zhang and Chattopadhyay (*Fiddling the Twiddle Constants: Fault Injection
Analysis of the Number Theoretic Transform*, IACR ePrint 2022/824) inject a single electromagnetic
fault that sets the twiddle constants to zero. The transform does not fail. It returns a value of
the ordinary shape carrying far less entropy than it should, and that is enough to recover a Kyber
key and to forge a Dilithium signature, including a bypass of Dilithium's own verification.

The attack works because **nothing downstream can distinguish a real root of unity from a fiddled
one**. A transform with broken twiddles returns output of the same size, type and range as a correct
one. No error is available to raise. The wrong twiddle is simply used.

## The same fault, with no attacker

We reached that fault condition by carelessness rather than by injection, which is worth recording
because it is the cheaper route to it.

A transform was built under the constants module on three moduli. The third, `1610612737`, was taken
on faith because it has the right shape: `3 · 2^29 + 1`, the form an NTT modulus must have. Its
generator was raised to `(p−1)/L` to produce a root of unity of order `L`, exactly as the
construction requires. A check written next to it reported the root was fine.

The check was trial division to one hundred, on a ten digit number. `1610612737` is **composite**,
and the proof is one line: `2^(1610612736) mod 1610612737 ≠ 1`, so Fermat refuses it. The certificate
is the witness `2`.

Because it is composite, `g^((p−1)/L)` had no particular order, the twiddles were wrong, and the
transform returned numbers of the ordinary shape that were not the convolution of anything. The two
correct moduli in the same set returned zero wrong slots out of thirty-two. The composite one
returned thirty-two out of thirty-two, and the only reason anybody noticed is that the three were
recombined against each other and disagreed.

**A copied constant is a constant nobody checked.** Kyber's modulus, Dilithium's modulus and the
three thirty-two bit moduli that general purpose libraries reach for are the same values everywhere,
carried between codebases as literals. The tables are correct. That is not the point. The point is
that correctness is being inherited instead of established, and inherited correctness cannot tell
you when a value has been fiddled.

## Proth's theorem, which makes the check a proof

> **Proth's theorem.** Let `N = k · 2^n + 1` with `k` odd and `k < 2^n`. Then `N` is prime **if and
> only if** there is an integer `a` with `a^((N−1)/2) ≡ −1 (mod N)`.

Every modulus a transform can use has this shape, because admitting a root of unity of order `2^n`
is the same as `2^n` dividing `N − 1`. So the theorem reaches every candidate that matters.

**Why a witness is a proof.** Suppose `a^((N−1)/2) ≡ −1 (mod N)`, and let `p` be any prime factor of
`N`. Then `a^((N−1)/2) ≡ −1 (mod p)` as well, so the order of `a` modulo `p` divides `N − 1` but does
not divide `(N−1)/2 = k · 2^(n−1)`. Since `N − 1 = k · 2^n`, the order must therefore carry the full
`2^n`, giving `2^n | p − 1` and so `p ≡ 1 (mod 2^n)`. Every prime factor of `N` is at least `2^n + 1`.

If `N` were composite it would have at least two such factors, so `N ≥ (2^n + 1)^2 > 2^(2n)`. But
`k < 2^n` gives `N = k · 2^n + 1 < 2^(2n) + 1`. The two cannot both hold, so `N` is prime. ∎

That last step needs `k < 2^n` and nothing weaker. A modulus outside the range is therefore
reported as out of range instead of being tested anyway.

**Why a witness is easy to find.** If `N` is prime then Euler's criterion makes `a^((N−1)/2)` the
Legendre symbol of `a`, which is `−1` for every quadratic non-residue,
and that is half of all `a`. A witness therefore
is found by trying small integers, and the first one usually works.

**Both verdicts are certificates.** A witness `a` with `a^((N−1)/2) ≡ −1` proves primality. A witness
`a` with `a^(N−1) ≢ 1` proves compositeness, by Fermat. Neither answer is a probability, and neither
is a judgement call. The only other outcome is running out of candidates, which is reported as
inconclusive instead of rounded toward either verdict.

## The order of the root, exactly, without factoring anything

Proving the modulus prime is not enough. The twiddle is `ω = g^((p−1)/L)`, and the step from a
generator to a root of unity is precisely where the constant stops being checked.

> **Claim.** For `L = 2^m`, if `ω^L = 1` and `ω^(L/2) ≠ 1`, then `ω` has order exactly `L`.

**Proof.** The order divides `L = 2^m`, so it is `2^j` for some `j ≤ m`. If `j < m` then `2^j` divides
`2^(m−1) = L/2`, which would give `ω^(L/2) = 1`. It does not. So `j = m`. ∎

Two exponentiations settle it completely, with no factoring of anything. This is cheap enough to run
on every twiddle before every transform, and it is the step the fault attack removes. It refuses a
zeroed twiddle, a root of short order, and a root drawn from a composite modulus, all by the same
test.

The generator itself is proved the same way and just as completely: `g` generates the whole group if
and only if `g^((p−1)/q) ≠ 1` for every prime `q` dividing `p − 1`. Here `p − 1 = k · 2^n` with `k`
small, so factoring it is factoring `k`, and the proof is complete instead of partial.

## What it costs on this desktop

One proof is one modular exponentiation. Measured on unbounded integers with nothing vectorised and
nothing on the GPU:

| bits | decimal digits | one proof |
| ---: | ---: | ---: |
| 64 | 19 | 0.0001 s |
| 128 | 39 | 0.0001 s |
| 256 | 77 | 0.0002 s |
| 512 | 154 | 0.0011 s |
| 1024 | 308 | 0.0185 s |
| 2048 | 617 | 0.0419 s |
| 4096 | 1,233 | 0.2876 s |

A **1,233 digit number proved prime in under three tenths of a second**, deterministically. Not a
probable prime, not a result with a confidence attached: a certificate, with the witness recorded
beside it so the reader can recheck the claim without rerunning anything.

The cost grows as roughly the square of the bit length, since the exponent has `N` bits and each
squaring costs the multiply. This is the same theorem the large prime searches run, where the
records are Proth primes of several million digits; the difference between those runs and this table
is only how long one is willing to wait.

## Why the size is ours to choose

The tabled moduli are small because they are sized to a machine word. A lane holds sixty-four bits, a
product of two residues has to fit in one, and so the modulus stops below `2^32`. That is a property
of the lane. It is not a property of the mathematics.

The arithmetic here is on unbounded integers, so the proof runs at any width, and moduli far past
anything tabled can be produced and proved on demand. Found and proved by this file:

| modulus | shape | transform length |
| --- | --- | ---: |
| 18446744069414584321 | `(2^32 − 1) · 2^32 + 1` | 2^32 |
| 9223372195768565761 | `2147483685 · 2^32 + 1` | 2^32 |
| 39614081257148775820397903873 | `140737488355387 · 2^48 + 1` | 2^48 |

The last one admits a transform of length 281,474,976,710,656. Nobody tables that, because it does
not fit in a lane. **The floor belongs to the format, and the format is a choice**, the same finding
this tree reached measuring a precision null, arriving from the other side.

## The group law, and the proof that it is not enough on its own

The twiddle table is not a list of numbers that happen to be useful. It is a group, and saying so
precisely is what licenses the way the transform is implemented.

> **The law.** Let `ω` have order exactly `n` modulo a prime `p`, and let `w_j = ω^j` for
> `0 ≤ j < n`. Then `{w_j}` is the cyclic group of order `n` generated by `ω`, and in particular
> `w_j · w_k = w_((j+k) mod n)` for every `j` and `k`.

**Proof.** `w_j · w_k = ω^(j+k)`. Write `j + k = qn + r` with `0 ≤ r < n`. Then
`ω^(j+k) = (ω^n)^q · ω^r = 1^q · ω^r = ω^r = w_r`, and `r` is `(j+k) mod n`. The identity is
`w_0 = ω^0 = 1` and the inverse of `w_j` is `w_(n−j)`, so the set is closed, has an identity and has
inverses, which makes it a group; it is generated by one element, so it is cyclic. ∎

Two consequences are used directly:

- **The table sums to zero.** For `n > 1`, `Σ_j w_j = (ω^n − 1)/(ω − 1) = 0/(ω − 1) = 0`, exactly,
  because `ω ≠ 1` makes the denominator invertible. This is an integer zero and not a small residual.
- **The table is generated by repeated multiplication.** `w_(j+1) = w_j · ω`, so building the whole
  table costs one modular multiply per entry. In floating point that construction is warned against
  because error accumulates along the chain. In the exact ring there is no error to accumulate, so
  the cheap construction and the correct one are the same construction.

### The disproof: the law is necessary and is not sufficient

The group law looks like it should certify a twiddle table. It does not, and the counterexample is
not exotic.

> **Claim.** Let `ω'` have order `d` where `d` divides `n` and `d < n`. Then the table
> `w'_j = ω'^j` satisfies the group law at length `n` **exactly**, while being the wrong table.

**Proof.** Since `d` divides `n`, `ω'^n = (ω'^d)^(n/d) = 1`. So the argument above runs unchanged
with `ω'` in place of `ω`, and `w'_j · w'_k = w'_((j+k) mod n)` holds for every `j` and `k`. ∎

A root of half the required order therefore produces a table that is a genuine homomorphic image, of the
wrong group. Measured against the other table level invariants in
`examples/proofing/twiddle_placement.py`, at length 4096 with `ω'` of order 2048:

| invariant | verdict on a root of half the order |
| --- | --- |
| `w_0 = 1` | passes |
| `Σ w_j = 0` | passes |
| `Σ w_j² = 0` | passes |
| group law on sampled pairs | passes, 0 of 256 failures |
| **order test** | **fails, alone among these** |

Every invariant computable from the table at O(n) cost is blind to it, because each one is a
statement the smaller group also satisfies. What separates them is the order, and the order is not a
property any single relation among entries exposes.

### What does separate them, in two exponentiations

> **Claim.** For `L = 2^m`, `ω` has order exactly `L` if and only if `ω^L = 1` and `ω^(L/2) ≠ 1`.

**Proof.** The order divides `L = 2^m`, so it is `2^j` for some `j ≤ m`. If `j < m` then `2^j`
divides `2^(m−1) = L/2`, giving `ω^(L/2) = 1`. It does not, so `j = m`. ∎

No factoring, no search, two exponentiations, and it catches the case every cheaper test misses.

### Why the order of the checks matters operationally

The transform builds its twiddles once by repeated multiplication and reads them at a stride, which
the group law permits. But the group law permits that construction from **any** root
whose order divides the length, including a wrong one, and the result would be a transform that
returns values of the ordinary shape that are not the convolution of anything.

So the order proof is not an optional extra beside the optimisation. It is the precondition for the optimisation being safe, and it has to run first. Stated as a rule: **prove the order, then
generate the table.** Reversing those two produces a fast wrong answer, which is this tree's
recurring failure with a stopwatch attached.

The change was measured. Replacing an exponentiation per butterfly with one table read cut the
transform at length 2^27 from 2006 ms to 680 ms, a factor of 2.95, and the output digest was
identical at every length tested. A correct optimisation moves the clock and leaves the answer
alone, so comparing the digest before and after says which of the two happened here.

## On the card, where a second silent wrong answer was waiting

The transform these constants exist for runs in `src/bench/bench_ntt_cuda.cu`, over the three moduli
below, each carrying its Proth witness in the source beside it:

| modulus | shape | witness | order |
| ---: | --- | ---: | ---: |
| 2013265921 | `15 · 2^27 + 1` | 11 | 2^27 |
| 2281701377 | `17 · 2^27 + 1` | 3 | 2^27 |
| 3892314113 | `29 · 2^27 + 1` | 3 | 2^27 |

The first run of that kernel agreed with the host on the first modulus and differed in **every slot**
on the other two. The property separating them is not primality, which all three have. It is that
`2013265921` is below `2^31` and the other two are above it. In the butterfly

```c
uint32_t sum = upper + lower;      /* both below the modulus */
```

two residues below a modulus above `2^31` sum past `2^32` and wrap, silently, in a type that raises
nothing. The same is true of the borrow in the difference. Only the smallest modulus never reached
the boundary. One arm agreed and two did not, for that reason alone.

**This is the same fault as the composite modulus, one level down.** In both cases an assumption
about the arithmetic went unstated, the transform returned values of the ordinary shape, and nothing
in the output said otherwise. The first was a constant nobody proved; the second was a width nobody
checked. Neither was found by reading the code. Both were found because the gate ran cases that
differed in one property, so the failure named its own cause.

Widened to 64 bits, all three moduli agree with the host, and the device multiply agrees with
Python's own at every size tested.

## What it costs on the card

One full multiply is two forward transforms, a pointwise product and one inverse, per modulus:

| transform length | decimal digits carried | one modulus |
| ---: | ---: | ---: |
| 2^20 | 10.1 million | 8.5 ms |
| 2^22 | 40.4 million | 49.4 ms |
| 2^24 | 162 million | 220 ms |
| 2^26 | 646 million | 938 ms |
| 2^27 | 1.29 billion | 2006 ms |

Three moduli at 2^27 is about six seconds of device time for a product of a billion decimal digits.
The host's own multiply is Karatsuba, measured at 0.930 s for a million digits and 5.610 s for three
million, an exponent of 1.635; extrapolated across three orders of magnitude that is some twenty
hours for the same product. The extrapolation is stated as an extrapolation, since it reaches well
past anything measured directly.

**The packing costs nothing.** A large integer is already a run of
32-bit limbs, so handing one to the device is `value.to_bytes(count * 4, "little")` and reading one
back is `int.from_bytes(raw, "little")`. Those are the same bytes named twice, not a conversion. The
device returns the product as three arrays and the caller assembles

    base + p0 · step + p0 · p1 · rest

where each array is read as one integer at a 32-bit stride. Convolution coefficients run past `2^32`
and have to be carried, and the carrying happens inside that addition, in the host's own big-integer
arithmetic. A carry pass written out over a hundred million coefficients would cost more than every
transform put together; here there is no pass at all.

## What this file refuses

- A modulus outside Proth's range, where `k` is not below `2^n`. The converse turns a witness into
  a proof, and it does not hold there.
- A root whose order falls short of the length asked for, the fiddled twiddle exactly.
- Any verdict without its certificate. Every answer carries the witness that establishes it.

## Source

Prasanna Ravi, Bolin Yang, Shivam Bhasin, Fan Zhang, Anupam Chattopadhyay. *Fiddling the Twiddle
Constants: Fault Injection Analysis of the Number Theoretic Transform.* IACR ePrint 2022/824.
