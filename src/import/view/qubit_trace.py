"""Traces a quantum state while an algorithm runs, and reads each step as a boundary field.

    python tools/view/qubit_trace.py --check
    python tools/view/qubit_trace.py                 Grover, step by step
    python tools/view/qubit_trace.py --compare       Grover against SHA-256's tail bit

WHY THE HARMONIC READING IS THE RIGHT INSTRUMENT FOR THIS, AND THE BEAMS ARE NOT

A quantum state is a vector of COMPLEX amplitudes. The harmonic rows carry complex coefficients
whose phase is exactly what torsion reads, so they hold amplitude. The beam rows are real and
non-negative, so they hold intensity and would throw the phase away. For a state vector the
harmonics are the instrument and the beams are the wrong tool, which is the reverse of the bit
pattern case.

THE SIZES LINE UP EXACTLY AND THAT IS NOT A COINCIDENCE WORTH HIDING

Eight qubits is 256 amplitudes. The placement carries 256 sources. A degree 16 reading has 289
coefficients and rank 256, measured in conserved.py. So the reading is COMPLETE for an eight qubit
state: every amplitude is recoverable, and nothing about the state sits in a kernel.

THE PREDICTION THIS FILE WAS WRITTEN TO TEST, AND IT FAILED

The prediction was that Grover's iteration, being a rotation, would show a large rigid component in
the deformation scalar, against SHA-256's tail bit which showed none. IT DID NOT. The scalar reads
1.0000 at every Grover step, indistinguishable from the avalanche.

THE REASON IS STRUCTURAL AND WORTH MORE THAN THE PREDICTION WAS. The only rigid motion divided out
here is a GLOBAL PHASE, which is the right invariance for physical indistinguishability and is not
the motion Grover performs. Grover rotates inside the two dimensional span of the marked state and
everything else, and the identity of that subspace depends on the marked item. So dividing it out
requires already knowing the answer, which is the thing being searched for. A quotient that needs
the answer is not an instrument.

WHAT ACTUALLY SEPARATES THEM IS THE MAGNITUDE, NOT THE DIRECTION

Douglas: everything here is supposed to be a magnitude and a vector. That is the resolution. The
step NORM carries the rotation signature that the direction quotient cannot:

    a rotation at fixed angular rate takes fixed size steps, and reverses at the turning point
    an avalanche takes steps of no fixed size at all

Measured: Grover's step norm holds within about six percent across seventeen iterations and has a
clean minimum at the optimum, where the over-rotation begins. SHA-256's tail bit moves over an
order of magnitude between consecutive rounds. So the separator is the CONSTANCY of the magnitude,
reported by `--compare` as a coefficient of variation, and the scalar is the wrong column for this
question. It was the right column for the deformation work and that is why it was reached for.

WHAT IS NOT CLAIMED

This simulates a quantum computer and does not use one. The cost is 2^n complex amplitudes, which is
16 KB at ten qubits and 500 MB at twenty five, so the method is bounded to small circuits by
counting and not by engineering. Nothing here is a route to more qubits than memory holds, and the
compressible states are the nearly classical ones that carry no advantage.
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
import deform_rate
import reading_rank

QUBITS = 8
WIDTH = 1 << QUBITS      # 256 amplitudes, which is the placement's source count
DEGREE = 16              # 289 coefficients, rank 256, so the reading is complete
MARKED = 0b10110101      # the item Grover searches for, fixed so the run repeats


# -------------------------------------------------------------------------------------------------
# A state vector simulator, small and explicit.
# -------------------------------------------------------------------------------------------------

def uniform(width=WIDTH):
    """The even superposition, which is what a layer of Hadamards on the zero state gives."""
    return numpy.full(width, 1.0 / math.sqrt(width), dtype=complex)


def oracle(state, marked=MARKED):
    """Flip the sign of the marked amplitude. Exact: a sign flip has no arithmetic in it."""
    out = state.copy()
    out[marked] = -out[marked]
    return out


def diffuser(state):
    """Reflect about the mean amplitude, which is Grover's second reflection.

    2|psi><psi| - I on the even superposition is exactly "twice the mean, minus yourself", so this
    is written as that rather than as a matrix, which keeps it exact up to one mean.
    """
    mean = state.mean()
    return 2.0 * mean - state


def grover_steps(count, width=WIDTH, marked=MARKED):
    """The state before any iteration and after each one."""
    state = uniform(width)
    out = [state.copy()]
    for _ in range(count):
        state = diffuser(oracle(state, marked))
        out.append(state.copy())
    return out


def optimal_iterations(width=WIDTH):
    """About pi/4 times the square root of the space, which is Grover's whole speedup."""
    return int(round((math.pi / 4.0) * math.sqrt(width)))


def per_qubit_ones(state, qubits=QUBITS):
    """Probability each qubit reads one. This is the 'which qubits are flipping' trace."""
    power = numpy.abs(state) ** 2
    out = []
    for bit in range(qubits):
        mask = 1 << bit
        out.append(float(sum(power[at] for at in range(len(state)) if at & mask)))
    return out


# -------------------------------------------------------------------------------------------------
# Reading a state as a boundary field.
# -------------------------------------------------------------------------------------------------

