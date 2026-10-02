import io
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "maint"))
import score_metric
import truth_io

# score_metric (cell_tracking/maint) held to the published metric's own tests. The cases and the counts they assert
# are those of tests/test_division_sandbox_examples.py, tests/test_division_metrics.py and tests/test_metrics.py in
# royerlab's competition scoring code at commit 075fc5f5a52d11077f9dc2b074644618f26939e2, each named as its test is. A
# count marked "by hand" is this file's own, worked from the published code, where the published test asserts less.
# The geff cases read the training key 6bba_c328f2fd through truth_io, as the published ones read it. The CSV cases
# are this file's: they hold the graph csv_to_geffs builds. Host work, no device
#   score_metric_test.py


class Tally(object):

    def __init__(self):
        self.checks = 0
        self.failures = 0

    def held(self, what, got, want):
        self.checks += 1
        if got != want:
            self.failures += 1
            print("  FAILED: %s: %r, and was to be %r" % (what, got, want))

    def near(self, what, got, want):
        # pytest.approx's default: within a millionth of what is wanted, or 1e-12
        self.checks += 1
        if not (abs(got - want) <= max(1e-6 * abs(want), 1e-12)):
            self.failures += 1
            print("  FAILED: %s: %r, and was to be %r" % (what, got, want))

    def true(self, what, got):
        self.held(what, bool(got), True)


TALLY = Tally()


def build(nodes, edges):
    # nodes: a dict of name to (t, z, y, x), in order
    graph = score_metric.Graph()
    ids = {}
    for name, (t, z, y, x) in nodes.items():
        ids[name] = graph.add_node(t, z, y, x)
    for source, target in edges:
        graph.add_edge(ids[source], ids[target])
    return graph.join(), ids


def at(t, y):
    # the sandbox's nodes: t and y, with z and x 0
    return (t, 0.0, y, 0.0)


def evaluate(pred, gt, max_distance=score_metric.MAX_DISTANCE, scale=None):
    return score_metric.evaluate(pred, gt, scale, max_distance)


def jaccard_of(pred, gt, max_distance=score_metric.MAX_DISTANCE, scale=None):
    # _jaccard_of: the edge Jaccard, 0 where TP + FP + FN is 0
    result = evaluate(pred, gt, max_distance, scale)
    denominator = result["edge_tp"] + result["edge_fp"] + result["edge_fn"]
    return result["edge_tp"] / denominator if denominator > 0 else 0.0


def all_counts(result):
    return (result["edge_tp"], result["edge_fp"], result["edge_fn"], result["division_tp"], result["division_fp"],
            result["division_fn"])


def division_counts(pred, gt, max_distance):
    # evaluate_divisions: (tp, fn, fp)
    result = evaluate(pred, gt, max_distance)
    return (result["division_tp"], result["division_fn"], result["division_fp"])


def named(ids, nodes):
    return {name for name, node in ids.items() if node in nodes}


# test_division_sandbox_examples.py

GT_DIVISION = ({"P": at(0, 0.0), "D": at(1, 0.0), "C1": at(2, 5.0), "C2": at(2, -5.0), "G1": at(3, 5.0),
                "G2": at(3, -5.0)},
               [("P", "D"), ("D", "C1"), ("D", "C2"), ("C1", "G1"), ("C2", "G2")])

HACK2_GT = ({"61": at(1, 10.0), "62": at(2, 10.0), "63": at(3, 0.0), "64": at(3, 20.0), "66": at(4, 20.0),
             "98": at(4, 0.0), "99": at(1, -40.0), "100": at(2, -40.0), "101": at(3, -25.0), "102": at(4, -25.0),
             "103": at(3, -45.0), "104": at(4, -45.0)},
            [("61", "62"), ("62", "63"), ("62", "64"), ("64", "66"), ("63", "98"), ("99", "100"), ("100", "101"),
             ("101", "102"), ("100", "103"), ("103", "104")])

HACK2_PRED = ({"105": at(0, 15.0), "106": at(2, 15.0), "107": at(3, 30.0), "108": at(3, 5.0), "109": at(4, 5.0),
               "110": at(4, 30.0), "114": at(4, -20.0), "115": at(3, -50.0), "116": at(4, -50.0),
               "121": at(5, -50.0), "122": at(1, 55.0), "124": at(2, 55.0), "130": at(3, 55.0),
               "132": at(1, 15.0), "153": at(2, -35.0)},
              [("106", "107"), ("108", "109"), ("107", "110"), ("115", "116"), ("116", "121"), ("122", "124"),
               ("124", "108"), ("124", "130"), ("130", "114"), ("105", "132"), ("132", "106"), ("105", "122"),
               ("122", "153"), ("106", "115")])

SANDBOX = {
    "hack2": (HACK2_GT, HACK2_PRED, (5, 4, 5, 0, 4, 2), 10.0),
    "perfect_division": (GT_DIVISION, GT_DIVISION, (5, 0, 0, 1, 0, 0), 1.0),
    "missed_division": (GT_DIVISION,
                        ({"P": at(0, 0.0), "D": at(1, 0.0), "C1": at(2, 5.0), "G1": at(3, 5.0)},
                         [("P", "D"), ("D", "C1"), ("C1", "G1")]),
                        (3, 0, 2, 0, 0, 1), 1.0),
    "delayed_local_division": (GT_DIVISION,
                               ({"P": at(0, 0.0), "D": at(1, 0.0), "M": at(2, 0.0), "G1": at(3, 5.0),
                                 "G2": at(3, -5.0)},
                                [("P", "D"), ("D", "M"), ("M", "G1"), ("M", "G2")]),
                               (1, 3, 4, 1, 0, 0), 1.0),
    "dummy_branch_same_lineage": (GT_DIVISION,
                                  ({"P": at(0, 0.0), "D": at(1, 0.0), "C1": at(2, 5.0), "X": at(2, 50.0),
                                    "G2": at(3, -5.0)},
                                   [("P", "D"), ("D", "C1"), ("D", "X"), ("C1", "G2")]),
                                  (2, 2, 3, 0, 1, 1), 1.0),
    "spurious_linear_division": (({"A": at(0, 20.0), "B": at(1, 20.0), "C": at(2, 20.0)},
                                  [("A", "B"), ("B", "C")]),
                                 ({"A": at(0, 20.0), "B": at(1, 20.0), "C1": at(2, 20.0), "C2": at(2, 25.0)},
                                  [("A", "B"), ("B", "C1"), ("B", "C2")]),
                                 (2, 1, 0, 0, 1, 0), 1.0),
    "cross_component_children": (({"A0": at(0, 0.0), "A1": at(1, 0.0), "B0": at(0, 20.0), "B1": at(1, 20.0)},
                                  [("A0", "A1"), ("B0", "B1")]),
                                 ({"P": at(0, 0.0), "C1": at(1, 0.0), "C2": at(1, 20.0)},
                                  [("P", "C1"), ("P", "C2")]),
                                 (1, 1, 1, 0, 1, 0), 1.0),
    "cross_component_grandchild_fallback": (({"A1": at(1, 0.0), "A2": at(2, 0.0), "B1": at(1, 20.0),
                                              "B2": at(2, 20.0)},
                                             [("A1", "A2"), ("B1", "B2")]),
                                            ({"F": at(0, 10.0), "A": at(1, 0.0), "U": at(1, 40.0),
                                              "B": at(2, 20.0)},
                                             [("F", "A"), ("F", "U"), ("U", "B")]),
                                            (0, 1, 2, 0, 1, 0), 1.0),
    "disconnected_daughter": (GT_DIVISION,
                              (GT_DIVISION[0], [("P", "D"), ("D", "C1"), ("C1", "G1"), ("C2", "G2")]),
                              (4, 0, 1, 0, 0, 1), 1.0),
}


