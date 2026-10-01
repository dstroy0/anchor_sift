"""Which of the two linear languages has grip on natural data.

bench_language measured the two module structures SHA-256 alternates between - exclusive-or with
rotation, linear over GF(2)^32, and addition, linear over the integers modulo 2^32 - and found the
translation between them is one-way. An integer-linear map leaks about 3.5 bits to the
exclusive-or view because an addition is an exclusive-or plus a carry. A GF(2)-linear map leaks
0.03 bits the other way, which is nothing. GF(2) is strictly the more expressive of the two.

That raised a claim about intuition and not about SHA-256: nature is full of accumulation, phase
and carry, and almost empty of parity, so human intuition is trained on the weaker language. That
claim was an analogy. This turns it into a number.

Each corpus is read as bytes. For a lag, the exclusive-or difference and the additive difference of
every pair at that lag are histogrammed, and the collision entropy of each says how much grip that
language has: eight bits is flat and anything above zero is structure that language can see.

The corpora carry their own controls, and this set was therefore used in place of a new one:

  english_1813_austen_repeatkey_k8   Austen under an eight-byte repeating key. At lag eight the key
                                     cancels exactly, so the exclusive-or view must see a great deal
                                     and the additive view must see nothing. A positive control for
                                     GF(2) built from real language.
  english_1813_austen_keystream      Austen under a running key. Both views must see nothing.
  monkey_a26_d18_uniform             Synthetic uniform. Both views must see nothing.
  math_sqrt2_digits                  A normal number. Both views must see nothing.

Usage: python tools/language_of_nature.py [corpus directory]
"""

import math
import random
import sys
from pathlib import Path

LAGS = (1, 2, 3, 4, 8, 16)
CAP = 4_000_000

# Ordered so the controls print first and the natural rows are read against them.
WANTED = (
    ("english_1813_austen_repeatkey_k8", "control, GF(2) by construction"),
    ("english_1813_austen_keystream", "control, structureless"),
    ("monkey_a26_d18_uniform", "control, structureless"),
    ("math_sqrt2_digits", "control, structureless"),
    ("english_1813_austen", "language, English prose"),
    ("greek_iliad", "language, Greek"),
    ("finnish_1849_kalevala", "language, Finnish"),
    ("csource_formal", "language, C source"),
    ("voc_whale_humpback", "vocalisation, humpback"),
    ("voc_wolf_howl", "vocalisation, wolf"),
    ("voc_birds_dawn", "vocalisation, dawn chorus"),
    ("voc_human_speech", "vocalisation, human speech"),
    ("infra_blue_atlantic", "infrasound, blue whale"),
    ("art_hokusai", "image, Hokusai"),
    ("art_mondrian", "image, Mondrian"),
    ("math_prime_gaps", "number theory, prime gaps"),
)


def shortfall(seats, lag, additive):
    """Bits by which the difference distribution at this lag falls short of flat over 256."""
    counts = [0] * 256
    limit = min(len(seats) - lag, CAP)
    if limit < 4096:
        return None

    if additive:
        for at in range(limit):
            counts[(seats[at] - seats[at + lag]) & 0xFF] += 1
    else:
        for at in range(limit):
            counts[seats[at] ^ seats[at + lag]] += 1

    # Unbiased collision probability. The naive sum of squared frequencies is biased upward and
    # would report grip that is not there.
    collisions = sum(c * (c - 1) for c in counts)
    possible = limit * (limit - 1)
    if collisions == 0:
        return 0.0
    return 8.0 + math.log2(collisions / possible)


def grip(seats, shuffled, lag, additive):
    """Bits this language sees at this lag beyond what the alphabet alone accounts for.

    The first version of this compared against flat over 256 bins and every control failed. A
    corpus of decimal digits uses ten byte values, so its difference distribution is concentrated
    whatever the arrangement, and the reading was the size of the alphabet and not any
    structure at the lag. Sqrt(2) read 4.09 bits of grip and it has none; the uniform monkey read
    3.05 and it has none by construction.

    The fix is the null the posits already specify: it must delete the property being asked about
    alone. A shuffle of the same bytes destroys every arrangement and preserves the
    alphabet exactly, so the difference between the two readings is arrangement and cannot be
    alphabet. That is also why the shuffle cannot be wrong - it is the data with one property
    removed and not a model that could be false.
    """
    live = shortfall(seats, lag, additive)
    dead = shortfall(shuffled, lag, additive)
    if (live is None) or (dead is None):
        return None
    return live - dead


