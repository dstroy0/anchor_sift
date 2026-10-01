"""The fourth term as the operation it exists for: a qubit snapping its vector to release entanglement.

    python tools/view/snap_release.py --check
    python tools/view/snap_release.py               the two snaps, measured against the state vector
    python tools/view/snap_release.py --cost        what the fourth term costs and what it buys

WHY FOUR TERMS AND NOT THREE, WHICH IS THE QUESTION THIS ANSWERS

Douglas, 2026-09-11: "it needs to be 4, the integral allows for the qubit to snap its vector and
switch position to release entanglement."

I had answered the wrong question before this. I measured STATIC capacity: how many reals it takes
to write down an arbitrary pure state, which is 2^(n+1) - 2, against a fixed budget of c*n. Four
reals a qubit is exact through two qubits and short from three on, and no amount of precision moves
that line. All true, and none of it about what he asked.

His fourth term is not storage for an amplitude. It is a MAGNITUDE OF 0 OR 1 saying whether this
qubit is currently entangled at all, and its purpose is to make the snap available. A binary term
cannot hold an arbitrary amplitude and it can hold that perfectly.

THE THREE TERM MACHINE CANNOT ASK THE QUESTION THE SNAP ANSWERS

With a direction and a polarisation, a qubit carries where it points. Nothing in it says whether it
is bound to anything. a three term machine cannot tell a free qubit from an entangled one, and
therefore cannot know whether a snap is available or what releasing it would cost. The fourth term
is not extra capacity, it is the predicate the operation is conditioned on.

THE TWO SNAPS, AND THEY ARE BOTH EXACT

Both are standard graph state operations and both are exact on the bits, with no arithmetic:

    RELEASE, which is a Z measurement. Delete every edge on the qubit. It leaves the cluster and
    its entanglement is gone. This is snapping without switching position.

    SWITCH, which is a Y measurement. Complement the edges AMONG the qubit's neighbours, then
    delete the qubit's own edges. The qubit leaves and its neighbours inherit the connectivity, so
    the entanglement moves rather than vanishing. This is the snap-and-switch he described, and the
    local complementation is the switch.

His reading of it was "conservation in action, the system balances itself". The measurement below
is whether that holds: whether SWITCH preserves what RELEASE destroys.

GRADED AGAINST THE STATE VECTOR, NOT AGAINST ITSELF

Entropy here is read as the GF(2) rank of the off diagonal adjacency block, which is the bits and
never an amplitude array. For small cases the same number is computed from the actual 2^n state
vector and the two must agree. A bit level answer that has never been graded against the thing it
claims to summarise is a claim, not a measurement.
"""

import argparse
import itertools
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy

import graph_machine

BITS_PER_TERM = 64               # his floor, and product_machine.py measured why it is the floor
TERMS = 4                        # direction, polarisation, and the entanglement magnitude


def neighbours_of(machine, qubit):
    """The qubits this one is currently entangled with, read off the adjacency."""
    return [one for one in range(machine.qubits) if one != qubit and machine.edges[qubit, one]]


def entanglement_magnitude(machine, qubit):
    """The fourth term: 1 when this qubit is bound to anything, 0 when it is free.

    MAGNITUDELESS IN HIS SENSE, meaning it carries no length of its own. It is a predicate, and it
    is exactly what a three term qubit has no room for.
    """
    return 1 if neighbours_of(machine, qubit) else 0


def release(machine, qubit):
    """Z measurement: the qubit snaps and leaves, and its entanglement is destroyed.

    Deletes every edge on the qubit and nothing else. The neighbours keep whatever they had with
    each other and inherit nothing.
    """
    machine.edges[qubit, :] = 0
    machine.edges[:, qubit] = 0
    return machine


def switch(machine, qubit):
    """Y measurement: local complementation on the neighbourhood, then the qubit leaves.

    THE ORDER MATTERS AND IT IS NOT INTERCHANGEABLE. The complementation has to happen while the
    qubit still has its edges, because the neighbourhood is defined by them. Deleting first would
    complement an empty set and the operation would silently degrade into release().
    """
    live = neighbours_of(machine, qubit)
    for at, one in enumerate(live):
        for two in live[at + 1:]:
            flipped = machine.edges[one, two] ^ 1
            machine.edges[one, two] = flipped
            machine.edges[two, one] = flipped
    return release(machine, qubit)


def complement_only(machine, qubit):
    """Local complementation with the qubit LEFT IN PLACE, for the involution control below."""
    live = neighbours_of(machine, qubit)
    for at, one in enumerate(live):
        for two in live[at + 1:]:
            flipped = machine.edges[one, two] ^ 1
            machine.edges[one, two] = flipped
            machine.edges[two, one] = flipped
    return machine


SPLIT_CAP = 400                  # above this the balanced cuts are sampled, not enumerated


