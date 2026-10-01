"""Draws the beam read: what an eye sees of the compression state, round by round.

    python examples/00_blob_viz_tools/build_beam_view.py
    python examples/00_blob_viz_tools/build_beam_view.py --nonces 512      faster, weaker limit
    python examples/00_blob_viz_tools/build_beam_view.py --check

WHAT THIS PAGE IS FOR

beam_read.py prints the result and the print is the record. This draws it, because the shape of the
result is the argument and a column of numbers does not show a shape: everything sits on the floor
until round 64, where it jumps. The jump means something only against the floor.

THE PAGE IS SELF CONTAINED AND HELD

One file, no network, no CDN, no interpreter. Same convention as the other pages in this directory.
The subject is SHA-256 and a real header. It is HELD: it is built to a local path and it does not
go anywhere, and for that reason it is drawn with hand-written SVG and not a chart library.

WHAT IT MUST NOT DO

It must not draw the rounds before the nonce enters as though they were measurements. Rounds 0
through 15 are bit-identical across the sweep because the nonce sits in schedule word 15. Their
zeros are construction. They are drawn in their own shaded band and labeled, because an unlabeled
zero in a chart reads as the strongest result on it.
"""

import argparse
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import numpy

import beam_read
import out_path

INSTRUMENTS = ("beam", "harmonic")


def collect(nonces):
    """Run the sweep and reduce it to one record per round per instrument."""
    readings, target, beam_count, harmonic_count = beam_read.sweep(nonces)
    rows = []
    for round_at in beam_read.READ_AT:
        for name in INSTRUMENTS:
            features = readings[round_at][name]
            value, column = beam_read.loudest(features, target)
            bar = beam_read.null_bar(features, target, seed=round_at)
            limit = beam_read.detection_limit(features, target, bar, seed=round_at)
            rows.append({
                "round": round_at,
                "instrument": name,
                "loudest": value,
                "bar": bar,
                "limit": limit,
                "column": column,
                "fires": value > bar,
                "constructed": round_at < beam_read.FIRST_LIVE_ROUND,
            })
    return rows, {
        "nonces": nonces,
        "beam_rows": beam_count,
        "harmonic_rows": harmonic_count,
        "target_spread": float(target.std()),
        "target_levels": int(numpy.unique(target).size),
    }


def chart(rows):
    """A categorical chart: rounds across, correlation up, both instruments and the drawn bar.

    CATEGORICAL AND NOT LINEAR IN THE ROUND NUMBER. The rounds sampled are 8, 15, 16, 17, 20, 24,
    32, 48, 64, which are deliberately dense where the nonce enters and sparse after. On a linear
    axis the four interesting rounds would pile into one tenth of the width and the empty stretch
    from 48 to 64 would take a third of it.
    """
    rounds = sorted({row["round"] for row in rows})
    width, height = 760.0, 300.0
    left, right, top, bottom = 54.0, 14.0, 16.0, 40.0
    plot_width = width - left - right
    plot_height = height - top - bottom

    ceiling = max(max(row["loudest"] for row in rows), max(row["bar"] for row in rows))
    ceiling = max(0.6, ceiling * 1.12)

    def x_of(round_at):
        return left + plot_width * (rounds.index(round_at) + 0.5) / len(rounds)

    def y_of(value):
        return top + plot_height * (1.0 - value / ceiling)

    parts = []

    # The construction band, drawn first so everything else sits on top of it.
    constructed = [one for one in rounds if one < beam_read.FIRST_LIVE_ROUND]
    if constructed:
        edge = left + plot_width * len(constructed) / len(rounds)
        parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" class="band" />'
                     % (left, top, edge - left, plot_height))
        parts.append('<text x="%.1f" y="%.1f" class="bandlabel">nonce has not entered</text>'
                     % (left + 6.0, top + 14.0))
        parts.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="divide" />'
                     % (edge, top, edge, top + plot_height))

    # Horizontal guides at round fractions, labeled with the value they mean.
    for step in (0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6):
        if step > ceiling:
            continue
        y = y_of(step)
        parts.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="guide" />'
                     % (left, y, width - right, y))
        parts.append('<text x="%.1f" y="%.1f" class="tick">%.1f</text>' % (left - 8.0, y + 3.5, step))

    # The drawn null bar, as a stepped line: it is a property of the feature count and so it moves
    # between instruments and rounds instead of being one horizontal threshold.
    for name, style in (("beam", "barbeam"), ("harmonic", "barharmonic")):
        points = []
        for round_at in rounds:
            for row in rows:
                if row["round"] == round_at and row["instrument"] == name:
                    points.append("%.1f,%.1f" % (x_of(round_at), y_of(row["bar"])))
        if points:
            parts.append('<polyline points="%s" class="%s" />' % (" ".join(points), style))

    # The readings themselves.
    for name, style in (("beam", "eye"), ("harmonic", "region")):
        points = []
        for round_at in rounds:
            for row in rows:
                if row["round"] == round_at and row["instrument"] == name:
                    points.append((x_of(round_at), y_of(row["loudest"]), row))
        parts.append('<polyline points="%s" class="line %s" />'
                     % (" ".join("%.1f,%.1f" % (x, y) for x, y, _ in points), style))
        for x, y, row in points:
            shape = 'class="dot %s%s"' % (style, " fired" if row["fires"] else "")
            parts.append('<circle cx="%.1f" cy="%.1f" r="%.1f" %s />'
                         % (x, y, 5.0 if row["fires"] else 3.4, shape))
            if row["fires"]:
                parts.append('<text x="%.1f" y="%.1f" class="fires">%.3f</text>'
                             % (x - 16.0, y - 11.0, row["loudest"]))

    # The round axis.
    for round_at in rounds:
        parts.append('<text x="%.1f" y="%.1f" class="xtick">%d</text>'
                     % (x_of(round_at), height - 20.0, round_at))
    parts.append('<text x="%.1f" y="%.1f" class="axis">round of the compression function</text>'
                 % (left + plot_width / 2.0, height - 5.0))
    parts.append('<text x="%.1f" y="%.1f" class="axis vert" transform="rotate(-90 %.1f %.1f)">'
                 'loudest correlation</text>' % (16.0, top + plot_height / 2.0,
                                                 16.0, top + plot_height / 2.0))

    return ('<svg viewBox="0 0 %.0f %.0f" class="chart" role="img" '
            'aria-label="loudest correlation per round for both instruments">%s</svg>'
            % (width, height, "".join(parts)))


