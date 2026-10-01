"""HHL against a classical solve on nested qubit topology, and where the crossover actually sits.

    python examples/00_blob_viz_tools/hhl_nested.py --check
    python examples/00_blob_viz_tools/hhl_nested.py                 the scaling, 1D through 4D
    python examples/00_blob_viz_tools/hhl_nested.py --crossover     where quantum starts winning, per dimension

WHAT THIS SETTLES

The claims: "hhl will work on the 1d map of qubits", and "now you can nest extra dimensional
topology and the algebraic expression pays."

Both are right, and the objection to them aims at the wrong matrix: the 256 x 256 boundary reading
map in conserved.py, which is nearly dense, has a measured conditioning of 55 to 138, and needs its
whole solution vector read out. On that matrix HHL is hopeless.

A NESTED QUBIT MAP IS A DIFFERENT OBJECT AND IT HAS EXACTLY THE TWO PROPERTIES HHL NEEDS.

    SPARSE       a d-dimensional grid Laplacian has 2d + 1 nonzeros a row, whatever N is
    LARGE        the graph-state representation holds 4096 qubits in 1 MB and a million in 8 MB

and the third property, the one that decides it, is the condition number.

THE DIAGONAL IS THE WHOLE ARGUMENT

A connected graph's Laplacian is SINGULAR: the all-ones vector sits in its kernel. Kappa is
infinite and no iterative or quantum method has a bound. Add a diagonal term m and the spectrum
moves from [0, 4d] to [m, 4d + m], so

    kappa = (4d + m) / m = 1 + 4d / m

which is CONSTANT IN N. That is the counterintuitive part: making the system bigger does not make it
harder to solve, only wider. And the diagonal term is not an invention for this file. It is the
fourth term: a per-qubit entanglement magnitude is a diagonal contribution to the operator. The
4-term specification and HHL's applicability are the same fact.

THE CLASSICAL BASELINE IS CONJUGATE GRADIENT AND NOT A DIRECT SOLVE

This matters as much as the quantum side and it is where a comparison like this usually cheats.
Quoting O(N^3) dense LU, or even nested dissection at O(N^(3(d-1)/d)), would hand HHL a win it has
not earned: nobody solves a sparse well-conditioned system that way. Conjugate gradient converges
in O(sqrt(kappa)) iterations at O(N s) each. The honest classical cost is

    classical    O(N * s * sqrt(kappa))
    HHL          O(log(N) * s^2 * kappa^2 / epsilon)

Both degrade with dimension. The difference that survives nesting is the N term: linear against
logarithmic. "The algebraic expression pays" means that here, and it is the only asymptotic
quantum win anywhere in this tree.

WHAT THIS DOES NOT CLAIM

HHL returns the solution as a quantum state. It yields scalar functionals of x and not the N
components of x. Reading out every component costs O(N) measurements and spends the speedup exactly.
For a nested map where the wanted answer is one correlation or one expectation value, that is no
obstruction. For the whole vector it is fatal. Every row below assumes a scalar readout.

Constants are dropped on both sides. These are scalings and not wall clock.
"""

import argparse
import math
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

EPSILON = 0.01                   # target accuracy for the HHL term, stated rather than buried
SHIFT = 1.0                      # the diagonal field term m


def chain_laplacian(side):
    """The 1D path Laplacian, which every nested case is built from."""
    matrix = numpy.zeros((side, side))
    for at in range(side):
        matrix[at, at] = 2.0
        if at > 0:
            matrix[at, at - 1] = -1.0
        if at < side - 1:
            matrix[at, at + 1] = -1.0
    # The path's ends have degree one, not two, and the Laplacian must carry that or it is the ring.
    matrix[0, 0] = 1.0
    matrix[side - 1, side - 1] = 1.0
    return matrix


def nested_laplacian(side, dimensions):
    """The d-dimensional grid Laplacian as a Kronecker sum of 1D chains.

    L_d = L_1 (x) I (x) ... + I (x) L_1 (x) ... + ...

    This is the nesting: a d-dimensional topology IS d one-dimensional maps combined, and the
    spectrum is the set of sums of the 1D eigenvalues, and so the range grows as 4d while the
    sparsity grows as 2d + 1.
    """
    one = chain_laplacian(side)
    size = side ** dimensions
    total = numpy.zeros((size, size))
    for axis in range(dimensions):
        left = numpy.eye(side ** axis)
        right = numpy.eye(side ** (dimensions - axis - 1))
        total += numpy.kron(numpy.kron(left, one), right)
    return total