def sandbox_cases():
    for name in sorted(SANDBOX):
        gt_spec, pred_spec, want, max_distance = SANDBOX[name]
        gt, _ = build(*gt_spec)
        pred, _ = build(*pred_spec)
        TALLY.held("sandbox %s: edge TP, FP, FN, division TP, FP, FN" % name,
                   all_counts(evaluate(pred, gt, max_distance)), want)
    gt, _ = build(*HACK2_GT)
    pred, ids = build(*HACK2_PRED)
    TALLY.held("sandbox hack2: the false forks", named(ids, evaluate(pred, gt, 10.0)["divisions"]["fp_forks"]),
               {"105", "106", "122", "124"})


# test_division_metrics.py

def xyz(t, z, y, x):
    return (t, z, y, x)


GT_NODES = {"P": xyz(0, 0.0, 0.0, 0.0), "D": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 5.0, 0.0),
            "C2": xyz(2, 0.0, -5.0, 0.0), "G1": xyz(3, 0.0, 5.0, 0.0), "G2": xyz(3, 0.0, -5.0, 0.0)}
GT_EDGES = [("P", "D"), ("D", "C1"), ("D", "C2"), ("C1", "G1"), ("C2", "G2")]
TWO_COMPONENT_NODES = {"A1": xyz(1, 0.0, 0.0, 0.0), "A2": xyz(2, 0.0, 0.0, 0.0), "B1": xyz(1, 0.0, 20.0, 0.0),
                       "B2": xyz(2, 0.0, 20.0, 0.0)}
TWO_COMPONENT_EDGES = [("A1", "A2"), ("B1", "B2")]

TWO_DIVISIONS_GT = ({"P1": xyz(0, 0.0, 10.0, 0.0), "D1": xyz(1, 0.0, 10.0, 0.0), "C1a": xyz(2, 0.0, 15.0, 0.0),
                     "C1b": xyz(2, 0.0, 5.0, 0.0), "C1a2": xyz(3, 0.0, 15.0, 0.0), "C1b2": xyz(3, 0.0, 5.0, 0.0),
                     "P2": xyz(0, 0.0, -10.0, 0.0), "D2": xyz(1, 0.0, -10.0, 0.0), "C2a": xyz(2, 0.0, -5.0, 0.0),
                     "C2b": xyz(2, 0.0, -15.0, 0.0), "C2a2": xyz(3, 0.0, -5.0, 0.0),
                     "C2b2": xyz(3, 0.0, -15.0, 0.0)},
                    [("P1", "D1"), ("D1", "C1a"), ("D1", "C1b"), ("C1a", "C1a2"), ("C1b", "C1b2"), ("P2", "D2"),
                     ("D2", "C2a"), ("D2", "C2b"), ("C2a", "C2a2"), ("C2b", "C2b2")])


def windows(graph):
    # extract_divisions: each divider's window, its nodes and the key's edges among them
    held = {}
    for divider in range(len(graph.times)):
        if graph.out_degree[divider] != 2:
            continue
        nodes = set(score_metric.division_window(graph, divider))
        edges = sum(1 for source, target in zip(graph.sources, graph.targets) if source in nodes and target in nodes)
        held[divider] = (len(nodes), edges)
    return held


def extract_divisions_cases():
    graph, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0), "C": xyz(2, 0.0, 0.0, 0.0)},
                     [("A", "B"), ("B", "C")])
    TALLY.held("test_no_divisions", windows(graph), {})
    graph, ids = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 5.0, 0.0),
                        "C2": xyz(2, 0.0, -5.0, 0.0), "D": xyz(3, 0.0, -5.0, 0.0), "E": xyz(3, 0.0, 5.0, 0.0)},
                       [("A", "B"), ("B", "C1"), ("B", "C2"), ("C2", "D"), ("C1", "E")])
    TALLY.held("test_single_division", windows(graph), {ids["B"]: (6, 5)})
    graph, ids = build({"B": xyz(0, 0.0, 0.0, 0.0), "C1": xyz(1, 0.0, 5.0, 0.0), "C2": xyz(1, 0.0, -5.0, 0.0),
                        "D": xyz(2, 0.0, -5.0, 0.0), "E": xyz(2, 0.0, 5.0, 0.0)},
                       [("B", "C1"), ("B", "C2"), ("C2", "D"), ("C1", "E")])
    TALLY.held("test_single_division_no_parent", windows(graph), {ids["B"]: (5, 4)})
    graph, ids = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 5.0, 0.0),
                        "C2": xyz(2, 0.0, -5.0, 0.0)},
                       [("A", "B"), ("B", "C1"), ("B", "C2")])
    TALLY.held("test_single_division_leaf_children", windows(graph), {ids["B"]: (4, 3)})
    graph, ids = build(*TWO_DIVISIONS_GT)
    TALLY.held("test_two_independent_divisions", windows(graph), {ids["D1"]: (6, 5), ids["D2"]: (6, 5)})
    graph, ids = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 5.0, 0.0),
                        "C2": xyz(2, 0.0, -5.0, 0.0), "E": xyz(3, 0.0, 5.0, 0.0), "G": xyz(3, 0.0, -5.0, 0.0),
                        "F1": xyz(4, 0.0, 8.0, 0.0), "F2": xyz(4, 0.0, 2.0, 0.0)},
                       [("A", "B"), ("B", "C1"), ("B", "C2"), ("C1", "E"), ("C2", "G"), ("E", "F1"), ("E", "F2")])
    TALLY.held("test_chained_divisions_are_separate", windows(graph), {ids["B"]: (6, 5), ids["E"]: (4, 3)})
    graph, _ = build({}, [])
    TALLY.held("test_empty_graph", windows(graph), {})


