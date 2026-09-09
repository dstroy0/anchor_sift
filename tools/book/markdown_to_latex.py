from pathlib import Path
import re
import sys

SPECIALS = {
    "&": r"\&",
    "%": r"\%",
    "$": r"\$",
    "#": r"\#",
    "_": r"\_",
    "{": r"\{",
    "}": r"\}",
    "~": r"\textasciitilde{}",
    "^": r"\textasciicircum{}",
    "\\": r"\textbackslash{}",
}


def escape_text(value):
    return "".join(SPECIALS.get(character, character) for character in value)


def inline(value):
    protected = []

    def protect(content):
        protected.append(content)
        return f"\x00{len(protected) - 1}\x00"

    def format_code(match):
        code = escape_text(match.group(1))
        code = code.replace("/", "/\\allowbreak{}")
        code = code.replace("-", "-\\allowbreak{}")
        code = code.replace(".", ".\\allowbreak{}")
        code = code.replace("_", "_\\allowbreak{}")
        code = re.sub(r"(?<=[a-z])(?=[A-Z])", r"\\allowbreak{}", code)
        return protect(r"\texttt{" + code + "}")

    value = re.sub(r"`([^`]+)`", format_code, value)
    value = re.sub(
        r"\$\$(.+?)\$\$", lambda match: protect(r"\(" + match.group(1) + r"\)"), value
    )
    value = re.sub(
        r"\$(.+?)\$", lambda match: protect(r"\(" + match.group(1) + r"\)"), value
    )
    protected = [
        content.replace(r"\lt", "<").replace(r"\gt", ">") for content in protected
    ]
    value = escape_text(value)
    value = re.sub(r"\*\*(.+?)\*\*", r"\\textbf{\1}", value)
    value = re.sub(r"\*(.+?)\*", r"\\emph{\1}", value)
    value = re.sub(r"(?<!\\)_([^_]+)_", r"\\emph{\1}", value)
    value = re.sub(
        r"\x00(\d+)\x00", lambda match: protected[int(match.group(1))], value
    )
    return value


def table_row(line):
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def is_separator(line):
    cells = table_row(line)
    return bool(cells) and all(re.fullmatch(r":?-+:?", cell) for cell in cells)


def convert_table(lines, index):
    rows = [table_row(lines[index])]
    index += 1
    if index < len(lines) and is_separator(lines[index]):
        index += 1
    while index < len(lines) and "|" in lines[index] and lines[index].strip():
        rows.append(table_row(lines[index]))
        index += 1
    width = max(len(row) for row in rows)
    column_width = rf"\dimexpr\textwidth/{width}-2\tabcolsep\relax"
    spec = (
        "@{}"
        + "".join(
            rf">{{\setlength{{\rightskip}}{{0pt}}\setlength{{\parfillskip}}{{0pt}}\arraybackslash}}p{{{column_width}}}"
            for _ in range(width)
        )
        + "@{}"
    )
    output = [
        r"\tiny",
        r"\setlength{\tabcolsep}{2pt}",
        f"\\begin{{longtable}}{{{spec}}}",
        "\\toprule",
    ]
    for row_number, row in enumerate(rows):
        row += [""] * (width - len(row))
        output.append(" & ".join(inline(cell) for cell in row) + r" \\")
        if row_number == 0:
            output.append("\\midrule")
    output.extend(["\\bottomrule", "\\end{longtable}", r"\normalsize", ""])
    return output, index


