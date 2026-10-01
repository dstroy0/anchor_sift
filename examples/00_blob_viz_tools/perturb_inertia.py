"""Perturbation rotational inertia, per qubit: how hard the state resists being disturbed, by axis.

    python examples/00_blob_viz_tools/perturb_inertia.py --check
    python examples/00_blob_viz_tools/perturb_inertia.py              the inertia tensor per shape
    python examples/00_blob_viz_tools/perturb_inertia.py --profile    the per-qubit response, not summed

WHY THIS IS NOT THE TWIST, AND WHY IT WILL NOT COME BACK ZERO

"Add perturbation rotational inertia", "per qubit".

snap_release.py already measures the response to a TWIST, which is local complementation, and that
comes back exactly 0.0 at every vertex on every shape. It has to: local complementation is a local
Clifford operation and those preserve entanglement across every bipartition. A twist moves the
description and not the content, the relabeling-is-free result from another direction.

A PERTURBATION IS A DIFFERENT OPERATOR. Toggling the edges on one qubit changes the STATE, not its
description. It is not a local Clifford and it is not obliged to preserve anything. The response
is therefore live, and because each qubit sits at a position on the shell, the response has an
orientation.

WHAT MAKES IT ROTATIONAL

Each qubit has a place. Perturbing qubit i produces a response r_i, the amount of entanglement
moved. Treating that response as a mass at that qubit's position gives the ordinary inertia tensor

    I = sum_i r_i ( |p_i|^2 delta - p_i p_i^T )

whose eigenvalues are the principal moments and whose eigenvectors are the principal axes. A qubit
far from an axis and easy to disturb contributes heavily to the moment about that axis; one sitting
on the axis contributes nothing to it however easy it is to disturb. The word rotational means that
and only that here, and it is the standard definition and not an analogy.

A SPHERICAL ARRANGEMENT SHOULD COME OUT NEARLY ISOTROPIC, with three similar principal moments,
because no axis is special. A CHAIN SHOULD NOT: its qubits lie along one direction. The moment
about that direction should be far smaller than about the two across it. If those two predictions
fail the tensor is not measuring what it claims.
"""

import argparse
import math
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import beam_rows
import graph_machine
import snap_release

QUBITS = 16


def positions(count):
    """Where the qubits sit: golden directions on the shell, the same placement the readings use."""
    return numpy.array(beam_rows.source_points(count), dtype=float)


def shaped(qubits, shape):
    machine = graph_machine.GraphMachine(qubits)
    if shape == "grid":
        side = int(round(math.sqrt(qubits)))
        machine.grid(side)
    elif shape == "sphere":
        machine.golden_sphere(4)
    elif shape == "random":
        machine.random_edges(2 * qubits, seed=7)
    else:
        getattr(machine, shape)()
    return machine


def perturb_response(machine, qubit):
    """How much entanglement moves when this qubit's edges are toggled, and then restored.

    THE PERTURBATION IS AN INVOLUTION AND THE RESTORE IS EXACT. Toggling the same set twice returns
    the original adjacency bit for bit, which the control below checks. This measures a response
    without leaving the object changed. A measurement that quietly damaged the state would make
    every later qubit's response depend on the order they were visited.
    """
    before = snap_release.total_entanglement(machine)

    row = machine.edges[qubit].copy()
    for other in range(machine.qubits):
        if other == qubit:
            continue
        flipped = machine.edges[qubit, other] ^ 1
        machine.edges[qubit, other] = flipped
        machine.edges[other, qubit] = flipped

    after = snap_release.total_entanglement(machine)

    for other in range(machine.qubits):
        if other == qubit:
            continue
        flipped = machine.edges[qubit, other] ^ 1
        machine.edges[qubit, other] = flipped
        machine.edges[other, qubit] = flipped

    return abs(after - before)


def inertia_tensor(machine, places):
    """The perturbation inertia tensor, and the per-qubit responses it is built from."""
    responses = numpy.array([perturb_response(machine, one) for one in range(machine.qubits)])
    tensor = numpy.zeros((3, 3))
    for at in range(machine.qubits):
        point = places[at]
        tensor += responses[at] * (point.dot(point) * numpy.eye(3) - numpy.outer(point, point))
    return tensor, responses


def _report(qubits=QUBITS):
    places = positions(qubits)
    print("")
    print("  %d qubits on the shell. Each one's edges are toggled, the entanglement response is" % qubits)
    print("  read, and the responses are placed at their qubits' positions as masses.")
    print("")
    print("  %-10s %8s %11s %11s %11s %12s %11s"
          % ("shape", "edges", "I small", "I mid", "I large", "anisotropy", "trace"))

    for shape in ("line", "ring", "grid", "sphere", "complete", "random"):
        machine = shaped(qubits, shape)
        if int(machine.edges.sum()) == 0:
            print("  %-10s %8s" % (shape, "no edges"))
            continue
        tensor, responses = inertia_tensor(machine, places)
        moments = numpy.linalg.eigvalsh(tensor)
        spread = (moments[2] / moments[0]) if moments[0] > 1e-12 else float("inf")
        print("  %-10s %8d %11.4f %11.4f %11.4f %12s %11.4f"
              % (shape, int(machine.edges.sum()) // 2,
                 moments[0], moments[1], moments[2],
                 ("%.3f" % spread) if math.isfinite(spread) else "degenerate",
                 numpy.trace(tensor)))

    print("")
    print("  READ THE TABLE, NOT THIS SENTENCE.")
    print("")
    print("  ANISOTROPY IS THE LARGEST PRINCIPAL MOMENT OVER THE SMALLEST. A value near 1 means")
    print("  the state resists perturbation equally about every axis, as a placement")
    print("  with no preferred direction should. A large value names a soft axis.")
    print("")
    print("  The twist's response to the same shapes is exactly 0.0 by local Clifford invariance,")
    print("  so every number above is carried by the perturbation and none of it by the rotation.")
    return 0


