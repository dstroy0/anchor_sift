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
    # Matched against the escaped form, because escape_text ran on the line above and every
    # underscore is \_ by the time this reads it. The old pattern refused exactly those: its
    # (?<!\\) was written for raw text and, run here, it never matched once. A _title_ reached the
    # page as \_title\_ and typeset as two literal underscores around the words.
    #
    # Word boundaries on both ends keep an identifier out of it, so read_me_first stays whole.
    value = re.sub(r"(?<![A-Za-z0-9])\\_(\S(?:(?!\\_).)*?)\\_(?![A-Za-z0-9])",
                   r"\\emph{\1}", value)
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
        # A thematic break. Nothing read it, so the dashes joined the paragraph, went through
        # inline() unescaped and typeset as an em dash, which is the one character the prose check
        # calls breaking. It becomes space: the division is what the author wrote, and a rule drawn
        # across the page is a decoration nobody asked for.
        if re.fullmatch(r"\s*(?:-{3,}|\*{3,}|_{3,})\s*", line):
            flush_paragraph()
            output.extend([r"\medskip", ""])
            index += 1
            continue
        # A figure on its own line. Without this the tag went through inline() and came out as
        # literal text, and a generator writing raw LaTeX instead had every backslash escaped.
        # The path is used as written, and a generator puts the file beside the chapter.
        picture = re.match(r"^!\[(.*)\]\(([^)]+)\)\s*$", line)
        if picture:
            flush_paragraph()
            output.extend([
                r"\begin{figure}[htbp]",
                r"\centering",
                r"\includegraphics[width=\textwidth]{%s}" % picture.group(2),
                r"\caption{%s}" % inline(picture.group(1)) if picture.group(1) else "",
                r"\end{figure}",
                "",
            ])
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


# BOOKS, TITLEPAGE, MAIN and chapter_stem were cut from here. They were build_book's inputs: the
# per book list of chapters, the two document templates, and the source path to chapter name rule.
# build_book is gone, every source path the list named was deleted when the research moved into
# theory/, and maint/texbuild/build_theory.sh finds the books by globbing theory for main.tex, so the
# list cannot go stale by being wrong about what exists.


def main():
    # The book building half of this file is gone, and removing it was the point.
    #
    # It converted docs/research markdown into theory chapters. That direction is dead: theory/ is
    # the source, the chapters are edited by hand, and docs/research is one pointer page. Every
    # source path the manifest below names was deleted when the research moved.
    #
    # build_book skipped a missing source and carried on, but it rewrote main.tex every time from
    # whatever it had found. With every source gone it would have written four books with empty
    # include lists, and the chapters would still be sitting there unread. A guard asking for
    # --overwrite-chapters was the earlier answer and it only made the loaded gun harder to fire.
    #
    # convert() stays and is imported by corpus_derivation.py and pure_corpus_index.py, which build
    # their chapters from markdown they generate in memory. Nothing writes a chapter from a file.
    print("  This module is imported for convert(), which turns markdown into a TeX chapter.")
    print("  It no longer builds books. theory/ is the source and its chapters are edited by hand.")
    print("  Build the PDFs with: sh maint/texbuild/build_theory.sh")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
