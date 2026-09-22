"""Device arithmetic. No host path, no dispatch, no fallback.

This is the device half of a deliberate split. `digit_engine` is the host half. Neither imports the
other's multiply, and nothing at runtime moves work between them, so "which machine ran this" is
answered by the import line and not by the size of an operand.

    import device_engine        every multiply here is on the card, at every size
    import digit_engine         every multiply there is on the host, at every size

WHY THE SPLIT AND NOT A DISPATCH

A multiply that chooses its own arm by operand size is convenient and it destroys the property that
matters: a tool built on it is half host and half device, the halves move with the input, and no run
can be described without knowing every operand that passed through it. Worse, a tool written against
the dispatch runs ENTIRELY on the host at small widths while reading as a device tool, the fault
happened to the BBP sweep in this tree and cost a night. The crossover sits at 1,024 limbs - 32,768
bits - and the sweep was running at 900.

WHY NEITHER HALF CARRIES ITS OWN RECURRENCES

Both bind `series`, which holds one copy of the Newton reciprocal, the inverse root, the division
and Chudnovsky's splitting, each taking the multiply as an argument. An earlier version of this file
carried its own copies. That is the other way to be wrong: two copies of an iteration are one edit
from disagreeing, nothing reports it when they do, and the first symptom is two engines returning
different answers with no way to tell which is broken.

So the split is in the MULTIPLY, the single thing that actually differs between the two
machines, and nowhere else. Everything above the multiply is shared, and `gate()` checks that the
two agree bit for bit on every operand and every sign. A disagreement is a fault in the device path,
never a reason to fall back.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import gpu_multiply
import series


def product(left, right):
    """The product, on the device, whatever the size.

    `gpu_multiply.device_multiply` is the raw card call and has no threshold in it;
    `gpu_multiply.multiply` is the dispatching one and is deliberately NOT what this calls.

    Sign is handled here because the transform is over a prime field and carries none. Zero is
    short-circuited because a transform of nothing is nothing and the round trip would be waste.
    """
    if left == 0 or right == 0:
        return 0
    negative = (left < 0) != (right < 0)
    out = gpu_multiply.device_multiply(abs(left), abs(right))[0]
    return -out if negative else out


def reciprocal(value, bits):
    """floor(2^bits / value). `series.reciprocal` with the device multiply."""
    return series.reciprocal(product, value, bits)


def divide(top, bottom, places):
    """floor(top * 10^places / bottom). `series.divide` with the device multiply."""
    return series.divide(product, top, bottom, places)


def divide_binary(top, bottom, bits):
    """floor(top * 2^bits / bottom). `series.divide_binary` with the device multiply."""
    return series.divide_binary(product, top, bottom, bits)


def inverse_root(value, bits):
    """floor(2^bits / sqrt(value)). `series.inverse_root` with the device multiply."""
    return series.inverse_root(product, value, bits)


def root_scaled(value, places):
    """floor(sqrt(value) * 10^places). `series.root_scaled` with the device multiply."""
    return series.root_scaled(product, value, places)


def reduce_by(value, modulus, folded=None):
    """`value` modulo `modulus`. `series.reduce_by` with the device multiply."""
    return series.reduce_by(product, value, modulus, folded)


def power_mod(base, power, modulus):
    """`base` to `power` modulo `modulus`. `series.power_mod` with the device multiply."""
    return series.power_mod(product, base, power, modulus)


def split(first, last):
    """Chudnovsky's binary splitting over [first, last). `series.split` with the device multiply."""
    return series.split(product, first, last)


def terms_for(digits):
    return series.terms_for(digits)


def chudnovsky(digits, guard=24):
    """Pi to `digits` places, with every multiply on the card."""
    return series.chudnovsky(product, digits, guard)


def gate():
    """The device must equal the host on every size and every sign, or it is broken.

    The multiply is graded directly against the host's, and then the reciprocal is graded too,
    because the reciprocal is where a multiply that is subtly wrong at one width would first show up
    as a wrong answer and not a wrong product. Both must match EXACTLY: these are integer
    routines returning exact floors, so there is no tolerance to argue about, and a check that
    allowed one would be hiding the only failure mode worth catching.
    """
    import digit_engine as host

    failures = 0
    checked = 0
    for bits in (2048, 20000, 120000):
        one = gpu_multiply._made(bits, 0x71 + bits)
        two = gpu_multiply._made(bits, 0xB3 + bits)
        for left, right in ((one, two), (-one, two), (one, -two), (-one, -two), (0, two), (one, 0)):
            checked += 1
            if product(left, right) != host.product(left, right):
                failures += 1
                print("    MISMATCH on the product at %s bits" % format(bits, ","))
    print("    %d products, %d mismatches" % (checked, failures))

    same = 0
    total = 0
    for bits in (2048, 8192):
        value = gpu_multiply._made(bits // 2, 0x2D + bits)
        total += 1
        if reciprocal(value, bits) == host.reciprocal(value, bits):
            same += 1
        else:
            print("    MISMATCH on the reciprocal at %s bits" % format(bits, ","))
    print("    %d reciprocals, %d matching the host exactly" % (total, same))

    return failures == 0 and same == total


if __name__ == "__main__":
    print("  device engine, no host path")
    print("  grading against the host half, the only thing it may be compared to")
    print()
    ok = gate()
    print()
    print("  %s" % ("device and host agree; the split is sound"
                    if ok else "REFUSING: the device path is wrong and must be fixed, not bypassed"))
    gpu_multiply.shut_down()
    raise SystemExit(0 if ok else 1)