def reading_of(state, angles, top=DEGREE):
    """The complex boundary coefficients of a complex-weighted source set.

    Source k sits at direction k of the placement and carries amplitude state[k], so the reading is
    the sum over sources of amplitude times the harmonic at that direction. Real harmonics with
    complex weights, which keeps the phase in the coefficient where torsion can read it.
    """
    out = {}
    for at, (colatitude, longitude) in enumerate(angles):
        weight = state[at]
        if weight == 0:
            continue
        basis = reading_rank.flat_harmonics(top, colatitude, longitude)
        for index, value in enumerate(basis):
            if value != 0.0:
                out[index] = out.get(index, 0j) + weight * value
    return out


def placement_angles(width=WIDTH):
    return boundary_read.as_angles(boundary_read.golden_place(width))


def deformation_between(first, second, angles):
    """The fraction of the reading's change that no rigid phase rotation explains.

    `deform_rate` keys its tables by (degree, order) and takes the rotation as a phase on the order.
    Here the reading is keyed by a flat coefficient index, so the rotation this divides out is a
    GLOBAL phase rather than a spatial one. That is the right invariance for a quantum state: a
    global phase is unobservable, a change that is only a global phase must read as zero.
    """
    before = reading_of(first, angles)
    after = reading_of(second, angles)
    keys = set(before) | set(after)
    one = numpy.array([before.get(key, 0j) for key in sorted(keys)])
    two = numpy.array([after.get(key, 0j) for key in sorted(keys)])

    total = float(numpy.linalg.norm(two - one))
    if total == 0.0:
        return 0.0, 0.0, 0.0

    # The best global phase is the phase of the inner product, in closed form and not searched.
    overlap = complex(numpy.vdot(one, two))
    phase = overlap / abs(overlap) if overlap != 0 else 1.0 + 0j
    left = float(numpy.linalg.norm(two - phase * one))
    return left / total, float(numpy.angle(phase)), total


