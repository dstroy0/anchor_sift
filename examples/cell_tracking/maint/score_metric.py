import collections
import csv
import json
import os
import sys
import warnings

import numpy as np
import scipy.sparse as sp
from scipy.optimize import linear_sum_assignment
from scipy.sparse.csgraph import min_weight_full_bipartite_matching
from scipy.spatial import cKDTree
from scipy.spatial.distance import cdist

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import score_submission
import truth_io

# The competition's metric, rebuilt from its published code so that a submission CSV is scored here as it is graded.
# The source is royerlab's competition scoring code at commit 075fc5f5a52d11077f9dc2b074644618f26939e2 (metrics.py,
# division_metrics.py, io.py, scripts/csv_to_geffs.py and scripts/evaluate.py) and the tracksdata it matches with,
# royerlab/tracksdata at e13cf379b5127deeb8301ce56410fda35b5a3cf9 (BaseGraph.match, _matching_data,
# _match_single_frame, _fill_empty and DistanceMatching). score_submission.py is left as it was. Where the prose and
# the code part, the code is followed. Each step as read:
#
#   the graph    a dataset's rows as csv_to_geffs builds them: a node for each node row and an edge for each edge row,
#                each in the order the rows come. An edge's id is its place among the dataset's edge rows. source_id
#                and target_id name node_ids. A node_id named twice is its later row, as csv_to_geffs's dict keeps it,
#                and an edge that names no node errors on the CSV, as csv_to_geffs raises
#   the key      its nodes and edges through truth_io, in the geff's array order. n_total is the geff's
#                estimated_number_of_nodes through score_submission.estimated_nodes, NaN where it is absent
#   the scale    the dataset's .zarr, multiscales[0].datasets[0].coordinateTransformations[0].scale[-3:], as
#                io._parse_scale reads it; DEFAULT_SCALE where there is no .zarr or it holds no multiscales
#   matching     frame by frame, as _match_single_frame. The key's nodes of the frame are the rows and the CSV's nodes
#                of the frame the columns, each in its graph's order. A pair within MAX_DISTANCE after the scale weighs
#                1/(1+d), and the weights, taken column by column as np.where takes them, are a float32 csr_array one
#                past the largest row and column that hold a pair. scipy's min_weight_full_bipartite_matching
#                (maximize) is run on it. When that raises, the empty rows and columns are filled with -1 and it is
#                run again; when that raises too, linear_sum_assignment (maximize) is run on the dense matrix, -1
#                where nothing is. A pair reading -1 in the sparse weights is dropped. A pair the dense run takes where
#                the sparse weights hold nothing reads 0 there, not -1, and is kept, as the published code keeps it
#   edges        as _evaluate_matched_graph. A CSV edge is matched when its ends are matched to the ends of a key edge.
#                The copies of one source and target are one edge; the copies agree on matched, and the lowest id is
#                kept, where polars' unique after an unstable sort names none. Only edges one frame forward are kept.
#                Of the edges with both ends matched, the lowest id for each matched pair is kept; under a one-to-one
#                matching no two share one. Each source keeps its two lowest ids. An edge is counted when its source is
#                matched to a key node with an edge out or its target to one with an edge in. TP is the matched edges,
#                FP the counted less TP, FN the key's edges less TP. A CSV graph with no edges or no nodes is TP 0,
#                FP 0 and FN the key's edges
#   divisions    as division_metrics. A key division is a node with exactly two edges out, copies counted, as
#                rustworkx counts them. Its window is its parents, itself, its children and theirs, in that order, and
#                for each window the whole CSV graph is matched as above against the window's nodes alone. CSV forks
#                are the nodes with two or more edges out over every CSV edge, not only those the edge counts keep.
#                Successors and predecessors are a node's distinct neighbors, as rustworkx's successor_indices gives
#                them. The candidates, the one-to-one pairing and the false forks (the considered, the evaluable, the
#                malformed and the cross-component, less the paired) follow score_divisions and
#                _pred_division_fork_sets line for line. The key's components are its weakly connected ones
#   the score    per_sample_metrics and summarize: J = TP/(TP+FP+FN), ratio = (CSV nodes - n_total)/n_total and
#                adjusted = max(0, J (1 - 0.1 ratio)) per dataset; the adjusted J weighted by TP+FP+FN over the
#                datasets; the division Jaccard over the summed division counts; the score is the adjusted J plus 0.1
#                of the division Jaccard, or the adjusted J alone when no dataset holds a division TP, FP or FN
#   datasets     those in both the CSV and the keys, as evaluate_pairs takes them. A dataset the CSV lacks is not scored
#
#   score_metric.py <submission.csv> [<dataset> ...]

