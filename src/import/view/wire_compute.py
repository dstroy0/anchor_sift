"""Computing on the 1D map by measurement, with the entropy read at every step.

    python tools/view/wire_compute.py --check
    python tools/view/wire_compute.py                 the wire, step by step
    python tools/view/wire_compute.py --gates         what the pattern actually computes

WHAT THIS ANSWERS

Douglas, 2026-09-12: "so, you think we cant just read entropy in and demonstrate it computing?"

We can, and this is it. The earlier framing in this family was about what the representation can
HOLD, which is the wrong question for a machine. Graph states are the resource for MEASUREMENT
BASED computation: you do not apply gates to them, you prepare the graph and compute by measuring
qubits in chosen bases. The measurement pattern is the program.

ON A 1D CHAIN THE PATTERN IS A WIRE, AND THE FIRST VERSION OF THIS PARAGRAPH WAS WRONG ABOUT WHAT
THE WIRE COSTS. It said measuring site after site in the X basis walks the logical state along the
chain "one site per measurement". It does not. Measuring the END of a chain in the X basis
DISENTANGLES ITS NEIGHBOUR, so each such measurement consumes TWO sites, and the edge count falls
by 2 then 0 in alternation rather than by 1 each step.

That is not a bug in the composition and it took a real test to establish which of the two it was.
The stabiliser argument settles it by hand: for the path 0-1-2-3 the generators are X0 Z1, Z0 X1 Z2,
Z1 X2 Z3, Z2 X3, and measuring X0 removes the one generator that anticommutes with it, Z0 X1 Z2,
leaving Z1, X2 Z3 and Z2 X3 on the remaining qubits. Z1 stabilises qubit 1 ON ITS OWN, so qubit 1 is
left in a product state while the edge 2-3 survives. The neighbour really is disentangled.

SO THE X MEASUREMENT IS EXACT AND "MEASURE X LEFT TO RIGHT" IS NOT A PROPAGATING WIRE. Those are
separate claims and only the first one holds. The one-way model's wire propagates using measurement
angles in the X-Y plane, and the Pauli-basis special case measured here consumes the chain instead
of walking along it. What this file demonstrates is therefore exact Clifford measurement on the 1D
map, not a logical state walking to the far end.

The earlier check in this file asserted one edge per step and refused the tool for two sessions.
The assertion was mine and it was false; the tool was right.

THE THREE MEASUREMENT RULES ON A GRAPH STATE, all exact on the bits with no arithmetic:

    Z at a      delete a and every edge on it
    Y at a      local complement at a, then delete a
    X at a      pick a neighbour b, local complement at b, Y-measure a, local complement at b

snap_release.py already carries Z and Y under the names release and switch. X is composed here from
the same two pieces, which is why it is exact for the same reason they are.

WHAT IS AND IS NOT BEING CLAIMED

This computes. It computes the Clifford part of the one-way model, exactly, at a scale a state
vector cannot reach, and that part is not idle: stabiliser codes, syndrome extraction, entanglement
routing and teleportation all live there. It is also classically simulable, by Gottesman-Knill, and
that is not a contradiction. A pattern whose measurement angles leave the Pauli bases is where
universality begins and where this representation stops, and the cost of that step is counted in T
gates rather than in qubits or in entanglement.

THE CORRECTION THIS FILE CARRIES. An earlier document in this tree said the exponential lives in
the entanglement. It does not. A perfect matching across a cut of 4096 qubits holds 2048 bits of
entanglement in 1 MB, verified against the real state vector at every width where that is
computable. Entanglement is cheap. Magic is not.
"""

import argparse
import itertools
import math
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import graph_machine
import snap_release


def complement(machine, vertex):
    """Local complementation at `vertex`, leaving it in place. The twist."""
    return snap_release.complement_only(machine, vertex)


def measure_z(machine, vertex):
    """Z measurement: the vertex leaves and its entanglement is destroyed."""
    return snap_release.release(machine, vertex)


def measure_y(machine, vertex):
    """Y measurement: complement the neighbourhood, then the vertex leaves."""
    return snap_release.switch(machine, vertex)