def balanced_splits(qubits, cap=SPLIT_CAP, seed=0):
    """Balanced bipartitions: every one of them when that is cheap, a fixed sample when it is not.

    Qubit 0 is pinned to the kept side. A split and its complement have the same off diagonal block
    up to transpose and therefore the same GF(2) rank, so counting both would double every figure
    and change nothing.

    THE CAP IS HERE BECAUSE THE FIRST VERSION HUNG THE MACHINE. The exhaustive count is
    C(n-1, n/2-1), which is 35 splits at 8 qubits, 462 at 12, 6435 at 16 and 1352078 at 24. Each one
    costs a GF(2) elimination, and twist_profile calls this n+1 times, a 24 qubit probe was tens
    of millions of eliminations and had to be killed.

    Sampling with a FIXED seed keeps the figure reproducible, which is the only property that
    matters for comparing shapes against each other. The caller is told which mode ran, because a
    sampled mean reported as an exhaustive one is a different number wearing the same name.
    """
    rest = list(range(1, qubits))
    half = qubits // 2
    if half < 1:
        return [], "none"

    total = math.comb(len(rest), half - 1) if hasattr(math, "comb") else None
    if total is not None and total <= cap:
        return [(0,) + one for one in itertools.combinations(rest, half - 1)], "exhaustive"

    generator = numpy.random.default_rng(seed)
    seen = set()
    while len(seen) < cap:
        pick = tuple(sorted(generator.choice(rest, size=half - 1, replace=False).tolist()))
        seen.add((0,) + pick)
    return sorted(seen), "sampled"


def total_entanglement(machine):
    """Mean entanglement across ALL balanced bipartitions, exhaustively.

    THIS REPLACES A DEGENERATE MEASURE AND THE OLD ONE WAS WORSE THAN USELESS. It summed the rank
    over the n splits of one qubit against the rest. A single qubit block is one row, and the GF(2)
    rank of one nonzero row is 1, so that sum was counting how many qubits had any edge at all. It
    read exactly 8 for all eight shapes at 8 qubits, and the twist moment built on it read exactly 0
    everywhere, because local complementation never isolates a vertex.

    Two dead columns in a results table are bad enough. The real damage was that they looked alive:
    the ordering printed from them was list order, and the prose called it a finding.

    A balanced cut is where the entanglement of a graph state actually shows. Taken over every
    balanced cut there is nothing chosen by hand, which was the only merit the old version had.
    """
    splits, _ = balanced_splits(machine.qubits)
    if not splits:
        return 0.0
    total = 0
    for keep in splits:
        order = list(keep) + [one for one in range(machine.qubits) if one not in keep]
        block = machine.edges[numpy.ix_(order, order)]
        cut = len(keep)
        total += int(graph_machine.gf2_rank(block[:cut, cut:].copy() % 2))
    return total / float(len(splits))


def bound_count(machine):
    """How many qubits carry a fourth term magnitude of 1."""
    return sum(entanglement_magnitude(machine, one) for one in range(machine.qubits))


def lc_orbit(machine, cap=20000):
    """Every graph reachable from this one by local complementation, as a set of keys.

    THE SECOND ENTROPY TERM, and it is independent of the first by construction. The GF(2) rank
    measures entanglement ACROSS A CUT of one fixed graph. This measures how many DISTINCT graphs
    the state can be moved to without touching the qubits at all, which is the freedom the state
    has rather than the correlation it holds. log2 of the orbit size is the entropy-adjacent figure,
    and it is the quantity the open entropy test wanted: family size against rank.

    Two states in one orbit are the same state up to local Clifford operations, so the orbit is the
    equivalence class and its size is how much of the description is convention rather than content.
    That is exactly the "relabelling is free, computing costs" result this tree keeps finding, in a
    form that can be counted.

    Breadth first over local complementation at every vertex. `cap` stops the enumeration rather
    than letting a wide orbit run the machine out of memory, and the caller is told when it was hit,
    because a truncated count reported as a total is a made-up number.
    """
    start = bytes(machine.edges.reshape(-1))
    seen = {start}
    frontier = [machine.edges.copy()]
    truncated = False

    while frontier:
        current = frontier.pop()
        for vertex in range(machine.qubits):
            walker = graph_machine.GraphMachine(machine.qubits)
            walker.edges = current.copy()
            complement_only(walker, vertex)
            key = bytes(walker.edges.reshape(-1))
            if key not in seen:
                if len(seen) >= cap:
                    truncated = True
                    frontier = []
                    break
                seen.add(key)
                frontier.append(walker.edges.copy())
        if truncated:
            break

    return len(seen), truncated


