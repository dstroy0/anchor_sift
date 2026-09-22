"""Builds the residue A-scope: four readings of one compression state, in one frame.

The other generators here draw one measurement each. This one puts four on the same object at the
same depth, because the question they answer together is not answerable by any of them alone:

    state boundary      the 256 state bits as spikes, with a persistence smear across depth and a
                        tracer ring on every bit that ignited or went out entering this round
    residue spectrum    the 32 dependency classes at that depth, against the null band
    round by class      all 64 depths and all 32 classes at once, so the window where the signal
                        lives and the depth where it collapses are one glance rather than a scrub
    matched filter      the whole trajectory of the pre-registered waveform through depth

WHAT THE COLOURS CARRY

The stick colouring is selectable because different questions want different tags, and two of them
are structural rather than decorative:

    hot     lit or unlit, which is the state itself
    a.e     the two computed words against the six carried ones. SHA-256's round computes a and e
            and shifts the rest along unchanged, so this tag makes the shift register visible as
            motion instead of as a fact in a document
    word    one hue per state word, for following a single word through the rounds
    dwell   how many rounds a bit has held its value, which separates the frozen from the churning

THE WAVEFORM IS NAMED BEFORE THE DATA IS OPENED

Classes 0, 31, 6, 11 and 25 are the diagonal, the carry at -1 mod 32, and Sigma1's three rotation
amounts. SHA-256 moves bits across positions in exactly those ways and no others, so the waveform
is read off the round function rather than chosen after looking at the spectrum, and its matched
filter carries no multiple-comparison penalty. That is the whole reason the number means anything.

    python tools/view/build_scope_view.py
    python tools/view/build_scope_view.py --block 4 --out somewhere.html

  --block   which block of the corpus supplies the header. Default: 0, the newest.
  --out     where to write. Default: scope_view.html beside this script.
"""

import argparse
import csv
import io
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TEMPLATE = os.path.join(HERE, "scope_view_template.html")
CORPUS = os.path.join(ROOT, "tools", "chain", "blocks.json")
SHADOWS = os.path.join(ROOT, "src", "bench", "shadows.csv")

sys.path.insert(0, os.path.join(ROOT, "examples", "proofing"))

import boundary_read
import state_deflection

RINGS = 8
WIDTH = 32

# The transport the round function actually has. Named here, before shadows.csv is opened.
DIAGONAL = 0
CARRY = 31
SIGMA0 = (2, 13, 22)
SIGMA1 = (6, 11, 25)
WAVEFORM = (DIAGONAL, CARRY) + SIGMA1


def header_words(block):
    """The eighty byte header's first sixteen words, big-endian as SHA-256 reads them."""
    raw = (struct.pack("<I", block["version"])
           + bytes.fromhex(block["previousblockhash"])[::-1]
           + bytes.fromhex(block["merkle_root"])[::-1]
           + struct.pack("<I", block["timestamp"])
           + struct.pack("<I", block["bits"])
           + struct.pack("<I", block["nonce"]))
    return [int.from_bytes(raw[at:at + 4], "big") for at in range(0, 64, 4)]


def spike_directions():
    """The 256 boundary points as unit vectors, in the placement the reading itself uses."""
    points = boundary_read.ring_place(RINGS, WIDTH)
    out = []
    for theta, phi in boundary_read.as_angles(points):
        out.append([round(math.sin(theta) * math.cos(phi), 6),
                    round(math.cos(theta), 6),
                    round(math.sin(theta) * math.sin(phi), 6)])
    return out


def lit_per_round(words):
    """One 256 bit mask per round, as hex, word zero's high bit first."""
    states = state_deflection.states_of(words)
    out = []
    for step in range(len(states)):
        mask = 0
        for index, word in enumerate(states[step]):
            for bit in range(32):
                if (word >> (31 - bit)) & 1:
                    mask |= 1 << (index * 32 + bit)
        out.append(format(mask, "064x"))
    return out


def standardised_spectrum():
    """Each class's deviation from the class mean, in units of the scatter of the other classes.

    The common mode is removed first because incomplete avalanche and the schedule's light cone are
    both independent of the output bit and so spread evenly over all thirty-two residues. A reading
    that leaves the offset in reports the offset instead of the target.
    """
    by_depth = {}
    with io.open(SHADOWS, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if row["kind"] != "residue":
                continue
            by_depth.setdefault(int(row["round"]), {})[int(row["a"])] = float(row["value"])

    spectrum = {}
    for depth in sorted(by_depth):
        values = [by_depth[depth].get(k, 0.0) for k in range(32)]
        mean = sum(values) / 32.0
        row = []
        for skip in range(32):
            rest = [values[k] for k in range(32) if k != skip]
            rest_mean = sum(rest) / len(rest)
            variance = sum((v - rest_mean) ** 2 for v in rest) / (len(rest) - 1)
            scatter = variance ** 0.5 if variance > 0 else 1.0
            row.append(round((values[skip] - mean) / scatter, 4))
        spectrum[depth] = row
    return spectrum


def main():
    parser = argparse.ArgumentParser(description="Build the residue A-scope.")
    parser.add_argument("--block", type=int, default=0,
                        help="index into the block corpus, newest first. Default 0.")
    parser.add_argument("--out", default=os.path.join(HERE, "scope_view.html"))
    given = parser.parse_args()

    with io.open(CORPUS, encoding="utf-8") as handle:
        blocks = json.load(handle)
    if not 0 <= given.block < len(blocks):
        raise SystemExit("block index out of range: corpus holds %d" % len(blocks))
    block = blocks[given.block]

    payload = {
        "height": block["height"],
        "nonce": int(block["nonce"]),
        "id": block["id"],
        "spikes": spike_directions(),
        "rounds": lit_per_round(header_words(block)),
        "spectrum": standardised_spectrum(),
        "waveform": list(WAVEFORM),
        "sigma0": list(SIGMA0),
        "sigma1": list(SIGMA1),
    }

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    if "/*DATA*/" not in page:
        raise SystemExit("template has no /*DATA*/ placeholder: %s" % TEMPLATE)
    page = page.replace("/*DATA*/", json.dumps(payload, separators=(",", ":")))

    with io.open(given.out, "w", encoding="utf-8") as handle:
        handle.write(page)

    print("wrote %s" % given.out)
    print("  block  %d, nonce %d" % (block["height"], int(block["nonce"])))
    print("  spikes %d, rounds %d, depths %d..%d"
          % (len(payload["spikes"]), len(payload["rounds"]),
             min(payload["spectrum"]), max(payload["spectrum"])))
    print("  waveform %s, named from the round function" % (list(WAVEFORM),))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
