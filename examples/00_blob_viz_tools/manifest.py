"""Every viewer in one record, and a change to any one of them re-checks all of them.

    python examples/00_blob_viz_tools/manifest.py                 check the tree against the record
    python examples/00_blob_viz_tools/manifest.py --write         rewrite the record from the tree
    python examples/00_blob_viz_tools/manifest.py --check         run this tool against cases with known answers

WHAT WAS MISSING

Seventeen builders fill nine templates, and the pairing lived nowhere. A builder named its template
in a string, a template read its data by name in a hundred places, and nothing connected the two. A
key added to a template was a key seventeen builders might or might not supply, a template edited
under a builder was a page that changed without anybody asking for it, and the only way to learn
either was to open the page.

The sharing is not even. `voxel_view_template.html` is filled by six builders, `room_view_template`
by three and `sphere_view_template` by two, so one template edit reaches six pages and the record is
where that number lives.

`data_check.py` answers the question for one built page. This answers it for the set, and it answers
the question a set has that a page does not: **did anything move.**

WHAT THE RECORD HOLDS

One row per builder: the template it fills, the page it writes, the data keys that template reads
without a guard, the keys it reads with one, and a digest of the builder and of the template.

The digests are the tiling. A template edited under three builders changes one digest and the check
reports three rows, because a page is a builder and a template together and neither alone is the
thing that shipped. Nothing here re-derives what `data_check` already decides; `reads_of`,
`protected` and `data_literal` are imported, and a key graded one way by the gate therefore cannot
be graded another way here.

WHAT IT REFUSES

A builder whose template is gone. A template read that no builder supplies, being `data_check`'s
finding raised to the set. And any drift between the record and the tree. That last one is the
reason the record is checked in: a page that changes without the record changing is a change nobody
wrote down.
"""

import argparse
import hashlib
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import data_check

RECORD = os.path.join(HERE, "viewers.json")

# The template a builder fills, and the page it writes. Read out of the builder instead of declared
# beside it, because a declaration next to the code is a second place for the truth to live.
TEMPLATE = re.compile(r'"([a-z_]+_template\.html)"')
OUTPUT = re.compile(r'out_path\.resolve\(\s*"([^"]+)"')


def digest(path):
    """The SHA-256 of a file, or None when it is not there."""
    if not os.path.exists(path):
        return None
    with io.open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def builders():
    """Every builder in the view directory, by path, sorted to keep a record stable across runs."""
    return sorted(os.path.join(HERE, one) for one in os.listdir(HERE)
                  if one.startswith("build_") and one.endswith(".py"))


def template_reads(path):
    """The data keys a template reads, split by whether anything guards the read.

    Only the first segment of each path is kept. A builder supplies top level keys, and whether
    `clock.ticks` is present once `clock` is supplied is the builder's own business and
    `data_check`'s question about a built page.
    """
    with io.open(path, encoding="utf-8", newline="") as handle:
        text = handle.read()
    found = data_check.reads_of(text)
    bare, asked = set(), set()
    for path_bits in found:
        head = path_bits[0]
        if data_check.protected(path_bits, found):
            asked.add(head)
        else:
            bare.add(head)
    # A key read bare anywhere is required, whatever else asks about it politely elsewhere.
    return sorted(bare), sorted(asked - bare)


def survey():
    """The record as the tree currently stands."""
    rows = []
    for path in builders():
        name = os.path.basename(path)
        with io.open(path, encoding="utf-8", newline="") as handle:
            source = handle.read()
        found = TEMPLATE.search(source)
        template = found.group(1) if found else None
        made = OUTPUT.search(source)

        row = {
            "builder": name,
            "builder_digest": digest(path),
            "template": template,
            "template_digest": None,
            "writes": made.group(1) if made else None,
            "requires": [],
            "optional": [],
        }
        if template:
            where = os.path.join(HERE, template)
            row["template_digest"] = digest(where)
            if os.path.exists(where):
                row["requires"], row["optional"] = template_reads(where)
        rows.append(row)
    return {"viewers": rows}


def load():
    if not os.path.exists(RECORD):
        return None
    with io.open(RECORD, encoding="utf-8") as handle:
        return json.load(handle)


def save(record):
    with io.open(RECORD, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(record, indent=2, sort_keys=True) + "\n")


def differences(recorded, live):
    """What moved, as a list of sentences, each naming a builder and a field."""
    was = {}
    for row in (recorded or {}).get("viewers", []):
        was[row.get("builder")] = row
    out = []

    for row in live["viewers"]:
        name = row["builder"]
        old = was.pop(name, None)
        if old is None:
            out.append("%s is new and not in the record" % name)
            continue
        for field in ("template", "writes", "builder_digest", "template_digest"):
            if old.get(field) != row.get(field):
                if field.endswith("_digest"):
                    out.append("%s: %s changed" % (name, field[:-7]))
                else:
                    out.append("%s: %s was %r and is now %r"
                               % (name, field, old.get(field), row.get(field)))
        for field in ("requires", "optional"):
            if sorted(old.get(field) or []) != sorted(row.get(field) or []):
                gained = sorted(set(row.get(field) or []) - set(old.get(field) or []))
                lost = sorted(set(old.get(field) or []) - set(row.get(field) or []))
                said = []
                if gained:
                    said.append("gained " + ", ".join(gained))
                if lost:
                    said.append("lost " + ", ".join(lost))
                out.append("%s: %s %s" % (name, field, " and ".join(said)))

    for name in sorted(was):
        out.append("%s is in the record and no longer in the tree" % name)
    return out


