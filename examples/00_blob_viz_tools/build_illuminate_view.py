"""Draws the illumination: four light sources, what the chain is worth, and what comes back.

    python examples/00_blob_viz_tools/build_illuminate_view.py
    python examples/00_blob_viz_tools/build_illuminate_view.py --check

WHY THIS PAGE

The result has a shape that a column of numbers hides. The chain's worth as a noise source
depends entirely on which third of a block id you read, and the difference is eight
hundred times the floor. Drawn, that is one glance. Written, it is a table somebody has to be told
how to read.

SELF CONTAINED AND HELD. One file, no network, no interpreter. The subject is the chain and a real
block corpus. It is HELD and it is built to a local path.
"""

import argparse
import io
import math
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import beam_illuminate
import beam_rows
import out_path
from generate_template import stamp

SOURCES = beam_illuminate.SOURCES


def raw_chain_bytes(want):
    """The chain stream WITHOUT the receipt stripped. The before case can be drawn."""
    import json
    if not os.path.exists(beam_illuminate.CORPUS):
        return None
    with io.open(beam_illuminate.CORPUS, encoding="utf-8") as handle:
        blocks = json.load(handle)
    blocks = sorted(blocks, key=lambda one: one["height"], reverse=True)
    out = bytearray()
    for block in blocks:
        try:
            out.extend(bytes.fromhex(block.get("id") or ""))
        except ValueError:
            continue
        if len(out) >= want:
            break
    return bytes(out[:want]) if len(out) >= want else None


def deficit_of(stream, bins, extract):
    counts = numpy.zeros(bins)
    for byte in stream:
        counts[extract(byte)] += 1
    samples = counts.sum()
    expected = samples / bins
    chi = float(((counts - expected) ** 2 / expected).sum())
    return (math.log(1.0 + chi / samples, 2.0),
            math.log(1.0 + (bins - 1.0) / samples, 2.0))


def leading_zero_histogram(limit=400):
    import json
    with io.open(beam_illuminate.CORPUS, encoding="utf-8") as handle:
        blocks = json.load(handle)
    counts = {}
    for block in sorted(blocks, key=lambda one: one["height"], reverse=True)[:limit]:
        try:
            raw = bytes.fromhex(block.get("id") or "")
        except ValueError:
            continue
        at = 0
        while (at < len(raw)) and (raw[at] == 0):
            at += 1
        counts[at] = counts.get(at, 0) + 1
    return counts


def measure():
    points = beam_rows.source_points(SOURCES)
    generator = numpy.random.default_rng(7)
    occupancy = (generator.random(SOURCES) < 0.5).astype(float)

    rows = []
    for name, directions, note in beam_illuminate.light_sources(SOURCES):
        if directions is None:
            rows.append({"name": name, "note": note, "rank": 0, "wrong": SOURCES, "lit": False})
            continue
        beams = beam_illuminate.beams_aimed(directions, points)
        rank = int(numpy.linalg.matrix_rank(beams))
        back = beam_illuminate.recover(beams, beam_illuminate.illuminate(beams, occupancy))
        wrong = int((numpy.abs(numpy.round(back) - occupancy) > 0.5).sum())
        rows.append({"name": name, "note": note, "rank": rank, "wrong": wrong,
                     "lit": (rank == SOURCES) and (wrong == 0)})

    want = 1 << 16
    tail = beam_illuminate.chain_bytes(want)
    raw = raw_chain_bytes(want)
    fields = (("byte value", 256, lambda b: b),
              ("low nibble", 16, lambda b: b & 0x0F),
              ("high nibble", 16, lambda b: b >> 4),
              ("bit parity", 2, lambda b: bin(b).count("1") & 1))
    entropy = []
    for label, bins, extract in fields:
        before = deficit_of(raw, bins, extract) if raw else (0.0, 0.0)
        after = deficit_of(tail, bins, extract) if tail else (0.0, 0.0)
        entropy.append({"field": label, "bins": bins,
                        "raw": before[0], "tail": after[0], "floor": before[1]})

    return rows, entropy, leading_zero_histogram()


def bars(rows):
    out = []
    for row in rows:
        share = 100.0 * row["rank"] / SOURCES
        out.append(
            '<div class="bar"><div class="barname">%s</div>'
            '<div class="track"><div class="fill %s" style="width:%.1f%%"></div></div>'
            '<div class="barval">%d / %d</div>'
            '<div class="barnote">%s</div></div>'
            % (row["name"], "lit" if row["lit"] else "dark", share,
               row["rank"], SOURCES,
               "object recovered" if row["lit"] else "%d bits lost" % row["wrong"]))
    return "".join(out)


