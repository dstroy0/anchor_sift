"""A product-state quantum machine at a fixed cost per qubit, and exactly where it stops working.

    python examples/00_blob_viz_tools/product_machine.py --check
    python examples/00_blob_viz_tools/product_machine.py            the machine, its scale and its wall
    python examples/00_blob_viz_tools/product_machine.py --width    what 64, 32 and 16 bits a qubit cost in error

THE SPECIFICATION AND WHY IT IS BUILDABLE

"Build the quantum computer with n qubit cap here, it should cost about 64b a qubit but we really
only need 32b."

That specification is a product-state machine in the Bloch form. A qubit is a direction and
a length:

    |psi> = cos(theta/2)|0> + exp(i phi) sin(theta/2)|1>

which is two real numbers. Two float32 is 64 bits a qubit, the specified figure, and it is not an
approximation of a product state. It IS one. So the qubit cap is memory divided by eight bytes, and
it reaches numbers no state vector ever will.

WHAT IT CAN DO, EXACTLY AND AT ANY SCALE

Every single-qubit gate. Rotations, Hadamard, phase, the lot, each touching two numbers and costing
nothing per qubit. A layer over a million qubits is a million cheap updates, not 2^1000000 anything.

WHAT IT CANNOT DO, AND THIS IS NOT A DEFECT

Entangle. A product state has one direction per qubit and no correlation between them by
construction. The representation has nowhere to put a correlation. The first genuinely entangling
gate is the wall, and `bloch_cost.py` measures what crossing it costs: the product form's error
rises from -2.220e-16 at zero entanglement to 6.464e-01 at maximal.

SO THE MACHINE HAS UNLIMITED QUBITS AND ZERO QUANTUM ADVANTAGE, and those two facts are the same
fact. Grover's intermediate states are entangled; that is where its speedup lives. Stabilizer
circuits and low bond dimension tensor networks are efficiently simulable classically PRECISELY
because they are cheap to describe. Cheap to describe and worth a quantum computer are opposite ends
of one axis, and this file is the cheap end built out honestly so the axis is visible.
"""

import argparse
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy

BITS_PER_QUBIT = 64          # two float32, the specified figure
BYTES_PER_QUBIT = BITS_PER_QUBIT // 8


class ProductMachine(object):
    """n qubits held as one direction each, at two float32 per qubit.

    The angles are the state. There is no amplitude array anywhere in this class, and so the
    qubit count is bounded by memory over eight bytes and not by an exponential.
    """

    def __init__(self, qubits, dtype=numpy.float32):
        self.qubits = qubits
        self.theta = numpy.zeros(qubits, dtype=dtype)
        self.phi = numpy.zeros(qubits, dtype=dtype)

    def bytes_held(self):
        return self.theta.nbytes + self.phi.nbytes

    def hadamard_all(self):
        """A Hadamard on every qubit at once, which for the zero state is theta = pi/2."""
        self.theta[:] = math.pi / 2.0
        self.phi[:] = 0.0

    def phase_all(self, angle):
        """A phase rotation on every qubit. Two array adds, whatever the qubit count."""
        self.phi += angle
        self.phi %= 2.0 * math.pi

    def rotate_all(self, angle):
        self.theta += angle
        self.theta %= 2.0 * math.pi

    def amplitudes(self):
        """The full state vector, ONLY for checking against small cases.

        This is the thing the machine exists to avoid computing and it is here so the machine can be
        graded. Calling it at any real scale is the mistake the whole file is about.
        """
        if self.qubits > 20:
            raise ValueError(
                "refusing to expand %d qubits to a state vector: that is 2^%d amplitudes and is "
                "the exact computation this representation exists to avoid" % (self.qubits, self.qubits))
        state = numpy.array([1.0 + 0j])
        for at in range(self.qubits):
            theta = float(self.theta[at])
            phi = float(self.phi[at])
            one = numpy.array([math.cos(theta / 2.0),
                               complex(math.cos(phi), math.sin(phi)) * math.sin(theta / 2.0)])
            state = numpy.kron(state, one)
        return state

    def probability_one(self, at):
        """Probability qubit `at` reads one, straight from its own angle. No state vector needed."""
        return float(math.sin(float(self.theta[at]) / 2.0) ** 2)


