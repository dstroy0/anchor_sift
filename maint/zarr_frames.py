import json
import os
import struct

from compression import zstd

BLOSC_HEADER = 16
SPREAD = [bytes((value >> place) & 1 for place in range(8)) for value in range(256)]


def unshuffle_bits(data, elements, typesize):
    rows = elements // 8
    out = bytearray(elements * typesize)
    for lane in range(typesize):
        gathered = 0
        for bit in range(8):
            row = data[(lane * 8 + bit) * rows:(lane * 8 + bit + 1) * rows]
            gathered |= int.from_bytes(b"".join(SPREAD[value] for value in row), "little") << bit
        out[lane::typesize] = gathered.to_bytes(elements, "little")
    return bytes(out)


class Frames(object):

    def __init__(self, source, sample):
        self.root = os.path.join(source, sample + ".zarr", "0")
        with open(os.path.join(self.root, "zarr.json"), "r", encoding="utf-8") as handle:
            meta = json.load(handle)
        names = [codec["name"] for codec in meta["codecs"]]
        if (meta["data_type"] != "uint16") or (names != ["bytes", "blosc"]):
            raise ValueError("%s: this reader takes uint16 under bytes and blosc only, not %s %s"
                             % (self.root, meta["data_type"], names))
        if meta["chunk_grid"]["configuration"]["chunk_shape"] != [1] + meta["shape"][1:]:
            raise ValueError("%s: this reader takes one chunk a frame" % self.root)
        self.shape = meta["shape"]
        self.held = None
        self.frame = None

    def frame_bytes(self, frame):
        if frame == self.held:
            return self.frame
        key = os.path.join(self.root, "c", str(frame), *(["0"] * (len(self.shape) - 1)))
        with open(key, "rb") as handle:
            chunk = handle.read()
        version, flags, typesize = chunk[0], chunk[2], chunk[3]
        total, block_bytes, compressed = struct.unpack_from("<3I", chunk, 4)
        if (version != 2) or (compressed != len(chunk)) or ((flags >> 5) != 4) or ((flags & 0x10) == 0) \
                or ((flags & 0x01) != 0):
            raise ValueError("frame %d: a blosc chunk this reader does not take, flags %#x" % (frame, flags))
        if (flags & 0x02) != 0:
            out = chunk[BLOSC_HEADER:BLOSC_HEADER + total]
        else:
            pieces = []
            for index in range((total + block_bytes - 1) // block_bytes):
                start = struct.unpack_from("<I", chunk, BLOSC_HEADER + 4 * index)[0]
                size = min(block_bytes, total - index * block_bytes)
                packed = struct.unpack_from("<I", chunk, start)[0]
                raw = chunk[start + 4:start + 4 + packed]
                data = raw if packed == size else zstd.decompress(raw)
                elements = size // typesize
                if ((flags & 0x04) != 0) and (size >= typesize) and (elements % 8 == 0):
                    whole = elements * typesize
                    data = unshuffle_bits(data, elements, typesize) + data[whole:size]
                pieces.append(data)
            out = b"".join(pieces)
        if len(out) != 2 * self.shape[1] * self.shape[2] * self.shape[3]:
            raise ValueError("frame %d: %d bytes, not one frame" % (frame, len(out)))
        self.held = frame
        self.frame = out
        return out

    def voxel(self, frame, voxel):
        return struct.unpack_from("<H", self.frame_bytes(frame), 2 * voxel)[0]
