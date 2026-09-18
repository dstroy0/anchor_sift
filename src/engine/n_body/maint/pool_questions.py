import argparse
import collections
import sys
from fractions import Fraction

def read_pool(path):
    edges = collections.OrderedDict()
    with open(path, encoding="utf-8") as handle:
        header = handle.readline().rstrip("\n").split("\t")
        for line in handle:
            row = dict(zip(header, line.rstrip("\n").split("\t")))
            for name in ("object", "candidate", "is_truth", "is_linked", "meeting", "step", "magnitude",
                         "candidate_voxels", "candidate_leaves", "object_voxels", "object_leaves"):
                row[name] = int(row[name])
            edges.setdefault((row["sample"], row["time"], row["object"], row["status"]), []).append(row)
    return edges

RANKINGS = {
    "meeting": lambda row: (-row["meeting"], row["step"], row["magnitude"]),
    "meeting then vector": lambda row: (-row["meeting"], row["step"], row["magnitude"], row["candidate"]),
    "vector then meeting": lambda row: (row["step"], row["magnitude"], -row["meeting"]),
    "meeting of the union": lambda row: (-Fraction(row["meeting"],
                                                   max(1, row["object_voxels"] + row["candidate_voxels"]
                                                       - row["meeting"])), row["step"]),
    "meeting of the candidate": lambda row: (-Fraction(row["meeting"], max(1, row["candidate_voxels"])), row["step"]),
    "meeting of the cell": lambda row: (-Fraction(row["meeting"], max(1, row["object_voxels"])), row["step"]),
    "nearest in size": lambda row: (abs(row["candidate_voxels"] - row["object_voxels"]), -row["meeting"]),
    "fewest leaves": lambda row: (row["candidate_leaves"], -row["meeting"]),
}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pool")
    parser.add_argument("--top", type=int, default=0, help="print this many failing pools in full")
    options = parser.parse_args()

    edges = read_pool(options.pool)
    failing = {key: rows for key, rows in edges.items() if key[3] != "correct"}
    correct = {key: rows for key, rows in edges.items() if key[3] == "correct"}
    print("  %d edges with a pool, %d of them failing" % (len(edges), len(failing)))
    print("    %-26s %8s %8s %8s" % ("ranking", "wins", "losses", "net"))
    unreachable = set(failing)
    for name, key in RANKINGS.items():
        wins = 0
        for edge, rows in failing.items():
            first = min(rows, key=key)
            wins += int(first["is_truth"] != 0)
            if first["is_truth"] != 0:
                unreachable.discard(edge)
        losses = 0
        for edge, rows in correct.items():
            first = min(rows, key=key)
            losses += int((first["is_linked"] == 0) and any(row["is_truth"] for row in rows))
        print("    %-26s %8d %8d %+8d" % (name, wins, losses, wins - losses))
    never = sum(1 for rows in failing.values() if not any(row["is_truth"] for row in rows))
    print("    the key's candidate is in the pool for %d of %d failing edges"
          % (len(failing) - never, len(failing)))
    print("    first under no ranking here: %d" % len(unreachable))
    for edge in list(unreachable)[:options.top]:
        rows = sorted(edges[edge], key=lambda row: -row["meeting"])
        print("    %s t%s object %d" % (edge[0], edge[1], edge[2]))
        for row in rows:
            print("      candidate %6d meeting %7d step %2d magnitude %10d voxels %6d leaves %5d%s%s"
                  % (row["candidate"], row["meeting"], row["step"], row["magnitude"], row["candidate_voxels"],
                     row["candidate_leaves"], " KEY" if row["is_truth"] else "", " LINKED" if row["is_linked"] else ""))
    return 0

if __name__ == "__main__":
    sys.exit(main())