def table(rows):
    out = []
    for row in rows:
        classes = []
        if row["fires"]:
            classes.append("fired")
        if row["constructed"]:
            classes.append("constructed")
        out.append('<tr%s><td>%d</td><td class="name">%s</td><td>%.4f</td><td>%.4f</td>'
                   '<td>%s</td><td>%s</td><td class="why">%s</td></tr>'
                   % (' class="%s"' % " ".join(classes) if classes else "",
                      row["round"], row["instrument"], row["loudest"], row["bar"],
                      "FIRES" if row["fires"] else "null",
                      ("%.3f" % row["limit"]) if row["limit"] is not None else "-",
                      "by construction" if row["constructed"] else ""))
    return "".join(out)


def render(rows, facts):
    beam_64 = next(r["loudest"] for r in rows if r["round"] == 64 and r["instrument"] == "beam")
    harmonic_64 = next(r["loudest"] for r in rows if r["round"] == 64 and r["instrument"] == "harmonic")
    ratio = (beam_64 / harmonic_64) if harmonic_64 else 0.0

    live = [r for r in rows if not r["constructed"] and r["round"] != 64]
    worst_limit = max(r["limit"] for r in live if r["limit"] is not None)

    return TEMPLATE % {
        "chart": chart(rows),
        "table": table(rows),
        "nonces": facts["nonces"],
        "beam_rows": facts["beam_rows"],
        "harmonic_rows": facts["harmonic_rows"],
        "levels": facts["target_levels"],
        "spread": facts["target_spread"],
        "beam_64": beam_64,
        "harmonic_64": harmonic_64,
        "ratio": ratio,
        "limit": worst_limit,
        "first_live": beam_read.FIRST_LIVE_ROUND,
        "nonce_word": beam_read.NONCE_WORD,
    }