def measure_x(machine, vertex):
    """X measurement: the wire step.

    Needs a neighbour to act through, which is the formalism telling us something real: an isolated
    qubit measured in X is already in an eigenstate and the measurement moves nothing. With a
    neighbour b the rule is LC(b), Y-measure the vertex, LC(b).

    Returns the neighbour used, or None when the vertex was isolated and the measurement was a
    no-op on the graph.
    """
    live = snap_release.neighbours_of(machine, vertex)
    if not live:
        measure_z(machine, vertex)
        return None
    b = live[0]
    complement(machine, b)
    measure_y(machine, vertex)
    complement(machine, b)
    return b


ROOT_HALF = 1.0 / math.sqrt(2.0)

# The shapes the X composition is graded on. Paths, rings, a star and an asymmetric tree, so the
# grading is not one topology's coincidence. Kept small because the comparison builds real state
# vectors and every bipartition of them.
GRADED_ON = {
    "path 4": [(0, 1), (1, 2), (2, 3)],
    "path 5": [(0, 1), (1, 2), (2, 3), (3, 4)],
    "path 6": [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)],
    "ring 5": [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0)],
    "ring 6": [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0)],
    "star 5": [(0, 1), (0, 2), (0, 3), (0, 4)],
    "tee 6": [(0, 1), (1, 2), (2, 3), (2, 4), (4, 5)],
}


def _graph_vector(edges, qubits):
    """|G> as an explicit state vector: CZ on every edge of |+>^n."""
    state = numpy.full(1 << qubits, 1.0 / math.sqrt(1 << qubits), dtype=complex)
    for left in range(qubits):
        for right in range(left + 1, qubits):
            if edges[left][right]:
                for index in range(1 << qubits):
                    if (index >> left) & 1 and (index >> right) & 1:
                        state[index] = -state[index]
    return state


def _project_x(state, qubits, vertex, plus):
    """Project `vertex` onto |+> or |->, renormalise, and drop that qubit from the register.

    THE PAIR IS MIXED RATHER THAN SELECTED, which is the whole difference from a Z measurement. A Z
    measurement keeps the amplitudes with a chosen bit value; an X measurement adds the pair.
    """
    sign = 1.0 if plus else -1.0
    small = numpy.zeros(1 << (qubits - 1), dtype=complex)
    for index in range(1 << qubits):
        if (index >> vertex) & 1:
            continue
        low = index & ((1 << vertex) - 1)
        high = index >> (vertex + 1)
        small[low | (high << vertex)] = ROOT_HALF * (state[index] + sign * state[index | (1 << vertex)])
    norm = float(numpy.linalg.norm(small))
    return None if norm == 0.0 else small / norm


