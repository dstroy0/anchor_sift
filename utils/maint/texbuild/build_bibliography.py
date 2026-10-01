r"""Generates every research paper's bibliography from the citations registry, pinned to a commit.

A surname in a chapter tells a reader which idea is being used and gives them nothing to go and
read. This turns the registry next door into a bibliography, and pins it: every entry carries the
commit of anchor_sift_citations it was read from, and the SHA-256 of the held copy where there is
one. A reader who disagrees with a number can then ask which bytes it was checked against and get
an exact answer.

The registry is the single source of truth. Nothing bibliographic is written here, because a second
copy of a citation is a second thing to keep true and the two would drift.

    python utils/maint/texbuild/build_bibliography.py

A research paper is every directory under theory/ holding a main.tex, at the two depths
build_theory.sh walks. Its entries are the registry rows whose key its own TeX spells or cites as
\cite{src:<label>} or \nocite{src:<label>}, matched by key_pattern in
utils/maint/citations/citations.py, the match a use is counted by. The result is bibliography.tex
beside main.tex, which main.tex brings in last. It sits beside main.tex and not in chapters/,
because theory_tex.py owns chapters/ in the research papers it writes and removes what it did not
write there. A research paper whose TeX neither spells nor cites a key gets no file.

Finds the registry through ANCHOR_SIFT_CITATIONS, else beside the checkouts. Errors instead of
generating from a dirty or unpushed registry, because a pin to a commit nobody else can fetch is not
a pin.
"""

import glob
import io
import os
import re
import subprocess
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, os.path.join(ROOT, "utils", "maint", "citations"))

import citations  # noqa: E402

TARGET = "bibliography.tex"

# Letters NFKD leaves whole, with the Latin letters a reference list files them under.
WHOLE = str.maketrans({"Ł": "L", "ł": "l", "Ø": "O", "ø": "o", "Đ": "D", "đ": "d", "Æ": "AE",
                       "æ": "ae", "Œ": "OE", "œ": "oe", "ß": "ss", "Þ": "Th", "þ": "th", "ı": "i"})


def filed(key):
    """The key as a reference list files it, marks dropped and case folded: Łoś under L, Gouvêa under G."""
    parts = unicodedata.normalize("NFKD", key.translate(WHOLE))
    return "".join(c for c in parts if not unicodedata.combining(c)).casefold()


def git(repo, *args):
    return subprocess.check_output(("git", "-C", repo) + args).decode().strip()


def escape(text):
    """LaTeX-safe. Titles carry colons and hyphens; authors carry accents that fontspec handles."""
    for bad, good in (("\\", "\\textbackslash{}"), ("&", "\\&"), ("%", "\\%"), ("$", "\\$"),
                      ("#", "\\#"), ("_", "\\_"), ("{", "\\{"), ("}", "\\}"), ("~", "\\textasciitilde{}"),
                      ("^", "\\textasciicircum{}")):
        text = text.replace(bad, good)
    return text


def breakable(text):
    """Escaped, in typewriter, with a break allowed after every slash and underscore."""
    text = escape(text).replace("/", "/\\allowbreak{}").replace("\\_", "\\_\\allowbreak{}")
    return "\\texttt{%s}" % text


def identifier(text):
    """An address is set breakable; anything else, a venue or a page, is set as text."""
    return " ".join(breakable(part) if "/" in part and " " not in part else escape(part)
                    for part in text.split(" "))


def read_table(path):
    rows = []
    with io.open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if (not line.strip()) or line.startswith("#"):
                continue
            parts = line.split("\t")
            if parts[0] in ("key", "sha256"):
                continue
            rows.append(parts)
    return rows


def research_papers():
    """Every directory holding a main.tex, at the two depths build_theory.sh walks."""
    found = glob.glob(os.path.join(ROOT, "theory", "*", "*", "main.tex"))
    found += glob.glob(os.path.join(ROOT, "theory", "*", "*", "*", "main.tex"))
    return sorted(os.path.dirname(one) for one in found)


BROUGHT_IN = re.compile(r"\\(?:input|include)\{([^}]+)\}")


def research_paper_text(research_paper):
    """Every .tex the research paper is built from, this file's own output excluded.

    That is every .tex under its directory, and every file an \\input or \\include in one of them
    names, resolved against the directory main.tex is built in, wherever it sits.
    """
    files = []
    for base, dirs, names in os.walk(research_paper):
        for name in sorted(names):
            if not name.endswith(".tex"):
                continue
            if base == research_paper and name == TARGET:
                continue
            files.append(os.path.normpath(os.path.join(base, name)))
    seen = set(files)
    text = []
    while files:
        path = files.pop(0)
        with io.open(path, encoding="utf-8", errors="replace") as handle:
            body = handle.read()
        text.append(body)
        for named in BROUGHT_IN.findall(body):
            found = os.path.normpath(os.path.join(research_paper, named.strip()))
            if not found.endswith(".tex"):
                found += ".tex"
            if found not in seen and os.path.isfile(found):
                seen.add(found)
                files.append(found)
    return "\n".join(text)


