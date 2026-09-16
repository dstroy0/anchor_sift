#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# A deposited protein model read three ways, because two of the three threw away what they measured.
#
#   Usage:  from representation.structure.protein import fetch, atoms, density, backbone, walk
#
# Laying every atom into a grid discards the order, and what is left is a scatter of points in a box
# that is mostly empty, where most of a line drawn through it crosses vacuum. Taking the step from
# one alpha carbon to the next keeps the order and discards the bonds, since an alpha carbon is
# already a summary of a residue and the step between two of them is not a bond. Walking the backbone
# nitrogen to alpha carbon to carbon keeps both, and every step of it is a real bond with a length
# fixed by chemistry.
#
# All three are here because the comparison between them is the finding, and dropping the two that
# lost would leave the third looking like the obvious choice it was not.
#
# Nothing here computes where the repository is. A caller passes the directory in.

import os
import urllib.request

import numpy

from representation.levels import to_levels

# Sent with the download, since a public archive is entitled to know who is asking.
AGENT = {"User-Agent": "anchor-sift-research/1.0"}

# The three backbone atoms of a residue, in the order the chain is assembled.
BACKBONE = ("N", "CA", "C")

# Angstroms. A backbone bond longer than this is a break in the model and not a bond.
BOND_LIMIT = 2.2

# Angstroms. The distance between consecutive alpha carbons, which is nearly fixed at 3.8.
STEP_LOW = 3.4
STEP_HIGH = 4.4

# Structures chosen to differ in the ways a reading might key on: size, chain count, and how far
# from a sphere the shape is.
WANTED = (
    ("1UBQ", "ubiquitin, small and compact"),
    ("4HHB", "hemoglobin, four chains"),
    ("1AON", "chaperonin, large barrel"),
    ("1BNA", "a DNA duplex, strongly elongated"),
    ("6VXX", "a spike glycoprotein"),
    ("1CRN", "crambin, very small"),
)


def fetch(code, corpora):
    """One deposited entry as text, downloaded once and read from `corpora` every time after.

    The archive is asked only where the file is absent. A run therefore costs the network nothing
    after the first, and a reading can be repeated with the network unavailable.
    """
    path = os.path.join(corpora, "pdb_%s.txt" % code)
    if os.path.isfile(path):
        with open(path, encoding="utf-8", errors="replace") as handle:
            return handle.read()
    url = "https://files.rcsb.org/download/%s.pdb" % code
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=180) as response:
        text = response.read().decode("utf-8", errors="replace")
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    return text


def atoms(text):
    """Every atom position in the file, in the order the file lists them."""
    found = []
    for line in text.splitlines():
        if not line.startswith("ATOM"):
            continue
        try:
            found.append((float(line[30:38]), float(line[38:46]), float(line[46:54])))
        except ValueError:
            continue
    return numpy.asarray(found, dtype=numpy.float64)


def density(points, side, blur):
    """Atoms laid into a grid and smoothed, the form a structure is observed in.

    The smoothing is not a convenience. Deposited atoms with no smoothing give a grid that is almost
    entirely empty, and a reading of that describes the emptiness. A few voxels is what the
    measurement that produced these coordinates actually resolves.

    Returns None where an axis has no extent, or where the smoothed grid does not vary.
    """
    low = points.min(axis=0)
    high = points.max(axis=0)
    span = high - low
    if float(span.min()) <= 0.0:
        return None
    # Each axis scaled on its own, so the grid holds the shape and not the bounding cube
    placed = numpy.clip(((points - low) / span * (side - 1)).astype(numpy.int64), 0, side - 1)
    grid = numpy.zeros((side,) * 3, dtype=numpy.float64)
    numpy.add.at(grid, (placed[:, 0], placed[:, 1], placed[:, 2]), 1.0)

    axes = numpy.meshgrid(*[numpy.fft.fftfreq(side) * side] * 3, indexing="ij")
    radius = sum(axis ** 2 for axis in axes)
    kernel = numpy.exp(-2.0 * (numpy.pi ** 2) * (blur ** 2) * radius / (side ** 2))
    smooth = numpy.real(numpy.fft.ifftn(numpy.fft.fftn(grid) * kernel))
    return to_levels(smooth)


def backbone(text, least=64):
    """Alpha carbons in the order the file lists them, split where the chain is not continuous."""
    runs = []
    current = []
    last_chain = None
    for line in text.splitlines():
        if (not line.startswith("ATOM")) or (line[12:16].strip() != "CA"):
            continue
        # The alternate location marker repeats a residue, and taking both puts a zero step in the chain
        if line[16] not in (" ", "A"):
            continue
        chain = line[21]
        try:
            point = (float(line[30:38]), float(line[38:46]), float(line[46:54]))
        except ValueError:
            continue
        if (last_chain is not None) and (chain != last_chain):
            runs.append(current)
            current = []
        current.append(point)
        last_chain = chain
    runs.append(current)
    return [numpy.asarray(run, dtype=numpy.float64) for run in runs if len(run) >= least]


