"""One bit flipped at the tail of a message, read as a deforming surface, round by round.

    python tools/view/tail_bit.py --check
    python tools/view/tail_bit.py                  the onset and what follows it

THE EXPERIMENT DOUGLAS ASKED FOR

Inject a one at the very tail of the message, right before the padding closes it, and watch the
surface. The state is read as a lit set on a boundary and the quantity reported is the deformation
scalar from `deform_rate`: the fraction of the reading's change that no rigid rotation explains.

WHY THE SCHEDULE MAKES THIS A CLEAN MEASUREMENT RATHER THAN A PICTURE

The flipped bit sits in schedule word 13, and round r consumes word r. So rounds 0 through 12 cannot
have seen it, and the first fourteen states must be BIT-IDENTICAL between the two messages. That is
a free exact null sitting in front of the experiment: if any of those rounds shows a nonzero
reading, the instrument is broken and nothing after it counts. The onset is therefore predicted and
not discovered, and the interesting question is only what the onset looks like and how long it
lasts.

Three regimes are expected, and the middle one is the only place a claim about revealing anything
could live:

    rounds 0 to 12     identical, exactly. The bit has not arrived.
    the onset          a few bits differ. The deformation is partial and localised.
    after saturation   half the bits differ. The deformation is total and carries no structure.

WHAT THIS TREE HAS ALREADY FOUND, STATED BEFORE THE RUN

The transform workbook's hypotheses came back null: survivor counts track the cost model exactly,
no bit or byte position departs from flat, and no projection over the digest reduces the number of
evaluations at all. The avalanche is designed to erase. So the honest prior is that the surface
deforms completely and reveals nothing, and the measurement worth having is the WIDTH of the onset
window, because that is the only interval in which the deformation is not yet total.

A large deformation is not a revelation. Saturation and structure look identical in any single
number, which is why the round count and the Hamming distance are printed beside the scalar.
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# Walks up from tools/view to the repository root rather than naming any directory along the way.
# The first version of this line carried the repository's own name as a path fallback, which the
# name guard denied the commit over, correctly: a tracked file naming that directory writes the
# banned name into every commit that holds it, and deleting the line later does not remove it.
ROOT = os.path.dirname(os.path.dirname(HERE))
PROOFING = os.path.join(ROOT, "examples", "proofing")
for _where in (HERE, PROOFING):
    if _where not in sys.path:
        sys.path.insert(0, _where)

import boundary_read
import deform_rate
import state_deflection

TOP = state_deflection.TOP

# The block is a 55 byte message, which is the longest that pads into a single block: 55 message
# bytes, the 0x80 close, then the 64 bit length. So byte 54 is the last message byte and byte 55 is
# the close itself.
MESSAGE_BYTES = 55

# Word 13 holds bytes 52 to 55, big endian, so byte 54 occupies bits 15 to 8 and its lowest bit is
# bit 8 of the word. That bit is the last bit of the message, immediately before the close.
TAIL_WORD = 13
TAIL_BIT = 8


def padded_block(fill=0x61):
    """A single block holding a 55 byte message, padded exactly as the standard requires."""
    data = bytearray([fill] * MESSAGE_BYTES)
    data.append(0x80)
    while len(data) < 56:
        data.append(0x00)
    bits = MESSAGE_BYTES * 8
    data.extend(bits.to_bytes(8, "big"))
    return [int.from_bytes(bytes(data[at:at + 4]), "big") for at in range(0, 64, 4)]


def with_tail_flipped(block):
    """The same block with the final message bit flipped, and nothing else touched."""
    out = list(block)
    out[TAIL_WORD] ^= (1 << TAIL_BIT)
    return out


def hamming(one, two):
    """Bits differing between two eight word states."""
    return sum(bin(a ^ b).count("1") for a, b in zip(one, two))


def reading_of(state, angles):
    """The boundary table of one state's lit set, as complex values.

    `boundary_read.complex_coefficients` returns (real, imaginary) TUPLES, which is the convention
    every reader in that module expects, and `deform_rate` works on complex numbers. The conversion
    belongs here at the boundary between the two rather than in either of them. The first version
    of this passed the tuples straight through and raised on subtracting one from another.
    """
    table = boundary_read.complex_coefficients(angles, state_deflection.lit_of(state), TOP)
    return {key: complex(real, imaginary) for key, (real, imaginary) in table.items()}


def _report():
    block = padded_block()
    flipped = with_tail_flipped(block)
    places = boundary_read.ring_place(state_deflection.RINGS, state_deflection.WIDTH)
    angles = boundary_read.as_angles(places)

    clean = state_deflection.states_of(block)
    dirty = state_deflection.states_of(flipped)

    print("  A 55 byte message in one block. Bit %d of schedule word %d flipped, which is the last"
          % (TAIL_BIT, TAIL_WORD))
    print("  message bit before the close. Read to degree %d on %d ring positions."
          % (TOP, state_deflection.TOTAL))
    print("")
    print("  Round r consumes schedule word r, so rounds 0 to %d cannot have seen the bit."
          % (TAIL_WORD - 1))
    print("")
    print("  %6s %9s %9s %14s %14s" % ("round", "bits diff", "of 256", "scalar", "total change"))

    onset = None
    saturated = None
    rows = []
    for at in range(len(clean)):
        bits = hamming(clean[at], dirty[at])
        if bits == 0:
            scalar, total = 0.0, 0.0
        else:
            scalar, _alpha, total = deform_rate.deformation_scalar(
                reading_of(clean[at], angles), reading_of(dirty[at], angles))
        rows.append((at, bits, scalar, total))
        if bits > 0 and onset is None:
            onset = at
        if bits >= 100 and saturated is None:
            saturated = at
        if at <= 2 or (onset is not None and at <= onset + 14) or at % 8 == 0 or at == 64:
            print("  %6d %9d %9.1f%% %14.4e %14.4e"
                  % (at, bits, 100.0 * bits / 256.0, scalar, total))

    print("")
    identical = [at for at, bits, _s, _t in rows if bits == 0]
    print("  EXACTLY IDENTICAL FOR ROUNDS %d THROUGH %d, which is the prediction the schedule makes"
          % (min(identical), max(identical)))
    print("  and the free null in front of this experiment. Every reading there is zero because the")
    print("  states are the same numbers, not because the arithmetic was good.")
    print("")
    if onset is not None:
        first = rows[onset]
        print("  ONSET AT ROUND %d with %d bits differing, scalar %.4f."
              % (onset, first[1], first[2]))
    if saturated is not None:
        print("  PAST 100 OF 256 BITS BY ROUND %d, so the onset window is %d rounds wide."
              % (saturated, saturated - onset))
    ending = rows[-1]
    print("  AT ROUND 64: %d of 256 bits differ, %.1f%%, scalar %.4f."
          % (ending[1], 100.0 * ending[1] / 256.0, ending[2]))
    print("")
    print("  THE SCALAR SATURATES AND THAT IS THE ANSWER, NOT A PRELUDE TO ONE. A value near one")
    print("  means no rigid motion explains any part of the change, which is what total")
    print("  reorganisation looks like. Structure would look like a scalar BELOW one holding")
    print("  steady, because that would be a change with a recoverable rigid part in it.")
    print("")
    print("  SO THE SURFACE DEFORMS COMPLETELY AND THE DEFORMATION CARRIES NO CONSTITUENTS.")
    print("  The onset window above is the only interval where the deformation is partial, and it")
    print("  is a handful of rounds out of sixty four. This agrees with everything else this tree")
    print("  has measured on SHA-256: the avalanche is designed to erase and it erases. A large")
    print("  deformation is not a revelation, and saturation and structure are indistinguishable")
    print("  in any single number, which is why the bit count is printed beside the scalar.")
    return 0


def _check():
    lines = []
    failed = 0

    block = padded_block()
    flipped = with_tail_flipped(block)

    # The flip must change exactly one bit of exactly one word, or the experiment is not the one
    # described. A padding byte touched by accident would change the message length instead.
    diff = [at for at in range(16) if block[at] != flipped[at]]
    bits = sum(bin(block[at] ^ flipped[at]).count("1") for at in range(16))
    lines.append("  the flip touches words %s and %d bit(s) in total" % (diff, bits))
    if diff != [TAIL_WORD] or bits != 1:
        lines.append("    FAIL the injection is not a single bit in a single word")
        failed += 1

    # The bit flipped must be inside the MESSAGE and not inside the padding, or this measures a
    # different message length rather than a tail bit.
    closer = (block[TAIL_WORD] >> 7) & 0x1FF
    lines.append("  word %d is %08x, so the close byte 0x80 sits in its low byte: %s"
                 % (TAIL_WORD, block[TAIL_WORD], (block[TAIL_WORD] & 0xFF) == 0x80))
    if (block[TAIL_WORD] & 0xFF) != 0x80:
        lines.append("    FAIL the padding close is not where this file thinks it is, so the")
        lines.append("         'right before close' position is wrong")
        failed += 1
    del closer

    # Length words must be the real bit length, or the block is not a valid padded message.
    length = (block[14] << 32) | block[15]
    lines.append("  the length words read %d bits, and the message is %d bytes"
                 % (length, MESSAGE_BYTES))
    if length != MESSAGE_BYTES * 8:
        lines.append("    FAIL the padding length is wrong, so this is not a standard block")
        failed += 1

    # THE FREE NULL. Rounds before the word is consumed must be bit identical. This is the control
    # that decides whether anything later means anything.
    clean = state_deflection.states_of(block)
    dirty = state_deflection.states_of(flipped)
    early = [at for at in range(TAIL_WORD + 1) if clean[at] != dirty[at]]
    lines.append("  states 0 to %d are bit identical: %s"
                 % (TAIL_WORD, "yes" if not early else "NO at %s" % early))
    if early:
        lines.append("    FAIL a round that cannot have seen the bit already differs")
        failed += 1

    # And the reading of two identical states must be exactly zero, not merely small.
    places = boundary_read.ring_place(state_deflection.RINGS, state_deflection.WIDTH)
    angles = boundary_read.as_angles(places)
    scalar, _alpha, total = deform_rate.deformation_scalar(
        reading_of(clean[5], angles), reading_of(dirty[5], angles))
    lines.append("  the reading at round 5, both messages: scalar %.1e, total change %.1e"
                 % (scalar, total))
    if total != 0.0:
        lines.append("    FAIL two identical states produced different readings")
        failed += 1

    # THE POSITIVE CONTROL. The bit must actually arrive, or the whole run is a null caused by a
    # broken injection rather than by the schedule.
    late = hamming(clean[-1], dirty[-1])
    lines.append("  at round 64, %d of 256 bits differ" % late)
    if late < 50:
        lines.append("    FAIL one tail bit did not avalanche, so either the injection or the")
        lines.append("         compression is wrong")
        failed += 1

    # The onset must be exactly where the schedule says, which is a prediction and not a fit.
    onset = next((at for at in range(len(clean)) if clean[at] != dirty[at]), None)
    lines.append("  first differing state is %s, and the schedule predicts %d"
                 % (onset, TAIL_WORD + 1))
    if onset != TAIL_WORD + 1:
        lines.append("    FAIL the onset is not where consuming word %d would put it" % TAIL_WORD)
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="one tail bit, read as a deforming surface")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    sys.exit((1 if _check() else 0) if args.check else _report())