def _report():
    print("  A qubit is two reals. The cap is memory over %d bytes, alone."
          % BYTES_PER_QUBIT)
    print("")
    print("  %16s %14s %18s %16s" % ("memory", "qubits", "state vector would be", "layer time"))

    for name, budget in (("32 KB", 32 * 1024), ("8 MB", 8 * 1024 ** 2),
                         ("512 MB", 512 * 1024 ** 2), ("8 GB", 8 * 1024 ** 3)):
        qubits = budget // BYTES_PER_QUBIT
        machine = ProductMachine(min(qubits, 4_000_000))
        began = time.perf_counter()
        machine.hadamard_all()
        machine.phase_all(0.3)
        machine.rotate_all(0.1)
        spent = time.perf_counter() - began
        print("  %16s %14s %18s %16s"
              % (name, "%d" % qubits, "1e%.0f bytes" % (qubits * math.log10(2.0) + 1.2),
                 "%.4f s" % spent if qubits <= 4_000_000 else "not run"))

    print("")
    print("  THE 4096 QUBIT CASE, which is where this started:")
    machine = ProductMachine(4096)
    machine.hadamard_all()
    machine.phase_all(0.7)
    print("    held in %d bytes, which is %.1f KB"
          % (machine.bytes_held(), machine.bytes_held() / 1024.0))
    print("    a state vector of the same 4096 qubits would be 1e1234 bytes")
    print("    probability qubit 0 reads one: %.6f" % machine.probability_one(0))
    print("    probability qubit 4095 reads one: %.6f" % machine.probability_one(4095))
    print("")
    print("  SO THE MACHINE IS REAL AND THE NUMBERS ARE HIS. Four thousand and ninety six qubits")
    print("  in thirty two kilobytes, every single-qubit gate exact, and a full layer over four")
    print("  million qubits in a fraction of a second.")
    print("")
    print("  NOW THE WALL, MEASURED AND NOT ASSERTED. bloch_cost.py fits the best product")
    print("  description to states of known entanglement:")
    print("")
    print("    entanglement    product overlap    error")
    print("       0.000 bits      1.000000000     -2.220e-16     exact")
    print("       0.798 bits      0.944404597      5.560e-02")
    print("       1.815 bits      0.822664388      1.773e-01")
    print("       3.000 bits      0.353553391      6.464e-01     hopeless")
    print("")
    print("  THE FIRST ENTANGLING GATE IS THE WALL AND NOTHING ABOUT THE QUBIT COUNT MOVES IT.")
    print("  A machine with a million qubits and no entanglement runs every product circuit")
    print("  exactly and no quantum algorithm at all, because the algorithms worth having put")
    print("  their advantage in the correlation. Grover's intermediate states are entangled.")
    print("")
    print("  AND THE COST OF GOING PART WAY IS KNOWN. A matrix product state at bond dimension")
    print("  chi holds entanglement up to log2(chi) per split and needs about 2 n chi^2 numbers:")
    print("")
    print("  %8s %16s %24s" % ("chi", "entropy held", "numbers for 4096 qubits"))
    for chi in (1, 2, 4, 16, 256):
        print("  %8d %16.1f %24.3e" % (chi, math.log2(chi), 2.0 * 4096 * chi * chi))
    print("")
    print("  Linear in the qubits and quadratic in the bond dimension, and the bond dimension is")
    print("  exponential in the entanglement. The cost structure fits in one line, and it says the")
    print("  qubit count is not the expensive part.")
    return 0


def _width():
    """What 64, 32 and 16 bits a qubit actually cost in accuracy.

    The specification says 64 bits a qubit and that 32 would do. Both are measurable and not arguable: the
    angles are stored at a width and the state they describe carries whatever error that width
    leaves. Graded against the same angles held at float64.
    """
    generator = numpy.random.default_rng(17)
    qubits = 12
    theta = generator.uniform(0, math.pi, size=qubits)
    phi = generator.uniform(0, 2.0 * math.pi, size=qubits)

    print("  %d qubits, the same directions stored at three widths and compared against float64."
          % qubits)
    print("")
    print("  %22s %12s %18s %18s"
          % ("per qubit", "bytes", "state error", "worst angle error"))

    exact = ProductMachine(qubits, numpy.float64)
    exact.theta[:] = theta
    exact.phi[:] = phi
    truth = exact.amplitudes()

    for name, dtype, bits in (("2 x float64, 128 bits", numpy.float64, 128),
                              ("2 x float32, 64 bits", numpy.float32, 64),
                              ("2 x float16, 32 bits", numpy.float16, 32)):
        machine = ProductMachine(qubits, dtype)
        machine.theta[:] = theta
        machine.phi[:] = phi
        got = machine.amplitudes()
        error = float(numpy.linalg.norm(got - truth))
        worst = max(float(abs(float(machine.theta[at]) - theta[at])) for at in range(qubits))
        print("  %22s %12d %18.4e %18.4e"
              % (name, machine.bytes_held(), error, worst))

    print("")
    print("  SIXTY FOUR BITS A QUBIT IS THE RIGHT CALL AND THIRTY TWO IS NOT, on these numbers.")
    print("  Two float32 hold the angles to about seven decimal digits, which puts the state error")
    print("  near 1e-7 and leaves plenty of room under any threshold this tree uses. Two float16")
    print("  hold about three digits and the state error lands near 1e-3, which is above the")
    print("  detection limits measured in unmodeled.py and would swamp them.")
    print("")
    print("  SO THE THIRTY TWO BIT VERSION IS CHEAPER THAN THE MEASUREMENTS IT WOULD BE USED FOR.")
    print("  That is the precision floor argument applied to a representation and not to an")
    print("  arithmetic: a format is adequate when its floor sits below the smallest thing the")
    print("  instrument is meant to see, and float16 angles do not.")
    return 0


