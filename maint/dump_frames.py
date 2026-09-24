#!/usr/bin/env python3

import argparse
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "src"))


def main():
    parser = argparse.ArgumentParser(description="Dump samples to flat files for the native driver.")
    parser.add_argument("--root", default=ROOT)
    parser.add_argument("--split", default="train")
    parser.add_argument("--sample")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--frames", type=int, default=40)
    parser.add_argument("--out", default=os.path.join(os.path.dirname(ROOT), "cache", "stacks"))
    args = parser.parse_args()

    import exact_track as exact

    os.makedirs(args.out, exist_ok=True)
    for name in exact.sample_names(args, need_truth=True):
        stack_path = os.path.join(args.out, name + ".stack")
        truth_path = os.path.join(args.out, name + ".truth")
        volume = exact.open_frames(args.root, args.split, name)
        depth, height, width = (int(value) for value in volume.shape[1:])
        count = min(args.frames, int(volume.shape[0]))
        header = struct.pack("<5I", count, depth, height, width, 0)
        expected = len(header) + count * depth * height * width * 2
        if not (os.path.isfile(stack_path) and os.path.getsize(stack_path) == expected):
            with open(stack_path + ".part", "wb") as handle:
                handle.write(header)
                for frame in range(count):
                    handle.write(exact.frame_bytes(volume, frame))
            os.replace(stack_path + ".part", stack_path)
        nodes, edges = exact.read_truth(args.root, args.split, name)
        with open(truth_path + ".part", "wb") as handle:
            handle.write(struct.pack("<2I", len(nodes), len(edges)))
            for node in sorted(nodes):
                time, (z, y, x) = nodes[node]
                handle.write(struct.pack("<q4i", node, time, z, y, x))
            for source, target in edges:
                handle.write(struct.pack("<2q", source, target))
        os.replace(truth_path + ".part", truth_path)
        print("  %s: %d frames of %dx%dx%d, %d nodes, %d edges" % (name, count, depth, height, width,
                                                                   len(nodes), len(edges)), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