def walk(text, least=96):
    """The backbone atoms in the order the chain was assembled, one run per unbroken stretch.

    A run continues only where the next atom is the next one the backbone calls for. A missing atom
    or a change of chain therefore ends the run, instead of putting a bond into it that no chemistry
    made.
    """
    runs = []
    current = []
    expecting = 0
    last_chain = None
    for line in text.splitlines():
        if not line.startswith("ATOM"):
            continue
        name = line[12:16].strip()
        if name not in BACKBONE:
            continue
        # An alternate location repeats an atom, and keeping both puts a zero length bond in the walk
        if line[16] not in (" ", "A"):
            continue
        chain = line[21]
        try:
            point = (float(line[30:38]), float(line[38:46]), float(line[46:54]))
        except ValueError:
            continue

        # The walk only continues where the next atom is the next one the backbone calls for
        if (name != BACKBONE[expecting]) or ((last_chain is not None) and (chain != last_chain)):
            runs.append(current)
            current = []
            expecting = 0
            if name != BACKBONE[0]:
                last_chain = chain
                continue
        current.append(point)
        expecting = (expecting + 1) % len(BACKBONE)
        last_chain = chain
    runs.append(current)
    return [numpy.asarray(run, dtype=numpy.float64) for run in runs if len(run) >= least]


def bonds(runs, least=96):
    """Every bond vector along the walk, each piece carrying where in the cycle of three it begins.

    A run holding a break is cut, and every piece after the first then starts somewhere other than
    the first bond of a residue. Concatenating them without saying so mixes the three bond types
    together, which read 1.43, 1.43 and 1.43 on the large structures: the average of all three,
    three times.
    """
    vectors = []
    for run in runs:
        moves = numpy.diff(run, axis=0)
        lengths = numpy.sqrt((moves ** 2).sum(axis=1))
        broken = numpy.flatnonzero(lengths > BOND_LIMIT)
        if len(broken) == 0:
            vectors.append((moves, 0))
            continue
        start = 0
        for stop in list(broken) + [len(lengths)]:
            piece = moves[start:stop]
            if len(piece) >= least:
                vectors.append((piece, start % len(BACKBONE)))
            start = stop + 1
    return vectors


def steps(runs):
    """The step from each residue to the next, kept only where the chain is unbroken."""
    kept = []
    for run in runs:
        moves = numpy.diff(run, axis=0)
        lengths = numpy.sqrt((moves ** 2).sum(axis=1))
        good = (lengths >= STEP_LOW) & (lengths <= STEP_HIGH)
        kept.append((moves[good], lengths[good]))
    return kept


# The three coordinate columns of a PDB ATOM record, each written to exactly three decimal places.
# Read as integers at that scale, a dihedral is a ratio of cross and dot products in which the scale
# cancels, so the angle is exact in the coordinates the deposit actually wrote.
COORD_PLACES = 3