def strongly_connected_cases():
    pred, ids = build({"GP": xyz(0, 0.0, 0.0, 0.0), "P": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 1.0, 0.0),
                       "C2": xyz(2, 0.0, -1.0, 0.0), "G2": xyz(3, 0.0, -1.0, 0.0)},
                      [("GP", "P"), ("P", "C1"), ("P", "C2"), ("C2", "G2")])
    TALLY.held("test_accepts_local_division_window",
               score_metric.strongly_connected(pred, ids["P"], {ids["GP"]}, [{ids["C1"]}, {ids["G2"]}]), True)
    pred, ids = build({"P": xyz(0, 0.0, 0.0, 0.0), "C1": xyz(1, 0.0, 1.0, 0.0), "C2": xyz(1, 0.0, -1.0, 0.0),
                       "G2": xyz(2, 0.0, -1.0, 0.0), "GG2": xyz(3, 0.0, -1.0, 0.0)},
                      [("P", "C1"), ("P", "C2"), ("C2", "G2"), ("G2", "GG2")])
    TALLY.held("test_rejects_great_grandchild_match",
               score_metric.strongly_connected(pred, ids["P"], {ids["P"]}, [{ids["C1"]}, {ids["GG2"]}]), False)
    pred, ids = build({"P": xyz(0, 0.0, 0.0, 0.0), "C": xyz(1, 0.0, 1.0, 0.0), "G": xyz(2, 0.0, 1.0, 0.0),
                       "X": xyz(1, 0.0, 20.0, 0.0)},
                      [("P", "C"), ("P", "X"), ("C", "G")])
    TALLY.held("test_requires_distinct_pred_daughter_lineages",
               score_metric.strongly_connected(pred, ids["P"], {ids["P"]}, [{ids["C"]}, {ids["G"]}]), False)


def score_divisions_cases():
    gt, _ = build(GT_NODES, GT_EDGES)
    pred, _ = build(GT_NODES, GT_EDGES)
    result = evaluate(pred, gt, 1.0)["divisions"]
    TALLY.held("TestScoreDivisions test_perfect_prediction: the scores", set(result["scores"].values()), {1})
    TALLY.held("TestScoreDivisions test_perfect_prediction: the paired forks", len(result["tp_forks"]), 1)
    TALLY.held("TestScoreDivisions test_perfect_prediction: the false forks", result["fp_forks"], set())
    pred, _ = build(GT_NODES, [("P", "D"), ("D", "C1"), ("C1", "G1"), ("C2", "G2")])
    TALLY.held("test_disconnected_child", set(evaluate(pred, gt, 1.0)["divisions"]["scores"].values()), {0})
    pred, _ = build({"P": xyz(0, 0.0, 0.0, 0.0), "D": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 5.0, 0.0),
                     "G1": xyz(3, 0.0, 5.0, 0.0)},
                    [("P", "D"), ("D", "C1"), ("C1", "G1")])
    TALLY.held("test_linear_no_fork", set(evaluate(pred, gt, 1.0)["divisions"]["scores"].values()), {0})
    pred, _ = build({"X": xyz(0, 0.0, 100.0, 100.0), "Y": xyz(1, 0.0, 100.0, 100.0)}, [("X", "Y")])
    TALLY.held("test_no_matched_nodes", set(evaluate(pred, gt, 1.0)["divisions"]["scores"].values()), {0})
    gt, gt_ids = build(GT_NODES, GT_EDGES)
    pred, pred_ids = build({"P": xyz(0, 0.0, 0.0, 0.0), "D": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 5.0, 0.0),
                            "X": xyz(2, 0.0, 50.0, 0.0), "G2": xyz(3, 0.0, -5.0, 0.0)},
                           [("P", "D"), ("D", "C1"), ("D", "X"), ("C1", "G2")])
    result = evaluate(pred, gt, 1.0)["divisions"]
    TALLY.held("test_rejected_local_fork_is_false_positive: D's score", result["scores"][gt_ids["D"]], 0)
    TALLY.held("test_rejected_local_fork_is_false_positive: the paired forks", result["tp_forks"], set())
    TALLY.held("test_rejected_local_fork_is_false_positive: the false forks", named(pred_ids, result["fp_forks"]),
               {"D"})
    TALLY.held("test_rejected_local_fork_is_false_positive: tp, fn, fp", division_counts(pred, gt, 1.0), (0, 1, 1))
    pred, _ = build({"P": xyz(0, 0.0, 0.0, 0.0), "D": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 5.0, 0.0),
                     "C2": xyz(2, 0.0, -5.0, 0.0), "G1": xyz(3, 0.0, 5.0, 0.0), "G2": xyz(3, 0.0, -5.0, 0.0)},
                    [("P", "D"), ("D", "C1"), ("C1", "G1"), ("C2", "G2")])
    TALLY.held("test_fork_but_wrong_topology", set(evaluate(pred, gt, 1.0)["divisions"]["scores"].values()), {0})
    gt, gt_ids = build(*TWO_DIVISIONS_GT)
    pred, _ = build({"P1": xyz(0, 0.0, 10.0, 0.0), "D1": xyz(1, 0.0, 10.0, 0.0), "C1a": xyz(2, 0.0, 15.0, 0.0),
                     "C1b": xyz(2, 0.0, 5.0, 0.0), "C1a2": xyz(3, 0.0, 15.0, 0.0), "C1b2": xyz(3, 0.0, 5.0, 0.0),
                     "P2": xyz(0, 0.0, -10.0, 0.0), "D2": xyz(1, 0.0, -10.0, 0.0), "C2a": xyz(2, 0.0, -5.0, 0.0),
                     "C2a2": xyz(3, 0.0, -5.0, 0.0)},
                    [("P1", "D1"), ("D1", "C1a"), ("D1", "C1b"), ("C1a", "C1a2"), ("C1b", "C1b2"), ("P2", "D2"),
                     ("D2", "C2a"), ("C2a", "C2a2")])
    scores = evaluate(pred, gt, 1.0)["divisions"]["scores"]
    TALLY.held("test_two_divisions_mixed_scores", (scores[gt_ids["D1"]], scores[gt_ids["D2"]]), (1, 0))
    gt, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0)}, [("A", "B")])
    pred, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0)}, [("A", "B")])
    TALLY.held("test_no_gt_divisions", evaluate(pred, gt, 1.0)["divisions"]["scores"], {})
    gt, _ = build(GT_NODES, GT_EDGES)
    pred, _ = build({"P": xyz(0, 0.0, 0.0, 0.0), "D": xyz(1, 0.0, 0.0, 0.0), "M": xyz(2, 0.0, 0.0, 0.0),
                     "C1": xyz(3, 0.0, 5.0, 0.0), "C2": xyz(3, 0.0, -5.0, 0.0)},
                    [("P", "D"), ("D", "M"), ("M", "C1"), ("M", "C2")])
    TALLY.held("test_connected_via_intermediate_nodes",
               set(evaluate(pred, gt, 1.0)["divisions"]["scores"].values()), {1})
    gt, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0), "D": xyz(2, 0.0, 0.0, 0.0),
                   "C1": xyz(3, 0.0, 5.0, 0.0), "C2": xyz(3, 0.0, -5.0, 0.0)},
                  [("A", "B"), ("B", "D"), ("D", "C1"), ("D", "C2")])
    pred, _ = build({"P1": xyz(0, 0.0, -20.0, 0.0), "P2": xyz(1, 0.0, -15.0, 0.0), "P3": xyz(2, 0.0, 0.5, 0.0),
                     "P4": xyz(3, 0.0, 5.0, 0.0), "P5": xyz(3, 0.0, -5.0, 0.0), "Q1": xyz(0, 0.0, 0.1, 0.0),
                     "Q2": xyz(1, 0.0, 0.1, 0.0), "Q3": xyz(2, 0.0, 50.0, 0.0)},
                    [("P1", "P2"), ("P2", "P3"), ("P3", "P4"), ("P3", "P5"), ("Q1", "Q2"), ("Q2", "Q3")])
    TALLY.held("test_matched_parent_from_different_track",
               set(evaluate(pred, gt, 5.0)["divisions"]["scores"].values()), {1})


