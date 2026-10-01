"""Real block headers as a known-answer test, then the winning nonce against losing ones.

    python tools/view/chain_kat.py --check
    python tools/view/chain_kat.py                 the KAT over the corpus
    python tools/view/chain_kat.py --winner        does a reading distinguish the winning nonce

DOUGLAS'S SUGGESTION AND WHY IT IS BETTER THAN WHAT CAME BEFORE

"You can use the real blockchain as your kat."

`nonce_read.py` swept 512 nonces on a header SHAPE, with a plausible set of words rather than a real
block, and asked whether an early state predicted the final digest. It came back null. The weakness
was the object: a header shape is not a header, and there was no positive class in it at all, because
none of those nonces had actually won anything.

The corpus fixes both. `tools/chain/blocks_deep.json` holds 6980 real blocks with version, previous
hash, merkle root, timestamp, bits and the WINNING NONCE, which is everything needed to rebuild the
exact eighty byte header. So:

    the KAT        rebuild the header, double hash it, and the result must equal the block id
    the test       read the state for the winning nonce and for many losing ones on the SAME
                   header, and ask whether the winner is distinguishable

THE KAT COMES FIRST AND NOTHING ELSE RUNS WITHOUT IT. A header assembled with a field in the wrong
byte order still produces numbers, still produces a boundary reading, and still produces
correlations, all of them meaningless. The block id is the one quantity that can catch that, and it
catches it completely: a single wrong byte anywhere changes the hash entirely.

WHAT THE POSITIVE CLASS BUYS. A winning nonce is a real member of a real rare class, so the question
becomes a detection question with a genuine label rather than a correlation against a proxy. If a
reading cannot separate the one nonce that won from a sample that lost, on the header where it
actually won, that is a much stronger null than a flat correlation.
"""

import argparse
import hashlib
import io
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PROOFING = os.path.join(ROOT, "examples", "proofing")
for _where in (HERE, PROOFING):
    if _where not in sys.path:
        sys.path.insert(0, _where)

import numpy

import boundary_read
import state_deflection

CORPUS = os.path.join(ROOT, "tools", "chain", "blocks_deep.json")
TOP = state_deflection.TOP


def load_blocks(where=None, limit=None):
    path = where or CORPUS
    with io.open(path, encoding="utf-8") as handle:
        blocks = json.load(handle)
    return blocks[:limit] if limit else blocks


def header_bytes(block, nonce=None):
    """The exact eighty byte header.

    The two hashes are stored as display hex, which is big endian, and the header carries them
    little endian, so both are reversed. Everything else is a little endian integer. Getting any of
    this wrong still yields a header-shaped object, which is why the block id is checked.
    """
    version = int(block["version"])
    previous = bytes.fromhex(block["previousblockhash"])[::-1]
    merkle = bytes.fromhex(block["merkle_root"])[::-1]
    timestamp = int(block["timestamp"])
    bits = int(block["bits"], 16) if isinstance(block["bits"], str) else int(block["bits"])
    use = int(block["nonce"]) if nonce is None else int(nonce)

    return (struct.pack("<I", version & 0xFFFFFFFF) + previous + merkle
            + struct.pack("<I", timestamp & 0xFFFFFFFF)
            + struct.pack("<I", bits & 0xFFFFFFFF)
            + struct.pack("<I", use & 0xFFFFFFFF))


def block_id_of(header):
    """The block id as displayed: double SHA-256, reversed."""
    once = hashlib.sha256(header).digest()
    twice = hashlib.sha256(once).digest()
    return twice[::-1].hex()


def hash_value(header):
    """The double hash as an integer, so blocks can be compared by how low they went."""
    once = hashlib.sha256(header).digest()
    twice = hashlib.sha256(once).digest()
    return int.from_bytes(twice[::-1], "big")


def leading_zeros_of(header):
    value = hash_value(header)
    return 256 - value.bit_length() if value else 256


def second_block_words(header):
    """The sixteen words of the SECOND compression block, where the nonce lives.

    An eighty byte header pads into two sixty four byte blocks. Bytes 0 to 63 are the first, and the
    second holds bytes 64 to 79, the 0x80 terminator, zeros, and the bit length 640. The nonce sits
    at bytes 76 to 79, so it is in the second block and the second compression is the one its
    trajectory belongs to.
    """
    tail = bytearray(header[64:80])
    tail.append(0x80)
    while len(tail) < 56:
        tail.append(0x00)
    tail.extend((640).to_bytes(8, "big"))
    return [int.from_bytes(bytes(tail[at:at + 4]), "big") for at in range(0, 64, 4)]