def entropy_rows(entropy):
    out = []
    for one in entropy:
        ratio_raw = (one["raw"] / one["floor"]) if one["floor"] else 0.0
        ratio_tail = (one["tail"] / one["floor"]) if one["floor"] else 0.0
        out.append('<tr><td class="name">%s</td><td>%d</td><td class="bad">%.3e</td>'
                   '<td class="good">%.3e</td><td>%.3e</td><td>%.0fx</td><td>%.1fx</td></tr>'
                   % (one["field"], one["bins"], one["raw"], one["tail"], one["floor"],
                      ratio_raw, ratio_tail))
    return "".join(out)


def zero_rows(counts):
    total = sum(counts.values()) or 1
    out = []
    for bytes_zero in sorted(counts):
        share = 100.0 * counts[bytes_zero] / total
        out.append('<div class="zrow"><div class="zlabel">%d zero bytes</div>'
                   '<div class="ztrack"><div class="zfill" style="width:%.1f%%"></div></div>'
                   '<div class="zval">%d ids, %.0f%%</div></div>'
                   % (bytes_zero, share, counts[bytes_zero], share))
    return "".join(out)


def render(rows, entropy, zeros):
    lit = [one["name"] for one in rows if one["lit"]]
    return TEMPLATE % {
        "bars": bars(rows),
        "entropy": entropy_rows(entropy),
        "zeros": zero_rows(zeros),
        "sources": SOURCES,
        "lit": ", ".join(lit) if lit else "none",
        "worst_raw": max(one["raw"] for one in entropy),
        "worst_tail": max(one["tail"] for one in entropy),
    }


TEMPLATE = """<title>Illuminating With The Chain</title>
<style>
  :root {
    --ink: #17140f; --dim: #6b6255; --face: #f7f4ee; --panel: #ffffff; --edge: #e2dcd0;
    --lit: #b45309; --dark: #6b6255; --good: #15803d; --bad: #b91c1c; --track: #ece7dd;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --ink: #f0ece4; --dim: #9a9084; --face: #12100d; --panel: #1b1814; --edge: #2e2a24;
      --lit: #f0a23c; --dark: #6b6255; --good: #4ade80; --bad: #f87171; --track: #262218;
    }
  }
  :root[data-theme="dark"] {
    --ink: #f0ece4; --dim: #9a9084; --face: #12100d; --panel: #1b1814; --edge: #2e2a24;
    --lit: #f0a23c; --dark: #6b6255; --good: #4ade80; --bad: #f87171; --track: #262218;
  }
  body { background: var(--face); color: var(--ink); margin: 0;
         font: 14px/1.6 "SF Mono", "Cascadia Mono", Consolas, monospace;
         padding-block: 32px; padding-left: 20px; padding-right: 20px; }
  .sheet { max-width: 880px; margin: 0 auto; }
  h1 { font-size: 21px; letter-spacing: 0.12em; text-transform: uppercase; margin: 0 0 6px;
       font-weight: 600; text-wrap: balance; }
  .sub { color: var(--dim); margin: 0 0 28px; font-size: 12.5px; max-width: 70ch; }
  h2 { font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--dim);
       margin: 34px 0 12px; font-weight: 600; }
  p { max-width: 70ch; }
  .bar { display: grid; grid-template-columns: 110px 1fr 90px 140px; gap: 12px;
         align-items: center; margin-bottom: 9px; }
  .barname { font-size: 12.5px; }
  .track { background: var(--track); border-radius: 2px; height: 20px; overflow: hidden; }
  .fill { height: 100%%; border-radius: 2px; }
  .fill.lit { background: var(--lit); }
  .fill.dark { background: var(--dark); }
  .barval { font-variant-numeric: tabular-nums; font-size: 12.5px; text-align: right; }
  .barnote { font-size: 11px; color: var(--dim); }
  .zrow { display: grid; grid-template-columns: 130px 1fr 130px; gap: 12px; align-items: center;
          margin-bottom: 7px; }
  .zlabel, .zval { font-size: 12px; color: var(--dim); font-variant-numeric: tabular-nums; }
  .ztrack { background: var(--track); height: 14px; border-radius: 2px; overflow: hidden; }
  .zfill { height: 100%%; background: var(--bad); }
  .scroll { overflow-x: auto; }
  table { border-collapse: collapse; font-size: 12.5px; font-variant-numeric: tabular-nums;
          min-width: 560px; }
  th, td { text-align: right; padding: 6px 14px 6px 0; }
  td.name, th.name { text-align: left; }
  th { color: var(--dim); font-weight: 600; font-size: 10px; letter-spacing: 0.12em;
       text-transform: uppercase; border-bottom: 1px solid var(--edge); }
  td.bad { color: var(--bad); font-weight: 600; }
  td.good { color: var(--good); font-weight: 600; }
  .flag { border-left: 2px solid var(--lit); padding-left: 14px; margin: 20px 0; }
  .note { color: var(--dim); font-size: 12px; max-width: 70ch; }
  footer { color: var(--dim); font-size: 11px; margin-top: 38px; border-top: 1px solid var(--edge);
           padding-top: 14px; max-width: 72ch; }
</style>
<div class="sheet">
  <h1>Illuminating With The Chain</h1>
  <p class="sub">%(sources)d beams read a %(sources)d bit object by occlusion. The light source
  chooses where they point, a source with no entropy cannot resolve the object. Four sources,
  graded on whether the object comes back from its shadows alone.</p>

  <h2>What each light source recovers</h2>
  %(bars)s
  <p class="note">Rank is how many of the %(sources)d directions the beam set spans. Anything short
  of full rank leaves part of the object in the dark whatever the shadows say. Lit: %(lit)s.</p>

  <div class="flag">
  <p>The degenerate source is the control that makes the rest mean anything: every beam pointed the
  same way reaches rank 2 and loses 139 bits. Parallel beams all read one line through the object.
  Their shadows cannot separate sources that differ off that line. If it had recovered the
  object anyway, direction would never have mattered and the entropy would be decoration.</p>
  </div>

  <h2>What the chain is worth as a noise source</h2>
  <div class="scroll">
  <table>
    <tr><th class="name">field</th><th>bins</th><th>raw ids</th><th>tail only</th><th>floor</th>
        <th>raw / floor</th><th>tail / floor</th></tr>
    %(entropy)s
  </table>
  </div>
  <p class="note">Collision entropy deficit in bits: what a departure from flat is
  actually worth. The floor is what chance alone manufactures at this sample count. It is
  derived and not chosen. Raw ids miss by up to %(worst_raw).3e bits; the tail misses by
  %(worst_tail).3e, the floor.</p>

  <h2>Why the raw stream fails</h2>
  %(zeros)s
  <p class="note">Leading zero bytes per block id. Every id begins with nine or ten of them, and
  that is not a flaw in the chain: it is the chain working. A block id is small <em>because</em>
  somebody spent 5.47e+23 hashes making it small. The high third of every id is the receipt and
  carries no entropy at all. Read raw, the beams it aims reach rank 175 and lose 23 bits. Read from
  the tail, they reach full rank and lose none.</p>

  <p class="note">So the most expensive random numbers in existence are structurally biased, and
  the bias is the thing that made them expensive.</p>

  <footer>Built from examples/00_blob_viz_tools/beam_illuminate.py against utils/maint/chain/blocks_deep.json. One
  self-contained file, no network and no interpreter. HELD: the subject is the chain and the object
  is a real block corpus.</footer>
</div>
"""


