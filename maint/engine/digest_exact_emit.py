#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Digest what the C limb arm emits, letting a second implementation elsewhere be compared to it.
#
#   python maint/engine/digest_exact_emit.py            every subject, digest per subject
#   python maint/engine/digest_exact_emit.py --lines    the normalized lines themselves
#
# WHY A DIGEST AND NOT THE VALUES
#
# Two implementations agreeing is only meaningful if they are compared on the same thing. Sending
# values invites reformatting on the way, and a reformatted number that happens to match hides a
# disagreement while a reformatted number that does not match invents one. A digest over exact text
# has neither failure: the bytes agree or they name themselves.
#
# THE NORMALIZED LINE
#
# bench_exact prints "read <index> <subject> <sign> <limb>..." because the index is what its own
# arithmetic rows refer to. The comparison form drops the index and the word, leaving
#
#   <subject> <sign> <limb>...            for a value that was read
#   <subject> refused <status>            for one that was not
#
# One space between fields, no trailing space, and the subject verbatim. Status is the
# AnchorExactStatus enum: 1 is WILL_NOT_FIT and 2 is NOT_DECIMAL. A refusal is digested like any
# other row, because what an implementation rejects is as much a claim as what it accepts.

import hashlib
import io
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)

DRIVER = os.path.join(ROOT, "build", "engine_c", "bench_exact.exe")
if not os.path.isfile(DRIVER):
    DRIVER = os.path.join(ROOT, "build", "engine_c", "bench_exact")


def normalized(rows):
    """The read rows as (subject, comparison line), in the order the driver emitted them."""
    held = []
    for row in rows:
        field = row.split()
        if (len(field) < 3) or (field[0] != "read"):
            continue
        # field[1] is the index and is dropped. The subject is one token, since no subject here
        # carries a space and a subject that did would need the emit format changed on both sides.
        subject = field[2]
        held.append((subject, " ".join([subject] + field[3:])))
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isfile(DRIVER):
        out.write("\n  no bench_exact at %s\n" % DRIVER)
        out.write("  cmake --build build/engine_c\n\n")
        out.flush()
        return 1

    rows = subprocess.run([DRIVER], capture_output=True, text=True,
                          check=True).stdout.splitlines()
    held = normalized(rows)
    if not held:
        out.write("\n  the driver emitted no read rows\n\n")
        out.flush()
        return 1

    if "--lines" in sys.argv:
        for _, line in held:
            out.write("%s\n" % line)
        out.flush()
        return 0

    out.write("\n  %d subjects, digested from what bench_exact emitted\n\n" % len(held))
    for subject, line in held:
        digest = hashlib.sha256(line.encode("utf-8")).hexdigest()[:16]
        out.write("  %-32s %s\n" % (subject, digest))

    whole = "\n".join(line for _, line in held)
    out.write("\n  all %d joined by one newline, no trailing newline\n" % len(held))
    out.write("    sha256 %s\n" % hashlib.sha256(whole.encode("utf-8")).hexdigest())
    out.write("    %d bytes\n\n" % len(whole.encode("utf-8")))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