KEYS = truth_io.SOURCE
DEFAULT_SCALE = (1.625, 0.40625, 0.40625)
MAX_DISTANCE = 7.0
ADJUSTMENT_ALPHA = 0.1
SCORE_DIVISION_WEIGHT = 0.1
FILL_VALUE = -1.0
# the reach the tree is asked for past MAX_DISTANCE, so that no pair the exact distance keeps is missed
REACH_SLACK = 1e-6
COLUMNS = ("dataset", "row_type", "node_id", "t", "z", "y", "x", "source_id", "target_id")


class Graph(object):
    # a graph as tracksdata holds it: its nodes numbered in the order they come, the order the matching lays a frame
    # out in, and its edges numbered in the order they come, which is their id

    def __init__(self):
        self.times = []
        self.places = []
        self.sources = []
        self.targets = []
        self.joined = False
        self.frames = {}

    def add_node(self, time, z, y, x):
        self.times.append(time)
        self.places.append((z, y, x))
        self.joined = False
        self.frames = {}
        return len(self.times) - 1

    def add_edge(self, source, target):
        self.sources.append(source)
        self.targets.append(target)
        self.joined = False
        return len(self.sources) - 1

    def join(self):
        # degrees count an edge's copies; successors and predecessors are distinct, in the order their edges come
        if self.joined:
            return self
        count = len(self.times)
        self.out_degree = [0] * count
        self.in_degree = [0] * count
        self.successors = [[] for _ in range(count)]
        self.predecessors = [[] for _ in range(count)]
        for source, target in zip(self.sources, self.targets):
            self.out_degree[source] += 1
            self.in_degree[target] += 1
            self.successors[source].append(target)
            self.predecessors[target].append(source)
        self.successors = [list(dict.fromkeys(held)) for held in self.successors]
        self.predecessors = [list(dict.fromkeys(held)) for held in self.predecessors]
        self.by_time = collections.defaultdict(list)
        for node, time in enumerate(self.times):
            self.by_time[time].append(node)
        self.joined = True
        return self

    def frame(self, time, scale):
        # a frame's nodes, their places after the scale, the finite ones and a tree over those
        held = self.frames.get((time, scale))
        if held is None:
            members = self.by_time.get(time, [])
            places = np.array([self.places[node] for node in members], dtype=np.float64).reshape(-1, 3)
            if scale is not None:
                places = places * np.array(scale)
            finite = np.flatnonzero(np.isfinite(places).all(axis=1))
            tree = cKDTree(places[finite]) if len(finite) else None
            held = (members, places, finite, tree)
            self.frames[(time, scale)] = held
        return held


def key_graph(truth):
    graph = Graph()
    index = {}
    for identity, (time, z, y, x) in truth.nodes.items():
        index[identity] = graph.add_node(int(time), float(z), float(y), float(x))
    for source, target in truth.edges:
        graph.add_edge(index[source], index[target])
    return graph.join()


def identity_of(text):
    try:
        return int(text)
    except ValueError:
        return text


def time_of(text):
    try:
        return int(text)
    except ValueError:
        return int(float(text))