def count_matched_cases():
    def evaluable(pred, gt):
        return len(evaluate(pred, gt, 1.0)["divisions"]["evaluable_forks"])

    gt, _ = build(GT_NODES, GT_EDGES)
    pred, _ = build(GT_NODES, GT_EDGES)
    TALLY.held("TestCountMatchedPredDivisions test_perfect_prediction", evaluable(pred, gt), 1)
    gt, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0), "C": xyz(2, 0.0, 0.0, 0.0)},
                  [("A", "B"), ("B", "C")])
    pred, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 0.0, 0.0),
                     "C2": xyz(2, 0.0, 5.0, 0.0)},
                    [("A", "B"), ("B", "C1"), ("B", "C2")])
    TALLY.held("test_spurious_division_on_linear_gt", evaluable(pred, gt), 1)
    gt, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0), "C": xyz(2, 0.0, 0.0, 0.0),
                   "D": xyz(0, 0.0, 20.0, 0.0), "E": xyz(1, 0.0, 20.0, 0.0), "F": xyz(2, 0.0, 20.0, 0.0)},
                  [("A", "B"), ("B", "C"), ("D", "E"), ("E", "F")])
    pred, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 0.0, 0.0),
                     "C2": xyz(2, 0.0, 5.0, 0.0), "D": xyz(0, 0.0, 20.0, 0.0), "E": xyz(1, 0.0, 20.0, 0.0),
                     "F1": xyz(2, 0.0, 20.0, 0.0), "F2": xyz(2, 0.0, 25.0, 0.0)},
                    [("A", "B"), ("B", "C1"), ("B", "C2"), ("D", "E"), ("E", "F1"), ("E", "F2")])
    TALLY.held("test_two_divisions", evaluable(pred, gt), 2)
    gt, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0)}, [("A", "B")])
    pred, _ = build({"X": xyz(0, 0.0, 100.0, 0.0), "Y": xyz(1, 0.0, 105.0, 0.0), "Z": xyz(1, 0.0, 95.0, 0.0)},
                    [("X", "Y"), ("X", "Z")])
    TALLY.held("test_unmatched_division_not_counted", evaluable(pred, gt), 0)
    gt, _ = build({"P": xyz(0, 0.0, 0.0, 0.0), "D": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 5.0, 0.0),
                   "C2": xyz(2, 0.0, -5.0, 0.0), "A": xyz(0, 0.0, 20.0, 0.0), "B": xyz(1, 0.0, 20.0, 0.0),
                   "C": xyz(2, 0.0, 20.0, 0.0)},
                  [("P", "D"), ("D", "C1"), ("D", "C2"), ("A", "B"), ("B", "C")])
    pred, _ = build({"P": xyz(0, 0.0, 0.0, 0.0), "D": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 5.0, 0.0),
                     "C2": xyz(2, 0.0, -5.0, 0.0), "A": xyz(0, 0.0, 20.0, 0.0), "B": xyz(1, 0.0, 20.0, 0.0),
                     "E1": xyz(2, 0.0, 20.0, 0.0), "E2": xyz(2, 0.0, 25.0, 0.0)},
                    [("P", "D"), ("D", "C1"), ("D", "C2"), ("A", "B"), ("B", "E1"), ("B", "E2")])
    TALLY.held("test_mixed_real_and_spurious", evaluable(pred, gt), 2)


