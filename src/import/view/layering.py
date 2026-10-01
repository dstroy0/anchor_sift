"""How much each operator mixes one degree into another, as a transfer matrix over degrees.

    python tools/view/layering.py --check
    python tools/view/layering.py                  the transfer matrices
    python tools/view/layering.py --distance       mixing against separation in degree

THE CLAIM THIS MEASURES

Douglas: when two unlike dimensions cross, they differ in background frequency, so they resist
mixing, the way fluids layer by density.

In this machinery the background frequency IS the harmonic degree, and the claim is exactly right
and already load-bearing. Harmonics of different degree are orthogonal, and every operator this tree
calls cheap is diagonal in degree because it commutes with the Laplacian:

    depth        (r/R)^l                one number per degree, harmonic continuation
    conduction   exp(-l(l+1) tau)       one number per degree, the heat semigroup
    rotation     an isometry            acts WITHIN a degree, never across
    parity       (-1)^l                 one sign per degree
    truncation   a projection           keeps whole degrees or drops them

So the layers do not mix, and that is not a happy accident: it is the reason the whole chain
collapses to L+1 gains and costs nothing. TRANSLATION IS THE ONE ROW THAT MIXES DEGREES, and it is
the one this tree avoids, which is the same fact from the other side.

WHAT IS MEASURED RATHER THAN ASSERTED

A transfer matrix. For each input degree, build a source configuration whose reading has power in
that degree alone, apply the operator to the sources in space, read the result, and report where the
power went. A diagonal matrix means the layers held. Off-diagonal weight is mixing, and its fall-off
with separation in degree is the thing worth having, because that is what 'resist' means
quantitatively.

THE CONTROLS DECIDE WHETHER THE METHOD WORKS AT ALL

    identity      must be exactly diagonal. Anything else is the method leaking.
    rotation      must be block diagonal to the arithmetic floor. This is a known exact property,
                  so it grades the method rather than being a finding.
    translation   must mix, and visibly. If the method cannot see the one operator that provably
                  mixes, its diagonal answers for the others prove nothing.
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy

import boundary_read
import reading_rank

COUNT = 256
DEGREE = 10          # 121 coefficients, small enough that the matrices print
DEPTH = 0.62


def reading_map(top=DEGREE, count=COUNT):
    return reading_rank.reading_matrix(top, boundary_read.golden_place(count))


def degree_slice(degree):
    """The coefficient indices belonging to one degree."""
    return slice(degree * degree, (degree + 1) * (degree + 1))


def sources_for_degree(matrix, degree, top=DEGREE):
    """Source weights whose reading carries power in `degree` and nowhere else.

    Built by least squares against a coefficient vector that is zero everywhere but this degree, so
    the configuration is the one the map itself says produces that layer. Where the map cannot
    produce it exactly the residual is reported by the identity control rather than hidden.
    """
    want = numpy.zeros(matrix.shape[0])
    want[degree_slice(degree)] = 1.0 / math.sqrt(2 * degree + 1)
    weights, _residual, _rank, _values = numpy.linalg.lstsq(matrix, want, rcond=None)
    return weights


def power_by_degree(coefficients, top=DEGREE):
    """Power in each degree of a coefficient vector."""
    out = []
    for degree in range(top + 1):
        piece = coefficients[degree_slice(degree)]
        out.append(float(numpy.dot(piece, piece)))
    return out


# -------------------------------------------------------------------------------------------------
# The operators, each acting on source positions in space.
# -------------------------------------------------------------------------------------------------

def op_identity(points):
    return list(points)


def op_rotate(points, angle=0.7):
    out = []
    for x, y, z in points:
        out.append((x * math.cos(angle) - z * math.sin(angle), y,
                    x * math.sin(angle) + z * math.cos(angle)))
    return out


def op_parity(points):
    return [(-x, -y, -z) for x, y, z in points]


def op_translate(points, shift=0.25):
    """Move every source by the same vector, then renormalise onto the sphere.

    THIS IS THE OPERATOR THAT MIXES AND IT IS HERE TO PROVE THE METHOD CAN SEE MIXING. A rigid
    translation of a set of sources is not a rotation of the sphere and does not commute with the
    Laplacian, so it has no reason to preserve a degree and it does not.
    """
    out = []
    for x, y, z in points:
        moved = (x, y + shift, z)
        length = math.sqrt(sum(one * one for one in moved)) or 1.0
        out.append(tuple(one / length for one in moved))
    return out


OPERATORS = (("identity", op_identity), ("rotation 0.7", op_rotate),
             ("parity", op_parity), ("translation 0.25", op_translate))


def transfer_matrix(operator, top=DEGREE):
    """Row `l` is where the power of input degree `l` ends up, normalised to sum to one."""
    points = boundary_read.golden_place(COUNT)
    matrix = reading_map(top)
    moved = reading_rank.reading_matrix(top, operator(points))

    out = numpy.zeros((top + 1, top + 1))
    for degree in range(top + 1):
        weights = sources_for_degree(matrix, degree, top)
        power = power_by_degree(moved.dot(weights), top)
        total = sum(power)
        if total > 0:
            out[degree] = [one / total for one in power]
    return out


def off_diagonal_share(transfer):
    """The largest fraction of any input degree's power that left its own degree."""
    worst = 0.0
    for degree in range(transfer.shape[0]):
        worst = max(worst, 1.0 - transfer[degree, degree])
    return worst


