import argparse
import html
import os
import re
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

STEPS = [
    ("read", "Read a frame", "one frame's voxels come off disk, as the integers the microscope wrote", "frame"),
    ("basins", "Find the cells", "each voxel is smoothed twice and the difference kept exactly, then every voxel"
                                 " steps uphill until it stops: one basin per resting place", "frame"),
    ("store", "Keep it as runs", "each basin becomes the stretches of voxels it holds along each row, and the"
                                 " frame is those runs: about 27 times smaller than the labelled volume", "frame"),
    ("motion", "Find the drift", "the whole view's shift between two frames, the same count taken at every shift"
                                 " at once", "pair"),
    ("overlap", "Meet the neighbours", "the positive voxels two frames share, basin by basin, at that shift", "pair"),
    ("climb", "Let each cell find its own shift", "every cell walks from the view's shift to the shift where it"
                                                  " agrees best with the next frame; each walk stops on its own", "pair"),
    ("tree", "Link and score", "the strongest partner each way makes a link, divisions are kept as branches, and"
                               " the links are scored against the answer key", "pair"),
]

NEVER = [
    ("It is not trained", "there is no model and no learned parameter in the binary: nothing was fitted to this"
                          " competition's data or to any other"),
    ("It reads nothing else", "the only input is the frames of the sample being tracked, and a .cfg of settings."
                              " No atlas, no pretrained network, no second dataset, no internet"),
    ("It forms no floating point value", "every stage is integer arithmetic, so the same frames give the same"
                                         " bytes on any machine that runs it"),
]

INK = "#e6ebf2"
DIM = "#98a2b3"
PAGE = "#0b0d11"
PANEL = "#141821"
EDGE = "#2a3140"
FRAME = "#56B4E9"
PAIR = "#E69F00"
GOOD = "#009E73"
BAD = "#D55E00"
PINK = "#CC79A7"

def grouped(value):
    return "{:,}".format(value)

def share(part, whole):
    tenths = (part * 2000 + whole) // (2 * whole)
    return "%d.%d%%" % divmod(tenths, 10)

def read_stages(path):
    totals = {name: 0 for name, _, _, _ in STEPS}
    frames = 0
    samples = 0
    wall = 0
    pooled = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if re.match(r"^  [0-9a-f]{4}_[0-9a-f]{8} ", line):
                samples += 1
                frames += int(re.search(r"(\d+) frames", line).group(1))
                for name in totals:
                    found = re.search(r"\b%s (\d+)" % name, line)
                    totals[name] += int(found.group(1)) if found else 0
            found = re.match(r"^    (correct link|wrong link|no link made|target among branches|endpoint undetected)\s+(\d+)", line)
            if found:
                pooled[found.group(1)] = int(found.group(2))
            found = re.match(r"^  (\d+) ms$", line)
            if found:
                wall = int(found.group(1))
    return totals, frames, samples, wall, pooled

def read_objects(directory):
    sizes = {}
    aberrant = 0
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".object"):
            continue
        path = os.path.join(directory, name)
        with open(path, "rb") as handle:
            header = struct.unpack("<16I", handle.read(64))
        sizes[name[:-7]] = (os.path.getsize(path), header)
        aberrant += header[11] + header[12] + header[13]
    return sizes, aberrant

def text(x, y, words, size=16, fill=INK, weight="400", anchor="start"):
    return '<text x="%d" y="%d" font-size="%d" fill="%s" font-weight="%s" text-anchor="%s">%s</text>' % (
        x, y, size, fill, weight, anchor, html.escape(words))

