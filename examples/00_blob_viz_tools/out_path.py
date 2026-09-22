"""Where a generated page goes, resolved to keep a tool from writing beside itself.

    python tools/view/out_path.py --check

A library and not a tool.

THE DEFECT THIS EXISTS FOR

Every builder here defaulted its output to the directory holding the builder. That is harmless in
the tree the tool was written in and wrong everywhere else: fetched into another repository, the
tool writes a generated page into files that repository has locked, inside a directory it has told
its formatters to leave alone, and the next fetch either overwrites the page or refuses because the
tree is dirty. A generated file belongs where generated files go, and the tool's own directory is
never that place.

THE ORDER

    1  what the caller asked for, used exactly as given
    2  the VIEW_OUT directory, for a caller who wants one place for everything
    3  the host toolkit's scratch root, when a tool has been fetched into one
    4  a build directory at the top of the tree the tool sits in
    5  the temporary directory the machine offers

Four finds the top of the tree by walking up for a marker instead of counting directories, since a
fetched tool sits at whatever depth the host chose. Five is the last resort and it is still correct:
somewhere disposable beats somewhere locked. No step resolves to the directory holding the caller,
and the check below holds that.
"""

import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

# What marks the top of a tree. A version control directory names it in a checkout; the toolkit
# settings name it in a repository that has joined one; a build directory names it where a tree has
# been unpacked without either.
MARKERS = (".git", "repotools.toml", "build")


def tree_top(start):
    """The top of the tree holding this path, or None where no marker is found on the way up."""
    here = os.path.abspath(start)
    while True:
        for mark in MARKERS:
            if os.path.exists(os.path.join(here, mark)):
                return here
        parent = os.path.dirname(here)
        if parent == here:
            return None
        here = parent


def host_scratch():
    """The scratch root of a toolkit this tool has been fetched into, when there is one.

    Held in a try, because the toolkit is absent in the tree these tools are written in and a
    missing host is the normal case and never an error. A host that offers a root and then raises
    is treated the same as no host at all.
    """
    try:
        import config
        loaded = config.load()
        root = loaded.scratch_root()
        if root and os.path.isdir(os.path.dirname(os.path.abspath(root))):
            return os.path.abspath(root)
    except Exception:
        return None
    return None


def out_root():
    """The directory generated pages go in, made if it is absent."""
    named = os.environ.get("VIEW_OUT")
    if named:
        root = os.path.abspath(named)
    else:
        root = host_scratch()
        if root is None:
            top = tree_top(HERE)
            root = os.path.join(top, "build", "view") if top else os.path.join(
                tempfile.gettempdir(), "view")
    if not os.path.isdir(root):
        os.makedirs(root, exist_ok=True)
    return root


def resolve(name, explicit=None):
    """Where to write a page called `name`, honouring an explicit choice above everything else.

    An explicit path is used as given and never rehomed, because a caller naming a file has already
    decided. Its parent is made when it is absent, and a caller is not asked to create a directory
    before it can be written into.
    """
    if explicit:
        out = os.path.abspath(explicit)
        parent = os.path.dirname(out)
        if parent and not os.path.isdir(parent):
            os.makedirs(parent, exist_ok=True)
        return out
    return os.path.join(out_root(), name)


def _check():
    lines = []
    failed = 0

    def say(text):
        lines.append(text)

    # The property the whole module exists for: no default lands in the caller's own directory.
    was = os.environ.pop("VIEW_OUT", None)
    try:
        got = resolve("page.html")
        say("  a default page goes to %s" % os.path.dirname(got))
        if os.path.dirname(os.path.abspath(got)) == HERE:
            say("  FAIL the default resolved to the directory holding the tool")
            failed += 1
        if not os.path.isdir(os.path.dirname(got)):
            say("  FAIL the directory it named was not made")
            failed += 1

        # An explicit choice is obeyed exactly.
        want = os.path.join(tempfile.gettempdir(), "out_path_check", "named.html")
        got = resolve("ignored.html", want)
        if got != os.path.abspath(want):
            say("  FAIL an explicit path was not used as given")
            failed += 1
        if not os.path.isdir(os.path.dirname(got)):
            say("  FAIL the parent of an explicit path was not made")
            failed += 1
        say("  an explicit path is obeyed and its parent made")

        # The environment wins over the tree, letting a caller put every page in one place.
        os.environ["VIEW_OUT"] = os.path.join(tempfile.gettempdir(), "out_path_env")
        got = resolve("page.html")
        if os.path.dirname(got) != os.path.abspath(os.environ["VIEW_OUT"]):
            say("  FAIL the environment did not win over the tree")
            failed += 1
        say("  the environment wins over the tree")
        del os.environ["VIEW_OUT"]

        # Walking up finds a top from inside a tree, and gives nothing where there is no marker.
        if tree_top(HERE) is None:
            say("  FAIL no tree top was found from a directory inside a checkout")
            failed += 1
        root = os.path.abspath(os.sep)
        if tree_top(os.path.join(root, "nowhere", "at", "all")) is not None:
            say("  FAIL a top was claimed where no marker exists")
            failed += 1
        say("  the tree top is found by marker and not by counting directories")
    finally:
        if was is not None:
            os.environ["VIEW_OUT"] = was

    sys.stdout.write("\n".join(lines) + "\n\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    if "--check" in sys.argv[1:]:
        sys.exit(1 if _check() else 0)
    sys.stdout.write(__doc__)
    sys.exit(2)