def read_submission(handle):
    # the CSV's graphs by dataset, as csv_to_geffs builds them: the nodes first and then the edges, each in row order
    reader = csv.reader(handle)
    head = next(reader)
    missing = [name for name in COLUMNS if name not in head]
    if missing:
        raise ValueError("the CSV has no column %s" % ", ".join(missing))
    at = {name: head.index(name) for name in COLUMNS}
    graphs = {}
    named = {}
    edges = collections.defaultdict(list)
    for parts in reader:
        dataset = parts[at["dataset"]]
        kind = parts[at["row_type"]]
        if kind == "node":
            graph = graphs.get(dataset)
            if graph is None:
                graph = graphs[dataset] = Graph()
                named[dataset] = {}
            node = graph.add_node(time_of(parts[at["t"]]), float(parts[at["z"]]), float(parts[at["y"]]),
                                  float(parts[at["x"]]))
            named[dataset][identity_of(parts[at["node_id"]])] = node
        elif kind == "edge":
            edges[dataset].append((identity_of(parts[at["source_id"]]), identity_of(parts[at["target_id"]])))
    for dataset, held in edges.items():
        if dataset not in graphs:
            graphs[dataset] = Graph()
            named[dataset] = {}
        for source, target in held:
            if (source not in named[dataset]) or (target not in named[dataset]):
                raise ValueError("%s: an edge %s -> %s names no node" % (dataset, source, target))
            graphs[dataset].add_edge(named[dataset][source], named[dataset][target])
    for graph in graphs.values():
        graph.join()
    return graphs


def read_scale(name):
    # io._parse_scale on the dataset's .zarr attributes, and DEFAULT_SCALE where there is no .zarr
    root = os.path.join(KEYS, name + ".zarr")
    if not os.path.isdir(root):
        return DEFAULT_SCALE
    if os.path.exists(os.path.join(root, "zarr.json")):
        with open(os.path.join(root, "zarr.json"), encoding="utf-8") as handle:
            attributes = json.load(handle).get("attributes", {})
    elif os.path.exists(os.path.join(root, ".zattrs")):
        with open(os.path.join(root, ".zattrs"), encoding="utf-8") as handle:
            attributes = json.load(handle)
    else:
        attributes = {}
    if "multiscales" not in attributes:
        return DEFAULT_SCALE
    transform = attributes["multiscales"][0]["datasets"][0]["coordinateTransformations"][0]
    if transform["type"] != "scale":
        raise ValueError("Transform type is not 'scale': %s" % transform)
    return tuple(float(value) for value in transform["scale"][-3:])


def fill_empty(weights, fill_value):
    # _fill_empty: the empty rows and columns found first, then each filled whole
    empty_rows = weights.sum(axis=1) == 0
    empty_cols = weights.sum(axis=0) == 0
    if empty_rows.any():
        weights[empty_rows, :] = fill_value
    if empty_cols.any():
        weights[:, empty_cols] = fill_value


def entries(weights, rows, columns):
    values = weights[rows, columns]
    if sp.issparse(values):
        values = values.toarray()
    return np.asarray(values).ravel()


def match_frame(reference, compared, finite, tree, max_distance):
    # _match_single_frame's optimal matching of one frame: the (row, column) pairs, rows the reference's nodes and
    # columns the compared nodes
    if tree is None:
        return []
    columns = []
    rows = []
    distances = []
    usable = np.flatnonzero(np.isfinite(reference).all(axis=1))
    if not len(usable):
        return []
    found = tree.query_ball_point(reference[usable], max_distance + REACH_SLACK)
    for row, near in zip(usable.tolist(), found):
        if not near:
            continue
        near = finite[np.asarray(near, dtype=np.int64)]
        apart = cdist(compared[near], reference[row:row + 1])[:, 0]
        kept = apart <= max_distance
        columns.extend(near[kept].tolist())
        rows.extend([row] * int(kept.sum()))
        distances.extend(apart[kept].tolist())
    if not rows:
        return []
    order = np.lexsort((np.asarray(rows), np.asarray(columns)))
    rows = np.asarray(rows)[order]
    columns = np.asarray(columns)[order]
    scores = (1.0 / (1.0 + np.asarray(distances)[order])).tolist()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", sp.SparseEfficiencyWarning)
        weights = sp.csr_array((scores, (rows.tolist(), columns.tolist())), dtype=np.float32)
        try:
            rows_id, cols_id = min_weight_full_bipartite_matching(weights, maximize=True)
        except ValueError:
            fill_empty(weights, FILL_VALUE)
            try:
                rows_id, cols_id = min_weight_full_bipartite_matching(weights, maximize=True)
            except ValueError:
                coo_weights = weights.tocoo()
                dense_weights = np.full(weights.shape, FILL_VALUE, dtype=np.float32)
                dense_weights[coo_weights.row, coo_weights.col] = coo_weights.data
                rows_id, cols_id = linear_sum_assignment(dense_weights, maximize=True)
            is_filled = np.isclose(entries(weights, rows_id, cols_id), FILL_VALUE)
            rows_id = rows_id[~is_filled]
            cols_id = cols_id[~is_filled]
    return list(zip(np.asarray(rows_id).tolist(), np.asarray(cols_id).tolist()))


