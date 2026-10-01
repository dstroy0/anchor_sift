"""Lays every measured constant onto the field of the block header it describes.

The readings taken across this work are not free-floating numbers. Each one is a statement about a
specific run of bytes in the eighty byte header, and a table of them sorted by magnitude hides that.
Sorted by the byte they describe, they say something a table cannot: which parts of a block carry
structure, which are level, and which were never measured at all.

EVERY CONSTANT CARRIES ITS NULL AND ITS VERDICT

A number without the floor it was measured against is not a result. So each entry below carries what
chance alone produces on the same statistic at the same sample size, and a verdict in three states:

    tilted    clears its own calibrated null by a margin no reasonable multiple-comparison
              correction erases
    level     came back flat. These are load-bearing: a flat reading from an instrument that
              detects signal elsewhere is evidence of absence, not absence of evidence
    marginal  sits on the line. Named as such rather than rounded into one of the other two

Roughly half the entries are level, which is the honest proportion and the reason to publish them
next to the tilted ones rather than only the interesting half.

    python tools/view/build_block_view.py
"""

import argparse
import io
import json
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TEMPLATE = os.path.join(HERE, "block_view_template.html")
CORPUS = os.path.join(ROOT, "tools", "chain", "blocks.json")

# Offset and width of every field of the eighty byte header, in the order it is serialised.
FIELDS = [
    ("version", 0, 4),
    ("previousblockhash", 4, 32),
    ("merkle_root", 36, 32),
    ("timestamp", 68, 4),
    ("bits", 72, 4),
    ("nonce", 76, 4),
]

# Each constant names the field it describes, what was measured, the value, the floor chance gives
# on the same statistic, and where it came from. Nothing here is estimated or carried over from
# elsewhere: every value was produced by a script in this tree during this work.
CONSTANTS = [
    ("header", "headers rebuilt and hashed against their recorded id", "1000 of 1000",
     "a single mismatch invalidates everything downstream", "tilted",
     "deck_memory.py, known-answer test"),

    ("version", "rolling window, reserved by BIP320", "bits 13 to 28",
     "specification, not measurement", "level", "BIP320"),
    ("version", "bits moving inside the window", "16 of 16",
     "and 0 of 16 outside it", "tilted", "kat_holes.py"),
    ("version", "chi-square of the window distribution", "17723",
     "14.8, and a null lands near 15 at any N", "tilted", "integrate.py, N=6980"),
    ("version", "bit 13 share against a flat counter", "0.4304, z = -11.63",
     "0.5000 predicted by a swept counter", "tilted", "integrate.py"),
    ("version", "bit 28 share against a flat counter", "0.1943, z = -51.09",
     "0.5000 predicted by a swept counter", "tilted", "integrate.py"),
    ("version", "top 20 values of 65536 possible", "26.7% of all blocks",
     "0.03% if the window were swept evenly", "tilted", "version_rake.py"),
    ("version", "base version outside the window", "0x20000000 at 98.6%",
     "3 distinct values in 6980 blocks", "level", "wins.py"),
    ("version", "does the window identify the miner, persistence", "-0.83 sd",
     "a shuffle of the same labels", "level", "emitter_test.py"),
    ("version", "does the window identify the miner, transfer", "+0.89 sd at best",
     "169 of 1000 shuffles reached it", "level", "emitter_test.py"),

    ("previousblockhash", "chain linkage", "determined by the parent",
     "no independent statistic exists here", "level", "structural"),

    ("merkle_root", "determined by the transactions", "not independently measured",
     "pool identity lives in the coinbase, which the header does not carry", "level",
     "structural"),

    ("timestamp", "blocks recording a time before their parent", "2.98%",
     "0% if the network's clocks agreed", "tilted", "integrate.py, 208 of 6979"),
    ("timestamp", "deepest reversal", "395 seconds",
     "NTP holds a machine within milliseconds", "tilted", "integrate.py"),
    ("timestamp", "low bits, loudest of eight", "z = 3.10",
     "3.35, the null's own largest over 8 cells", "level", "jitter.py"),
    ("timestamp", "residues mod ten", "chi-square 9.9 on 9 df",
     "a fair clock lands near 9", "level", "jitter.py"),
    ("timestamp", "interval spread over its mean", "0.9879",
     "1.0000 exactly, for an exponential", "level", "integrate.py"),
    ("timestamp", "daily cycle, peak to trough", "27.5%",
     "chi-square 36.6 against a null 95th of 35.1", "marginal", "diurnal_fix.py, p = 0.036"),
    ("timestamp", "hour of the daily trough", "18:00 UTC",
     "12:00 US Central, the afternoon demand peak", "marginal", "diurnal_fix.py"),

    ("bits", "distinct difficulty targets in 1000 blocks", "2",
     "one retarget boundary in that span, so 2 is correct", "level", "kat_holes.py"),
    ("bits", "retarget period", "2016 blocks",
     "specification, not measurement", "level", "consensus rule"),

    ("nonce", "popcount of winning nonces", "15.644, z = -3.98",
     "16.000 exactly, for a uniform 32-bit field", "marginal", "kat_nonces.py, N=1000"),
    ("nonce", "bit 7 share across winners", "0.430, z = -4.43",
     "the null's loudest over 32 cells was 2.28", "marginal", "kat_nonces.py"),
    ("nonce", "does SHA-256 favour low-popcount nonces", "-0.000333",
     "a band of 0.001 at 4 million hashes", "level", "deck_memory.py"),
    ("nonce", "hit rate, popcount 14 and under against 18 and over", "-1.00 sd",
     "0 hits against 1, over 2.4 million tries", "level", "deck_memory.py"),
    ("nonce", "distance-to-target autocorrelation, lags 1 to 1024", "all inside 0.0045",
     "the null band at 200000 samples", "level", "distance_landscape.py"),
    ("nonce", "hill-climbing against random search, equal budget", "+3.81 sd WORSE",
     "descent should win if the landscape had a slope", "level", "distance_landscape.py"),
    ("nonce", "descent on leading zeros against random draw", "-0.490 bits",
     "equal, if the landscape were flat", "level", "distance_landscape.py"),
    ("nonce", "entropy-distance descent against random", "+1.95 sd worse",
     "a nonlinear metric, tested separately from Hamming", "level", "entropy_distance.py"),
    ("nonce", "spread across the 32-bit range, eight cells", "chi-square 12.2 on 7 df",
     "null 9.3 on the same cells", "level", "kat_nonces.py"),

    ("compression", "algebraic degree in the nonce bits", "saturated by round 8",
     "126 cube cells, every one near 128 of 256", "level", "higher_order.py"),
    ("compression", "residue matched filter, rounds 6 to 16", "19.16 integrated",
     "waveform named from the round function, no max-of-N penalty", "tilted",
     "radar_receive.py"),
    ("compression", "Sigma1 against Sigma0 through the same filter", "12.61 and 3.34",
     "the mechanism predicts the asymmetry, T1 against T2", "tilted", "radar_receive.py"),
    ("compression", "the same receiver past the collapse", "largest 2.30",
     "null peak 2.45 over 20 maxima", "level", "radar_receive.py"),
    ("compression", "rounds recoverable backward without the message", "7 of 8 words",
     "the eighth is h + W, one 32-bit sum per round", "tilted", "recover.py"),
]


