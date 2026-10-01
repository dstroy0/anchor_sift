"""Builds the engine view: its template and parts in 00_blob_viz_tools/view/engine_view/, its shared tools from the
lib's toolbox, through the lib's one generator.

    python examples/cell_tracking/maint/build_engine_view.py
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(os.path.dirname(HERE)), "00_blob_viz_tools")
VIEW = os.path.join(LIB, "view")
TEMPLATE = os.path.join(VIEW, "engine_view", "page.html")
OUTPUTS = [os.path.join(VIEW, "engine_view.html"), "D:/kaggle/biohub_cell_tracking/SUBMISSION/engine_view.html"]

sys.path.insert(0, LIB)
import generate_template  # noqa: E402


def main():
    try:
        built = generate_template.assemble(TEMPLATE)
    except generate_template.Refused as why:
        sys.stderr.write("  %s\n" % why)
        return 1
    for out in OUTPUTS:
        out_dir = os.path.dirname(out)
        if not os.path.isdir(out_dir):
            print("  skipped %s, no %s" % (out, out_dir))
            continue
        with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(built)
        print("  %s (%d bytes)" % (out, len(built.encode("utf-8"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
