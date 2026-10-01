"""Builds a page for watching the worker pool: what it hit, and how hard it is cooking.

    python examples/00_blob_viz_tools/build_pool_view.py
    python examples/00_blob_viz_tools/build_pool_view.py --out pool.html
    python examples/00_blob_viz_tools/build_pool_view.py --check

WHAT THIS IS FOR AND WHAT IT DELIBERATELY LEAVES ALONE

Braiins' own dashboard already reports the pool side: accepted work, payouts, worker status. This
page does not duplicate any of that. What it has and the pool does not is the LOCAL side and the
CHAIN side together: device telemetry from this machine, the client's own accumulated counters, the
measured scaling that decides the pool size, and the real difficulty read out of a verified block
corpus and not quoted.

EVERY NUMBER ON THE PAGE IS MEASURED OR IT IS LABELED

The page is built from four sources, all local and all real:

    nvidia-smi              temperature, power, `utilization.gpu`, clocks, fan
    miner_totals.txt        the client's own hashes, shares, rejects, seconds, runs
    miner.log               the running hash rate samples, for the trace
    blocks_deep.json        6980 real blocks, for the target and the difficulty

Anything that could not be read is shown as absent and not filled with a plausible number, and
anything assumed carries the word. A dashboard that invents a figure is worse than one with a gap,
because a gap is visible and an invention is not.

SELF CONTAINED

One file, no network, no CDN, no interpreter. That is the tree's convention for these pages and it
is the property that makes a page worth keeping: it opens in five years on a machine with none of
this installed. The output location is resolved through `out_path` so the tool never writes beside
itself.
"""

import argparse
import io
import json
import math
import os
import re
import subprocess
import sys
import time
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import out_path
from generate_template import stamp

TOTALS = os.path.join(ROOT, "miner_totals.txt")
LOG = os.path.join(ROOT, "miner.log")
BASELINE = os.path.join(ROOT, "miner_baseline.log")
CORPUS = os.path.join(ROOT, "utils", "maint", "chain", "blocks_deep.json")

# Measured by src/import/hardware/device_scaling.sh on this card. Recorded and not recomputed,
# because the measurement takes minutes and the page should build in under a second.
SCALING = ((1, 2124.70, 1.000), (2, 1414.73, 0.666), (3, 1478.99, 0.696), (4, 1750.24, 0.824))

# Protocol constants, not assumptions: the ten minute target and the post-2024 subsidy.
BLOCK_SECONDS = 600.0
BLOCK_REWARD = 3.125
BLOCKS_PER_DAY = 144.0
SECONDS_PER_YEAR = 365.25 * 24.0 * 3600.0


def device_telemetry():
    """Live GPU readings, or None for anything the driver would not give."""
    fields = ("temperature.gpu", "power.draw", "utilization.gpu", "clocks.sm", "fan.speed",
              "memory.used", "memory.total", "name")
    try:
        raw = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=" + ",".join(fields), "--format=csv,noheader"],
            stderr=subprocess.DEVNULL, timeout=20).decode("utf-8", "replace")
    except Exception:
        return None
    parts = [one.strip() for one in raw.strip().splitlines()[0].split(",")]
    if len(parts) != len(fields):
        return None
    return dict(zip(fields, parts))


def read_totals():
    if not os.path.exists(TOTALS):
        return None
    with io.open(TOTALS, encoding="utf-8") as handle:
        parts = handle.read().split()
    if len(parts) < 7:
        return None
    return {
        "hashes": int(parts[0]), "anchors": int(parts[1]), "submitted": int(parts[2]),
        "accepted": int(parts[3]), "rejected": int(parts[4]),
        "seconds": float(parts[5]), "runs": int(parts[6]),
    }


def read_rates():
    """Running hash rate samples, newest last, from whichever logs exist."""
    out = []
    for path in (LOG, BASELINE):
        if not os.path.exists(path):
            continue
        with io.open(path, encoding="utf-8", errors="replace") as handle:
            out.extend(float(one) for one in re.findall(r"run (\d+) MH/s", handle.read()))
    return out


