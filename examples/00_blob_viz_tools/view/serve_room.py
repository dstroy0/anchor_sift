#!/usr/bin/env python3

import argparse
import http.server
import json
import os
import re
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLE_NAME = re.compile(r"^[A-Za-z0-9_]+$")

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "maint"))
import zarr_frames


def main():
    parser = argparse.ArgumentParser(description="Serve the room view and raw slices from the source on localhost.")
    parser.add_argument("--port", type=int, default=8733)
    parser.add_argument("--source", default="D:/kaggle_project_data/biohub_cell_tracking_data/train")
    args = parser.parse_args()
    source = os.path.abspath(args.source)
    readers = {}

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *handler_args, **handler_kwargs):
            super().__init__(*handler_args, directory=HERE, **handler_kwargs)

        def log_message(self, *_):
            return

        def reply(self, code, body, kind):
            self.send_response(code)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path == "/samples":
                names = sorted(entry[:-4] for entry in os.listdir(os.path.join(HERE, "data")) if entry.endswith(".smp"))
                self.reply(200, json.dumps(names).encode("utf-8"), "application/json")
                return
            if parsed.path == "/objects":
                names = sorted(entry[:-4] for entry in os.listdir(os.path.join(HERE, "data")) if entry.endswith(".vbo"))
                self.reply(200, json.dumps(names).encode("utf-8"), "application/json")
                return
            if parsed.path not in ("/slice", "/frame"):
                super().do_GET()
                return
            whole_frame = parsed.path == "/frame"
            query = urllib.parse.parse_qs(parsed.query)
            try:
                sample = query["sample"][0]
                time = int(query["t"][0])
                slice_z = 0 if whole_frame else int(query["z"][0])
            except (KeyError, ValueError):
                self.reply(400, b"sample and t are required, and z for a slice", "text/plain")
                return
            if not SAMPLE_NAME.match(sample):
                self.reply(400, b"bad sample name", "text/plain")
                return
            if not os.path.isdir(os.path.join(source, sample + ".zarr")):
                self.reply(404, b"no such sample in the source", "text/plain")
                return
            try:
                reader = readers.setdefault(sample, zarr_frames.Frames(source, sample))
            except (OSError, ValueError) as refused:
                self.reply(415, str(refused).encode("utf-8"), "text/plain")
                return
            frames, depth, height, width = reader.shape
            if not (0 <= time < frames and 0 <= slice_z < depth):
                self.reply(400, b"t or z outside the sample", "text/plain")
                return
            plane = height * width
            whole = reader.frame_bytes(time)
            body = whole if whole_frame else whole[2 * slice_z * plane:2 * (slice_z + 1) * plane]
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-Depth", str(depth if whole_frame else 1))
            self.send_header("X-Height", str(height))
            self.send_header("X-Width", str(width))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("  room view at http://127.0.0.1:%d/track_room.html, slices from %s" % (args.port, source), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