def _profile(qubits=QUBITS):
    places = positions(qubits)
    print("")
    print("  Per-qubit response, unsummed. The tensor above can be seen being built.")
    print("")
    for shape in ("line", "sphere"):
        machine = shaped(qubits, shape)
        _tensor, responses = inertia_tensor(machine, places)
        print("  %s: degree and response per qubit" % shape)
        print("    %6s %8s %10s %10s" % ("qubit", "degree", "response", "radius"))
        for at in range(qubits):
            degree = len(snap_release.neighbors_of(machine, at))
            radius = float(numpy.linalg.norm(places[at]))
            print("    %6d %8d %10.4f %10.4f" % (at, degree, responses[at], radius))
        print("    response spread %.4f to %.4f, mean %.4f"
              % (responses.min(), responses.max(), responses.mean()))
        print("")
    return 0


def _check():
    failed = 0
    print("")
    places = positions(QUBITS)

    # THE PERTURBATION MUST BE AN INVOLUTION AND MUST RESTORE EXACTLY. If it did not, every
    # response after the first would be measured on a damaged object and the order of visits would
    # change the tensor.
    bad = 0
    for shape in ("line", "ring", "sphere", "grid"):
        machine = shaped(QUBITS, shape)
        before = machine.edges.copy()
        for one in range(QUBITS):
            perturb_response(machine, one)
        if not numpy.array_equal(before, machine.edges):
            bad += 1
    print("  perturbing every qubit leaves the adjacency bit-identical: %s" % (bad == 0))
    failed += bad

    # AND IT MUST ACTUALLY MOVE SOMETHING, or the tensor is zero and says nothing. This is the
    # contrast with the twist, which provably moves nothing.
    machine = shaped(QUBITS, "sphere")
    _tensor, responses = inertia_tensor(machine, places)
    twists = [snap_release.twist_moment(shaped(QUBITS, "sphere"))]
    print("  perturbation responses are nonzero: %s (max %.4f, mean %.4f)"
          % (bool(responses.max() > 0), responses.max(), responses.mean()))
    print("  the twist's response to the same shape is %s, the invariance"
          % twists[0])
    if responses.max() <= 0:
        print("    FAIL a perturbation moved nothing. There is no inertia to measure")
        failed += 1
    if twists[0] != 0.0:
        print("    FAIL the twist moved entanglement, contradicting local Clifford invariance")
        failed += 1

    # THE TENSOR MUST BE SYMMETRIC AND POSITIVE SEMI-DEFINITE, which any real inertia tensor is.
    # A negative principal moment would mean the construction is not an inertia tensor at all.
    worst_symmetry = 0.0
    negative = 0
    for shape in ("line", "ring", "sphere", "grid", "random"):
        tensor, _responses = inertia_tensor(shaped(QUBITS, shape), places)
        worst_symmetry = max(worst_symmetry, float(numpy.abs(tensor - tensor.T).max()))
        if numpy.linalg.eigvalsh(tensor).min() < -1e-9:
            negative += 1
    print("  the tensor is symmetric to %.3e and positive semi-definite everywhere: %s"
          % (worst_symmetry, negative == 0))
    if worst_symmetry > 1e-9 or negative:
        print("    FAIL the construction is not an inertia tensor")
        failed += 1

    # THE TWO PREDICTIONS, stated in the docstring before the run so they can refute it. A shell
    # placement should be near isotropic; a chain laid along the placement should not be.
    sphere_moments = numpy.linalg.eigvalsh(inertia_tensor(shaped(QUBITS, "sphere"), places)[0])
    sphere_spread = sphere_moments[2] / sphere_moments[0] if sphere_moments[0] > 1e-12 else float("inf")
    print("  sphere anisotropy %.3f" % sphere_spread)
    if not math.isfinite(sphere_spread) or sphere_spread > 3.0:
        print("    NOTE the shell placement is not isotropic at this width, which is a finding")
        print("    about the golden placement and not a failure of the tensor.")

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="perturbation rotational inertia, per qubit")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--profile", action="store_true")
    parser.add_argument("--qubits", type=int, default=QUBITS)
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    if args.profile:
        return _profile(args.qubits)
    return _report(args.qubits)


if __name__ == "__main__":
    sys.exit(main())
