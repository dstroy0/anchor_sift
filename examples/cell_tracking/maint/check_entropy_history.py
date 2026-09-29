import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zarr_frames

WINDOW = 11
BITS = 16


def main():
    source = sys.argv[1]
    set_directory = sys.argv[2]
    sample = sys.argv[3]
    checked = int(sys.argv[4]) if len(sys.argv) > 4 else 2000
    history_path = os.path.join(set_directory, sample, sample + ".oapx")
    with open(history_path, "rb") as history:
        head = history.read(16)
        assert head[:8] == b"APXREP\0\0" and head[8:12] == b"OAPX", "not an OAPX apxrep"
        extent = struct.unpack("<4Q", history.read(32))
        window, windows, _payload_crc, _cloud_crc = struct.unpack("<4Q", history.read(32))
        _sample_root = history.read(32)
        payload_at = history.tell() + 8 * windows * windows
    assert window == WINDOW
    frames, depth, height, width = extent
    voxels = depth * height * width
    reader = zarr_frames.Frames(source, sample)
    assert list(extent) == reader.shape, "the history's extent is not the source's shape"
    chosen = sorted((index * 2654435761) % voxels for index in range(checked))
    values = {voxel: [] for voxel in chosen}
    for frame in range(frames):
        for voxel in chosen:
            values[voxel].append(reader.voxel(frame, voxel))
    differ = 0
    with open(history_path, "rb") as history:
        for voxel in chosen:
            for index in range(windows):
                first = index * WINDOW + 1
                last = min(first + WINDOW - 1, frames - 1)
                counts = [0] * BITS
                for frame in range(first, last + 1):
                    flipped = values[voxel][frame] ^ values[voxel][frame - 1]
                    for bit in range(BITS):
                        counts[bit] += (flipped >> bit) & 1
                expected = 0
                for bit in range(BITS):
                    expected |= counts[bit] << (4 * bit)
                history.seek(payload_at + 8 * (index * voxels + voxel))
                held = struct.unpack("<Q", history.read(8))[0]
                differ += (held != expected)
    print("  %s: %d voxels x %d windows checked by hand against the source: %d words differ"
          % (sample, checked, windows, differ))
    return 0 if differ == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