def convert(source, title):
    lines = source.splitlines()
    output = [
        r"\chapter{" + inline(title) + "}",
        "",
    ]
    index = 0
    paragraph = []
    in_code = False
    code_lines = []

    def flush_paragraph():
        if paragraph:
            output.append(" ".join(inline(part.strip()) for part in paragraph))
            output.append("")
            paragraph.clear()

    while index < len(lines):
        line = lines[index]
        if line.startswith("```"):
            flush_paragraph()
            if not in_code:
                in_code = True
                code_lines = []
            else:
                output.extend(
                    [
                        r"\begin{lstlisting}[breaklines=true,breakatwhitespace=false,basicstyle=\ttfamily\small]",
                        *code_lines,
                        r"\end{lstlisting}",
                        "",
                    ]
                )
                in_code = False
            index += 1
            continue
        if line.strip() == "$$":
            flush_paragraph()
            index += 1
            equation = []
            while index < len(lines) and lines[index].strip() != "$$":
                equation.append(lines[index])
                index += 1
            if index < len(lines):
                index += 1
            output.extend([r"\[", *equation, r"\]", ""])
            continue
        if in_code:
            code_lines.append(line)
            index += 1
            continue
        if not line.strip():
            flush_paragraph()
            index += 1
            continue
        heading = re.match(r"^(#{1,6})\s+(.+)$", line)
        if heading:
            flush_paragraph()
            level = len(heading.group(1))
            command = {
                1: "section",
                2: "subsection",
                3: "subsubsection",
                4: "paragraph",
                5: "subparagraph",
                6: "textbf",
            }[level]
            output.extend([f"\\{command}{{{inline(heading.group(2))}}}", ""])
            index += 1
            continue
        if line.startswith("|") and index + 1 < len(lines) and "|" in lines[index + 1]:
            flush_paragraph()
            table, index = convert_table(lines, index)
            output.extend(table)
            continue
        bullet = re.match(r"^\s*[-*+]\s+(.+)$", line)
        if bullet:
            flush_paragraph()
            output.append(r"\begin{itemize}")
            while index < len(lines):
                match = re.match(r"^\s*[-*+]\s+(.+)$", lines[index])
                if not match:
                    break
                output.append(r"\item " + inline(match.group(1)))
                index += 1
            output.extend([r"\end{itemize}", ""])
            continue
        if re.match(r"^\s*\d+\.\s+", line):
            flush_paragraph()
            output.append(r"\begin{enumerate}")
            while index < len(lines):
                match = re.match(r"^\s*\d+\.\s+(.+)$", lines[index])
                if not match:
                    break
                output.append(r"\item " + inline(match.group(1)))
                index += 1
            output.extend([r"\end{enumerate}", ""])
            continue
        if line.startswith(">"):
            paragraph.append(line[1:].strip())
        else:
            paragraph.append(line)
        index += 1
    flush_paragraph()
    if in_code:
        output.extend(
            [
                r"\begin{lstlisting}[breaklines=true,breakatwhitespace=false,basicstyle=\ttfamily\small]",
                *code_lines,
                r"\end{lstlisting}",
                "",
            ]
        )
    return "\n".join(output) + "\n"


# One entry per theory under theory/. Each is its own document with its own title page, and they
# share theory/preamble.tex, and a layout change reaches all of them.
#
# Sources all live under docs/research because that is what the site serves, and a second copy under
# theory/ would be a second thing to keep true. The books hold TeX alone.
BOOKS = (
    {
        "directory": "anchor_sift",
        "title": "Anchor Sift",
        "subtitle": "The construction, the method, and the vocabulary",
        "chapters": (
            ("anchor-sift.md", "The construction"),
            ("anchor-sift-method.md", "The method"),
            ("anchor-sift-missing-term.md", "Ordering the anchors by rarity"),
            ("terms.md", "Terms"),
        ),
    },
    {
        "directory": "workbook",
        "title": "Workbook",
        "subtitle": "Every claim, what killed it, and what still stands",
        "chapters": (("anchor-sift-ledger.md", "The ledger"),),
    },
    {
        "directory": "Salishan",
        "title": "Salishan",
        "subtitle": "Whose words these are, and how wrong the corpus could be",
        "chapters": (
            ("Salishan/pure_corpus/README.md", "Whose words these are"),
            ("Salishan/anchor-sift-salishan.md", "The corpus under the instrument"),
            ("Salishan/corpus-derivation.md", "How wrong it could be"),
            ("Salishan/running.md", "Running the extraction"),
            ("Salishan/refs.md", "Sources"),
        ),
    },
    {
        "directory": "thought_experiments",
        "title": "Thought Experiments",
        "subtitle": "The weird end, kept apart from what was measured",
        "chapters": (
            ("thought-experiments/README.md", "Sorted by wacky and by refusable"),
            ("thought-experiments/delta-null.md", "Delta null as a topological boundary"),
            ("thought-experiments/delta-null-what-is-testable.md",
             "What of delta null can be measured"),
            ("thought-experiments/hourly-supposition.md", "Suppositions, by the hour"),
            ("thought-experiments/absolute-zero.md", "Absolute zero as the noise floor"),
            ("thought-experiments/unification.md", "Unification and the continuum"),
        ),
    },
)