def evaluate_divisions_cases():
    gt, _ = build(GT_NODES, GT_EDGES)
    pred, _ = build(GT_NODES, GT_EDGES)
    TALLY.held("TestEvaluateDivisions test_perfect_prediction", division_counts(pred, gt, 1.0), (1, 0, 0))
    pred, _ = build({"P": xyz(0, 0.0, 0.0, 0.0), "D": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 5.0, 0.0),
                     "G1": xyz(3, 0.0, 5.0, 0.0)},
                    [("P", "D"), ("D", "C1"), ("C1", "G1")])
    TALLY.held("test_missed_division", division_counts(pred, gt, 1.0), (0, 1, 0))
    gt, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0), "C": xyz(2, 0.0, 0.0, 0.0)},
                  [("A", "B"), ("B", "C")])
    pred, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0), "C1": xyz(2, 0.0, 0.0, 0.0),
                     "C2": xyz(2, 0.0, 5.0, 0.0)},
                    [("A", "B"), ("B", "C1"), ("B", "C2")])
    TALLY.held("test_spurious_division", division_counts(pred, gt, 1.0), (0, 0, 1))
    two = ({"A0": xyz(0, 0.0, 0.0, 0.0), "A1": xyz(1, 0.0, 0.0, 0.0), "B0": xyz(0, 0.0, 20.0, 0.0),
            "B1": xyz(1, 0.0, 20.0, 0.0)},
           [("A0", "A1"), ("B0", "B1")])
    gt, _ = build(*two)
    pred, pred_ids = build({"P": xyz(0, 0.0, 0.0, 0.0), "C1": xyz(1, 0.0, 0.0, 0.0), "C2": xyz(1, 0.0, 20.0, 0.0)},
                           [("P", "C1"), ("P", "C2")])
    TALLY.held("test_children_matched_to_distinct_gt_components_are_one_fp: the false forks",
               named(pred_ids, evaluate(pred, gt, 1.0)["divisions"]["fp_forks"]), {"P"})
    TALLY.held("test_children_matched_to_distinct_gt_components_are_one_fp: tp, fn, fp",
               division_counts(pred, gt, 1.0), (0, 0, 1))
    pred, _ = build({"P": xyz(0, 0.0, 10.0, 0.0), "C": xyz(1, 0.0, 0.0, 0.0), "X": xyz(1, 0.0, 50.0, 0.0)},
                    [("P", "C"), ("P", "X")])
    TALLY.held("test_cross_component_rule_requires_two_matched_branches", division_counts(pred, gt, 1.0),
               (0, 0, 0))
    gt, _ = build(TWO_COMPONENT_NODES, TWO_COMPONENT_EDGES)
    pred, pred_ids = build({"F": xyz(0, 0.0, 10.0, 0.0), "A": xyz(1, 0.0, 0.0, 0.0), "U": xyz(1, 0.0, 40.0, 0.0),
                            "B": xyz(2, 0.0, 20.0, 0.0)},
                           [("F", "A"), ("F", "U"), ("U", "B")])
    TALLY.held("test_uses_grandchild_when_direct_child_is_unmatched",
               named(pred_ids, evaluate(pred, gt, 1.0)["divisions"]["fp_forks"]), {"F"})
    pred, _ = build({"F": xyz(0, 0.0, 10.0, 0.0), "A": xyz(1, 0.0, 0.0, 0.0), "U": xyz(1, 0.0, 40.0, 0.0),
                     "B": xyz(2, 0.0, 20.0, 0.0)},
                    [("F", "A"), ("F", "U"), ("A", "B")])
    TALLY.held("test_does_not_mix_child_and_grandchild_from_one_branch", division_counts(pred, gt, 1.0), (0, 0, 0))
    gt_nodes = dict(GT_NODES)
    gt_nodes.update({"X2": xyz(2, 0.0, 40.0, 0.0), "X3": xyz(3, 0.0, 40.0, 0.0), "Y2": xyz(2, 0.0, -40.0, 0.0),
                     "Y3": xyz(3, 0.0, -40.0, 0.0)})
    gt, _ = build(gt_nodes, GT_EDGES + [("X2", "X3"), ("Y2", "Y3")])
    pred, _ = build({"P": GT_NODES["P"], "D": GT_NODES["D"], "C1": GT_NODES["C1"], "C2": GT_NODES["C2"],
                     "W1": gt_nodes["X3"], "W2": gt_nodes["Y3"]},
                    [("P", "D"), ("D", "C1"), ("D", "C2"), ("C1", "W1"), ("C2", "W2")])
    TALLY.held("test_matched_children_take_precedence_over_wrong_grandchildren", division_counts(pred, gt, 1.0),
               (1, 0, 0))
    gt, _ = build(TWO_COMPONENT_NODES, TWO_COMPONENT_EDGES)
    pred, pred_ids = build({"F": xyz(0, 0.0, 10.0, 0.0), "U1": xyz(1, 0.0, 40.0, 0.0), "U2": xyz(1, 0.0, 50.0, 0.0),
                            "G": xyz(2, 0.0, 0.0, 0.0)},
                           [("F", "U1"), ("F", "U2"), ("U1", "G"), ("U2", "G")])
    TALLY.held("test_merged_grandchild_makes_fork_malformed",
               named(pred_ids, evaluate(pred, gt, 1.0)["divisions"]["fp_forks"]), {"F"})
    gt_spec = dict(TWO_DIVISIONS_GT[0])
    gt_spec.update({"A": xyz(0, 0.0, 30.0, 0.0), "B": xyz(1, 0.0, 30.0, 0.0), "C": xyz(2, 0.0, 30.0, 0.0)})
    gt, _ = build(gt_spec, TWO_DIVISIONS_GT[1] + [("A", "B"), ("B", "C")])
    pred, _ = build({"P1": xyz(0, 0.0, 10.0, 0.0), "D1": xyz(1, 0.0, 10.0, 0.0), "C1a": xyz(2, 0.0, 15.0, 0.0),
                     "C1b": xyz(2, 0.0, 5.0, 0.0), "C1a2": xyz(3, 0.0, 15.0, 0.0), "C1b2": xyz(3, 0.0, 5.0, 0.0),
                     "P2": xyz(0, 0.0, -10.0, 0.0), "D2": xyz(1, 0.0, -10.0, 0.0), "C2a": xyz(2, 0.0, -5.0, 0.0),
                     "C2a2": xyz(3, 0.0, -5.0, 0.0), "A": xyz(0, 0.0, 30.0, 0.0), "B": xyz(1, 0.0, 30.0, 0.0),
                     "E1": xyz(2, 0.0, 30.0, 0.0), "E2": xyz(2, 0.0, 35.0, 0.0)},
                    [("P1", "D1"), ("D1", "C1a"), ("D1", "C1b"), ("C1a", "C1a2"), ("C1b", "C1b2"), ("P2", "D2"),
                     ("D2", "C2a"), ("C2a", "C2a2"), ("A", "B"), ("B", "E1"), ("B", "E2")])
    TALLY.held("test_mixed_tp_fn_fp", division_counts(pred, gt, 1.0), (1, 1, 1))
    gt, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0)}, [("A", "B")])
    pred, _ = build({"A": xyz(0, 0.0, 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0)}, [("A", "B")])
    TALLY.held("test_no_divisions_in_either", division_counts(pred, gt, 1.0), (0, 0, 0))
    gt, _ = build(GT_NODES, GT_EDGES)
    copies = {}
    copy_edges = []
    for copy in (1, 2, 3):
        copies.update({"P%d" % copy: xyz(0, 0.0, 0.0, 0.0), "D%d" % copy: xyz(1, 0.0, 0.0, 0.0),
                       "C%da" % copy: xyz(2, 0.0, 5.0, 0.0), "C%db" % copy: xyz(2, 0.0, -5.0, 0.0),
                       "G%da" % copy: xyz(3, 0.0, 5.0, 0.0), "G%db" % copy: xyz(3, 0.0, -5.0, 0.0)})
        copy_edges += [("P%d" % copy, "D%d" % copy), ("D%d" % copy, "C%da" % copy), ("D%d" % copy, "C%db" % copy),
                       ("C%da" % copy, "G%da" % copy), ("C%db" % copy, "G%db" % copy)]
    pred, _ = build(copies, copy_edges)
    TALLY.held("test_duplicate_pred_divisions_no_tp_inflation", division_counts(pred, gt, 1.0), (1, 0, 0))


# test_metrics.py

ORIGIN = xyz(0, 0.0, 0.0, 0.0)


def make_graph_cases():
    # _make_graph: the pred and key graphs and a matching set by hand, pred 1 -> key 0, 2 -> 1 and 5 -> 3
    graph, _ = build({str(node): xyz(t, 0.0, 0.0, 0.0) for node, t in enumerate([0, 1, 2, 2, 3, 3])},
                     [("0", "1"), ("1", "2"), ("1", "3"), ("2", "4"), ("2", "5")])
    gt, _ = build({str(node): xyz(t, 0.0, 0.0, 0.0) for node, t in enumerate([1, 2, 3, 3])},
                  [("0", "1"), ("1", "2"), ("1", "3")])
    record = []
    tp, fp, fn, _ = score_metric.edge_counts(graph, gt, {1: 0, 2: 1, 5: 3}, record)
    TALLY.held("test_evaluate_matched_graph_overlap",
               sorted([source, target] for source, target, matched, _ in record if matched), [[1, 2], [2, 5]])
    TALLY.held("test_evaluate_matched_graph_pred_valid",
               sorted([source, target] for source, target, _, counted in record if counted),
               [[1, 2], [1, 3], [2, 4], [2, 5]])
    TALLY.near("test_compute_score_jaccard", tp / (tp + fp + fn), 2 / 5)
    TALLY.near("test_compute_score_dice", 2 * tp / (len(gt.sources) + tp + fp), 4 / 7)


def simple(z=0.0, y=0.0, x=0.0):
    graph, _ = build({"A": ORIGIN, "B": xyz(1, z, y, x)}, [("A", "B")])
    return graph