def match(graph, key, key_nodes=None, scale=None, max_distance=MAX_DISTANCE):
    # BaseGraph.match of graph against key, or against the key's subgraph of key_nodes in their order: each matched
    # node of graph and the key node it is matched to
    graph.join()
    key.join()
    if key_nodes is None:
        reference_by_time = key.by_time
    else:
        reference_by_time = collections.defaultdict(list)
        for node in key_nodes:
            reference_by_time[key.times[node]].append(node)
    matched = {}
    for time, reference_nodes in reference_by_time.items():
        if time not in graph.by_time:
            continue
        members, places, finite, tree = graph.frame(time, scale)
        reference = np.array([key.places[node] for node in reference_nodes], dtype=np.float64).reshape(-1, 3)
        if scale is not None:
            reference = reference * np.array(scale)
        for row, column in match_frame(reference, places, finite, tree, max_distance):
            matched[members[column]] = reference_nodes[row]
    return matched


def edge_counts(graph, key, matched, record=None):
    # _evaluate_matched_graph and the counts evaluate takes from it; record, when given, takes each kept edge's source,
    # target, whether it is matched and whether it is counted
    to_graph = {truth: node for node, truth in matched.items()}
    wanted = set()
    for source, target in zip(key.sources, key.targets):
        if (source in to_graph) and (target in to_graph):
            wanted.add((to_graph[source], to_graph[target]))
    first = {}
    for edge, pair in enumerate(zip(graph.sources, graph.targets)):
        if pair not in first:
            first[pair] = edge
    dropped = {"copies": len(graph.sources) - len(first)}
    edges = sorted(first.values())
    forward = [edge for edge in edges if graph.times[graph.targets[edge]] - graph.times[graph.sources[edge]] == 1]
    dropped["not one frame forward"] = len(edges) - len(forward)
    lowest = {}
    for edge in forward:
        pair = (matched.get(graph.sources[edge]), matched.get(graph.targets[edge]))
        if (pair[0] is not None) and (pair[1] is not None) and (pair not in lowest):
            lowest[pair] = edge
    unmerged = []
    for edge in forward:
        pair = (matched.get(graph.sources[edge]), matched.get(graph.targets[edge]))
        if (pair[0] is not None) and (pair[1] is not None) and (lowest[pair] != edge):
            continue
        unmerged.append(edge)
    dropped["merged"] = len(forward) - len(unmerged)
    taken = collections.Counter()
    capped = []
    for edge in unmerged:
        if taken[graph.sources[edge]] < 2:
            taken[graph.sources[edge]] += 1
            capped.append(edge)
    dropped["past two out"] = len(unmerged) - len(capped)
    tp = 0
    valid = 0
    for edge in capped:
        source = matched.get(graph.sources[edge])
        target = matched.get(graph.targets[edge])
        out_valid = (source is not None) and (key.out_degree[source] > 0)
        in_valid = (target is not None) and (key.in_degree[target] > 0)
        is_matched = (graph.sources[edge], graph.targets[edge]) in wanted
        if is_matched:
            if not (out_valid or in_valid):
                raise AssertionError("a matched edge is not counted")
            tp += 1
        if out_valid or in_valid:
            valid += 1
        if record is not None:
            record.append((graph.sources[edge], graph.targets[edge], is_matched, out_valid or in_valid))
    return tp, valid - tp, len(key.sources) - tp, dropped


