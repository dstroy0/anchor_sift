import argparse
import datetime
import os
import re
import sys
from fractions import Fraction

def places(value, digits=4):
    value = Fraction(value)
    sign = "-" if value < 0 else ""
    scaled = (abs(value.numerator) * (10 ** digits) * 2 + value.denominator) // (2 * value.denominator)
    whole, part = divmod(scaled, 10 ** digits)
    return "%s%d.%0*d" % (sign, whole, digits, part)

def read_edges(path):
    rows = []
    with open(path, encoding="utf-8") as handle:
        header = handle.readline().rstrip("\n").split("\t")
        for line in handle:
            fields = line.rstrip("\n").split("\t")
            row = dict(zip(header, fields))
            row["held"] = int(row["held"])
            row["basin_voxels"] = int(row["basin_voxels"])
            text = row.get("null_held", "")
            row["draws"] = [int(value) for value in text.split(",")] if text else []
            row["failed"] = row["status"] != "correct"
            rows.append(row)
    return rows

def engine_milliseconds(path):
    total = 0
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            match = re.search(r"engines (\d+) ms", line)
            if match:
                total += int(match.group(1))
    return total

def curve(rows):
    most = min((len(row["draws"]) for row in rows), default=0)
    points = []
    draws = 1
    while draws <= most:
        point = {"draws": draws}
        for group, wanted in (("correct", False), ("failing", True)):
            chosen = [row for row in rows if row["failed"] == wanted]
            beats = 0
            share = Fraction(0)
            for row in chosen:
                best = max(row["draws"][:draws])
                delta = row["held"] - best
                beats += 1 if delta > 0 else 0
                share += Fraction(delta, max(row["basin_voxels"], 1))
            point[group + "_edges"] = len(chosen)
            point[group + "_beats"] = beats
            point[group + "_share"] = share / len(chosen) if chosen else Fraction(0)
        point["separation"] = point["correct_share"] - point["failing_share"]
        points.append(point)
        draws *= 2
    return points

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("edges")
    parser.add_argument("log")
    parser.add_argument("--history", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "null_curve_history.tsv"))
    parser.add_argument("--label", default="")
    options = parser.parse_args()

    rows = read_edges(options.edges)
    milliseconds = engine_milliseconds(options.log)
    points = curve(rows)
    if not points:
        sys.stderr.write("  no null draws in %s\n" % options.edges)
        raise SystemExit(1)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    columns = ["stamp", "label", "edges", "engine_ms", "draws", "correct_beats", "correct_edges", "failing_beats",
               "failing_edges", "correct_share", "failing_share", "separation"]

    previous = {}
    if os.path.exists(options.history):
        with open(options.history, encoding="utf-8") as handle:
            header = handle.readline().rstrip("\n").split("\t")
            for line in handle:
                row = dict(zip(header, line.rstrip("\n").split("\t")))
                previous[int(row["draws"])] = row

    print("  %d edges, engines %d ms, %s" % (len(rows), milliseconds, options.label or "unlabelled"))
    print("    %-6s %-17s %-17s %-12s %-12s %-12s" % ("draws", "correct beat null", "failing beat null", "correct share",
                                                       "failing share", "separation"))
    lines = []
    for point in points:
        record = {
            "stamp": stamp, "label": options.label, "edges": str(len(rows)), "engine_ms": str(milliseconds),
            "draws": str(point["draws"]),
            "correct_beats": str(point["correct_beats"]), "correct_edges": str(point["correct_edges"]),
            "failing_beats": str(point["failing_beats"]), "failing_edges": str(point["failing_edges"]),
            "correct_share": places(point["correct_share"]), "failing_share": places(point["failing_share"]),
            "separation": places(point["separation"]),
        }
        print("    %-6d %-17s %-17s %-12s %-12s %-12s" % (
            point["draws"], "%d/%d" % (point["correct_beats"], point["correct_edges"]),
            "%d/%d" % (point["failing_beats"], point["failing_edges"]), record["correct_share"], record["failing_share"],
            record["separation"]))
        before = previous.get(point["draws"])
        if before is not None:
            changed = [name for name in columns[2:] if before.get(name) != record[name]]
            if changed:
                print("           changed since %s: %s" % (before["stamp"], ", ".join(
                    "%s %s -> %s" % (name, before.get(name), record[name]) for name in changed)))
            else:
                print("           unchanged since %s" % before["stamp"])
        lines.append("\t".join(record[name] for name in columns))

    new_file = not os.path.exists(options.history)
    with open(options.history, "a", encoding="utf-8", newline="\n") as handle:
        if new_file:
            handle.write("\t".join(columns) + "\n")
        for line in lines:
            handle.write(line + "\n")
    print("  recorded in %s" % options.history)

if __name__ == "__main__":
    main()