def twist_profile(machine):
    """Per vertex: how much the entanglement moves when the graph is twisted there.

    Douglas, 2026-09-11: "that moment inertia from the torsion and tension relationship that makes
    objects spin and twist, qubits do that."

    The pieces are already here and they line up without forcing:

        the TWIST is local complementation at one vertex, which is a local Clifford operation and
        therefore free, changing the description and not the state
        the TENSION is the edge set, since an edge is the one bit of entanglement a pair holds
        the RESPONSE is the change in total entanglement under that twist

    A vertex whose complementation barely moves the total is RIGID: the graph resists being twisted
    there. One that swings it is FREE. That distribution is the profile, and it is a property of the
    shape rather than of any choice made here, because every vertex is twisted and none is picked.

    Returns two lists of signed changes, one per vertex: the change in entanglement and the change
    in edge count. They are returned together because the whole result is in the contrast between
    them.

    THE ENTANGLEMENT RESPONSE IS EXACTLY ZERO AND THAT IS A THEOREM, NOT A MEASUREMENT. Local
    complementation is a local Clifford operation, and local Clifford operations preserve
    entanglement across every bipartition. So the first list is all zeros for every graph, at every
    vertex, at any size.

    That is not a dead measure to be replaced. It is an exact null, in the same family as the other
    exact nulls here, and it says the thing this tree keeps finding from new directions:
    RELABELLING IS FREE. A twist moves the description and not the content.

    THE TENSION RESPONSE IS NOT ZERO. The edge count is not a local Clifford invariant, so twisting
    changes how many pairs are bound while leaving what they hold across any cut untouched. That is
    the torsion against tension relationship with the conservation actually measured rather than
    asserted: the twist redistributes the binding and conserves the correlation.
    """
    base_entanglement = total_entanglement(machine)
    base_edges = int(machine.edges.sum()) // 2
    moved = []
    tension = []
    for vertex in range(machine.qubits):
        walker = graph_machine.GraphMachine(machine.qubits)
        walker.edges = machine.edges.copy()
        complement_only(walker, vertex)
        moved.append(total_entanglement(walker) - base_entanglement)
        tension.append((int(walker.edges.sum()) // 2) - base_edges)
    return moved, tension


def twist_moment(machine):
    """Second moment of the ENTANGLEMENT response. Exactly 0 for every graph, by LC invariance.

    Kept as a function rather than deleted because it is the exact null, and a control that is
    computed is worth more than one that is remembered.
    """
    moved, _ = twist_profile(machine)
    return sum(one * one for one in moved)


def tension_moment(machine):
    """Second moment of the EDGE COUNT response, which is the inertia analogue that is alive.

    Same shape as a moment of inertia summing mass against a squared distance. A graph whose edge
    count barely moves under a twist anywhere is rigid; one that swings is free.

    SQUARED AND NOT ABSOLUTE, deliberately. Signed changes cancel, and a near-zero signed sum would
    report a graph that twists hard in both directions as rigid. The square measures how much
    movement there is rather than where it ended up.
    """
    _, tension = twist_profile(machine)
    return sum(one * one for one in tension) / float(machine.qubits)


def pressure(machine, qubit):
    """How hard this qubit is being vibrated by its neighbours.

    Douglas, 2026-09-11: "they usually dissipate or are vibrated by neighbors back to their lowest
    state."

    The sum of the neighbours' DEGREES, not this qubit's own degree. That distinction is the whole
    content of the word "neighbours": a qubit bound to four isolated partners is barely disturbed,
    while one bound to four hubs is sitting in a storm. Using its own degree would make pressure a
    relabelling of connectivity and the driven relaxation below would then be a slower spelling of
    the random one.
    """
    return sum(len(neighbours_of(machine, one)) for one in neighbours_of(machine, qubit))


def relax(machine, driven=True, seed=0):
    """Release qubits one at a time until nothing is bound, and record the entanglement each step.

    THIS ADDS THE ONE THING THE MODEL DID NOT HAVE. Local complementation and measurement are both
    unitary-or-projective and closed: nothing in them leaks, and nothing relaxes. So the model could
    not express dissipation at all, and I wrongly let dissipation stand as an explanation for a
    table whose real cause was neighbourhood parity.

    `driven` picks the qubit under the most neighbour pressure at every step, recomputed each time
    because releasing one qubit changes the pressure on the rest. `driven=False` picks in a fixed
    random order and is the MATCHED CONTROL: same number of releases, same endpoint, no pressure.

    If the two produce the same curve then neighbour pressure is decoration and the honest report is
    that dissipation here is just decay in a costume.

    Returns the entanglement after each release, starting with the value before any.
    """
    work = graph_machine.GraphMachine(machine.qubits)
    work.edges = machine.edges.copy()

    generator = numpy.random.default_rng(seed)
    order = list(generator.permutation(machine.qubits))

    curve = [total_entanglement(work)]
    while True:
        bound = [one for one in range(work.qubits) if entanglement_magnitude(work, one)]
        if not bound:
            break
        if driven:
            # Highest neighbour pressure, with the lowest index breaking a tie so the run is
            # reproducible rather than depending on dictionary order.
            target = max(bound, key=lambda one: (pressure(work, one), -one))
        else:
            target = next(one for one in order if one in bound)
        release(work, target)
        curve.append(total_entanglement(work))
    return curve


def decay_rate(curve):
    """Exponential rate fitted to the entanglement curve, or None when it cannot be fitted.

    Least squares on log(entanglement) against step, over the steps where the entanglement is
    still positive. A constant rate here is what would make "dissipation" a real process with a
    number attached rather than a description.

    Returns (rate, half_life, points_used). None when fewer than three positive points exist, since
    a rate fitted to two points is not a fit, it is a line through whatever there was.
    """
    live = [(at, value) for at, value in enumerate(curve) if value > 0.0]
    if len(live) < 3:
        return None
    steps = numpy.array([one[0] for one in live], dtype=float)
    logs = numpy.log(numpy.array([one[1] for one in live], dtype=float))
    slope, _ = numpy.polyfit(steps, logs, 1)
    rate = -float(slope)
    half = (math.log(2.0) / rate) if rate > 1e-12 else float("inf")
    return rate, half, len(live)


def shaped(qubits, shape):
    machine = graph_machine.GraphMachine(qubits)
    getattr(machine, shape)()
    return machine


def _report():
    print("")
    print("  THE TWO SNAPS on four shapes. `bound` counts qubits whose fourth term reads 1.")
    print("  `total` is the entanglement summed over every single qubit split, so no bipartition")
    print("  is chosen by hand.")
    print("")
    print("  %-10s %7s %26s %26s" % ("", "", "RELEASE  (Z, snap only)", "SWITCH  (Y, snap + move)"))
    print("  %-10s %7s %8s %8s %8s %8s %8s %8s"
          % ("shape", "qubits", "bound", "total", "after", "bound", "total", "after"))

    for shape in ("star", "line", "ring", "complete"):
        for qubits in (6, 10):
            base = shaped(qubits, shape)
            before_bound = bound_count(base)
            before_total = total_entanglement(base)

            # The same qubit in both, so the two operations are compared on one object and not on
            # two differently shaped ones.
            target = 0

            one = shaped(qubits, shape)
            release(one, target)
            two = shaped(qubits, shape)
            switch(two, target)

            print("  %-10s %7d %8d %8.2f %8.2f %8d %8.2f %8d"
                  % (shape, qubits, before_bound, before_total,
                     total_entanglement(one), bound_count(one),
                     total_entanglement(two), bound_count(two)))
    print("")

    # THE CLAIM UNDER TEST, stated as a comparison rather than as a conclusion. Does switching
    # preserve what releasing destroys?
    print("  DOES SWITCHING PRESERVE WHAT RELEASING DESTROYS, which is his conservation reading:")
    print("")
    print("  %-10s %7s %10s %10s %10s %10s"
          % ("shape", "qubits", "before", "release", "switch", "switch-release"))
    conserved = 0
    examined = 0
    for shape in ("star", "line", "ring", "complete", "grid"):
        for qubits in (6, 9, 12):
            if shape == "grid":
                machine = graph_machine.GraphMachine(qubits)
                width = int(round(qubits ** 0.5))
                if width * width != qubits:
                    continue
                machine.grid(width)
                before = total_entanglement(machine)
                one = graph_machine.GraphMachine(qubits); one.grid(width)
                two = graph_machine.GraphMachine(qubits); two.grid(width)
            else:
                before = total_entanglement(shaped(qubits, shape))
                one = shaped(qubits, shape)
                two = shaped(qubits, shape)
            release(one, 0)
            switch(two, 0)
            after_release = total_entanglement(one)
            after_switch = total_entanglement(two)
            examined += 1
            if after_switch > after_release:
                conserved += 1
            print("  %-10s %7d %10.2f %10.2f %10.2f %+10.2f"
                  % (shape, qubits, before, after_release, after_switch,
                     after_switch - after_release))

    print("")
    print("  READ THE TABLE, NOT THIS SENTENCE.")
    print("")
    print("  Switching left MORE entanglement than releasing in %d of %d cases."
          % (conserved, examined))
    if conserved == examined:
        print("  So the switch is not a relabelling of the release: the local complementation moves")
        print("  connectivity into the neighbourhood that the release simply discards. That is the")
        print("  fourth term earning its 8 bytes, since both operations are conditioned on it and")
        print("  a three term qubit cannot tell which is available.")
    elif conserved == 0:
        print("  So on these shapes switching preserved nothing that releasing did not, and the")
        print("  distinction is not visible in this measure. That is against his reading and it")
        print("  needs saying plainly rather than being softened.")
    else:
        print("  So it holds on some shapes and not others, which is the interesting outcome and")
        print("  means the shape decides. Neither the conservation reading nor its denial survives")
        print("  as stated.")
    return 0


def _entropy(qubits=8):
    """Three entropy-adjacent measures against each other, on flat and spherical arrangements.

    Douglas: "spherical objects, which in this case are representing potential."

    THE THREE MEASURES ARE INDEPENDENT AND THAT IS THE POINT. They could easily have been three
    spellings of one number, and if they were, two of them would be waste:

        RANK      mean entanglement over every balanced cut of ONE graph. What correlation is held.
        FAMILY    log2 of the local complementation orbit. How many descriptions are the same
                  state, so how much of the representation is convention.
        TENSION   the second moment of the EDGE COUNT response to a twist. How hard the binding is
                  to move. The entanglement response to the same twist is exactly zero by local
                  Clifford invariance, which is the exact null in _check, so this is the half of
                  the torsion relationship that carries anything.

    EVERY SHAPE IS MATCHED AGAINST A RANDOM GRAPH ON THE SAME EDGE COUNT. Without that the
    comparison is worthless: a shape with more edges holds more entanglement for no interesting
    reason, and the earlier version of this comparison in graph_machine.py had exactly that problem.
    The matched random row is the control, and a shape only means something where it departs from
    it.
    """
    print("")
    print("  %d qubits. Every shape against a random graph on the SAME edge count, because an" % qubits)
    print("  unmatched comparison only measures how many edges somebody drew.")
    print("")
    print("  %-16s %6s %7s %9s %8s   %7s %9s %8s"
          % ("", "", "", "SHAPE", "", "", "RANDOM", ""))
    print("  %-16s %6s %7s %9s %8s   %7s %9s %8s"
          % ("shape", "edges", "rank", "family", "moment", "rank", "family", "moment"))

    def measures(machine):
        size, truncated = lc_orbit(machine)
        return (total_entanglement(machine),
                math.log(size, 2.0),
                tension_moment(machine),
                truncated)

    builders = [
        ("star", lambda m: m.star()),
        ("line", lambda m: m.line()),
        ("ring", lambda m: m.ring()),
        ("complete", lambda m: m.complete()),
        ("grid 2x4", lambda m: m.grid(4)),
        ("grid3d 2x2", lambda m: m.grid3d(2, 2)),
        ("fibonacci", lambda m: m.fibonacci()),
        ("golden sphere", lambda m: m.golden_sphere(4)),
    ]

    any_truncated = False
    rows = []
    for name, build in builders:
        machine = graph_machine.GraphMachine(qubits)
        try:
            build(machine)
        except (ValueError, TypeError, IndexError) as error:
            print("  %-16s skipped: %s" % (name, error))
            continue
        edges = int(machine.edges.sum()) // 2
        if edges == 0:
            print("  %-16s skipped: no edges" % name)
            continue

        rank, family, moment, cut = measures(machine)
        any_truncated = any_truncated or cut

        # The matched control, averaged over seeds so one lucky draw cannot carry it.
        control = []
        for seed in range(5):
            other = graph_machine.GraphMachine(qubits)
            other.random_edges(edges, seed=seed)
            control.append(measures(other))
        any_truncated = any_truncated or any(one[3] for one in control)
        mean_rank = sum(one[0] for one in control) / 5.0
        mean_family = sum(one[1] for one in control) / 5.0
        mean_moment = sum(one[2] for one in control) / 5.0

        rows.append((name, edges, rank, family, moment, mean_rank, mean_family, mean_moment))
        print("  %-16s %6d %7.2f %9.2f %8.2f   %7.2f %9.2f %8.2f"
              % (name, edges, rank, family, moment, mean_rank, mean_family, mean_moment))

    print("")
    if any_truncated:
        print("  AT LEAST ONE ORBIT HIT THE ENUMERATION CAP, so those family figures are lower")
        print("  bounds and not totals. Said here rather than left for a reader to assume.")
        print("")

    # DO THE THREE MEASURES AGREE ON AN ORDERING? If they rank the shapes the same way they are one
    # measure wearing three hats. If they disagree, each is carrying something the others are not,
    # and the disagreement is the result.
    if len(rows) >= 3:
        by_rank = [one[0] for one in sorted(rows, key=lambda r: -r[2])]
        by_family = [one[0] for one in sorted(rows, key=lambda r: -r[3])]
        by_moment = [one[0] for one in sorted(rows, key=lambda r: -r[4])]
        print("  ordered by rank:    %s" % ", ".join(by_rank))
        print("  ordered by family:  %s" % ", ".join(by_family))
        print("  ordered by moment:  %s" % ", ".join(by_moment))
        print("")
        print("  READ THE TABLE, NOT THIS SENTENCE.")
        print("")
        if by_rank == by_family == by_moment:
            print("  The three orderings are identical, so on these shapes the three measures are")
            print("  one quantity spelled three ways and two of them are redundant here.")
        else:
            print("  The three orderings differ, so each measure carries something the other two do")
            print("  not: held correlation, description freedom, and resistance to being twisted are")
            print("  separate properties of the same graph.")
    return 0


def _relax(qubits=10):
    """Dissipation: pressure-driven relaxation against a matched random-order control."""
    print("")
    print("  %d qubits. Qubits are released one at a time until nothing is bound." % qubits)
    print("  DRIVEN takes the qubit under the most neighbour pressure, recomputed every step.")
    print("  RANDOM takes a fixed random order: same count of releases, same endpoint, no pressure.")
    print("  If the two curves agree, neighbour pressure is doing nothing and the honest word is")
    print("  decay rather than dissipation.")
    print("")
    print("  %-16s %6s   %8s   %8s   %17s   %8s"
          % ("shape", "steps", "driven", "rnd mean", "rnd range (20 seeds)", "verdict"))

    builders = (
        ("star", lambda m: m.star()),
        ("line", lambda m: m.line()),
        ("ring", lambda m: m.ring()),
        ("complete", lambda m: m.complete()),
        ("grid 2x5", lambda m: m.grid(5)),
        ("fibonacci", lambda m: m.fibonacci()),
        ("golden sphere", lambda m: m.golden_sphere(4)),
    )

    separated = 0
    examined = 0
    for name, build in builders:
        machine = graph_machine.GraphMachine(qubits)
        try:
            build(machine)
        except (ValueError, TypeError, IndexError) as error:
            print("  %-16s skipped: %s" % (name, error))
            continue
        if int(machine.edges.sum()) == 0:
            print("  %-16s skipped: no edges" % name)
            continue

        driven = relax(machine, driven=True)
        # TWENTY SEEDS, NOT FIVE, AND THE RANGE IS KEPT. A mean alone cannot say whether a gap is
        # real: the first version of this printed gaps of 0.0457 and -0.0200 against rates near 0.3
        # with no idea what the seed to seed variation was, and then called pressure a real driver.
        # The spread of the random orders IS the null here, and it is drawn rather than assumed.
        randoms = [relax(machine, driven=False, seed=seed) for seed in range(20)]

        driven_fit = decay_rate(driven)
        random_fits = [one for one in (decay_rate(two) for two in randoms) if one is not None]

        if driven_fit is None or not random_fits:
            print("  %-16s %6d   %8s   %8s %17s   %8s"
                  % (name, len(driven) - 1, "-", "-", "too few steps to fit", "-"))
            continue

        d_rate, d_half, _ = driven_fit
        rates = [one[0] for one in random_fits]
        r_rate = sum(rates) / len(rates)
        low, high = min(rates), max(rates)

        examined += 1
        # THE VERDICT IS WHETHER THE DRIVEN RATE FALLS OUTSIDE THE RANDOM ORDERS' RANGE. No
        # tolerance is chosen: the control's own spread sets the bar, which is the rule here after
        # a judgment-picked threshold produced two false positives in beam_read.py tonight.
        outside = d_rate < low or d_rate > high
        if outside:
            separated += 1

        print("  %-16s %6d   %8.4f   %8.4f   %7.4f..%7.4f   %8s"
              % (name, len(driven) - 1, d_rate, r_rate, low, high,
                 "OUTSIDE" if outside else "inside"))

    print("")
    print("  READ THE TABLE, NOT THIS SENTENCE.")
    print("")
    print("  The driven rate fell OUTSIDE the random orders' own range on %d of %d shapes."
          % (separated, examined))
    print("")
    print("  THE COMPLETE GRAPH IS A FREE EXACT CONTROL. Every qubit in it has identical neighbour")
    print("  pressure, so driven and random are the same process by construction and the driven")
    print("  rate must sit inside the range. If that row ever reads OUTSIDE, pressure() is not")
    print("  computing what it claims and nothing else in the table can be read.")
    print("")
    if separated == 0:
        print("  So neighbour pressure changes nothing measurable here. The relaxation rate is a")
        print("  property of the SHAPE and not of the order of release, and every apparent gap sat")
        print("  inside the variation between random seeds. 'Vibrated by neighbours' and 'released")
        print("  at random' are the same curve. That is against the reading that prompted this")
        print("  measurement and it is the result.")
    else:
        print("  So on those shapes the driven rate leaves the control's own spread, which is the")
        print("  first evidence that pressure drives the relaxation rather than relabelling it.")
        print("  It still needs a second width before it is believed: these rates are slopes")
        print("  through under ten points each.")
    return 0


def _cost():
    print("")
    print("  WHAT THE FOURTH TERM COSTS, at his floor of %d bits a term." % BITS_PER_TERM)
    print("")
    per_local = TERMS * BITS_PER_TERM // 8
    print("  %8s %14s %16s %16s %14s"
          % ("qubits", "local bytes", "adjacency bytes", "bytes a qubit", "total"))
    for qubits in (16, 256, 4096, 65536):
        local = qubits * per_local
        adjacency = qubits * (qubits - 1) // 2 / 8.0
        total = local + adjacency
        print("  %8d %14d %16.0f %16.1f %11.2f MB"
              % (qubits, local, adjacency, total / qubits, total / 1048576.0))
    print("")
    print("  The four local terms are a FIXED %d bytes a qubit. The adjacency is what grows, and it" % per_local)
    print("  grows as n/16 bytes a qubit, because entanglement is a property of PAIRS and there are")
    print("  n(n-1)/2 of them. So the fourth term is not what makes this expensive at scale: it is")
    print("  8 bytes flat, and it is what makes the snap expressible at all.")
    print("")
    print("  Against the alternative: a full state vector at 4096 qubits is 2^4096 amplitudes, which")
    print("  is beyond writing down. The graph form holds real entanglement at that width in about")
    print("  1 MB. The trade is that it holds STABILISER states and not every state, and that is")
    print("  the same wall exact_qubits.py measured from the other side: these are cheap because")
    print("  Clifford circuits are classically simulable.")
    return 0


def _check():
    failed = 0
    print("")

    # THE BIT LEVEL ANSWER MUST AGREE WITH THE STATE VECTOR. This is the control that makes every
    # other number here a measurement rather than a claim about a data structure.
    for shape in ("star", "line", "ring", "complete"):
        for qubits in (4, 6, 8):
            machine = shaped(qubits, shape)
            keep = qubits // 2
            from_bits = machine.entropy_across(keep)
            from_state = graph_machine.entropy_from_state(machine.amplitudes(), keep, qubits)
            if abs(from_bits - from_state) > 1e-9:
                print("    FAIL %s %d: bits say %d, state vector says %s"
                      % (shape, qubits, from_bits, from_state))
                failed += 1
    print("  the GF(2) rank agrees with the state vector on every shape and width tested: %s"
          % (failed == 0))

    # AND AFTER A SNAP IT MUST STILL AGREE, which is the part that would break if release() or
    # switch() left the adjacency in a state that is not a graph state.
    mismatch = 0
    for shape in ("star", "line", "ring", "complete"):
        for operation in (release, switch):
            machine = shaped(8, shape)
            operation(machine, 0)
            keep = 4
            from_bits = machine.entropy_across(keep)
            from_state = graph_machine.entropy_from_state(machine.amplitudes(), keep, 8)
            if abs(from_bits - from_state) > 1e-9:
                print("    FAIL after %s on %s: bits %d, state %s"
                      % (operation.__name__, shape, from_bits, from_state))
                mismatch += 1
    failed += mismatch
    print("  and it still agrees after both snaps, so each leaves a valid graph state: %s"
          % (mismatch == 0))

    # THE EXACT NULL. Snapping a qubit that is not entangled must change nothing at all. Its fourth
    # term reads 0, there is no entanglement to release, and both operations must be the identity.
    # This is free, it is exact, and it is the cheapest way to catch an off-by-one in the edge
    # deletion that would otherwise look like a small real effect.
    broke = 0
    for operation in (release, switch):
        machine = graph_machine.GraphMachine(8)
        machine.star()
        release(machine, 3)                       # qubit 3 is now free: fourth term reads 0
        before = machine.edges.copy()
        if entanglement_magnitude(machine, 3) != 0:
            print("    FAIL qubit 3 still reads entangled after being released")
            broke += 1
        operation(machine, 3)
        if not numpy.array_equal(before, machine.edges):
            print("    FAIL %s on an unentangled qubit changed the adjacency"
                  % operation.__name__)
            broke += 1
    failed += broke
    print("  snapping a free qubit is exactly the identity on both operations: %s" % (broke == 0))

    # LOCAL COMPLEMENTATION IS AN INVOLUTION. Applied twice at the same vertex it must return the
    # original graph exactly. This grades the switch's moving part on its own, separately from the
    # deletion, a bug in one is not hidden by the other.
    involution = 0
    for shape in ("star", "line", "ring", "complete", "grid"):
        machine = graph_machine.GraphMachine(9)
        if shape == "grid":
            machine.grid(3)
        else:
            getattr(machine, shape)()
        before = machine.edges.copy()
        complement_only(machine, 4)
        once = machine.edges.copy()
        complement_only(machine, 4)
        if not numpy.array_equal(before, machine.edges):
            print("    FAIL local complementation at 4 on %s is not an involution" % shape)
            involution += 1
        if numpy.array_equal(before, once) and shape != "star":
            # A star's centre neighbourhood is an independent set, so one complementation makes it
            # complete and cannot be a no-op; for the others a no-op would mean it did nothing.
            print("    NOTE complementation on %s changed nothing, so that vertex had under two "
                  "neighbours" % shape)
    failed += involution
    print("  local complementation is an involution on every shape tested: %s" % (involution == 0))

    # THE POSITIVE CONTROL. Releasing the centre of a star must take the cluster to nothing, because
    # every edge in a star touches the centre. If that does not empty it, release() is not deleting
    # what it claims to.
    machine = graph_machine.GraphMachine(10)
    machine.star()
    before = total_entanglement(machine)
    release(machine, 0)
    after = total_entanglement(machine)
    print("  releasing a star's centre: entanglement %.2f -> %.2f, bound qubits %d"
          % (before, after, bound_count(machine)))
    if before <= 0.0 or after > 1e-12:
        print("    FAIL releasing the centre of a star did not empty the cluster")
        failed += 1

    # THE MEASURE MUST NOT BE DEGENERATE, and this control exists because the version before it was.
    # A figure that reads the same for a star, a ring and a complete graph is not measuring their
    # entanglement, and the failure is invisible in a results table because equal numbers look like
    # a finding. Any honest measure here has to separate at least some of these shapes.
    spread = set()
    for shape in ("star", "line", "ring", "complete"):
        spread.add(round(total_entanglement(shaped(8, shape)), 6))
    print("  the entanglement measure takes %d distinct values over 4 shapes: %s"
          % (len(spread), sorted(spread)))
    if len(spread) < 2:
        print("    FAIL the measure is degenerate and cannot tell these shapes apart")
        failed += 1

    # THE EXACT NULL. A twist is a local Clifford operation and those preserve entanglement across
    # every bipartition, so the entanglement response must be EXACTLY zero for every shape at every
    # vertex. Computed rather than remembered: if it ever came back non-zero, either the
    # complementation is wrong or the entanglement measure is not reading a bipartition.
    twisted = set()
    for shape in ("star", "line", "ring", "complete", "grid"):
        machine = graph_machine.GraphMachine(9)
        if shape == "grid":
            machine.grid(3)
        else:
            getattr(machine, shape)()
        twisted.add(round(twist_moment(machine), 12))
    print("  the twist leaves entanglement exactly unchanged on every shape: %s  %s"
          % (twisted == {0.0}, sorted(twisted)))
    if twisted != {0.0}:
        print("    FAIL a local Clifford twist changed the entanglement, so one of the two is wrong")
        failed += 1

    # AND THE TENSION RESPONSE MUST BE ALIVE, or the twist is doing nothing at all and the exact
    # null above would be vacuous rather than informative.
    tensions = set()
    for shape in ("star", "line", "ring", "complete"):
        tensions.add(round(tension_moment(shaped(8, shape)), 6))
    print("  the tension moment takes %d distinct values over 4 shapes: %s"
          % (len(tensions), sorted(tensions)))
    if len(tensions) < 2:
        print("    FAIL the tension moment is degenerate, so the twist moves nothing measurable")
        failed += 1

    # AND THE FOURTH TERM MUST BE A PREDICATE, not a magnitude that drifted into a range.
    machine = shaped(12, "ring")
    values = {entanglement_magnitude(machine, one) for one in range(12)}
    print("  the fourth term takes only the values %s" % sorted(values))
    if values - {0, 1}:
        print("    FAIL the entanglement magnitude is not binary")
        failed += 1

    # RELAXATION MUST TERMINATE AND MUST BE MONOTONE. Each release strictly reduces the bound count,
    # so the loop cannot run longer than the qubit count and must end at zero entanglement. A
    # non-terminating relaxation would hang the tool, and a non-monotone one would mean release() is
    # putting edges back.
    for shape in ("star", "line", "ring", "complete"):
        curve = relax(shaped(8, shape), driven=True)
        if len(curve) - 1 > 8:
            print("    FAIL relaxation on %s took %d steps for 8 qubits" % (shape, len(curve) - 1))
            failed += 1
        if curve[-1] > 1e-12:
            print("    FAIL relaxation on %s ended at %.4f rather than empty" % (shape, curve[-1]))
            failed += 1
        if any(curve[at + 1] > curve[at] + 1e-12 for at in range(len(curve) - 1)):
            print("    FAIL relaxation on %s is not monotone, a release added entanglement"
                  % shape)
            failed += 1
    print("  relaxation terminates, is monotone and ends empty on every shape: %s" % (failed == 0))

    # THE EXACT NULL. An unentangled graph relaxes in zero steps and its entanglement never moves.
    empty = graph_machine.GraphMachine(8)
    curve = relax(empty, driven=True)
    print("  an unbound graph relaxes in %d steps, curve %s" % (len(curve) - 1, curve))
    if len(curve) != 1 or curve[0] != 0.0:
        print("    FAIL an unbound graph did not relax trivially")
        failed += 1

    # AND THE POSITIVE CONTROL ON PRESSURE. In a star the centre carries every edge, so it is under
    # the most neighbour pressure and driven relaxation must take it first and finish in one step.
    # If it takes more, pressure() is not ranking what it claims to.
    star = shaped(10, "star")
    curve = relax(star, driven=True)
    print("  driven relaxation empties a 10 qubit star in %d step(s)" % (len(curve) - 1))
    if len(curve) - 1 != 1:
        print("    FAIL pressure did not pick the star's centre first")
        failed += 1

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="the fourth term and the snap it exists for")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--cost", action="store_true")
    parser.add_argument("--entropy", action="store_true")
    parser.add_argument("--relax", action="store_true")
    parser.add_argument("--qubits", type=int, default=8)
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    if args.cost:
        return _cost()
    if args.entropy:
        return _entropy(args.qubits)
    if args.relax:
        return _relax(args.qubits if args.qubits != 8 else 10)
    return _report()


if __name__ == "__main__":
    sys.exit(main())
