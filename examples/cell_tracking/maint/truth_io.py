import json
import os
import struct
import sys

from compression import zstd


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


SPELLINGS = {"uint64": "Q", "int64": "q"}


def read_array(root):
    with open(os.path.join(root, "zarr.json"), "r", encoding="utf-8") as handle:
        meta = json.load(handle)
    shape = meta["shape"]
    chunk = meta["chunk_grid"]["configuration"]["chunk_shape"]
    names = [codec["name"] for codec in meta["codecs"]]
    little = meta["codecs"][0]["configuration"]["endian"] == "little"
    spelled = SPELLINGS.get(meta["data_type"])
    if (spelled is None) or (names not in (["bytes"], ["bytes", "zstd"])) or (shape[1:] != chunk[1:]):
        raise ValueError("%s: an array this reader does not take: %s, codecs %s, chunks %s over %s"
                         % (root, meta["data_type"], names, chunk, shape))
    separator = meta["chunk_key_encoding"]["configuration"]["separator"]
    width = 1
    for extent in shape[1:]:
        width *= extent
    rows = []
    for first in range(0, shape[0], chunk[0]):
        key = separator.join(["c", str(first // chunk[0])] + ["0"] * (len(shape) - 1))
        path = os.path.join(root, *key.split("/"))
        if not os.path.exists(path):
            rows.extend([meta["fill_value"]] * (min(chunk[0], shape[0] - first) * width))
            continue
        with open(path, "rb") as handle:
            raw = handle.read()
        if "zstd" in names:
            raw = zstd.decompress(raw)
        values = struct.unpack(("<" if little else ">") + spelled * (chunk[0] * width), raw)
        rows.extend(values[:min(chunk[0], shape[0] - first) * width])
    return rows, width


def read(path):
    identities, _ = read_array(os.path.join(path, "nodes", "ids"))
    places = [read_array(os.path.join(path, "nodes", "props", axis, "values"))[0] for axis in "tzyx"]
    nodes = {}
    for at, identity in enumerate(identities):
        nodes[identity] = tuple(places[axis][at] for axis in range(4))
    ends, width = read_array(os.path.join(path, "edges", "ids"))
    if width != 2:
        raise ValueError("%s: edges are not pairs" % path)
    edges = [(ends[at], ends[at + 1]) for at in range(0, len(ends), 2)]
    return Truth(nodes, edges)


def every(directory):
    held = []
    for name in sorted(os.listdir(directory)):
        if name.endswith(".geff"):
            held.append(name[:-len(".geff")])
    return held


def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else "D:/kaggle_project_data/biohub_cell_tracking_data/train"
    first = int(sys.argv[2]) if len(sys.argv) > 2 else 25
    names = every(directory)[:first]
    print("  %-24s %8s %8s %8s %10s %10s" % ("sample", "nodes", "edges", "frames", "nodes/frame", "divisions"))
    total_nodes = 0
    total_edges = 0
    total_divisions = 0
    for name in names:
        truth = read(os.path.join(directory, name + ".geff"))
        frames = len(truth.times)
        divisions = len(truth.divisions())
        total_nodes += len(truth.nodes)
        total_edges += len(truth.edges)
        total_divisions += divisions
        print("  %-24s %8d %8d %8d %10d %10d"
              % (name, len(truth.nodes), len(truth.edges), frames,
                 len(truth.nodes) // max(frames, 1), divisions))
    print("  %-24s %8d %8d %8s %10s %10d" % ("TOTAL", total_nodes, total_edges, "", "", total_divisions))


if __name__ == "__main__":
    raise SystemExit(main())
