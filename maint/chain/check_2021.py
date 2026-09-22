"""The known-answer test for the hashrate instrument: does it see 2021?

An instrument that has never been shown to detect a real event cannot be believed when it reports
none. The recent corpus flagged zero hashrate excursions in 48 days, and that negative is worth
nothing until the same code is pointed at an event everyone already knows the answer to.

2021 supplies one. Mining was banned in China across May to July, global hashrate fell by roughly
half, and it recovered over the following months as fleets moved, principally to North America. The
event is dated, documented, enormous, and independent of anything being fitted here.

    if hashrate-from-intervals is an instrument, it must show the collapse and the recovery

THE TRAP THIS AVOIDS

Hashrate is not one over the interval. Difficulty retargets every 2016 blocks and the retarget
changes intervals BY DESIGN, so a reading that ignores difficulty reports the protocol's own
corrections as though they were events. The ban forced the largest downward retargets in the
chain's history, which means the naive reading would find its biggest signal in exactly the wrong
place. Hashrate is difficulty over interval, and that is what is computed here.

THE SECOND TEST, WHICH IS HARDER

The migration moved hashrate from about 105 degrees east to about 100 west, most of the way around
the planet. If the daily cycle measures where miners are, its phase has to move by most of twelve
hours across 2021. A cycle that stays put while the miners demonstrably moved is not measuring
miners, and that would retire the longitude reading rather than support it.

    python tools/chain/check_2021.py
    python tools/chain/check_2021.py --corpus tools/chain/blocks_2021.json
"""

import argparse
import io
import json
import math
import os
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(HERE, "blocks_2021.json")

RETARGET = 2016
WINDOW = 504   # a quarter of a retarget period, so no window straddles two of them


def stamp_text(when):
    piece = time.gmtime(when)
    return "%04d-%02d-%02d" % (piece.tm_year, piece.tm_mon, piece.tm_mday)