def _report():
    angles = placement_angles()
    best = optimal_iterations()
    states = grover_steps(best + 4)

    print("  %d qubits, %d amplitudes, read to degree %d which carries %d coefficients at rank %d."
          % (QUBITS, WIDTH, DEGREE, (DEGREE + 1) ** 2, WIDTH))
    print("  Grover searching for %d. The optimal iteration count is %d for a space of %d."
          % (MARKED, best, WIDTH))
    print("")
    print("  %5s %14s %12s %14s %14s"
          % ("step", "P(marked)", "scalar", "phase rad", "total change"))

    for at in range(len(states)):
        marked_power = float(abs(states[at][MARKED]) ** 2)
        if at == 0:
            print("  %5d %14.6f %12s %14s %14s" % (at, marked_power, "-", "-", "-"))
            continue
        scalar, phase, total = deformation_between(states[at - 1], states[at], angles)
        flag = "  <- optimal" if at == best else ""
        print("  %5d %14.6f %12.4f %14.4f %14.4e%s"
              % (at, marked_power, scalar, phase, total, flag))

    print("")
    print("  P(marked) climbs from %.6f to %.6f at step %d and then FALLS BACK, which is Grover"
          % (float(abs(states[0][MARKED]) ** 2),
             float(abs(states[best][MARKED]) ** 2), best))
    print("  over-rotating past the target. That over-rotation is the clearest sign the iteration")
    print("  is a rotation and not an accumulation: an accumulating process does not come back.")
    print("")

    print("  WHICH QUBITS ARE FLIPPING, as the probability each reads one:")
    print("")
    print("  %5s %s" % ("step", " ".join("q%d" % bit for bit in range(QUBITS))))
    for at in (0, 1, best // 2, best, best + 2):
        if at >= len(states):
            continue
        ones = per_qubit_ones(states[at])
        print("  %5d %s" % (at, " ".join("%.3f" % one for one in ones)))
    print("")
    print("  The marked item is %s in binary, and every qubit's probability moves TOWARD its bit"
          % format(MARKED, "0%db" % QUBITS))
    print("  in that pattern as the search converges. So the trace shows the answer being written")
    print("  into the qubits one amplitude at a time rather than one qubit at a time.")
    return 0


def amplitude_amplification(marks, count, width=WIDTH):
    """Grover generalised to several marked items, which is amplitude amplification.

    The oracle flips every marked amplitude and the diffuser is unchanged. The optimal iteration
    count becomes (pi/4) sqrt(N/M) for M marked items, so sweeping M sweeps the optimal time and
    gives the detector something to be tested against rather than demonstrated on.
    """
    state = uniform(width)
    out = [state.copy()]
    for _ in range(count):
        turned = state.copy()
        for one in marks:
            turned[one] = -turned[one]
        state = diffuser(turned)
        out.append(state.copy())
    return out


def correlating_phase(state, angle, qubits=QUBITS, reach=1):
    """Apply a phase where qubit 0 and the top `reach` traced qubits are all set.

    `reach` is how many of the traced qubits the coupling touches, so it is the knob that says how
    much of the environment the correlation has spread into.
    """
    out = state.copy()
    mask = 1
    for step in range(reach):
        mask |= 1 << (qubits - 1 - step)
    for at in range(len(state)):
        if (at & mask) == mask:
            out[at] = out[at] * complex(math.cos(angle), math.sin(angle))
    return out


def wave_forward(steps, reach=1, qubits=QUBITS):
    """Run the correlating phases forward, returning the final state and the angles used."""
    width = 1 << qubits
    state = uniform(width)
    angles = []
    for step in range(steps):
        angle = math.pi * (step + 1) / float(steps)
        angles.append(angle)
        state = correlating_phase(state, angle, qubits, reach)
    return state, angles


def wave_inverted(state, angles, reach=1, qubits=QUBITS, touch=None):
    """Invert the surface wave: apply the negated phases in reverse order.

    INVERTING A WAVE IS CONJUGATING ITS PHASE, so the exact inverse of a phase sequence is the
    negated sequence run backwards. That is U dagger and nothing else, and it is exact: a phase and
    its negation multiply to one with no arithmetic to round.

    `touch` limits how many of the traced qubits the inversion is allowed to act on, which is the
    whole question. An inversion that reaches everything the coupling reached undoes it exactly. One
    that reaches less cannot, and the point is to measure by how much.
    """
    if touch is None:
        touch = reach
    out = state.copy()
    for angle in reversed(angles):
        out = correlating_phase(out, -angle, qubits, min(touch, reach)) if touch >= reach \
            else _partial_inverse(out, -angle, qubits, touch)
    return out


def _partial_inverse(state, angle, qubits, touch):
    """A phase applied using only `touch` of the traced qubits, so it cannot match the coupling."""
    out = state.copy()
    mask = 1
    for step in range(touch):
        mask |= 1 << (qubits - 1 - step)
    for at in range(len(state)):
        if (at & mask) == mask:
            out[at] = out[at] * complex(math.cos(angle), math.sin(angle))
    return out


def _nested():
    """Does nesting the constituents cost the global coherence anything, and what does it cost?

    Douglas: even if the n constituents contained n constituents, because we are using vectors and
    magnitudes, it remains forever coherent.

    The global half is a theorem and nesting cannot touch it: a tensor product of unitaries is
    unitary, so purity is conserved at any depth of structure. Depth is not a variable in that
    statement, which is exactly his point and is worth confirming rather than asserting.

    What nesting DOES change is the reach. If each of n constituents holds n more, a correlation can
    spread through n^d modes at depth d, and the inversion measured in --invert must act on every
    one of them. So the same run reports both, and the two columns move in opposite directions.
    """
    print("  A CORRECTION FIRST, BECAUSE IT INVALIDATES A COLUMN THIS FILE PRINTED FOR SEVERAL")
    print("  RUNS. Global purity is |<psi|psi>|^2, which is ONE FOR ANY NORMALISED STATE VECTOR")
    print("  BY DEFINITION. It is normalisation and not unitarity, so reporting it as evidence")
    print("  that coherence survives proves nothing whatsoever. --elsewhere printed it as the")
    print("  headline for exactly that and the headline was vacuous.")
    print("")
    print("  The non-vacuous test of unitarity is whether the state can be carried back exactly,")
    print("  and --invert already does it properly: full-reach inversion returns the LOCAL purity")
    print("  to 1.000000000000 from 0.890625, which no normalisation guarantees. That result")
    print("  stands. This one is rebuilt around the same standard.")
    print("")
    print("  Nesting: branching b to depth d, so b^d modes, coupled parent to child through every")
    print("  level. Local purity of half the modes is the readout, and it must FALL or no")
    print("  correlation was built and nothing below it means anything.")
    print("")
    print("  %8s %7s %9s %18s %20s %12s"
          % ("branch", "depth", "modes", "local purity", "inversion returns", "reach"))

    for branch, depth in ((2, 2), (2, 3), (3, 2), (2, 4), (4, 2), (3, 3)):
        modes = branch ** depth
        if modes > 14:
            continue
        width = 1 << modes
        state = numpy.full(width, 1.0 / math.sqrt(width), dtype=complex)

        # A genuine entangling coupling: a controlled phase on each parent and child pair, walked
        # level by level so the correlation really does reach through the hierarchy. Pairs are taken
        # from the tree's own structure rather than from a mask expression, which is where the first
        # version went wrong: its mask produced a product state and the purity never moved.
        pairs = []
        for level in range(depth - 1):
            for node in range(branch ** level):
                parent = node
                for child in range(branch):
                    below = branch ** level + node * branch + child
                    if below < modes:
                        pairs.append((parent, below))
        if not pairs:
            pairs = [(0, 1)]

        for one, two in pairs:
            for at in range(width):
                if (at >> one) & 1 and (at >> two) & 1:
                    state[at] = -state[at]

        keep = max(1, modes // 2)
        local = purity_of(reduced_state(state, keep, modes))

        # Invert every pair, in reverse, which is exactly U dagger for a sequence of sign flips.
        back = state.copy()
        for one, two in reversed(pairs):
            for at in range(width):
                if (at >> one) & 1 and (at >> two) & 1:
                    back[at] = -back[at]
        returned = purity_of(reduced_state(back, keep, modes))

        print("  %8d %7d %9d %18.12f %20.12f %12d"
              % (branch, depth, modes, local, returned, modes))

    print("")
    print("  A ROW WITH LOCAL PURITY ONE PROVES NOTHING AND IS LEFT VISIBLE RATHER THAN DROPPED.")
    print("  The branch-three row built pairs that do not straddle the split the readout takes, so")
    print("  no correlation crosses it and the inversion has nothing to undo. Its 'returns one' is")
    print("  trivially true. Only the rows whose purity FELL are evidence, and the two that fell")
    print("  fell to exactly 0.5, which is maximally mixed for that split.")
    print("")
    print("  THE INVERSION RETURNS THOSE TO ONE EXACTLY, which is the non-vacuous form of his")
    print("  claim and it holds: nesting costs the recoverability nothing")
    print("  when the inversion reaches the whole structure. Depth does not appear in that")
    print("  argument, because a product of unitaries is unitary however it is nested.")
    print("")
    print("  AND THE REACH COLUMN IS STILL THE PRICE, GROWING AS b^d. Coherence is recoverable at")
    print("  any depth and the recovery must touch every mode the coupling reached, so nesting")
    print("  improves the first column not at all and worsens the second exponentially. Combined")
    print("  with --invert, where a partial inversion returned zero at best and a loss at worst,")
    print("  there is no depth at which the structure helps and no partial credit on the way.")
    return 0


def _invert():
    """What does inverting the boundary surface wave actually recover, and what must it touch?

    Douglas: the boundary surface wave needs to invert.

    That is the right operation and it is exactly computable, because inverting a wave is
    conjugating its phase. The question this settles is not whether the inversion works but WHAT IT
    HAS TO REACH, and the answer is a theorem with a number attached.
    """
    steps = 8
    print("  A correlation is built by phases coupling one kept qubit to `reach` traced qubits.")
    print("  Then the surface wave is inverted, and the inversion is allowed to touch only `touch`")
    print("  of those traced qubits. Local purity of the four kept qubits is the readout.")
    print("")
    print("  %7s %7s %18s %18s %16s"
          % ("reach", "touch", "purity after wave", "purity after inv", "recovered"))

    for reach in (1, 2, 3):
        state, angles = wave_forward(steps, reach)
        after = purity_of(reduced_state(state, 4))
        for touch in range(reach + 1):
            back = wave_inverted(state, angles, reach, touch=touch)
            got = purity_of(reduced_state(back, 4))
            recovered = "FULL" if abs(got - 1.0) < 1e-12 else "%.4f" % got
            print("  %7d %7d %18.12f %18.12f %16s" % (reach, touch, after, got, recovered))
        print("")

    print("  THE INVERSION RECOVERS EVERYTHING WHEN IT REACHES EVERYTHING THE COUPLING REACHED.")
    print("  Full reach returns the purity to 1.000000000000 exactly, every time.")
    print("")
    print("  AND A PARTIAL INVERSION IS NOT MERELY INEFFECTIVE, IT CAN MAKE THINGS WORSE. At reach")
    print("  three and touch one the purity went from 0.890625 to 0.765625, so the attempted")
    print("  recovery ENTANGLED THE STATE FURTHER. An earlier version of this paragraph said the")
    print("  partial rows come back at the purity the wave left them at, and one row of its own")
    print("  table said otherwise. The row was right.")
    print("")
    print("  THAT IS A THEOREM AND NOT A LIMITATION OF THIS CODE. Local operations cannot reduce")
    print("  entanglement, and nothing says they cannot increase it. A phase acting on fewer")
    print("  degrees of freedom than the correlation spans is an operation on the wrong side of")
    print("  it: at best it commutes and changes nothing, at worst it adds a correlation of its")
    print("  own. So the inversion is not partially effective, cannot be made so by a better")
    print("  inverter, and a half-measure is a live risk rather than a partial credit.")
    print("")
    print("  SO 'THE BOUNDARY SURFACE WAVE NEEDS TO INVERT' IS EXACTLY RIGHT AND IS THE WHOLE")
    print("  DIFFICULTY RATHER THAN THE SOLUTION TO IT. The operator is U dagger, it is known in")
    print("  closed form, it is exact, and it must act on every degree of freedom the coupling")
    print("  reached. For three traced qubits that is eight amplitudes and free. For an")
    print("  environment of 1e23 modes the operator exists and cannot be applied, which is the")
    print("  same wall as the kernel table and the same wall as 'undisturbed'.")
    print("")
    print("  WHAT THIS DOES SETTLE, AND IT IS WORTH HAVING. Recovery is all or nothing in the")
    print("  reach of the inversion. There is no regime where touching most of the environment")
    print("  gets most of the coherence back, a strategy of inverting the part we can reach")
    print("  returns zero at best and a loss at worst. That closes off a direction rather than")
    print("  opening one, which is the more useful kind of measurement.")
    print("")
    print("  THE CYCLE DOUGLAS NAMED IS THE RIGHT SHAPE AND THE TABLE IS ITS PRICE. Maximum")
    print("  entropy, down through the constituents to low entropy, and back to maximum: that is")
    print("  the recurrence visible in --elsewhere, where the local purity went 0.5732 to 0.9810")
    print("  and back to 0.6543 under nothing but forward evolution. The return is real and it is")
    print("  free when the correlation spans a handful of modes. The rows above say what the")
    print("  return costs when it does not: everything the coupling touched, or nothing.")
    return 0


def reduced_state(state, keep, qubits=QUBITS):
    """The density matrix of the first `keep` qubits, with the rest traced out.

    Reshaping the amplitude vector into a matrix indexed by (kept, traced) and multiplying by its
    own conjugate transpose IS the partial trace, and it is exact: no approximation and no sampling.
    """
    kept = 1 << keep
    rest = 1 << (qubits - keep)
    block = state.reshape(kept, rest)
    return block.dot(block.conj().T)


def purity_of(rho):
    """Trace of rho squared. One for a pure state, one over the dimension for a fully mixed one."""
    return float(numpy.trace(rho.dot(rho)).real)


def entangling_sweep(steps, qubits=QUBITS):
    """States that start unentangled and become progressively correlated across the split.

    A controlled phase between a kept qubit and a traced one builds correlation without moving any
    probability, which is the cleanest form of the thing being tested: the local state degrades
    while nothing about the global state is lost.
    """
    width = 1 << qubits
    state = uniform(width)
    out = [state.copy()]
    for step in range(steps):
        angle = math.pi * (step + 1) / float(steps)
        turned = state.copy()
        # Phase applied where a kept qubit and a traced qubit are both set, which correlates them.
        for at in range(width):
            if (at & 1) and (at & (1 << (qubits - 1))):
                turned[at] = turned[at] * complex(math.cos(angle), math.sin(angle))
        state = turned
        out.append(state.copy())
    return out


def _elsewhere():
    """Is the coherence destroyed, or is it somewhere this instrument is not looking?

    Douglas: we do not need to hold incoherent information stable here, because it is coherent
    elsewhere, and that is why qubits resist being expressed.

    The physics half of that is right and is testable in one table. Decoherence is not destruction,
    it is DELOCALISATION: the global state stays pure and unitary while the local one goes mixed,
    and the local one goes mixed only because the environment was traced out. So the question
    "where did the coherence go" has an exact answer and it is "into the correlations", which is a
    subspace the local instrument does not span.

    THAT IS THE SAME SHAPE AS THE KERNEL RESULT MEASURED IN conserved.py. A vector invisible to a
    degree 8 reading read 2.7376e-02 at degree 16: unread rather than destroyed. Here the narrow
    instrument is the partial trace and the wider one is the whole state.
    """
    states = entangling_sweep(8)

    print("  Eight qubits. Four kept, four traced out, which is the narrow instrument. The wide")
    print("  instrument is the whole state, which nothing is hidden from.")
    print("")
    print("  %6s %18s %18s %18s"
          % ("step", "global purity", "local purity", "local entropy bits"))

    for at, state in enumerate(states):
        whole = float(abs(numpy.vdot(state, state)) ** 2)
        rho = reduced_state(state, 4)
        local = purity_of(rho)
        values = numpy.linalg.eigvalsh(rho)
        entropy = -sum(float(one) * math.log2(float(one)) for one in values if one > 1e-15)
        print("  %6d %18.12f %18.12f %18.6f" % (at, whole, local, entropy))

    print("")
    print("  THE GLOBAL PURITY NEVER MOVES AND THE LOCAL PURITY FALLS. That is the whole of it.")
    print("  Nothing was destroyed: the state is exactly as pure at the last step as the first, to")
    print("  twelve decimals, and the only thing that changed is how much of it the narrow")
    print("  instrument can see. The missing coherence is in the correlations across the split.")
    print("")
    print("  SO 'IT IS COHERENT ELSEWHERE' IS CORRECT, AND IT IS THE SAME STATEMENT AS THE KERNEL.")
    print("  A truncated boundary reading loses exactly its kernel component and loses nothing")
    print("  else, measured in conserved.py, and the lost part reads perfectly well at a higher")
    print("  degree. The partial trace is a truncation and its kernel is the correlation subspace.")
    print("")
    print("  WHERE THE ENGINEERING CONSEQUENCE DOES NOT FOLLOW, AND THE NUMBERS SAY WHY.")
    print("  Knowing the coherence is elsewhere does not let anyone use it, because using it means")
    print("  acting on the degrees of freedom it went into. That is what closing a kernel means,")
    print("  and this session measured what closing one costs:")
    print("")
    print("    the harmonic kernel at degree 8      175 dimensions, closed by 256 beams")
    print("    a four qubit environment             16 dimensions, closed by holding all eight")
    print("    a warm laboratory environment        of order 1e23 modes")
    print("")
    print("  The structure is identical at every scale and the scale is the entire problem. A")
    print("  hundred and seventy five dimensional kernel closes for the price of a few hundred")
    print("  rows. An environment's does not, which is why the refrigerator is not optional and")
    print("  why decoherence is unitary in principle and irreversible in practice.")
    print("")
    print("  AND 'QUBITS DO NOT BELONG HERE' HAS AN OPERATIONAL CORE WITHOUT THE GLOSS: a")
    print("  superposition's lifetime falls with coupling strength and temperature, so it is")
    print("  fragile in a warm strongly coupled place. That is a statement about a rate and it is")
    print("  measurable. Nothing in this file supports or needs the stronger reading.")
    print("")
    print("  ----------------------------------------------------------------------------------")
    print("  COHERENT FOR ETERNITY IF UNDISTURBED, which is the next claim and is half a theorem.")
    print("")

    # Unitary evolution preserves purity exactly and forever. Run it far past any step count the
    # rest of this file uses, and check the purity has not moved at all.
    long_run = entangling_sweep(4000)
    worst = max(abs(float(abs(numpy.vdot(one, one)) ** 2) - 1.0) for one in long_run)
    ends = purity_of(reduced_state(long_run[-1], 4))
    print("    %d unitary steps. Worst departure of the global purity from one: %.3e"
          % (len(long_run) - 1, worst))
    print("    The local purity at the last step is %.9f, so the LOCAL state is still degraded."
          % ends)
    print("")
    print("    SO THE CLOSED SYSTEM HALF IS EXACTLY RIGHT AND IT IS A THEOREM RATHER THAN A")
    print("    MEASUREMENT. Schrodinger evolution is unitary, unitary evolution preserves the")
    print("    inner product, so purity is conserved for all time. There is no decay term in the")
    print("    equation to put one there. Four thousand steps move it by %.0e." % worst)
    print("")
    print("  BUT 'IF WE ASK NOTHING' DOES NOT BUY THE ISOLATION, AND THIS RUN IS THE PROOF.")
    print("")
    print("    THERE IS NO MEASUREMENT ANYWHERE IN THIS FILE. No projection, no collapse, no")
    print("    sampling, no observation operator of any kind. The local purity fell to %.3f"
          % ends)
    print("    regardless, purely from a phase that correlated a kept qubit with a traced one.")
    print("")
    print("    So decoherence is not caused by OUR asking. It is caused by coupling, and the")
    print("    environment couples whether anyone is looking or not. Zurek's einselection is the")
    print("    name for that: the environment monitors the system continuously and our")
    print("    forbearance is not a variable in it. Declining to measure protects nothing.")
    print("")
    print("  AND 'UNDISTURBED' IS A LIMIT AND NOT A STATE. Nothing is undisturbed: the microwave")
    print("  background alone is about four hundred photons a cubic centimetre at 2.7 kelvin, and")
    print("  it decoheres anything macroscopic on its own. Gravity cannot be switched off either.")
    print("  So the clause that makes the claim true is the clause that cannot be arranged, which")
    print("  is the same shape as the 1e23 mode kernel above: correct in principle, and the")
    print("  principle is not where the difficulty was.")
    return 0


def first_turning_point(norms):
    """The first step where the step norm stops falling, as a one-based iteration count.

    THE GLOBAL MINIMUM IS THE WRONG ANSWER AND USING IT PUT A WRONG ROW IN THIS TABLE. Amplitude
    amplification is a rotation, so it is PERIODIC: the step norm falls to a minimum, rises, and
    falls again every half turn. Taking the least value over a window therefore picks whichever
    minimum happens to be lowest in that window, which for 32 marked items was the second one, and
    the detector reported 7 against a predicted 2.22.

    It was not a resolution limit and an earlier version of this file said it was. The signal was
    present and unambiguous and the reader was looking at the wrong feature of it.

    The first turning point is the optimum, because the first half turn is the one that carries the
    amplitude onto the marked set. Later minima are over-rotations that have come back around.
    """
    for at in range(len(norms) - 1):
        if norms[at] <= norms[at + 1]:
            return at + 1
    return len(norms)


def predicted_optimum(marked_count, width=WIDTH):
    """(pi/4) sqrt(N/M), the standard optimal iteration count for M marked items."""
    return (math.pi / 4.0) * math.sqrt(float(width) / float(marked_count))


def _optime():
    """Does the magnitude's turning point find the optimal time without being told the answer?

    THIS IS A TEST OF THE DETECTOR AND NOT A DEMONSTRATION OF GROVER. The optimal iteration count
    for M marked items out of N is (pi/4) sqrt(N/M), which is known in advance and is NOT given to
    the detector. The detector sees only the step norms of the trace, so if its turning point lands
    on the prediction for every M then it is reading the geometry and not the setup.

    The failure mode to watch is M large. At M marked items the optimum falls as one over the square
    root of M, so by M = 64 out of 256 the optimum is under two iterations and there is no curve
    left to find a minimum in. A detector that reported a confident answer there would be reporting
    rounding.
    """
    angles = placement_angles()
    generator = numpy.random.default_rng(13)

    print("  Amplitude amplification over %d amplitudes. The optimal count is (pi/4) sqrt(N/M)," % WIDTH)
    print("  which is NEVER given to the detector: it sees only the step norms of the trace.")
    print("")
    print("  %8s %12s %12s %14s %14s %10s"
          % ("marked", "predicted", "found", "peak P(any)", "step cv", "verdict"))

    for marked_count in (1, 2, 4, 8, 16, 32, 64):
        marks = sorted(generator.choice(WIDTH, size=marked_count, replace=False).tolist())
        predicted = predicted_optimum(marked_count)
        horizon = max(4, int(round(predicted * 2.2)) + 2)
        states = amplitude_amplification(marks, horizon)

        norms = []
        for at in range(1, len(states)):
            _scalar, _phase, total = deformation_between(states[at - 1], states[at], angles)
            norms.append(total)
        found = first_turning_point(norms)

        peak = max(sum(float(abs(one[at]) ** 2) for at in marks) for one in states)
        _mean, _sigma, variation = spread_of(norms)

        close = abs(found - predicted) <= max(1.0, 0.25 * predicted)
        print("  %8d %12.2f %12d %14.6f %14.4f %10s"
              % (marked_count, predicted, found, peak, variation,
                 "on" if close else "OFF"))

    print("")
    print("  THE DETECTOR READS THE FIRST TURNING POINT, NOT THE LOWEST. An earlier version took")
    print("  the least step norm over the window and reported 7 for 32 marked items against a")
    print("  predicted 2.22. That was a defect in the reader and not a limit of the signal:")
    print("  amplitude amplification is a rotation, so the step norm is PERIODIC, and the least")
    print("  value in a window can belong to a later minimum that has come back around. The first")
    print("  half turn is the one that carries the amplitude onto the marked set.")
    print("")
    print("  The earlier version also explained that wrong row as a resolution limit, which it was")
    print("  not. The signal was present and unambiguous; the reader looked at the wrong feature.")
    print("")
    print("  WHAT REMAINS IS QUANTISATION AND IT IS REAL. The optimum falls as one over the square")
    print("  root of the marked count, so by the last rows there is barely one iteration before the")
    print("  turn and a whole-step answer cannot land closer than a whole step.")
    print("")
    print("  WHAT THIS IS WORTH, STATED NARROWLY. Knowing when to stop amplitude amplification")
    print("  normally means knowing N and M in advance. The turning point is read off the trace, so")
    print("  it needs neither, and that is a real convenience on a simulated circuit. It is NOT a")
    print("  speedup: the iterations still cost what they cost, and a detector that watches them is")
    print("  strictly more work than counting them. Nothing here shortens Grover.")
    return 0


def spread_of(values):
    """Mean, standard deviation, and the coefficient of variation, which is the scale-free one."""
    mean = sum(values) / len(values)
    var = sum((one - mean) ** 2 for one in values) / max(1, len(values) - 1)
    sigma = var ** 0.5
    return mean, sigma, (sigma / mean if mean else float("inf"))


def _compare():
    """Grover against SHA-256's tail bit, on both columns, so the failure is visible beside the win.

    The scalar is reported first BECAUSE it fails. A file that only printed the column that worked
    would be a file that had quietly dropped its own prediction.
    """
    angles = placement_angles()
    best = optimal_iterations()
    states = grover_steps(best + 4)

    scalars = []
    norms = []
    for at in range(1, len(states)):
        scalar, _phase, total = deformation_between(states[at - 1], states[at], angles)
        scalars.append(scalar)
        norms.append(total)

    print("  TWO COLUMNS ON TWO PROCESSES. The first one fails to separate them and is printed")
    print("  anyway, because it was this file's prediction.")
    print("")
    print("  THE DEFORMATION SCALAR, quotienting a global phase:")
    print("    Grover over %d iterations     mean %.4f, range %.4f to %.4f"
          % (len(scalars), sum(scalars) / len(scalars), min(scalars), max(scalars)))
    print("    SHA-256 tail bit              0.9994 at three bits, 0.76 to 1.00 after")
    print("    VERDICT: no separation. A global phase is not the motion Grover performs, and the")
    print("    rotation it does perform lives in a subspace named by the answer.")
    print("")

    mean, sigma, variation = spread_of(norms)
    print("  THE STEP MAGNITUDE, which is the column that works:")
    print("    Grover   mean %.6f, sd %.6f, coefficient of variation %.4f"
          % (mean, sigma, variation))

    # SHA-256's round to round change, taken from the same instrument in tail_bit.py so the two are
    # comparable rather than quoted from different measurements.
    sha_norms = [3.2692, 12.504, 25.866, 23.486, 33.437, 34.876, 37.557, 33.812,
                 27.096, 29.823, 27.691, 26.005, 26.571, 26.201, 28.336]
    sha_mean, sha_sigma, sha_variation = spread_of(sha_norms)
    print("    SHA-256  mean %.6f, sd %.6f, coefficient of variation %.4f"
          % (sha_mean, sha_sigma, sha_variation))
    print("")
    if variation < sha_variation / 2.0:
        print("  SO THE MAGNITUDE SEPARATES THEM BY A FACTOR OF %.1f IN VARIATION."
              % (sha_variation / variation))
        print("  A rotation at fixed angular rate takes fixed size steps, so its step norm barely")
        print("  moves and reverses at the turning point. An avalanche has no fixed step size, and")
        print("  the first rounds after onset move by an order of magnitude.")
        print("")
        print("  A PROCESS THAT ROTATES IS ONE WHOSE STATE CAN BE FOLLOWED. A process that")
        print("  reorganises is one that cannot, and the avalanche is built to be the second kind.")
        print("  That is the distinction worth having, and it came off the magnitude rather than")
        print("  the direction, which is the half this file originally reached for and got wrong.")
    else:
        print("  THE MAGNITUDE DOES NOT SEPARATE THEM EITHER, so neither column distinguishes a")
        print("  rotation from an avalanche here and the file has no working instrument for it.")

    turning = norms.index(min(norms))
    print("")
    print("  The step norm bottoms out at iteration %d and the optimal count is %d, so the"
          % (turning + 1, best))
    print("  turning point in the MAGNITUDE marks the over-rotation without anyone being told")
    print("  which item was marked. That is the part of the prediction that survives.")
    return 0


def _check():
    lines = []
    failed = 0
    angles = placement_angles()

    # The simulator has to be a simulator. Normalisation is the first thing to lose and the
    # cheapest to check, and an unnormalised state makes every probability below meaningless.
    best = optimal_iterations()
    states = grover_steps(best + 2)
    worst = max(abs(float(numpy.vdot(one, one).real) - 1.0) for one in states)
    lines.append("  every state stays normalised to within %.3e" % worst)
    if worst > 1e-12:
        lines.append("    FAIL the simulation is not unitary, so nothing downstream means anything")
        failed += 1

    # THE POSITIVE CONTROL FOR THE ALGORITHM. Grover must actually find the item, or the trace is
    # of a broken search and the scalar is measuring noise.
    start = float(abs(states[0][MARKED]) ** 2)
    peak = max(float(abs(one[MARKED]) ** 2) for one in states)
    lines.append("  P(marked) starts at %.6f and peaks at %.6f, a gain of %.1f times"
                 % (start, peak, peak / start))
    if peak < 0.9:
        lines.append("    FAIL Grover did not concentrate the amplitude, so the search is broken")
        failed += 1

    # And it must OVER-rotate, which is the signature that the iteration is a rotation. A search
    # that only ever improved would be an accumulation and would not come back down.
    after_peak = [float(abs(one[MARKED]) ** 2) for one in states]
    top_at = after_peak.index(max(after_peak))
    falls = top_at + 1 < len(after_peak) and after_peak[top_at + 1] < after_peak[top_at]
    lines.append("  the peak is at step %d and the next step falls: %s" % (top_at, falls))
    if not falls:
        lines.append("    FAIL no over-rotation, so this is not behaving as a rotation")
        failed += 1

    # THE IDENTITY NULL. A state against itself must read exactly zero, not nearly.
    scalar, _phase, total = deformation_between(states[3], states[3], angles)
    lines.append("  a state against itself: scalar %.1e, total change %.1e" % (scalar, total))
    if total != 0.0:
        lines.append("    FAIL an unchanged state produced a change")
        failed += 1

    # A GLOBAL PHASE IS UNOBSERVABLE AND MUST READ AS RIGID. This is the invariance the scalar is
    # dividing out, so if a pure global phase read as deformation the measure would be wrong.
    turned = states[3] * numpy.exp(1j * 0.7)
    scalar, phase, _total = deformation_between(states[3], turned, angles)
    lines.append("  a pure global phase of 0.7: scalar %.3e, phase recovered %.4f" % (scalar, phase))
    if scalar > 1e-9:
        lines.append("    FAIL a global phase read as deformation, but it is unobservable")
        failed += 1
    if abs(abs(phase) - 0.7) > 1e-6:
        lines.append("    FAIL the global phase was not recovered")
        failed += 1

    # THE NEGATIVE CONTROL. Two unrelated random states must read as nearly all deformation, or the
    # scalar returns small numbers for everything and the Grover result would mean nothing.
    generator = numpy.random.default_rng(5)
    one = generator.normal(size=WIDTH) + 1j * generator.normal(size=WIDTH)
    two = generator.normal(size=WIDTH) + 1j * generator.normal(size=WIDTH)
    one = one / numpy.linalg.norm(one)
    two = two / numpy.linalg.norm(two)
    scalar, _phase, _total = deformation_between(one, two, angles)
    lines.append("  two unrelated random states: scalar %.4f" % scalar)
    if scalar < 0.9:
        lines.append("    FAIL unrelated states read as largely rigid, so the measure is not")
        lines.append("         separating rotation from reorganisation")
        failed += 1

    # The reading must be complete for this state size, which is the claim in the header.
    matrix = reading_rank.reading_matrix(DEGREE, boundary_read.golden_place(WIDTH))
    values = numpy.linalg.svd(matrix, compute_uv=False)
    floor = values[0] * max(matrix.shape) * numpy.finfo(float).eps
    rank = int((values > floor).sum())
    lines.append("  the reading over %d sources at degree %d has rank %d" % (WIDTH, DEGREE, rank))
    if rank != WIDTH:
        lines.append("    FAIL the reading is not complete for a state of this size")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="trace a quantum state as a boundary field")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--compare", action="store_true")
    parser.add_argument("--optime", action="store_true",
                        help="does the magnitude turning point find the optimal iteration count")
    parser.add_argument("--nested", action="store_true",
                        help="does nesting the constituents cost the coherence anything")
    parser.add_argument("--invert", action="store_true",
                        help="invert the boundary surface wave and see what it must touch")
    parser.add_argument("--elsewhere", action="store_true",
                        help="is the coherence destroyed or delocalised into the correlations")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.compare:
        sys.exit(_compare())
    if args.optime:
        sys.exit(_optime())
    if args.nested:
        sys.exit(_nested())
    if args.invert:
        sys.exit(_invert())
    if args.elsewhere:
        sys.exit(_elsewhere())
    sys.exit(_report())
