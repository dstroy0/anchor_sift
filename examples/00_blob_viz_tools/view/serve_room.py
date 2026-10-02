#!/usr/bin/env python3

import argparse
import http.server
import json
import os
import re
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SAMPLE_NAME = re.compile(r"^[A-Za-z0-9_]+$")
DATA_FILE = re.compile(r"^/data/([A-Za-z0-9_]+\.(?:vbo|ibo|smp))$")

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), "cell_tracking", "maint"))
import zarr_frames


def main():
    parser = argparse.ArgumentParser(description="Serve the room view, the engine view's objects and raw slices from the source on localhost.")
    parser.add_argument("--port", type=int, default=8733)
    parser.add_argument("--source", default=os.path.join(REPO, "build", "data", "source"),
                        help="the samples the slices are read from, as fetch_open_sample.py lays them out. "
                             "Default: build/data/source")
    parser.add_argument("--channel", type=int, default=1,
                        help="the channel a sample with a c axis is read at. Default: 1, the open sample's nuclei")
    parser.add_argument("--data", default=os.path.join(REPO, "build", "view", "data"),
                        help="the tracker's .vbo and .ibo objects and the .smp samples, served at data/. "
                             "Default: build/view/data")
    args = parser.parse_args()
    source = os.path.abspath(args.source)
    data = os.path.abspath(args.data)

    def listed(suffix):
        if not os.path.isdir(data):
            return []
        return sorted(entry[:-len(suffix)] for entry in os.listdir(data) if entry.endswith(suffix))
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
                self.reply(200, json.dumps(listed(".smp")).encode("utf-8"), "application/json")
                return
            if parsed.path == "/objects":
                self.reply(200, json.dumps(listed(".vbo")).encode("utf-8"), "application/json")
                return
            named = DATA_FILE.match(parsed.path)
            if named:
                path = os.path.join(data, named.group(1))
                if not os.path.isfile(path):
                    self.reply(404, b"no such file in the data folder", "text/plain")
                    return
                with open(path, "rb") as handle:
                    self.reply(200, handle.read(), "application/octet-stream")
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
            if zarr_frames.sample_root(source, sample) is None:
                self.reply(404, b"no such sample in the source", "text/plain")
                return
            try:
                reader = readers.get(sample) or readers.setdefault(sample, zarr_frames.Frames(source, sample,
                                                                                               args.channel))
            except (OSError, ValueError) as error:
                self.reply(415, str(error).encode("utf-8"), "text/plain")
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
    print("  room view at http://127.0.0.1:%d/track_room.html, engine view at /engine_view.html, objects from %s, "
          "slices from %s" % (args.port, data, source), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