def matching_cases():
    gt = simple()
    TALLY.near("test_evaluate_perfect_prediction", jaccard_of(simple(), gt, 1.0), 1.0)
    far, _ = build({"A": xyz(0, 100.0, 100.0, 100.0), "B": xyz(1, 100.0, 100.0, 100.0)}, [("A", "B")])
    TALLY.near("test_evaluate_no_matching_prediction", jaccard_of(far, gt, 1.0), 0.0)
    for axis in ("z", "y", "x"):
        TALLY.near("test_distance_threshold: 14 along %s" % axis, jaccard_of(simple(**{axis: 14.0}), gt, 15.0), 1.0)
        TALLY.near("test_distance_threshold: 16 along %s" % axis, jaccard_of(simple(**{axis: 16.0}), gt, 15.0), 0.0)
    pred = simple(z=4.0)
    TALLY.near("test_scale_parameter: none", jaccard_of(pred, gt, 15.0), 1.0)
    TALLY.near("test_scale_parameter: (4, 1, 1)", jaccard_of(pred, gt, 15.0, (4.0, 1.0, 1.0)), 0.0)
    TALLY.near("test_scale_parameter: (2, 1, 1)", jaccard_of(pred, gt, 15.0, (2.0, 1.0, 1.0)), 1.0)


def track(times, shift=0.0):
    return {"N%d" % t: xyz(t, 0.0, 0.0, float(t) + shift) for t in times}