def main():
    parser = argparse.ArgumentParser(description="Validate the hashrate instrument on 2021.")
    parser.add_argument("--corpus", default=DEFAULT)
    given = parser.parse_args()

    with io.open(given.corpus, encoding="utf-8") as handle:
        blocks = json.load(handle)
    blocks.sort(key=lambda b: b["height"])
    count = len(blocks)
    if count < 4000:
        raise SystemExit("corpus too short for this test: %d blocks" % count)

    first, last = blocks[0], blocks[-1]
    print("  %d blocks, heights %d..%d" % (count, first["height"], last["height"]))
    print("  %s .. %s" % (stamp_text(first["timestamp"]), stamp_text(last["timestamp"])))
    print()

    # DOES THE CORPUS CONTAIN THE EVENT? CHECKED FIRST, AND FATAL IF NOT.
    #
    # This ran once against blocks_2021.json covering 2021-11-03 to 2021-12-20 - entirely AFTER the
    # ban and after the recovery - and reported "the collapse is NOT visible" and "the instrument
    # fails its known answer. Nothing it reported about small dips should be believed." Every word
    # of that was produced from a window in which nothing happened.
    #
    # A known-answer test whose corpus does not span the known answer is failure mode 1 in this
    # tree's own list: a quantity that structurally cannot show the effect, with the resulting null
    # reported as a finding. It is worse than no test, because it convicts a working instrument.
    #
    # The ban ran May to July 2021 and the recovery through that autumn, so the window has to open
    # before the collapse and close after the return. Those are heights near 675,000 and 715,000.
    BAN_BEGAN = 1619827200      # 2021-05-01
    BAN_ENDED = 1627776000      # 2021-08-01
    if not (first["timestamp"] <= BAN_ENDED and last["timestamp"] >= BAN_BEGAN):
        print("=" * 76)
        print("  REFUSING: THE CORPUS DOES NOT CONTAIN THE EVENT")
        print("=" * 76)
        print()
        print("    The ban ran 2021-05-01 to 2021-07-31 and this corpus is %s .. %s."
              % (stamp_text(first["timestamp"]), stamp_text(last["timestamp"])))
        print("    There is no collapse inside this window to detect, so an instrument that")
        print("    reports none here has been told nothing, and a verdict against it would be")
        print("    a statement about the corpus.")
        print()
        print("    Fetch the window that spans the event, roughly heights 675,000 to 715,000:")
        print()
        print("      python tools/chain/fetch_deep.py --from 675000 --to 715000 \\")
        print("          --into tools/chain/blocks_ban_2021.json")
        print("      python tools/chain/check_2021.py --corpus tools/chain/blocks_ban_2021.json")
        print()
        return 1

    print("=" * 76)
    print("  1. THE RETARGETS  -  are they where the protocol says, and how large?")
    print("=" * 76)
    print()
    seen = []
    for block in blocks:
        value = block.get("difficulty")
        if value is None:
            continue
        if not seen or value != seen[-1][1]:
            seen.append((block["height"], value))
    print("    %d distinct difficulty values across the span" % len(seen))
    print()
    print("      height    on a retarget?    difficulty        change")
    previous = None
    for height, value in seen[:18]:
        aligned = "yes" if height % RETARGET == 0 else "NO (height %% 2016 = %d)" % (height % RETARGET)
        change = "" if previous is None else "%+7.2f%%" % (100.0 * (value / previous - 1.0))
        print("      %7d   %-22s %14.4g   %s" % (height, aligned, value, change))
        previous = value
    print()
    print("    A value changing anywhere but a multiple of 2016 means the reader is wrong, not")
    print("    the chain. The largest downward steps here should be the ones the ban forced.")

    print()
    print("=" * 76)
    print("  2. HASHRATE  -  difficulty over interval, which is the quantity that means it")
    print("=" * 76)
    print()
    series = []
    for start in range(0, count - WINDOW, WINDOW // 2):
        chunk = blocks[start:start + WINDOW]
        if chunk[0]["height"] // RETARGET != chunk[-1]["height"] // RETARGET:
            continue      # straddles a retarget; excluded rather than corrected
        span = chunk[-1]["timestamp"] - chunk[0]["timestamp"]
        if span <= 0:
            continue
        gap = span / float(len(chunk) - 1)
        diff = chunk[len(chunk) // 2].get("difficulty")
        if not diff:
            continue
        series.append((chunk[len(chunk) // 2]["timestamp"], diff / gap))

    if len(series) < 6:
        raise SystemExit("too few clean windows: %d" % len(series))

    values = [v for _, v in series]
    peak = max(values)
    trough_at, trough = min(series, key=lambda p: p[1])
    peak_at = max(series, key=lambda p: p[1])[0]
    print("    %d windows of %d blocks, retarget-straddling windows excluded" % (len(series), WINDOW))
    print()
    print("      peak      %s   %.4g" % (stamp_text(peak_at), peak))
    print("      trough    %s   %.4g" % (stamp_text(trough_at), trough))
    print("      fall      %.1f%% from peak to trough" % (100.0 * (1.0 - trough / peak)))
    print()
    print("    the curve, each row a window, scaled to the peak:")
    for when, value in series:
        bar = "#" * int(round(value / peak * 52))
        print("      %s  %-52s %5.1f%%" % (stamp_text(when), bar, 100.0 * value / peak))

    print()
    print("=" * 76)
    print("  VERDICT ON THE INSTRUMENT")
    print("=" * 76)
    fall = 100.0 * (1.0 - trough / peak)
    print()
    if fall >= 35.0 and trough_at < peak_at + 200 * 86400:
        print("    The collapse is visible: %.1f%% off the peak, bottoming %s."
              % (fall, stamp_text(trough_at)))
        print("    The instrument detects an event it was never tuned for, so its silence over the")
        print("    recent corpus now means something it did not mean before.")
    else:
        print("    The collapse is NOT visible at the expected size: %.1f%% off peak." % fall)
        print("    The instrument fails its known answer. Nothing it reported about small dips")
        print("    should be believed, including the zero excursions over the recent corpus.")

    print()
    print("=" * 76)
    print("  3. DID THE DAILY CYCLE'S PHASE MOVE WITH THE MINERS?")
    print("=" * 76)
    print()
    print("  Hashrate moved from roughly 105 east to roughly 100 west, so a cycle that measures")
    print("  where miners are must shift its trough by most of twelve hours. A cycle that does not")
    print("  move retires the longitude reading.")
    print()
    third = count // 3
    for name, part in (("first third", blocks[:third]),
                       ("middle third", blocks[third:2 * third]),
                       ("last third", blocks[2 * third:])):
        hours = [0] * 24
        for block in part:
            hours[(block["timestamp"] // 3600) % 24] += 1
        per = len(part) / 24.0
        floor = math.sqrt(per)
        trough_hour = min(range(24), key=lambda h: hours[h])
        peak_hour = max(range(24), key=lambda h: hours[h])
        swing = (hours[peak_hour] - hours[trough_hour]) / floor
        lon = (16 - trough_hour) * 15
        while lon > 180:
            lon -= 360
        while lon < -180:
            lon += 360
        print("    %-14s %s..%s   trough %02d:00   swing %4.1f floors   implied %+4d deg"
              % (name, stamp_text(part[0]["timestamp"]), stamp_text(part[-1]["timestamp"]),
                 trough_hour, swing, lon))
    print()
    print("    Swing is in Poisson floors. Below about 3 the trough hour is noise and its implied")
    print("    longitude means nothing, however confident the number looks.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
