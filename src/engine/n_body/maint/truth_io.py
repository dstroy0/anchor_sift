import os
import struct

class Truth(object):

    def __init__(self, nodes, edges):
        self.nodes = nodes
        self.edges = edges

    @property
    def times(self):
        return sorted({place[0] for place in self.nodes.values()})

    def by_time(self):
        held = {}
        for identity, place in self.nodes.items():
            held.setdefault(place[0], []).append(identity)
        return held

    def successors(self):
        held = {}
        for source, target in self.edges:
            held.setdefault(source, []).append(target)
        return held

    def divisions(self):
        return {parent: frozenset(children)
                for parent, children in self.successors().items() if len(children) > 1}

def read(path):
    with open(path, "rb") as handle:
        raw = handle.read()
    node_count, edge_count = struct.unpack_from("<II", raw, 0)
    at = 8
    nodes = {}
    for _ in range(node_count):
        identity, time, z, y, x = struct.unpack_from("<qiiii", raw, at)
        at += 8 + 16
        nodes[identity] = (time, z, y, x)
    edges = []
    for _ in range(edge_count):
        source, target = struct.unpack_from("<qq", raw, at)
        at += 16
        edges.append((source, target))
    return Truth(nodes, edges)

def every(directory):
    held = []
    for name in sorted(os.listdir(directory)):
        if name.endswith(".truth"):
            held.append(name[:-len(".truth")])
    return held

def main():
    import sys
    directory = sys.argv[1] if len(sys.argv) > 1 else "D:/kaggle_project_data/cache/stacks"
    first = int(sys.argv[2]) if len(sys.argv) > 2 else 25
    names = every(directory)[:first]
    print("  %-24s %8s %8s %8s %10s %10s" % ("sample", "nodes", "edges", "frames", "nodes/frame", "divisions"))
    total_nodes = 0
    total_edges = 0
    total_divisions = 0
    for name in names:
        truth = read(os.path.join(directory, name + ".truth"))
        frames = len(truth.times)
        divisions = len(truth.divisions())
        total_nodes += len(truth.nodes)
        total_edges += len(truth.edges)
        total_divisions += divisions
        print("  %-24s %8d %8d %8d %10.1f %10d"
              % (name, len(truth.nodes), len(truth.edges), frames,
                 len(truth.nodes) / max(frames, 1), divisions))
    print("  %-24s %8d %8d %8s %10s %10d" % ("TOTAL", total_nodes, total_edges, "", "", total_divisions))

if __name__ == "__main__":
    raise SystemExit(main())