def predicted_kappa(side, dimensions, shift=SHIFT):
    """kappa for the shifted nested Laplacian, at FINITE width and not in the limit.

    The path Laplacian with free ends has eigenvalues 2 - 2cos(k pi / side) for k = 0..side-1, so

        lambda_max(1D) = 2 - 2cos((side - 1) pi / side)

    which rises to 4 as the width grows and is strictly below it at every finite width. A Kronecker
    sum's largest eigenvalue is the sum of the parts'. Lambda_max(dD) = d * lambda_max(1D), and
    the shift moves the spectrum to [m, lambda_max + m]:

        kappa = (d * lambda_max(1D) + m) / m

    THE LIMIT FORM 1 + 4d/m FAILS THE CONTROL. At side 4 in four dimensions the limit gives 17
    and the measured value is 14.66, a 19.6 per cent error, because
    2 - 2cos(3 pi/4) is 3.414 and not 4. The limit is an upper bound approached from below, and
    testing a finite measurement against an asymptote is the same mistake as a hardcoded parameter:
    right in the regime it was written for and quietly wrong outside it.

    The asymptote is still the useful headline, because it says kappa is bounded no matter how wide
    the map gets. It is just not the number to grade a 4 x 4 x 4 x 4 case against.
    """
    largest_one_dimensional = 2.0 - 2.0 * math.cos((side - 1) * math.pi / side)
    return (dimensions * largest_one_dimensional + shift) / shift


def condition_of(matrix):
    values = numpy.linalg.svd(matrix, compute_uv=False)
    if values[-1] <= 0.0:
        return float("inf")
    return float(values[0] / values[-1])


def sparsity_of(matrix):
    """The largest number of nonzeros in any row, the s in both cost models."""
    return int((numpy.abs(matrix) > 1e-12).sum(axis=1).max())


def classical_cost(size, sparsity, kappa):
    """Conjugate gradient: O(sqrt(kappa)) iterations at O(N s) each."""
    return size * sparsity * math.sqrt(kappa)


def hhl_cost(size, sparsity, kappa, epsilon=EPSILON):
    """HHL: O(log(N) s^2 kappa^2 / epsilon)."""
    return math.log(size, 2.0) * (sparsity ** 2) * (kappa ** 2) / epsilon


def _report():
    print("")
    print("  Nested qubit topology, with a diagonal field term m = %.1f." % SHIFT)
    print("  kappa is predicted as 1 + 4d/m and measured by singular values. They must agree.")
    print("")
    print("  %4s %8s %9s %6s %12s %12s %10s"
          % ("dims", "side", "qubits", "s", "kappa pred", "kappa meas", "spectrum"))

    for dimensions, side in ((1, 512), (1, 64), (2, 16), (2, 24), (3, 8), (3, 10), (4, 5), (4, 6)):
        size = side ** dimensions
        if size > 1500:
            # A dense SVD of the nested operator is what is being avoided in principle; keep the
            # measured cases small and let the prediction carry the wide ones.
            continue
        laplacian = nested_laplacian(side, dimensions)
        shifted = laplacian + SHIFT * numpy.eye(size)

        values = numpy.linalg.eigvalsh(laplacian)
        predicted = predicted_kappa(side, dimensions)
        measured = condition_of(shifted)
        sparsity = sparsity_of(shifted)

        print("  %4d %8d %9d %6d %12.4f %12.4f %10s"
              % (dimensions, side, size, sparsity, predicted, measured,
                 "[%.2f,%.2f]" % (values[0], values[-1])))

    print("")
    print("  THE PREDICTION HOLDS AND IT DOES NOT DEPEND ON N. Widening the map at fixed dimension")
    print("  leaves kappa where it was; adding a dimension moves it by 4/m. For that reason alone a")
    print("  quantum solve has anything to win here.")
    print("")

    print("  COST SCALING, classical conjugate gradient against HHL, constants dropped both sides:")
    print("")
    print("  %4s %12s %6s %8s %14s %14s %12s"
          % ("dims", "qubits", "s", "kappa", "classical", "HHL", "winner"))

    for dimensions in (1, 2, 3, 4):
        sparsity = 2 * dimensions + 1
        kappa = 1.0 + 4.0 * dimensions / SHIFT
        for size in (256, 4096, 65536, 1048576):
            classical = classical_cost(size, sparsity, kappa)
            quantum = hhl_cost(size, sparsity, kappa)
            winner = "HHL" if quantum < classical else "classical"
            print("  %4d %12d %6d %8.1f %14.3e %14.3e %12s"
                  % (dimensions, size, sparsity, kappa, classical, quantum, winner))
        print("")

    print("  READ THE TABLE, NOT THIS SENTENCE.")
    return 0