TEMPLATE = """<title>Eyes on the State</title>
<style>
  :root {
    --ink: #14181f; --dim: #5d6b7c; --face: #f5f6f4; --panel: #ffffff; --edge: #dde3e6;
    --eye: #b45309; --region: #1e5f74; --bar: #9aa7b1; --fire: #a21caf; --band: #eceef0;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --ink: #e9edf1; --dim: #8f9cab; --face: #0c1015; --panel: #151a21; --edge: #262e38;
      --eye: #f6a53d; --region: #4ec3dd; --bar: #5c6875; --fire: #e879f9; --band: #10151b;
    }
  }
  :root[data-theme="dark"] {
    --ink: #e9edf1; --dim: #8f9cab; --face: #0c1015; --panel: #151a21; --edge: #262e38;
    --eye: #f6a53d; --region: #4ec3dd; --bar: #5c6875; --fire: #e879f9; --band: #10151b;
  }
  body { background: var(--face); color: var(--ink); margin: 0;
         font: 14px/1.6 "SF Mono", "Cascadia Mono", Consolas, monospace;
         padding-block: 30px; padding-left: 20px; padding-right: 20px; }
  .sheet { max-width: 880px; margin: 0 auto; }
  h1 { font-size: 20px; letter-spacing: 0.13em; text-transform: uppercase; margin: 0 0 6px;
       font-weight: 600; text-wrap: balance; }
  .sub { color: var(--dim); margin: 0 0 24px; font-size: 12.5px; max-width: 70ch; }
  h2 { font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--dim);
       margin: 32px 0 10px; font-weight: 600; }
  p { max-width: 70ch; }
  .chart { width: 100%%; height: auto; display: block; background: var(--panel);
           border: 1px solid var(--edge); border-radius: 3px; }
  .band { fill: var(--band); }
  .bandlabel { fill: var(--dim); font-size: 9.5px; letter-spacing: 0.09em;
               text-transform: uppercase; }
  .divide { stroke: var(--edge); stroke-width: 1; stroke-dasharray: 3 3; }
  .guide { stroke: var(--edge); stroke-width: 1; }
  .tick { fill: var(--dim); font-size: 10px; text-anchor: end; font-variant-numeric: tabular-nums; }
  .xtick { fill: var(--dim); font-size: 10.5px; text-anchor: middle;
           font-variant-numeric: tabular-nums; }
  .axis { fill: var(--dim); font-size: 10px; text-anchor: middle; letter-spacing: 0.09em;
          text-transform: uppercase; }
  .line { fill: none; stroke-width: 1.8; }
  .line.eye { stroke: var(--eye); }
  .line.region { stroke: var(--region); }
  .dot.eye { fill: var(--eye); }
  .dot.region { fill: var(--region); }
  .dot.fired { stroke: var(--fire); stroke-width: 2; }
  .fires { fill: var(--fire); font-size: 11px; font-variant-numeric: tabular-nums;
           font-weight: 600; }
  .barbeam, .barharmonic { fill: none; stroke: var(--bar); stroke-width: 1.2;
                           stroke-dasharray: 4 3; }
  .key { display: flex; flex-wrap: wrap; gap: 18px; margin: 12px 0 0; font-size: 11.5px;
         color: var(--dim); }
  .key span { display: inline-flex; align-items: center; gap: 7px; }
  .swatch { width: 15px; height: 3px; border-radius: 2px; display: inline-block; }
  .scroll { overflow-x: auto; }
  table { border-collapse: collapse; font-size: 12.5px; font-variant-numeric: tabular-nums;
          min-width: 520px; }
  th, td { text-align: right; padding: 5px 14px 5px 0; }
  td.name, th.name, td.why, th.why { text-align: left; }
  th { color: var(--dim); font-weight: 600; font-size: 10px; letter-spacing: 0.12em;
       text-transform: uppercase; border-bottom: 1px solid var(--edge); }
  tr.fired td { color: var(--fire); font-weight: 600; }
  tr.constructed td { color: var(--dim); }
  td.why { color: var(--dim); font-size: 11px; }
  .note { color: var(--dim); font-size: 12px; max-width: 70ch; }
  .flag { border-left: 2px solid var(--eye); padding-left: 13px; margin: 18px 0; }
  footer { color: var(--dim); font-size: 11px; margin-top: 36px; border-top: 1px solid var(--edge);
           padding-top: 14px; max-width: 72ch; }
</style>
<div class="sheet">
  <h1>Eyes on the State</h1>
  <p class="sub">Does a line integral through the SHA-256 compression state predict the final
  digest, where a region integral could not? %(nonces)d nonces on one real header, read two ways at
  nine rounds, against a drawn null.</p>

  %(chart)s
  <div class="key">
    <span><i class="swatch" style="background: var(--eye)"></i> beam, %(beam_rows)d line integrals</span>
    <span><i class="swatch" style="background: var(--region)"></i> harmonic, %(harmonic_rows)d region integrals</span>
    <span><i class="swatch" style="background: var(--bar)"></i> drawn null bar, 95th percentile of 200 shuffles</span>
  </div>

  <h2>Why run this when the region read already said null</h2>
  <p>The earlier null was measured with six scalars, and five of them were power shares. A power
  share is invariant under rotation by construction, so that instrument could not see orientation at
  any strength. The state carries 256 numbers, one per bit. A six-dimensional rotation-averaged
  summary of a 256-dimensional object is not a test of the object.</p>
  <p>A beam is a line integral, and it is not in the span of the region rows: stacked with the
  degree-8 harmonic map it takes the rank from %(harmonic_rows)d to %(beam_rows)d, closing the whole
  kernel. It also reads passively, by occlusion, without perturbing what it reads.</p>

  <h2>The result</h2>
  <div class="scroll">
  <table>
    <tr><th>round</th><th class="name">instrument</th><th>loudest</th><th>null bar</th>
        <th>verdict</th><th>limit</th><th class="why">note</th></tr>
    %(table)s
  </table>
  </div>

  <div class="flag">
  <p>Null at every live round before 64, on both instruments. The shaded band is rounds where the
  nonce has not entered the state: the nonce sits in schedule word %(nonce_word)d and round
  <em>r</em> consumes word <em>r</em>. Every state before round %(first_live)d is bit-identical
  across the sweep. Those zeros are construction, not evidence, and they are a control: variance
  there would be a wiring bug.</p>
  <p>Round 64 is the positive control and it fires. The target is the leading zero count of state
  64. Reading state 64 is reading the answer. A null there would have meant the instrument was
  blind, alone on this page could be trusted.</p>
  </div>

  <h2>Where the eyes do win</h2>
  <p>On the one round that carries a signal, the two instruments do not read the same amount of it:
  the beam reaches <strong>%(beam_64).4f</strong> and the harmonic <strong>%(harmonic_64).4f</strong>,
  a factor of <strong>%(ratio).2f</strong> on the same state, the same target and the same null.
  That is the directional information a power share averages away, and it is a real property of the
  row type and not a claim about it.</p>
  <p>It does not help a miner. The early rounds have nothing for either instrument to find, and a
  better instrument pointed at an empty room still reads empty.</p>

  <h2>What the null is worth</h2>
  <p class="note">The weakest limit across the live rounds is %(limit).3f, a correlation below
  about that would not have been visible to this sample. The limit is measured by fading an injected
  correlation until it stops clearing the bar, not derived: an analytic floor comes out too low,
  and the rule is to draw the null and not compute it. The target takes
  %(levels)d distinct values with a spread of %(spread).4f.</p>

  <footer>Built from beam_read.py over %(nonces)d nonces on one real header shape. One
  self-contained file, no network and no interpreter. HELD: the subject is SHA-256 and the object is
  a block header.</footer>
</div>
"""


