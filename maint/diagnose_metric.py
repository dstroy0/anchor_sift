import collections
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import score_submission as metric
import truth_io


def apart_um(one, other):
    return math.sqrt(sum((metric.SCALE[axis] * (one[axis] - other[axis])) ** 2 for axis in range(3)))


def main():
    path = sys.argv[1]
    directory = sys.argv[2] if len(sys.argv) > 2 else "D:/kaggle_project_data/biohub_cell_tracking_data/train"
    largest = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    policy = metric.policy_largest(largest) if largest else metric.policy_all
    dumped = metric.read_nodes(path)
    rows = collections.Counter()
    landed_apart = []
    match_distance = []
    for name in sorted(dumped):
        truth = truth_io.read(os.path.join(directory, name + ".geff"))
        by_time = truth.by_time()
        frames = dumped[name]
        chosen = {time: policy(frames[time]) for time in frames}
        became = {}
        node_of = {}
        for time, picked in chosen.items():
            for node in picked:
                node_of[(time, node["leaf"])] = node
            keys = by_time.get(time, [])
            if not picked or not keys:
                continue
            for at, identity in metric.match(picked, keys, truth.nodes).items():
                became[identity] = (time, picked[at]["leaf"])
                match_distance.append(apart_um(picked[at]["place"], truth.nodes[identity][1:]))
        for source, target in truth.edges:
            ours_source = became.get(source)
            ours_target = became.get(target)
            if ours_source is None:
                rows["source unmatched"] += 1
                continue
            if ours_target is None:
                rows["target unmatched"] += 1
                continue
            node = node_of[ours_source]
            children = node.get("children", [node["forward"]])
            if ours_target[1] in children:
                rows["hit"] += 1
            elif all(child < 0 for child in children):
                rows["links nowhere"] += 1
            else:
                rows["lands elsewhere"] += 1
                landed = node_of.get((ours_target[0], children[0]))
                if landed is not None:
                    landed_apart.append(apart_um(landed["place"], node_of[ours_target]["place"]))
                else:
                    rows["  (landed on a node the policy dropped)"] += 1
    total = sum(count for key, count in rows.items() if not key.startswith(" "))
    print("  %d key edges over %d samples, %s" % (total, len(dumped), "every node" if not largest else
                                                   "the %d largest per frame" % largest))
    for key in ("hit", "source unmatched", "target unmatched", "lands elsewhere", "links nowhere",
                "  (landed on a node the policy dropped)"):
        print("  %-42s %6d  %5.1f%%" % (key, rows[key], 100.0 * rows[key] / total if total else 0.0))
    for label, values in (("matched node to key node, um", match_distance),
                          ("elsewhere landing to target's match, um", landed_apart)):
        if values:
            values.sort()
            print("  %-42s median %.2f, 90th %.2f, n %d" % (label, values[len(values) // 2],
                                                            values[(9 * len(values)) // 10], len(values)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