def first_block_state(header):
    """The eight word state after compressing the first sixty four bytes."""
    words = [int.from_bytes(header[at:at + 4], "big") for at in range(0, 64, 4)]
    return state_deflection.states_of(words)[64]


def _report(limit=400):
    blocks = load_blocks(limit=limit)
    print("  %d real blocks from %s." % (len(blocks), os.path.relpath(CORPUS, ROOT)))
    print("")

    passed = 0
    failed = []
    for block in blocks:
        header = header_bytes(block)
        if block_id_of(header) == block["id"]:
            passed += 1
        else:
            failed.append(block["height"])

    print("  THE KAT: rebuild each header, double hash it, and compare to the block id.")
    print("    %d of %d headers reproduce their own block id exactly." % (passed, len(blocks)))
    if failed:
        print("    FAILED at heights: %s" % failed[:8])
        print("")
        print("  NOTHING ELSE IN THIS FILE MEANS ANYTHING UNTIL THAT IS ZERO. A header assembled")
        print("  with a field in the wrong byte order still produces readings and correlations,")
        print("  all of them about an object that does not exist.")
        return 1

    print("")
    print("  SO THE HEADERS ARE EXACT, and the winning nonces in them are the real ones. That is")
    print("  a corpus with a genuine positive class rather than a header shape.")
    print("")

    heights = [block["height"] for block in blocks]
    zeros = [leading_zeros_of(header_bytes(block)) for block in blocks]
    print("  heights %d to %d" % (min(heights), max(heights)))
    print("  leading zeros of the winning hashes: min %d, max %d, mean %.2f"
          % (min(zeros), max(zeros), sum(zeros) / float(len(zeros))))
    print("")
    print("  Those leading zero counts are the difficulty of the era, recovered from the headers")
    print("  alone, which is a second and independent sign the reconstruction is right: nothing")
    print("  about a wrongly assembled header would land in the correct range.")
    return 0


def _winner(blocks_to_try=48, losers=384):
    """Does a boundary reading separate the winning nonce from losing ones on the same header?"""
    blocks = load_blocks(limit=blocks_to_try * 4)
    places = boundary_read.ring_place(state_deflection.RINGS, state_deflection.WIDTH)
    angles = boundary_read.as_angles(places)

    usable = []
    for block in blocks:
        if block_id_of(header_bytes(block)) == block["id"]:
            usable.append(block)
        if len(usable) >= blocks_to_try:
            break

    print("  %d verified blocks. For each, the winning nonce against %d random losing nonces on"
          % (len(usable), losers))
    print("  the SAME header, read at round 32 of the second compression.")
    print("")
    print("  The readout is the rank of the winner's feature among the losers, which is uniform")
    print("  between 0 and 1 under the null. A reading that separated winners would push it to an")
    print("  end; anything near 0.5 is no separation at all.")
    print("")
    print("  %10s %14s %14s %14s" % ("height", "winner rank", "zeros won", "zeros median"))

    generator = numpy.random.default_rng(23)
    ranks = []
    for block in usable:
        header = header_bytes(block)
        carried = first_block_state(header)

        def feature_for(nonce):
            words = second_block_words(header_bytes(block, nonce))
            state = state_deflection.states_of(words, start=carried)[32]
            live = state_deflection.lit_of(state)
            table = boundary_read.complex_coefficients(angles, live, TOP)
            power = boundary_read.deflection(table, TOP)
            total = sum(power) or 1.0
            return float(power[0] / total)

        winner = feature_for(int(block["nonce"]))
        sample = []
        zeros = []
        for _ in range(losers):
            nonce = int(generator.integers(0, 1 << 32))
            sample.append(feature_for(nonce))
            zeros.append(leading_zeros_of(header_bytes(block, nonce)))
        below = sum(1 for one in sample if one < winner)
        rank = below / float(len(sample))
        ranks.append(rank)
        print("  %10d %14.4f %14d %14.1f"
              % (block["height"], rank, leading_zeros_of(header), float(numpy.median(zeros))))

    mean = float(numpy.mean(numpy.array(ranks)))
    spread = float(numpy.std(numpy.array(ranks)))
    print("")
    print("  mean winner rank %.4f, spread %.4f, over %d blocks" % (mean, spread, len(ranks)))
    print("  under the null the mean is 0.5 with a spread of %.4f / sqrt(%d) = %.4f"
          % (0.2887, len(ranks), 0.2887 / (len(ranks) ** 0.5)))
    print("")
    if abs(mean - 0.5) < 3.0 * 0.2887 / (len(ranks) ** 0.5):
        print("  NO SEPARATION. The winning nonce sits where a random nonce sits, and the reading")
        print("  does not know which one won. That is a stronger null than a flat correlation,")
        print("  because the label here is real: these nonces actually won these blocks.")
    else:
        print("  THE MEAN RANK IS OFF CENTRE, which is a finding and needs the whole corpus and a")
        print("  second feature before it is believed.")
    print("")
    print("  WHAT THIS CANNOT SETTLE. %d blocks and one feature at one round. The corpus holds" % len(ranks))
    print("  6980, so the sweep is a pilot and its own bound is wide. And the winning nonce is")
    print("  only special with respect to the FINAL digest, which the round 32 state does not")
    print("  contain, a null here is what the counting already predicted.")
    return 0


