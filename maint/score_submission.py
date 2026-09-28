import collections
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import truth_io

SCALE = (1.625, 0.40625, 0.40625)
REACH_UM = 7.0
COUNT_WEIGHT = 0.1
DIVISION_WEIGHT = 0.1


GEFF = "D:/kaggle_project_data/biohub_cell_tracking_data/train/%s.geff/zarr.json"
_ESTIMATED = {}


def estimated_nodes(name):
    if name not in _ESTIMATED:
        import json
        try:
            with open(GEFF % name, encoding="utf-8") as handle:
                meta = json.load(handle)
            _ESTIMATED[name] = float(meta["attributes"]["geff"]["extra"]["estimated_number_of_nodes"])
        except (OSError, KeyError, ValueError):
            _ESTIMATED[name] = float("nan")
    return _ESTIMATED[name]


NODE_COLUMNS = ("sample", "time", "leaf", "z", "y", "x", "voxels", "object", "object_members", "forward", "departure",
                "held")
NODE_OPTIONAL = (("object_link", "-1"), ("object_links", "0"), ("null_draws", "0"), ("null_at_least", "0"),
                 ("null_best", "0"), ("split_from", "-1"))


def read_rows(handle, head, held):
    for line in handle:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < len(head):
            continue
        row = dict(zip(head, parts))
        held[row["sample"]][int(row["time"])].append({
            "leaf": int(row["leaf"]),
            "place": (int(row["z"]), int(row["y"]), int(row["x"])),
            "voxels": int(row["voxels"]),
            "object": int(row["object"]),
            "members": int(row["object_members"]),
            "forward": int(row["forward"]),
            "departure": int(row["departure"]),
            "held": int(row["held"]),
            "object_link": int(row.get("object_link", -1)),
            "object_links": int(row.get("object_links", 0)),
            "null_draws": int(row.get("null_draws", 0)),
            "null_at_least": int(row.get("null_at_least", 0)),
            "null_best": int(row.get("null_best", 0)),
            "split_from": int(row.get("split_from", -1)),
        })


def read_rows_fast(handle, head, held):
    # read_rows by column number: a column the head names twice is read at its last place, as dict(zip()) keeps it,
    # and an optional column the head lacks reads its default from a tail past the row's own fields. Rows come a frame
    # at a time, so the frame's list is looked up only when the sample or time field changes
    index = {}
    for at, name in enumerate(head):
        index[name] = at
    width = len(head)
    tail = []
    for name, fallback in NODE_OPTIONAL:
        if name not in index:
            index[name] = width + len(tail)
            tail.append(fallback)
    (sample, time, leaf, z, y, x, voxels, identity, members, forward, departure, kept, link, links, draws, at_least,
     best, split) = (index[name] for name in NODE_COLUMNS + tuple(name for name, _ in NODE_OPTIONAL))
    last = (None, None)
    frame = None
    for line in handle:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < width:
            continue
        if tail:
            parts = parts[:width] + tail
        if (parts[sample], parts[time]) != last:
            last = (parts[sample], parts[time])
            frame = held[parts[sample]][int(parts[time])]
        frame.append({
            "leaf": int(parts[leaf]),
            "place": (int(parts[z]), int(parts[y]), int(parts[x])),
            "voxels": int(parts[voxels]),
            "object": int(parts[identity]),
            "members": int(parts[members]),
            "forward": int(parts[forward]),
            "departure": int(parts[departure]),
            "held": int(parts[kept]),
            "object_link": int(parts[link]),
            "object_links": int(parts[links]),
            "null_draws": int(parts[draws]),
            "null_at_least": int(parts[at_least]),
            "null_best": int(parts[best]),
            "split_from": int(parts[split]),
        })


