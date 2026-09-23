"""Checks whether any number a bench prints was already sitting in its binary.

The failure this looks for is specific. A compiler that can prove an expression's inputs are known
at compile time will evaluate it then and emit the answer as an immediate, so the bench prints a
constant while appearing to measure one. bench_engines already caught an entire engine that was a
constant function; nothing structural prevents the same thing happening to a statistic.

The test: read every printed floating-point number out of a bench's output, read every eight-byte
double out of the binary's read-only data, and report the printed numbers that are already there.

A match is not by itself a defect. A bench that prints a threshold, a sample count or an expected
value it was given in source will match, correctly. What the report is for is the opposite case: a
number described as measured that turns out to be a literal the compiler folded. Every match has to
be looked at against the source line that printed it.

Usage: python maint/audit/audit_constants.py <audit directory> [arm]
"""

import re
import struct
import subprocess
import sys
from pathlib import Path

# Values that appear in almost any binary and carry no information about folding. Printing one of
# these proves nothing either way, so they are excluded to keep the report readable.
UNINTERESTING = {
    0.0,
    0.5,
    1.0,
    2.0,
    3.0,
    4.0,
    8.0,
    10.0,
    16.0,
    32.0,
    64.0,
    100.0,
    128.0,
    256.0,
    1000.0,
}

NUMBER_PATTERN = re.compile(r"[-+]?\d+\.\d+(?:[eE][-+]?\d+)?")


def binary_doubles(path):
    """Returns every eight-byte double in the binary's read-only sections."""
    dump = subprocess.run(
        ["objdump", "-s", "-j", ".rdata", "-j", ".data", "-j", ".text", str(path)],
        capture_output=True,
        text=True,
    )
    raw = bytearray()
    for line in dump.stdout.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        if not re.fullmatch(r"[0-9a-f]+", parts[0]):
            continue
        for group in parts[1:]:
            if not re.fullmatch(r"[0-9a-f]{2,8}", group):
                break
            raw.extend(bytes.fromhex(group))

    found = set()
    for offset in range(0, len(raw) - 7):
        value = struct.unpack_from("<d", raw, offset)[0]
        if value != value or value in (float("inf"), float("-inf")):
            continue
        if value == 0.0 or abs(value) < 1e-12 or abs(value) > 1e12:
            continue
        found.add(value)
    return found


def printed_numbers(path):
    """Returns every floating-point number the bench printed, with the text that produced it."""
    seen = {}
    for line in path.read_text(errors="replace").splitlines():
        for match in NUMBER_PATTERN.finditer(line):
            try:
                value = float(match.group())
            except ValueError:
                continue
            seen.setdefault(value, line.strip())
    return seen


def tolerance_for(text):
    """Half a unit in the last printed place, the most a rounded value can be off by."""
    body = text.split("e")[0].split("E")[0]
    decimals = len(body.split(".")[1]) if "." in body else 0
    return 0.5 * (10.0 ** -decimals)


def main():
    work = Path(sys.argv[1])
    arm = sys.argv[2] if len(sys.argv) > 2 else "O2"
    directory = work / arm

    print("checking arm %s in %s" % (arm, directory))
    print()

    for output in sorted(directory.glob("*.out")):
        binary = output.with_suffix(".exe")
        if not binary.exists():
            continue

        constants = binary_doubles(binary)
        matches = []
        for value, line in printed_numbers(output).items():
            if value in UNINTERESTING or abs(value) < 1e-9:
                continue
            text = NUMBER_PATTERN.search(line)
            span = tolerance_for(text.group()) if text else 1e-9
            for constant in constants:
                if abs(constant - value) <= span:
                    matches.append((value, constant, line))
                    break

        status = "%-22s %4d printed, %5d constants, %3d already in the binary" % (
            output.stem,
            len(printed_numbers(output)),
            len(constants),
            len(matches),
        )
        print(status)
        for value, constant, line in sorted(matches)[:14]:
            print("      %-18.10g  <=  %-18.10g  %s" % (value, constant, line[:78]))


main()
