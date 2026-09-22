"""Copies the general tools into the toolkit repository, in its house style and its layout.

Two sets, because membership there is by what a thing is and never by who calls it:

  lib/numerics/          computation over numeric sequences. Imported, never run.
  media_tools/dataviz/   the viewers. Imports numerics.

    python maint/publish_dataviz.py            # report what would be copied
    python maint/publish_dataviz.py --write    # copy them

The tools that hardcode a path into this repository are not copied and are named below with the
reason, putting the decision on the record instead of in a commit message.

WHY THIS TRANSFORMS INSTEAD OF COPYING

A generator here says `import dsp`, which works only because Python puts a script's own directory
on sys.path when it is run. A fetched tool that is imported and not run does not get that, so the
published form opens with the toolkit's walk-up preamble and imports by set. That is a real
difference between the two trees, and it is applied mechanically at publish time and never by
hand: one source, one transform, no drift to maintain.

Copies and not symlinks, still deliberately. A link out of a fetched toolkit into a private tree
resolves on this machine and nowhere else. Toolkit canonical with links back into the consuming
tree is the shape that does not drift, and it is a move for when the boundary settles.
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIEW = os.path.join(HERE, "tools", "view")
TOOLKIT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "repo_tools")

HEADER = (
    "# repo_tools - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>\n"
    "# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial"
    " OR LicenseRef-Educational\n"
)

# Verbatim from lib/repotools/boot.py, the single duplicated fragment in that toolkit, because it
# is the code that finds the shared code; counting parents instead breaks the day a tool moves.
PREAMBLE = (
    "import os, sys\n"
    "_at = os.path.dirname(os.path.abspath(__file__))\n"
    "while _at != os.path.dirname(_at) and not os.path.isdir("
    "os.path.join(_at, \"lib\", \"repotools\")):\n"
    "    _at = os.path.dirname(_at)\n"
    "sys.path.insert(0, os.path.join(_at, \"lib\"))\n"
)

# what to copy, where it lands, and the imports the published form uses instead.
NUMERICS = {
    "dsp.py": "dsp.py",
    "exact.py": "precision.py",
}

DATAVIZ = [
    "build_blob_view.py",
    "build_chart_view.py",
    "build_field_view.py",
    "build_plot_view.py",
    "build_sound_view.py",
    "build_sweep_view.py",
    "settings.py",
    "chart_view_template.html",
    "voxel_view_template.html",
]

# Rewritten in the published form only. The left side is what this tree says.
#
# Matched on the statement and not on a line with its indentation baked in. The first version of
# this table wrote "\n    import exact as extended\n" for a line indented eight spaces, so it matched
# nothing, changed nothing, and published a file that raised ModuleNotFoundError the moment anyone
# used the option it guarded. A rewrite that does not match has to be an error and never a quiet
# pass-through, and LEFTOVERS below enforces that.
IMPORTS = [
    ("import dsp", "from numerics import dsp"),
    ("import exact as extended", "from numerics import precision as extended"),
    ("import exact", "from numerics import precision as exact"),
]

# No published file may still name a module that only exists in this tree. Checked after the
# rewrite and never trusted, because the failure this catches is the rewrite doing nothing.
LEFTOVERS = ("import dsp", "import exact", "import settings as")

STAYS = {
    "build_voxel_view.py": "opens src/bench/shadows.csv",
    "build_shadow_view.py": "opens src/bench/shadows.csv",
    "build_sources_view.py": "opens src/bench/sources.csv",
    "make_shadow_figure.py": "opens src/bench/shadows.csv",
    "build_step_view.py": "traces SHA-256, which is this tree's subject",
    "step_view_template.html": "belongs to build_step_view.py",
    "shadow_view_template.html": "belongs to build_shadow_view.py",
    "sources_view_template.html": "belongs to build_sources_view.py",
}


def published(text, name, runnable):
    """The file as the toolkit should hold it."""
    if name.endswith(".html"):
        # A template's first line is its title, and a header comment would print on the page.
        # Nothing to add.
        return text

    # Whole statements, so indentation cannot make a rule miss. Only a line matching exactly the
    # import is touched; the same words inside a docstring or a comment are left alone.
    out = []
    for line in text.split("\n"):
        bare = line.strip()
        for was, now in IMPORTS:
            if bare == was:
                line = line[:len(line) - len(line.lstrip())] + now
                break
        out.append(line)
    text = "\n".join(out)

    if "SPDX-License-Identifier" not in text[:400]:
        text = HEADER + text

    # Only something that is run needs to find the toolkit. A module that is imported is already
    # on the path by the time it loads, and a preamble in it would be dead code.
    if runnable and "_at = os.path.dirname" not in text:
        marker = '"""\n'
        end = text.find(marker, text.find('"""') + 3)
        if end > 0:
            cut = end + len(marker)
            text = text[:cut] + "\n" + PREAMBLE + text[cut:]

    # The rewrite is checked, not trusted. A module named here exists only in the source tree, and
    # a published file naming one would raise on import somewhere the author never runs it.
    for line in text.split("\n"):
        # startswith, not equality. The first version of this guard compared the whole statement, so
        # `import exact as extended` did not match the entry `import exact` and the check passed on
        # a file that raised at run time. A guard that only catches the spelling you thought of is
        # not a guard.
        if any(line.strip().startswith(one) for one in LEFTOVERS):
            raise SystemExit(
                "publish refused: %s still says %r after the rewrite.\n"
                "  Add the statement to IMPORTS. The published copy would have failed at run time."
                % (name, line.strip()))
    return text


