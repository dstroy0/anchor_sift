import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VIEW = os.path.join(ROOT, "examples", "00_blob_viz_tools", "view")
PARTS = os.path.join(VIEW, "engine_view")
ORDER = ["turn_table.js", "shaders.js", "shaders_render.js", "shaders_slice.js", "shaders_soft.js", "object.js", "gpu.js", "cfg.js",
         "app.js", "panels.js", "input.js"]
OUTPUTS = [os.path.join(VIEW, "engine_view.html")]
MARK = "/*ENGINE_VIEW_SCRIPT*/"


def main():
    page = io.open(os.path.join(PARTS, "page.html"), encoding="utf-8").read()
    if MARK not in page:
        sys.stderr.write("  page.html has no %s\n" % MARK)
        return 1
    script = ["const EV = {};"]
    for name in ORDER:
        path = os.path.join(PARTS, name)
        if not os.path.isfile(path):
            sys.stderr.write("  missing part %s\n" % path)
            return 1
        script.append("// ---- %s ----" % name)
        script.append(io.open(path, encoding="utf-8").read())
    built = page.replace(MARK, "\n".join(script))
    for out in OUTPUTS:
        with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(built)
        print("  %s (%d bytes)" % (out, len(built.encode("utf-8"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
