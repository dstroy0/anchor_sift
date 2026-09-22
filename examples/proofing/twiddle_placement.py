"""The twiddle table read as a ring placement, where the null is the integer zero.

    python examples/proofing/twiddle_placement.py --check    grade against known answers
    python examples/proofing/twiddle_placement.py --floor    the exact null against the float one

WHAT THIS IS FOR

`twiddle_proof.py` proves a modulus prime and a root's order before a transform runs. That closes
the constant at the moment it is made. It does nothing about the constant at the moment it is USED,
which is where the fault injection of ePrint 2022/824 lands: an electromagnetic pulse during the
butterfly network, on twiddle values already sitting in memory, long after any generator is gone.

Re-deriving the table at that point costs a modular exponentiation per entry. The alternative is an
invariant of the whole table that costs one pass and cannot be satisfied by a corrupted table.

THE PLACEMENT, AND WHY IT HAS AN EXACT NULL

The twiddles are w_j = omega^j for j in [0, n), which is n points equally spaced around a circle.
This tree already reads a ring placement exactly: deflection is the magnitude and is blind to a
rotation by construction, torsion is the phase and recovers the turn with its sign. A placement
turned by whole steps is the same set relabelled, so its null is not small, it is zero.

For the twiddle table the statement is arithmetic and needs no geometry at all:

    sum over j of omega^(j m) = (omega^(n m) - 1) / (omega^m - 1) = 0

whenever n does not divide m, because omega^n = 1 makes the numerator exactly zero while omega^m
is not 1 and so the denominator is invertible. In the field modulo p that quotient is the integer
zero. There is no residual to bound and no tolerance to pick.

THE SAME QUANTITY IN FLOATING POINT IS NOT ZERO, and that difference is the whole advantage.
Evaluated as complex exponentials the sum lands at the format's floor, some 1e-16 times the root of
n. A reader working there has to choose a threshold, and a threshold is a number an attacker tunes
underneath: a fault small enough to hide below it is invisible by construction. Working in the exact
ring there is nothing to hide under, because any nonzero residue at all is a fault. `--floor`
measures both and prints the gap.

WHAT IS CHECKED, AND WHAT EACH CHECK CATCHES

    THE SUM. One pass, O(n) additions, no multiplies. Catches any corruption that moves the total.

    THE GROUP LAW. w_j * w_k = w_((j + k) mod n). This law is the difference between twiddles and an
    arbitrary table, and a single corrupted entry fails every pair that touches it. Sampled, not
    exhausted, because s samples catch a single corruption with probability 1 - (1 - 2/n)^s and
    exhausting is O(n^2) for no gain.

    THE FIRST ENTRY. w_0 = 1. Trivial, and it is what the paper's own attack breaks, since zeroing
    the table takes w_0 down with it.

    THE ORDER. Two exponentiations, from `twiddle_proof`. Catches a root that never had the order,
    the fault this tree inflicted on itself with a composite modulus.

WHAT IT REFUSES

A verdict of clean on a table it has only partly read. Every check below reports which entries it
touched and the probability it would have missed a single corruption, because a sampled check that
reports a bare pass is claiming more than it measured, and that is this tree's recurring failure.
"""

import argparse
import cmath
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import twiddle_proof as tp

# A modulus proved prime by twiddle_proof, with room for the transform lengths used below. Named
# here instead of imported from a table so that the proof and the use sit next to each other.
MODULUS = 2013265921          # 15 * 2^27 + 1, Proth witness 11


def table_of(prime, length):
    """The twiddle table for a transform of `length`, as exact residues, with its root.

    The root's order is proved before the table is built, so any table returned from here has already
    passed the generation time check. Anything found later therefore came from corruption, since
    the constant was already proved good.
    """
    root, why = tp.twiddle_of(prime, length)
    if root is None:
        raise ValueError(why)
    out = [1] * length
    for step in range(1, length):
        out[step] = out[step - 1] * root % prime
    return out, root


def power_sum(table, prime, power=1):
    """Sum of w_j raised to `power`, modulo `prime`. Exactly zero on a clean table."""
    total = 0
    if power == 1:
        for one in table:
            total += one
        return total % prime
    for one in table:
        total += pow(one, power, prime)
    return total % prime