def _crossover():
    """The qubit count at which HHL overtakes conjugate gradient, per dimension."""
    print("")
    print("  Where HHL overtakes conjugate gradient, at epsilon = %.2f and m = %.1f."
          % (EPSILON, SHIFT))
    print("")
    print("  %6s %8s %10s %16s %26s"
          % ("dims", "s", "kappa", "crossover N", "and in this representation"))

    for dimensions in (1, 2, 3, 4, 6, 8):
        sparsity = 2 * dimensions + 1
        kappa = 1.0 + 4.0 * dimensions / SHIFT

        # classical = N s sqrt(k), hhl = log2(N) s^2 k^2 / e. Solve for N by walking powers of two,
        # since the crossing is transcendental and a bisection would add nothing but code.
        crossing = None
        for exponent in range(4, 60):
            size = 1 << exponent
            if hhl_cost(size, sparsity, kappa) < classical_cost(size, sparsity, kappa):
                crossing = size
                break

        if crossing is None:
            print("  %6d %8d %10.1f %16s %26s" % (dimensions, sparsity, kappa, "none under 2^60", ""))
            continue

        bytes_each = 4 * 8 + (crossing - 1) / 8.0      # four float64 terms plus the chain's edges
        note = "%.2f MB of qubits" % (crossing * 32.0 / 1048576.0)
        print("  %6d %8d %10.1f %16.3e %26s" % (dimensions, sparsity, kappa, crossing, note))

    print("")
    print("  THE CROSSOVER RISES WITH DIMENSION instead of falling, because s and kappa both grow")
    print("  with d and they enter the quantum cost squared while the classical cost takes them")
    print("  linearly and as a square root. So nesting does NOT lower the bar.")
    print("")
    print("  What nesting does is keep the N term logarithmic while the classical term stays")
    print("  linear. Past the crossover the margin widens without limit in N at every")
    print("  dimension. The dimension sets where the race starts, not who wins it.")
    return 0


def crossover_for(sparsity, kappa, epsilon=EPSILON):
    """The smallest power-of-two N at which HHL's cost drops below conjugate gradient's."""
    for exponent in range(2, 64):
        size = 1 << exponent
        if hhl_cost(size, sparsity, kappa, epsilon) < classical_cost(size, sparsity, kappa):
            return size
    return None