def phi_psi(text):
    """Every residue's backbone torsions phi, psi and omega, as exact integer terms.

    A protein's fold does not live in where its atoms are. Rigidly moving the whole molecule leaves
    the fold untouched, so the coordinates carry an orientation and a position the fold does not
    have. What the fold lives in is the backbone torsions, and those are what the Ramachandran rules
    are written over. This reads them and keeps them exact.

    A torsion is a ratio. For the four atoms across a bond it is atan2(Y, X) with

        Y = -(n1 x b2) . n2      X = n1 . n2       n1 = b1 x b2, n2 = b2 x b3

    where b1, b2, b3 are the three bond vectors. Every one of Y and X is an integer when the atoms
    are, so nothing is rounded to form them. The only irrational step is the atan2 itself, and it is
    not taken here. The caller is handed Y, and the two integers C and S whose product C * sqrt(S)
    is X, and renders the angle to a stated precision. This mirrors representation.exact: the reader
    stays integer, and the one place an irrational is unavoidable is named and deferred, not buried
    in a float that fixes a precision nobody chose.

    X is returned split because its own sqrt is where the irrational sits. atan2(Y, dot . |b2|) and
    atan2(Y / |b2|, dot) are the same angle, so the |b2| is factored out as sqrt(S) with
    S = b2 . b2 and C = n1 . n2, and the caller multiplies them at whatever precision it declares.

    The sign is the IUPAC convention, fixed not by assertion but by measurement: with it, a corpus
    of deposited structures reproduces each one's wwPDB-published Ramachandran outlier rate, and
    with it negated every structure reads as its own mirror image and almost nothing agrees.

    Returns a list in chain and sequence order, one entry per residue carrying both neighbors:

        {"chain", "seq", "name", "next_name",
         "phi": (Y, C, S), "psi": (Y, C, S), "omega": (Y, C, S)}

    omega is the peptide torsion CA-C-N-CA into this residue, from which a caller tells a cis proline
    from a trans one. A residue at a chain end or across a break, where a neighbor is missing, is
    left out rather than joined across the gap.
    """
    def scaled(field):
        body = field.strip()
        sign = 1
        if body[:1] in ("+", "-"):
            sign = -1 if body[0] == "-" else 1
            body = body[1:]
        whole, _, part = body.partition(".")
        part = (part + "000")[:COORD_PLACES]
        return sign * int((whole or "0") + part)

    def cross(one, two):
        return (one[1] * two[2] - one[2] * two[1],
                one[2] * two[0] - one[0] * two[2],
                one[0] * two[1] - one[1] * two[0])

    def dot(one, two):
        return one[0] * two[0] + one[1] * two[1] + one[2] * two[2]

    def less(one, two):
        return (one[0] - two[0], one[1] - two[1], one[2] - two[2])

    def torsion(p0, p1, p2, p3):
        b1 = less(p1, p0)
        b2 = less(p2, p1)
        b3 = less(p3, p2)
        n1 = cross(b1, b2)
        n2 = cross(b2, b3)
        return (-dot(cross(n1, b2), n2), dot(n1, n2), dot(b2, b2))

    # Backbone atoms in file order, gathered per residue, keeping the first alternate location only,
    # because a second one repeats a residue and puts a zero length bond into the walk.
    order = []
    seen = {}
    for line in text.splitlines():
        if not line.startswith("ATOM"):
            continue
        atom = line[12:16].strip()
        if atom not in BACKBONE:
            continue
        if line[16] not in (" ", "A"):
            continue
        key = (line[21], line[22:27])
        if key not in seen:
            seen[key] = {"chain": line[21], "seq": line[22:27].strip(),
                         "name": line[17:20].strip()}
            order.append(key)
        try:
            seen[key][atom] = (scaled(line[30:38]), scaled(line[38:46]), scaled(line[46:54]))
        except ValueError:
            continue

    # One list of complete residues per chain, in the order the file lists them.
    chains = {}
    for key in order:
        record = seen[key]
        if all(atom in record for atom in BACKBONE):
            chains.setdefault(record["chain"], []).append(record)

    found = []
    for chain in chains.values():
        for at in range(1, len(chain) - 1):
            prev, here, nxt = chain[at - 1], chain[at], chain[at + 1]
            found.append({
                "chain": here["chain"], "seq": here["seq"],
                "name": here["name"], "next_name": nxt["name"],
                "phi": torsion(prev["C"], here["N"], here["CA"], here["C"]),
                "psi": torsion(here["N"], here["CA"], here["C"], nxt["N"]),
                "omega": torsion(prev["CA"], prev["C"], here["N"], here["CA"]),
            })
    return found


# THE WALK BACK TO COORDINATES
#
# A run of points, the kind `walk` returns, is fixed by where its first three points sit and, from
# the fourth on, by how each point stands on the three before it: a bond length, the angle it turns
# through, and the dihedral about the bond it shares with its predecessor. Those three terms hold no
# position and no orientation, so they are what survives moving or turning the whole run. `phi_psi`
# makes this statement for the two torsions of a residue; the same holds for every point of the
# backbone. `internal_coords` reads the terms off a run and `rebuild` walks them back; handed the
# terms read off a run, `rebuild` returns that run.


def internal_coords(atoms):
    """Each point's bond length, turn angle and dihedral against the three points before it.

    `atoms` is an ordered run of points, the kind `walk` returns. The first three are the seed and
    carry no terms. From the fourth on, a point is fixed by its distance to the point before it, the
    angle it makes at that point with the one before that, and the dihedral about the shared bond.

    Returns three float arrays the length of `atoms`, the seed entries left at zero. The dihedral
    sign is the one `rebuild` reads back, so `rebuild(atoms[:3], *internal_coords(atoms))` reproduces
    `atoms`.
    """
    count = len(atoms)
    bond = numpy.zeros(count, dtype=numpy.float64)
    angle = numpy.zeros(count, dtype=numpy.float64)
    dihedral = numpy.zeros(count, dtype=numpy.float64)
    if count < 2:
        return bond, angle, dihedral
    edge = numpy.diff(atoms, axis=0)
    length = numpy.sqrt((edge ** 2).sum(axis=1))
    bond[1:] = length
    if count >= 3:
        # The angle at each interior point, between the edge arriving and the edge leaving it.
        toward = -edge[:-1]
        onward = edge[1:]
        cosine = (toward * onward).sum(axis=1) / (length[:-1] * length[1:])
        angle[2:] = numpy.arccos(numpy.clip(cosine, -1.0, 1.0))
    if count >= 4:
        b1 = edge[:-2]
        b2 = edge[1:-1]
        b3 = edge[2:]
        n1 = numpy.cross(b1, b2)
        n2 = numpy.cross(b2, b3)
        unit_b2 = b2 / numpy.sqrt((b2 ** 2).sum(axis=1))[:, None]
        m = numpy.cross(n1, unit_b2)
        # Negated to the IUPAC sign, so a torsion read here carries the same sign as phi_psi and the
        # Ramachandran rules: a right-handed alpha helix sits near phi -63, psi -43, not its mirror.
        dihedral[3:] = -numpy.arctan2((m * n2).sum(axis=1), (n1 * n2).sum(axis=1))
    return bond, angle, dihedral