def edge_rule_cases():
    gt, _ = build(track(range(3)), [("N0", "N1"), ("N1", "N2")])
    pred, _ = build(track(range(4)), [("N0", "N1"), ("N1", "N2"), ("N2", "N3")])
    TALLY.near("test_extra_edge_at_track_end_not_penalized", jaccard_of(pred, gt, 0.5), 1.0)
    gt, _ = build(track(range(1, 4)), [("N1", "N2"), ("N2", "N3")])
    pred, _ = build(track(range(4)), [("N0", "N1"), ("N1", "N2"), ("N2", "N3")])
    TALLY.near("test_extra_edge_at_track_start_not_penalized", jaccard_of(pred, gt, 0.5), 1.0)

    line = {"A": ORIGIN, "B": xyz(1, 0.0, 0.0, 0.0), "C": xyz(2, 0.0, 0.0, 0.0)}
    with_d = dict(line)
    with_d["D"] = xyz(1, 100.0, 100.0, 100.0)
    for extra, want in ((("D", "A"), 1.0), (("D", "B"), 1.0), (("D", "C"), 2 / 3), (("A", "D"), 2 / 3),
                        (("B", "D"), 1.0), (("C", "D"), 1.0)):
        gt, _ = build(line, [("A", "B"), ("B", "C")])
        pred, _ = build(with_d, [("A", "B"), ("B", "C"), extra])
        TALLY.near("test_spurious_edge_to_gt_interior_is_penalized: %s -> %s" % extra, jaccard_of(pred, gt, 5.0),
                   want)

    dividing = {"A": ORIGIN, "B": xyz(1, 0.0, 0.0, 0.0), "C": xyz(2, 0.0, 10.0, 0.0), "D": xyz(2, 0.0, -10.0, 0.0)}
    dividing_edges = [("A", "B"), ("B", "C"), ("B", "D")]
    gt, _ = build(dividing, dividing_edges)
    pred, _ = build(dividing, dividing_edges)
    TALLY.near("test_division_extra_child_dropped_and_missing_child_penalized: perfect", jaccard_of(pred, gt, 5.0),
               1.0)
    with_e = dict(dividing)
    with_e["E"] = xyz(2, 100.0, 100.0, 100.0)
    pred, _ = build(with_e, dividing_edges + [("B", "E")])
    TALLY.near("test_division_extra_child_dropped_and_missing_child_penalized: B -> E", jaccard_of(pred, gt, 5.0),
               1.0)
    pred, _ = build(dividing, [("A", "B"), ("B", "D")])
    TALLY.near("test_division_extra_child_dropped_and_missing_child_penalized: B -> C missing",
               jaccard_of(pred, gt, 5.0), 2 / 3)

    gt, _ = build(line, [("A", "B"), ("B", "C")])
    pred, _ = build({"A": xyz(0, 0.0, 9.0, 0.0), "Ap": xyz(0, 0.0, 10.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0),
                     "C": xyz(2, 0.0, 0.0, 0.0), "D": xyz(1, 0.0, 100.0, 0.0)},
                    [("A", "B"), ("B", "C"), ("Ap", "D")])
    TALLY.near("test_node_matching_prefers_closer_node: A nearer", jaccard_of(pred, gt, 15.0), 1.0)
    pred, _ = build({"A": xyz(0, 0.0, 10.0, 0.0), "Ap": xyz(0, 0.0, 9.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0),
                     "C": xyz(2, 0.0, 0.0, 0.0), "D": xyz(1, 0.0, 100.0, 0.0)},
                    [("A", "B"), ("B", "C"), ("Ap", "D")])
    TALLY.true("test_node_matching_prefers_closer_node: A' nearer, below 1", jaccard_of(pred, gt, 15.0) < 1.0)

    gt, _ = build({"g0": ORIGIN, "g1": xyz(1, 29.0, 5.0, 56.0), "g2": xyz(1, 36.0, 232.0, 74.0)},
                  [("g0", "g1"), ("g0", "g2")])
    background = {"p0": ORIGIN}
    for count in range(10):
        background["bg%d" % count] = xyz(1, 150.0 + count, 150.0, 150.0)
    background["p1"] = xyz(1, 36.0, 232.0, 74.0)
    pred, _ = build(background, [("p0", "p1")])
    result = evaluate(pred, gt)
    TALLY.true("test_unmatched_gt_node_does_not_corrupt_nearby_match", jaccard_of(pred, gt) >= 0.0)
    TALLY.held("test_unmatched_gt_node_does_not_corrupt_nearby_match: edge TP, FP, FN, by hand",
               (result["edge_tp"], result["edge_fp"], result["edge_fn"]), (1, 0, 1))

    tracks = {"A": ORIGIN, "B": xyz(1, 0.0, 0.0, 0.0), "C": xyz(2, 0.0, 0.0, 0.0), "D": xyz(0, 0.0, 50.0, 0.0),
              "E": xyz(1, 0.0, 50.0, 0.0), "F": xyz(2, 0.0, 50.0, 0.0)}
    tracks_edges = [("A", "B"), ("B", "C"), ("D", "E"), ("E", "F")]
    gt, _ = build(tracks, tracks_edges)
    pred, _ = build(tracks, tracks_edges + [("B", "E")])
    TALLY.near("test_cross_track_edge_penalized_only_when_forward: B -> E", jaccard_of(pred, gt, 1.0), 1.0)
    pred, _ = build(tracks, tracks_edges + [("B", "F")])
    TALLY.near("test_cross_track_edge_penalized_only_when_forward: B -> F", jaccard_of(pred, gt, 1.0), 4 / 5)

    gt, _ = build(line, [("A", "B"), ("B", "C")])
    pred, _ = build({"D": xyz(0, 100.0, 100.0, 100.0), "B": xyz(1, 0.0, 0.0, 0.0), "C": xyz(2, 0.0, 0.0, 0.0)},
                    [("D", "B"), ("B", "C")])
    TALLY.near("test_reparenting_node_penalized", jaccard_of(pred, gt, 1.0), 1 / 3)

    parted = {"A": ORIGIN, "B": xyz(1, 0.0, 10.0, 0.0), "C": xyz(1, 0.0, -10.0, 0.0)}
    gt, _ = build(parted, [("A", "B"), ("A", "C")])
    pred, _ = build(parted, [("A", "B")])
    TALLY.near("test_missing_division_child_penalized", jaccard_of(pred, gt, 1.0), 1 / 2)

    gt, _ = build(line, [("A", "B"), ("B", "C")])
    pred, _ = build(line, [("A", "B"), ("A", "B"), ("B", "C")])
    score = jaccard_of(pred, gt, 1.0)
    TALLY.true("test_duplicate_edges_cannot_inflate_score: at most 1", score <= 1.0)
    TALLY.near("test_duplicate_edges_cannot_inflate_score", score, 1.0)

    pair = {"A": ORIGIN, "B": xyz(1, 0.0, 0.0, 0.0)}
    gt, _ = build(pair, [("A", "B")])
    pred, _ = build(pair, [])
    TALLY.near("test_pred_no_edges_scores_zero", jaccard_of(pred, gt, 1.0), 0.0)
    pred, _ = build({}, [])
    TALLY.near("test_empty_pred_no_nodes_scores_zero", jaccard_of(pred, gt, 1.0), 0.0)

    colocated = {"A": ORIGIN, "B": ORIGIN, "C": xyz(1, 0.0, 0.0, 0.0), "D": xyz(1, 0.0, 50.0, 0.0)}
    gt, _ = build(colocated, [("A", "C"), ("B", "D")])
    pred, _ = build(colocated, [("A", "C"), ("B", "D")])
    score = jaccard_of(pred, gt, 1.0)
    TALLY.true("test_colocated_gt_nodes_ambiguous_matching: 0 or 1",
               abs(score - 0.0) <= 1e-12 or abs(score - 1.0) <= 1e-6)

    gt, _ = build(pair, [("A", "B")])
    pred, _ = build({"A": xyz(0, 0.0, 5.0, 0.0), "spoiler": xyz(0, 0.0, 1.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0)},
                    [("A", "B")])
    TALLY.near("test_spoiler_node_steals_match", jaccard_of(pred, gt), 0.0)

    five = {"N%d" % t: xyz(t, 0.0, 0.0, float(t)) for t in range(5)}
    five_edges = [("N%d" % t, "N%d" % (t + 1)) for t in range(4)]
    gt, _ = build(five, five_edges)
    pred, _ = build(five, five_edges + [("N1", "N1"), ("N2", "N2"), ("N3", "N3")])
    TALLY.near("test_self_loops_on_interior_nodes_dropped", jaccard_of(pred, gt, 1.0), 1.0)

    gt, _ = build(pair, [("A", "B")])
    pred, _ = build(pair, [("A", "B"), ("B", "A")])
    TALLY.near("test_reverse_edge_at_boundary_invisible", jaccard_of(pred, gt, 1.0), 1.0)

    lattice = {}
    for row in range(3):
        lattice["A%d" % row] = xyz(0, 0.0, float(row * 50), 0.0)
        lattice["B%d" % row] = xyz(1, 0.0, float(row * 50), 0.0)
    gt, _ = build(lattice, [("A%d" % row, "B%d" % row) for row in range(3)])
    pred, _ = build(lattice, [("A%d" % row, "B%d" % other) for row in range(3) for other in range(3)])
    TALLY.near("test_dense_bipartite_cross_edges_capped_by_id", jaccard_of(pred, gt, 1.0), 2 / 7)

    gt, _ = build(line, [("A", "B"), ("B", "C")])
    pred, _ = build(line, [("A", "C")])
    TALLY.near("test_skip_connection_scores_zero", jaccard_of(pred, gt, 1.0), 0.0)

    gt, _ = build(pair, [("A", "B")])
    pred, _ = build({"X": xyz(5, 0.0, 0.0, 0.0), "Y": xyz(6, 0.0, 0.0, 0.0)}, [("X", "Y")])
    TALLY.near("test_distance_matching_respects_timeframes", jaccard_of(pred, gt, 1.0), 0.0)

    noisy = dict(line)
    for count in range(100):
        noisy["noise_%d" % count] = xyz(count % 3, 500.0 + count, 500.0 + count, 500.0 + count)
    gt, _ = build(line, [("A", "B"), ("B", "C")])
    pred, _ = build(noisy, [("A", "B"), ("B", "C")] + [("noise_%d" % count, "noise_%d" % (count + 1))
                                                         for count in range(99)])
    TALLY.near("test_correct_track_with_many_unmatched_noise_edges", jaccard_of(pred, gt, 1.0), 1.0)

    hub = {"hub": ORIGIN}
    hub_edges = []
    for child in range(5):
        hub["C%d" % child] = xyz(1, 0.0, float(child * 20), 0.0)
        hub_edges.append(("hub", "C%d" % child))
    gt, _ = build(hub, hub_edges)
    hub_pred = dict(hub)
    for child in range(5):
        hub_pred["F%d" % child] = xyz(1, 100.0 + child, 100.0, 100.0)
    pred, _ = build(hub_pred, hub_edges + [("hub", "F%d" % child) for child in range(5)])
    TALLY.near("test_hub_out_degree_capped_at_two", jaccard_of(pred, gt, 1.0), 2 / 5)

    gt, _ = build(pair, [("A", "B")])
    pred, _ = build({"A": xyz(0, float("nan"), float("nan"), float("nan")), "B": xyz(1, 0.0, 0.0, 0.0)},
                    [("A", "B")])
    TALLY.near("test_nan_coordinates_no_match", jaccard_of(pred, gt), 0.0)
    pred, _ = build({"A": xyz(0, float("inf"), 0.0, 0.0), "B": xyz(1, 0.0, 0.0, 0.0)}, [("A", "B")])
    TALLY.near("test_inf_coordinates_no_match", jaccard_of(pred, gt), 0.0)

    same, _ = build(pair, [("A", "B")])
    TALLY.near("test_same_graph_object_as_pred_and_gt", jaccard_of(same, same, 1.0), 1.0)

    big = dict(pair)
    big["C"] = xyz(2, 0.0, 0.0, 0.0)
    TALLY.near("test_score_asymmetric_big_pred_vs_small_gt: big pred",
               jaccard_of(build(big, [("A", "B"), ("B", "C")])[0], build(pair, [("A", "B")])[0], 1.0), 1.0)
    TALLY.near("test_score_asymmetric_big_pred_vs_small_gt: small pred",
               jaccard_of(build(pair, [("A", "B")])[0], build(big, [("A", "B"), ("B", "C")])[0], 1.0), 0.5)

    gt, _ = build(line, [("A", "B"), ("B", "C")])
    pred, _ = build(with_d_at(line, 0), [("A", "B"), ("B", "C"), ("D", "B")])
    TALLY.near("test_false_merge_into_interior_penalized", jaccard_of(pred, gt, 1.0), 2 / 3)
    pred, _ = build(with_d_at(line, 0), [("A", "B"), ("B", "C"), ("D", "A")])
    TALLY.near("test_false_merge_into_track_start_invisible", jaccard_of(pred, gt, 1.0), 1.0)