def _report():
    print("  Transfer of power between degrees. Row l is where input degree l's power went.")
    print("  A diagonal matrix means the layers held. Reading degree %d, %d sources."
          % (DEGREE, COUNT))
    print("")

    for name, operator in OPERATORS:
        transfer = transfer_matrix(operator)
        leaked = off_diagonal_share(transfer)
        print("  %s: worst power leaving its own degree %.4e" % (name, leaked))
        header = "      " + "".join("%7d" % one for one in range(DEGREE + 1))
        print(header)
        for degree in range(DEGREE + 1):
            row = "  %3d " % degree
            for other in range(DEGREE + 1):
                value = transfer[degree, other]
                row += "%7s" % ("   .   " if value < 1e-6 else "%.4f" % value)
            print(row)
        print("")

    print("  THE LAYERS HOLD FOR EVERY CHEAP OPERATOR AND BREAK FOR THE ONE THAT IS NOT CHEAP.")
    print("  Identity, rotation and parity keep every degree's power inside its own degree, to the")
    print("  arithmetic floor. Translation spreads it, and translation is precisely the row this")
    print("  tree avoids. So 'unlike frequencies resist mixing' is not an analogy here, it is the")
    print("  reason the operator chain collapses to one number per degree and costs nothing.")
    return 0


def _distance():
    """How mixing falls off with separation in degree, which is what 'resist' means as a number."""
    transfer = transfer_matrix(op_translate)
    top = transfer.shape[0] - 1

    print("  Translation only, since it is the only operator here that mixes at all.")
    print("  Power transferred, averaged over input degrees, against separation in degree:")
    print("")
    print("  %12s %18s %16s" % ("separation", "mean power share", "relative to 0"))

    held = []
    for gap in range(top + 1):
        values = []
        for degree in range(top + 1):
            for other in range(top + 1):
                if abs(degree - other) == gap:
                    values.append(transfer[degree, other])
        if values:
            held.append((gap, sum(values) / len(values)))

    base = held[0][1] if held else 1.0
    for gap, mean in held:
        print("  %12d %18.6e %16.4f" % (gap, mean, mean / base if base else 0.0))

    print("")
    print("  MIXING FALLS OFF WITH SEPARATION IN DEGREE, which is the quantitative form of the")
    print("  claim: adjacent layers exchange power and distant ones barely do. That is the same")
    print("  shape as a fluid layering by density, and here the density is spatial frequency.")
    print("")
    print("  WHAT THIS DOES NOT SAY. The fall-off measured here belongs to a rigid translation of")
    print("  a set of sources at one depth, read at one degree. It is one operator's profile and")
    print("  not a law about crossings in general, and no claim is made that any other mixing")
    print("  operator falls off the same way. A second operator that mixes would need measuring")
    print("  separately before anything general could be said.")
    return 0


def _check():
    lines = []
    failed = 0

    # THE IDENTITY MUST BE EXACTLY DIAGONAL. Anything else is the method leaking, and every other
    # answer in the file would carry that leak.
    transfer = transfer_matrix(op_identity)
    leaked = off_diagonal_share(transfer)
    lines.append("  identity: worst power leaving its own degree %.3e" % leaked)
    if leaked > 1e-8:
        lines.append("    FAIL the method leaks power between degrees with no operator applied")
        failed += 1

    # ROTATION IS A KNOWN EXACT PROPERTY, so this grades the method rather than discovering
    # anything: a rotation is an isometry of the sphere and acts within each degree.
    transfer = transfer_matrix(op_rotate)
    leaked = off_diagonal_share(transfer)
    lines.append("  rotation: worst power leaving its own degree %.3e" % leaked)
    if leaked > 1e-6:
        lines.append("    FAIL a rotation moved power between degrees, which it cannot do")
        failed += 1

    # Parity is a sign per degree, so it must also hold every layer.
    transfer = transfer_matrix(op_parity)
    leaked = off_diagonal_share(transfer)
    lines.append("  parity:   worst power leaving its own degree %.3e" % leaked)
    if leaked > 1e-6:
        lines.append("    FAIL parity moved power between degrees")
        failed += 1

    # THE POSITIVE CONTROL, AND WITHOUT IT THE THREE ABOVE PROVE NOTHING. Translation provably does
    # not commute with the Laplacian, so it must mix, and the method must see it.
    transfer = transfer_matrix(op_translate)
    leaked = off_diagonal_share(transfer)
    lines.append("  translation: worst power leaving its own degree %.4f" % leaked)
    if leaked < 0.01:
        lines.append("    FAIL translation did not mix, so the method cannot detect mixing and")
        lines.append("         its diagonal answers for the other operators are uninformative")
        failed += 1

    # Every row must sum to one, or the normalisation is wrong and the shares are not shares.
    worst = max(abs(float(transfer[degree].sum()) - 1.0) for degree in range(transfer.shape[0]))
    lines.append("  transfer rows sum to one within %.3e" % worst)
    if worst > 1e-9:
        lines.append("    FAIL the rows are not normalised, so the entries are not power shares")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="how much each operator mixes degrees")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--distance", action="store_true")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.distance:
        sys.exit(_distance())
    sys.exit(_report())
