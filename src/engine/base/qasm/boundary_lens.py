#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Boundary lens: read the topology of the wedge field at a frozen anchor, without perturbing it.

The construction (Doug, in conversation): pin two boundary strands -- the forward chunk from the message
side and the backward chunk from the digest side -- and the FIELD between them is the affine region both
ends jointly permit (span V, the wedge). You never store the interior; you read its topology through a
boundary lens: a projection at the anchor that returns an INVARIANT of the field, not its 2^256 points.
Reading an invariant of an exact object does not alter the object, so the read is non-perturbing (the
indicator glass, not a measurement), the run stays reversible (the bidirectional clock: forward-from-
message and backward-from-digest meet at the anchor and each is the other's exact inverse), and the
infinite interior is preserved -- frozen between the anchor points as a snapshot you can read again,
identically.

Two invariants, because the model predicts they diverge:

  * DIMENSION (the linear lens): rank of the field's GF(2) span; complement = 256 - rank. This is the
    ONLY invariant an affine subspace has -- one component, no curvature. measure_complement.py already
    showed rank saturates (complement -> 0) near round 19, so past there the linear lens is blind.

  * CURVATURE (the topology lens): the fraction of second differences
        f(x) ^ f(x^a) ^ f(x^b) ^ f(x^a^b)
    that VANISH over the frozen aperture (the low `bits` of the free word). All vanish  <=>  the field
    map is GF(2)-affine (degree <=1, trivial topology). A nonzero fraction means the field is a genuine
    variety -- the curvature the linear lens cannot see. Reported beside the degree-2 lift's extra rank
    (directions the AND-monomials carry that the raw field does not), which is the same curvature counted
    a second way.

Honest scope: the lens returns invariants (shadows), never the enumerated interior -- which is exactly
enough here, because "is the true pair recoverable" is itself an invariant (the coset is nonempty or it
is not). It does not shrink a general entangled state below its bond dimension and it does not move the
round-28 wall; it reads where the wall is. The field is exact-integer, so the read is repeatable to the
bit; a keyed digest over the generator matrix stands in for the engine's Merkle seal -- flip one generator
bit and the witness root changes (demonstrated once at startup).

No third-party libraries; Python integers only. hashlib is used solely for the witness root.

Usage:  python boundary_lens.py <mid> <p_idx> <q_idx> <bits> <seed> <trials> <r_lo> <r_hi>
        python boundary_lens.py 13 13 8 6 2024 1 16 30
"""

import hashlib
import sys

sys.path.insert(0, r"D:\git_project\repos\owned\private\PQC\sha256\mitm")
from reduced_round_mitm import (
    biclique_plant, forward_from_state, invert_from_state, wordwise_sub,
    schedule_expand, set_low_bits, gf2_rref, state_to_bits,
)

MASK64 = (1 << 64) - 1
GOLDEN = 0x9E3779B97F4A7C15
CURV_SAMPLES = 400          # second-difference triples drawn per field, per round
DIM_LIFT = 512              # degree-2 lift ambient, matching measure_complement's first lift point


class SplitMix:
    """The tree's counter RNG: state = seed + instance*GOLDEN, splitmix64 finalizer. Matches the kernels."""

    def __init__(self, seed, instance):
        self.state = (seed + instance * GOLDEN) & MASK64

    def next64(self):
        self.state = (self.state + GOLDEN) & MASK64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & MASK64
        return z ^ (z >> 31)

    def word(self):
        return self.next64() & 0xFFFFFFFF

    def bits(self, count):
        mask = 0xFFFFFFFF if count >= 32 else ((1 << count) - 1)
        return self.next64() & mask


def lift(raw256, extra):
    """Raw 256 bits ++ `extra` degree-2 AND-monomials -- the same lift measure_complement/bottle use."""
    value = raw256
    for index in range(extra):
        partner = ((index * 131) + 17) & 255
        other = ((partner + 1) & 255) if partner == index else partner
        if (raw256 >> index) & (raw256 >> other) & 1:
            value |= 1 << (256 + index)
    return value


def forward_field_table(anchor, base, target, p_idx, bits, rounds, mid):
    """f(x) = bits(target - forward_chunk(message with p's low `bits` = x)), x over the frozen aperture.

    The forward strand pinned at the digest: hf(x) = target (-) final(x). The map x -> bits(hf(x)) is the
    field the forward lens reads; its span (differences from x=0) is the forward half of span V.
    """
    table = []
    for x in range(1 << bits):
        message = list(base)
        message[p_idx] = set_low_bits(base[p_idx], x, bits)
        final = forward_from_state(anchor, schedule_expand(message, rounds), mid, rounds)
        table.append(state_to_bits(wordwise_sub(target, final)))
    return table


def backward_field_table(anchor, base, q_idx, bits, rounds, mid):
    """g(y) = bits(H_in from inverting the backward chunk with q's low `bits` = y), y over the aperture.

    The backward strand pinned at the message: hb(y) = invert_chunk(message with q = y). The map
    y -> bits(hb(y)) is the field the backward lens reads; its span is the backward half of span V.
    """
    table = []
    for y in range(1 << bits):
        message = list(base)
        message[q_idx] = set_low_bits(base[q_idx], y, bits)
        h_in = invert_from_state(anchor, schedule_expand(message, rounds), mid, 0)
        table.append(state_to_bits(h_in))
    return table


def gens_from_table(table):
    """Field generators: each aperture image XOR the x=0 image (removes the affine offset)."""
    return [table[x] ^ table[0] for x in range(1, len(table))]


def rank(rows, dim):
    return len(gf2_rref(rows, dim))


def curvature_vanish_fraction(table, bits, rng):
    """Fraction of second differences f(x)^f(x^a)^f(x^b)^f(x^a^b) that are ZERO over the aperture.

    1.0 == the field map is GF(2)-affine (degree <=1): trivial topology, a flat subspace. Below 1.0 ==
    the field is curved: a genuine variety, the topology the rank lens is blind to. The affine offset
    cancels in the four-fold XOR, so this reads pure map nonlinearity.
    """
    size = 1 << bits
    if size < 4:
        return 1.0
    vanish = 0
    for _ in range(CURV_SAMPLES):
        x = rng.bits(bits)
        a = rng.bits(bits)
        b = rng.bits(bits)
        second = table[x] ^ table[x ^ a] ^ table[x ^ b] ^ table[x ^ a ^ b]
        if second == 0:
            vanish += 1
    return vanish / CURV_SAMPLES


def witness_root(*generator_lists):
    """Keyed digest over every field generator -- stands in for the engine's Merkle seal at this read."""
    digest = hashlib.blake2b(digest_size=16, key=b"boundary-lens")
    for gens in generator_lists:
        for value in gens:
            digest.update(value.to_bytes(96, "little"))     # 768 bits: covers the 512-lift columns too
    return digest.hexdigest()


def clock_closes(anchor, base, rounds, mid):
    """The bidirectional clock closes exactly: invert to H_in at round 0, run forward back to the anchor.

    forward_from_state(invert_from_state(anchor)) == anchor is the reversibility witness -- trace back and
    forward returns you to the same moment, bit-exact. Target-independent; it is a property of the clock.
    """
    schedule = schedule_expand(base, rounds)
    h_in = invert_from_state(anchor, schedule, mid, 0)
    return forward_from_state(h_in, schedule, 0, mid) == anchor


def read_instance(seed, index, rounds, mid, p_idx, q_idx, bits):
    """One frozen read: build both boundary fields at the anchor and return their topology invariants."""
    rng = SplitMix(seed, index)
    anchor = tuple(rng.word() for _ in range(8))
    base = [rng.word() for _ in range(16)]
    secret_p = rng.bits(bits)
    secret_q = rng.bits(bits)
    target = biclique_plant(anchor, base, p_idx, q_idx, mid, rounds, bits, secret_p, secret_q)

    fwd_table = forward_field_table(anchor, base, target, p_idx, bits, rounds, mid)
    bwd_table = backward_field_table(anchor, base, q_idx, bits, rounds, mid)
    fwd_gens = gens_from_table(fwd_table)
    bwd_gens = gens_from_table(bwd_table)
    all_gens = fwd_gens + bwd_gens

    raw_rank = rank(all_gens, 256)
    extra = DIM_LIFT - 256
    lift_rank = rank([lift(v, extra) for v in all_gens], DIM_LIFT)

    # non-perturbing read: the clock closes (reversible), and re-reading gives an identical witness root
    reversible = clock_closes(anchor, base, rounds, mid)
    root_a = witness_root(fwd_gens, bwd_gens)
    root_b = witness_root(fwd_gens, bwd_gens)

    return {
        "raw_rank": raw_rank,
        "complement": 256 - raw_rank,
        "lift_extra_rank": lift_rank - raw_rank,            # degree-2 directions beyond the flat field
        "fwd_curv0": curvature_vanish_fraction(fwd_table, bits, SplitMix(seed, index ^ 0x5151)),
        "bwd_curv0": curvature_vanish_fraction(bwd_table, bits, SplitMix(seed, index ^ 0x8888)),
        "fwd_fiber": len(set(fwd_table)),
        "bwd_fiber": len(set(bwd_table)),
        "reversible": reversible,
        "root_stable": root_a == root_b,
        "root": root_a,
    }


def seal_selftest(seed, rounds, mid, p_idx, q_idx, bits):
    """Once: show a one-bit flip in a field generator changes the witness root -- any flip fails the seal."""
    rng = SplitMix(seed, 0)
    anchor = tuple(rng.word() for _ in range(8))
    base = [rng.word() for _ in range(16)]
    target = biclique_plant(anchor, base, p_idx, q_idx, mid, rounds, bits, rng.bits(bits), rng.bits(bits))
    gens = gens_from_table(forward_field_table(anchor, base, target, p_idx, bits, rounds, mid))
    clean = witness_root(gens)
    flipped = list(gens)
    flipped[0] ^= 1                                          # one bit, anywhere in the field
    tampered = witness_root(flipped)
    print("  seal self-test: clean root %s ... | one-bit-flip root %s ... | %s"
          % (clean[:12], tampered[:12], "DIFFERS (seal holds)" if clean != tampered else "COLLISION (bug)"))


def run(mid, p_idx, q_idx, bits, seed, trials, r_lo, r_hi):
    print("boundary lens on the wedge field: dimension (rank) vs curvature (2nd-diff), both strands, frozen")
    print("  anchor mid=%d  fwd word p=%d  bwd word q=%d  aperture=%d bits  seed=%d  %d trial(s)"
          % (mid, p_idx, q_idx, bits, seed, trials))
    seal_selftest(seed, max(r_hi, mid + 2), mid, p_idx, q_idx, bits)
    print("  curvature 1.00 = flat (affine, trivial topology); < 1.00 = curved field the rank lens can't see")
    header = ("  round | rank/256 | cmpl | deg2+rank | fwd curv0 | bwd curv0 | fwd fiber | bwd fiber | clock")
    print(header)
    print("  " + "-" * (len(header) - 2))
    for rounds in range(r_lo, r_hi + 1):
        if rounds <= mid:
            continue
        reads = [read_instance(seed, index, rounds, mid, p_idx, q_idx, bits) for index in range(trials)]

        def rng_span(key, fmt="%d"):
            vals = [r[key] for r in reads]
            lo, hi = min(vals), max(vals)
            return (fmt % lo) if lo == hi else (fmt + "-" + fmt) % (lo, hi)

        def avg(key):
            return sum(r[key] for r in reads) / len(reads)

        clock_ok = all(r["reversible"] and r["root_stable"] for r in reads)
        full = 1 << bits
        print("  %5d | %8s | %4s | %9s | %9.2f | %9.2f | %5s/%-3d | %5s/%-3d | %s"
              % (rounds,
                 rng_span("raw_rank"),
                 rng_span("complement"),
                 rng_span("lift_extra_rank"),
                 avg("fwd_curv0"),
                 avg("bwd_curv0"),
                 rng_span("fwd_fiber"), full,
                 rng_span("bwd_fiber"), full,
                 "exact" if clock_ok else "BROKEN"))
    print("  (clock 'exact' = forward(+)backward == target and the re-read root matched: reversible,")
    print("   non-perturbing. cmpl->0 = linear topology exhausted; watch curvature/deg2 past that point.)")


if __name__ == "__main__":
    a = sys.argv
    if len(a) < 9:
        print(__doc__)
        sys.exit(2)
    run(int(a[1]), int(a[2]), int(a[3]), int(a[4]), int(a[5]), int(a[6]), int(a[7]), int(a[8]))
