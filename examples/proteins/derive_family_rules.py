#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRO-x-003
#
# Derive the emergent conformational families of the corpus and write their quirks as a ruleset
# beside the Ramachandran rules.
#
#   Usage:  python examples/proteins/derive_family_rules.py [--write]
#
# A family here is not a fold name or a function label. It is a grouping the proteins fall into by
# their own Ramachandran signature, the occupancy of the two-degree grid coarsened to the resolution
# a null supports. Three things keep this honest and are all in this file:
#
#   The resolution is drawn, not chosen. A protein of a few hundred residues cannot fill the 32400
#   two-degree cells, so at that grid its signature is sampling noise and a random draw of the same
#   count reaches the same distance from the corpus. Coarsening to ten degrees is where a live
#   signature sits farthest above that residue-count-matched null; the sweep is REPORTED here.
#
#   The count is drawn, not chosen. The number of families is the gap statistic (Tibshirani 2001)
#   against a structure-free reference uniform over the data's own PCA box, so a lower live
#   dispersion than the null is real grouping and not the data merely being tighter than a blob.
#
#   The method is controlled. Before any family is written, the same pipeline is run on synthetic
#   proteins built from known archetypes. If it does not recover that planted split, this refuses to
#   write a ruleset, because a grouping found by a method that cannot find a known one means nothing.
#
# What the corpus actually shows, with the control passing, is a near-continuum: the gap keeps
# improving as the count rises, with only a weak first peak, so the families are soft partitions of a
# helix-rich to sheet-rich continuum and are labeled as such. A family's quirk is the set of grid
# cells where it sits more than the whole corpus does, drawn as an excess over the corpus marginal
# and carried with its counts.

import glob
import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))
sys.path.insert(0, os.path.join(ROOT, "examples", "proteins"))

import numpy  # noqa: E402
from representation.structure.protein import walk, internal_coords  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")
OUT = os.path.join(ROOT, "examples", "proteins", "family_rules.py")

GRID_DEGREES = 10.0                          # the null-selected resolution; the sweep is reported
K = int(round(360.0 / GRID_DEGREES))
KMAX = 14
BREF = 6
RESTARTS = 4
CONTROL_K = 4                                # archetypes planted in the positive control
CONTROL_SPREAD = 15.0
rng = numpy.random.default_rng(20260916)


