"""Lexes SHA-256's morphing boundary into a language: eight octant letters, round by round.

    python tools/view/octant_lex.py --check
    python tools/view/octant_lex.py --message "abc"

  --message   the block to compress. Default the empty message, padded.
  --top       highest harmonic degree the readings use. Default 8.

WHAT THIS READS

Space splits into eight octants sharing one trilateral right-angle corner at the origin, and on the
boundary that split cuts eight congruent spherical triangles of area pi/2 each. A state of the
object writes one letter in each octant, the letter being what share of the lit set sits there, and
a round rewrites all eight at once. The eight numbers tracked across the rounds are the word the
computation spells, and this prints it.

Three things come out of the reading, and all three are the same table read differently:

    delta       how much of the reading moved this round, as a percentage of the whole. Small early
                and large once the mixing has taken hold.
    coherence   what share of the rounds wrote a signature no other round wrote. A collision is a
                null permutation: a move this reading cannot see.
    turn        the rotation recovered from the twist, in radians, with the sign giving which way.

The geometry, the placements and the three readings live in boundary_read, which knows nothing about
hashes. What is here is the part that knows: the compression, and what to ask of it.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import boundary_read
import build_sha_clock_view as clock
import build_sha_pairs_view as sha

WORDS = 8
WIDTH = 32
BITS = WORDS * WIDTH
ROUNDS = 64


def live_of(text):
    """The indices of the lit bits in a state written as a string of ones and zeroes."""
    return [at for at in range(len(text)) if text[at] == "1"]


# Which word a round copies each carried word from. A round sets b to a's old value, c to b's, d to
# c's, f to e's, g to f's and h to g's, so those six are copied and never computed.
CARRIED = ((1, 0), (2, 1), (3, 2), (5, 4), (6, 5), (7, 6))


def rounds_of(message, read="state"):
    """The 256 bits after each round, taken either from the working state or from the digest.

    THE DIFFERENCE MATTERS AND IT IS NOT SMALL

    The digest reading adds the initial values back into every word before handing the frame over.
    That feed-forward is a mixing step applied after the round has finished, and it is applied to
    every frame, so it hides the structure the round itself put there. Measuring the digest sequence
    and reporting it as a property of the round is measuring the wrong object.

    The working state is the eight words as the round leaves them, with nothing added back, and the
    register shift is visible only in that. Every earlier reading here used the digest, so the
    working state is the default now and the digest is kept as something to compare against.
    """
    block = sha.padded(message)
    if block is None:
        return None, None

    if read == "digest":
        frames = []
        words = None
        for count in range(1, ROUNDS + 1):
            text, words = sha.digest_after(block, count)
            frames.append(text)
        return frames, "".join("%08x" % one for one in words)

    # The clock traces every operation, so the state after a round is the last operation of it.
    every, digest = clock.trace(block, ROUNDS)
    frames = [every[at * clock.OPS + clock.OPS - 1] for at in range(ROUNDS)]
    return frames, "".join("%08x" % one for one in digest)


def shift_structure(frames):
    """How many of the six carried words survive a round exactly, once the shift is undone.

    The decisive test of which object is being read. Those six words are copied, so on the working
    state every one of them has to match the word it came from, exactly, every round. A reading where
    none of them matches is a reading of something the round has been mixed into after the fact.
    """
    hits = 0
    total = 0
    for at in range(1, len(frames)):
        before, after = frames[at - 1], frames[at]
        for to, frm in CARRIED:
            total += 1
            if after[to * WIDTH:(to + 1) * WIDTH] == before[frm * WIDTH:(frm + 1) * WIDTH]:
                hits += 1
    return hits, total


def lexicon(frames, points):
    """The eight-letter signature of every round, and the delta from the round before it."""
    rows = []
    last = None
    for at, frame in enumerate(frames):
        share = boundary_read.octant_share(points, live_of(frame))
        delta = 0.0 if last is None else boundary_read.octant_delta(last, share)
        rows.append((at + 1, share, delta))
        last = share
    return rows


def redraw_level(points, lit_count, seed=9, tries=200):
    """The delta two independent random states of the same weight give, as a baseline.

    Without this the delta is a number with no scale. Eight letters over 256 bits is a coarse
    alphabet, and two unrelated states of the same weight already differ by a few percent in it just
    from the counting noise, and a measured delta only means something held against that. A reading
    sitting at this level is saturated: it is reporting noise at full volume and has no room left to
    show the mixing taking hold.
    """
    state = (seed ^ 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF

    def pick():
        nonlocal state
        order = list(range(len(points)))
        for at in range(len(order) - 1, 0, -1):
            state = (state * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
            swap = (state >> 33) % (at + 1)
            order[at], order[swap] = order[swap], order[at]
        return order[:lit_count]

    total = 0.0
    for _ in range(tries):
        total += boundary_read.octant_delta(
            boundary_read.octant_share(points, pick()),
            boundary_read.octant_share(points, pick()))
    return total / tries


def coherence(rows):
    """What share of the rounds wrote a signature no other round wrote, and the collisions.

    Rounded before it is compared, because two signatures that agree to a part in a million are the
    same letter for any purpose a reader has, and comparing raw floats would call them distinct on
    the last bit of the mantissa.
    """
    seen = {}
    for at, share, _ in rows:
        key = tuple(round(one, 6) for one in share)
        seen.setdefault(key, []).append(at)
    nulls = [group for group in seen.values() if len(group) > 1]
    return len(seen) / float(len(rows)), nulls


def main():
    argv = sys.argv[1:]
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        return 2

    def option(flag, fallback, cast=str):
        if flag in argv:
            return cast(argv[argv.index(flag) + 1])
        return fallback

    message = option("--message", "")
    top = option("--top", 8, int)
    if top < 1 or top > 16:
        sys.stderr.write("--top sits between 1 and 16\n")
        return 2

    read = option("--read", "state")
    if read not in ("state", "digest"):
        sys.stderr.write("--read takes state or digest\n")
        return 2

    frames, digest = rounds_of(message.encode("utf-8"), read)
    if frames is None:
        sys.stderr.write("--message has to fit one block, which is 55 bytes at most\n")
        return 2

    points = boundary_read.golden_place(BITS)
    angles = boundary_read.as_angles(points)
    rows = lexicon(frames, points)
    share, nulls = coherence(rows)

    out = []
    out.append("  sha-256 compressing %s" % ("the empty message" if not message else repr(message)))
    out.append("  256 bits on a golden placement, read to degree %d" % top)
    out.append("  reading the %s" % ("working state" if read == "state" else "finalized digest"))
    out.append("")

    # Which object is on the table, settled by counting the words a round copies without change.
    hits, total = shift_structure(frames)
    out.append("  the six carried words, checked against the words they are copied from")
    out.append("    %d of %d match exactly, which is %.1f%%" % (hits, total, 100.0 * hits / total))
    if hits == total:
        out.append("    all of them, so this is the round's own state and the shift is in it")
    elif hits == 0:
        out.append("    none of them, so something has been mixed in after the round finished")
    out.append("")

    # The screw a rotate comes to on this placement, and the reason the letters are predictable.
    turn, slide, pitch = boundary_read.screw_of(BITS, 1)
    out.append("  one index of shift on this placement is a rigid screw")
    out.append("    turn %.6f rad, axial slide %.6f, pitch %.9f" % (turn, slide, pitch))
    out.append("    the pitch holds for every amount, so one helix carries them all")
    out.append("")

    out.append("  the word, round by round")
    out.append("    round " + " ".join("oct%d " % q for q in range(8)) + "  delta")
    for at, letters, delta in rows:
        if at <= 4 or at in (8, 16, 24, 32, 48, 64):
            out.append("     %3d  " % at + " ".join("%.3f" % one for one in letters)
                       + "   %5.1f%%" % delta)
    out.append("")

    moves = [delta for _, _, delta in rows[1:]]
    early = sum(moves[:8]) / 8.0
    late = sum(moves[-8:]) / 8.0
    floor = redraw_level(points, len(live_of(frames[0])))
    out.append("    the delta averages %.1f%% over the first eight rounds and %.1f%% over the last"
               % (early, late))
    out.append("    two unrelated states of the same weight differ by %.1f%% in this alphabet" % floor)
    early_ratio = early / floor if floor else 0.0
    late_ratio = late / floor if floor else 0.0
    out.append("    against that floor the delta runs %.2f early and %.2f late"
               % (early_ratio, late_ratio))

    # Three outcomes and they mean different things, so the number is not left to speak for itself.
    #
    # WHAT IS MEASURED HERE AND WHAT IS NOT, because this output is the thing a reader trusts most
    # and it was overstating its case.
    #
    # Measured: where the delta sits against a floor built the same way, and whether it crosses that
    # floor between the ends of the run. Both are counts against a redraw baseline.
    #
    # Not measured: WHY it sits there. A move that carries mass coherently from octant to octant
    # shifts the shares further than a scramble of them would, and a rigid relabeling of the indices
    # is such a move, so the register shift is a candidate cause of an excess over the floor. It is a
    # candidate and nothing here tests it. Separately, and this part IS counted, the shift is present
    # in the working state exactly: all 378 carried words match. Those are two different claims --
    # the shift being in the object, and the shift being what moved the delta -- and only the first
    # has a count behind it.
    #
    # The documents were corrected to hold that split and this tool disagreed with them in public
    # until now. A tool and a document that disagree leave a reader to pick, and they will pick the
    # tool.
    if early_ratio > 1.15:
        out.append("    early rounds move it further than independence, which is the alphabet")
        out.append("    responding to something the redraw baseline does not contain")
        out.append("    WHY is not measured here. A move carrying mass coherently from octant to")
        out.append("    octant would do this, and a rigid relabeling of the indices is such a move,")
        out.append("    so the register shift is a candidate cause and no more than a candidate")
    elif early_ratio > 0.85:
        out.append("    early rounds sit at the floor, so the reading is saturated and carries")
        out.append("    nothing but the counting noise of eight letters over 256 bits")
    else:
        out.append("    early rounds move it less than independence, so the octants can see")
        out.append("    something the round conserves")
    if early_ratio > 1.0 and late_ratio < 1.0:
        out.append("    the delta crosses the floor between the two ends of the run, so this is a")
        out.append("    trend and never a level. Whatever the excess was, the later rounds spend it")

    # The turn between the first and last round, read off the twist.
    first = boundary_read.torsion(
        boundary_read.complex_coefficients(angles, live_of(frames[0]), top), top)
    final = boundary_read.torsion(
        boundary_read.complex_coefficients(angles, live_of(frames[-1]), top), top)
    got = boundary_read.turn_between(first, final)
    if got is not None:
        out.append("    the twist between round 1 and round %d reads %.6f radians" % (ROUNDS, got))
    out.append("")

    # The rank first, and the distinctness second, because in the other order the distinctness
    # reads as the result and it is the cheaper number by a wide margin.
    #
    # The eight shares are a linear map from the lit set to eight counts, so it has rank 8 at most.
    # At fixed weight they carry one constraint, leaving seven free numbers, and every direction of
    # the source space beyond those seven moves no letter at all. That is a bound on the reading and
    # no sample size, precision or probe count moves it.
    free = len(boundary_read.OCTANTS) - 1
    blind = len(angles) - len(boundary_read.OCTANTS)
    out.append("    the alphabet is a rank-%d map on %d sources: %d free numbers at fixed weight,"
               % (len(boundary_read.OCTANTS), len(angles), free))
    out.append("    and %d directions of the source that move no letter at all" % blind)
    out.append("    %d rounds wrote %d distinct signatures, coherence %.1f%%"
               % (len(rows), int(round(share * len(rows))), 100.0 * share))
    if nulls:
        for group in nulls:
            out.append("    null permutation: rounds %s share one signature" % (group,))
    else:
        out.append("    no null permutations, and against that rank it is close to free: %d real"
                   % free)
        out.append("    numbers separate %d unrelated states whether or not the %d carry meaning,"
                   % (len(rows), free))
        out.append("    so distinctness here is not evidence. Evidence would be a delta below the")
        out.append("    redraw level, or a signature that predicts the round it came from")
    out.append("")
    out.append("  digest: %s" % digest)

    sys.stdout.write("\n".join(out) + "\n")

    if "--check" in argv:
        # The digest is the check that the trace is the hash and not something shaped like it.
        want = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        failed = 0
        if not message and digest != want:
            sys.stdout.write("  FAIL the empty message did not give the published digest\n")
            failed += 1
        if abs(sum(rows[0][1]) - 1.0) > 1e-12:
            sys.stdout.write("  FAIL the eight letters do not add to one\n")
            failed += 1
        # Which object is being read, checked by counting and not asserted. The six carried words
        # are copied by the round, so on the working state every one of them matches and on the
        # digest none of them do, because the feed-forward adds the initial values back afterward.
        # This is the check that would have caught the whole reading being taken on the wrong thing.
        if read == "state" and hits != total:
            sys.stdout.write("  FAIL the working state lost a word the round only copies\n")
            failed += 1
        if read == "digest" and hits != 0:
            sys.stdout.write("  FAIL the digest kept a copied word, so the feed-forward is absent\n")
            failed += 1

        # On the working state the delta starts above independence and ends below it. Two earlier
        # versions of this check asserted the wrong thing: first that the delta grows as the mixing
        # takes hold, then that it holds level. It does neither. It falls, and it crosses the floor
        # on the way down, and both of those were invisible while the digest was the thing measured.
        if read == "state":
            if early_ratio <= 1.0:
                sys.stdout.write("  FAIL the early delta no longer clears the redraw floor\n")
                failed += 1
            if late_ratio >= early_ratio:
                sys.stdout.write("  FAIL the delta did not fall across the run\n")
                failed += 1
        sys.stdout.write("\n%d check(s) failed\n" % failed)
        return 1 if failed else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