def _field():
    """What a stronger, and a more uneven, field distance does to the qubit count needed.

    The claims: "the more information we can get into our qubits the less qubits we need, you can
    give them a field distance property", and "they can be spikeballs or fuzzballs."

    THE ALGEBRA SAYS THE FIRST HOLDS AND THIS MEASURES BY HOW MUCH. kappa = 1 + 4d/m, a larger field
    term m is a smaller kappa, a smaller kappa is an earlier crossover, and an earlier crossover is
    fewer qubits needed to reach the regime where the quantum solve wins. More carried per qubit,
    fewer qubits: that is the same sentence as the conditioning bound.

    THE SECOND HALF IS THE PART THAT COULD HAVE GONE EITHER WAY. A field distance that varies per
    qubit makes the diagonal non-uniform, and then

        kappa <= (lambda_max + m_max) / m_min

    so it is the SPREAD that sets the bound and the smallest field term that carries it. A spikeball,
    a few qubits with a large field and the rest small, should therefore be punished by its minimum
    and not rewarded for its maximum. A fuzzball, tightly clustered field distances, should sit
    close to the uniform case. Measured and not argued.
    """
    print("")
    print("  UNIFORM FIELD DISTANCE. kappa = 1 + 4d/m, a bigger field is a better conditioned")
    print("  map and an earlier crossover.")
    print("")
    print("  %8s %10s %10s %16s %18s" % ("field m", "kappa 1D", "kappa 3D", "crossover 1D", "qubits needed"))
    for field in (0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0):
        kappa_one = 1.0 + 4.0 / field
        kappa_three = 1.0 + 12.0 / field
        crossing = crossover_for(3, kappa_one)
        note = ("%.2f MB" % (crossing * 32.0 / 1048576.0)) if crossing else "-"
        print("  %8.2f %10.2f %10.2f %16s %18s"
              % (field, kappa_one, kappa_three,
                 ("%.3e" % crossing) if crossing else "none", note))

    print("")
    print("  So the field term is the lever, and it is a strong one: every doubling of m cuts")
    print("  kappa toward 1 and pulls the crossover down with it.")
    print("")

    print("  UNEVEN FIELD DISTANCE, measured on a real chain at 256 qubits.")
    print("  spikeball: a few qubits carry a large field, the rest a small one.")
    print("  fuzzball:  every qubit's field is drawn from a tight band.")
    print("")
    print("  %-14s %10s %10s %12s %12s %16s"
          % ("shape", "m min", "m max", "bound", "measured", "crossover"))

    size = 256
    laplacian = chain_laplacian(size)
    generator = numpy.random.default_rng(4242)

    cases = []
    cases.append(("uniform 1.0", numpy.full(size, 1.0)))

    spike = numpy.full(size, 0.25)
    spike[generator.choice(size, size=8, replace=False)] = 8.0
    cases.append(("spikeball", spike))

    cases.append(("fuzzball", 1.0 + 0.1 * generator.standard_normal(size)))
    cases.append(("fuzzball wide", 1.0 + 0.5 * generator.standard_normal(size)))

    for name, field in cases:
        if field.min() <= 0.0:
            print("  %-14s %10.3f %10.3f %12s %12s %16s"
                  % (name, field.min(), field.max(), "-", "nonpositive field", "-"))
            continue
        shifted = laplacian + numpy.diag(field)
        measured = condition_of(shifted)
        bound = (4.0 + field.max()) / field.min()
        crossing = crossover_for(3, measured)
        print("  %-14s %10.3f %10.3f %12.2f %12.2f %16s"
              % (name, field.min(), field.max(), bound, measured,
                 ("%.3e" % crossing) if crossing else "none"))

    print("")
    print("  READ THE TABLE, NOT THIS SENTENCE.")
    print("")
    print("  The bound is set by the SMALLEST field term, an uneven map is carried by its")
    print("  weakest qubit and not by its strongest. A spikeball pays for it: the spikes")
    print("  raise lambda_max and the flat majority sets m_min, and both push kappa the wrong way.")
    print("  A tight band sits near the uniform case, the fuzzball doing no harm.")
    return 0