def main():
    parser = argparse.ArgumentParser(description="Build the annotated block view.")
    parser.add_argument("--out", default=os.path.join(HERE, "block_view.html"))
    given = parser.parse_args()

    with io.open(CORPUS, encoding="utf-8") as handle:
        block = json.load(handle)[0]

    raw = (struct.pack("<I", block["version"])
           + bytes.fromhex(block["previousblockhash"])[::-1]
           + bytes.fromhex(block["merkle_root"])[::-1]
           + struct.pack("<I", block["timestamp"])
           + struct.pack("<I", block["bits"])
           + struct.pack("<I", block["nonce"]))
    if len(raw) != 80:
        raise SystemExit("header is %d bytes, not 80" % len(raw))

    rolled = (block["version"] >> 13) & 0xFFFF
    # Measured shares of each window bit, from the 6980-block corpus.
    shares = [0.4304, 0.4400, 0.4510, 0.4300, 0.4120, 0.3970, 0.3640, 0.3140,
              0.3020, 0.3090, 0.2840, 0.2830, 0.3190, 0.3030, 0.2330, 0.1943]

    payload = {
        "height": block["height"],
        "id": block["id"],
        "bytes": list(raw),
        "fields": [{"name": n, "at": a, "width": w} for n, a, w in FIELDS],
        "values": {
            "version": "0x%08x" % block["version"],
            "timestamp": str(block["timestamp"]),
            "bits": "0x%08x" % block["bits"],
            "nonce": str(block["nonce"]),
            "rolled": "0x%04x" % rolled,
        },
        "windowShares": shares,
        "constants": [{"field": f, "what": w, "value": v, "null": n, "verdict": d, "from": s}
                      for f, w, v, n, d, s in CONSTANTS],
    }

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    if "/*DATA*/" not in page:
        raise SystemExit("template has no /*DATA*/ placeholder: %s" % TEMPLATE)
    page = page.replace("/*DATA*/", json.dumps(payload, separators=(",", ":")))

    with io.open(given.out, "w", encoding="utf-8") as handle:
        handle.write(page)

    tally = {}
    for entry in payload["constants"]:
        tally[entry["verdict"]] = tally.get(entry["verdict"], 0) + 1
    print("wrote %s" % given.out)
    print("  block %d, 80 byte header" % block["height"])
    print("  %d constants: %s" % (len(CONSTANTS),
                                  ", ".join("%d %s" % (v, k) for k, v in sorted(tally.items()))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