def by_template(live):
    """Which builders share each template, putting a number on the reach of one edit."""
    out = {}
    for row in live["viewers"]:
        if row["template"]:
            out.setdefault(row["template"], []).append(row["builder"])
    return out


def check():
    live = survey()
    recorded = load()
    lines = []
    failed = 0

    shared = by_template(live)
    lines.append("  %d builders over %d templates" % (len(live["viewers"]), len(shared)))
    for template in sorted(shared):
        kin = shared[template]
        lines.append("    %-28s %d builder(s)%s"
                     % (template, len(kin), "" if len(kin) == 1 else ": " + ", ".join(kin)))
    lines.append("")

    # A builder pointing at a template that is not there. Nothing else about that row can be trusted.
    for row in live["viewers"]:
        if not row["template"]:
            lines.append("  %s NAMES NO TEMPLATE" % row["builder"])
            failed += 1
        elif row["template_digest"] is None:
            lines.append("  %s names %s, which is not in this directory"
                         % (row["builder"], row["template"]))
            failed += 1

    if recorded is None:
        lines.append("  NO RECORD at %s" % os.path.relpath(RECORD, ROOT))
        lines.append("    a first record is written with --write, and checked in, so that a page")
        lines.append("    changing without the record changing is a change nobody wrote down")
        failed += 1
    else:
        moved = differences(recorded, live)
        if moved:
            lines.append("  %d difference(s) between the tree and the record" % len(moved))
            for one in moved:
                lines.append("    %s" % one)
            lines.append("    rewrite with --write when the change is one you meant")
            failed += len(moved)
        else:
            lines.append("  the tree matches the record in every field")

    sys.stdout.write("\n".join(lines) + "\n\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


# A record and a tree that differ in one field each, so every branch of `differences` is exercised
# against an answer known before it runs.
KNOWN_WAS = {"viewers": [
    {"builder": "build_a.py", "template": "one_template.html", "writes": "a.html",
     "builder_digest": "aa", "template_digest": "tt", "requires": ["shell"], "optional": []},
    {"builder": "build_gone.py", "template": "one_template.html", "writes": "g.html",
     "builder_digest": "gg", "template_digest": "tt", "requires": [], "optional": []},
]}

KNOWN_NOW = {"viewers": [
    {"builder": "build_a.py", "template": "one_template.html", "writes": "a.html",
     "builder_digest": "aa", "template_digest": "TT", "requires": ["shell", "clock"], "optional": []},
    {"builder": "build_new.py", "template": "one_template.html", "writes": "n.html",
     "builder_digest": "nn", "template_digest": "TT", "requires": [], "optional": []},
]}


def _check():
    lines = []
    failed = 0

    moved = differences(KNOWN_WAS, KNOWN_NOW)
    joined = " | ".join(moved)
    wants = (("template changed", "a template edit is reported"),
             ("gained clock", "a new required key is reported"),
             ("build_new.py is new", "a builder absent from the record is reported"),
             ("build_gone.py is in the record", "a builder that left the tree is reported"))
    for token, why in wants:
        ok = token in joined
        lines.append("  %s: %s" % (why, "yes" if ok else "NO"))
        if not ok:
            failed += 1

    same = differences(KNOWN_WAS, KNOWN_WAS)
    lines.append("  a record against itself reports %d difference(s)" % len(same))
    if same:
        failed += 1

    # The reads split has to agree with data_check on a page data_check already grades, or the two
    # tools disagree about the same template and the record means nothing.
    room = os.path.join(HERE, "room_view_template.html")
    if os.path.exists(room):
        need, ask = template_reads(room)
        lines.append("  room template: %d required, %d optional" % (len(need), len(ask)))
        lines.append("    required: %s" % ", ".join(need))
        lines.append("    optional: %s" % ", ".join(ask))
        if "clock" in need:
            lines.append("    FAIL clock is guarded everywhere and must not be required")
            failed += 1
    else:
        lines.append("  the room template is not here, so the split was not graded")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d gate check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="every viewer in one record")
    parser.add_argument("--write", action="store_true", help="rewrite the record from the tree")
    parser.add_argument("--check", action="store_true", help="grade this tool on known cases")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.write:
        save(survey())
        sys.stdout.write("wrote %s\n" % os.path.relpath(RECORD, ROOT))
        sys.exit(0)
    sys.exit(1 if check() else 0)