def rebuild(seed, bond, angle, dihedral, steer=None):
    """Walk the internal terms back into coordinates, each point placed on the three before it.

    `seed` is the first three points, which fix where the run sits and how it is turned. `bond`,
    `angle` and `dihedral` are what `internal_coords` returns. From the fourth point on, each is
    placed by the one step that reproduces its bond length, its turn angle, and its dihedral about
    the bond it shares with its predecessor. The frame is built from the three prior points, so an
    error in one point rides forward into every point after it. The run's shape is read against the
    deposit with that error carried forward, and superposing the two backbones would hide where it
    entered.

    This is the Natural Extension Reference Frame placement (Parsons, Holmes, Rojas, Tsai, Strauss,
    J Comput Chem 2005, doi:10.1002/jcc.20237). The step is sequential, so a small per-point error
    propagates the length of the run; a distance-geometry transform reads all points at once and
    does not carry it.

    `steer`, when given, is called as steer(index, dihedral_radians) before each point is placed and
    its return is the direction actually walked. A caller passes it to hold the walk inside a region
    it alone defines, a truthy cell of a table it supplies, and leaves a direction untouched by
    returning it as given. The engine stays blind to what makes a direction truthy: the whole of that
    judgment is the caller's, which keeps the reference table (the Ramachandran grid, say) out of the
    engine while the walk that reads it is here.

    Returns the run as a float array the length of `bond`.
    """
    count = len(bond)
    out = numpy.empty((count, 3), dtype=numpy.float64)
    out[:3] = seed
    for at in range(3, count):
        prev3, prev2, prev1 = out[at - 3], out[at - 2], out[at - 1]
        axis = prev1 - prev2
        axis = axis / numpy.sqrt((axis ** 2).sum())
        normal = numpy.cross(prev2 - prev3, axis)
        normal = normal / numpy.sqrt((normal ** 2).sum())
        side = numpy.cross(normal, axis)
        radius = bond[at]
        turn = angle[at]
        about = dihedral[at] if steer is None else steer(at, dihedral[at])
        local = numpy.array([-radius * numpy.cos(turn),
                             radius * numpy.sin(turn) * numpy.cos(about),
                             radius * numpy.sin(turn) * numpy.sin(about)])
        out[at] = prev1 + numpy.column_stack([axis, side, normal]) @ local
    return out


# TRUTHY AND FALSY STEERING
#
# A walk that steers reads a table that says, at each place it might go, true or false: this place is
# allowed, that one is not. The mechanism is here, in the engine, because the walk is here. What the
# table means is not: a caller builds it, from the Ramachandran grid or anything else, and hands the
# walk a `steer` that consults it. `nearest_truthy` is the one piece of that a walk needs from the
# engine and cannot get from the table alone, since a table only answers about the place it is asked
# and not where the nearest allowed place is. It knows true from false and nothing more, so it serves
# any table, and the reference data that fills a particular one stays out of the engine.


def nearest_truthy(truthy, row, col):
    """The nearest cell a boolean grid marks true, searching outward on a torus from (row, col).

    If (row, col) is already true it stands. Otherwise the search grows a square ring, wrapping both
    axes, and returns the first true cell it reaches; ties inside a ring resolve in a fixed scan
    order, so the same grid and cell always steer the same way. Returns None only when the grid holds
    no true cell at all, which a caller reads as a table that forbids everywhere and refuses.
    """
    rows, cols = truthy.shape
    if truthy[row % rows, col % cols]:
        return (row % rows, col % cols)
    for radius in range(1, max(rows, cols) + 1):
        for d_row in range(-radius, radius + 1):
            for d_col in range(-radius, radius + 1):
                if max(abs(d_row), abs(d_col)) != radius:
                    continue
                here_row, here_col = (row + d_row) % rows, (col + d_col) % cols
                if truthy[here_row, here_col]:
                    return (here_row, here_col)
    return None
