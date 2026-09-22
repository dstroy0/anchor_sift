"""How far a change travels through a real compressor tree, simulated instead of assumed.

The batch-invariance figures depend on one number: how many bit positions a change climbs when a
round's operands are reduced. An earlier run assumed textbook depths - three levels of 3:2 for the
five-operand T1, two for the four-operand schedule - and textbook is not a netlist.

Three things are varied here, because each of them moves the answer:

  topology     3:2 is a full adder and climbs one bit per level. 4:2 is built from two of them but
               its internal carry is absorbed and never rippled, so it reduces four operands to
               two for one bit of climb. 7:3 spreads its three outputs over bits i, i+1 and i+2.
  state        whether a and e are resolved every round or carried redundantly. This is the
               that decides the answer, and it is not free to choose: Sigma is a xor of rotations,
               rotation does not distribute over addition, so ROTR(s+c) is not ROTR(s)+ROTR(c).
               A design that keeps the state redundant cannot compute Sigma on it.
  operands     five for T1, two for T2 and for the two final sums, four in the schedule.

Taint is simulated bit by bit through each compressor and never modeled by a climb rate, so the
climb is measured out of the simulation and printed beside the assumption it replaces.

    python tools/compressor_test.py
"""

import sys

MASK = 0xFFFFFFFF
ROUNDS = 64
NONCE_WORD = 3


def rotr(value, by):
    return ((value >> by) | (value << (32 - by))) & MASK


# Cell shapes: how many operands a cell eats, and where its outputs land relative to the input bit.
# A 4:2 absorbs its internal carry, so both outputs stay within one position of the input despite
# being two full adders deep. A 7:3 spreads three outputs over three positions.
CELLS = {
    "3:2": (3, (0, 1)),
    "4:2": (4, (0, 1)),
    "7:3": (7, (0, 1, 2)),
}


def reduce_32(operands, topology):
    """Reduce operand taints to two through a Wallace tree. Returns (taints, levels).

    Reduction is level-parallel, as the hardware is: at each level every operand that
    can be grouped into a cell is, all cells fire at once, and their outputs form the next level.

    An earlier version used a queue - take from the front, push to the back - and reported that the
    topology made no difference. That was the queue and not the tree: a tainted operand's outputs
    were re-queued behind untainted ones and met fewer cells than they should, so the climb came out
    short and equal for every cell shape.
    """
    eats, lands = CELLS[topology]
    working = [t & MASK for t in operands]
    levels = 0

    while len(working) > 2:
        levels += 1
        nxt = []
        at = 0
        # Every full group of `eats` operands goes through a cell at this level, in parallel.
        while len(working) - at >= eats:
            here = 0
            for one in working[at:at + eats]:
                here |= one
            for shift in lands:
                nxt.append((here << shift) & MASK)
            at += eats
        # Whatever will not fill a cell is carried to the next level untouched.
        leftover = working[at:]
        # A group too small for this cell but big enough for a full adder still reduces.
        if (len(nxt) + len(leftover) > 2) and (len(leftover) >= 3):
            here = leftover[0] | leftover[1] | leftover[2]
            nxt.extend([here, (here << 1) & MASK])
            leftover = leftover[3:]
        working = nxt + leftover
        if not nxt:
            # Nothing could reduce: fall back to a full adder so the loop cannot spin.
            padded = working + [0, 0]
            here = padded[0] | padded[1] | padded[2]
            working = [here, (here << 1) & MASK] + working[3:]

    while len(working) < 2:
        working.append(0)
    return working, levels


def resolve(taint):
    """A carry-propagate adder settles the word. A tainted bit taints everything above it."""
    if taint == 0:
        return 0
    lowest = taint & (-taint)
    return (MASK - lowest + 1) & MASK


def add(operands, topology, settle):
    parts, _ = reduce_32(operands, topology)
    together = parts[0] | parts[1]
    return resolve(together) if settle else together


def small_sigma0(t):
    return rotr(t, 7) | rotr(t, 18) | (t >> 3)


def small_sigma1(t):
    return rotr(t, 17) | rotr(t, 19) | (t >> 10)


def big_sigma0(t):
    return rotr(t, 2) | rotr(t, 13) | rotr(t, 22)


def big_sigma1(t):
    return rotr(t, 6) | rotr(t, 11) | rotr(t, 25)


def run(varying, topology, settle):
    words = [0] * ROUNDS
    words[NONCE_WORD] = varying
    for slot in range(16, ROUNDS):
        words[slot] = add([small_sigma1(words[slot - 2]), words[slot - 7],
                           small_sigma0(words[slot - 15]), words[slot - 16]], topology, settle)

    state = [0] * 8
    per_round = []
    for at in range(ROUNDS):
        a, b, c, d, e, f, g, h = state
        one = add([h, big_sigma1(e), e | f | g, words[at], 0], topology, settle)
        two = add([big_sigma0(a), a | b | c], topology, settle)
        state = [add([one, two], topology, settle), a, b, c,
                 add([d, one], topology, settle), e, f, g]
        per_round.append(list(state))
    return words, per_round


def popcount(v):
    return bin(v).count("1")


def measure_climb(topology):
    """One tainted bit in, how many positions does it occupy after reducing five operands."""
    parts, levels = reduce_32([1, 0, 0, 0, 0], topology)
    reached = parts[0] | parts[1]
    return popcount(reached) - 1, levels