TITLEPAGE = r"""%% Generated by tools/book/markdown_to_latex.py. Edit the manifest there.
\begin{titlepage}
  \centering
  \vfill
  {\Large\spacedallcaps{%(title)s}} \\
  \vspace{2cm}
  \spacedlowsmallcaps{by} \\
  \vspace{1cm}
  {\large\spacedallcaps{Douglas Quigg}} \\
  \vfill
  \spacedlowsmallcaps{Research and Theory} \\
  \spacedlowsmallcaps{%(subtitle)s} \\
  \vfill
  \spacedlowsmallcaps{anchor\_sift} \\
  \spacedlowsmallcaps{2026}
  \vfill
\end{titlepage}
"""

MAIN = r"""%% Generated by tools/book/markdown_to_latex.py. Edit the manifest there.
%% Compile from this directory so the shared inputs resolve:
%%     latexmk -pdf -outdir=../../build/theory/%(directory)s main.tex
\documentclass[11pt,paper=a4,twoside,openright,titlepage,
headinclude,footinclude,BCOR=5mm]{scrbook}

\input{../preamble.tex}

\begin{document}
\frenchspacing
\emergencystretch=3em
\hbadness=10000
\vbadness=10000
\hfuzz=8pt
\cfoot*{}
\ofoot*{\pagemark}

\frontmatter
\pagestyle{plain}
\include{frontmatter/titlepage}

\tableofcontents

\mainmatter
\pagestyle{scrheadings}

%(includes)s
\end{document}
"""


def chapter_stem(relative):
    """A chapter file name from a source path, flattened to keep a subdirectory from colliding."""
    return "chapter_" + relative.replace("/", "_").replace("-", "_").rsplit(".", 1)[0]


def build_book(root, book):
    """Writes one book's chapters, its title page and its main.tex."""
    source_dir = root / "docs" / "research"
    book_dir = root / "theory" / book["directory"]
    (book_dir / "chapters").mkdir(parents=True, exist_ok=True)
    (book_dir / "frontmatter").mkdir(parents=True, exist_ok=True)

    includes = []
    for relative, title in book["chapters"]:
        source_path = source_dir / relative
        if not source_path.is_file():
            print("  missing, skipped: %s" % source_path)
            continue
        stem = chapter_stem(relative)
        (book_dir / "chapters" / (stem + ".tex")).write_text(
            convert(source_path.read_text(encoding="utf-8"), title), encoding="utf-8"
        )
        includes.append(r"\include{chapters/%s}" % stem)

    (book_dir / "frontmatter" / "titlepage.tex").write_text(
        TITLEPAGE % {"title": book["title"], "subtitle": book["subtitle"]},
        encoding="utf-8",
    )
    (book_dir / "main.tex").write_text(
        MAIN % {"directory": book["directory"], "includes": "\n".join(includes)},
        encoding="utf-8",
    )
    return len(includes)


def main():
    # The direction is inverted and this script is retired. theory/ holds the research now, the
    # chapters are edited by hand, and docs/research carries pointer pages written from the same
    # manifest by theory_pointers.py. Running the old direction would rebuild every chapter from a
    # pointer page and delete the research doing it, so it refuses instead.
    #
    # It is kept because the manifest below is still the list of what each book holds, and because
    # its markdown to TeX conversion is the record of how the chapters were first produced.
    if "--overwrite-chapters" not in sys.argv:
        print("  markdown_to_latex is retired: theory/ is the source, docs/research points at it.")
        print("  Chapters are edited by hand. Rebuilding them from the pointer pages would empty")
        print("  every book. Use tools/dev_env/theory_pointers.py to refresh the pointer pages,")
        print("  and tools/book/build_theory.sh to build the PDFs.")
        return 1

    root = Path(__file__).resolve().parents[2]
    for book in BOOKS:
        written = build_book(root, book)
        print("  %-20s %d chapter(s)" % (book["directory"], written))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
