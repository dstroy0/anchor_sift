#!/usr/bin/env python3
"""Fetches the open sample the examples run on and lays it out as a source.

The sample is a mouse intestinal organoid imaged by light-sheet over time, H2B nuclei on channel 1 and the mem9
membrane on channel 0, from "Reference OME-Zarr for 3D time-lapse light-sheet microscopy with nuclei tracking"
(Hess, Caton, Kothari, Swedlow, Liberali, Quintas Glasner de Medeiros), doi:10.5281/zenodo.22078388, under
CC BY 4.0. The archive is checked against the record's MD5, and its raw OME-Zarr is unpacked as
<source>/<sample>.ome.zarr, where ingest and serve_room.py find it.

The record's nucleus tracks become the answer key at <source>/<sample>.geff: the same node and edge ids, t the frame
index, and z y x in voxels of the image, each place in micrometers divided by the image's scale on that axis and
rounded half up. They are written as int64 arrays under the bytes codec alone.
"""

import argparse
import hashlib
import json
import os
import shutil
import struct
import sys
import urllib.request
import zipfile

from compression import zstd

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
RECORD = "https://zenodo.org/api/records/22078388/files/%s/content"
CUTS = {
    "mini": ("001-mini.zip", "068f5bb5434831401d672a20e4dfc143", 242435464),
    "mini-lowT": ("001-mini-lowT.zip", "e5370b25835296b8d25296e072da3b6f", 265749546),
    "mini-varT": ("001-mini-varT.zip", "758da8d915bb3d2e30f2699a4c1849ba", 239123614),
    "small": ("001-small.zip", "476fac87c617089bcb874e58d972ca99", 2394240964),
}


def digest(path):
    hashed = hashlib.md5()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 22), b""):
            hashed.update(block)
    return hashed.hexdigest()


def fetch(name, wanted, size, folder):
    path = os.path.join(folder, name)
    if os.path.isfile(path) and os.path.getsize(path) == size and digest(path) == wanted:
        print("  %s is here and holds" % path)
        return path
    print("  fetching %s, %d bytes" % (RECORD % name, size), flush=True)
    partial = path + ".part"
    with urllib.request.urlopen(RECORD % name) as response, open(partial, "wb") as out:
        shutil.copyfileobj(response, out, 1 << 22)
    if digest(partial) != wanted:
        os.remove(partial)
        raise SystemExit("  %s does not match the record's MD5 %s" % (name, wanted))
    os.replace(partial, path)
    return path


def unpack(archive, image, into):
    stem = None
    with zipfile.ZipFile(archive) as packed:
        for entry in packed.infolist():
            parts = entry.filename.split("/")
            if len(parts) < 3 or parts[1] != image or entry.is_dir():
                continue
            stem = parts[0]
            target = os.path.join(into, *parts[2:])
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with packed.open(entry) as source, open(target, "wb") as out:
                shutil.copyfileobj(source, out, 1 << 22)
    if stem is None:
        raise SystemExit("  %s holds no %s" % (archive, image))
    return stem


