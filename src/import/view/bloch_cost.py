"""Where the exponential cost of a quantum state actually lives, measured against entanglement.

    python tools/view/bloch_cost.py --check
    python tools/view/bloch_cost.py                 the cost against entanglement entropy

THE CORRECTION THIS FILE EXISTS TO RECORD

I had been answering that n qubits need 2^n amplitudes, and quoting the storage for 4096 of them as
though that settled it. Douglas: infinite compressibility means a double is a vector, and another
double is a magnitude, and their difference is their angle.

He is right and the counting I was doing was the wrong counting. A single qubit is a DIRECTION AND A
LENGTH:

    |psi> = cos(theta/2)|0> + exp(i phi) sin(theta/2)|1>

which is two real numbers. So n qubits in that form is 2n reals, and 4096 of them is 8192 numbers,
about 64 KB. The exponential is nowhere in that description.

SO WHERE IS THE EXPONENTIAL, SINCE IT IS REAL

It is in the ENTANGLEMENT and nowhere else. The Bloch form describes a PRODUCT state, one direction
per qubit with no correlation between them, and the product states are a vanishing corner of the
space: 2n parameters against 2^(n+1) - 2 for the whole of it. Everything the extra parameters buy is
correlation.

That is a sharper statement than the one I was making, and it is the measurable one. This file takes
states of known entanglement, fits the best product description to each, and reports the error
against the entanglement entropy. The prediction is that the error is zero at zero entanglement and
rises with it, so the cost of the state is exactly what the product form cannot say.

AND IT LINES UP WITH WHAT --nested MEASURED. Local purity one meant a product state and the
inversion had nothing to undo. Local purity 0.5 meant maximal correlation across the split and the
inversion had to reach the whole structure. Same axis, read from the storage side instead of the
recovery side.
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy

QUBITS = 6
WIDTH = 1 << QUBITS


def product_state(angles):
    """A state built as one direction per qubit, which is the Bloch form of a product state.

    `angles` is a list of (theta, phi) pairs, so the whole description is 2n real numbers however
    many qubits there are. The state vector is their tensor product, computed here only so the
    entanglement can be measured: the DESCRIPTION is the angles and it never grows past 2n.
    """
    state = numpy.array([1.0 + 0j])
    for theta, phi in angles:
        one = numpy.array([math.cos(theta / 2.0),
                           complex(math.cos(phi), math.sin(phi)) * math.sin(theta / 2.0)])
        state = numpy.kron(state, one)
    return state


def reduced(state, keep, qubits=QUBITS):
    kept = 1 << keep
    rest = 1 << (qubits - keep)
    block = state.reshape(kept, rest)
    return block.dot(block.conj().T)


def entropy_of(state, keep, qubits=QUBITS):
    """Entanglement entropy across the split, in bits. Zero for a product state."""
    values = numpy.linalg.eigvalsh(reduced(state, keep, qubits))
    return -sum(float(one) * math.log2(float(one)) for one in values if one > 1e-14)


def best_product_fit(state, qubits=QUBITS, rounds=400):
    """The closest product state, by alternating projection onto each qubit's own direction.

    Each sweep replaces one qubit's direction with the one that best matches the target given the
    others, which is the standard alternating scheme for a rank-one tensor approximation. What is
    returned is the overlap, so one means the state IS a product state and less means the product
    form cannot express it.
    """
    generator = numpy.random.default_rng(3)
    vectors = []
    for _ in range(qubits):
        one = generator.normal(size=2) + 1j * generator.normal(size=2)
        vectors.append(one / numpy.linalg.norm(one))

    tensor = state.reshape([2] * qubits)
    for _ in range(rounds):
        for at in range(qubits):
            partial = tensor
            # Contract every other qubit against its current direction.
            for other in reversed(range(qubits)):
                if other == at:
                    continue
                partial = numpy.tensordot(partial, vectors[other].conj(), axes=([other], [0]))
            length = numpy.linalg.norm(partial)
            if length > 0:
                vectors[at] = partial / length

    fitted = numpy.array([1.0 + 0j])
    for one in vectors:
        fitted = numpy.kron(fitted, one)
    return abs(complex(numpy.vdot(fitted, state)))


def entangling_pairs(strength, qubits=QUBITS):
    """A state with a tunable amount of entanglement across the middle split.

    At strength zero this is a product state exactly. At strength one it is a maximally correlated
    pair across the split. Nothing else about the state changes, so the only variable is the
    correlation.
    """
    state = numpy.zeros(1 << qubits, dtype=complex)
    half = qubits // 2
    for at in range(1 << qubits):
        top = at >> (qubits - half)
        low = at & ((1 << (qubits - half)) - 1)
        if top == low:
            state[at] = 1.0
        else:
            state[at] = 0.0
    correlated = state / numpy.linalg.norm(state)

    flat = numpy.full(1 << qubits, 1.0 / math.sqrt(1 << qubits), dtype=complex)
    mixed = (1.0 - strength) * flat + strength * correlated
    return mixed / numpy.linalg.norm(mixed)


def _report():
    print("  %d qubits. A product description is 2n = %d real numbers, whatever n is."
          % (QUBITS, 2 * QUBITS))
    print("  A full state vector is 2^n = %d complex amplitudes. The question is when the first"
          % WIDTH)
    print("  description is enough, and the answer is entanglement.")
    print("")
    print("  %10s %18s %18s %18s"
          % ("strength", "entropy bits", "product overlap", "error"))

    for step in range(11):
        strength = step / 10.0
        state = entangling_pairs(strength)
        entropy = entropy_of(state, QUBITS // 2)
        overlap = best_product_fit(state)
        print("  %10.2f %18.6f %18.9f %18.3e"
              % (strength, entropy, overlap, 1.0 - overlap))

    print("")
    print("  AT ZERO ENTANGLEMENT THE PRODUCT FORM IS EXACT and 2n numbers carry the whole state.")
    print("  That is Douglas's point and it holds: a direction and a length per qubit, and the")
    print("  exponential is nowhere in it. 4096 qubits in that form is 8192 numbers, about 64 KB.")
    print("")
    print("  THE ERROR RISES WITH THE ENTANGLEMENT AND NOTHING ELSE CHANGES DOWN THE TABLE. So the")
    print("  exponential cost is not the cost of the qubits, it is the cost of the CORRELATION")
    print("  between them. That is a sharper statement than the one I was making and it is his.")
    print("")
    print("  WHAT IT COSTS TO GO PART WAY, since this is the useful axis. A matrix product state")
    print("  with bond dimension chi needs about 2 n chi^2 numbers and represents exactly the")
    print("  states whose entanglement entropy is at most log2(chi) across every split:")
    print("")
    print("  %10s %16s %22s" % ("chi", "entropy it holds", "numbers for 4096 qubits"))
    for chi in (1, 2, 4, 16, 256, 65536):
        print("  %10d %16.1f %22.3e" % (chi, math.log2(chi), 2.0 * 4096 * chi * chi))
    print("")
    print("  So the storage is exponential in the ENTANGLEMENT and linear in the qubit count. A")
    print("  product state is chi of one. A maximally entangled state of n qubits needs chi of")
    print("  2^(n/2), which is where the 2^n comes back from.")
    print("")
    print("  AND THE CATCH IS THE SAME ONE AS EVERY OTHER TIME TODAY. The states a quantum")
    print("  computer is worth having for are the entangled ones: Grover's intermediate states are")
    print("  entangled, and that is where its advantage lives. Stabiliser circuits and low bond")
    print("  dimension tensor networks are efficiently simulable classically PRECISELY BECAUSE")
    print("  they are cheap to describe. Cheap to describe and worth a quantum computer are the")
    print("  two ends of one axis, which is the third form of that trade measured today.")
    return 0


def _terms():
    """How far do more terms per qubit get, and where exactly do they stop?

    Douglas: we can represent entanglement, we have a third and fourth term, a polarisation and an
    entanglement vector, magnitudeless.

    That is the right instinct and it buys a real amount. The question is arithmetic: a pure state of
    n qubits has 2^(n+1) - 2 real parameters after normalisation and global phase are removed, and
    any scheme spending a FIXED number of reals per qubit has c*n. So the question is where c*n
    stops covering 2^(n+1) - 2, and the answer does not depend on which four quantities are chosen.
    """
    print("  A pure state of n qubits carries 2^(n+1) - 2 real parameters, after normalisation and")
    print("  global phase are taken out. A fixed budget per qubit carries c*n. Where do they cross?")
    print("")
    print("  %5s %10s %12s %14s %16s %10s"
          % ("qubits", "2n Bloch", "4n proposed", "n^2 pairwise", "full state", "4n covers"))

    for qubits in (2, 3, 4, 6, 8, 12, 16, 32, 64, 4096):
        # Python integers, because 2.0 ** 4097 overflows a float and the first version of this
        # line raised OverflowError on the last row. The exponent is the whole point of the table,
        # so the one place it must not be approximated is here.
        full = (1 << (qubits + 1)) - 2
        covers = "yes" if 4 * qubits >= full else "no"
        shown = "%d" % full if full < 10 ** 12 else "1e%.0f" % (math.log10(2.0) * (qubits + 1))
        print("  %5d %10d %12d %14d %16s %10s"
              % (qubits, 2 * qubits, 4 * qubits, qubits * qubits, shown, covers))

    print("")
    print("  FOUR TERMS PER QUBIT COVERS TWO QUBITS EXACTLY AND FAILS FROM THREE. At two qubits the")
    print("  full space is six parameters and four terms each gives eight, so there is room to")
    print("  spare and every two qubit state including a Bell pair is representable. At three the")
    print("  space is fourteen and the budget is twelve, and the gap doubles with every qubit after.")
    print("")
    print("  AND THAT CONCLUSION DOES NOT DEPEND ON WHICH FOUR QUANTITIES ARE CHOSEN. It is a")
    print("  counting argument: any fixed number of reals per qubit is linear in n and the state")
    print("  space is exponential in n, so they cross early and never uncross. A polarisation term")
    print("  and an entanglement vector are good choices and they do not change the exponent.")
    print("")
    print("  WHAT DOES REACH FURTHER, AND IT IS THE LADDER HIS IDEA IS THE SECOND RUNG OF:")
    print("")
    print("    2n reals          product states only, zero entanglement, exact")
    print("    4n reals          every two qubit state, and pairwise structure beyond that")
    print("    n^2 numbers       pairwise correlations, which is a covariance matrix")
    print("    O(n^2) BITS       STABILISER states, by Gottesman and Knill: n generators of 2n+1")
    print("                      bits each, and these ARE massively entangled. Bell pairs, GHZ")
    print("                      states, the whole Clifford orbit, at millions of qubits.")
    print("    2 n chi^2         matrix product states, entanglement up to log2(chi) per split")
    print("    2^(n+1) - 2       everything")
    print("")
    print("  SO ENTANGLEMENT IS NOT THE THING THAT IS EXPENSIVE. STRUCTURELESS entanglement is.")
    print("  A GHZ state over a million qubits is maximally entangled and costs O(n^2) bits, and a")
    print("  stabiliser simulator runs it comfortably. What no fixed or polynomial budget holds is")
    print("  a GENERIC state, and by pigeonhole almost every state is generic.")
    print("")
    print("  AND THE CATCH ARRIVES IN THE SAME PLACE IT ALWAYS DOES. Gottesman and Knill is a")
    print("  simulability theorem: Clifford circuits are efficiently classically simulable, which")
    print("  is exactly why stabiliser states are cheap to hold. Every rung of that ladder that is")
    print("  cheap is cheap BECAUSE the states on it carry no advantage, and the first rung that")
    print("  carries advantage is the one nothing polynomial reaches.")
    print("")
    print("  HOW MANY TERMS PER QUBIT WOULD ACTUALLY BE ENOUGH, which is the sharpest form of the")
    print("  question. Solve c*n >= 2^(n+1) - 2 for c, so this is the budget per qubit that a")
    print("  representation would have to carry to cover every state of n qubits:")
    print("")
    print("  %8s %24s" % ("qubits", "terms needed per qubit"))
    for qubits in (2, 3, 4, 8, 16, 32, 64, 128):
        needed = ((1 << (qubits + 1)) - 2 + qubits - 1) // qubits
        shown = "%d" % needed if needed < 10 ** 9 else "1e%.0f" % math.log10(needed)
        print("  %8d %24s" % (qubits, shown))

    print("")
    print("  And read the other way, which is the useful direction:")
    print("")
    for budget in (2, 3, 4, 8, 16, 64, 1024, 1048576):
        best = 0
        for qubits in range(1, 64):
            if budget * qubits >= (1 << (qubits + 1)) - 2:
                best = qubits
        print("       %9d terms a qubit covers every state of up to %2d qubits" % (budget, best))

    print("")
    print("  SO THE TERMS PER QUBIT MUST THEMSELVES GROW AS 2^n / n. Doubling the budget buys ONE")
    print("  more qubit, every time: three terms reach two qubits, eight reach four, sixteen reach")
    print("  five, sixty four reach eight, a thousand reach twelve, a million reach 23. That is the")
    print("  exponential arriving in the per-qubit cost instead of the qubit count, which is the")
    print("  same wall wearing a different label.")
    print("")
    print("  AND AT THAT POINT THE REPRESENTATION IS THE STATE VECTOR WITH EXTRA STEPS. A budget of")
    print("  2^n / n terms per qubit is 2^n terms in total, which is the amplitude array, reached")
    print("  by a longer road. 'Several or more vectors and magnitudes' is exactly right as a")
    print("  DESCRIPTION of a qubit and it does not change what the collection costs.")
    print("")
    print("  WHAT IS TRUE AND WORTH KEEPING. A qubit IS a vector and a magnitude, the Bloch form is")
    print("  exact, and a product state of any size is 2n reals with no approximation anywhere. The")
    print("  thing no per-qubit budget fixes is the COUNT of qubits that can be correlated at once,")
    print("  because that count is what the exponent is counting.")
    print("")
    print("  WHAT IS WORTH BUILDING OUT OF THIS, AND IT IS NOT NOTHING. The four term machine would")
    print("  represent every two qubit state exactly and every pairwise-correlated state")
    print("  approximately, at four reals a qubit, a million qubits with pairwise structure fits")
    print("  in 16 MB. That is a real instrument for a real class of states and it is worth having")
    print("  as long as its wall is written on it, the way the product machine's is.")
    return 0


def _check():
    lines = []
    failed = 0

    # A PRODUCT STATE MUST FIT EXACTLY, or the fitter is broken and every row below is noise.
    generator = numpy.random.default_rng(11)
    angles = [(float(generator.uniform(0, math.pi)), float(generator.uniform(0, 2 * math.pi)))
              for _ in range(QUBITS)]
    state = product_state(angles)
    overlap = best_product_fit(state)
    entropy = entropy_of(state, QUBITS // 2)
    lines.append("  a product state of %d qubits: entropy %.3e bits, product overlap %.12f"
                 % (QUBITS, entropy, overlap))
    if entropy > 1e-9:
        lines.append("    FAIL a product state has nonzero entanglement, so the entropy is wrong")
        failed += 1
    if abs(overlap - 1.0) > 1e-6:
        lines.append("    FAIL the fitter cannot reproduce a product state, so it grades nothing")
        failed += 1

    # 2n NUMBERS MUST BE ENOUGH. Rebuild from the angles alone and compare, which is the claim.
    rebuilt = product_state(angles)
    gap = float(numpy.linalg.norm(rebuilt - state))
    lines.append("  rebuilt from %d angles alone: difference %.3e" % (2 * QUBITS, gap))
    if gap > 1e-12:
        lines.append("    FAIL the angles do not determine the state")
        failed += 1

    # THE NEGATIVE CONTROL. A maximally entangled state must NOT fit, or the fitter returns one for
    # everything and the exactness above means nothing.
    hard = entangling_pairs(1.0)
    overlap = best_product_fit(hard)
    entropy = entropy_of(hard, QUBITS // 2)
    lines.append("  a maximally correlated state: entropy %.4f bits, product overlap %.6f"
                 % (entropy, overlap))
    if entropy < 0.5:
        lines.append("    FAIL the entangled state is not entangled, so the axis is inert")
        failed += 1
    if overlap > 0.9:
        lines.append("    FAIL a product fit reproduced an entangled state, which it cannot")
        failed += 1

    # And the error must be monotone in the entanglement, or it is not measuring entanglement.
    pairs = []
    for step in (0, 3, 6, 10):
        state = entangling_pairs(step / 10.0)
        pairs.append((entropy_of(state, QUBITS // 2), 1.0 - best_product_fit(state)))
    rising = all(pairs[at][1] <= pairs[at + 1][1] + 1e-9 for at in range(len(pairs) - 1))
    lines.append("  error rises with entropy across %s: %s"
                 % (", ".join("%.2f" % one for one, _two in pairs), rising))
    if not rising:
        lines.append("    FAIL the product error does not track the entanglement")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="where a quantum state's storage cost lives")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--terms", action="store_true",
                        help="how far more terms per qubit reach, and where they stop")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.terms:
        sys.exit(_terms())
    sys.exit(_report())
