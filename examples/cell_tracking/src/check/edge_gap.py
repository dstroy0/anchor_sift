# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The key-edge gap, edge by edge: for each edge of one sample's key, how far each end lies from the nearest predicted
# node in its frame, and whether the nearest node to the edge's start links on to the nearest node to its end. Then the
# scorer's own count on the same sample. Distances are in um, with the scorer's SCALE; "within" is the scorer's
# REACH_UM, as its match takes it (apart <= REACH_UM). The key's nodes and edges are read through truth_io alone.
#
#   edge_gap.py <nodes.tsv> <keys> <sample>
#
# <nodes.tsv> is a nodes file the driver wrote; only <sample>'s rows are used. <keys> is the folder of the .geff keys.
# It writes nothing.
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "maint"))
import score_submission
import truth_io


def apart(place, key_place):
    return math.sqrt(sum((score_submission.SCALE[axis] * (place[axis] - key_place[axis])) ** 2 for axis in range(3)))


# the predicted node nearest the key place in its frame, and how far it lies, or (None, inf) on a frame with none
def nearest(frame, key_place):
    best = None
    best_apart = math.inf
    for node in frame:
        distance = apart(node["place"], key_place)
        if distance < best_apart:
            best = node
            best_apart = distance
    return best, best_apart


def main():
    if len(sys.argv) != 4:
        print("  usage: edge_gap.py <nodes.tsv> <keys> <sample>")
        return 2
    nodes_path, keys, sample = sys.argv[1:4]
    held = score_submission.read_nodes(nodes_path)
    if sample not in held:
        print("  %s holds no rows of %s" % (nodes_path, sample))
        return 1
    frames = held[sample]
    truth = truth_io.read(os.path.join(keys, sample + ".geff"))
    reach = score_submission.REACH_UM
    print("  %s: %d predicted nodes over %d frames; the key %d nodes, %d edges; SCALE %s um, within means <= %.1f um"
          % (sample, sum(len(one) for one in frames.values()), len(frames), len(truth.nodes), len(truth.edges),
             score_submission.SCALE, reach))
    print("  %-10s %-10s %5s %10s %10s %8s %8s %8s %s" % ("key a", "key b", "t", "a apart", "b apart", "near a",
                                                        "forward", "near b", "near a links to near b"))
    distances = []
    carried = 0
    # of the edges not carried: the start's nearest node links to nothing, links elsewhere, or there is no node
    unlinked = 0
    elsewhere = 0
    nodeless = 0
    for a, b in sorted(truth.edges, key=lambda edge: (truth.nodes[edge[0]][0], edge)):
        time_a, *place_a = truth.nodes[a]
        time_b, *place_b = truth.nodes[b]
        near_a, apart_a = nearest(frames.get(time_a, []), place_a)
        near_b, apart_b = nearest(frames.get(time_b, []), place_b)
        distances.extend((apart_a, apart_b))
        links = (near_a is not None) and (near_b is not None) and (near_a["forward"] == near_b["leaf"])
        carried += 1 if links else 0
        if not links:
            if (near_a is None) or (near_b is None):
                nodeless += 1
            elif near_a["forward"] < 0:
                unlinked += 1
            else:
                elsewhere += 1
        print("  %-10d %-10d %5d %10.3f %10.3f %8s %8s %8s %s"
              % (a, b, time_a, apart_a, apart_b, near_a["leaf"] if near_a else "-",
                 near_a["forward"] if near_a else "-", near_b["leaf"] if near_b else "-", "yes" if links else "no"))
    within = [one for one in distances if one <= reach]
    rest = [one for one in distances if one > reach]
    print("  %d of %d key-edge ends have a predicted node within %.1f um" % (len(within), len(distances), reach))
    if rest:
        print("  the other %d lie %.3f to %.3f um from the nearest" % (len(rest), min(rest), max(rest)))
    print("  on %d of %d key edges the node nearest the start links on to the node nearest the end"
          % (carried, len(truth.edges)))
    print("  on the other %d it links to no node on %d and to another node on %d; on %d a frame holds no node"
          % (len(truth.edges) - carried, unlinked, elsewhere, nodeless))
    print("  the scorer on %s alone, every node kept:" % sample)
    score_submission.score({sample: frames}, keys, score_submission.policy_all, names=[sample])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