def max_matching(left, edges):
    # _bipartite_max_matching: augmenting paths by depth-first search
    match_r = {}
    match_l = {}

    def augment(u, seen):
        for v in edges.get(u, ()):
            if v in seen:
                continue
            seen.add(v)
            if (v not in match_r) or augment(match_r[v], seen):
                match_l[u] = v
                match_r[v] = u
                return True
        return False

    for u in left:
        augment(u, set())
    return match_l


def weak_components(graph):
    component = {}
    for seed in range(len(graph.times)):
        if seed in component:
            continue
        component[seed] = seed
        stack = [seed]
        while stack:
            current = stack.pop()
            for neighbor in graph.successors[current] + graph.predecessors[current]:
                if neighbor not in component:
                    component[neighbor] = seed
                    stack.append(neighbor)
    return component


def branch_evidence(graph, fork, child, matched, component):
    # _branch_component_evidence: the key component a fork's child branch shows, and whether the branch is malformed
    if set(graph.predecessors[child]) != {fork}:
        return None, True
    if child in matched:
        return component[matched[child]], False
    grandchildren = graph.successors[child]
    if any(set(graph.predecessors[node]) != {child} for node in grandchildren):
        return None, True
    found = {component[matched[node]] for node in grandchildren if node in matched}
    if len(found) == 1:
        return next(iter(found)), False
    return None, False


def fork_sets(graph, key, matched, forks):
    # _pred_division_fork_sets: the evaluable, cross-component and malformed forks
    evaluable = {fork for fork in forks if (fork in matched) and (key.out_degree[matched[fork]] >= 1)}
    component = weak_components(key)
    cross = set()
    malformed = set()
    for fork in sorted(forks):
        evidence = []
        for child in graph.successors[fork]:
            found, broken = branch_evidence(graph, fork, child, matched, component)
            if broken:
                malformed.add(fork)
                break
            if found is not None:
                evidence.append(found)
        else:
            if len(set(evidence)) >= 2:
                cross.add(fork)
    return evaluable, cross, malformed


def division_roles(local, key, divider):
    # _matched_division_nodes: the nodes matched to the parent side, and to each daughter's side
    if not local:
        return None
    children = key.successors[divider]
    if len(children) < 2:
        return None
    parent_side = {divider, *key.predecessors[divider]}
    parents = {node for node, truth in local.items() if truth in parent_side}
    daughters = [{node for node, truth in local.items() if truth in {child, *key.successors[child]}}
                 for child in children]
    if (not parents) or (sum(bool(held) for held in daughters) < 2):
        return None
    return parents, daughters


def strongly_connected(graph, fork, parents, daughters):
    # _is_strongly_connected_division
    if {fork, *graph.predecessors[fork]}.isdisjoint(parents):
        return False
    lineages = [{child, *graph.successors[child]} for child in graph.successors[fork]]
    edges = {lineage: {at for at, members in enumerate(lineages) if not held.isdisjoint(members)}
             for lineage, held in enumerate(daughters)}
    return len(max_matching(list(edges), edges)) >= 2


def division_window(key, divider):
    # extract_divisions: the divider's parents, itself, its children and their children
    children = key.successors[divider]
    grandchildren = [node for child in children for node in key.successors[child]]
    return list(dict.fromkeys([*key.predecessors[divider], divider, *children, *grandchildren]))


def division_counts(graph, key, matched, scale=None, max_distance=MAX_DISTANCE):
    # score_divisions and evaluate_divisions: TP, FP and FN, each key division's score, and the paired, false and
    # evaluable forks
    forks = {node for node in range(len(graph.times)) if graph.out_degree[node] >= 2}
    evaluable, cross, malformed = fork_sets(graph, key, matched, forks)
    invalid = cross | malformed
    candidates = {}
    considered = set()
    for divider in range(len(key.times)):
        if key.out_degree[divider] != 2:
            continue
        local = match(graph, key, division_window(key, divider), scale, max_distance)
        roles = division_roles(local, key, divider)
        if roles is None:
            candidates[divider] = set()
            continue
        parents, daughters = roles
        nearby = parents | {successor for parent in parents for successor in graph.successors[parent]}
        local_forks = nearby & forks
        considered |= local_forks
        candidates[divider] = {fork for fork in local_forks - invalid
                               if strongly_connected(graph, fork, parents, daughters)}
    pairing = max_matching(list(candidates), candidates)
    scores = {divider: int(divider in pairing) for divider in candidates}
    tp_forks = set(pairing.values())
    fp_forks = (considered | evaluable | invalid) - tp_forks
    return {"tp": sum(scores.values()), "fp": len(fp_forks), "fn": len(scores) - sum(scores.values()),
            "scores": scores, "tp_forks": tp_forks, "fp_forks": fp_forks, "evaluable_forks": evaluable}


