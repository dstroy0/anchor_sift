#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Tests for the structural stage of docs_check.py. That stage fails a commit.
#
#   Usage:  python maint/prose/test_docs_check_structural.py
#
# The stage is not tiered and --strict does not reach it. A false positive here is a commit that
# cannot be made. These are the hardest assertions in the suite and the counts below are derived
# from the tree at run time.
#
# Every count this file asserts on is measured when the test runs. A constant would have been
# correct on the day it was written and wrong on the day the tree moved, and the whole reason the
# structural stage needed repairing is that nobody had measured it outside anchor_sift.

import os
import re
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import docs_check


def sibling_repository(name):
    """A repository checked out beside this one, or None.

    The environment variable is read first. A tree kept somewhere else is then still testable.
    main_checkout() answers where the siblings are, because a linked worktree computes them from
    the wrong directory when __file__ is used. Commit 915b3a9 landed that fix.
    """
    named = os.environ.get("PROTOCORE_TREE" if name == "ProtoCore" else name.upper() + "_TREE")
    if named:
        return named if os.path.isdir(named) else None
    beside = os.path.join(os.path.dirname(docs_check.main_checkout()), name)
    return beside if os.path.isdir(beside) else None


def describe_ref(tree):
    """The revision a measurement was taken at, and whether that revision is reachable anywhere.

    A count without its ref is a count about an unspecified tree. Two sessions read 58 British hits
    and 15 for the same repository, and the difference between them was two refs and no defect.

    Reachability is printed with it because a revision is authority only while somebody else can
    fetch it. A local-only commit is a tree of one, and a fixture pinned to a commit that lives in a
    worktree dies with the session that made it.
    """
    try:
        head = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"], cwd=tree, stderr=subprocess.PIPE
        ).decode("utf-8", "replace").strip()
        remote = subprocess.check_output(
            ["git", "branch", "-r", "--contains", "HEAD"], cwd=tree, stderr=subprocess.PIPE
        ).decode("utf-8", "replace").strip()
    except (OSError, subprocess.CalledProcessError):
        return "no git history"
    return "%s (%s)" % (head, remote.splitlines()[0].strip() if remote else "NOT PUSHED")


# An independent reading of the two structural rules that survive on ProtoCore/docs. These are
# written out here instead of imported. The assertion below measures the tree. Both count per
# line. A finding is reported at that granularity and a reader opens one line.
#
# The character is built from its code point. Writing it out would put an em dash in a tree that
# bans them, and docs_check would then report this file for the thing it tests for.
EM_DASH_CHARACTER = chr(0x2014)
TABLE_SEPARATOR = re.compile(r"^[ \t]*\|[-:| \t]+\|[ \t]*$")
TABLE_ROW = re.compile(r"^[ \t]*\|")


def derived_structural(root):
    """Em dash lines and header-only tables under a root, counted without calling docs_check.

    Returns (em_dashes, empty_tables). The prose view is taken from docs_check, since selecting
    which lines of a file count as prose belongs to the coverage stage. The two structural rules
    under test are re-implemented here.
    """
    dashes = 0
    tables = 0
    for path in sorted(docs_check.walk_markdown([root])):
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
        dashes += sum(1 for line in docs_check.prose_only(path, lines)
                      if EM_DASH_CHARACTER in line)
        if not path.endswith(".md"):
            continue
        for at, line in enumerate(lines):
            if not TABLE_SEPARATOR.match(line):
                continue
            under = lines[at + 1] if (at + 1) < len(lines) else ""
            if not TABLE_ROW.match(under):
                tables += 1
    return dashes, tables


