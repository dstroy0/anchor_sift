#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Check the C limb arithmetic against python integers, which know nothing about limbs.
#
#   python maint/engine/check_exact_limbs.py                  build/engine_c/bench_exact is run
#   python maint/engine/check_exact_limbs.py <rows.txt>       rows already captured are read
#
# WHY THE CHECK IS NOT INSIDE THE C
#
# A library cannot be its own oracle. A second routine in bench_exact.c saying what an addition
# should come to would carry whatever the author believed about the answer, and it would agree with
# the first routine forever, including on the days both are wrong.
#
# A python integer is arbitrary precision and is implemented by somebody else. It has no fixed
# width, no limb, no carry the author of exact_limbs.c wrote, and no shared line of code. Where the
# two disagree the disagreement is real.
#
# WHAT THIS CHECK CANNOT SEE
#
# Both sides read one contract, and that contract is exact_limbs.h. Agreement here is evidence the
# contract is unambiguous and that two implementations read it the same way. It is not evidence
# that either reading matches a deposit.
#
# A CIF, or any third format, could define decimal text differently from the way this header does.
# Both arms would then be wrong together and every row below would still come back green. That
# failure is invisible from here and the only thing that finds it is a published number: the
# crystallography oracle compares a recovered period against a cell edge somebody else measured,
# That check has an answer from outside this tree, and this one does not.
#
# WHAT IS BEING COMPARED
#
# The C prints a sign, how many limbs the value uses, and those limbs in hex, least significant
# first. This reassembles that into an integer and compares against the same operation done
# directly. It also checks the refusals: a value too wide for the fixed width has to come back
# refused, since a fixed width is the only bound this representation carries and a silent wrap is
# the worst failure available to it.
#
# The same rows are read at every width a build selects, 1 limb to 32768. The width comes from the
# first row the driver prints and never from the header text, since the build that produced the
# rows may have set it.

import io
import os
import re
import subprocess
import sys

# The subject built to overrun the width carries 315654 digits at 32768 limbs, and python refuses to
# convert a decimal string longer than 4300 digits unless told otherwise. The limit guards a server
# parsing untrusted text in quadratic time. The text here is the driver's own.
sys.set_int_max_str_digits(0)

HERE = os.path.dirname(os.path.abspath(__file__))
def _repository_root():
    """This repository, asked of git.

    The marker climbed to before was build/, which the repository PRODUCES rather than CONTAINS, so
    a linked worktree and a never-built clone both lack it. The climb then walked past the root it
    was looking for into another checkout entirely, and every path derived from it pointed at a
    different tree than the tool was run from. That lands on a real repository with real files,
    which is indistinguishable from working.

    A marker infers the root. Git answers it. The climb below is kept only for an exported tree with
    no git directory, and it looks for src/engine, which is TRACKED: a marker the repository
    contains is present in every checkout of it, and a marker the repository produces is present in
    none of them until something has already run.

    Git's own variables are cleared first. Inside a hook GIT_DIR is exported, and a rev-parse that
    inherits it answers about that repository rather than about the directory it was asked from,
    returning the current directory instead of the root.
    """
    start = os.path.dirname(os.path.abspath(__file__))
    environment = dict(os.environ)
    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX", "GIT_COMMON_DIR"):
        environment.pop(key, None)

    try:
        said = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], cwd=start,
                                       stderr=subprocess.PIPE, env=environment)
    except (OSError, subprocess.CalledProcessError):
        said = b""

    top = said.decode("utf-8", "replace").strip()
    if top and os.path.isdir(top):
        return os.path.abspath(top)

    climbed = start
    while (climbed != os.path.dirname(climbed)) \
            and not os.path.isdir(os.path.join(climbed, "src", "engine")):
        climbed = os.path.dirname(climbed)
    return climbed


ROOT = _repository_root()

DRIVER = os.path.join(ROOT, "build", "engine_c", "bench_exact.exe")
if not os.path.isfile(DRIVER):
    DRIVER = os.path.join(ROOT, "build", "engine_c", "bench_exact")

# Positions in the planted run the C builds, and the value standing at each. Stated here as the plan
# and built independently, the same way bench_lattice plants an occurrence instead of looking for
# one. Nothing is read back from the C to construct it.
RUN_PLACES = 64
RUN_STEP = 4