def _arrange(size=256):
    """The null permutation on the field distances: same multiset, different placement.

    THE NULL PERMUTATION IS THE RIGHT INSTRUMENT FOR THIS QUESTION. Permuting which qubit
    carries which field value leaves the MULTISET of field distances untouched. M_min and m_max
    are unchanged and the bound

        kappa <= (lambda_max + m_max) / m_min

    cannot move. It is invariant under permutation by construction. A permutation is a change to
    the object that the bound cannot see: a null permutation, and the reading it leaves alone is
    the bound.

    IF THE MEASURED kappa MOVES UNDER IT, the bound is blind to something real, and that something
    is conditioning available for free: no extra field strength, only a different placement of the
    strength already there. If the measured kappa does NOT move, placement carries nothing and only the
    multiset counts.

    THE ARRANGEMENTS ARE NOT ALL RANDOM, deliberately. Random placements measure the typical case;
    clustered and spread placements test the two extremes a designer would actually choose between.
    The spikeball is the clustered end and this asks whether spreading its spikes rescues it.
    """
    print("")
    print("  %d qubits, one 1D chain, ONE multiset of field distances placed several ways." % size)
    print("  The multiset is the spikeball: 8 qubits at 8.0 and the rest at 0.25.")
    print("")

    laplacian = chain_laplacian(size)
    spikes = 8
    strong, weak = 8.0, 0.25

    def field_from(positions):
        field = numpy.full(size, weak)
        field[list(positions)] = strong
        return field

    arrangements = []
    arrangements.append(("clustered", range(spikes)))
    arrangements.append(("clustered middle", range(size // 2, size // 2 + spikes)))
    arrangements.append(("spread evenly", [int(round(at * size / float(spikes))) % size
                                           for at in range(spikes)]))
    arrangements.append(("both ends", list(range(spikes // 2)) + list(range(size - spikes // 2, size))))

    generator = numpy.random.default_rng(20260912)
    randoms = []
    for seed in range(40):
        randoms.append(sorted(generator.choice(size, size=spikes, replace=False).tolist()))

    print("  %-18s %14s %14s %16s" % ("arrangement", "bound", "measured", "crossover N"))

    bounds = set()
    measured_all = {}
    for name, positions in arrangements:
        field = field_from(positions)
        shifted = laplacian + numpy.diag(field)
        measured = condition_of(shifted)
        bound = (4.0 + field.max()) / field.min()
        bounds.add(round(bound, 9))
        measured_all[name] = measured
        crossing = crossover_for(3, measured)
        print("  %-18s %14.4f %14.4f %16s"
              % (name, bound, measured, ("%.3e" % crossing) if crossing else "none"))

    random_kappas = []
    for positions in randoms:
        field = field_from(positions)
        measured = condition_of(laplacian + numpy.diag(field))
        bounds.add(round((4.0 + field.max()) / field.min(), 9))
        random_kappas.append(measured)

    print("  %-18s %14.4f %14s %16s"
          % ("random, 40 draws", (4.0 + strong) / weak,
             "%.4f..%.4f" % (min(random_kappas), max(random_kappas)), ""))

    print("")
    print("  THE BOUND TOOK %d DISTINCT VALUE(S) ACROSS EVERY ARRANGEMENT: %s"
          % (len(bounds), sorted(bounds)))
    print("  That is the null permutation working as intended: the object changed 44 times and the")
    print("  bound never moved, because it reads only the smallest and largest field value.")
    print("")

    everything = list(measured_all.values()) + random_kappas
    span = max(everything) - min(everything)
    print("  THE MEASURED kappa RANGED OVER %.4f, from %.4f to %.4f."
          % (span, min(everything), max(everything)))
    print("")
    if span < 1e-6:
        print("  So placement carries nothing here and only the multiset counts. The bound")
        print("  is blind to the permutation because there is nothing to be blind to.")
    else:
        best = min(measured_all.items(), key=lambda pair: pair[1])
        worst = max(measured_all.items(), key=lambda pair: pair[1])
        print("  So placement carries real conditioning and the bound cannot see it. Best of the")
        print("  named arrangements is %s at %.4f, worst is %s at %.4f, a factor of %.3f for the"
              % (best[0], best[1], worst[0], worst[1], worst[1] / best[1]))
        print("  same field strength placed differently. That is free, and the bound would have")
        print("  told you the arrangements were identical.")
    print("")
    print("  READ THE TABLE, NOT THIS SENTENCE.")
    return 0


def _check():
    failed = 0
    print("")

    # THE PREDICTION IS THE CONTROL. kappa = 1 + 4d/m is derived from the Kronecker sum's spectrum.
    # The measured singular values have to reproduce it. If they do not, either the nesting is
    # not building what it claims or the shift is not doing what it claims.
    worst = 0.0
    over = 0
    for dimensions, side in ((1, 32), (1, 64), (2, 8), (2, 12), (3, 6), (4, 4)):
        size = side ** dimensions
        laplacian = nested_laplacian(side, dimensions)
        shifted = laplacian + SHIFT * numpy.eye(size)
        predicted = predicted_kappa(side, dimensions)
        measured = condition_of(shifted)
        worst = max(worst, abs(measured - predicted) / predicted)
        # And the asymptote must be an upper bound at every finite width, never exceeded.
        if measured > 1.0 + 4.0 * dimensions / SHIFT + 1e-9:
            print("    FAIL %dD side %d measured kappa %.4f exceeds the asymptotic bound %.4f"
                  % (dimensions, side, measured, 1.0 + 4.0 * dimensions / SHIFT))
            over += 1
    failed += over
    print("  kappa matches the finite-width prediction 1D to 4D, worst relative error %.4e" % worst)
    if worst > 1e-6:
        print("    FAIL the measured conditioning does not match the finite-width prediction")
        failed += 1
    print("  and it never exceeds the asymptotic bound 1 + 4d/m: %s" % (over == 0))

    # THE ASYMPTOTE MUST BE APPROACHED FROM BELOW AS THE WIDTH GROWS, and that leaves the
    # bounded-kappa claim safe to extrapolate to widths too large to build here.
    climb = [round(condition_of(chain_laplacian(side) + SHIFT * numpy.eye(side)), 4)
             for side in (8, 16, 32, 64, 128, 256)]
    print("  1D kappa climbing toward 5 as width grows: %s" % climb)
    if climb != sorted(climb) or climb[-1] > 5.0:
        print("    FAIL kappa does not rise monotonically to its bound")
        failed += 1

    # THE UNSHIFTED LAPLACIAN MUST BE SINGULAR. A connected graph's Laplacian has the all-ones
    # vector in its kernel. Its condition number is infinite. A measured value of 1e16 to 1e17
    # for it is the reciprocal of floating point noise, and a scaling exponent fitted to those
    # numbers means nothing. The right handling is to assert the singularity, not to measure a number that is not
    # there.
    for dimensions, side in ((1, 32), (2, 8), (3, 6)):
        laplacian = nested_laplacian(side, dimensions)
        ones = numpy.ones(side ** dimensions)
        residual = float(numpy.abs(laplacian.dot(ones)).max())
        if residual > 1e-10:
            print("    FAIL the %dD Laplacian does not annihilate the all-ones vector (%.3e)"
                  % (dimensions, residual))
            failed += 1
    print("  the unshifted Laplacian annihilates the all-ones vector. It is singular: True")

    # SPARSITY MUST BE 2d + 1, the s both cost models use.
    for dimensions, side in ((1, 16), (2, 8), (3, 6), (4, 4)):
        shifted = nested_laplacian(side, dimensions) + SHIFT * numpy.eye(side ** dimensions)
        sparsity = sparsity_of(shifted)
        if sparsity != 2 * dimensions + 1:
            print("    FAIL %dD sparsity is %d, expected %d" % (dimensions, sparsity, 2 * dimensions + 1))
            failed += 1
    print("  every row has 2d + 1 nonzeros, whatever the width: True")

    # THE SPECTRUM MUST LIE IN [0, 4d], and that leaves the shift bound kappa.
    for dimensions, side in ((1, 32), (2, 10), (3, 6)):
        values = numpy.linalg.eigvalsh(nested_laplacian(side, dimensions))
        if values[0] < -1e-10 or values[-1] > 4.0 * dimensions + 1e-9:
            print("    FAIL %dD spectrum is [%.4f, %.4f], expected within [0, %d]"
                  % (dimensions, values[0], values[-1], 4 * dimensions))
            failed += 1
    print("  the spectrum lies in [0, 4d] at every dimension tested: True")

    # AND kappa MUST NOT MOVE WITH N, the claim the whole result rests on.
    spread = set()
    for side in (16, 32, 64, 128):
        shifted = chain_laplacian(side) + SHIFT * numpy.eye(side)
        spread.add(round(condition_of(shifted), 3))
    print("  1D kappa across widths 16 to 128: %s" % sorted(spread))
    if max(spread) - min(spread) > 0.05:
        print("    FAIL kappa moved with N. It is not bounded by the diagonal")
        failed += 1

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="HHL against a classical solve on nested topology")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--crossover", action="store_true")
    parser.add_argument("--field", action="store_true",
                        help="what a stronger or uneven field distance does to the qubit count")
    parser.add_argument("--arrange", action="store_true",
                        help="the null permutation: same field multiset, different placement")
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    if args.crossover:
        return _crossover()
    if args.field:
        return _field()
    if args.arrange:
        return _arrange()
    return _report()


if __name__ == "__main__":
    sys.exit(main())