def main():
    print("Climb measured out of the simulation, for a five-operand reduction.\n")
    print("  %-8s %10s %10s" % ("topology", "levels", "bits up"))
    print("  %-8s %10s %10s" % ("-" * 8, "-" * 10, "-" * 10))
    for topology in ("3:2", "4:2", "7:3"):
        up, levels = measure_climb(topology)
        print("  %-8s %10d %10d" % (topology, levels, up))

    print("\nInvariant bits across a batch, by topology and by what the state carries.")
    print("Sigma needs a resolved value, so 'redundant' is an upper bound no design can reach.\n")

    print("  %-10s %-10s %12s %12s %10s"
          % ("state", "topology", "sched bits", "state bits", "of 4096"))
    print("  %-10s %-10s %12s %12s %10s"
          % ("-" * 10, "-" * 10, "-" * 12, "-" * 12, "-" * 10))

    varying = (1 << 8) - 1
    for settle, label in ((True, "resolved"), (False, "redundant")):
        for topology in ("3:2", "4:2", "7:3"):
            words, rounds = run(varying, topology, settle)
            sched = sum(32 - popcount(words[t]) for t in range(16, ROUNDS))
            comp = sum((32 - popcount(r[0])) + (32 - popcount(r[4])) for r in rounds)
            ceiling = (48 * 32) + (ROUNDS * 2 * 32)
            print("  %-10s %-10s %12d %12d %9.1f%%"
                  % (label, topology, sched, comp, 100.0 * (sched + comp) / ceiling))

    print("\n  A resolved state settles a and e every round, so the topology stops mattering to")
    print("  this total even though it changes the climb. Redundant state keeps the climb small")
    print("  and cannot be built as written: Sigma is a xor of rotations, rotation does not")
    print("  distribute over addition, so a and e must be settled before Sigma reads them.")

    # -- which bits vary, not only how many ------------------------------------------------------
    #
    # Everything above assumes a batch of *consecutive* nonces, so the varying field is the low
    # bits. Nothing forces that. A miner chooses its own enumeration order, and the varying field
    # is whatever that order makes it. Sweeping a single varying bit across all 32 positions asks
    # whether the order is worth choosing.
    print("\nOne varying nonce bit, swept across the word. Sequential enumeration only ever")
    print("exercises the first row of this table.\n")
    print("  %6s %12s %12s %10s" % ("bit", "sched bits", "state bits", "of 4096"))
    print("  %6s %12s %12s %10s" % ("-" * 6, "-" * 12, "-" * 12, "-" * 10))

    ceiling = (48 * 32) + (ROUNDS * 2 * 32)
    best = (-1, -1)
    for bit in range(32):
        words, rounds = run(1 << bit, "4:2", True)
        sched = sum(32 - popcount(words[t]) for t in range(16, ROUNDS))
        comp = sum((32 - popcount(r[0])) + (32 - popcount(r[4])) for r in rounds)
        total = sched + comp
        if total > best[1]:
            best = (bit, total)
        if bit < 4 or bit > 27 or total == best[1]:
            print("  %6d %12d %12d %9.1f%%" % (bit, sched, comp, 100.0 * total / ceiling))
    print("  ...")
    print("\n  best single varying bit: %d at %.1f%%" % (best[0], 100.0 * best[1] / ceiling))

    # -- enumeration order, which is a free choice ------------------------------------------------
    #
    # Counting upward varies the low bits. Nothing requires that. Counting so the *high* bits vary
    # puts the change where a carry cannot leave it, and the difference is not small.
    print("\nA batch of 2^b nonces, varying the low b bits against the high b bits.")
    print("Counting upward gives the low column. The high column is a different order, same cost.\n")
    print("  %4s %14s %14s %10s" % ("b", "low b vary", "high b vary", "ratio"))
    print("  %4s %14s %14s %10s" % ("-" * 4, "-" * 14, "-" * 14, "-" * 10))

    for b in (1, 2, 4, 8, 12, 16):
        low = (1 << b) - 1
        high = (MASK << (32 - b)) & MASK
        out = []
        for varying in (low, high):
            words, rounds = run(varying, "4:2", True)
            sched = sum(32 - popcount(words[t]) for t in range(16, ROUNDS))
            comp = sum((32 - popcount(r[0])) + (32 - popcount(r[4])) for r in rounds)
            out.append(sched + comp)
        print("  %4d %13.1f%% %13.1f%% %9.2fx"
              % (b, 100.0 * out[0] / ceiling, 100.0 * out[1] / ceiling,
                 (float(out[1]) / out[0]) if out[0] else 0.0))

    # -- the field, drawn ------------------------------------------------------------------------
    #
    # A sum over the field cannot show where the free bits are, and where is the question for
    # a floorplan. Each row is a round, each column a bit position of the a word.
    print("\nFree bits of the a word, by round. '.' is free, '#' can differ.")
    print("Low bit at the left. Batch of adjacent pairs, 4:2, resolved.\n")
    words, rounds = run(1, "4:2", True)
    print("        %s" % "".join(str(i % 10) for i in range(32)))
    for at in range(12):
        taint = rounds[at][0]
        row = "".join("#" if (taint >> i) & 1 else "." for i in range(32))
        print("  r%-4d  %s  %d free" % (at, row, 32 - popcount(taint)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
