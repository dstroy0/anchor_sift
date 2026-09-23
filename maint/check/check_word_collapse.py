"""Which message word loses its structure first, and does any of them break the schedule's order?

Seen on the helix the sixteen message words read as petals, and which one goes first is apparent at
a glance. The schedule makes an ordering inevitable - word w cannot act before round w+1, so it
starts falling later than word w-1 - and that much is not a finding.

The finding, if there is one, is a word that leaves order: one that falls faster or slower than its
neighbors once the head start is taken out. The avalanche profiles were measured identical to one
part in 10^4 aligned to their own wavefronts, which predicts strict order and equal spacing. Any
word that departs from that is doing something the schedule does not account for.

Three crossings are timed per word, from the deterministic plateau down to the noise floor.

    python maint/check/check_word_collapse.py
"""

import csv
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "build", "bench", "shadows.csv")

PLATEAU = 67108608.0
MARKS = [("leaves plateau", 0.98), ("half fallen", 0.50), ("near floor", 0.001)]


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no shadows.csv\n")
        return 1

    # Mean over the 32 bits of each word, per round.
    by_word = {}
    with open(SOURCE, newline="") as handle:
        for row in csv.DictReader(handle):
            if row["kind"] != "inbit":
                continue
            word = int(row["a"]) // 32
            at = int(row["round"])
            by_word.setdefault(word, {}).setdefault(at, []).append(float(row["value"]))

    level = {}
    for word, rounds in by_word.items():
        level[word] = {r: (sum(v) / len(v)) for r, v in rounds.items()}

    def crosses(word, fraction):
        """First round whose mean has fallen below `fraction` of the plateau."""
        want = PLATEAU * fraction
        for at in sorted(level[word]):
            if level[word][at] < want:
                return at
        return None

    print("Rounds at which each message word's mean crosses down through the plateau.\n")
    print("  %5s %6s" % ("word", "wakes"), end="")
    for name, _ in MARKS:
        print(" %15s" % name, end="")
    print(" %10s" % "span")
    print("  %5s %6s" % ("-" * 5, "-" * 6), end="")
    for _ in MARKS:
        print(" %15s" % ("-" * 15), end="")
    print(" %10s" % ("-" * 10))

    spans = []
    offsets = []
    for word in range(16):
        wakes = word + 1
        marks = [crosses(word, f) for _, f in MARKS]
        print("  %5d %6d" % (word, wakes), end="")
        for at in marks:
            print(" %15s" % (at if at is not None else "-"), end="")
        if marks[0] is not None and marks[2] is not None:
            span = marks[2] - marks[0]
            spans.append(span)
            offsets.append(marks[0] - wakes)
            print(" %10d" % span)
        else:
            print(" %10s" % "-")

    if spans:
        print("\n  span is how many rounds a word takes to fall from plateau to floor.")
        print("  mean %.2f, spread %.2f, minimum %d, maximum %d"
              % (sum(spans) / len(spans),
                 (sum((s - (sum(spans) / len(spans))) ** 2 for s in spans) / max(1, len(spans) - 1))
                 ** 0.5, min(spans), max(spans)))
        print("\n  offset is how long after waking a word leaves the plateau. The schedule predicts")
        print("  the same value for every word, so a departure is not accounted for by it.")
        print("  values: %s" % (", ".join(str(o) for o in offsets)))
        same = len(set(offsets)) == 1
        print("  %s" % ("all equal: strict schedule order, nothing out of turn." if same
                        else "NOT all equal: at least one word is out of turn, see above."))
    return 0


if __name__ == "__main__":
    sys.exit(main())