def group_law_failures(table, prime, samples, seed=0x51F7):
    """How many sampled pairs break w_j * w_k = w_((j+k) mod n), and how many were tried.

    The law is the difference between a set of twiddles and a list of numbers. A corrupted entry
    cannot satisfy it except by being replaced with the value it should have had.
    """
    length = len(table)
    state = random.Random(seed)
    bad = 0
    for _ in range(samples):
        left = state.randrange(length)
        right = state.randrange(length)
        if table[left] * table[right] % prime != table[(left + right) % length]:
            bad += 1
    return bad, samples


def miss_chance(length, samples):
    """The chance a single corrupted entry escapes `samples` pairs, stated as a number."""
    if length <= 1:
        return 0.0
    return (1.0 - 2.0 / length) ** samples


def reading(table, prime, samples=256):
    """Everything the exact reading says about one table, as a record.

    The order test reads the root back out of the table, since w_1 IS the root, and asks whether it
    has the full order. That question cannot be answered by any of the other entries here, for the
    reason recorded against `fault_wrong_order`, so it is carried as its own field instead of being
    folded into the group law it superficially resembles.
    """
    length = len(table)
    return {
        "length": length,
        "first": table[0],
        "sum": power_sum(table, prime, 1),
        "square_sum": power_sum(table, prime, 2) if length > 2 else None,
        "law_bad": group_law_failures(table, prime, samples)[0],
        "law_tried": samples,
        "miss": miss_chance(length, samples),
        "order_ok": length > 1 and tp.order_is(table[1], length, prime),
    }


def is_clean(record):
    """Whether a reading shows no corruption. Every condition is an exact equality.

    WHICH CONDITION CATCHES WHAT, because a check that reports a bare pass is claiming more than it
    measured and this list is what it actually measured:

        the sum          any corruption that changes the multiset of values, deterministically
        the squares      the same again at a second power, which a compensating pair would need to
                         satisfy simultaneously
        the group law    a PERMUTATION of the table, which leaves both sums untouched because the
                         multiset is unchanged; this is the only condition that sees a rotation
        w_0              the zeroing the published attack performs
        the order        a root whose order merely DIVIDES the length, which satisfies every other
                         condition here exactly while none of them can see it
    """
    return (record["first"] == 1
            and record["sum"] == 0
            and (record["square_sum"] in (0, None))
            and record["law_bad"] == 0
            and record["order_ok"])


# The fault models. Each takes a clean table and returns a corrupted copy, named for what it does to
# the hardware instead of for what it does to the list.
def fault_zeroed(table, prime):
    """Every twiddle set to zero, the paper's own single fault."""
    return [0] * len(table)


def fault_zeroed_but_first(table, prime):
    """Zeroed except w_0, which defeats the obvious check and is the version worth testing."""
    out = [0] * len(table)
    out[0] = 1
    return out