# The run with repeated positions, as bench_exact.c lists it: unsorted, with four positions listed
# twice carrying two values. Built here from the plan, and counted with a dict, which keeps the last
# value at a repeated position.
REPEATED_POSITIONS = ("2.00", "0.25", "1.00", "0.25", "0.50", "2.00", "1.25", "0.75", "1.00",
                      "0.00", "1.50", "0.50")
REPEATED_VALUES = (1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4)

# The C statuses a refusal row prints.
WILL_NOT_FIT = 1
NOT_DECIMAL = 2

# The decimal grammar exact_integer.h documents, written as a regular expression. The C and
# representation.exact each walk the text byte by byte. A regex shares no step with either. The
# classes are ASCII by construction: [0-9] and the four padding bytes, with no \d or \s, which also
# match Unicode digits and whitespace.
GRAMMAR = re.compile(r"[ \t\r\n]*([+-]?)([0-9]*)(?:\.([0-9]*))?(?:\(([0-9]+)\))?[ \t\r\n]*")


def constant(path, pattern):
    """One constant read out of a source file as text, without importing or compiling it.

    Read as text deliberately. Importing the python module would make this file the same
    implementation it is supposed to be checking, and compiling the header would need a compiler
    where a regular expression will do.
    """
    with io.open(os.path.join(ROOT, path), encoding="utf-8", errors="replace") as handle:
        # MULTILINE, since a constant sits at the start of its own line and not the start of a file.
        found = re.search(pattern, handle.read(), re.MULTILINE)
    return int(found.group(1)) if found else None