class LinkTargetsThatAreNotPaths(unittest.TestCase):
    """path_candidate() refusing the two shapes that wear markdown link syntax."""

    def test_doxygen_reference_is_not_a_path(self):
        # Every one of these was read off ProtoCore's documents and six were confirmed as live
        # symbols in its source. The filesystem has no answer about any of them.
        for target in ("@ref HTTP_10", "@ref HttpVersion", "@ref HttpReq::version",
                       "@ref send_chunked", "@ref WS_FRAME_SIZE", "@ref MAX_HEADERS",
                       "@ref PROTOCORE_ENABLE_KEEPALIVE", "@ref protocore_config.h"):
            self.assertFalse(docs_check.path_candidate(target), target)

    def test_both_doxygen_spellings_are_refused(self):
        # Doxygen accepts the backslash form everywhere it accepts the at sign.
        self.assertFalse(docs_check.path_candidate("\\ref MAX_CONNS"))
        self.assertFalse(docs_check.path_candidate("@subpage porting"))

    def test_declarator_syntax_is_not_a_path(self):
        # The three targets that produced the three non-Doxygen breaking findings, verbatim.
        for target in ("uint8_t slot, HttpReq *req",
                       "const char *user, const uint8_t *blob, size_t len",
                       "const char *user, const char *pass"):
            self.assertFalse(docs_check.path_candidate(target), target)

    def test_declarator_with_no_pointer_star_is_not_a_path(self):
        # The parameter list neither the star rule nor the keyword rule reaches. Nothing in the five
        # trees measured has this shape, and it is covered because the next example written will.
        self.assertFalse(docs_check.path_candidate("uint8_t slot, size_t len"))

    def test_type_keyword_head_is_not_a_path(self):
        self.assertFalse(docs_check.path_candidate("const char *name"))
        self.assertFalse(docs_check.path_candidate("struct HttpReq request"))

    def test_a_directory_named_const_is_still_a_path(self):
        # The keyword rule wants the space after the keyword. A path segment spelled the same way
        # is untouched.
        self.assertTrue(docs_check.path_candidate("const/README.md"))

    def test_two_paths_separated_by_a_comma_are_still_checked(self):
        # The comma rule is bounded to items of two words each. A pair of paths has no interior
        # space in either item and stays a candidate.
        self.assertTrue(docs_check.path_candidate("docs/a.md, docs/b.md"))


class LinksStillChecked(unittest.TestCase):
    """The rule still doing the job it was written for. A repair that turns a check off is not one."""

    def setUp(self):
        self.here = os.path.join(HERE, "sample.md")

    def test_a_missing_relative_target_is_reported(self):
        found = docs_check.dead_links(self.here, ["see [the notes](no_such_file_here.md) for it"])
        self.assertEqual(len(found), 1)
        self.assertIn("no_such_file_here.md", found[0][1])
        self.assertEqual(found[0][0], 1)

    def test_a_target_that_is_there_is_not_reported(self):
        found = docs_check.dead_links(self.here, ["see [the checker](docs_check.py) for it"])
        self.assertEqual(found, [])

    def test_external_and_absolute_targets_are_left_alone(self):
        lines = ["[a](https://example.invalid/page)", "[b](/absolute/path.md)"]
        self.assertEqual(docs_check.dead_links(self.here, lines), [])

    def test_a_doxygen_reference_line_reports_nothing(self):
        # ProtoCore docs/README.md:2496, verbatim. Three findings on one line before the repair.
        line = ("| `version`        | [`HttpVersion`](@ref HttpVersion) | [`HTTP_10`](@ref HTTP_10)"
                ", [`HTTP_11`](@ref HTTP_11), or [`HTTP_UNKNOWN`](@ref HTTP_UNKNOWN) |")
        self.assertEqual(docs_check.dead_links(self.here, [line]), [])

    def test_a_lambda_in_an_example_reports_nothing(self):
        # ProtoCore docs/SECURITY.md:903 and docs/SSH.md:91 and :94, verbatim.
        lines = ['server.on("/diag", HTTP_GET, [](uint8_t slot, HttpReq *req) {',
                 "protocore_ssh_auth_set_pubkey_cb([](const char *user, const uint8_t *blob, "
                 "size_t len) {",
                 'protocore_ssh_auth_set_password_cb([](const char *user, const char *pass) {']
        self.assertEqual(docs_check.dead_links(self.here, lines), [])