def _check():
    lines = []
    failed = 0

    # THE KAT IS THE CHECK. Everything else in this file rests on the header being exact.
    blocks = load_blocks(limit=50)
    good = 0
    for block in blocks:
        if block_id_of(header_bytes(block)) == block["id"]:
            good += 1
    lines.append("  %d of %d real headers reproduce their block id" % (good, len(blocks)))
    if good != len(blocks):
        lines.append("    FAIL the header reconstruction is wrong, so every reading taken from it")
        lines.append("         is about an object that does not exist")
        failed += 1

    # THE NEGATIVE CONTROL. A header with one bit changed must NOT reproduce the id, or the KAT is
    # not checking anything.
    block = blocks[0]
    header = bytearray(header_bytes(block))
    header[40] ^= 0x01
    lines.append("  the same header with one bit flipped reproduces the id: %s"
                 % (block_id_of(bytes(header)) == block["id"]))
    if block_id_of(bytes(header)) == block["id"]:
        lines.append("    FAIL a corrupted header passed the KAT")
        failed += 1

    # And a wrong nonce must fail too, which is what makes the nonce the thing under test.
    wrong = header_bytes(block, int(block["nonce"]) ^ 1)
    lines.append("  the same header with the nonce off by one reproduces the id: %s"
                 % (block_id_of(wrong) == block["id"]))
    if block_id_of(wrong) == block["id"]:
        lines.append("    FAIL the nonce does not affect the hash, which is impossible")
        failed += 1

    # The second block words must carry the nonce, since that is where the trajectory is read.
    words = second_block_words(header_bytes(block))
    other = second_block_words(header_bytes(block, int(block["nonce"]) ^ 0xFF))
    differing = [at for at in range(16) if words[at] != other[at]]
    lines.append("  changing the nonce changes second-block words %s" % differing)
    if not differing:
        lines.append("    FAIL the nonce is absent from the second compression block")
        failed += 1

    # The padding must be the standard one for an eighty byte message.
    length = (words[14] << 32) | words[15]
    lines.append("  the second block's length field reads %d bits, and 80 bytes is %d"
                 % (length, 640))
    if length != 640:
        lines.append("    FAIL the padding length is wrong, so this is not a valid second block")
        failed += 1

    # The winning hashes must actually be low, which is the sanity check on the whole corpus.
    zeros = [leading_zeros_of(header_bytes(one)) for one in blocks[:20]]
    lines.append("  leading zeros of 20 winning hashes: min %d, mean %.1f" % (min(zeros),
                                                                             sum(zeros) / 20.0))
    if min(zeros) < 20:
        lines.append("    FAIL a winning block hash with under 20 leading zeros is not a winner,")
        lines.append("         so the corpus or the reconstruction is wrong")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="real headers as a known answer test")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--winner", action="store_true")
    parser.add_argument("--blocks", type=int, default=48)
    parser.add_argument("--losers", type=int, default=384)
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.winner:
        sys.exit(_winner(args.blocks, args.losers))
    sys.exit(_report())