def evaluate(graph, key, scale=None, max_distance=MAX_DISTANCE):
    # metrics.evaluate on one dataset, with evaluate_pairs' node recall
    graph.join()
    key.join()
    matched = match(graph, key, None, scale, max_distance) if graph.times else {}
    if graph.sources:
        edge_tp, edge_fp, edge_fn, dropped = edge_counts(graph, key, matched)
        recall = len(set(matched.values())) / len(key.times)
    else:
        edge_tp, edge_fp, edge_fn = 0, 0, len(key.sources)
        dropped = {}
        recall = 0.0
    divisions = division_counts(graph, key, matched, scale, max_distance)
    return {
        "edge_tp": edge_tp, "edge_fp": edge_fp, "edge_fn": edge_fn,
        "division_tp": divisions["tp"], "division_fp": divisions["fp"], "division_fn": divisions["fn"],
        "num_pred_nodes": len(graph.times),
        "node_recall": recall,
        "dropped": dropped,
        "divisions": divisions,
    }


def per_sample_metrics(counts, n_total):
    if n_total > 0:
        total_node_ratio = (counts["num_pred_nodes"] - n_total) / n_total
    else:
        total_node_ratio = float("nan")
    denominator = counts["edge_tp"] + counts["edge_fp"] + counts["edge_fn"]
    edge_jaccard = counts["edge_tp"] / denominator if denominator > 0 else float("nan")
    if (edge_jaccard == edge_jaccard) and (total_node_ratio == total_node_ratio):
        adjusted = max(0.0, edge_jaccard * (1 - ADJUSTMENT_ALPHA * total_node_ratio))
    else:
        adjusted = float("nan")
    row = dict(counts)
    row.update({"total_node_ratio": total_node_ratio, "edge_jaccard": edge_jaccard, "adj_edge_jaccard": adjusted})
    return row


def jaccard(tp, fp, fn):
    denominator = tp + fp + fn
    return tp / denominator if denominator > 0 else float("nan")


def summarize(rows):
    valid = [row for row in rows if row["edge_tp"] == row["edge_tp"]]
    if not valid:
        return {"n": 0, "edge_jaccard": float("nan"), "division_jaccard": float("nan"), "division_tp": 0,
                "division_fp": 0, "division_fn": 0, "node_recall": float("nan"), "adj_edge_jaccard": float("nan"),
                "n_adj": 0, "score": float("nan"), "edge_tp": 0, "edge_fp": 0, "edge_fn": 0}
    totals = {name: sum(row[name] for row in valid)
              for name in ("edge_tp", "edge_fp", "edge_fn", "division_tp", "division_fp", "division_fn",
                           "num_pred_nodes")}
    adjusted_rows = [row for row in valid if row["adj_edge_jaccard"] == row["adj_edge_jaccard"]]
    weights = [row["edge_tp"] + row["edge_fp"] + row["edge_fn"] for row in adjusted_rows]
    total_weight = sum(weights)
    if total_weight > 0:
        adjusted = sum(weight * row["adj_edge_jaccard"] for weight, row in zip(weights, adjusted_rows)) / total_weight
    else:
        adjusted = float("nan")
    if totals["division_tp"] + totals["division_fp"] + totals["division_fn"] == 0:
        division_jaccard = float("nan")
        score = adjusted
    else:
        division_jaccard = jaccard(totals["division_tp"], totals["division_fp"], totals["division_fn"])
        score = adjusted + SCORE_DIVISION_WEIGHT * division_jaccard
    return {
        "n": len(valid),
        "edge_jaccard": jaccard(totals["edge_tp"], totals["edge_fp"], totals["edge_fn"]),
        "division_jaccard": division_jaccard,
        "edge_tp": totals["edge_tp"], "edge_fp": totals["edge_fp"], "edge_fn": totals["edge_fn"],
        "division_tp": totals["division_tp"], "division_fp": totals["division_fp"],
        "division_fn": totals["division_fn"],
        "node_recall": sum(row["node_recall"] for row in valid) / len(valid),
        "adj_edge_jaccard": adjusted,
        "n_adj": len(adjusted_rows),
        "score": score,
    }