def signature(text, degrees):
    size = degrees
    side = int(round(360.0 / degrees))
    v = numpy.zeros(side * side)
    for run in walk(text, least=1):
        n = len(run)
        if n < 4:
            continue
        _, _, dih = internal_coords(run)
        deg = numpy.degrees(dih)
        for r in range(1, n // 3):
            a_psi, a_phi = 3 * r, 3 * r + 2
            if a_phi < n:
                cp = int((deg[a_phi] + 180) // size) % side
                cq = int((deg[a_psi] + 180) // size) % side
                v[cp * side + cq] += 1
    return v


def hellinger(v):
    s = v.sum()
    return numpy.sqrt(v / s) if s else v


def sqdist(X, C):
    return (X * X).sum(1)[:, None] - 2.0 * (X @ C.T) + (C * C).sum(1)[None, :]


def kmeans(X, k, seed):
    r = numpy.random.default_rng(seed)
    best = None
    for _ in range(RESTARTS):
        centers = [X[r.integers(len(X))]]
        for _ in range(k - 1):
            d = numpy.maximum(sqdist(X, numpy.array(centers)).min(1), 0.0)
            p = d / d.sum() if d.sum() > 0 else None
            centers.append(X[r.choice(len(X), p=p)] if p is not None else X[r.integers(len(X))])
        C = numpy.array(centers)
        lab = numpy.zeros(len(X), dtype=int)
        for _ in range(40):
            lab = sqdist(X, C).argmin(1)
            newC = numpy.array([X[lab == j].mean(0) if (lab == j).any() else C[j] for j in range(k)])
            if numpy.allclose(newC, C):
                break
            C = newC
        w = float(((X - C[lab]) ** 2).sum())
        if best is None or w < best[0]:
            best = (w, lab, C)
    return best


def gap_kstar(X, kmax, out):
    """The gap statistic against a uniform PCA-box reference; returns k*, labels, centroids."""
    Xc = X - X.mean(0)
    _, _, Vt = numpy.linalg.svd(Xc, full_matrices=False)
    Xr = Xc @ Vt.T
    lo, hi = Xr.min(0), Xr.max(0)
    gaps, sds, keep = {}, {}, {}
    for k in range(1, kmax + 1):
        w_live, lab, C = kmeans(X, k, 100 + k)
        logs = numpy.array([numpy.log(kmeans(rng.uniform(lo, hi, size=Xr.shape) @ Vt,
                                             k, 500 + k * 10 + b)[0]) for b in range(BREF)])
        gaps[k] = float(logs.mean() - numpy.log(w_live))
        sds[k] = float(logs.std() * numpy.sqrt(1 + 1.0 / BREF))
        keep[k] = (lab, C)
        if out:
            out.write("    k=%2d  gap=%.4f  sd=%.4f\n" % (k, gaps[k], sds[k]))
    kstar = kmax
    for k in range(1, kmax):
        if gaps[k] >= gaps[k + 1] - sds[k + 1]:
            kstar = k
            break
    return kstar, keep[kstar][0], keep[kstar][1]


def positive_control(out):
    """Run the whole pipeline on planted archetypes; return whether it recovers them exactly."""
    side = K
    centers = [(-63, -43), (-120, 130), (-75, 145), (60, 45)][:CONTROL_K]
    X, truth = [], []
    for ti, (cphi, cpsi) in enumerate(centers):
        for _ in range(100):
            phis = rng.normal(cphi, CONTROL_SPREAD, 300)
            psis = rng.normal(cpsi, CONTROL_SPREAD, 300)
            v = numpy.zeros(side * side)
            cp = ((phis + 180) // GRID_DEGREES).astype(int) % side
            cq = ((psis + 180) // GRID_DEGREES).astype(int) % side
            for a, b in zip(cp, cq):
                v[a * side + b] += 1
            X.append(hellinger(v)); truth.append(ti)
    X = numpy.array(X); truth = numpy.array(truth)
    kstar, lab, _ = gap_kstar(X, CONTROL_K + 4, None)
    _, lab_at_true, _ = kmeans(X, CONTROL_K, 42)
    purity = sum(numpy.bincount(truth[lab_at_true == j]).max()
                 for j in range(CONTROL_K) if (lab_at_true == j).any()) / len(X)
    out.write("  positive control: planted K=%d, recovered k*=%d, purity=%.3f\n"
              % (CONTROL_K, kstar, purity))
    return (kstar == CONTROL_K) and (purity > 0.98)


def resolution_sweep(texts, out):
    """Report where a live signature sits farthest above its residue-count-matched null."""
    out.write("  resolution sweep (live vs residue-count-matched marginal null, Jensen-Shannon):\n")
    for degrees in (2.0, 4.0, 10.0, 20.0, 45.0):
        vecs = [s for s in (signature(t, degrees) for t in texts) if s.sum() >= 20]
        marg = numpy.sum(vecs, axis=0); marg = marg / marg.sum()

        def js(p, q):
            m = 0.5 * (p + q); keep = m > 0
            p, q, m = p[keep], q[keep], m[keep]
            kl = lambda a, b: float((a[a > 0] * numpy.log2(a[a > 0] / b[a > 0])).sum())
            return 0.5 * kl(p, m) + 0.5 * kl(q, m)

        live, null = [], []
        for v in vecs:
            t = v.sum()
            live.append(js(v / t, marg))
            d = rng.multinomial(int(t), marg).astype(float)
            null.append(js(d / d.sum(), marg))
        live, null = numpy.array(live), numpy.array(null)
        out.write("    %5.1f deg  live med=%.4f  null med=%.4f  gap=%.4f\n"
                  % (degrees, numpy.median(live), numpy.median(null),
                     numpy.median(live) - numpy.median(null)))


def basin(cell):
    cp, cq = divmod(cell, K)
    return (-180 + GRID_DEGREES * cp + GRID_DEGREES / 2, -180 + GRID_DEGREES * cq + GRID_DEGREES / 2)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    write = "--write" in sys.argv

    texts = []
    for path in sorted(glob.glob(os.path.join(CORPORA, "pdb_*.txt"))):
        with open(path, encoding="utf-8", errors="replace") as handle:
            texts.append(handle.read())
    if not texts:
        out.write("no corpus. Run examples/proteins/build_corpus.py first.\n")
        out.flush()
        return 1
    out.write("  corpus: %d deposits\n\n" % len(texts))

    resolution_sweep(texts[:min(len(texts), 1500)], out)
    out.write("\n")

    if not positive_control(out):
        out.write("\n  the positive control did not recover its planted split. Refusing to write a\n")
        out.write("  ruleset: a grouping found by a method that cannot find a known one means nothing.\n")
        out.flush()
        return 1

    vecs = [signature(t, GRID_DEGREES) for t in texts]
    usable = [v for v in vecs if v.sum() >= 20]
    X = numpy.array([hellinger(v) for v in usable])
    counts = numpy.array([v.sum() for v in usable])
    marg = numpy.sum(usable, axis=0); marg = marg / marg.sum()
    out.write("\n  gap statistic over the corpus:\n")
    kstar, lab, _ = gap_kstar(X, KMAX, out)
    out.write("\n  emergent families: k* = %d (soft partitions of a continuum)\n" % kstar)

    families = []
    for j in range(kstar):
        members = numpy.where(lab == j)[0]
        mean_sig = numpy.mean([usable[m] / usable[m].sum() for m in members], axis=0)
        excess = mean_sig - marg
        quirk_cells = [c for c in numpy.argsort(excess)[::-1] if excess[c] > 0][:8]
        quirks = [(int(c), round(float(mean_sig[c]), 4), round(float(marg[c]), 4),
                   round(float(excess[c]), 4)) for c in quirk_cells]
        families.append({"members": int(len(members)), "quirks": quirks})
        top = ", ".join("phi%+.0f/psi%+.0f +%.1f%%" % (basin(c)[0], basin(c)[1], 100 * ex)
                        for c, _, _, ex in quirks[:3])
        out.write("    family %d: %4d proteins  quirk basins: %s\n" % (j, len(members), top))

    if write:
        write_module(len(texts), len(usable), kstar, families)
        out.write("\n  wrote %s\n" % OUT)
    else:
        out.write("\n  add --write to emit %s\n" % os.path.basename(OUT))
    out.flush()
    return 0


def write_module(deposits, usable, kstar, families):
    lines = []
    lines.append("#!/usr/bin/env python3")
    lines.append("# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>")
    lines.append("# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR "
                 "LicenseRef-Educational")
    # The machine-read number, not an informal label. This emitted "PRO-RULES-FAMILY", which
    # catalog.py cannot parse, so --assign inserted a real PRO-x-004 under the SPDX line and the
    # generated file carried two lines both spelled "# Catalog: ". That pair is what made deleting
    # the load-bearing one look like removing a duplicate, and it happened.
    lines.append("# Catalog: PRO-x-004")
    lines.append("#")
    lines.append("# GENERATED by examples/proteins/derive_family_rules.py. Do not edit by hand;")
    lines.append("# regenerate from the corpus. Each family is a soft partition of a helix-rich to")
    lines.append("# sheet-rich continuum, not a discrete kind; the generator's positive control and")
    lines.append("# gap statistic are what license reading these as families at all.")
    lines.append("#")
    lines.append("# Derived from %d deposits (%d with a usable signature) at a %g-degree grid."
                 % (deposits, usable, GRID_DEGREES))
    lines.append("")
    lines.append("GRID_DEGREES = %g" % GRID_DEGREES)
    lines.append("CELLS_PER_AXIS = %d" % K)
    lines.append("")
    lines.append("# One entry per emergent family. `quirks` is (cell, family_fraction, "
                 "corpus_fraction, excess),")
    lines.append("# the grid cells where the family sits more than the whole corpus does, most in "
                 "excess first.")
    lines.append("FAMILIES = [")
    for fam in families:
        lines.append("    {\"members\": %d, \"quirks\": [" % fam["members"])
        for q in fam["quirks"]:
            lines.append("        (%d, %g, %g, %g)," % q)
        lines.append("    ]},")
    lines.append("]")
    lines.append("")
    lines.append("")
    lines.append("def cell_of(phi_degrees, psi_degrees):")
    lines.append("    \"\"\"The grid cell a (phi, psi) in degrees falls in, wrapping both axes.\"\"\"")
    lines.append("    side = CELLS_PER_AXIS")
    lines.append("    cp = int((phi_degrees + 180) // GRID_DEGREES) % side")
    lines.append("    cq = int((psi_degrees + 180) // GRID_DEGREES) % side")
    lines.append("    return cp * side + cq")
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
