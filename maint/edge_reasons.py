import argparse
import collections
import sys

REASONS = [
    ("key leaf undetected", "the key's next node lies in no body: nothing to link to"),
    ("never met", "the key's object shares no voxel with this cell's object and none of its leaves landed"
                  " there, so it was never in the pool"),
    ("outweighed", "the key's object was in the pool and lost the magnitude to the object linked instead"),
    ("unified apart", "the cell's object did link to the key's object, but the two were carried into different"
                      " unified objects, so the scored link points elsewhere"),
    ("object linked none", "the cell's object made no link at all into the next frame"),
    ("nothing shared", "the cell and the key's leaf share no voxel at this pair's lag"),
    ("not mutual", "the key's leaf does not land back on this cell, so the pair was never a candidate"),
    ("landed elsewhere", "the cell shares most with the key's leaf, but its landing fell in another"),
    ("leaf shares less", "the key's leaf shares fewer voxels with this cell than another leaf does"),
    ("object outweighed", "this cell's own landing and its best share are both the key's leaf, so the object it"
                          " belongs to lost the weighing for the whole object"),
]


def reason_of(row):
    truth_leaf = int(row["truth_leaf"])
    chosen_leaf = int(row["chosen_leaf"])
    truth_shared = int(row["truth_shared"])
    best_shared = int(row["best_shared"])
    if truth_leaf < 0:
        return "key leaf undetected"
    if int(row["object_links_truth"]) != 0:
        return "unified apart"
    if "truth_weight" in row:
        if int(row["truth_weight"]) == 0:
            return "never met"
        return "outweighed"
    if int(row["object_links"]) == 0:
        return "object linked none"
    if truth_shared == 0:
        return "nothing shared"
    if int(row["truth_mutual"]) == 0:
        return "not mutual"
    if (truth_shared == best_shared) and (chosen_leaf != truth_leaf):
        return "landed elsewhere"
    if truth_shared < best_shared:
        return "leaf shares less"
    return "object outweighed"


def read_rows(path):
    rows = []
    with open(path, encoding="utf-8") as handle:
        header = handle.readline().rstrip("\n").split("\t")
        for line in handle:
            fields = line.rstrip("\n").split("\t")
            rows.append(dict(zip(header, fields)))
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("edges")
    parser.add_argument("--status", default="wrong,nolink", help="statuses to explain, comma separated")
    parser.add_argument("--list", action="store_true", help="print every failing row beside its reason")
    options = parser.parse_args()

    wanted = set(options.status.split(","))
    rows = read_rows(options.edges)
    if not rows or "truth_leaf" not in rows[0]:
        sys.stderr.write("  %s carries no diagnosis columns; run the driver that writes them\n" % options.edges)
        return 1
    failing = [row for row in rows if row["status"] in wanted]
    counts = collections.Counter(reason_of(row) for row in failing)
    print("  %d of %d edges are %s" % (len(failing), len(rows), " or ".join(sorted(wanted))))
    for name, meaning in REASONS:
        if counts[name] == 0:
            continue
        print("    %-22s %3d   %s" % (name, counts[name], meaning))
    losses = [(int(row["best_shared"]), int(row["truth_shared"])) for row in failing
              if reason_of(row) == "leaf shares less"]
    if losses:
        near = sum(1 for best, truth in losses if (truth * 2) >= best)
        print("    of the %d whose leaf shared less, %d shared at least half what the winner shared"
              % (len(losses), near))
    if options.list:
        print("    %-16s %5s %-8s %-22s %8s %8s %8s" % ("sample", "time", "status", "reason", "truth", "chosen", "best"))
        for row in failing:
            print("    %-16s %5s %-8s %-22s %8s %8s %8s" % (row["sample"], row["time"], row["status"], reason_of(row),
                                                            row["truth_shared"], row["chosen_shared"], row["best_shared"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