def with_d_at(nodes, t):
    held = dict(nodes)
    held["D"] = xyz(t, 100.0, 100.0, 100.0)
    return held


def without(graph, nodes=(), edges=()):
    # graph less the nodes and edges named, and less the edges of the nodes named, the rest in their order
    nodes = set(nodes)
    edges = set(edges)
    kept = score_metric.Graph()
    index = {}
    for node, time in enumerate(graph.times):
        if node not in nodes:
            index[node] = kept.add_node(time, *graph.places[node])
    for edge, (source, target) in enumerate(zip(graph.sources, graph.targets)):
        if (edge not in edges) and (source in index) and (target in index):
            kept.add_edge(index[source], index[target])
    return kept.join()


def geff_cases():
    path = os.path.join(score_metric.KEYS, "6bba_c328f2fd.geff")
    if not os.path.isdir(path):
        TALLY.true("the training key %s is there" % path, False)
        return
    gt = score_metric.key_graph(truth_io.read(path))
    TALLY.near("test_evaluate_geff_against_itself_is_perfect",
               jaccard_of(score_metric.key_graph(truth_io.read(path)), gt, 1.0), 1.0)
    scores = [jaccard_of(without(gt, edges=range(count)), gt, 1.0) for count in (0, 1, 2, 3, 10, 50, 200)]
    TALLY.near("test_evaluate_geff_score_decreases_when_edges_removed: none removed", scores[0], 1.0)
    for step in (1, 2, 3):
        TALLY.true("test_evaluate_geff_score_decreases_when_edges_removed: %s below %s" % (scores[step],
                                                                                        scores[step - 1]),
                   scores[step] < scores[step - 1])
    scores = [jaccard_of(without(gt, nodes=range(count)), gt, 1.0) for count in (0, 10, 50, 150)]
    TALLY.near("test_evaluate_geff_score_decreases_when_nodes_removed: none removed", scores[0], 1.0)
    for step in (1, 2, 3):
        TALLY.true("test_evaluate_geff_score_decreases_when_nodes_removed: %s below %s" % (scores[step],
                                                                                        scores[step - 1]),
                   scores[step] < scores[step - 1])


def summarize_cases():
    def row(tp, fp, fn, nodes, n_total, recall):
        return score_metric.per_sample_metrics(
            {"edge_tp": tp, "edge_fp": fp, "edge_fn": fn, "division_tp": 0, "division_fp": 0, "division_fn": 0,
             "num_pred_nodes": nodes, "node_recall": recall}, n_total)

    summary = score_metric.summarize([row(5, 0, 0, 10, 10, 1.0), row(3, 1, 2, 8, 8, 0.8)])
    TALLY.true("test_summarize_no_divisions_warns_and_drops_term: division jaccard NaN",
               math.isnan(summary["division_jaccard"]))
    TALLY.true("test_summarize_no_divisions_warns_and_drops_term: score finite", math.isfinite(summary["score"]))
    TALLY.near("test_summarize_no_divisions_warns_and_drops_term: score is the adjusted", summary["score"],
               summary["adj_edge_jaccard"])
    # by hand: J 1 and 3/6, no node over, weighed 5 and 6
    TALLY.near("summarize: the adjusted weighed by TP + FP + FN, by hand", summary["adj_edge_jaccard"], 8 / 11)
    TALLY.near("summarize: the edge jaccard over the summed counts, by hand", summary["edge_jaccard"], 8 / 11)
    # by hand: 20 nodes against 10 is a ratio of 1. J 1/2 is adjusted to 1/2 * 0.9
    TALLY.near("per_sample_metrics: the node ratio, by hand", row(1, 0, 1, 20, 10, 1.0)["adj_edge_jaccard"], 0.45)
    TALLY.near("per_sample_metrics: never below 0, by hand", row(1, 0, 1, 200, 10, 1.0)["adj_edge_jaccard"], 0.0)
    TALLY.true("per_sample_metrics: no n_total is NaN, by hand",
               math.isnan(row(1, 0, 1, 20, float("nan"), 1.0)["adj_edge_jaccard"]))
    divided = row(1, 0, 1, 10, 10, 1.0)
    divided.update({"division_tp": 1, "division_fp": 1, "division_fn": 0})
    summary = score_metric.summarize([divided])
    TALLY.near("summarize: the division term, by hand", summary["score"], 0.5 + 0.1 * 0.5)


def csv_cases():
    text = "\n".join([
        "id,dataset,row_type,node_id,t,z,y,x,source_id,target_id",
        "0,b,edge,-1,-1,-1,-1,-1,7,9",
        "1,a,node,5,0,0,0,0,-1,-1",
        "2,b,node,9,1,1.5,2,3,-1,-1",
        "3,a,node,6,1,0,0,1,-1,-1",
        "4,b,node,7,0,0,0,0,-1,-1",
        "5,a,edge,-1,-1,-1,-1,-1,5,6",
        "6,a,node,8,1,0,0,2,-1,-1",
        "7,a,edge,-1,-1,-1,-1,-1,5,8",
        "",
    ])
    graphs = score_metric.read_submission(io.StringIO(text))
    TALLY.held("the CSV: its datasets", sorted(graphs), ["a", "b"])
    TALLY.held("the CSV: a's nodes in row order", (graphs["a"].times, graphs["a"].places),
               ([0, 1, 1], [(0.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 0.0, 2.0)]))
    TALLY.held("the CSV: a's edges in row order, as its node ids name them", list(zip(graphs["a"].sources,
                                                                                    graphs["a"].targets)),
               [(0, 1), (0, 2)])
    TALLY.held("the CSV: a's frame 1 in row order", graphs["a"].by_time[1], [1, 2])
    TALLY.held("the CSV: b's nodes, and its edge row ahead of them", (graphs["b"].times, graphs["b"].places,
                                                                      list(zip(graphs["b"].sources,
                                                                               graphs["b"].targets))),
               ([1, 0], [(1.5, 2.0, 3.0), (0.0, 0.0, 0.0)], [(1, 0)]))
    try:
        score_metric.read_submission(io.StringIO(text + "8,a,edge,-1,-1,-1,-1,-1,5,99\n"))
        error = False
    except ValueError:
        error = True
    TALLY.held("the CSV: an edge naming no node errors", error, True)


def main():
    sandbox_cases()
    extract_divisions_cases()
    strongly_connected_cases()
    score_divisions_cases()
    count_matched_cases()
    evaluate_divisions_cases()
    make_graph_cases()
    matching_cases()
    edge_rule_cases()
    geff_cases()
    summarize_cases()
    csv_cases()
    print("  score_metric test: %d checks, %d failed" % (TALLY.checks, TALLY.failures))
    return 1 if TALLY.failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