class StandardsPassTheirOwnStructuralStage(unittest.TestCase):
    """The two documents that authorize this checker, against the stage of it that fails a commit.

    A gate that flags the standard it enforces is wrong by construction. This is the slice of that
    test belonging to dead_links. The em dash findings in both documents come from a different
    stage and are a decision for the author of those documents. They are reported and not
    asserted on. There are 43 of them at the time of writing, 24 in code-documentation/SKILL.md and
    19 in code-comments/SKILL.md, and code-documentation section 109 bans the em dash by name.
    """

    def skill_files(self):
        base = os.path.join(os.path.expanduser("~"), ".claude", "skills")
        found = [os.path.join(base, one, "SKILL.md")
                 for one in ("code-documentation", "code-comments")]
        return [one for one in found if os.path.isfile(one)]

    def test_no_dead_link_findings_in_either_standard(self):
        files = self.skill_files()
        if not files:
            self.skipTest("the two standards are not installed under ~/.claude/skills")
        for path in files:
            with open(path, encoding="utf-8", errors="replace") as handle:
                lines = handle.read().splitlines()
            self.assertEqual(docs_check.dead_links(path, lines), [], path)


class ProtoCoreStructuralStage(unittest.TestCase):
    """The whole stage against a Doxygen C repository, which is where it was measured to be wrong.

    anchor_sift is Python and markdown and uses no Doxygen. The rule is correct here and was
    never tested anywhere else. ProtoCore carries @ref throughout. Had this gate reached its
    pre-commit hook, ProtoCore could not have committed at all, and per-repo prose tiering would not
    have helped because the break is in the structural stage.
    """

    @classmethod
    def setUpClass(cls):
        cls.tree = sibling_repository("ProtoCore")
        if not cls.tree:
            return
        cls.docs = os.path.join(cls.tree, "docs")
        if not os.path.isdir(cls.docs):
            cls.tree = None
            return
        cls.ref = describe_ref(cls.tree)
        answer = subprocess.run(
            [sys.executable, os.path.join(HERE, "docs_check.py"), cls.docs],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        cls.output = answer.stdout.decode("utf-8", "replace")
        cls.status = answer.returncode
        cls.breaking = [one.strip() for one in cls.output.splitlines()
                        if one.strip().startswith("BREAK ")]
        sys.stderr.write("\n  ProtoCore/docs measured at %s: %d breaking finding(s)\n"
                         % (cls.ref, len(cls.breaking)))

    def setUp(self):
        if not self.tree:
            self.skipTest("ProtoCore is not checked out beside this repository")

    def test_no_breaking_finding_names_a_doxygen_reference(self):
        # 244 of 251 before the repair.
        named = [one for one in self.breaking if "@ref" in one or "\\ref" in one]
        self.assertEqual(named, [])

    def test_the_three_declarator_sites_are_clean(self):
        # SECURITY.md:903, SSH.md:91, SSH.md:94. Asserted by site and not by count, because a count
        # going to zero for the wrong reason reads the same as a repair.
        for site in ("SECURITY.md:903", "SSH.md:91", "SSH.md:94"):
            self.assertEqual([one for one in self.breaking if site in one], [], site)

    def test_breaking_total_equals_what_the_tree_holds(self):
        # Derived when the test runs, never a constant. TOOLKIT.md's three em dashes are queued for
        # repair and README.md's empty table is a generator defect. Every term of this sum is
        # expected to move and the assertion has to move with it.
        #
        # A NOTE FOR WHOEVER ADDS THE GENERATED-REGION RULE. ProtoCore docs/README.md:2404, the one
        # genuine structural finding in that whole tree, sits between the BEGIN and END GENERATED
        # markers at :2399 and :2408 for gen_readme_sections.py. A rule that SKIPS a marked region
        # deletes it and this test goes red, which is the test doing its job. Report the finding
        # with the generator named from the marker instead of suppressing it, and derived_structural
        # above has to learn the same rule on the same day or the two halves disagree.
        dashes, tables = derived_structural(self.docs)
        sys.stderr.write("  derived at %s: %d em dash line(s) + %d header-only table(s) = %d\n"
                         % (self.ref, dashes, tables, dashes + tables))
        self.assertEqual(len(self.breaking), dashes + tables)

    def test_the_stage_is_not_asserted_into_vacancy(self):
        # A tree with no structural findings at all would pass the test above whatever the code did.
        dashes, tables = derived_structural(self.docs)
        self.assertGreater(dashes + tables, 0)

    def test_the_exit_status_still_refuses_a_real_structural_finding(self):
        # Prose never fails a build. Structure does, and it has to keep doing so. ProtoCore/docs
        # holds genuine structural findings today. This run exits 1 for the right reason.
        dashes, tables = derived_structural(self.docs)
        self.assertEqual(self.status, 1 if (dashes + tables) else 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