def built_control(kind, length=2_000_000, period=8):
    """A sequence one language reads exactly and the other cannot.

    The repeating-key corpus was used for this first and it is not a GF(2)-only control. A
    repeating exclusive-or key puts a period into the data that both languages see, because
    k[i mod 8] xor k[(i+1) mod 8] takes only eight values and the additive view sees that period
    just as well. It read add 1.1585 against xor 0.9213 and the reading was uninterpretable.

    These are clean. In the GF(2) case each block is the previous block exclusive-ored with a fixed
    constant, so the exclusive-or difference at the period is exactly that constant, eight bits of
    grip, while the additive difference is spread by the carries. In the integer case each block is
    the previous block plus a constant, and the two roles swap. Each control has to come out
    lopsided in its own direction or this tool is measuring neither language.
    """
    generator = random.Random(20260908)
    block = bytearray(generator.randrange(256) for _ in range(period))
    offset = 0x5A
    out = bytearray()

    while len(out) < length:
        out.extend(block)
        if kind == "xor":
            block = bytearray(value ^ offset for value in block)
        else:
            block = bytearray((value + offset) & 0xFF for value in block)
    return bytes(out[:length])


def main():
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "C:/Users/Douglas/Desktop/git_project/anchor_sift/build/corpora")

    print("=" * 96)
    print("  Which linear language has grip on natural data")
    print("=" * 96)
    print()
    print("  Grip is bits below flat, per language, best over lags %s." % (LAGS,))
    print("  A positive number is structure that language can see. Zero is blindness.")
    print()
    print("  %-34s %-32s %9s %9s %9s" % ("corpus", "what it is", "xor", "add", "which"))
    print("  %-34s %-32s %9s %9s %9s" % ("-" * 34, "-" * 32, "-" * 9, "-" * 9, "-" * 9))

    sources = [("[built] xor-periodic", "control, GF(2) by construction",
                built_control("xor")),
               ("[built] add-periodic", "control, integer by construction",
                built_control("add"))]

    for name, description in WANTED:
        path = root / (name + ".sym")
        if path.exists():
            body = path.read_bytes()
            if len(body) >= 100000:
                sources.append((name, description, body))

    for name, description, seats in sources:

        # One shuffle of the same bytes, reused across lags. It carries the identical alphabet and
        # no arrangement at all, precisely the property being asked about and no other.
        shuffled = bytearray(seats[:CAP + max(LAGS)])
        random.Random(20260908).shuffle(shuffled)

        best_xor = 0.0
        best_add = 0.0
        best_xor_lag = 0
        best_add_lag = 0
        for lag in LAGS:
            by_xor = grip(seats, shuffled, lag, False)
            by_add = grip(seats, shuffled, lag, True)
            if (by_xor is not None) and (by_xor > best_xor):
                best_xor = by_xor
                best_xor_lag = lag
            if (by_add is not None) and (by_add > best_add):
                best_add = by_add
                best_add_lag = lag

        if best_xor > best_add + 0.02:
            verdict = "xor"
        elif best_add > best_xor + 0.02:
            verdict = "add"
        else:
            verdict = "level"

        print("  %-34s %-32s %9.4f %9.4f %9s" %
              (name[:34], description, best_xor, best_add, verdict), " xor@%d add@%d" % (best_xor_lag, best_add_lag))

    print()
    print("  The repeating-key row is the positive control and it must read xor, because at a lag")
    print("  equal to the key length the key cancels under exclusive-or and not under subtraction.")
    print("  The structureless rows must read near zero in both columns. If a natural row reads")
    print("  add and the controls behave, then natural data is legible in the weaker of the two")
    print("  languages and the intuition trained on it is trained on the weaker one.")


main()