def read_nodes(path):
    held = collections.defaultdict(lambda: collections.defaultdict(list))
    with open(path, encoding="utf-8") as handle:
        head = handle.readline().rstrip("\n").split("\t")
        if all(name in head for name in NODE_COLUMNS):
            read_rows_fast(handle, head, held)
        else:
            read_rows(handle, head, held)
    for frames in held.values():
        times = sorted(frames)
        for at, time in enumerate(times[1:], 1):
            earlier = {one["leaf"]: one for one in frames[times[at - 1]]}
            for one in frames[time]:
                parent = earlier.get(one["split_from"])
                if parent is None:
                    continue
                parent.setdefault("children", [parent["forward"]]).append(one["leaf"])
    return held


def as_objects(frames):
    object_of = {}
    for time, bodies in frames.items():
        for one in bodies:
            object_of[(time, one["leaf"])] = one["object"]
    times = sorted(frames)
    onward = {time: times[at + 1] for at, time in enumerate(times[:-1])}
    held = {}
    for time, bodies in frames.items():
        grouped = collections.defaultdict(list)
        for one in bodies:
            grouped[one["object"]].append(one)
        rows = []
        for identity, members in grouped.items():
            leader = max(members, key=lambda one: one["voxels"])
            later = onward.get(time)
            went = collections.Counter()
            for one in members:
                if (one["forward"] >= 0) and (later is not None):
                    target = object_of.get((later, one["forward"]), -1)
                    if target >= 0:
                        went[target] += one["voxels"]
            ranked = [target for target, _ in went.most_common()]
            forward = leader["object_link"] if (leader["object_links"] > 0) else (ranked[0] if ranked else -1)
            rows.append({
                "leaf": identity,
                "place": leader["place"],
                "voxels": sum(one["voxels"] for one in members),
                "object": identity,
                "members": len(members),
                "forward": forward,
                "children": ranked[:1],
                "departure": min(one["departure"] for one in members),
                "held": max(one["held"] for one in members),
                "null_draws": leader["null_draws"],
                "null_at_least": min(one["null_at_least"] for one in members),
                "null_best": min(one["null_best"] for one in members),
            })
        held[time] = rows
    return held


def cell_of(place):
    return (math.floor(SCALE[0] * place[0] / REACH_UM), math.floor(SCALE[1] * place[1] / REACH_UM),
            math.floor(SCALE[2] * place[2] / REACH_UM))


def match(predicted, truth_nodes, truth_places):
    # the true nodes in a grid of cells REACH_UM wide in scaled um, each listed under its own cell and the 26 around
    # it, so the list under a predicted node's cell is every true node in that cell and the 26 around it. A pair within
    # REACH_UM differs by at most one cell on every axis, so no pair is lost; the pairs are measured and sorted as when
    # every predicted node met every true node, and the matching is the same
    near = collections.defaultdict(list)
    for identity in truth_nodes:
        _, tz, ty, tx = truth_places[identity]
        cz, cy, cx = cell_of((tz, ty, tx))
        for dz in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    near[(cz + dz, cy + dy, cx + dx)].append((identity, tz, ty, tx))
    pairs = []
    for at, node in enumerate(predicted):
        for identity, tz, ty, tx in near.get(cell_of(node["place"]), ()):
            apart = math.sqrt(sum((SCALE[axis] * (node["place"][axis] - (tz, ty, tx)[axis])) ** 2
                                  for axis in range(3)))
            if apart <= REACH_UM:
                pairs.append((apart, at, identity))
    pairs.sort()
    taken_prediction = set()
    taken_truth = set()
    matched = {}
    for _, at, identity in pairs:
        if (at in taken_prediction) or (identity in taken_truth):
            continue
        taken_prediction.add(at)
        taken_truth.add(identity)
        matched[at] = identity
    return matched


