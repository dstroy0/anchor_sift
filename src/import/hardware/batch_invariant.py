"""Which bits are guaranteed invariant across a batch of consecutive nonces.

Mining hardware is memoryless across candidates: every nonce is computed from scratch, and the only
sharing is the midstate plus the handful of rounds and schedule words the nonce cannot reach.
Nonces are enumerated in sequence. A batch of 2^b consecutive ones agrees in every bit above the
low b, and any gate whose output depends only on those fixed bits is evaluated 2^b times where once
would do.

This computes, exactly, which bit positions can possibly differ within such a batch. It does not
sample. Taint runs forward through the schedule and the compression, over-approximating at every
step: a path may carry no influence, but the absence of a path is exact, and a guaranteed-invariant
bit is the only kind hardware can spend.

    python tools/batch_invariant.py

The Bitcoin nonce is bytes 76 to 79 of the header, which is W[3] of the second block.

WHAT THE ADDER MODEL DECIDES, AND WHAT IT DOES NOT

A first version assumed resolved adders and found the sharing dead at round 3, because a settled
carry chain lets a change at bit zero reach bit thirty-one. That is not how SHA-2 hardware is built:
the inner loop keeps sum and carry apart and never propagates during the rounds, as
shortens the critical path. Under carry-save a 3:2 compressor moves influence up exactly one bit, so
the answer changes - round 3 keeps twenty free bits and the total rises by about a third.

It then dies at round 4 anyway, and the reason is worth stating because it is not the adder.
Sigma1 is ROTR6 xor ROTR11 xor ROTR25, so one tainted bit becomes three at separated positions every
round, and a thirty-two bit word saturates in two or three rounds however the adder is arranged.
The residue spectrum reached the same place independently: Sigma1 reads 12.61 against Sigma0's 3.34
through the matched filter. The operation that carries the mixing is the operation that caps this.
"""

import sys

MASK = 0xFFFFFFFF
NONCE_WORD = 3
ROUNDS = 64


def rotr(value, by):
    return ((value >> by) | (value << (32 - by))) & MASK


# How the adder is built decides how far a change travels, and the two answers are not close.
#
#   resolved   a ripple or fast carry-propagate adder settles the whole word. A change at bit
#              zero can reach bit thirty-one whenever the bits between it happen to carry. Taint
#              smears to the top of the word in one addition.
#   carrysave  the inner loop keeps sum and carry apart and never propagates during the rounds,
#              as SHA-2 hardware actually does to shorten the critical path. A 3:2
#              compressor moves influence up exactly one bit, so taint grows a level at a time.
#
# Silicon uses the second. The first model's answer was wrong for that reason.
ADDER = "carrysave"

# A five-operand add (h, Sigma1, Choose, K, W) compresses 5 to 2 in three levels of 3:2, so taint
# climbs three bit positions per round. Two operands need one level.
LEVELS_FIVE = 3
LEVELS_TWO = 1


def smear_up(taint):
    """Every bit above the lowest tainted one: a resolved carry moves influence upward without end."""
    if taint == 0:
        return 0
    lowest = taint & (-taint)
    return (MASK - lowest + 1) & MASK


def climb(taint, levels):
    """Taint after `levels` of 3:2 compression, each carrying influence up one bit position."""
    out = taint
    for _ in range(levels):
        out |= (out << 1) & MASK
    return out


def add_taint(*parts, **kind):
    levels = kind.get("levels", LEVELS_FIVE)
    together = 0
    for one in parts:
        together |= one
    if ADDER == "resolved":
        return smear_up(together)
    return climb(together, levels)


def small_sigma0(taint):
    return rotr(taint, 7) | rotr(taint, 18) | (taint >> 3)


def small_sigma1(taint):
    return rotr(taint, 17) | rotr(taint, 19) | (taint >> 10)


def big_sigma0(taint):
    return rotr(taint, 2) | rotr(taint, 13) | rotr(taint, 22)


def big_sigma1(taint):
    return rotr(taint, 6) | rotr(taint, 11) | rotr(taint, 25)