def array_of(packed, root):
    """A zarr v3 array of one chunk under bytes and zstd, as a list of its elements in C order."""
    meta = json.loads(packed.read(root + "/zarr.json"))
    codecs = [codec["name"] for codec in meta["codecs"]]
    if meta["chunk_grid"]["configuration"]["chunk_shape"] != meta["shape"] or codecs not in (["bytes"], ["bytes", "zstd"]):
        raise SystemExit("  %s: one chunk under bytes or bytes and zstd is read here, not %s" % (root, codecs))
    chunk = packed.read(root + "/c/" + "/".join("0" * len(meta["shape"])))
    data = zstd.decompress(chunk) if codecs[-1] == "zstd" else chunk
    defined = {"uint64": "Q", "int64": "q", "float64": "d"}[meta["data_type"]]
    return list(struct.unpack("<%d%s" % (len(data) // 8, defined), data)), meta["shape"]


def array_write(root, shape, values, kind):
    os.makedirs(os.path.join(root, "c"), exist_ok=True)
    meta = {"zarr_format": 3, "node_type": "array", "shape": shape, "data_type": {"q": "int64", "Q": "uint64"}[kind],
            "chunk_grid": {"name": "regular", "configuration": {"chunk_shape": shape}},
            "chunk_key_encoding": {"name": "default", "configuration": {"separator": "/"}}, "fill_value": 0,
            "codecs": [{"name": "bytes", "configuration": {"endian": "little"}}]}
    with open(os.path.join(root, "zarr.json"), "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2)
    chunk = os.path.join(root, "c", *("0" * len(shape)))
    os.makedirs(os.path.dirname(chunk), exist_ok=True)
    with open(chunk, "wb") as handle:
        handle.write(struct.pack("<%d%s" % (len(values), kind), *values))


def answer_key(archive, stem, image, into):
    with zipfile.ZipFile(archive) as packed:
        group = json.loads(packed.read("%s/%s/zarr.json" % (stem, image)))["attributes"]["ome"]["multiscales"][0]
        names = [axis["name"] for axis in group["axes"]]
        scale = group["datasets"][0]["coordinateTransformations"][0]["scale"]
        tracks = "%s/deconv.ome.zarr/tracks/nucleus.geff" % stem
        ids, shape = array_of(packed, tracks + "/nodes/ids")
        edges, edge_shape = array_of(packed, tracks + "/edges/ids")
        places = {"t": array_of(packed, tracks + "/nodes/props/t_idx/values")[0]}
        for axis in "zyx":
            step = scale[names.index(axis)]
            places[axis] = [int(value / step + 0.5) for value in array_of(packed, tracks + "/nodes/props/%s/values" % axis)[0]]
    if os.path.isdir(into):
        shutil.rmtree(into)
    os.makedirs(into)
    with open(os.path.join(into, "zarr.json"), "w", encoding="utf-8") as handle:
        json.dump({"zarr_format": 3, "node_type": "group", "attributes": {"geff": {
            "geff_version": "1.2", "directed": True,
            "axes": [{"name": "t", "type": "time", "unit": "frame"}] +
                    [{"name": axis, "type": "space", "unit": "voxel"} for axis in "zyx"]}}}, handle, indent=2)
    array_write(os.path.join(into, "nodes", "ids"), shape, ids, "Q")
    for axis in "tzyx":
        array_write(os.path.join(into, "nodes", "props", axis, "values"), shape, places[axis], "q")
    array_write(os.path.join(into, "edges", "ids"), edge_shape, edges, "Q")
    return shape[0], edge_shape[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--cut", choices=sorted(CUTS), default="mini",
                        help="which cut of the record: mini is 5 frames, the lowT and varT cuts sample time "
                             "differently, small is 2.4 GB. Default: mini")
    parser.add_argument("--image", choices=["raw.ome.zarr", "deconv.ome.zarr"], default="raw.ome.zarr")
    parser.add_argument("--source", default=os.path.join(REPO, "build", "data", "source"),
                        help="the source folder the sample is unpacked into. Default: build/data/source")
    parser.add_argument("--sample", default="organoid_001",
                        help="the sample's name in the source. Default: organoid_001")
    args = parser.parse_args()
    name, wanted, size = CUTS[args.cut]
    archive = fetch(name, wanted, size, os.path.dirname(os.path.abspath(args.source)))
    into = os.path.join(args.source, args.sample + ".ome.zarr")
    if os.path.isdir(into):
        shutil.rmtree(into)
    stem = unpack(archive, args.image, into)
    print("  %s from %s %s" % (into, name, args.image))
    key = os.path.join(args.source, args.sample + ".geff")
    nodes, edges = answer_key(archive, stem, args.image, key)
    print("  %s: %d nodes, %d edges" % (key, nodes, edges))
    return 0


if __name__ == "__main__":
    sys.exit(main())