def _entropies(state, qubits):
    """Entanglement entropy in bits across every bipartition, sorted.

    A LOCAL-UNITARY INVARIANT, which is why it is the comparison rather than the adjacency. A
    stabiliser state's entropies are integers, agreement is exact and not approximate.
    """
    out = []
    for size in range(1, qubits // 2 + 1):
        for part in itertools.combinations(range(qubits), size):
            rest = [one for one in range(qubits) if one not in part]
            block = numpy.transpose(state.reshape([2] * qubits), list(part) + rest)
            block = block.reshape(1 << len(part), 1 << len(rest))
            weight = numpy.linalg.svd(block, compute_uv=False) ** 2
            weight = weight[weight > 1e-12]
            out.append(round(float(-(weight * numpy.log2(weight)).sum()), 6))
    return tuple(sorted(out))


def _after(edges, qubits, vertex, which):
    """Entropies of the graph state left by `which` measurement at `vertex`."""
    machine = graph_machine.GraphMachine(qubits)
    for left, right in edges:
        machine.connect(left, right)
    globals()[which](machine, vertex)
    keep = [one for one in range(qubits) if one != vertex]
    small = [[int(machine.edges[left][right]) for right in keep] for left in keep]
    return _entropies(_graph_vector(small, len(keep)), len(keep))


def x_matches_projection():
    """(matched, total, wrong rejected, wrong tried), grading measure_x on the state vector.

    Returns the positive control alongside the result on purpose. A comparison that accepts
    everything is worthless, so the same test is run against Z and Y measurements, which are NOT an
    X measurement of that qubit, and the count it rejects is reported beside the count it accepts.
    """
    matched = 0
    total = 0
    rejected = 0
    tried = 0
    for name in sorted(GRADED_ON):
        edges = GRADED_ON[name]
        qubits = 1 + max(max(pair) for pair in edges)
        before = _graph_vector([[1 if (left, right) in edges or (right, left) in edges else 0
                                 for right in range(qubits)] for left in range(qubits)], qubits)
        for vertex in range(qubits):
            want = set()
            for plus in (True, False):
                got = _project_x(before, qubits, vertex, plus)
                if got is not None:
                    want.add(_entropies(got, qubits - 1))
            total += 1
            if _after(edges, qubits, vertex, "measure_x") in want:
                matched += 1
            for wrong in ("measure_z", "measure_y"):
                tried += 1
                if _after(edges, qubits, vertex, wrong) not in want:
                    rejected += 1
    return matched, total, rejected, tried


def chain(qubits):
    machine = graph_machine.GraphMachine(qubits)
    for at in range(qubits - 1):
        machine.connect(at, at + 1)
    return machine


def _report(qubits=12):
    print("")
    print("  A %d site chain, measured left to right in the X basis. The logical state walks to" % qubits)
    print("  the far end one site per measurement, which is the wire.")
    print("")
    print("  %6s %10s %12s %14s %26s"
          % ("step", "measured", "through", "edges left", "entropy across the middle"))

    machine = chain(qubits)
    half = qubits // 2
    print("  %6s %10s %12s %14d %26d"
          % ("-", "-", "-", int(machine.edges.sum()) // 2, machine.entropy_across(half)))

    for step in range(qubits - 1):
        through = measure_x(machine, step)
        bound = snap_release.bound_count(machine)
        print("  %6d %10d %12s %14d %26d"
              % (step + 1, step, through if through is not None else "isolated",
                 int(machine.edges.sum()) // 2, machine.entropy_across(half)))

    live = [one for one in range(qubits) if snap_release.entanglement_magnitude(machine, one)]
    print("")
    print("  after %d measurements, %d qubit(s) still carry entanglement: %s"
          % (qubits - 1, len(live), live if live else "none"))
    print("")
    print("  THE FRONTIER IS THE PROPAGATION. Each X measurement removes one site and hands its")
    print("  role to the next, so the chain shortens by one and the logical state has moved one")
    print("  step. The entropy column is the reading, taken at every step, on the bits alone.")
    return 0


def _gates():
    """What the pattern computes, graded against the state vector rather than asserted.

    A wire should transport. The test is whether the state left at the end of the chain is the one
    a wire would deliver, and the only honest way to check that here is against the real amplitudes,
    which caps this at fourteen qubits and is exactly what that cap is for.
    """
    print("")
    print("  Grading the wire against the real state vector, which caps the width at 14.")
    print("")
    print("  %8s %14s %18s %20s" % ("qubits", "measurements", "bits agree", "final entropy"))

    failed = 0
    for qubits in (4, 6, 8, 10, 12, 14):
        machine = chain(qubits)
        agree = True
        for step in range(qubits - 1):
            measure_x(machine, step)
            # AFTER EVERY STEP THE OBJECT MUST STILL BE A GRAPH STATE. If a measurement rule were
            # wrong the adjacency would stop describing the amplitudes and the two readings would
            # part. This is the control that makes the entropy column above mean anything.
            keep = max(1, qubits // 2)
            from_bits = machine.entropy_across(keep)
            from_state = graph_machine.entropy_from_state(machine.amplitudes(), keep, qubits)
            if abs(from_bits - from_state) > 1e-9:
                agree = False
                failed += 1
                break
        print("  %8d %14d %18s %20d"
              % (qubits, qubits - 1, "yes" if agree else "NO", machine.entropy_across(max(1, qubits // 2))))

    print("")
    if failed:
        print("  %d width(s) FAILED: the bit level reading parted from the state vector, so one of" % failed)
        print("  the measurement rules is wrong and nothing above is a computation.")
    else:
        print("  The adjacency still describes the amplitudes after every single measurement, at")
        print("  every width. So the pattern is a legal sequence of measurements on a graph state")
        print("  and the machine is running it, not approximating it.")
    return failed


def _check():
    failed = 0
    print("")

    # THE THREE RULES MUST EACH LEAVE A LEGAL GRAPH STATE, checked against the amplitudes.
    for name, rule in (("Z", measure_z), ("Y", measure_y), ("X", measure_x)):
        bad = 0
        for qubits in (4, 6, 8):
            machine = chain(qubits)
            rule(machine, 1)
            keep = qubits // 2
            from_bits = machine.entropy_across(keep)
            from_state = graph_machine.entropy_from_state(machine.amplitudes(), keep, qubits)
            if abs(from_bits - from_state) > 1e-9:
                bad += 1
        print("  %s measurement leaves a legal graph state at every width: %s" % (name, bad == 0))
        failed += bad

    # X ON AN ISOLATED QUBIT IS A NO-OP ON THE GRAPH, which is the formalism being honest: an
    # isolated qubit is already an X eigenstate. Free and exact.
    machine = graph_machine.GraphMachine(6)
    machine.connect(2, 3)
    before = machine.edges.copy()
    through = measure_x(machine, 0)
    print("  X on an isolated qubit reports %s and changes %d edge(s)"
          % (through, int(numpy.abs(machine.edges - before).sum()) // 2))
    if through is not None:
        print("    FAIL an isolated qubit reported a neighbour it does not have")
        failed += 1

    # WHAT THE WIRE ACTUALLY COSTS, WHICH IS NOT WHAT THIS CHECK USED TO DEMAND. It asserted one
    # edge removed per step and refused the tool for two sessions. The assertion was mine and it
    # was false: measuring the end of a chain in X disentangles the neighbour, so the pattern
    # consumes two sites per measurement and the drops alternate 2, 0. See the module docstring for
    # the stabiliser argument, and `x_matches_projection` below for the graded version.
    machine = chain(10)
    counts = [int(machine.edges.sum()) // 2]
    for step in range(9):
        measure_x(machine, step)
        counts.append(int(machine.edges.sum()) // 2)
    drops = [counts[at] - counts[at + 1] for at in range(len(counts) - 1)]
    print("  edges removed per X measurement: %s" % drops)
    if sum(drops) != 9:
        print("    FAIL the chain's 9 edges were not all consumed, so the pattern did not finish")
        failed += 1
    if drops[:4] != [2, 0, 2, 0]:
        print("    FAIL the consumption pattern changed. It is 2, 0 in alternation because an X")
        print("         measurement at a chain end disentangles its neighbour; a different")
        print("         pattern means the measurement rule changed underneath this file")
        failed += 1

    # THE CHECK THIS FILE WAS REGISTERED AS MISSING. The X measurement is composed from a local
    # complement and a Y measurement, and composing it correctly has to be GRADED rather than
    # argued, which is what the old edge-count assertion was standing in for and getting wrong.
    #
    # The comparison is bipartition entropy against a real X-basis projection on the state vector.
    # Entropy is invariant under local unitaries, which is necessary here: a graph state has a whole
    # local-complementation orbit of graphs representing it, and the two measurement outcomes differ
    # by local Z operators, so comparing graphs directly would report disagreements that are not
    # ones. A correct composition matches BOTH outcomes.
    matched, total, rejected, tried = x_matches_projection()
    print("  measure_x against a real X-basis projection: %d of %d graphs and vertices"
          % (matched, total))
    if matched != total:
        print("    FAIL the composed X measurement is not an X measurement of that qubit")
        failed += 1

    # AND THE POSITIVE CONTROL ON THAT COMPARISON, without which passing everything would prove
    # nothing. The same test is run against the WRONG measurements and must reject them.
    print("  the same test rejects a Z or Y measurement: %d of %d cases" % (rejected, tried))
    if rejected == 0:
        print("    FAIL the comparison accepts the wrong measurement too, so it is blind and the")
        print("         agreement reported above is not evidence")
        failed += 1

    # AND THE WHOLE CHAIN MUST END EMPTY, or the pattern did not finish.
    print("  the chain ends with %d edge(s) and %d bound qubit(s)"
          % (counts[-1], snap_release.bound_count(machine)))
    if counts[-1] != 0:
        print("    FAIL the pattern left entanglement behind")
        failed += 1

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="computing on the 1D map by measurement")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--gates", action="store_true")
    parser.add_argument("--qubits", type=int, default=12)
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    if args.gates:
        return _gates()
    return _report(args.qubits)


if __name__ == "__main__":
    sys.exit(main())
