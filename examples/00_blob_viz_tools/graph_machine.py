"""Entanglement as a binary vector: a graph-state machine at one bit per pair.

    python examples/00_blob_viz_tools/graph_machine.py --check
    python examples/00_blob_viz_tools/graph_machine.py             the machine, its scale and its wall
    python examples/00_blob_viz_tools/graph_machine.py --shapes    entanglement of different graph shapes

A BINARY MAGNITUDE BETWEEN PAIRS

A third and fourth term per qubit, a polarization and an entanglement vector, does not hold
entanglement (below). A vector and magnitude of entanglement with the magnitude one or zero does,
and it is a known formalism. An entanglement magnitude that is binary between each pair IS AN ADJACENCY MATRIX,
and a state specified by which pairs are connected is a GRAPH STATE:

    |G> = product over edges (i,j) of CZ_ij applied to |+> on every qubit

One bit per pair. n(n-1)/2 bits for n qubits. 4096 qubits is about a megabyte, and the states it
covers are genuinely entangled: Bell pairs, GHZ, cluster states, the whole graph-state family.

WHY THIS BEATS THE FOUR TERM VERSION

Four reals a qubit is 4n numbers and covers two qubits exactly, failing from three, because 4n is
linear and the state space is exponential. One bit per PAIR is n(n-1)/2, which is quadratic, and it
buys a class of states that is exponentially large and maximally entangled and not a fixed
handful.

AND THE ENTANGLEMENT IS READABLE WITHOUT BUILDING THE STATE

The entropy across any split of a graph state is the rank over GF(2) of the adjacency block between
the two halves. So the correlation is read off the bits directly, in the same spirit as the product
machine reading a probability off one angle: no amplitude array anywhere.

THE WALL, WRITTEN ON IT THE WAY THE PRODUCT MACHINE'S IS

Graph states are stabilizer states, and stabilizer states are efficiently classically simulable by
Gottesman and Knill, and that makes them cheap to hold. So this machine holds real
entanglement, at real scale, with no quantum advantage, and the two facts are the same fact for the
fourth time in this family.

What graph states ARE the substrate of is measurement-based quantum computing, where a cluster state
plus ADAPTIVE NON-CLIFFORD MEASUREMENT is universal. The universality lives in the measurement
schedule and not in the state. The cost returns there instead of being avoided.
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy


class GraphMachine(object):
    """n qubits, entanglement held as one bit per pair.

    The adjacency is the state. There is no amplitude array, and so the cost is quadratic in
    the qubit count and not exponential.
    """

    def __init__(self, qubits):
        self.qubits = qubits
        self.edges = numpy.zeros((qubits, qubits), dtype=numpy.uint8)

    def bits_held(self):
        """One bit per unordered pair: what the adjacency actually carries."""
        return self.qubits * (self.qubits - 1) // 2

    def connect(self, one, two):
        if one == two:
            raise ValueError("a qubit cannot be entangled with itself, and the diagonal of an "
                             "adjacency matrix is not an entanglement magnitude")
        self.edges[one, two] = 1
        self.edges[two, one] = 1

    def star(self):
        """Every qubit joined to qubit zero. This is the GHZ state up to local gates."""
        for at in range(1, self.qubits):
            self.connect(0, at)

    def line(self):
        """A chain: the one dimensional cluster state, the substrate for measurement-based
        computing."""
        for at in range(self.qubits - 1):
            self.connect(at, at + 1)

    def ring(self):
        self.line()
        if self.qubits > 2:
            self.connect(self.qubits - 1, 0)

    def complete(self):
        for one in range(self.qubits):
            for two in range(one + 1, self.qubits):
                self.connect(one, two)

    def grid(self, width):
        """A two dimensional cluster state, the universal substrate."""
        for at in range(self.qubits):
            row, column = divmod(at, width)
            if column + 1 < width and at + 1 < self.qubits:
                self.connect(at, at + 1)
            if at + width < self.qubits:
                self.connect(at, at + width)
            del row

    def grid3d(self, width, height):
        """A three dimensional cluster, since the two dimensional one won at twelve qubits."""
        for at in range(self.qubits):
            if (at % width) + 1 < width and at + 1 < self.qubits:
                self.connect(at, at + 1)
            if ((at // width) % height) + 1 < height and at + width < self.qubits:
                self.connect(at, at + width)
            if at + width * height < self.qubits:
                self.connect(at, at + width * height)

    def fibonacci(self):
        """Connect each qubit to the ones a Fibonacci number away.

        The Fibonacci offsets are the integer face of the golden ratio. This is the discrete
        version of the placement that wins on spread everywhere else in this tree.
        """
        offsets = []
        one, two = 1, 2
        while one < self.qubits:
            offsets.append(one)
            one, two = two, one + two
        for at in range(self.qubits):
            for step in offsets:
                if at + step < self.qubits:
                    self.connect(at, at + step)

    def euler_offsets(self):
        """Connect by offsets taken from the continued fraction expansion of e.

        e = [2; 1, 2, 1, 1, 4, 1, 1, 6, 1, 1, 8, ...], whose terms are a known pattern and not a
        draw. This is a deterministic irrational-flavored connection rule and not a random one.
        """
        terms = [2, 1, 2, 1, 1, 4, 1, 1, 6, 1, 1, 8, 1, 1, 10, 1, 1, 12]
        running = 0
        offsets = []
        for term in terms:
            running += term
            if running < self.qubits:
                offsets.append(running)
        for at in range(self.qubits):
            for step in offsets:
                if at + step < self.qubits:
                    self.connect(at, at + step)

    def golden_sphere(self, neighbors=4):
        """Place the qubits on a sphere by the golden placement and join each to its nearest.

        This is the spherical shape, and the placement is the same Fibonacci sphere every reading in
        this tree uses. Nearest by angle. The geometry dictates the graph and no hand chooses it.
        """
        import boundary_read
        points = boundary_read.golden_place(self.qubits)
        for at, point in enumerate(points):
            scored = []
            for other, two in enumerate(points):
                if other == at:
                    continue
                dot = sum(a * b for a, b in zip(point, two))
                scored.append((dot, other))
            scored.sort(reverse=True)
            for _dot, other in scored[:neighbors]:
                self.connect(at, other)

    def random_edges(self, count, seed=0):
        """A matched-count random graph, the control every shape is read against."""
        generator = numpy.random.default_rng(seed)
        placed = 0
        guard = 0
        while placed < count and guard < count * 200:
            one = int(generator.integers(0, self.qubits))
            two = int(generator.integers(0, self.qubits))
            guard += 1
            if one != two and not self.edges[one, two]:
                self.connect(one, two)
                placed += 1

    def entropy_across(self, keep):
        """Entanglement entropy in bits across the split, from the adjacency alone.

        For a graph state the entropy across a bipartition is the rank over GF(2) of the off
        diagonal block of the adjacency matrix. So this is read off the bits and never from a state
        vector. The representation exists for that.
        """
        block = self.edges[:keep, keep:].copy() % 2
        return int(gf2_rank(block))

    def amplitudes(self):
        """The state vector, ONLY so small cases can be graded against the bit-level answer."""
        if self.qubits > 14:
            raise ValueError(
                "refusing to expand %d qubits: that is 2^%d amplitudes and is the computation this "
                "representation exists to avoid" % (self.qubits, self.qubits))
        width = 1 << self.qubits
        state = numpy.full(width, 1.0 / math.sqrt(width), dtype=complex)
        for one in range(self.qubits):
            for two in range(one + 1, self.qubits):
                if self.edges[one, two]:
                    for at in range(width):
                        if (at >> one) & 1 and (at >> two) & 1:
                            state[at] = -state[at]
        return state


def gf2_rank(block):
    """Rank of a binary matrix over GF(2), by elimination in the field the entropy lives in.

    Ordinary numerical rank is the wrong tool: these entries are bits and the arithmetic is modulo
    two, a real-valued elimination would report a different number for a matrix that is singular
    over GF(2) and not over the reals.
    """
    work = block.copy() % 2
    rows, columns = work.shape
    rank = 0
    row = 0
    for column in range(columns):
        pivot = None
        for at in range(row, rows):
            if work[at, column]:
                pivot = at
                break
        if pivot is None:
            continue
        work[[row, pivot]] = work[[pivot, row]]
        for at in range(rows):
            if at != row and work[at, column]:
                work[at] = (work[at] + work[row]) % 2
        row += 1
        rank += 1
        if row == rows:
            break
    return rank


def entropy_from_state(state, keep, qubits):
    """Entanglement entropy from the amplitude array, for grading the bit-level answer."""
    kept = 1 << keep
    rest = 1 << (qubits - keep)
    block = state.reshape(kept, rest)
    values = numpy.linalg.svd(block, compute_uv=False)
    power = values ** 2
    power = power[power > 1e-14]
    return -float(sum(one * math.log2(one) for one in power))


def _report():
    print("  Entanglement as one bit per pair. The cost is n(n-1)/2 bits, quadratic in the qubit")
    print("  count, and the states covered are genuinely entangled.")
    print("")
    print("  %10s %16s %16s %22s"
          % ("qubits", "pairs", "adjacency", "state vector would be"))
    for qubits in (8, 64, 4096, 65536):
        machine = GraphMachine(min(qubits, 4096))
        bits = qubits * (qubits - 1) // 2
        print("  %10d %16s %16s %22s"
              % (qubits, "%d" % bits, "%.1f MB" % (bits / 8.0 / 1024.0 / 1024.0),
                 "1e%.0f bytes" % (qubits * math.log10(2.0) + 1.2)))
        del machine

    print("")
    print("  THE 4096 QUBIT CASE, which is where this thread started:")
    bits = 4096 * 4095 // 2
    print("    a complete graph on 4096 qubits needs %d bits, %.2f MB"
          % (bits, bits / 8.0 / 1024.0 / 1024.0))
    print("    a cluster state on 4096 qubits needs %d edges, %.1f KB"
          % (4095, 4095 / 8.0 / 1024.0))
    print("    the state vector of either would be 1e1234 bytes")
    print("")
    print("  AND THE ENTANGLEMENT IS READ OFF THE BITS. For a graph state the entropy across a")
    print("  split is the GF(2) rank of the adjacency block between the halves. No amplitude")
    print("  array is built to find it. A large machine reports its own correlation structure.")
    print("")

    for qubits, name in ((12, "star, which is GHZ up to local gates"),
                         (12, "line, the cluster state"),
                         (12, "complete graph")):
        machine = GraphMachine(qubits)
        if name.startswith("star"):
            machine.star()
        elif name.startswith("line"):
            machine.line()
        else:
            machine.complete()
        half = qubits // 2
        print("    %-38s entropy across the half split: %d bits"
              % (name, machine.entropy_across(half)))

    print("")
    print("  SO THE MACHINE HOLDS REAL ENTANGLEMENT AT REAL SCALE, which the product machine could")
    print("  not do at any size. A binary entanglement magnitude between pairs is an adjacency")
    print("  matrix, and a state")
    print("  specified that way is a graph state.")
    print("")
    print("  THE WALL, AND IT IS THE SAME WALL. Graph states are stabilizer states and stabilizer")
    print("  states are efficiently classically simulable by Gottesman and Knill, and that makes")
    print("  them cheap to hold. Real entanglement, real scale, no quantum advantage, and")
    print("  those are one fact and not three.")
    print("")
    print("  WHERE THE ADVANTAGE ACTUALLY SITS IN THIS FORMALISM, since graph states are not a")
    print("  dead end. A two dimensional cluster state plus ADAPTIVE NON-CLIFFORD MEASUREMENT is")
    print("  universal for quantum computing. The state is cheap and the universality lives in the")
    print("  measurement schedule. The cost returns in the measurements instead of being")
    print("  avoided. That is worth knowing precisely because it says which half to look at.")
    return 0


def _shapes():
    """Entanglement of different graph shapes, the field-shape question made concrete."""
    print("  Which field shape is the most efficient config? For a graph state the shape IS the")
    print("  adjacency. The question is then exact and not vague: which shapes buy the most")
    print("  entanglement per bit spent.")
    print("")
    qubits = 64
    half = qubits // 2
    print("  %d qubits, split %d against %d. The entropy ceiling is %d bits for ANY shape."
          % (qubits, half, half, half))
    print("")
    print("  %-18s %10s %14s %16s %14s"
          % ("shape", "edges", "entropy", "per edge", "of ceiling"))

    builders = (
        ("star", lambda m: m.star()),
        ("line, 1D cluster", lambda m: m.line()),
        ("ring", lambda m: m.ring()),
        ("grid 8x8, 2D", lambda m: m.grid(8)),
        ("grid 4x4x4, 3D", lambda m: m.grid3d(4, 4)),
        ("fibonacci offsets", lambda m: m.fibonacci()),
        ("euler offsets", lambda m: m.euler_offsets()),
        ("golden sphere, k=4", lambda m: m.golden_sphere(4)),
        ("golden sphere, k=8", lambda m: m.golden_sphere(8)),
        ("complete", lambda m: m.complete()),
    )

    rows = []
    for name, build in builders:
        machine = GraphMachine(qubits)
        build(machine)
        edges = int(machine.edges.sum() // 2)
        entropy = machine.entropy_across(half)
        rows.append((name, edges, entropy))
        print("  %-18s %10d %14d %16.4f %13.1f%%"
              % (name, edges, entropy, entropy / float(edges) if edges else 0.0,
                 100.0 * entropy / float(half)))

    print("")
    print("  AND THE CONTROL, at each shape's own edge count. Spread is separated from count:")
    print("")
    print("  %-18s %10s %14s %16s" % ("matched random", "edges", "entropy", "per edge"))
    for name, edges, entropy in rows:
        if edges == 0 or edges > qubits * (qubits - 1) // 2:
            continue
        machine = GraphMachine(qubits)
        machine.random_edges(edges, seed=len(name))
        got = machine.entropy_across(half)
        print("  %-18s %10d %14d %16.4f"
              % ("random, %d edges" % edges, edges, got,
                 got / float(edges) if edges else 0.0))

    print("")
    print("  RANDOM BEATS EVERY STRUCTURED SHAPE, DECISIVELY. At 63 edges a random graph reaches 19")
    print("  bits where the line reaches 1, three times the best structured shape per edge, and it")
    print("  beats the two dimensional grid using forty four percent fewer edges.")
    print("")
    print("  THE REASON IS EXACT. The entropy here IS the GF(2) rank of the adjacency block, and a")
    print("  random binary matrix has near full rank with high probability while a regular one is")
    print("  rank deficient by construction. Disorder maximizes rank. Disorder maximizes")
    print("  entanglement per edge. A complete graph is the extreme case in the other direction:")
    print("  its off-diagonal block is all ones, GF(2) rank ONE. It buys a single bit however")
    print("  large n is, from n(n-1)/2 edges.")
    print("")
    print("  THE TABLE IS THE FINDING AND THE SENTENCE IS A GUESS UNTIL IT MATCHES. The grid wins")
    print("  at twelve qubits and not at sixty four, and neither the star nor the line is best.")
    print("")
    print("  AND THIS INVERTS THE PLACEMENT RESULT. For CONDITIONING")
    print("  of a boundary reading, the golden placement beats random by 42 against 2174. For")
    print("  ENTANGLEMENT PER EDGE, random beats every structured shape. Same tree, opposite")
    print("  optima, because conditioning wants even coverage and GF(2) rank wants disorder. Those")
    print("  are two different objectives.")
    print("")
    print("  THE EMBEDDING DOES NOT ENTER AT ALL, which settles the spherical and oblate questions")
    print("  without measuring them. A graph state depends only on WHICH PAIRS are connected, not")
    print("  on where the qubits sit, a shape in space matters only if the adjacency is DERIVED")
    print("  from proximity. The golden sphere rows derive it that way, and proximity graphs are")
    print("  structured, hence rank deficient, hence inefficient: the sphere lands at 0.0963")
    print("  against random's 0.3016. An oblate spheroid would be another proximity graph and")
    print("  would lose the same way, and so would any wave function used as a density, unless the")
    print("  adjacency it produced were disordered and not smooth.")
    print("")
    print("  AND THE CEILING IS THE SMALLER HALF, in bits, for any shape whatsoever. Entropy across")
    print("  a split of k qubits against the rest cannot exceed k. No amount of connection")
    print("  passes it. That is the same counting bound as the rank ceiling: the reading cannot")
    print("  carry more than the thing being read.")
    return 0


def _check():
    lines = []
    failed = 0

    # THE BIT LEVEL ENTROPY MUST AGREE WITH THE STATE VECTOR, or the cheap readout is not the same
    # quantity as the expensive one and every large number this file prints is unfounded.
    worst = 0.0
    for qubits, shape in ((6, "star"), (6, "line"), (8, "line"), (8, "complete"), (10, "ring")):
        machine = GraphMachine(qubits)
        getattr(machine, shape)()
        half = qubits // 2
        from_bits = machine.entropy_across(half)
        from_state = entropy_from_state(machine.amplitudes(), half, qubits)
        worst = max(worst, abs(from_bits - from_state))
        lines.append("  %-9s %2d qubits: entropy from bits %d, from the state vector %.9f"
                     % (shape, qubits, from_bits, from_state))
    if worst > 1e-6:
        lines.append("    FAIL the GF(2) rank disagrees with the state vector's entropy, so the")
        lines.append("         bit-level readout is not measuring entanglement")
        failed += 1

    # A GRAPH WITH NO EDGES MUST HAVE ZERO ENTROPY. That is the product state, and it is the
    # negative control: if an empty graph read as entangled the measure would be meaningless.
    empty = GraphMachine(8)
    lines.append("  a graph with no edges: entropy %d bits" % empty.entropy_across(4))
    if empty.entropy_across(4) != 0:
        lines.append("    FAIL an unentangled state read as entangled")
        failed += 1

    # THE POSITIVE CONTROL. A Bell pair must read exactly one bit.
    bell = GraphMachine(2)
    bell.connect(0, 1)
    lines.append("  a Bell pair: entropy %d bit" % bell.entropy_across(1))
    if bell.entropy_across(1) != 1:
        lines.append("    FAIL a Bell pair is not reading as one bit of entanglement")
        failed += 1

    # The GF(2) rank must differ from the real-valued rank somewhere, or using it was pointless and
    # the file should say so instead of carrying a special routine.
    block = numpy.array([[1, 1, 0], [1, 0, 1], [0, 1, 1]], dtype=numpy.uint8)
    over_two = gf2_rank(block)
    over_reals = int(numpy.linalg.matrix_rank(block.astype(float)))
    lines.append("  a matrix with GF(2) rank %d and real rank %d, so the field matters"
                 % (over_two, over_reals))
    if over_two == over_reals:
        lines.append("    NOTE this example does not separate the two fields; the routine is still")
        lines.append("         correct but the demonstration is not showing why it is needed")

    # Cost must be quadratic and not exponential, the claim of the representation.
    small = GraphMachine(100).bits_held()
    large = GraphMachine(200).bits_held()
    lines.append("  100 qubits need %d bits and 200 need %d, a ratio of %.3f"
                 % (small, large, large / float(small)))
    if not 3.8 < large / float(small) < 4.2:
        lines.append("    FAIL the cost is not quadratic in the qubit count")
        failed += 1

    # The refusal must fire instead of attempting an exponential expansion.
    try:
        GraphMachine(40).amplitudes()
        lines.append("    FAIL a 40 qubit machine agreed to expand to 2^40 amplitudes")
        failed += 1
    except ValueError:
        lines.append("  expanding a 40 qubit machine raises, as it must")

    # And the entropy can never exceed the smaller half, for any shape. A counting bound.
    over = []
    for shape in ("star", "line", "ring", "complete"):
        machine = GraphMachine(10)
        getattr(machine, shape)()
        if machine.entropy_across(5) > 5:
            over.append(shape)
    lines.append("  entropy never exceeds the smaller half, across four shapes: %s"
                 % ("yes" if not over else "NO at %s" % over))
    if over:
        lines.append("    FAIL entropy passed the counting bound, which is impossible")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="entanglement as one bit per pair")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--shapes", action="store_true")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.shapes:
        sys.exit(_shapes())
    sys.exit(_report())