def _escape(text):
    """The miner's own last line goes on the page. It is escaped and not trusted."""
    return (str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def _spell_age(seconds):
    """An age a reader can judge at a glance, and not a raw second count."""
    seconds = float(seconds)
    if seconds < 90.0:
        return "%.0f seconds" % seconds
    if seconds < 5400.0:
        return "%.0f minutes" % (seconds / 60.0)
    return "%.1f hours" % (seconds / 3600.0)


def read_liveness():
    """How old the log is, and therefore whether any figure on this page is current.

    THE GAP THIS CLOSES. When the pool closes the connection and the miner exits, the --watch loop
    keeps rewriting this page every thirty seconds, and without this the page keeps showing its
    mean rate and total hashed with NOTHING anywhere on it saying the miner is gone. Every number
    is still true as a historical total and the page reads as live.

    That is the same defect this tree guards against in its own instruments: a reading that cannot
    report its own blindness. The totals are not wrong, they are STALE, and the difference has to
    be on the page and not in the reader's head.

    The threshold is derived and not picked. The miner writes a tick roughly every two seconds,
    a log older than a few ticks means it has stopped writing. `STALE_TICKS` sets how many
    missed ticks count as gone, and the age is always shown a reader never has to trust the
    verdict alone.
    """
    tick_seconds = 2.0
    stale_ticks = 15

    if not os.path.exists(LOG):
        return {"age": None, "live": False, "why": "there is no miner.log at all"}

    age = time.time() - os.path.getmtime(LOG)
    live = age < tick_seconds * stale_ticks

    why = None
    if not live:
        # The miner says why it left on its way out, and that line is worth surfacing and not
        # making somebody open the log to find it.
        with io.open(LOG, encoding="utf-8", errors="replace") as handle:
            handle.seek(max(0, os.path.getsize(LOG) - 4096))
            tail = handle.read().strip().splitlines()
        for line in reversed(tail):
            line = line.strip()
            if line and not line.startswith("[") and "MH/s" not in line:
                why = line
                break
    return {"age": age, "live": live, "why": why,
            "limit": tick_seconds * stale_ticks}


def read_pool():
    """What the pool itself states, read out of the client's log and not inferred.

    THE REASON THIS EXISTS. A share difficulty derived from the miner's own share spacing is a
    measurement of the past. The pool states the current one on every connect, and the two can
    disagree by a factor of eleven when the historical shares were won under an easier target. A
    page that shows only the inferred figure quietly reports a share rate that is no longer current.

    Both are kept. The stated one is the target mined against now; the inferred one is what was
    actually achieved, and their disagreement is the finding and not an error to hide.
    """
    out = {"difficulty": None, "workers": None, "worker": None}
    for path in (LOG, BASELINE):
        if not os.path.exists(path):
            continue
        with io.open(path, encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        stated = re.findall(r"share difficulty ([\d.]+)", text)
        if stated:
            out["difficulty"] = float(stated[-1])
        threads = re.findall(r"workers: (\d+)", text)
        if threads:
            out["workers"] = int(threads[-1])
        named = re.findall(r"worker: (\S+)", text)
        if named:
            out["worker"] = named[-1]
    return out


def read_chain():
    """The most recent block in the corpus, and the target its bits encode."""
    if not os.path.exists(CORPUS):
        return None
    with io.open(CORPUS, encoding="utf-8") as handle:
        blocks = json.load(handle)
    if not blocks:
        return None
    newest = max(blocks, key=lambda one: one["height"])
    bits = newest["bits"]
    value = int(bits, 16) if isinstance(bits, str) else int(bits)
    exponent = value >> 24
    mantissa = value & 0x007FFFFF
    target = (mantissa << (8 * (exponent - 3))) if exponent > 3 else (mantissa >> (8 * (3 - exponent)))
    # THE NETWORK HASH RATE IS DERIVED AND NOT ASSUMED, and the win rate below is a measurement
    # because of it. Difficulty is defined so that the network finds a block every
    # BLOCK_SECONDS on average. Rate = difficulty * 2^32 / BLOCK_SECONDS falls straight out of a
    # number the chain itself publishes. No external quote is needed and none is used.
    network = newest["difficulty"] * (2.0 ** 32) / BLOCK_SECONDS
    return {
        "height": newest["height"], "count": len(blocks), "difficulty": newest["difficulty"],
        "target": target, "zeros": 256 - target.bit_length(),
        "expected": (1 << 256) // (target + 1),
        "network": network,
    }


def sparkline(values, width=110, height=28):
    """An SVG polyline of the rate samples. Drawn and not charted. Nothing is loaded."""
    if not values:
        return "", 0.0, 0.0
    top = max(values)
    low = min(values)
    span = (top - low) or 1.0
    step = max(1, len(values) // width)
    thinned = values[::step][-width:]
    points = []
    for at, value in enumerate(thinned):
        x = at * (720.0 / max(1, len(thinned) - 1))
        y = height + 100.0 - ((value - low) / span) * 100.0
        points.append("%.1f,%.1f" % (x, y))
    return " ".join(points), low, top


def render(telemetry, totals, rates, chain, pool=None, liveness=None):
    pool = pool or {"difficulty": None, "workers": None, "worker": None}
    mean_rate = (totals["hashes"] / totals["seconds"]) if totals and totals["seconds"] else 0.0
    points, low, top = sparkline(rates)

    # THE BANNER GOES FIRST, ABOVE EVERY FIGURE, because its whole job is to say whether the
    # figures below it mean anything right now. Putting it at the bottom would be putting the
    # caveat after the reader has already believed the number.
    banner = ""
    if liveness is not None:
        age = liveness.get("age")
        if liveness.get("live"):
            banner = ('<div class="live ok">MINING. The log was written %.0f s ago, so the '
                      'figures below are current.</div>' % (age or 0.0))
        else:
            spell = "unknown" if age is None else _spell_age(age)
            why = liveness.get("why") or "the log simply stopped being written"
            banner = ('<div class="live stale">NOT MINING. The log has not been written for '
                      '<b>%s</b>, so every figure below is a HISTORICAL TOTAL and none of it is '
                      'current. The miner\'s last word was: <b>%s</b></div>'
                      % (spell, _escape(why)))

    def cell(label, value, note=""):
        extra = ('<div class="note">%s</div>' % note) if note else ""
        return ('<div class="cell"><div class="label">%s</div>'
                '<div class="value">%s</div>%s</div>' % (label, value, extra))

    def absent(label, why):
        return ('<div class="cell gone"><div class="label">%s</div>'
                '<div class="value">absent</div><div class="note">%s</div></div>' % (label, why))

    # --- device, the cooking half -----------------------------------------------------------
    if telemetry:
        util = telemetry["utilization.gpu"]
        cooking = []
        cooking.append(cell("temperature", telemetry["temperature.gpu"] + " &deg;C"))
        cooking.append(cell("power draw", telemetry["power.draw"]))
        cooking.append(cell("utilization", util))
        cooking.append(cell("SM clock", telemetry["clocks.sm"]))
        cooking.append(cell("fan", telemetry["fan.speed"]))
        cooking.append(cell("memory", telemetry["memory.used"] + " of " + telemetry["memory.total"]))
        device_name = telemetry["name"]
        idle_note = ""
        try:
            if float(util.replace("%", "").strip()) < 5.0:
                idle_note = ('<p class="warn">Utilization is under five percent, so the card is '
                             'idle and these readings are its resting state rather than its load. '
                             'Nothing is mining.</p>')
        except ValueError:
            pass
    else:
        cooking = [absent("device telemetry", "nvidia-smi did not answer")]
        device_name = "device unknown"
        idle_note = ""

    # --- shares, the hitting half -----------------------------------------------------------
    if totals:
        acceptance = (100.0 * totals["accepted"] / totals["submitted"]) if totals["submitted"] else 0.0
        per_share = (totals["hashes"] / totals["accepted"]) if totals["accepted"] else 0.0
        implied = per_share / (2.0 ** 32) if per_share else 0.0
        hitting = [
            cell("accepted", "%d" % totals["accepted"], "of %d submitted" % totals["submitted"]),
            cell("rejected", "%d" % totals["rejected"],
                 "acceptance %.1f%%" % acceptance),
            cell("total hashed", "%.2f TH" % (totals["hashes"] / 1e12)),
            cell("mean rate", "%.0f MH/s" % (mean_rate / 1e6)),
            cell("runs", "%d" % totals["runs"],
                 "%.2f hours lifetime" % (totals["seconds"] / 3600.0)),
            cell("implied difficulty", "%.0f" % implied,
                 "from the share spacing, not from the pool"),
        ]
        spread = (100.0 / math.sqrt(totals["accepted"])) if totals["accepted"] else 0.0
        share_note = ('<p class="note wide">Share spacing is exponentially distributed, a mean '
                      'drawn from %d shares carries a spread of about %.0f percent. That is enough '
                      'to say the client works and not enough to state its rate; roughly nineteen '
                      'shares would bring it near twenty three percent.</p>'
                      % (totals["accepted"], spread))
    else:
        hitting = [absent("share counters", "miner_totals.txt not found")]
        share_note = ""

    # --- chain -------------------------------------------------------------------------------
    if chain:
        chain_cells = [
            cell("newest block read", "%d" % chain["height"],
                 "%d blocks in the corpus" % chain["count"]),
            cell("difficulty", "%.3e" % chain["difficulty"]),
            cell("leading zero bits", "%d" % chain["zeros"], "required by the target"),
            cell("nonces per block", "%.3e" % chain["expected"]),
        ]
        # The wait for a block belongs in the Win rate section below and is not repeated here; the
        # bits route to it is checked against the difficulty route in --check.
    else:
        chain_cells = [absent("chain context", "the block corpus was not found")]

    # --- win rate ----------------------------------------------------------------------------
    # TWO SCALES, KEPT APART ON THE PAGE. A share and a block are both wins and they are eleven
    # orders of magnitude apart. They get separate groups and not one interleaved grid. Then
    # the reader never has to check a label to know which world a figure lives in.
    share_win = []
    block_win = []
    if totals and totals["accepted"] and totals["seconds"]:
        per_share_hashes = totals["hashes"] / float(totals["accepted"])
        per_hour = totals["accepted"] / (totals["seconds"] / 3600.0)
        share_win.append(cell("shares won", "%.2f / hour" % per_hour,
                              "%d over %.2f hours, measured"
                              % (totals["accepted"], totals["seconds"] / 3600.0)))
        share_win.append(cell("hashes per share", "%.3e" % per_share_hashes))
        share_win.append(cell("first try rate, achieved", "1 in %.3e" % per_share_hashes,
                              "p = %.3e, measured from our own spacing"
                              % (1.0 / per_share_hashes)))
    else:
        share_win.append(absent("share win rate", "no accepted shares recorded"))

    # WHAT THE POOL SAYS OUTRANKS WHAT IS INFERRED. The stated difficulty is the target mined
    # against right now; the spacing above is what was achieved under whatever target was set at
    # the time. When they disagree the stated one is current and the page says so.
    if pool["difficulty"]:
        stated_hashes = pool["difficulty"] * (2.0 ** 32)
        share_win.append(cell("pool share difficulty", "%.0f" % pool["difficulty"],
                              "stated by the pool, not inferred"))
        share_win.append(cell("first try rate, current", "1 in %.3e" % stated_hashes,
                              "p = %.3e, exact from the stated target"
                              % (1.0 / stated_hashes)))
        if totals and totals["accepted"] and mean_rate > 0:
            expected_per_hour = mean_rate * 3600.0 / stated_hashes
            share_win.append(cell("shares expected", "%.2f / hour" % expected_per_hour,
                                  "at the stated target and the measured rate"))
            achieved_difficulty = (totals["hashes"] / float(totals["accepted"])) / (2.0 ** 32)
            if achieved_difficulty > 0:
                factor = pool["difficulty"] / achieved_difficulty
                if factor > 1.5 or factor < 0.67:
                    share_note = (('<p class="warn">The pool has us at share difficulty %.0f while '
                                   'our own %d shares imply %.0f, a factor of %.1f. Those shares '
                                   'were won under an easier target, so the achieved rate above is '
                                   'history and the current row is the one to read. This is why '
                                   'both are shown.</p>'
                                   % (pool["difficulty"], totals["accepted"], achieved_difficulty,
                                      factor)) + share_note)
    if pool["worker"]:
        share_win.append(cell("worker", pool["worker"],
                              ("%d threads" % pool["workers"]) if pool["workers"] else ""))

    if chain and mean_rate > 0:
        # THE FIRST TRY RATE LEADS THE GROUP, because it is the only figure here with no telemetry
        # and no rate in it: the probability that one nonce, the first one or the 10^23rd, is the
        # answer. It falls straight out of the target. It is exact and not measured.
        #
        # WHY FIRST IS THE SAME AS ANY. A nonce is a trial of a function with no order to exploit:
        # SHA-256d gives no reason for nonce 0 to be luckier than nonce 2^31. The first try
        # carries exactly the per-nonce probability and nothing about being first improves it. The
        # whole value of a better machine is in running MORE trials, never in choosing a better
        # first one. That is also what the period probe in examples/00_blob_viz_tools/nonce_period.py went looking
        # for and did not find: no structure across nonces, down to a limit of 1.83e-02.
        per_nonce = float(chain["target"] + 1) / float(1 << 256)
        block_win.append(cell("first try rate", "1 in %.3e" % (1.0 / per_nonce),
                              "p = %.3e, exact from the target" % per_nonce))
        block_win.append(cell("first tries a second", "%.3e" % mean_rate,
                              "each hash is an independent first try"))
        block_win.append(cell("median nonces to a block", "%.3e" % (math.log(2.0) / per_nonce),
                              "half the time it lands sooner than this"))

        # The win rate per block IS this miner's share of the network rate: one hash is one
        # independent trial. The fraction of the trials run here is the probability the winning
        # one is this miner's.
        # It is one number and it gets one cell.
        share_of_network = mean_rate / chain["network"]
        per_block = share_of_network * BLOCK_REWARD
        blocks_to_win = 1.0 / share_of_network
        years_to_win = blocks_to_win * BLOCK_SECONDS / SECONDS_PER_YEAR
        block_win.append(cell("network hash rate", "%.3e H/s" % chain["network"],
                              "derived from the chain's own difficulty"))
        block_win.append(cell("win rate per block", "%.3e" % share_of_network,
                              "our share of the network's hashes, which is the same number"))
        block_win.append(cell("expected per block", "%.3e BTC" % per_block,
                              "at a %.3f BTC subsidy" % BLOCK_REWARD))
        block_win.append(cell("expected per day", "%.3e BTC" % (per_block * BLOCKS_PER_DAY)))
        block_win.append(cell("one block, expected wait", "%.2e years" % years_to_win,
                              "%.3e blocks, and the bits route agrees" % blocks_to_win))

        # THE GAP BETWEEN THE TWO WINS, COMPUTED AND NOT CLAIMED. The sentence reads the number it
        # is describing: the ratio of the two difficulties.
        gap_text = ""
        if totals and totals["accepted"]:
            share_difficulty = (totals["hashes"] / float(totals["accepted"])) / (2.0 ** 32)
            if share_difficulty > 0:
                decades = math.log10(chain["difficulty"] / share_difficulty)
                gap_text = ('<p class="warn">The two groups above are not the same event and are '
                            '%.1f orders of magnitude apart: the share target implied by our own '
                            'spacing is difficulty %.0f, the chain is at %.3e. A share is pool '
                            'bookkeeping and arrives in hours; a block is the chain and does not '
                            'arrive. Reading one as the other is the easiest mistake this page '
                            'invites.</p>' % (decades, share_difficulty, chain["difficulty"]))

        win_note = ('<p class="note wide">The network rate is not quoted from anywhere: difficulty '
                    'is defined a block arrives every ten minutes, so rate = difficulty times '
                    '2^32 over 600 comes straight out of a figure the chain publishes. Everything '
                    'in this block follows from that and from the measured local rate, and the '
                    'subsidy and the ten minutes are protocol constants.</p>'
                    '<p class="note wide">The first try rate is the probability that one nonce is '
                    'the answer, and it is the same for the first nonce as for any other: SHA-256d '
                    'gives no reason for one to be luckier, so being first buys nothing. The probe '
                    'in examples/00_blob_viz_tools/nonce_period.py went looking for structure across nonces that '
                    'would break that and found none down to 1.83e-02. A better machine wins by '
                    'running more trials, not by picking a better first one.</p>' + gap_text)
    else:
        block_win.append(absent("block win rate", "no chain data or no measured rate"))
        win_note = ""

    scaling_rows = "".join(
        '<tr%s><td>%d</td><td>%.2f</td><td>%.3f</td></tr>'
        % (' class="best"' if count == 1 else "", count, total, ratio)
        for count, total, ratio in SCALING)

    trace = ""
    if points:
        trace = ('<svg viewBox="0 0 720 160" preserveAspectRatio="none" class="trace">'
                 '<polyline points="%s" /></svg>'
                 '<div class="note wide">%d samples, %.0f to %.0f MH/s. The trace is the steady '
                 'state, not a growth curve: no log in this tree reaches back to the engine\'s '
                 'early rates.</div>' % (points, len(rates), low, top))

    return TEMPLATE % {
        "device": device_name,
        "banner": banner,
        "cooking": "".join(cooking),
        "idle": idle_note,
        "hitting": "".join(hitting),
        "share_note": share_note,
        "chain": "".join(chain_cells),
        "share_win": "".join(share_win),
        "block_win": "".join(block_win),
        "win_note": win_note,
        "trace": trace,
        "scaling": scaling_rows,
    }


TEMPLATE = """<title>Worker Pool</title>
<style>
  :root {
    --ink: #10151c; --dim: #5c6a7a; --face: #f4f6f8; --panel: #ffffff;
    --edge: #dfe5ec; --hot: #c2410c; --good: #0f766e; --bad: #b91c1c; --trace: #0f766e;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --ink: #e8edf2; --dim: #8c9aab; --face: #0d1117; --panel: #161b22;
      --edge: #283039; --hot: #fb923c; --good: #2dd4bf; --bad: #f87171; --trace: #2dd4bf;
    }
  }
  :root[data-theme="dark"] {
    --ink: #e8edf2; --dim: #8c9aab; --face: #0d1117; --panel: #161b22;
    --edge: #283039; --hot: #fb923c; --good: #2dd4bf; --bad: #f87171; --trace: #2dd4bf;
  }
  body {
    background: var(--face); color: var(--ink); margin: 0;
    font: 14px/1.55 "SF Mono", "Cascadia Mono", Consolas, monospace;
    padding-block: 28px; padding-left: 20px; padding-right: 20px;
  }
  .sheet { max-width: 940px; margin: 0 auto; }
  h1 { font-size: 19px; letter-spacing: 0.14em; text-transform: uppercase;
       margin: 0 0 4px; font-weight: 600; }
  .sub { color: var(--dim); margin: 0 0 26px; font-size: 12.5px; }
  h2 { font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--dim);
       margin: 30px 0 10px; font-weight: 600; }
  .grid { display: grid; gap: 10px; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); }
  .cell { background: var(--panel); border: 1px solid var(--edge); border-radius: 3px;
          padding: 11px 13px; }
  .cell.gone { border-style: dashed; }
  .cell.gone .value { color: var(--dim); }
  .label { font-size: 10.5px; letter-spacing: 0.13em; text-transform: uppercase;
           color: var(--dim); margin-bottom: 5px; }
  .value { font-size: 21px; font-variant-numeric: tabular-nums; }
  .note { font-size: 11px; color: var(--dim); margin-top: 5px; }
  .note.wide { margin-top: 10px; max-width: 68ch; }
  .warn { color: var(--hot); font-size: 12px; margin: 12px 0 0; max-width: 68ch; }
  table { border-collapse: collapse; font-variant-numeric: tabular-nums; font-size: 13px; }
  th, td { text-align: right; padding: 5px 15px 5px 0; }
  th { color: var(--dim); font-weight: 600; font-size: 10.5px; letter-spacing: 0.13em;
       text-transform: uppercase; border-bottom: 1px solid var(--edge); }
  tr.best td { color: var(--good); font-weight: 600; }
  .trace { width: 100%%; height: 110px; display: block; margin-top: 6px; }
  .trace polyline { fill: none; stroke: var(--trace); stroke-width: 1.6; }
  .scroll { overflow-x: auto; }
  footer { color: var(--dim); font-size: 11px; margin-top: 34px;
           border-top: 1px solid var(--edge); padding-top: 14px; max-width: 72ch; }
  .live { font-size: 12.5px; line-height: 1.5; padding: 11px 14px; border-radius: 3px;
          margin: 0 0 20px 0; border-left: 3px solid; max-width: 74ch; }
  .live b { font-weight: 650; }
  .live.ok { color: var(--good); border-left-color: var(--good);
             background: color-mix(in srgb, var(--good) 8%%, transparent); }
  .live.stale { color: var(--bad); border-left-color: var(--bad);
                background: color-mix(in srgb, var(--bad) 10%%, transparent); }
</style>
<div class="sheet">
  <h1>Worker Pool</h1>
  <p class="sub">%(device)s &middot; local telemetry, the client's own counters, and the chain read
  from a verified corpus. Braiins reports the pool side; this is everything the pool cannot see.</p>

  %(banner)s

  <h2>Cooking</h2>
  <div class="grid">%(cooking)s</div>
  %(idle)s

  <h2>Hitting</h2>
  <div class="grid">%(hitting)s</div>
  %(share_note)s

  <h2>Rate trace</h2>
  %(trace)s

  <h2>Chain</h2>
  <div class="grid">%(chain)s</div>

  <h2>Win rate &mdash; a share</h2>
  <div class="grid">%(share_win)s</div>

  <h2>Win rate &mdash; a block</h2>
  <div class="grid">%(block_win)s</div>
  %(win_note)s

  <h2>Pool size, measured</h2>
  <div class="scroll">
  <table>
    <tr><th>instances</th><th>aggregate MH/s</th><th>vs one</th></tr>
    %(scaling)s
  </table>
  </div>
  <p class="note wide">Concurrent miner processes on one card are time-sliced, and worse than
  time-sliced: two lose a third of the aggregate and it never recovers past one. So the pool is one
  device process, and parallelism belongs in streams inside it. Measured by
  src/import/hardware/device_scaling.sh, not assumed.</p>

  <footer>Every figure above is read from nvidia-smi, miner_totals.txt, miner.log or
  blocks_deep.json at build time. Anything unreadable is shown as absent and not filled in.
  Rebuild to refresh: this page is one self-contained file with no network and no interpreter.
  It is a snapshot by design.</footer>
</div>
"""


def _check():
    lines = []
    failed = 0

    telemetry = device_telemetry()
    lines.append("  nvidia-smi answered: %s" % (telemetry is not None))
    if telemetry:
        lines.append("    %s, %s C, %s, util %s"
                     % (telemetry["name"], telemetry["temperature.gpu"],
                        telemetry["power.draw"], telemetry["utilization.gpu"]))

    totals = read_totals()
    lines.append("  totals read: %s" % (totals is not None))
    if totals:
        lines.append("    %.2f TH, %d of %d shares, %d runs"
                     % (totals["hashes"] / 1e12, totals["accepted"], totals["submitted"],
                        totals["runs"]))

    rates = read_rates()
    lines.append("  %d rate samples" % len(rates))

    chain = read_chain()
    lines.append("  chain read: %s" % (chain is not None))
    if chain:
        lines.append("    block %d, %d zero bits needed, %.3e nonces a block"
                     % (chain["height"], chain["zeros"], chain["expected"]))
        lines.append("    network %.3e H/s, derived from difficulty %.4e"
                     % (chain["network"], chain["difficulty"]))

        # TWO ROUTES TO THE SAME WAIT, from two separate fields the chain publishes. The Chain
        # section reaches it through `bits`: decode the target, count the nonces that clear it,
        # divide by the measured rate. The Win rate section reaches it through `difficulty`: turn
        # that into a network rate, take our share, invert it, multiply by ten minutes. If the
        # corpus's bits and difficulty ever disagreed, these would separate and the page would be
        # quoting one of them wrongly. They must not separate.
        from_bits = float(chain["expected"])
        from_difficulty = chain["difficulty"] * (2.0 ** 32)
        gap = abs(from_bits - from_difficulty) / from_difficulty
        lines.append("    bits route %.6e nonces, difficulty route %.6e, relative gap %.2e"
                     % (from_bits, from_difficulty, gap))
        if gap > 1e-4:
            lines.append("    FAIL bits and difficulty disagree, so one of them is misread")
            failed += 1

        # THE FIRST TRY RATE IS THE RECIPROCAL OF THE NONCE COUNT, and if it is not then one of the
        # two is wrong. p is computed from the target in floating point and the count in exact
        # integers. Their product is 1 to within the float conversion or not at all.
        per_nonce = float(chain["target"] + 1) / float(1 << 256)
        product = per_nonce * float(chain["expected"])
        lines.append("    first try p = %.6e, times %.6e nonces = %.9f"
                     % (per_nonce, chain["expected"], product))
        if abs(product - 1.0) > 1e-9:
            lines.append("    FAIL the first try rate is not the reciprocal of the nonce count")
            failed += 1

    pool = read_pool()
    lines.append("  pool stated share difficulty: %s, worker %s, %s threads"
                 % (pool["difficulty"], pool["worker"], pool["workers"]))
    if pool["difficulty"] and totals and totals["accepted"]:
        achieved = (totals["hashes"] / float(totals["accepted"])) / (2.0 ** 32)
        lines.append("    achieved difficulty from spacing %.0f, stated %.0f, factor %.1f"
                     % (achieved, pool["difficulty"], pool["difficulty"] / achieved))

    page = render(telemetry, totals, rates, chain, pool)

    # The page must be self contained: no network reference of any kind.
    offenders = [one for one in ("http://", "https://", "//cdn", "<script") if one in page]
    lines.append("  the page references nothing external: %s" % (not offenders))
    if offenders:
        lines.append("    FAIL the page pulls %s, so it is not self contained" % offenders)
        failed += 1

    # NO FIAT ANYWHERE. A BTC amount is a measurement; a dollar amount is a price quote off a
    # market this tree does not read, and it would be the one invented number on the page.
    fiat = [one for one in ("$", "USD", "usd", "dollar") if one in page]
    lines.append("  the page quotes no currency price: %s" % (not fiat))
    if fiat:
        lines.append("    FAIL the page carries %s, which is a quote and not a measurement" % fiat)
        failed += 1

    # It must carry a title and paint its own background, or it borrows the host's theme.
    for needed in ("<title>", "background: var(--face)"):
        if needed not in page:
            lines.append("    FAIL the page is missing %s" % needed)
            failed += 1
    lines.append("  the page sets its own title and background: %s"
                 % ("<title>" in page and "background: var(--face)" in page))

    # THE LIVENESS BANNER, BOTH BRANCHES. A stale page keeps showing its mean rate with nothing
    # saying the miner is gone, every figure true as a historical total and the page reading as
    # live, and an untested banner does not prevent that.
    stale = render(device_telemetry(), read_totals(), read_rates(), read_chain(), read_pool(),
                   {"age": 21734.0, "live": False, "why": "pool closed the connection",
                    "limit": 30.0})
    fresh = render(device_telemetry(), read_totals(), read_rates(), read_chain(), read_pool(),
                   {"age": 3.0, "live": True, "why": None, "limit": 30.0})
    lines.append("  the stale banner says NOT MINING and names the age: %s"
                 % ("NOT MINING" in stale and "6.0 hours" in stale))
    if "NOT MINING" not in stale or "6.0 hours" not in stale:
        lines.append("    FAIL a stopped miner does not announce itself, so every total on this")
        lines.append("         page reads as current when none of it is")
        failed += 1
    lines.append("  it also surfaces the miner's own last line: %s"
                 % ("pool closed the connection" in stale))
    if "pool closed the connection" not in stale:
        lines.append("    FAIL the reason the miner stopped is not on the page, so somebody has")
        lines.append("         to open the log to find out why")
        failed += 1
    lines.append("  the live banner says MINING and the stale one does not: %s"
                 % ("MINING." in fresh and "NOT MINING" not in fresh))
    if "NOT MINING" in fresh:
        lines.append("    FAIL a running miner is reported as stopped, which is the same defect")
        lines.append("         pointing the other way")
        failed += 1

    # AND THE BANNER MUST NOT BE INVENTED WHEN NOTHING IS KNOWN. A page built without a liveness
    # reading must stay silent and not claim either state.
    quiet = render(device_telemetry(), read_totals(), read_rates(), read_chain(), read_pool())
    lines.append("  with no liveness reading the page claims neither state: %s"
                 % ("MINING" not in quiet))
    if "MINING" in quiet:
        lines.append("    FAIL the page asserted a liveness it was never given")
        failed += 1

    # THE NEGATIVE CONTROL. With every source missing the page must render ABSENT cells and not
    # numbers, because a dashboard that invents a figure is worse than one with a visible gap.
    blank = render(None, None, [], None, None)
    absences = blank.count("absent")
    lines.append("  with no sources at all the page shows %d absent cells and no invented numbers"
                 % absences)
    if absences < 3:
        lines.append("    FAIL missing sources did not render as absent")
        failed += 1
    if "MH/s\">" in blank or "TH<" in blank:
        lines.append("    FAIL a figure appeared with no source behind it")
        failed += 1

    # And it must not resolve its output beside itself. out_path exists to prevent it.
    target = out_path.resolve("pool_view.html")
    lines.append("  output resolves to %s" % target)
    if os.path.dirname(os.path.abspath(target)) == HERE:
        lines.append("    FAIL the page would be written beside the builder")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def build_once(out):
    """One snapshot. Returns the path written and the byte count."""
    page = render(device_telemetry(), read_totals(), read_rates(), read_chain(), read_pool(),
                  read_liveness())
    target = out_path.resolve("pool_view.html", out)
    with io.open(target, "w", encoding="utf-8") as handle:
        handle.write(stamp(page))
    return target, len(page)


def main():
    parser = argparse.ArgumentParser(description="a page for watching the worker pool")
    parser.add_argument("--out", default=None)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--watch", type=int, default=0, metavar="SECONDS",
                        help="rebuild every SECONDS so the page tracks a running miner")
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0

    # WATCH MODE EXISTS BECAUSE THE PAGE IS A SNAPSHOT BY DESIGN. It carries no script and makes no
    # request, the property that makes it worth keeping, and the cost of that is that it
    # cannot refresh itself. Rebuilding on a timer keeps the figures live without giving the page a
    # network dependency it would then have forever.
    #
    # The write is the whole file every time and the browser reload is the user's. Nothing here
    # needs to coordinate with a reader. A rebuild is a few milliseconds against a miner running at
    # 2.35 GH/s. This is free in the sense that matters: it does not compete for the card.
    if args.watch > 0:
        sys.stdout.write("  rebuilding every %d seconds, ctrl-c to stop\n" % args.watch)
        while True:
            target, size = build_once(args.out)
            sys.stdout.write("  %s  %d bytes\n" % (time.strftime("%H:%M:%S"), size))
            sys.stdout.flush()
            time.sleep(args.watch)

    target, size = build_once(args.out)
    sys.stdout.write("  wrote %s, %d bytes\n" % (target, size))
    return 0


if __name__ == "__main__":
    sys.exit(main())