def put(source_dir, name, target_dir, as_name, runnable, write):
    source = os.path.join(source_dir, name)
    if not os.path.exists(source):
        print("  MISSING   %s" % name)
        return 0
    with io.open(source, encoding="utf-8") as handle:
        text = handle.read()
    out = published(text, as_name, runnable)
    target = os.path.join(target_dir, as_name)
    same = (os.path.exists(target)
            and io.open(target, encoding="utf-8").read() == out)
    where = os.path.relpath(target, TOOLKIT).replace(os.sep, "/")
    print("  %-9s %s" % ("unchanged" if same else ("copy" if write else "would copy"), where))
    if write and not same:
        if not os.path.isdir(target_dir):
            os.makedirs(target_dir)
        with io.open(target, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(out)
        return 1
    return 0


def main():
    write = "--write" in sys.argv
    if not os.path.isdir(os.path.join(TOOLKIT, "lib", "repotools")):
        sys.stderr.write("no toolkit at %s\n" % TOOLKIT)
        return 1

    moved = 0
    for name, as_name in sorted(NUMERICS.items()):
        moved += put(VIEW, name, os.path.join(TOOLKIT, "lib", "numerics"), as_name, False, write)
    for name in DATAVIZ:
        runnable = name.startswith("build_")
        moved += put(VIEW, name, os.path.join(TOOLKIT, "media_tools", "dataviz"),
                     name, runnable, write)

    # Anything left behind by the rename has to go, or the toolkit holds two copies of one module
    # under two names and shape hashing will not tell anyone which is live.
    stale = os.path.join(TOOLKIT, "media_tools", "dataviz", "exact.py")
    if os.path.exists(stale):
        print("  %-9s media_tools/dataviz/exact.py (renamed to numerics/precision.py)"
              % ("remove" if write else "would remove"))
        if write:
            os.remove(stale)
    stale = os.path.join(TOOLKIT, "media_tools", "dataviz", "dsp.py")
    if os.path.exists(stale):
        print("  %-9s media_tools/dataviz/dsp.py (moved to numerics/dsp.py)"
              % ("remove" if write else "would remove"))
        if write:
            os.remove(stale)

    print("")
    print("staying in this tree:")
    for name in sorted(STAYS):
        print("  %-28s %s" % (name, STAYS[name]))

    print("")
    print("%d written" % moved if write else "nothing written. Run with --write.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