def schedule_taint(varying):
    """Taint of every schedule word, given the nonce word varies in `varying`."""
    words = [0] * ROUNDS
    words[NONCE_WORD] = varying
    for slot in range(16, ROUNDS):
        # Four operands: two levels of 3:2 compression.
        words[slot] = add_taint(small_sigma1(words[slot - 2]), words[slot - 7],
                                small_sigma0(words[slot - 15]), words[slot - 16], levels=2)
    return words


def compression_taint(words):
    """Taint of the eight state words after each round.

    Choose and Majority are bitwise. A position is tainted when any of its inputs is. The two
    temporaries are sums, so they widen upward.
    """
    state = [0] * 8
    per_round = []
    for at in range(ROUNDS):
        a, b, c, d, e, f, g, h = state
        # T1 is a five-operand sum, T2 a two-operand one, and a and e each add once more.
        one = add_taint(h, big_sigma1(e), e | f | g, words[at], levels=LEVELS_FIVE)
        two = add_taint(big_sigma0(a), a | b | c, levels=LEVELS_TWO)
        state = [add_taint(one, two, levels=LEVELS_TWO), a, b, c,
                 add_taint(d, one, levels=LEVELS_TWO), e, f, g]
        per_round.append(list(state))
    return per_round


def popcount(value):
    return bin(value).count("1")


def main():
    print("Bits guaranteed invariant across a batch of 2^b consecutive nonces.")
    print("The nonce is W[%d] of the second block; a batch of 2^b agrees above its low b bits.\n"
          % NONCE_WORD)

    print("  %3s %10s %12s %12s %10s %10s"
          % ("b", "batch", "sched bits", "state bits", "total", "of 4096"))
    print("  %3s %10s %12s %12s %10s %10s"
          % ("---", "----------", "------------", "------------", "----------", "----------"))

    for b in (1, 2, 4, 8, 12, 16, 20, 24, 28, 32):
        varying = (1 << b) - 1 if b < 32 else MASK
        words = schedule_taint(varying)
        rounds = compression_taint(words)

        # Schedule: the expanded words only. W[0] to W[15] are the message and the hardware writes
        # them per nonce anyway.
        sched_fixed = sum(32 - popcount(words[t]) for t in range(16, ROUNDS))
        # State: word a and word e are computed each round; b, c, d, f, g, h are copies and cost
        # nothing, so counting all eight would flatter the result.
        state_fixed = sum((32 - popcount(r[0])) + (32 - popcount(r[4])) for r in rounds)

        total = sched_fixed + state_fixed
        # 48 expanded words and 64 rounds of two computed words, all 32 bits wide.
        ceiling = (48 * 32) + (ROUNDS * 2 * 32)
        print("  %3d %10s %12d %12d %10d %9.1f%%"
              % (b, "2^%d" % b, sched_fixed, state_fixed, total, 100.0 * total / ceiling))

    print("\n  A bit counted here cannot differ anywhere in the batch, so the gate that would")
    print("  compute it can be shared across all 2^b lanes. The count falls as b grows because a")
    print("  wider varying field reaches more of the word through the sigma rotations and the")
    print("  carry.")

    # Where the sharing runs out, at one batch size, round by round.
    print("\nWhere it dies, for a batch of 2^8:\n")
    words = schedule_taint((1 << 8) - 1)
    rounds = compression_taint(words)
    print("  %6s %12s %12s" % ("round", "a bits free", "e bits free"))
    print("  %6s %12s %12s" % ("------", "------------", "------------"))
    last = None
    for at in range(ROUNDS):
        free_a = 32 - popcount(rounds[at][0])
        free_e = 32 - popcount(rounds[at][4])
        if (free_a, free_e) != last or at < 8:
            print("  %6d %12d %12d" % (at, free_a, free_e))
        last = (free_a, free_e)
        if free_a == 0 and free_e == 0:
            print("  ... nothing free from here on")
            break
    return 0


if __name__ == "__main__":
    sys.exit(main())
