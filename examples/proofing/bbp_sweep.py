"""Point the validated relation search at real constants, across a grid of parameters.

The pipeline is gated in both directions: it recovers a planted relation exactly, it rejects a false
one found among unrelated numbers, and it rediscovers the 1996 BBP formula for pi. So it can be
pointed somewhere and its answers read.

WHERE NOT TO POINT IT

Borwein, Galway and Borwein proved in 2004 that pi has no degree-one BBP formula in a power-of-two
base beyond the three already known. That region is closed and searching it only rediscovers what is
there. So the grid covers powers two and three, which are far less swept, and constants besides pi.

WHAT A HIT WOULD AND WOULD NOT BE

A believable relation here is a CANDIDATE formula, not a discovery. Most of the space is either
empty or already in Bailey's compendium, and anything that survives the screen has to be checked
against it before it is called new. What the screen guarantees is only that the relation is not an
artifact of finite precision, the part that is easy to get wrong and hard to notice.

    python examples/proofing/bbp_sweep.py
    python examples/proofing/bbp_sweep.py --places 1600
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bbp_search
import relation_search


POWERS = (2, 3)
BASES = (2, 4, 8, 16, 3, 9)
STRIDES = (2, 3, 4, 6, 8)


def log_two(places):
    """log 2 = sum over k of 1/(k 2^k), scaled by 2^places. Exact integer terms."""
    scale = 1 << places
    total = 0
    power = 2
    k = 1
    while power <= scale * k:
        total += scale // (k * power)
        power <<= 1
        k += 1
    return total


def apery(places):
    """zeta(3) by Apery's series: (5/2) sum (-1)^(n-1) / (n^3 C(2n,n)).

    The central binomial grows like four to the n, so the series converges geometrically and every
    term is an exact integer division of a scaled one.
    """
    scale = 1 << places
    total = 0
    binomial = 1
    n = 1
    while True:
        # C(2n,n) built up across terms, never recomputed.
        binomial = binomial * (2 * n) * (2 * n - 1) // (n * n) if n > 1 else 2
        denominator = (n ** 3) * binomial
        if denominator > scale:
            break
        term = scale // denominator
        total = total + term if (n % 2 == 1) else total - term
        n += 1
    return (5 * total) // 2


def main():
    parser = argparse.ArgumentParser(description="Sweep the relation search over real constants.")
    parser.add_argument("--places", type=int, default=1100)
    parser.add_argument("--host", action="store_true",
                        help="run on the host instead of the card")
    given = parser.parse_args()
    places = given.places

    # THE ENGINE IS AN IMPORT, NOT A SWITCH. What stood here called `device_only.engage()`, which
    # reached into another module and rebound its multiply for the whole process - a monkeypatch,
    # and one that lied twice over. It routed through the DISPATCHING multiply, which hands operands
    # below 1,024 limbs back to the host; 1,024 limbs is 32,768 bits, leaving a sweep at the default
    # 1,100 places printed "routing every multiply to the device" and then ran entirely on the CPU.
    #
    # Now the module is named once, here, and handed down as a plain function. There is nothing to
    # engage and nothing that can be rebound from elsewhere.
    #
    # A word on what the card is worth at a given width, since the honest answer is not "always".
    # `device_engine.product` goes to the card at EVERY size, including sizes where the host would
    # win, because a tool that silently changes machines is the thing being fixed. Below about a
    # thousand limbs a device multiply is mostly pipe, leaving a small sweep run this way slower than
    # the same sweep on --host, and that is a real cost and not a rounding error.
    #
    # It is also the regime this search is least interesting in. A relation whose coefficients run
    # to D digits cannot be seen below about D*n digits of input, so the precision where a formula
    # becomes visible and the precision where the card becomes the right machine are the same
    # region. Run it deep, where both facts point the same way.
    if given.host:
        import digit_engine as engine
        print("  every multiply on the host, at every size")
    else:
        import device_engine as engine
        print("  every multiply on the card, at every size")
    product = engine.product

    print()
    print("  computing the constants to 2^%d..." % places)
    PI = bbp_search.pi_scaled(product, places)
    constants = {
        "pi": PI,
        "pi^2": (PI * PI) >> places,
        "log2": log_two(places),
        "zeta(3)": apery(places),
    }
    for name, value in constants.items():
        whole = value >> places
        frac = ((value - (whole << places)) * 10 ** 12) >> places
        print("    %-9s %d.%012d" % (name, whole, frac))

    # THE CONTROL FIRST. Pi at base sixteen, power one, stride eight is where the 1996 formula
    # lives. A sweep that cannot find a formula it is standing on cannot be believed when it
    # reports empty cells, and reporting 240 empty cells without having run this is the exact
    # fault this work spent a session learning to avoid.
    print()
    print("  CONTROL: the sweep must find pi's known formula in its own machinery")
    control = bbp_search.search(product, constants["pi"], 16, 1, 8, places, verbose=False)
    if control is None:
        print("    no relation at all. The sweep is broken and its empty cells mean nothing.")
        return 1
    coefficients, residual, size = control
    margin = places - (abs(residual).bit_length() if residual else 0)
    span = size.bit_length() * 9 + 32
    if margin > span:
        print("    found, residual 2^-%d against a span of %d bits. The sweep works." % (margin, span))
    else:
        print("    found a relation but the screen rejects it, so the screen is mis-set here.")
        return 1

    # Powers two and three, which are far less swept than the degree-one region that is closed.
    grid = []
    for power in POWERS:
        for base in BASES:
            for stride in STRIDES:
                grid.append((base, power, stride))

    print()
    print("  %d parameter cells per constant, %d constants" % (len(grid), len(constants)))
    print("  a cell is reported only if its residual sits far enough below the precision that")
    print("  coefficients that size could not have cancelled there by accident")
    print()
    print("    constant   base  power  stride   largest coeff   residual bits   verdict")

    survivors = []
    for name, alpha in constants.items():
        for base, power, stride in grid:
            found = bbp_search.search(product, alpha, base, power, stride, places, verbose=False)
            if found is None:
                continue
            coefficients, residual, size = found
            if size == 0:
                continue
            bits = abs(residual).bit_length() if residual else 0
            margin = places - bits
            span = size.bit_length() * (stride + 1) + 32
            believable = margin > span
            if believable:
                survivors.append((name, base, power, stride, coefficients, residual, size))
                print("    %-10s %4d  %5d  %6d   %13s   %13d   CANDIDATE"
                      % (name, base, power, stride, format(size, ","), margin))

    print()
    print("=" * 78)
    print("  RESULT")
    print("=" * 78)
    print()
    print("    %d cells searched, %d produced a relation the screen accepts"
          % (len(grid) * len(constants), len(survivors)))
    print()
    if not survivors:
        print("    Nothing survived. At this precision the grid holds no relation with")
        print("    coefficients small enough to be distinguished from an accidental cancellation.")
        print("    That is a statement about the precision as much as the space: a relation with")
        print("    larger coefficients needs proportionally more digits before it can be seen at")
        print("    all, and depth is the single axis this engine has without a floor.")
    else:
        for name, base, power, stride, coefficients, residual, size in survivors[:10]:
            print("    %s, base %d, power %d, stride %d" % (name, base, power, stride))
            print("      %s" % ", ".join(str(v) for v in coefficients))
            print("      residual %s" % format(abs(residual), ","))
        print()
        print("    Each is a CANDIDATE and none is a discovery until it is checked against")
        print("    Bailey's compendium: most of this space is already mapped, and the screen")
        print("    only certifies that a relation is not a precision artifact.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