def score(dumped, directory, policy, first=25, quiet=False, objects=False, names=None):
    names = truth_io.every(directory)[:first] if names is None else names
    edge_tp = edge_fp = edge_fn = 0
    division_tp = division_fp = division_fn = 0
    predicted_total = 0
    truth_total = 0
    per_sample = []
    for name in names:
        if name not in dumped:
            continue
        truth = truth_io.read(os.path.join(directory, name + ".geff"))
        truth_by_time = truth.by_time()
        truth_edges = set(truth.edges)
        truth_divisions = truth.divisions()
        frames = as_objects(dumped[name]) if objects else dumped[name]
        chosen = {time: policy(frames[time]) for time in frames}
        predicted_here = sum(len(one) for one in chosen.values())
        predicted_total += predicted_here
        truth_total += estimated_nodes(name)
        became = {}
        for time, picked in chosen.items():
            keys = truth_by_time.get(time, [])
            if not picked or not keys:
                continue
            matched = match(picked, keys, truth.nodes)
            for at, identity in matched.items():
                became[(time, picked[at]["leaf"])] = identity
        times = sorted(frames)
        onward = {}
        for at, time in enumerate(times[:-1]):
            onward[time] = times[at + 1]
        ours = set()
        our_children = collections.defaultdict(set)
        for time, picked in chosen.items():
            later = onward.get(time)
            if later is None:
                continue
            taken = {one["leaf"] for one in chosen.get(later, [])}
            for node in picked:
                for child in node.get("children", [node["forward"]]):
                    if (child < 0) or (child not in taken):
                        continue
                    ours.add(((time, node["leaf"]), (later, child)))
                    our_children[(time, node["leaf"])].add((later, child))
        out_degree = collections.Counter()
        in_degree = collections.Counter()
        for a, b in truth_edges:
            out_degree[a] += 1
            in_degree[b] += 1
        here_tp = 0
        for source, target in ours:
            a = became.get(source)
            b = became.get(target)
            out_valid = (a is not None) and (out_degree[a] > 0)
            in_valid = (b is not None) and (in_degree[b] > 0)
            if not (out_valid or in_valid):
                continue
            if (a is not None) and (b is not None) and ((a, b) in truth_edges):
                here_tp += 1
            else:
                edge_fp += 1
        edge_tp += here_tp
        edge_fn += len(truth_edges) - here_tp
        ours_divided = {became[parent]: frozenset(became[child] for child in children if child in became)
                        for parent, children in our_children.items()
                        if (len(children) > 1) and (parent in became)}
        for parent, children in ours_divided.items():
            if truth_divisions.get(parent) == children:
                division_tp += 1
            else:
                division_fp += 1
        division_fn += len(set(truth_divisions) - set(ours_divided))
        per_sample.append((name, len(truth.nodes), predicted_here))

    jaccard = (edge_tp / (edge_tp + edge_fp + edge_fn)) if (edge_tp + edge_fp + edge_fn) else 0.0
    over = ((predicted_total - truth_total) / truth_total) if truth_total else 0.0
    adjusted = max(0.0, jaccard * (1.0 - (COUNT_WEIGHT * over)))
    divisions = ((division_tp / (division_tp + division_fp + division_fn))
                 if (division_tp + division_fp + division_fn) else 0.0)
    final = adjusted + (DIVISION_WEIGHT * divisions)
    if not quiet:
        print("  nodes: predicted %d against %d true, %+.1f%% over" % (predicted_total, truth_total, 100 * over))
        print("  edges: TP %d, FP %d, FN %d" % (edge_tp, edge_fp, edge_fn))
        print("  edge jaccard      %.6f" % jaccard)
        print("  node count factor %.6f" % (1.0 - (COUNT_WEIGHT * over)))
        print("  adjusted jaccard  %.6f" % adjusted)
        print("  divisions: TP %d, FP %d, FN %d, jaccard %.6f"
              % (division_tp, division_fp, division_fn, divisions))
        print("  SCORE             %.6f" % final)
    return final, adjusted, jaccard, predicted_total, truth_total


def policy_all(frame):
    return list(frame)


def policy_largest(count):
    def pick(frame):
        return sorted(frame, key=lambda one: -one["voxels"])[:count]
    return pick