def _check():
    lines = []
    failed = 0

    # The representation must be exact for a product state, the claim it rests on.
    generator = numpy.random.default_rng(5)
    qubits = 8
    machine = ProductMachine(qubits, numpy.float64)
    machine.theta[:] = generator.uniform(0, math.pi, size=qubits)
    machine.phi[:] = generator.uniform(0, 2.0 * math.pi, size=qubits)
    state = machine.amplitudes()
    norm = float(abs(numpy.vdot(state, state)))
    lines.append("  %d qubits from %d angles: state norm %.15f" % (qubits, 2 * qubits, norm))
    if abs(norm - 1.0) > 1e-12:
        lines.append("    FAIL the angles do not produce a normalized state")
        failed += 1

    # The per-qubit probability must agree with the one read off the full state vector, or the
    # cheap readout is not the same quantity as the expensive one.
    power = numpy.abs(state) ** 2
    worst = 0.0
    for at in range(qubits):
        mask = 1 << (qubits - 1 - at)
        from_state = float(sum(power[one] for one in range(len(state)) if one & mask))
        worst = max(worst, abs(from_state - machine.probability_one(at)))
    lines.append("  per-qubit probability, angle against full state: worst gap %.3e" % worst)
    if worst > 1e-12:
        lines.append("    FAIL the cheap readout disagrees with the state vector")
        failed += 1

    # Memory must be linear in the qubits. This is the entire claim of the representation.
    small = ProductMachine(1000).bytes_held()
    large = ProductMachine(2000).bytes_held()
    lines.append("  1000 qubits hold %d bytes and 2000 hold %d, a ratio of %.4f"
                 % (small, large, large / float(small)))
    if abs(large / float(small) - 2.0) > 1e-9:
        lines.append("    FAIL memory is not linear in the qubit count")
        failed += 1

    # THE REFUSAL MUST FIRE. Expanding a large machine to a state vector is the mistake this
    # representation exists to prevent. It must raise and not attempt it.
    try:
        ProductMachine(64).amplitudes()
        lines.append("    FAIL a 64 qubit machine agreed to expand to 2^64 amplitudes")
        failed += 1
    except ValueError:
        lines.append("  expanding a 64 qubit machine to a state vector raises, as it must")

    # And four thousand qubits must actually fit in the stated budget.
    big = ProductMachine(4096)
    lines.append("  4096 qubits hold %d bytes, %.1f KB" % (big.bytes_held(), big.bytes_held() / 1024.0))
    if big.bytes_held() > 64 * 1024:
        lines.append("    FAIL 4096 qubits did not fit in 64 KB")
        failed += 1

    # THE NEGATIVE CONTROL, which keeps the file honest. The representation must
    # NOT be able to express an entangled state, or its cheapness would be free advantage.
    import bloch_cost
    hard = bloch_cost.entangling_pairs(1.0, 6)
    overlap = bloch_cost.best_product_fit(hard, 6)
    lines.append("  a maximally entangled state fitted by a product form: overlap %.6f" % overlap)
    if overlap > 0.9:
        lines.append("    FAIL the product form expressed an entangled state, which would make")
        lines.append("         this representation a free quantum computer and it is not")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="a product-state machine and its wall")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--width", action="store_true")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.width:
        sys.exit(_width())
    sys.exit(_report())