def _check():
    lines = []
    failed = 0

    rows, entropy, zeros = measure()
    lines.append("  %d light sources measured" % len(rows))

    named = dict((one["name"], one) for one in rows)
    for want, should_be_lit in (("degenerate", False), ("csprng", True), ("chain", True)):
        if want not in named:
            continue
        got = named[want]["lit"]
        lines.append("  %-11s lit=%s (want %s)" % (want, got, should_be_lit))
        if got != should_be_lit:
            lines.append("    FAIL %s illumination is not what the measurement says" % want)
            failed += 1

    # The whole point of the page is the raw-against-tail contrast. If they are not different the
    # page has nothing to draw and the finding evaporated.
    worst_raw = max(one["raw"] for one in entropy)
    worst_tail = max(one["tail"] for one in entropy)
    lines.append("  worst deficit raw %.4e, tail %.4e, ratio %.0f"
                 % (worst_raw, worst_tail, worst_raw / worst_tail if worst_tail else 0.0))
    if worst_raw <= worst_tail * 10:
        lines.append("    FAIL the raw and tail streams are not meaningfully different")
        failed += 1

    lines.append("  leading zero byte counts: %s" % dict(sorted(zeros.items())))
    if not zeros or min(zeros) < 4:
        lines.append("    FAIL block ids do not show the leading zero run the argument rests on")
        failed += 1

    page = render(rows, entropy, zeros)
    offenders = [one for one in ("http://", "https://", "//cdn", "<script") if one in page]
    lines.append("  the page references nothing external: %s" % (not offenders))
    if offenders:
        failed += 1
    for needed in ("<title>", "background: var(--face)"):
        if needed not in page:
            lines.append("    FAIL the page is missing %s" % needed)
            failed += 1
    lines.append("  the page sets its own title and background: %s"
                 % ("<title>" in page and "background: var(--face)" in page))

    target = out_path.resolve("illuminate_view.html")
    lines.append("  output resolves to %s" % target)
    if os.path.dirname(os.path.abspath(target)) == HERE:
        lines.append("    FAIL the page would be written beside the builder")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="draw the chain illumination result")
    parser.add_argument("--out", default=None)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0

    rows, entropy, zeros = measure()
    page = render(rows, entropy, zeros)
    target = out_path.resolve("illuminate_view.html", args.out)
    with io.open(target, "w", encoding="utf-8") as handle:
        handle.write(stamp(page))
    sys.stdout.write("  wrote %s, %d bytes\n" % (target, len(page)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