def wrapped(x, y, words, room, size=15, fill=DIM, step=21):
    budget = max(8, room // ((size * 55) // 100))
    lines = []
    line = ""
    for word in words.split(" "):
        candidate = word if line == "" else (line + " " + word)
        if len(candidate) > budget:
            lines.append(line)
            line = word
        else:
            line = candidate
    lines.append(line)
    return [text(x, y + (step * at), lines[at], size, fill) for at in range(len(lines))], y + (step * len(lines))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stages", required=True, help="a Windows driver log of the 25 samples, no objects written")
    parser.add_argument("--linux", required=True, help="the Linux build's log of the same 25 samples")
    parser.add_argument("--objects", default=os.path.join(ROOT, "view", "data"))
    parser.add_argument("--out", default="D:/kaggle/biohub_cell_tracking/SUBMISSION/infographic.svg")
    options = parser.parse_args()

    totals, frames, samples, wall, pooled = read_stages(options.stages)
    _, _, linux_samples, linux_wall, linux_pooled = read_stages(options.linux)
    objects, aberrant = read_objects(options.objects)
    whole = sum(totals.values())
    per_frame = sum(totals[name] for name, _, _, group in STEPS if group == "frame")
    per_pair = whole - per_frame
    edges = sum(pooled.values())
    correct = pooled.get("correct link", 0)
    first_name = sorted(objects)[0]
    object_bytes, header = objects[first_name]
    dense = header[2] * header[3] * header[4] * header[5] * 4
    all_object_bytes = sum(size for size, _ in objects.values())

    width = 1200
    parts = []

    def panel(top, height, title):
        parts.append('<rect x="40" y="%d" width="%d" height="%d" rx="14" fill="%s" stroke="%s"/>'
                     % (top, width - 80, height, PANEL, EDGE))
        parts.append(text(64, top + 38, title, 22, INK, "600"))

    parts.append(text(40, 70, "Tracking every cell in a developing zebrafish", 36, INK, "700"))
    parts.append(text(40, 104, "One compiled tracker. No training, no model, nothing read but the movie in front of it.",
                      18, DIM))
    y = 140

    rows = 120 + (len(STEPS) * 78)
    panel(y, rows, "What happens to a movie")
    parts.append(text(64, y + 66, "%d training samples, %s frames, one RTX 3070, Windows 11. Each step's bar is its"
                                  " summed clock over those samples." % (samples, grouped(frames)), 15, DIM))
    bar_left = 880
    bar_room = width - 80 - bar_left - 150
    row = y + 96
    for at in range(len(STEPS)):
        name, title, meaning, group = STEPS[at]
        colour = FRAME if group == "frame" else PAIR
        length = max(2, (totals[name] * bar_room) // max(totals.values()))
        parts.append('<circle cx="76" cy="%d" r="13" fill="%s"/>' % (row + 12, colour))
        parts.append(text(76, row + 17, "%d" % (at + 1), 14, PAGE, "700", "middle"))
        parts.append(text(100, row + 17, title, 17, INK, "600"))
        lines, _ = wrapped(100, row + 41, meaning, bar_left - 130)
        parts.extend(lines)
        parts.append('<rect x="%d" y="%d" width="%d" height="22" rx="4" fill="%s"/>' % (bar_left, row + 2, length, colour))
        parts.append(text(bar_left + length + 10, row + 19, "%s ms" % grouped(totals[name]), 14, DIM))
        row += 78
    parts.append('<rect x="64" y="%d" width="16" height="16" rx="3" fill="%s"/>' % (row - 4, FRAME))
    parts.append(text(88, row + 9, "once per frame: %s ms, %s of the engine time"
                      % (grouped(per_frame), share(per_frame, whole)), 16, INK))
    parts.append('<rect x="620" y="%d" width="16" height="16" rx="3" fill="%s"/>' % (row - 4, PAIR))
    parts.append(text(644, row + 9, "once per pair of frames: %s ms, %s"
                      % (grouped(per_pair), share(per_pair, whole)), 16, INK))
    y += rows + 30

    panel(y, 250, "What it never does")
    row = y + 80
    for title, meaning in NEVER:
        parts.append('<circle cx="76" cy="%d" r="10" fill="none" stroke="%s" stroke-width="3"/>' % (row - 5, BAD))
        parts.append('<line x1="69" y1="%d" x2="83" y2="%d" stroke="%s" stroke-width="3"/>' % (row - 12, row + 2, BAD))
        parts.append(text(100, row, title, 18, INK, "600"))
        lines, _ = wrapped(100, row + 24, meaning, width - 240)
        parts.extend(lines)
        row += 62
    y += 280

    panel(y, 230, "Links against the answer key")
    parts.append(text(64, y + 110, "%s of %s" % (grouped(correct), grouped(edges)), 54, GOOD, "700"))
    parts.append(text(64, y + 144, "labeled links correct, %s, strict scoring" % share(correct, edges), 18, INK))
    stack_left = 560
    stack_room = width - 80 - stack_left - 24
    cursor = stack_left
    for label, colour in (("correct link", GOOD), ("wrong link", BAD), ("no link made", PINK)):
        count = pooled.get(label, 0)
        length = (count * stack_room + edges - 1) // edges if count else 0
        parts.append('<rect x="%d" y="%d" width="%d" height="34" fill="%s"/>' % (cursor, y + 72, length, colour))
        cursor += length
    parts.append(text(stack_left, y + 140, "wrong %s (%s), no link %s (%s), endpoint not detected %s" % (
        grouped(pooled.get("wrong link", 0)), share(pooled.get("wrong link", 0), edges),
        grouped(pooled.get("no link made", 0)), share(pooled.get("no link made", 0), edges),
        grouped(pooled.get("endpoint undetected", 0))), 15, DIM))
    parts.append(text(64, y + 196, "The same %s samples on the Linux build: %s, wall clock %s ms." % (
        linux_samples, "the same pooled score, edge rows byte for byte" if linux_pooled == pooled
        else "a pooled score that differs from the Windows build's", grouped(linux_wall)), 15, DIM))
    y += 260

    panel(y, 300, "What comes out")
    parts.append(text(64, y + 70, "One sample of %d frames, %d x %d x %d voxels, as one file, including the .cfg that"
                      " made it:" % (header[2], header[3], header[4], header[5]), 16, INK))
    dense_room = width - 80 - 64 - 240
    object_length = max(3, (object_bytes * dense_room) // dense)
    parts.append('<rect x="64" y="%d" width="%d" height="30" rx="4" fill="%s"/>' % (y + 90, dense_room, EDGE))
    parts.append(text(64 + dense_room + 12, y + 111, "%s bytes as labelled voxels" % grouped(dense), 15, DIM))
    parts.append('<rect x="64" y="%d" width="%d" height="30" rx="4" fill="%s"/>' % (y + 130, object_length, FRAME))
    parts.append(text(64 + object_length + 12, y + 151, "%s bytes as runs, %d times smaller"
                      % (grouped(object_bytes), dense // object_bytes), 15, DIM))
    lines, _ = wrapped(64, y + 196,
                       "All %d objects together are %s bytes. The viewer page streams one into a single buffer on the"
                       " graphics card and draws every cell from it: voxels, or smooth translucent cells lit by lights"
                       " the reader moves, each with a wall at the membrane's thickness, beside a map the camera turns."
                       " A clinical face names things in words; a machine face exposes every integer to a program."
                       % (len(objects), grouped(all_object_bytes)), width - 200, 15, INK, 24)
    parts.extend(lines)
    y += 330

    panel(y, 300, "What every run checks, and what it still gets wrong")
    checks = [
        ("Runs against voxels", "%d objects: every basin's run lengths sum to its voxel count, %d aberrant"
                                % (len(objects), aberrant)),
        ("Settings against settings", "a .cfg written by a run, run again, writes the same bytes and the same edges"),
    ]
    row = y + 78
    for title, meaning in checks:
        parts.append('<circle cx="76" cy="%d" r="9" fill="%s"/>' % (row - 6, GOOD))
        parts.append(text(100, row, title, 17, INK, "600"))
        parts.append(text(100, row + 24, meaning, 15, DIM))
        row += 58
    limits = [
        "Every positive basin is a cell here: about 1,000 a frame against a published estimate of a few hundred.",
        "Repairing an over-cut cell can join two distinct cells through a hub; the viewer's review list ranks them.",
        "The binary does not yet write the competition's submission file, and it wants a compute 7.5 or 8.6 device.",
    ]
    for words in limits:
        parts.append('<circle cx="76" cy="%d" r="9" fill="%s"/>' % (row - 6, PINK))
        parts.append(text(100, row, words, 15, INK))
        row += 34
    y += 330

    parts.append(text(40, y + 10, "Membrane thickness: Bionumbers, cell biology by the numbers; bilayer 3.6 to 4.3 nm"
                                  " in rat hepatocyte plasma membranes (Mitra et al., PNAS 2004).", 12, DIM))
    height = y + 40
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" font-family="Segoe UI,'
           ' Roboto, Helvetica, Arial, sans-serif">' % (width, height, width, height),
           '<rect width="%d" height="%d" fill="%s"/>' % (width, height, PAGE)] + parts + ["</svg>"]
    with open(options.out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(svg) + "\n")
    print("  %s (%d x %d)" % (options.out, width, height))
    print("  %d samples, %d frames, %d of %d ms per frame, %d of %d edges correct, %d objects, %d aberrant" % (
        samples, frames, per_frame, whole, correct, edges, len(objects), aberrant))

if __name__ == "__main__":
    main()