def policy_cell_sized(count):
    def pick(frame):
        if not frame:
            return []
        sizes = sorted(one["voxels"] for one in frame)
        middle = sizes[len(sizes) // 2]
        return sorted(frame, key=lambda one: abs(one["voxels"] - middle))[:count]
    return pick


def policy_linked_and_sized(count):
    def pick(frame):
        usable = [one for one in frame if one["forward"] >= 0]
        if not usable:
            return []
        sizes = sorted(one["voxels"] for one in usable)
        middle = sizes[len(sizes) // 2]
        return sorted(usable, key=lambda one: abs(one["voxels"] - middle))[:count]
    return pick


def policy_held(count):
    def pick(frame):
        usable = [one for one in frame if one["forward"] >= 0]
        return sorted(usable, key=lambda one: -one["held"])[:count]
    return pick


def policy_still(count):
    def pick(frame):
        usable = [one for one in frame if one["forward"] >= 0]
        return sorted(usable, key=lambda one: (one["departure"], -one["voxels"]))[:count]
    return pick


def policy_stands(_ignored=None):
    def pick(frame):
        usable = [one for one in frame if one["forward"] >= 0]
        if not usable:
            return []
        ordered = sorted(usable, key=lambda one: one["voxels"])
        total = sum(one["voxels"] for one in ordered)
        running = 0
        center = ordered[-1]["voxels"]
        for one in ordered:
            running += one["voxels"]
            if running * 2 >= total:
                center = one["voxels"]
                break
        return [one for one in usable
                if ((one["voxels"] * 2) >= center) and (one["voxels"] <= (center * 2))]
    return pick


def policy_above_null(_ignored=None):
    def pick(frame):
        usable = [one for one in frame if one["forward"] >= 0]
        if not usable or (usable[0]["null_draws"] == 0):
            return usable
        return [one for one in usable if one["null_at_least"] == 0]
    return pick


POLICIES = {
    "stands": policy_stands,
    "above_null": policy_above_null,
    "all": lambda: policy_all,
    "largest": policy_largest,
    "sized": policy_cell_sized,
    "linked": policy_linked_and_sized,
    "held": policy_held,
    "still": policy_still,
}


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "D:/kaggle_project_data/tsv/nodes25.tsv"
    directory = sys.argv[2] if len(sys.argv) > 2 else "D:/kaggle_project_data/biohub_cell_tracking_data/train"
    wanted = sys.argv[3] if len(sys.argv) > 3 else "sweep"
    dumped = read_nodes(path)
    print("  read %d samples from %s" % (len(dumped), path))
    if wanted == "sweep":
        print()
        print("  %-8s %-10s %6s %12s %12s %12s" % ("grain", "policy", "n", "nodes", "jaccard", "SCORE"))
        for objects in (False, True):
            grain = "object" if objects else "body"
            final, adjusted, jaccard, predicted, truth = score(
                dumped, directory, policy_stands(), quiet=True, objects=objects)
            print("  %-8s %-10s %6s %12d %12.6f %12.6f  (target %d)"
                  % (grain, "stands", "-", predicted, jaccard, final, truth))
            final, adjusted, jaccard, predicted, _ = score(
                dumped, directory, policy_all, quiet=True, objects=objects)
            print("  %-8s %-10s %6s %12d %12.6f %12.6f" % (grain, "all", "-", predicted, jaccard, final))
            for name in ("largest", "held"):
                for count in (200, 400, 700):
                    final, adjusted, jaccard, predicted, _ = score(
                        dumped, directory, POLICIES[name](count), quiet=True, objects=objects)
                    print("  %-8s %-10s %6d %12d %12.6f %12.6f"
                          % (grain, name, count, predicted, jaccard, final))
        return 0
    count = int(sys.argv[4]) if len(sys.argv) > 4 else 3
    objects = (len(sys.argv) > 5) and (sys.argv[5] == "object")
    names = None
    if (len(sys.argv) > 6) and (sys.argv[6] == "nodes"):
        names = sorted(dumped)
        if not names:
            print("  the nodes hold no samples")
            return 1
        keys = set(truth_io.every(directory))
        missing = [name for name in names if name not in keys]
        if missing:
            print("  no key in %s for: %s" % (directory, " ".join(missing)))
            return 1
        print("  scoring the %d samples the nodes hold: %s .. %s" % (len(names), names[0], names[-1]))
    score(dumped, directory, POLICIES[wanted](count) if wanted != "all" else policy_all, objects=objects,
          names=names)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
