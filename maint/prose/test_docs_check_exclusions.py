#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The exclusion layer and the reporting lines, checked instead of remembered.
#
#   Usage:  python maint/prose/test_docs_check_exclusions.py
#
# Standalone unittest, no pytest dependency, same as the three suites beside it.
#
# WHAT THESE TESTS ARE FOR. Every exclusion in docs_check is a rule that makes the tool report LESS,
# and a rule that makes a checker report less is the easiest kind of rule to get wrong and the
# hardest kind to notice being wrong. A wrong exclusion reports a clean tree. So each one here is
# asserted from both ends: what it silences and what it must NOT silence.
#
# EVERY COUNT IS DERIVED AT RUN TIME AND NONE IS WRITTEN DOWN. The manifest row count, the British
# convention cost, the legal block cost and the generated region membership are all measured from
# the tree when the test runs, and the ref they were measured at is printed with its reachability.
# Numbers hand-carried through this tree have been wrong repeatedly: the brief for this work said a
# manifest held 2028 rows and a read pass said 2029, and both were describing the same file with the
# header row counted differently.

import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import docs_check as dc  # noqa: E402


def sibling_repository(name):
    """A repository beside this one, or None.

    Resolved through docs_check.main_checkout() and not through __file__. This suite inherits
    the worktree repair.
    """
    named = os.environ.get("%s_TREE" % name.upper())
    if named:
        return named if os.path.isdir(named) else None
    base = dc.main_checkout()
    owned = os.path.dirname(os.path.dirname(base))
    for where in (
        os.path.join(owned, "public", name),
        os.path.join(owned, "private", name),
        os.path.join(os.path.dirname(base), name),
    ):
        if os.path.isdir(where):
            return where
    return None


def ref_of(where):
    """`<revision> (<reachability>)` for a checkout, for printing beside a measurement.

    Section 5's first rule. A count without its revision is a count about an unspecified tree, and
    a revision that no remote contains is a tree of one.
    """
    answer = dc.tree_ref(where)
    if not answer:
        return "no revision"
    return "%s (%s)" % (answer[1], answer[2])


PROTOCORE = sibling_repository("ProtoCore")
IDEMIP = sibling_repository("idemIP")
CORPUS = sibling_repository("salishan_corpus")


