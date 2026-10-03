"""Render source files to numbered PNG pages, for surveying at image density.

    src2png.py <file> <out_stem> [rows_per_page] [pt] [start] [end] [--columns N]
    src2png.py <dir> <dest> [kb_per_page] [pt] [--columns N]

A line wider than WRAP_COLUMNS, or than N where --columns is given, wraps onto
continuation rows that carry no line number, and nothing is clipped off the right. The directory form walks <dir>,
renders every file whose extension is in WALK_EXTS, and writes
<dest>/<name>_<ext>_<n>.png. Pages break on whole rows.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\consola.ttf",
    r"C:\Windows\Fonts\cour.ttf",
    r"C:\Windows\Fonts\lucon.ttf",
]

WALK_EXTS = (".txt", ".py", ".c", ".h", ".cpp")

WRAP_COLUMNS = 120


def load_font(size):
    for path in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def char_width(font):
    probe = Image.new("RGB", (10, 10))
    d = ImageDraw.Draw(probe)
    return d.textlength("M" * 100, font=font) / 100.0


def wrap_line(text, width):
    """Segments of text no wider than width, broken on a space near the edge or hard where none is."""
    if len(text) <= width:
        return [text]
    out = []
    rest = text
    while len(rest) > width:
        cut = rest.rfind(" ", 0, width + 1)
        if cut <= 0:
            out.append(rest[:width])
            rest = rest[width:]
        else:
            out.append(rest[:cut])
            rest = rest[cut + 1 :]
    out.append(rest)
    return out


def rows_of(lines, start):
    """(lineno, segment) rows: a source line's first segment carries its number, its wraps carry None."""
    rows = []
    for i, text in enumerate(lines):
        segments = wrap_line(text, WRAP_COLUMNS)
        rows.append((start + i, segments[0]))
        for seg in segments[1:]:
            rows.append((None, seg))
    return rows


def by_rows(rows, rows_per_page):
    """Chunks of rows_per_page rows."""
    for p0 in range(0, len(rows), rows_per_page):
        yield rows[p0 : p0 + rows_per_page]


def by_row_bytes(rows, kb_per_page):
    """Chunks holding at most kb_per_page kilobytes, split only between rows."""
    limit = kb_per_page * 1024
    used = 0
    chunk = []
    for lineno, text in rows:
        if chunk and used + len(text) + 1 > limit:
            yield chunk
            used = 0
            chunk = []
        chunk.append((lineno, text))
        used += len(text) + 1
    if chunk:
        yield chunk


def write_page(rows, name, font, cw, size):
    """One page: each row's line number in gray, blank on a wrap continuation, and its text in black."""
    lh = size + 5
    widest = max((len(text) for _, text in rows), default=1)
    W = int(cw * (widest + 7)) + 24
    H = lh * len(rows) + 20
    img = Image.new("RGB", (W, H), (255, 255, 255))
    dr = ImageDraw.Draw(img)
    for i, (lineno, text) in enumerate(rows):
        gutter = "{0:>5} ".format(lineno) if lineno is not None else ""
        dr.text((10, 10 + i * lh), gutter, font=font, fill=(150, 150, 150))
        dr.text((10 + cw * 6, 10 + i * lh), text, font=font, fill=(0, 0, 0))
    img.save(name)
    return W, H


def read_lines(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read().split("\n")


def render_file(src, out_stem, rows_per_page, size, start, end, font, cw):
    lines = read_lines(src)
    if end <= 0 or end > len(lines):
        end = len(lines)
    lines = lines[start - 1 : end]
    rows = rows_of(lines, start)
    out = []
    for n, chunk in enumerate(by_rows(rows, rows_per_page), 1):
        name = "{0}_{1}.png".format(out_stem, n)
        W, H = write_page(chunk, name, font, cw, size)
        out.append((name, W, H))
    return out


def render_tree(root, dest, kb_per_page, size, font, cw):
    if not os.path.isdir(dest):
        os.makedirs(dest)
    out = []
    for dirpath, _, filenames in os.walk(root):
        for fn in sorted(filenames):
            stem, ext = os.path.splitext(fn)
            if ext.lower() not in WALK_EXTS:
                continue
            src = os.path.join(dirpath, fn)
            lines = read_lines(src)
            rows = rows_of(lines, 1)
            base = os.path.join(dest, "{0}_{1}".format(stem, ext.lstrip(".").lower()))
            for n, chunk in enumerate(by_row_bytes(rows, kb_per_page), 1):
                name = "{0}_{1}.png".format(base, n)
                W, H = write_page(chunk, name, font, cw, size)
                out.append((name, W, H))
    return out


def main():
    global WRAP_COLUMNS
    args = sys.argv[1:]
    if "--columns" in args:
        at = args.index("--columns")
        WRAP_COLUMNS = int(args[at + 1])
        del args[at : at + 2]
    sys.argv[1:] = args
    src = sys.argv[1]
    dst = sys.argv[2]

    if os.path.isdir(src):
        kb_per_page = int(sys.argv[3]) if len(sys.argv) > 3 else 8
        size = int(sys.argv[4]) if len(sys.argv) > 4 else 15
        font = load_font(size)
        pages = render_tree(src, dst, kb_per_page, size, font, char_width(font))
    else:
        rows_per_page = int(sys.argv[3]) if len(sys.argv) > 3 else 200
        size = int(sys.argv[4]) if len(sys.argv) > 4 else 15
        start = int(sys.argv[5]) if len(sys.argv) > 5 else 1
        end = int(sys.argv[6]) if len(sys.argv) > 6 else 0
        font = load_font(size)
        pages = render_file(src, dst, rows_per_page, size, start, end, font, char_width(font))

    for name, W, H in pages:
        print("{0}  {1}x{2}".format(name, W, H))


if __name__ == "__main__":
    main()