def _check():
    lines = []
    failed = 0

    rows, facts = collect(192)
    lines.append("  %d rows over %d nonces" % (len(rows), facts["nonces"]))

    # THE FREE EXACT NULL, AGAIN, HERE. The page must not be able to draw a non-zero reading for a
    # round the nonce never reached, whatever the sweep does.
    for row in rows:
        if row["constructed"] and row["loudest"] != 0.0:
            lines.append("    FAIL round %d read %.6f before the nonce entered"
                         % (row["round"], row["loudest"]))
            failed += 1
    lines.append("  rounds before the nonce enters all read exactly zero: %s"
                 % all(r["loudest"] == 0.0 for r in rows if r["constructed"]))

    # THE POSITIVE CONTROL MUST FIRE even at the reduced nonce count used for checking.
    control = [r for r in rows if r["round"] == 64]
    lines.append("  round 64 fires on both instruments: %s" % all(r["fires"] for r in control))
    if not all(r["fires"] for r in control):
        lines.append("    FAIL the positive control did not fire")
        failed += 1

    page = render(rows, facts)

    offenders = [one for one in ("http://", "https://", "//cdn", "<script") if one in page]
    lines.append("  the page references nothing external: %s" % (not offenders))
    if offenders:
        lines.append("    FAIL the page pulls %s" % offenders)
        failed += 1

    for needed in ("<title>", "background: var(--face)"):
        if needed not in page:
            lines.append("    FAIL the page is missing %s" % needed)
            failed += 1
    lines.append("  the page sets its own title and paints its own background: %s"
                 % ("<title>" in page and "background: var(--face)" in page))

    # THE BAND MUST BE DRAWN AND LABELED, because an unlabeled zero is the failure mode this page
    # was written to avoid.
    lines.append("  the construction band is drawn and labeled: %s"
                 % ('class="band"' in page and "nonce has not entered" in page))
    if 'class="band"' not in page or "nonce has not entered" not in page:
        lines.append("    FAIL the rounds before the nonce enters are not marked")
        failed += 1

    target = out_path.resolve("beam_read.html")
    lines.append("  output resolves to %s" % target)
    if os.path.dirname(os.path.abspath(target)) == HERE:
        lines.append("    FAIL the page would be written beside the builder")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="draw the beam read of the compression state")
    parser.add_argument("--out", default=None)
    parser.add_argument("--nonces", type=int, default=beam_read.NONCES)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0

    rows, facts = collect(args.nonces)
    page = render(rows, facts)
    target = out_path.resolve("beam_read.html", args.out)
    with io.open(target, "w", encoding="utf-8") as handle:
        handle.write(page)
    sys.stdout.write("  wrote %s, %d bytes\n" % (target, len(page)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