def findings_in(path, regions=None):
    """Every prose finding in one file, through the same path main() takes."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    said = dc.prose_only(path, lines)
    return dc.banned_tokens(
        said,
        quotations=path.endswith(".md"),
        comments=not path.endswith((".md", ".tex")),
        path=path,
        regions=regions,
    )


# ============================================================================
# 1. THE SHAPE EVERY EXCLUSION SHARES
# ============================================================================


class EveryExclusionRefusesAndSaysSo(unittest.TestCase):
    """A skip that says nothing is the failure this whole section exists against.

    private_survey's docstring records the case that earned it: the scan covered zero closed
    repositories for the whole of a directory migration, and nobody could see it, because "scanned
    none" and "there are none" printed the same nothing.
    """

    def test_a_declined_file_is_named_by_the_run_that_declined_it(self):
        if not IDEMIP:
            self.skipTest("idemIP is not checked out beside this one")
        corpus = os.path.join(IDEMIP, "docs", "learn", "RFC")
        if not os.path.isdir(corpus):
            self.skipTest("the RFC corpus is not in this checkout")
        ledger = dc.Ledger()
        kept = dc.walk_markdown([corpus], ledger)
        self.assertEqual(kept, [], "no file under a verbatim root is read")
        self.assertGreater(ledger.total(), 0, "and every one of them is named")
        printed = "\n".join(ledger.report())
        self.assertIn("verbatim third-party", printed)
        self.assertIn("RFC Editor", printed, "the reason travels with the count")

    def test_the_exclusion_applies_with_no_ledger_to_record_it(self):
        """Recording is optional. The rule never is.

        A caller that has not been taught about the ledger must not be able to turn an exclusion off
        by forgetting to pass one, which is how an optional argument becomes an optional rule.
        """
        if not IDEMIP:
            self.skipTest("idemIP is not checked out beside this one")
        corpus = os.path.join(IDEMIP, "docs", "learn", "RFC")
        if not os.path.isdir(corpus):
            self.skipTest("the RFC corpus is not in this checkout")
        self.assertEqual(dc.walk_markdown([corpus]), [])

    def test_the_ledger_keeps_the_sites_and_not_only_a_count(self):
        ledger = dc.Ledger()
        ledger.note("a rule", "a reason", "a/site.md:1")
        ledger.note("a rule", "a reason", "a/site.md:9")
        ledger.note("another rule", "another reason", "b/site.md:1")
        self.assertEqual(ledger.total(), 3)
        printed = "\n".join(ledger.report())
        self.assertIn("a/site.md:1", printed)
        self.assertIn("a/site.md:9", printed)
        self.assertIn("a rule: 2, a reason", printed)

    def test_the_ledger_holds_its_rules_in_first_appearance_order(self):
        ledger = dc.Ledger()
        ledger.note("second", "why", "x")
        ledger.note("first", "why", "y")
        ledger.note("second", "why", "z")
        self.assertEqual([one[0] for one in ledger.order], ["second", "first"])


# ============================================================================
# 2. VERBATIM THIRD-PARTY TEXT, AS A CONCEPT AND NOT A PATH LIST
# ============================================================================


class VerbatimThirdPartyIsANamedConcept(unittest.TestCase):
    """Somebody else's words, reproduced byte for byte.

    Three instances were found independently, which is what makes this a concept. The test that
    matters most is the marker one: a path list is a chore somebody has to remember to extend, and
    the way a chore fails is that a fourth corpus arrives and nobody adds it.
    """

    def test_a_directory_declares_itself_with_a_marker_and_no_list_is_touched(self):
        import tempfile

        with tempfile.TemporaryDirectory() as where:
            vendored = os.path.join(where, "a_corpus_this_tool_has_never_heard_of")
            os.makedirs(vendored)
            inside = os.path.join(vendored, "someone_elses.md")
            with open(inside, "w", encoding="utf-8") as handle:
                handle.write("# a document\n")
            self.assertIsNone(
                dc.verbatim_root(inside), "not verbatim before the directory says so"
            )
            dc._VERBATIM_CACHE.clear()
            with open(
                os.path.join(vendored, dc.VERBATIM_MARKER), "w", encoding="utf-8"
            ) as handle:
                handle.write("the IETF's, not ours\n")
            held = dc.verbatim_root(inside)
            dc._VERBATIM_CACHE.clear()
            self.assertIsNotNone(
                held, "the marker is the second answer to the question"
            )
            self.assertIn(dc.VERBATIM_MARKER, held[1])

    def test_every_default_root_is_matched_on_the_path(self):
        for one, why in dc.VERBATIM_ROOTS:
            held = dc.verbatim_root("/a/tree/%s/a_file.md" % one)
            self.assertIsNotNone(held, "%s is a default root and did not match" % one)
            self.assertEqual(held[1], why, "the reason travels with the root")

    def test_every_default_root_carries_more_than_one_path_component(self):
        """A bare directory name is not distinctive enough to be a rule.

        `oracles` alone would match any directory anywhere with that name, and this tree has a
        build/papers that is a different thing from the corpus papers/.
        """
        for one, _ in dc.VERBATIM_ROOTS:
            self.assertIn(
                "/",
                one.strip("/"),
                "%r is one component and would match too much" % one,
            )

    def test_every_default_root_states_a_reason_and_not_only_a_rule(self):
        for one, why in dc.VERBATIM_ROOTS:
            self.assertGreater(
                len(why.split()),
                4,
                "%s has a rule and no reason, which is what gets deleted" % one,
            )

    def test_a_path_outside_every_root_is_read(self):
        self.assertIsNone(dc.verbatim_root(os.path.join(HERE, "docs_check.py")))

    def test_the_ietf_corpus_is_declined(self):
        if not IDEMIP:
            self.skipTest("idemIP is not checked out beside this one")
        corpus = os.path.join(IDEMIP, "docs", "learn", "RFC")
        if not os.path.isdir(corpus):
            self.skipTest("the RFC corpus is not in this checkout")
        held = os.listdir(corpus)
        print(
            "\n  idemIP docs/learn/RFC at %s: %d file(s), all declined"
            % (ref_of(IDEMIP), len(held))
        )
        self.assertEqual(dc.walk_markdown([corpus]), [])

    def test_the_transcribed_tables_are_declined(self):
        if not CORPUS:
            self.skipTest("the closed corpus is not in this checkout")
        oracles = os.path.join(CORPUS, "oracles")
        if not os.path.isdir(oracles):
            self.skipTest("oracles/ is not in this checkout")
        readable = [one for one in os.listdir(oracles) if dc.checked_file(one)]
        print(
            "  salishan_corpus/oracles: %d file(s) this tool could otherwise open, all declined"
            % len(readable)
        )
        self.assertGreater(len(readable), 0, "and there is something to decline")
        self.assertEqual(dc.walk_markdown([oracles]), [])

    def test_the_cost_is_named_and_it_is_two_files_of_our_own(self):
        """The rule takes two of this project's own index pages with the corpora they index.

        Named here. The
        alternative is an allowlist inside each verbatim root, which is a second list to maintain
        for two files.
        """
        ours = []
        if IDEMIP:
            ours.append(os.path.join(IDEMIP, "docs", "learn", "RFC", "README.md"))
        if PROTOCORE:
            ours.append(
                os.path.join(PROTOCORE, "docs", "learn", "datasheets", "README.md")
            )
        held = [one for one in ours if os.path.isfile(one)]
        if not held:
            self.skipTest("neither index page is in this checkout")
        for one in held:
            self.assertIsNotNone(
                dc.verbatim_root(one), "%s goes quiet with the corpus it indexes" % one
            )
        print("  cost of the verbatim rule: %d index page(s) of our own" % len(held))


# ============================================================================
# 3. SIGNED MANIFESTS
# ============================================================================


class SignedManifestsAreRefusedAndNeverSkipped(unittest.TestCase):
    """The most dangerous exclusion here, and the only one whose cost is not a question of taste.

    Changing one byte of a hashed file makes its hash wrong, fails the reconcile the corpus runs
    before every commit, and invalidates a signature whose purpose is to attest what a published
    measurement was taken over.
    """

    def setUp(self):
        if not CORPUS:
            self.skipTest("the closed corpus is not in this checkout")
        self.manifest = os.path.join(CORPUS, "MANIFEST.tsv")
        if not os.path.isfile(self.manifest):
            self.skipTest("MANIFEST.tsv is not in this checkout")

    def test_the_manifests_are_found_and_the_row_count_is_derived_not_written_down(
        self,
    ):
        home = dc.manifest_home(os.path.join(CORPUS, "oracles"))
        self.assertEqual(os.path.abspath(home), os.path.abspath(CORPUS))
        index = dc.manifest_index(home)
        by_manifest = {}
        for held in index.values():
            by_manifest[os.path.basename(held[0])] = (
                by_manifest.get(os.path.basename(held[0]), 0) + 1
            )
        print("\n  salishan_corpus at %s attests: %s" % (ref_of(CORPUS), by_manifest))
        self.assertGreater(
            len(index), 100, "a manifest this small means it did not parse"
        )
        # Counted against the file, independently of the parser being tested.
        with open(self.manifest, encoding="utf-8", errors="replace") as handle:
            rows = [
                one
                for one in handle
                if one.strip() and not one.startswith("#") and "\t" in one
            ]
        self.assertEqual(
            by_manifest["MANIFEST.tsv"],
            len(rows) - 1,
            "every row but the column header names an attested path",
        )

    def test_both_manifests_carry_a_detached_signature(self):
        signed = []
        for name in dc.MANIFEST_NAMES:
            where = os.path.join(CORPUS, name)
            if not os.path.isfile(where):
                continue
            signature = where + dc.SIGNATURE_SUFFIX
            self.assertTrue(
                os.path.isfile(signature),
                "%s is attested by nothing. The refusal has no force" % name,
            )
            signed.append(name)
        print("  signed manifests present: %s" % ", ".join(signed))
        self.assertGreater(len(signed), 1)

    def test_a_listed_path_is_refused_for_rewriting_and_the_manifest_is_named(self):
        listed = sorted(dc.manifest_index(CORPUS))
        readable = [one for one in listed if dc.checked_file(one)]
        if not readable:
            self.skipTest("nothing attested carries an extension this tool reads")
        where = os.path.join(CORPUS, readable[0].replace("/", os.sep))
        why = dc.fix_refusal(where, "alphabet")
        self.assertIsNotNone(why, "an attested path is never rewritten")
        self.assertIn("MANIFEST", why, "and the refusal names the manifest")
        self.assertIn(".asc", why, "and the signature that would be invalidated")

    def test_the_refusal_carries_the_reconcile_command_from_the_manifest_itself(self):
        """Lifted from the manifest header. It cannot drift from the tool that maintains it."""
        said = dc.reconcile_command(self.manifest)
        print("  reconcile command, as the manifest states it: %s" % said)
        self.assertIn(".py", said, "it names the tool that reconciles the tree")
        with open(self.manifest, encoding="utf-8", errors="replace") as handle:
            header = "".join(one for one in handle if one.startswith("#"))
        self.assertIn(
            said, header, "and it is quoted from the file and not written out here"
        )

    def test_reading_is_not_writing(self):
        """A listed file is read and reported like any other. Only the rewrite is refused.

        Reporting changes no bytes. There is nothing for the hashes to disagree with, and a
        corpus that goes unread is a corpus nobody can check.
        """
        home = dc.manifest_home(os.path.join(CORPUS, "README.md"))
        self.assertIsNotNone(home)
        self.assertIsNone(
            dc.manifest_listed(os.path.join(CORPUS, "README.md")),
            "the README is not attested. This test is about the others",
        )
        listed = [one for one in dc.manifest_index(home) if dc.checked_file(one)]
        if not listed:
            self.skipTest("nothing attested carries an extension this tool reads")
        where = os.path.join(home, listed[0].replace("/", os.sep))
        self.assertIsNotNone(dc.manifest_listed(where))
        with open(where, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
        # prose_only answers for an attested file exactly as it answers for any other.
        self.assertEqual(len(dc.prose_only(where, lines)), len(lines))

    def test_an_unlisted_path_in_the_same_tree_is_not_refused_on_that_ground(self):
        where = os.path.join(CORPUS, "README.md")
        if not os.path.isfile(where):
            self.skipTest("the corpus README is not in this checkout")
        why = dc.fix_refusal(where, "alphabet")
        if why:
            self.assertNotIn("attested", why)

    def test_the_manifest_walk_stops_at_a_repository_boundary(self):
        """A manifest attests one repository. A parent holding several is not that repository."""
        self.assertIsNone(
            dc.manifest_home(HERE),
            "this tree carries no manifest and must not inherit the corpus one",
        )


# ============================================================================
# 4. LEGAL BLOCKS
# ============================================================================


class LegalBlocksAreBlankedPerBlockAndNotPerLine(unittest.TestCase):
    """A GPL grant is fifteen lines and two of them hold anything a regex can find.

    Where the block ends is the whole rule, and getting it wrong in either direction has a cost that
    was measured before this landed.
    """

    def test_the_two_tier_fixture_keeps_both_of_its_licence_sites(self):
        """idemIP strip_comments.py, the sharpest fixture available, with both halves in one file.

        :2-3 is a real copyright and SPDX pair and is not ours to edit. :4 and :12 say `licence` in
        prose ABOUT a license block, four lines and eleven lines below it, and :4 sits directly
        under the header with no blank line between them. A block rule reaching one line too far
        takes :4 with the header.
        """
        if not IDEMIP:
            self.skipTest("idemIP is not checked out beside this one")
        where = os.path.join(IDEMIP, "tools", "dev_env", "strip_comments.py")
        if not os.path.isfile(where):
            self.skipTest("strip_comments.py is not in this checkout")
        at = sorted(one for one, what in findings_in(where) if "licence" in what)
        print(
            "\n  idemIP strip_comments.py at %s: licence reported at %s"
            % (ref_of(IDEMIP), at)
        )
        self.assertEqual(at, [4, 12])

    def test_the_second_half_of_the_fixture_keeps_both_of_its_sites(self):
        if not IDEMIP:
            self.skipTest("idemIP is not checked out beside this one")
        where = os.path.join(IDEMIP, "tools", "dev_env", "readclean.py")
        if not os.path.isfile(where):
            self.skipTest("readclean.py is not in this checkout")
        at = sorted(one for one, what in findings_in(where) if "licence" in what)
        self.assertEqual(at, [12, 36])

    def test_the_legal_block_itself_is_blanked_and_named(self):
        if not IDEMIP:
            self.skipTest("idemIP is not checked out beside this one")
        where = os.path.join(IDEMIP, "tools", "dev_env", "strip_comments.py")
        if not os.path.isfile(where):
            self.skipTest("strip_comments.py is not in this checkout")
        with open(where, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
        ledger = dc.Ledger()
        said = dc.prose_only(where, lines, ledger)
        self.assertEqual(said[1], "", "the copyright line is blanked")
        self.assertEqual(said[2], "", "and so is the SPDX line beside it")
        self.assertNotEqual(said[3].strip(), "", "and the docstring under them is not")
        printed = "\n".join(ledger.report())
        self.assertIn("legal block", printed)
        self.assertIn(":1-3", printed, "the span is named, not only the count")

    def test_a_bare_comment_marker_separates_two_blocks(self):
        """The regression this rule was rewritten for, guarded by name.

        A first attempt split blocks on blank SOURCE lines. A `#` alone on a line is not blank,
        an entire comment header read as one block: 164 findings went quiet across this tree alone,
        among them six hits in a file about orthography. Emptiness is measured on the MARKER-stripped
        text instead, the same test runs() already makes.
        """
        said = [
            "#!/usr/bin/env python3",
            "# a project - Copyright (C) 2026 Somebody <nobody@example.com>",
            "# SPDX-License-Identifier: AGPL-3.0-or-later",
            "#",
            "# The header carries a crucial myriad of things, the point.",
        ]
        kept = dc.legal_blank(said)
        self.assertEqual(kept[:3], ["", "", ""], "the legal block goes")
        self.assertIn("crucial", kept[4], "and the prose under the separator stays")

    def test_a_doxygen_file_block_under_an_spdx_block_is_still_read(self):
        """The comment standard puts the @file block directly under the SPDX block with no blank.

        Without the comment-form and close tests the two read as one, and every @file brief in every
        C file in every tree here would go unchecked.
        """
        said = [
            "/* a project - Copyright (C) 2026 Somebody <nobody@example.com>",
            " * SPDX-License-Identifier: AGPL-3.0-or-later",
            " */",
            "/**",
            " * @file ring_buffer.h",
            " * @brief A crucial myriad of frames, which is what makes it work.",
            " */",
        ]
        kept = dc.legal_blank(said)
        self.assertEqual(kept[:3], ["", "", ""], "the license block goes")
        self.assertIn("crucial", kept[5], "and the @file block beneath it does not")

    def test_a_file_with_no_legal_line_is_returned_unchanged(self):
        said = ["# a comment", "# another", "", "# a third"]
        self.assertEqual(dc.legal_blank(said), said)

    def test_the_rule_silences_nothing_in_the_trees_on_disk(self):
        """Derived at run time over a bounded scope, and re-derive it after any change here.

        Zero is the outcome to want from a rule whose job is to protect an artifact and not to hide
        a backlog. A block walker reaching too far reports the same zero on this test and 164
        findings on the tree, which is why the two boundary tests above are asserted by shape.
        """
        roots = [os.path.join(dc.REPOSITORY, "maint")]
        if IDEMIP:
            roots.append(os.path.join(IDEMIP, "tools"))
        roots = [one for one in roots if os.path.isdir(one)]
        silenced = 0
        read = 0
        for path in sorted(dc.walk_markdown(roots)):
            read += 1
            with open(path, encoding="utf-8", errors="replace") as handle:
                lines = handle.read().splitlines()
            raw = dc.prose_only(path, lines)
            blanked = set()
            for start, stop in dc.comment_blocks(raw):
                if any(dc.LEGAL.search(one) for one in raw[start:stop]):
                    blanked.update(range(start + 1, stop + 1))
            if not blanked:
                continue
            quotations = path.endswith(".md")
            comments = not path.endswith((".md", ".tex"))
            for at, _, _ in dc.banned_hits(raw, quotations, comments):
                if at in blanked:
                    silenced += 1
        print(
            "  legal blanking over %d file(s): %d finding(s) silenced"
            % (read, silenced)
        )
        self.assertEqual(silenced, 0)


# ============================================================================
# 5. GENERATED REGIONS
# ============================================================================


class GeneratedRegionsAreAttributedAndNeverSuppressed(unittest.TestCase):
    """The one decision here a reader is likely to want to reverse. It is tested hardest.

    The structural pass that landed before this one wrote its instruction into the assertion a
    suppressing rule would break: the single genuine structural finding in the whole of
    ProtoCore/docs sits inside a generated region. Skipping marked regions deletes the finding
    this objective asks to be asserted and reports that tree clean.
    """

    def test_both_marker_shapes_are_read(self):
        lines = [
            "before",
            "<!-- BEGIN GENERATED CONFIG-OVERRIDES (tools/ci_tooling/generate/gen_sections.py) -->",
            "inside the first",
            "<!-- END GENERATED CONFIG-OVERRIDES -->",
            "between",
            "<!-- BEGIN GENERATED test-environments (edit test_matrix.json, run harness.py gen) -->",
            "inside the second",
            "<!-- END GENERATED test-environments -->",
            "after",
        ]
        inside, complaints = dc.generated_regions(lines)
        self.assertEqual(complaints, [])
        self.assertEqual(inside[3], "tools/ci_tooling/generate/gen_sections.py")
        self.assertEqual(inside[7], "edit test_matrix.json, run harness.py gen")
        self.assertNotIn(1, inside)
        self.assertNotIn(5, inside)
        self.assertNotIn(9, inside)

    def test_an_unclosed_marker_is_reported_and_not_allowed_to_swallow_the_file(self):
        lines = [
            "before",
            "<!-- BEGIN GENERATED THING (gen.py) -->",
            "inside",
            "still inside",
        ]
        inside, complaints = dc.generated_regions(lines)
        self.assertEqual(len(complaints), 1)
        self.assertEqual(complaints[0][0], 2)
        self.assertIn("no END GENERATED", complaints[0][1])
        self.assertIn(3, inside)

    def test_a_finding_inside_a_region_keeps_its_place_and_names_the_generator(self):
        note = dc.attributed(
            "table header with no rows under it", 4, {4: "gen_sections.py"}
        )
        self.assertIn("table header with no rows under it", note)
        self.assertIn("gen_sections.py", note)
        self.assertIn("fix the generator", note)

    def test_a_finding_outside_a_region_carries_no_attribution(self):
        self.assertEqual(
            dc.attributed("a finding", 9, {4: "gen_sections.py"}), "a finding"
        )

    def test_the_protocore_empty_table_is_still_reported_and_is_still_inside_a_region(
        self,
    ):
        """Asserted BY SITE and not by count.

        A count falling to the right number for the wrong reason reads exactly like a repair. This
        one names the file, the line, the finding and the generator.
        """
        if not PROTOCORE:
            self.skipTest("ProtoCore is not checked out beside this one")
        where = os.path.join(PROTOCORE, "docs", "README.md")
        if not os.path.isfile(where):
            self.skipTest("ProtoCore docs/README.md is not in this checkout")
        with open(where, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
        inside, complaints = dc.generated_regions(lines)
        self.assertEqual(complaints, [], "every marker in this file is closed")
        empty = dc.empty_tables(lines)
        print(
            "\n  ProtoCore docs/README.md at %s: %d header-only table(s), %d line(s) generated"
            % (ref_of(PROTOCORE), len(empty), len(inside))
        )
        self.assertGreater(
            len(empty),
            0,
            "the genuine structural finding this rule must not delete is gone. If "
            "it was fixed in ProtoCore, say so and retire this assertion; do not "
            "make a suppressing rule pass by deleting the finding it suppressed.",
        )
        for at, what in empty:
            self.assertIn(
                at,
                inside,
                "docs/README.md:%d is the finding this objective asks to be asserted "
                "and it sits inside a generated region. A rule that SKIPS a marked "
                "region deletes it and reports this tree clean. Report it and name the "
                "generator from the marker." % at,
            )
            note = dc.attributed(what, at, inside)
            self.assertIn("gen_readme_sections.py", note)

    def test_the_generated_rule_removed_no_breaking_finding_from_protocore(self):
        """The whole-tree arm of the same guard, run as a subprocess the way a hook runs it."""
        if not PROTOCORE:
            self.skipTest("ProtoCore is not checked out beside this one")
        docs = os.path.join(PROTOCORE, "docs")
        if not os.path.isdir(docs):
            self.skipTest("ProtoCore docs/ is not in this checkout")
        answer = subprocess.run(
            [sys.executable, os.path.join(HERE, "docs_check.py"), docs],
            capture_output=True,
            text=True,
            env=dc.git_env(),
        )
        breaking = [
            one for one in answer.stdout.splitlines() if one.strip().startswith("BREAK")
        ]
        print(
            "  ProtoCore/docs at %s: %d breaking finding(s)"
            % (ref_of(PROTOCORE), len(breaking))
        )
        self.assertGreater(
            len(breaking),
            0,
            "a generated-region rule that takes the breaking count to zero has "
            "suppressed the finding it was supposed to attribute",
        )
        named = [one for one in breaking if "generated by" in one]
        self.assertGreater(
            len(named), 0, "and at least one of them names its generator"
        )

    def test_a_site_inside_a_region_is_refused_for_rewriting(self):
        why = dc.fix_refusal("a/page.md", "alphabet", 4, {4: "gen_sections.py"})
        self.assertIsNotNone(why)
        self.assertIn("gen_sections.py", why)
        self.assertIn(
            "regeneration",
            why,
            "a source fix not paired with regeneration reds the pull request",
        )


# ============================================================================
# 6. OBJECTIVE 13's CLAUSE: UNLESS THE SUBJECT IS BRITISH
# ============================================================================


class TheSubjectIsTheConvention(unittest.TestCase):
    """A passage about a writing convention has to be able to write the word it is about.

    Bounded to the alphabet tier and to the run, which is what keeps it from being a bypass.
    """

    def test_a_passage_about_the_convention_may_write_the_word(self):
        said = [
            "# British English writes colour and behaviour where American writes color."
        ]
        found = [what for _, what in dc.banned_tokens(said, comments=True)]
        self.assertEqual(
            [one for one in found if one.startswith("spelling")],
            [],
            "the subject of the sentence is the convention itself",
        )

    def test_the_same_passage_still_reports_a_construction(self):
        """The bound is the test. A paragraph about convention does not get a register pass."""
        said = [
            "# British spelling is what makes the difference. A reader has to know."
        ]
        found = [what for _, what in dc.banned_tokens(said, comments=True)]
        self.assertTrue(
            any(one.startswith("tier A") for one in found),
            "only the alphabet tier goes quiet, never a construction",
        )

    def test_the_subject_is_the_convention_and_not_the_country(self):
        """A bare country name would exempt a company, and the company's prose is a live finding."""
        said = ["# British Telecom asked for an optimisation of the initialised path."]
        found = [what for _, what in dc.banned_tokens(said, comments=True)]
        self.assertTrue(
            any(one.startswith("spelling") for one in found),
            "the subject here is a company. The convention is still reported",
        )

    def test_the_exemption_is_bounded_to_the_run_that_carries_the_subject(self):
        said = [
            "# British spelling writes colour.",
            "",
            "# The optimisation runs once.",
        ]
        at = [
            one
            for one, what in dc.banned_tokens(said, comments=True)
            if what.startswith("spelling")
        ]
        self.assertEqual(
            at, [3], "the next paragraph is a different run and is reported"
        )

    def test_context_exempt_answers_with_a_tier_set_and_not_a_boolean(self):
        self.assertEqual(
            dc.context_exempt("British English writes colour"), frozenset(("alphabet",))
        )
        self.assertEqual(dc.context_exempt("an ordinary sentence"), frozenset())

    def test_the_clause_silences_nothing_in_the_trees_on_disk(self):
        """Derived at run time. Nothing in any tree here writes about the convention today.

        The rule is the objective's own clause written down before a document needs it, the
        opposite of the usual order and is why the number is asserted.
        """
        roots = [os.path.join(dc.REPOSITORY, "maint")]
        if PROTOCORE:
            roots.append(os.path.join(PROTOCORE, "docs"))
        roots = [one for one in roots if os.path.isdir(one)]
        silenced = 0
        read = 0
        for path in sorted(dc.walk_markdown(roots)):
            read += 1
            with open(path, encoding="utf-8", errors="replace") as handle:
                lines = handle.read().splitlines()
            said = dc.prose_only(path, lines)
            quotations = path.endswith(".md")
            comments = not path.endswith((".md", ".tex"))
            for text, offsets in dc.runs(said):
                if not (offsets and dc.context_exempt(text)):
                    continue
                for _, pattern, _ in dc.banned_hits([text], quotations, comments):
                    if dc.tier_of(pattern) == "alphabet":
                        silenced += 1
        print(
            "\n  the convention clause over %d file(s): %d finding(s) silenced"
            % (read, silenced)
        )
        self.assertEqual(silenced, 0)

    def test_the_standards_rule_is_a_rewrite_refusal_and_not_a_scan_exemption(self):
        """Measured out.

        Exempting a run for naming a standard silenced 1,733 findings in one tree unbounded and 20
        bounded to the alphabet tier, and every one of the 20 was ordinary prose in a paragraph that
        happened to cite an RFC. It bought nothing: the site it was written for, "Robustness
        Variable" in an RFC 2236 brief, matches no pattern in LOCALE and produced no finding.
        """
        said = [
            "# RFC 2236 section 8.1 describes the behaviour of the initialised timer."
        ]
        found = [what for _, what in dc.banned_tokens(said, comments=True)]
        self.assertTrue(
            any(one.startswith("spelling") for one in found),
            "naming a standard does not turn the convention stage off",
        )
        why = dc.fix_refusal("a/file.c", "alphabet", line=said[0])
        self.assertIsNotNone(why, "but the line is never rewritten")
        self.assertIn("standard", why)