def fault_one_zero(table, prime):
    """A single twiddle zeroed, deep in the table where a spot check will not look."""
    out = list(table)
    out[len(out) // 3] = 0
    return out


def fault_one_bit(table, prime):
    """A single bit flipped in a single twiddle, the smallest corruption the hardware can make."""
    out = list(table)
    at = len(out) // 3
    out[at] = (out[at] ^ 1) % prime
    return out


def fault_wrong_order(table, prime):
    """The table rebuilt on a root of half the order, so it repeats halfway through.

    This is the fiddled twiddle in its most plausible form: every entry is a real root of unity, the
    values look entirely ordinary, and the table is simply not the one the transform needs.
    """
    length = len(table)
    root, _ = tp.twiddle_of(prime, length // 2)
    out = [1] * length
    for step in range(1, length):
        out[step] = out[step - 1] * root % prime
    return out


def fault_rotated(table, prime):
    """The table rotated by one position, every value genuine and every value in the wrong place."""
    return table[1:] + table[:1]


FAULTS = (
    ("all twiddles zeroed", fault_zeroed),
    ("zeroed except the first", fault_zeroed_but_first),
    ("one twiddle zeroed", fault_one_zero),
    ("one bit flipped", fault_one_bit),
    ("root of half the order", fault_wrong_order),
    ("table rotated by one", fault_rotated),
)


def float_sum(length):
    """The same placement summed as complex exponentials, and that is everyone else can measure."""
    total = complex(0.0, 0.0)
    for step in range(length):
        total += cmath.exp(2j * cmath.pi * step / length)
    return abs(total)


def _check():
    lines = []
    failed = 0
    length = 4096

    lines.append("  THE MODULUS, proved before anything is built on it")
    verdict, witness = tp.proth_prime(MODULUS)
    lines.append("    %d  %s, witness %s" % (MODULUS, verdict, witness))
    if verdict != "prime":
        lines.append("    REFUSING to build a table on an unproved modulus")
        sys.stdout.write("\n".join(lines) + "\n1 check(s) failed\n")
        return 1
    lines.append("")

    table, root = table_of(MODULUS, length)
    clean = reading(table, MODULUS)
    lines.append("  THE CLEAN TABLE, length %s, root %d" % (format(length, ","), root))
    lines.append("    w_0                        %d" % clean["first"])
    lines.append("    sum of w_j                 %d" % clean["sum"])
    lines.append("    sum of w_j squared         %d" % clean["square_sum"])
    lines.append("    group law, %d pairs       %d failed" % (clean["law_tried"], clean["law_bad"]))
    lines.append("    a single corruption would escape with chance %.2e" % clean["miss"])
    if not is_clean(clean):
        lines.append("    THE CLEAN TABLE DOES NOT READ CLEAN")
        failed += 1
    else:
        lines.append("    reads clean, and every one of those is an exact equality")
    lines.append("")

    lines.append("  THE SUM IS ZERO AT EVERY POWER THE LENGTH DOES NOT DIVIDE")
    for power in (1, 2, 3, 5, 17):
        got = power_sum(table, MODULUS, power)
        wanted = 0 if length % power or power < length else None
        ok = got == 0
        lines.append("    power %-3d sum %-12d %s" % (power, got, "zero" if ok else "NOT ZERO"))
        if not ok:
            failed += 1
    lines.append("")

    lines.append("  EVERY FAULT MODEL, against a reading with no threshold in it")
    for name, apply in FAULTS:
        broken = apply(table, MODULUS)
        record = reading(broken, MODULUS)
        caught = not is_clean(record)
        why = []
        if record["first"] != 1:
            why.append("w_0")
        if record["sum"] != 0:
            why.append("sum")
        if record["square_sum"] not in (0, None):
            why.append("squares")
        if record["law_bad"]:
            why.append("law %d/%d" % (record["law_bad"], record["law_tried"]))
        if not record["order_ok"]:
            why.append("order")
        lines.append("    %-26s %-7s %s"
                     % (name, "CAUGHT" if caught else "MISSED", ", ".join(why) if why else ""))
        if not caught:
            failed += 1
    lines.append("")

    lines.append("  A CLEAN TABLE IS NOT REPORTED AS FAULTED, on several lengths")
    for size in (256, 1024, 4096):
        other, _ = table_of(MODULUS, size)
        if not is_clean(reading(other, MODULUS)):
            lines.append("    length %-6d FALSE ALARM" % size)
            failed += 1
        else:
            lines.append("    length %-6d clean" % size)
    lines.append("")

    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def _floor():
    lines = ["  THE NULL, exact against floating point", ""]
    lines.append("    %10s %22s %18s" % ("length", "exact residue", "float64 magnitude"))
    for power in (8, 10, 12, 14, 16):
        length = 1 << power
        table, _ = table_of(MODULUS, length)
        exact = power_sum(table, MODULUS, 1)
        drifted = float_sum(length)
        lines.append("    %10s %22d %18.6e" % (format(length, ","), exact, drifted))

    lines.append("")
    lines.append("  The left column is an integer and it is zero. The right column is a floor, and")
    lines.append("  anything a fault does below that floor cannot be seen from there at all.")
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the twiddle table as a ring placement")
    parser.add_argument("--check", action="store_true", help="grade against known answers")
    parser.add_argument("--floor", action="store_true", help="the exact null against the float one")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.floor:
        sys.exit(_floor())
    parser.print_help()
