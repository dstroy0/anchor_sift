"""Renders the residue shadow as a character map for the theory book.

The published viewers are interactive and the book is not, so the same field is drawn here in
characters. Density stands for magnitude and the sign is carried by the character set, because a
book printed in one color cannot use hue for it.

    python tools/make_shadow_figure.py

Writes a LaTeX verbatim block to stdout; paste it into the chapter.
"""

import csv
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "src", "bench", "shadows.csv")

# Two ramps, so sign survives a monochrome page. Negative deepens through one set, positive
# through the other, and a cell at zero is blank and not a dot, so empty reads as empty.
DOWN = " .:-=+*#%@"
UP = " ,;iclxdKW"


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no shadows.csv\n")
        return 1

    field = {}
    for row in csv.DictReader(open(SOURCE, newline="")):
        if row["kind"] == "residue":
            field.setdefault(int(row["a"]), {})[int(row["round"])] = float(row["value"])

    rounds = sorted(field[0].keys())[:40]

    def draw(title, get):
        ceiling = max(abs(get(k, r)) for k in range(32) for r in rounds)
        print("%% %s" % title)
        print("\\begin{verbatim}")
        print("res | " + "".join(str(r % 10) for r in rounds))
        print("----+-" + ("-" * len(rounds)))
        for k in range(32):
            line = "%3d | " % k
            for r in rounds:
                value = get(k, r)
                scaled = math.log10(1 + abs(value)) / math.log10(1 + ceiling)
                step = min(9, int(scaled * 9.999))
                line += (DOWN if value < 0 else UP)[step]
            print(line)
        print("\\end{verbatim}")
        print("")

    # As measured: every class carries the same large offset, so all thirty-two rows look alike.
    draw("raw fold", lambda k, r: field[k][r])

    # With the class mean removed at each depth, the only reading that means anything.
    means = {}
    for r in rounds:
        means[r] = sum(field[k][r] for k in range(32)) / 32.0
    draw("common mode removed", lambda k, r: field[k][r] - means[r])
    return 0


if __name__ == "__main__":
    sys.exit(main())