def entry(s, held):
    parts = [escape(s["author"] or s["key"])]
    if s["title"]:
        parts.append("\\emph{%s}" % escape(s["title"]))
    if s["identifier"]:
        parts.append(identifier(s["identifier"]))
    if s["year"] and s["year"] not in s["title"] + s["identifier"]:
        parts.append(escape(s["year"]))
    if not (s["author"] or s["identifier"]):
        parts = ["%s. Owed a full citation" % escape(s["key"])]
    text = ". ".join(part.rstrip(".") for part in parts) + "."
    digest = held.get(s["file"], "") if s["file"] else ""
    if s["file"]:
        text += "\\newline\n{\\footnotesize Copy held %s" % breakable(s["file"])
        if digest:
            text += ", SHA-256 \\texttt{%s}" % escape(digest)
        text += ".}"
    return "\\bibitem{%s}\n%s" % (citations.label(s["key"]), text)


def render(sources, held, commit, when):
    owed = [s for s in sources if not (s["author"] or s["identifier"])]
    out = []
    out.append("\\backmatter")
    out.append("\\AfterBibliographyPreamble{%")
    out.append("Every measurement in this work is built on somebody's published result, and the")
    out.append("first purpose of this chapter is that those people are credited by name. A surname")
    out.append("in a footnote is not a citation. The second purpose is that the credit is checkable:")
    out.append("each source is registered in \\texttt{anchor\\_sift\\_citations}, where the copy sits")
    out.append("itself, and this bibliography is generated from that registry and pinned to one")
    out.append("commit of it. A reference therefore resolves not to a title but to exact bytes.")
    out.append("")
    out.append("Credit here does not depend on agreement. Where this work reproduces a published")
    out.append("result it says so, and where it fails to reproduce one it says that too, under the")
    out.append("same names, because a refutation rests on the original as much as a confirmation does.")
    out.append("")
    out.append("\\begin{description}")
    out.append("\\item[Registry commit] \\texttt{%s}" % commit)
    out.append("\\item[Dated] %s" % escape(when))
    out.append("\\item[Inventory] \\texttt{MANIFEST.tsv}, signed; the hashes below are its rows")
    out.append("\\end{description}")
    out.append("")
    out.append("A reader who disagrees with a number in this research paper can ask which copy it was checked")
    out.append("against, and the hash answers exactly. Two copies of a paper are rarely the same")
    out.append("bytes.")
    if owed:
        out.append("")
        out.append("These results are used in the work and their authors are not yet properly")
        out.append("credited: the registry holds a key and no bibliographic fields.")
    out.append("\\par\\medskip\\raggedright}")
    out.append("\\KOMAoptions{bibliography=totoc}")
    out.append("\\begin{thebibliography}{%d}" % len(sources))
    out.append("")
    for s in sources:
        out.append(entry(s, held))
        out.append("")
    out.append("\\end{thebibliography}")
    return "\n".join(out) + "\n"


def main():
    registry = citations.private_root()
    if not os.path.isdir(registry):
        sys.stderr.write("no citations registry; set ANCHOR_SIFT_CITATIONS\n")
        return 1

    if git(registry, "status", "--porcelain"):
        sys.stderr.write("the registry has uncommitted changes; commit and sign it first\n")
        return 1

    commit = git(registry, "rev-parse", "HEAD")
    try:
        remote = git(registry, "rev-parse", "origin/main")
    except subprocess.CalledProcessError:
        remote = None
    if remote != commit:
        sys.stderr.write("the registry commit is not pushed; a pin nobody can fetch is not a pin\n")
        return 1

    when = git(registry, "show", "-s", "--format=%cs", "HEAD")

    held = {}
    for row in read_table(os.path.join(registry, "MANIFEST.tsv")):
        while len(row) < 4:
            row.append("")
        held[row[3]] = row[0]

    columns = citations.FIELDS
    sources = []
    for row in read_table(os.path.join(registry, citations.NAME)):
        row += [""] * (len(columns) - len(row))
        sources.append(dict(zip(columns, row)))
    sources.sort(key=lambda s: filed(s["key"]))

    for research_paper in research_papers():
        text = research_paper_text(research_paper)
        used = [s for s in sources if citations.key_pattern(s["key"]).search(text)]
        target = os.path.join(research_paper, TARGET)
        shown = os.path.relpath(target, ROOT).replace("\\", "/")
        if not used:
            if os.path.isfile(target):
                os.remove(target)
                print("removed %s, no key used" % shown)
            continue
        with io.open(target, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(render(used, held, commit, when))
        owed = sum(1 for s in used if not (s["author"] or s["identifier"]))
        print("wrote %-60s %3d entries, %d owed a full citation" % (shown, len(used), owed))

    print("pinned to %s (%s)" % (commit[:12], when))
    return 0


if __name__ == "__main__":
    sys.exit(main())