# ============================================================================
# 7. A BANNED HINGE IS DISSOLVED AND NEVER REPLACED
# ============================================================================


class NothingIsRewrittenThatIsNotTokenForToken(unittest.TestCase):
    """Detection is mechanical. Substitution is where the judgement lives.

    A construction ban targets a rhetorical move and not a word. The nearest synonym preserves
    the move and lands on another banned item. `rather` is banned at code-documentation:110 and the
    X-not-Y shape that repairs it is banned at :146 of the same document.
    """

    def test_the_alphabet_tier_is_the_only_tier_a_rewrite_may_reach(self):
        self.assertEqual(
            dc.FIX_TIERS,
            frozenset(("alphabet",)),
            "read code-documentation:110 and :146 before widening this",
        )

    def test_every_construction_tier_is_refused_with_the_sections_that_say_so(self):
        for tier in ("A", "B"):
            why = dc.fix_refusal("a/file.md", tier)
            self.assertIsNotNone(why)
            self.assertIn("code-documentation:110", why)
            self.assertIn(":146", why)
            self.assertIn("permanently", why)

    def test_a_plain_convention_finding_is_allowed(self):
        self.assertIsNone(
            dc.fix_refusal(os.path.join(HERE, "nothing_special.md"), "alphabet")
        )

    def test_the_two_tier_line_splits(self):
        """idemIP strip_comments.py:12 carries a `licence` and a `rather` on one line.

        That single line is the sharpest available statement of where a rewrite may go and where it
        may not: the convention half is token for token, and the construction half is report-only
        forever.
        """
        if not IDEMIP:
            self.skipTest("idemIP is not checked out beside this one")
        where = os.path.join(IDEMIP, "tools", "dev_env", "strip_comments.py")
        if not os.path.isfile(where):
            self.skipTest("strip_comments.py is not in this checkout")
        with open(where, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
        said = dc.prose_only(where, lines)
        verdicts = {}
        for at, pattern, token in dc.banned_hits(said, comments=True, path=where):
            if at != 12:
                continue
            tier = dc.tier_of(pattern)
            verdicts[token.lower()] = dc.fix_refusal(where, tier, at, {}, lines[at - 1])
        print(
            "\n  idemIP strip_comments.py:12 at %s: %s"
            % (ref_of(IDEMIP), sorted(verdicts))
        )
        self.assertIn("licence", verdicts)
        self.assertIn("rather", verdicts)
        self.assertIsNone(
            verdicts["licence"], "token for token, and the shape cannot change"
        )
        self.assertIsNotNone(
            verdicts["rather"], "a hinge is dissolved and never replaced"
        )

    def test_a_line_carrying_a_normative_keyword_is_never_rewritten(self):
        why = dc.fix_refusal(
            "a/file.c",
            "alphabet",
            line="// The sender MUST NOT retransmit the initialised segment.",
        )
        self.assertIsNotNone(why)
        self.assertIn("2119", why)

    def test_the_normative_keyword_test_is_case_sensitive(self):
        """ "this may be null" is prose. "the sender MAY retransmit" is a requirement."""
        self.assertIsNone(
            dc.fix_refusal(
                os.path.join(HERE, "plain.md"), "alphabet", line="the value may be null"
            )
        )
        self.assertIsNotNone(
            dc.fix_refusal("a/file.c", "alphabet", line="the sender MAY retransmit")
        )

    def test_the_source_states_the_limit_where_a_maintainer_will_look_for_it(self):
        """A rule with no reason beside it is the kind a later maintainer finishes.

        This one reads as an unimplemented feature and is a permanent limit. The reasoning has to
        sit at the constant a person would edit.
        """
        with open(os.path.join(HERE, "docs_check.py"), encoding="utf-8") as handle:
            body = handle.read()
        head = body[: body.index("FIX_TIERS = ")]
        note = head[head.index("WHAT A REWRITE MAY TOUCH") :]
        for wanted in ("code-documentation:110", ":146", "permanently", "X-not-Y"):
            self.assertIn(wanted, note, "the note above FIX_TIERS drops %r" % wanted)


# ============================================================================
# 8. THE REPORT SAYS WHAT IT MEASURED
# ============================================================================


class TheReportSaysWhatItMeasured(unittest.TestCase):
    """Three lines, and each one prevented a real confusion.

    A run reporting "0 findings" over two configured roots reads exactly like a clean tree, and that
    is how a repository carrying dozens of British spellings reads as green.
    """

    def run_on(self, *args):
        answer = subprocess.run(
            [sys.executable, os.path.join(HERE, "docs_check.py")] + list(args),
            capture_output=True,
            text=True,
            env=dc.git_env(),
        )
        return answer.stdout

    def test_the_roots_are_printed_before_any_finding(self):
        said = self.run_on(os.path.join(HERE, "docs_check.py"))
        lines = [one.strip() for one in said.splitlines() if one.strip()]
        self.assertTrue(
            lines[0].startswith("roots configured:"),
            "a reader meets the scope before the count, and got %r" % lines[0],
        )

    def test_a_root_that_is_not_there_is_printed_as_not_found(self):
        said = self.run_on(os.path.join(HERE, "no_such_directory_anywhere"))
        self.assertIn(
            "NOT FOUND",
            said,
            "a missing root reads as zero findings and must never read as clean",
        )

    def test_the_revision_is_printed_with_its_reachability(self):
        said = self.run_on(os.path.join(HERE, "docs_check.py"))
        measured = [one for one in said.splitlines() if "measured at" in one]
        print("\n  %s" % "\n  ".join(one.strip() for one in measured))
        self.assertEqual(len(measured), 1)
        self.assertTrue(
            ("reachable from" in measured[0]) or ("NOT PUSHED" in measured[0]),
            "a revision no remote contains is a tree of one and has to say so",
        )

    def test_the_private_footer_from_the_worktree_repair_still_prints(self):
        """Carried forward from the commit that landed it, and guarded here because a rebuild of
        the report is exactly what drops it. Its own docstring records the third occurrence of the
        failure it prevents."""
        said = self.run_on("--strict", os.path.join(HERE, "docs_check.py"))
        self.assertNotIn(
            "private roots scanned",
            said,
            "a named root is a scoped run and does not survey the closed repositories",
        )
        held, absent = dc.private_survey()
        print("  private roots: %d held, %d absent" % (len(held), len(absent)))
        self.assertEqual(len(held) + len(absent), len(dc.PRIVATE_NAMES))

    def test_the_excluded_count_prints_even_when_it_is_zero(self):
        """ "excluded: 0" and a silence are the same two states private_survey exists to separate."""
        said = self.run_on(os.path.join(HERE, "docs_check.py"))
        self.assertIn("excluded:", said)

    def test_the_scope_sentence_names_the_axes_this_tool_does_not_answer_for(self):
        said = self.run_on(os.path.join(HERE, "docs_check.py"))
        self.assertIn("installed nowhere", said)
        self.assertIn("root(s) and nothing outside them", said)

    def test_the_fix_plan_writes_nothing_and_says_so(self):
        if not IDEMIP:
            self.skipTest("idemIP is not checked out beside this one")
        where = os.path.join(IDEMIP, "tools", "dev_env", "strip_comments.py")
        if not os.path.isfile(where):
            self.skipTest("strip_comments.py is not in this checkout")
        before = open(where, "rb").read()
        said = self.run_on("--fix", where)
        self.assertEqual(open(where, "rb").read(), before, "--fix wrote to the tree")
        self.assertIn("plan only", said)
        self.assertIn("REFUSED", said)
        self.assertIn("would rewrite", said)

    def test_the_fix_plan_prints_the_reconcile_command_in_a_tree_carrying_a_manifest(
        self,
    ):
        if not CORPUS:
            self.skipTest("the closed corpus is not in this checkout")
        where = os.path.join(CORPUS, "README.md")
        if not os.path.isfile(where):
            self.skipTest("the corpus README is not in this checkout")
        said = self.run_on("--fix", where)
        self.assertIn("signed manifest", said)
        self.assertIn(
            ".py", said, "and the instruction names the tool that reconciles the tree"
        )

    def test_prose_still_never_fails_a_build(self):
        """Verbatim in both standards, in the sentence that names this tool, and unchanged here.

        An exclusion layer is a place where an exit rule gets rewritten by accident.
        """
        answer = subprocess.run(
            [
                sys.executable,
                os.path.join(HERE, "docs_check.py"),
                os.path.join(HERE, "test_docs_check_exclusions.py"),
            ],
            capture_output=True,
            text=True,
            env=dc.git_env(),
        )
        breaking = [
            one for one in answer.stdout.splitlines() if one.strip().startswith("BREAK")
        ]
        prose = [
            one for one in answer.stdout.splitlines() if one.strip().startswith("prose")
        ]
        if breaking:
            self.skipTest(
                "this file carries a structural finding. The exit code is about that"
            )
        print(
            "  this suite reports %d prose finding(s) and exits %d"
            % (len(prose), answer.returncode)
        )
        self.assertEqual(answer.returncode, 0)


# ============================================================================
# 9. THE WORK BESIDE THIS ONE IS UNTOUCHED
# ============================================================================


class TheWorkBesideThisOneIsUntouched(unittest.TestCase):
    """Four passes have landed in this file. Each one guards the three before it."""

    def test_the_structural_gate_is_still_there(self):
        self.assertFalse(dc.path_candidate("@ref HTTP_10"))
        self.assertFalse(dc.path_candidate("const char *user, const char *pass"))
        self.assertTrue(dc.path_candidate("docs/README.md"))

    def test_private_survey_still_returns_both_halves(self):
        held, absent = dc.private_survey()
        self.assertEqual(len(held) + len(absent), len(dc.PRIVATE_NAMES))
        self.assertIn(
            "scanned none",
            dc.private_survey.__doc__,
            "the docstring records the regression and is the record of it",
        )

    def test_the_tiers_still_name_their_sections(self):
        self.assertEqual(dc.tier_of(r"\brather\b"), "A")
        self.assertIn(r"\brather\b", dc.AUTHORITY)

    def test_the_convention_stage_is_still_spliced_into_the_table_that_enforces_it(
        self,
    ):
        for one in dc.LOCALE:
            self.assertIn(one, dc.BANNED)

    def test_the_build_file_selection_still_reaches_a_name_and_a_hook(self):
        self.assertTrue(dc.checked_file("a/tree/CMakeLists.txt"))
        self.assertTrue(dc.checked_file("a/tree/.githooks/pre-commit"))

    def test_every_git_query_hands_off_the_callers_repository(self):
        """Git EXPORTS GIT_DIR to a hook, and a rev-parse inheriting it answers about that
        repository instead of the directory it was asked from.

        The worktree repair that landed --git-common-dir was written against this and the clearing
        did not come with it. A correct query kept giving a wrong answer under a hook. This pass
        added it, and the reporting lines depend on it: every one of them asks git a question about
        a directory it was handed.
        """
        for one in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
            self.assertIn(one, dc.GIT_HANDOFF)
        kept = dict(os.environ)
        kept["GIT_DIR"] = "somewhere/else/.git"
        was = os.environ.get("GIT_DIR")
        os.environ["GIT_DIR"] = "somewhere/else/.git"
        try:
            self.assertNotIn("GIT_DIR", dc.git_env())
        finally:
            if was is None:
                os.environ.pop("GIT_DIR", None)
            else:
                os.environ["GIT_DIR"] = was


if __name__ == "__main__":
    unittest.main(verbosity=2)