def version_lock(out):
    """Whether the two arms are built against the same contract.

    The C carries a limb count and a declared digit floor; the python side carries the scale it
    ingests at. They are separate declarations of one number, and nothing in either file refers to
    the other. They can drift apart silently. A drift makes the two arms disagree about values
    neither of them is wrong about individually. That is the hardest kind of disagreement to read.

    Returns 1 where they agree, 0 where they do not.
    """
    limbs = constant("src/engine/c/no_rounding/exact_integer.h",
                     r"#define\s+ANCHOR_EXACT_LIMBS\s+(\d+)")
    floor = constant("src/engine/c/no_rounding/exact_integer.h",
                     r"#define\s+ANCHOR_EXACT_DIGITS\s+(\d+)")
    scale = constant("src/engine/python/representation/exact.py",
                     r"^SCALE_DIGITS\s*=\s*(\d+)")

    if (limbs is None) or (floor is None) or (scale is None):
        out.write("  could not read the contract constants from both sides\n")
        return 0

    # The width has to hold the floor, and the python scale has to be the same floor. A python scale
    # above the C floor would ingest values the C refuses; below it, the two would disagree about
    # what fits.
    held = (32 * limbs)
    room = ((floor * 3322) // 1000) + 1
    if room > held:
        out.write("  CONTRACT: %d digits declared, %d limbs hold %d bits, needs %d\n"
                  % (floor, limbs, held, room))
        return 0
    if scale != floor:
        out.write("  CONTRACT: python ingests at %d digits, C declares %d\n" % (scale, floor))
        return 0

    out.write("  contract: %d limbs, %d bits, %d digits declared on both sides\n"
              % (limbs, held, floor))
    return 1


def value_of(sign, limbs):
    """One printed row reassembled into an integer, without any of the C's arithmetic."""
    held = 0
    for at, limb in enumerate(limbs):
        held += limb << (32 * at)
    return sign * held


def integer_at(field, at, width_limbs):
    """One printed integer out of a row, starting at field `at`: a sign, a limb count, those limbs.

    Returns (value, where the next field starts), or (None, at) where the row is malformed. A count
    past the width, a row cut short or a top limb of zero is malformed. The driver prints exactly
    the limbs up to the highest nonzero one. Any of those three means the printing and the
    arithmetic no longer describe one value.
    """
    if len(field) < at + 2:
        return None, at
    sign = int(field[at])
    count = int(field[at + 1])
    limbs = [int(one, 16) for one in field[at + 2:at + 2 + count]]
    if (count > width_limbs) or (len(limbs) != count) or (count and limbs[-1] == 0):
        return None, at
    return value_of(sign, limbs), at + 2 + count


def measured_of(text, places, width):
    """Decimal text as (status, value, uncertainty), done with python integers alone.

    `status` is 0 where the C must accept the text, and otherwise the refusal status the C must
    return: NOT_DECIMAL for text outside the grammar, WILL_NOT_FIT for a value or an uncertainty
    needing more places than `places` or more bits than `width`. `uncertainty` is None where the
    text carries no bracket. Written out here instead of imported, because this file is the second
    implementation and an import would make it the same one.
    """
    found = GRAMMAR.fullmatch(text)
    if (found is None) or not (found.group(2) or found.group(3)):
        return NOT_DECIMAL, None, None
    sign, whole, bracket = found.group(1), found.group(2), found.group(4)
    part = found.group(3) or ""

    # Trailing zeros in the fraction are not places. 1.2300 and 1.23 are one number and a scale of
    # two places holds both exactly. Counting the zeros refuses a value that needs no rounding.
    # ".000" is zero, and trimming it to no digit at all must not make it text that is not decimal.
    trimmed = part.rstrip("0")
    if len(trimmed) > places:
        return WILL_NOT_FIT, None, None
    value = int(whole + trimmed or "0") * (10 ** (places - len(trimmed)))
    if sign == "-":
        value = -value
    if abs(value) >= (1 << width):
        return WILL_NOT_FIT, None, None

    if bracket is None:
        return 0, value, None
    # The bracket counts units of the last place printed, trailing zeros included.
    if len(part) > places:
        return WILL_NOT_FIT, None, None
    uncertainty = int(bracket) * (10 ** (places - len(part)))
    if uncertainty >= (1 << width):
        return WILL_NOT_FIT, None, None
    return 0, value, uncertainty


def exact_of(text, places, width=1 << 20):
    """Decimal text as an integer at `places`, or None where the C is required to refuse it."""
    status, value, _uncertainty = measured_of(text, places, width)
    return value if status == 0 else None


def text_of(hexed):
    """A subject's bytes from the hex the C printed, one character per byte.

    Latin-1 maps every byte to one code point. A byte above 0x7F then stays one character that no
    [0-9] or padding class matches, the same way the C reads it.
    """
    return bytes.fromhex(hexed).decode("latin-1")


def planted_run(places):
    """The run the C builds, constructed here from the plan and not from its output."""
    positions = []
    values = []
    for at in range(RUN_PLACES):
        text = "%d.%02d" % (at // RUN_STEP, (at % RUN_STEP) * 25)
        positions.append(exact_of(text, places))
        values.append(at % RUN_STEP)
    return positions, values


def agreement(positions, values, lag):
    """How many places carry the same value as the place exactly one lag away."""
    seen = dict(zip(positions, values))
    return sum(1 for one, value in seen.items() if seen.get(one + lag) == value)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    if len(sys.argv) > 1:
        with io.open(sys.argv[1], encoding="utf-8") as handle:
            rows = handle.read().splitlines()
    else:
        if not os.path.isfile(DRIVER):
            out.write("\n  no bench_exact at %s\n" % DRIVER)
            out.write("  cmake -S src/engine/c -B build/engine_c -G Ninja"
                      " -DCMAKE_BUILD_TYPE=Release && cmake --build build/engine_c\n\n")
            out.flush()
            return 1
        rows = subprocess.run([DRIVER], capture_output=True, text=True,
                              check=True).stdout.splitlines()

    if (not rows) or (not rows[0].startswith("limbs ")):
        out.write("\n  the driver printed nothing recognizable\n\n")
        out.flush()
        return 1
    parts = rows[0].split()
    limbs = int(parts[1])
    places = int(parts[3])
    width = 32 * limbs

    subjects = {}
    checked = 0
    wrong = []

    for row in rows[1:]:
        field = row.split()
        if not field:
            continue
        kind = field[0]

        if kind == "read":
            index = int(field[1])
            text = text_of(field[2])
            status, wanted, _uncertainty = measured_of(text, places, width)
            if field[3] == "refused":
                # A refusal has to be the one the python side says is required, of the same kind, or
                # the C is refusing values it should have read.
                if int(field[4]) != status:
                    wrong.append("read %d %r: refused with %s, python says %d"
                                 % (index, text, field[4], status))
                subjects[index] = None
            else:
                got, _next = integer_at(field, 3, limbs)
                if got is None:
                    wrong.append("read %d %r: malformed limbs" % (index, text))
                elif status != 0:
                    wrong.append("read %d %r: read, which python refuses with %d"
                                 % (index, text, status))
                elif got != wanted:
                    wrong.append("read %d %r: read as %d, python says %d"
                                 % (index, text, got, wanted))
                subjects[index] = wanted if status == 0 else None
            checked += 1
            continue

        if kind == "meas":
            index = int(field[1])
            text = text_of(field[2])
            status, wanted, spread = measured_of(text, places, width)
            if field[3] == "refused":
                if int(field[4]) != status:
                    wrong.append("meas %d %r: refused with %s, python says %d"
                                 % (index, text, field[4], status))
            else:
                carried = int(field[3])
                got, after = integer_at(field, 4, limbs)
                got_spread, _next = integer_at(field, after, limbs)
                if (got is None) or (got_spread is None):
                    wrong.append("meas %d %r: malformed limbs" % (index, text))
                elif status != 0:
                    wrong.append("meas %d %r: read, which python refuses with %d"
                                 % (index, text, status))
                elif got != wanted:
                    wrong.append("meas %d %r: value %d, python says %d"
                                 % (index, text, got, wanted))
                elif carried != (0 if spread is None else 1):
                    wrong.append("meas %d %r: carried %d, python says %s"
                                 % (index, text, carried, spread))
                elif got_spread != (0 if spread is None else spread):
                    wrong.append("meas %d %r: uncertainty %d, python says %s"
                                 % (index, text, got_spread, spread))
            checked += 1
            continue

        if kind == "keep":
            # A refusal must leave its output as it was. The last field is 1 where it did.
            if field[-1] != "1":
                wrong.append("%s: a refusal changed its output" % row)
            checked += 1
            continue

        if kind == "agreerep":
            lag = exact_of(field[1], places)
            positions = [exact_of(one, places) for one in REPEATED_POSITIONS]
            wanted = agreement(positions, list(REPEATED_VALUES), lag)
            if int(field[2]) != wanted:
                wrong.append("%s: got %s, python says %d" % (row, field[2], wanted))
            checked += 1
            continue

        if kind in ("add", "sub", "mul"):
            low = subjects.get(int(field[1]))
            high = subjects.get(int(field[2]))
            if (low is None) or (high is None):
                continue
            wanted = (low + high) if kind == "add" else \
                     (low - high) if kind == "sub" else (low * high)
            fits = abs(wanted) < (1 << width)
            if field[3] == "refused":
                if fits:
                    wrong.append("%s: refused, but %d fits %d bits" % (row, wanted, width))
            else:
                got, _next = integer_at(field, 3, limbs)
                if got is None:
                    wrong.append("%s: malformed limbs" % row)
                elif not fits:
                    wrong.append("%s: produced a value where %d needs more than %d bits"
                                 % (row, wanted, width))
                elif got != wanted:
                    wrong.append("%s: got %d, python says %d" % (row, got, wanted))
            checked += 1
            continue

        if kind == "cmp":
            low = subjects.get(int(field[1]))
            high = subjects.get(int(field[2]))
            if (low is None) or (high is None):
                continue
            order = (low > high) - (low < high)
            same = 1 if low == high else 0
            if (int(field[3]) != order) or (int(field[4]) != same):
                wrong.append("%s: got %s %s, python says %d %d"
                             % (row, field[3], field[4], order, same))
            checked += 1
            continue

        if kind == "agree":
            lag = exact_of(field[1], places)
            positions, values = planted_run(places)
            wanted = agreement(positions, values, lag)
            if int(field[2]) != wanted:
                wrong.append("%s: got %s, python says %d" % (row, field[2], wanted))
            checked += 1
            continue

    out.write("\n  %d rows checked at %d limbs, %d decimal places, %d bits wide\n"
              % (checked, limbs, places, width))

    # Checked after the rows. A contract drift is then reported beside the disagreement it caused
    # instead of in place of it. Both are failures and neither substitutes for the other.
    locked = version_lock(out)

    if wrong:
        out.write("\n  DISAGREEMENTS (%d)\n" % len(wrong))
        for one in wrong[:40]:
            out.write("    %s\n" % one)
        if len(wrong) > 40:
            out.write("    and %d more\n" % (len(wrong) - 40))
        out.write("\n  the C and python integers do not agree. One of them has a defect.\n\n")
        out.flush()
        return 1

    out.write("  every row agrees with python integer arithmetic\n\n")
    out.flush()
    return 0 if locked else 1


if __name__ == "__main__":
    raise SystemExit(main())