def main():
    if len(sys.argv) < 2:
        print("  score_metric.py <submission.csv> [<dataset> ...]")
        return 1
    path = sys.argv[1]
    with open(path, newline="", encoding="utf-8") as handle:
        graphs = read_submission(handle)
    keys = truth_io.every(KEYS)
    names = sorted(set(graphs) & set(keys))
    print("  %s: %d datasets in both the CSV and the keys (of %d in the CSV / %d keys)"
          % (path, len(names), len(graphs), len(keys)))
    if len(sys.argv) > 2:
        wanted = sys.argv[2:]
        absent = [name for name in wanted if name not in names]
        if absent:
            print("  not in both the CSV and the keys: %s" % " ".join(absent))
            return 1
        names = sorted(set(wanted))
        print("  scoring the %d named: %s" % (len(names), " ".join(names)))
    rows = []
    skipped = []
    for name in names:
        try:
            key = key_graph(truth_io.read(os.path.join(KEYS, name + ".geff")))
            scale = read_scale(name)
            counts = evaluate(graphs[name], key, scale, MAX_DISTANCE)
            n_total = score_submission.estimated_nodes(name)
        except Exception as problem:
            skipped.append(name)
            print("  SKIP %s: %s: %s" % (name, type(problem).__name__, problem))
            continue
        row = per_sample_metrics(counts, n_total)
        rows.append(row)
        print("  %s: edge TP/FP/FN=%d/%d/%d div TP/FP/FN=%d/%d/%d n_pred=%d"
              % (name, row["edge_tp"], row["edge_fp"], row["edge_fn"], row["division_tp"], row["division_fp"],
                 row["division_fn"], row["num_pred_nodes"]))
        print("      scale %s, n_total %.0f, key %d nodes %d edges, node recall %.6f, edge jaccard %.6f,"
              " adjusted %.6f" % (scale, n_total, len(key.times), len(key.sources), row["node_recall"],
                                  row["edge_jaccard"], row["adj_edge_jaccard"]))
        print("      edges dropped: %s" % ", ".join("%d %s" % (count, reason)
                                                    for reason, count in row["dropped"].items()))
    if skipped:
        print("  skipped %d unreadable datasets: %s" % (len(skipped), skipped))
    summary = summarize(rows)
    print("  === Summary ===")
    print("  n=%d  score=%.4f  edge_jaccard=%.4f  adj_edge_jaccard=%.4f (n_adj=%d)  division_jaccard=%.4f"
          " (TP=%d FP=%d FN=%d)  node_recall=%.4f"
          % (summary["n"], summary["score"], summary["edge_jaccard"], summary["adj_edge_jaccard"], summary["n_adj"],
             summary["division_jaccard"], summary["division_tp"], summary["division_fp"], summary["division_fn"],
             summary["node_recall"]))
    print("  edges: TP %d, FP %d, FN %d" % (summary["edge_tp"], summary["edge_fp"], summary["edge_fn"]))
    print("  edge jaccard      %.6f" % summary["edge_jaccard"])
    print("  adjusted jaccard  %.6f" % summary["adj_edge_jaccard"])
    if summary["division_jaccard"] == summary["division_jaccard"]:
        print("  divisions: TP %d, FP %d, FN %d, jaccard %.6f"
              % (summary["division_tp"], summary["division_fp"], summary["division_fn"],
                 summary["division_jaccard"]))
    else:
        print("  divisions: TP 0, FP 0, FN 0. The division term is dropped")
    print("  SCORE             %.6f" % summary["score"])
    return 1 if skipped else 0


if __name__ == "__main__":
    raise SystemExit(main())
