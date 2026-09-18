#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Tests for the register stages of docs_check.py: the two tiers, what stands behind each one, and
# the reporting text.
#
#   Usage:  python maint/prose/test_docs_check_tiers.py
#
# THE FIRST TEST IN THIS FILE IS THE GOVERNING ONE. The two SKILL.md files ARE the standard. A gate
# that reports either of them on vocabulary is wrong by construction, whatever it found. That
# one assertion catches the whole over-reach class without anybody enumerating it, and it is why
# thirteen bare word bans came out of the table instead of thirteen exemptions going in.
#
# Read the note above docs_check.AUTHORITY before changing anything here. The tier a pattern is in
# is decided by the sentence in the standard and never by the shape of the regex.
#
# Every count asserted here is derived when the test runs. A constant is correct on the day it is
# written and wrong on the day the tree moves, and hand-carried numbers in this tree have been wrong
# repeatedly. Where a fixture is pinned to a revision, the revision is printed with whether it is
# reachable from anywhere but this machine.

import os
import re
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import docs_check

SKILLS = os.path.join(os.path.expanduser("~"), ".claude", "skills")
STANDARDS = {
    "code-documentation": os.path.join(SKILLS, "code-documentation", "SKILL.md"),
    "code-comments": os.path.join(SKILLS, "code-comments", "SKILL.md"),
}


def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read().splitlines()


def findings(path):
    """Every prose finding docs_check would print for one file, as (line, text).

    Calls the same three functions main() calls, with the same arguments. A test cannot pass
    against a reading of the file that main() never performs.
    """
    lines = read(path)
    said = docs_check.prose_only(path, lines)
    return docs_check.banned_tokens(
        said,
        quotations=path.endswith(".md"),
        comments=not path.endswith((".md", ".tex")),
    )


def sibling_repository(name):
    """A repository checked out beside this one, or None.

    Resolved through main_checkout() and not __file__. A linked worktree computing sibling paths from
    __file__ lands inside .claude/ and finds nothing. Commit 915b3a9 landed that fix and this inherits it.
    """
    named = os.environ.get(name.upper() + "_TREE")
    if named:
        return named if os.path.isdir(named) else None
    beside = os.path.join(os.path.dirname(docs_check.main_checkout()), name)
    return beside if os.path.isdir(beside) else None


def describe_ref(tree):
    """The revision a measurement was taken at, and whether it is reachable anywhere but here."""
    try:
        head = (
            subprocess.check_output(
                ["git", "rev-parse", "--short", "HEAD"],
                cwd=tree,
                stderr=subprocess.PIPE,
            )
            .decode("utf-8", "replace")
            .strip()
        )
        remote = (
            subprocess.check_output(
                ["git", "branch", "-r", "--contains", "HEAD"],
                cwd=tree,
                stderr=subprocess.PIPE,
            )
            .decode("utf-8", "replace")
            .strip()
        )
    except (OSError, subprocess.CalledProcessError):
        return "no git history"
    return "%s (%s)" % (
        head,
        remote.splitlines()[0].strip() if remote else "NOT PUSHED",
    )


class StandardsPassTheCheckerTheyAuthorize(unittest.TestCase):
    """THE GOVERNING TEST. Neither standard is reported on vocabulary by the gate it names.

    WHY VOCABULARY AND NOT EVERYTHING, because the boundary is what the test is for.

    TIER B is vocabulary. A TIER B hit on one of these files is the checker telling the author of
    the standard that his own word choice is machine prose, and the document he wrote is the thing
    that decides what machine prose is. It is always wrong. That is asserted at zero.

    TIER A is a construction each document bans in a sentence. A TIER A hit on one of these files is
    the document using a construction it bans, which is a real finding about real prose and is the
    author's to decide. Eleven stand on code-documentation/SKILL.md and eight on
    code-comments/SKILL.md as this is written, mostly `rather`. They are reported, not exempted, and
    test_tier_a_findings_are_reported_and_named holds the line against anyone quieting them to make
    this class green.

    THE EM DASHES ARE NOT THIS TEST'S TO SETTLE. Both files carry em dashes, 24 and 19, and those
    are STRUCTURAL findings from em_dashes() that do fail a build. code-documentation:109 bans the
    em dash by name and hard. The checker is right and the documents violate their own rule 43
    times. Fixing them is a change to Douglas's standards and is his call. The count is asserted
    below only so that a silent change to it is visible.
    """

    def setUp(self):
        for path in STANDARDS.values():
            if not os.path.isfile(path):
                self.skipTest("the standards are not installed at %s" % SKILLS)

    def test_no_tier_b_vocabulary_finding_on_either_standard(self):
        for name, path in STANDARDS.items():
            got = [
                (at, what) for at, what in findings(path) if what.startswith("tier B")
            ]
            self.assertEqual(
                got,
                [],
                "%s is the standard this checker enforces. A TIER B vocabulary finding on it is "
                "the gate over-reaching, never the document failing:\n  %s"
                % (
                    name,
                    "\n  ".join("%s:%d %s" % (name, at, what) for at, what in got),
                ),
            )

    def test_no_spelling_finding_on_either_standard(self):
        # code-documentation:149 is the sentence that defines the house convention. A British hit
        # on it would mean the alphabet stage disagrees with the rule that wrote it.
        for name, path in STANDARDS.items():
            got = [what for _, what in findings(path) if what.startswith("spelling ")]
            self.assertEqual(got, [], "%s reported on spelling: %s" % (name, got))

    def test_tier_a_findings_are_reported_and_named(self):
        # The other half of the governing test, and the half that stops the first half being
        # satisfied by turning the gate off. Every remaining finding on these two files is TIER A
        # and carries the section that bans it, and a reader can go and read the sentence.
        for name, path in STANDARDS.items():
            got = findings(path)
            self.assertTrue(
                got,
                "%s reports nothing at all, which means the gate stopped "
                "reading it rather than agreeing with it" % name,
            )
            for at, what in got:
                self.assertTrue(
                    what.startswith("tier A "),
                    "%s:%d is neither TIER A nor exempt: %s" % (name, at, what),
                )
                self.assertIn(
                    "banned at ",
                    what,
                    "%s:%d is TIER A and names no sentence: %s" % (name, at, what),
                )
        print(
            "\n  standards after the tier split: %s"
            % ", ".join(
                "%s %d TIER A" % (name, len(findings(path)))
                for name, path in STANDARDS.items()
            )
        )

    def test_em_dashes_are_the_standards_own_rule_and_are_not_quieted(self):
        # Recorded, not argued here. em_dashes() is a different rule in a different stage and
        # nothing in the tier work touches it. If this number moves, either somebody edited the
        # standards or somebody quieted the rule, and the two are not the same thing.
        counted = {
            name: len(docs_check.em_dashes(docs_check.prose_only(path, read(path))))
            for name, path in STANDARDS.items()
        }
        self.assertTrue(
            all(one > 0 for one in counted.values()),
            "an em dash count fell to zero: %s" % counted,
        )
        print("\n  em dashes in the standards, structural and unresolved: %s" % counted)


class TierIsDecidedByTheSentence(unittest.TestCase):
    """The tier comes from the standard, never from the shape of the regex."""

    def test_rather_is_tier_a_although_it_is_one_word(self):
        # code-documentation:110 and code-comments:200 ban it outright. stage_of calls it a word
        # because it holds no space, and the tier disagrees with it deliberately.
        self.assertEqual(docs_check.stage_of(r"\brather\b"), "word")
        self.assertEqual(docs_check.tier_of(r"\brather\b"), "A")

    def test_superlative_group_is_tier_b_although_it_spans_words(self):
        group = (
            r"\b(stellar|superb|phenomenal|tremendous|immense|enormous|staggering)\b"
        )
        self.assertIn(group, docs_check.BANNED)
        self.assertEqual(docs_check.tier_of(group), "B")

    def test_every_authority_entry_names_a_live_pattern(self):
        # The import-time guard already raises on drift. This asserts the guard's condition
        # directly. A later edit that removes the guard then fails a test and not a run.
        orphans = [one for one in docs_check.AUTHORITY if one not in docs_check.BANNED]
        self.assertEqual(
            orphans, [], "AUTHORITY names patterns BANNED does not hold: %s" % orphans
        )

    def test_every_authority_entry_cites_a_standard_and_a_line(self):
        for pattern, where in docs_check.AUTHORITY.items():
            self.assertRegex(
                where,
                r"code-(documentation|comments):\d+",
                "AUTHORITY[%r] does not cite a section: %r" % (pattern, where),
            )

    def test_locale_patterns_are_neither_tier(self):
        for pattern in docs_check.LOCALE:
            self.assertEqual(docs_check.tier_of(pattern), "alphabet")
            self.assertNotIn(pattern, docs_check.AUTHORITY)

    def test_the_table_holds_no_pattern_twice(self):
        # One rule in two places is two rules that can be edited apart. \band nothing else\b was
        # written twice and only the dedupe in banned_hits kept it from doubling every finding.
        seen = [
            one for one in set(docs_check.BANNED) if docs_check.BANNED.count(one) > 1
        ]
        self.assertEqual(seen, [], "BANNED holds a pattern more than once: %s" % seen)


class EveryRuleAgainstTheSentenceThatStatesIt(unittest.TestCase):
    """Each phrase the standards ban BY NAME, in a carrier sentence, run through the checker.

    This is the test that found the transcription failures, and it found four that nobody had
    pointed at: `make clear` missing from a verb list both files spell out, both of section 146's
    own X-not-Y examples falling outside all three X-not-Y patterns because each wanted a copula and
    an article, and the `spelling` token ban demoted to a construction ban.

    A transcription failure is never isolated to the instances somebody noticed. This is a table
    and not three assertions.
    """

    # (carrier sentence, the phrase the standard names, where it names it)
    #
    # docs-check: quoting
    NAMED = (
        (
            "The colon is what separates them.",
            "is what separates",
            "code-documentation:126",
        ),
        (
            "The guard is what holds the invariant.",
            "is what holds",
            "code-documentation:126",
        ),
        (
            "The flag is what decides the branch.",
            "is what decides",
            "code-documentation:126",
        ),
        (
            "The bound is what makes the walk finite.",
            "is what makes",
            "code-comments:205",
        ),
        (
            "The token makes clear that the payload follows.",
            "make clear",
            "code-documentation:147",
        ),
        (
            "The token announces the end of the frame.",
            "announces",
            "code-documentation:147",
        ),
        ("Declared, not allocated.", "X-not-Y, bare", "code-documentation:146"),
        ("A number, not a guess.", "X-not-Y, bare", "code-documentation:146"),
        (
            "The pool is a cache and never a buffer.",
            "is a P and never a Q",
            "code-documentation:127",
        ),
        (
            "It reports the count and nothing more.",
            "and nothing more",
            "code-documentation:128",
        ),
        ("It reports the count and no more.", "and no more", "code-documentation:128"),
        (
            "It reports the count and nothing else.",
            "and nothing else",
            "code-comments:207",
        ),
        (
            "That is the one place the bound is set.",
            "the one place",
            "code-documentation:129",
        ),
        (
            "The header is the one thing the loader reads.",
            "the one thing",
            "code-comments:207",
        ),
        (
            "This is the whole of what the call does.",
            "the whole of what",
            "code-documentation:130",
        ),
        ("That is the whole of the contract.", "the whole of the", "code-comments:207"),
        (
            "It is precisely the bound the header sets.",
            "is precisely the",
            "code-documentation:131",
        ),
        (
            "The alignment is what matters most.",
            "that matters most",
            "code-documentation:131",
        ),
        ("What matters is the alignment.", "what matters is", "code-documentation:131"),
        (
            "The size is the one that matters.",
            "the one that matters",
            "code-documentation:116",
        ),
        ("That is what survives a reset.", "what survives", "code-documentation:120"),
        ("The counts add up to the header length.", "add up", "code-documentation:110"),
        ("The pool is drained. A caller sees nothing.", "so a", "code-comments:200"),
        # The inflection. Unmatched until 2026-09-16 because the pattern implemented the token and
        # code-documentation:112 describes the clause. It fails against `\bso a\b` and passes
        # against `\bso an?\b`, the only reason this row is worth a line.
        ("The pool is drained. An entry is dropped.", "so an", "code-comments:200"),
        ("The bound is read here.", "rather", "code-comments:200"),
        ("The spelling is wrong in three places.", "spelling", "code-comments:200"),
        (
            "The pool is sized here, the bound the caller sees.",
            "the",
            "code-comments:206",
        ),
        (
            "It frees the block, which is what the caller asked for.",
            "which is what",
            "code-comments:206",
        ),
        (
            "It frees the block, which is why the pool shrinks.",
            "which is why",
            "code-comments:206",
        ),
    )
    # docs-check: end quoting

    def test_every_phrase_the_standards_name_is_caught(self):
        missed = [
            (phrase, where, sentence)
            for sentence, phrase, where in self.NAMED
            if not list(docs_check.banned_hits([sentence], comments=True))
        ]
        self.assertEqual(
            missed,
            [],
            "the standards name these by name and the table does not reach them:\n  %s"
            % "\n  ".join("%s (%s): %s" % one for one in missed),
        )

    def test_every_phrase_the_standards_name_is_tier_a(self):
        # At least one TIER A pattern has to fire, not every pattern that fires. A carrier sentence
        # can trip a house shape on the way past. The carrier for `what survives` also matches the
        # unnamed that-is-what clause, and only the first has a sentence in a standard behind it.
        # Both are reported, and the tier separates them.
        wrong = []
        for sentence, phrase, where in self.NAMED:
            tiers = {
                docs_check.tier_of(pattern)
                for _, pattern, _ in docs_check.banned_hits([sentence], comments=True)
            }
            if "A" not in tiers:
                wrong.append((phrase, where, sorted(tiers)))
        self.assertEqual(
            wrong,
            [],
            "a construction the standard bans by name is scored as vocabulary:\n  %s"
            % "\n  ".join("%s (%s) fired only as %s" % one for one in wrong),
        )

    def test_spelling_is_scoped_to_comments_by_its_own_sentence(self):
        # code-comments:200: "none has a legitimate use in a comment here". The scope is in the
        # sentence. The code carries it. A page about a character encoding writes the word.
        said = ["The spelling of the identifier is what the linker sees."]
        self.assertTrue(list(docs_check.banned_hits(said, comments=True)))
        self.assertEqual(
            [
                one
                for one in docs_check.banned_hits(said, comments=False)
                if one[1] == r"\bspelling\b"
            ],
            [],
        )

    def test_the_mid_sentence_appositive_is_left_alone(self):
        # Section 146 permits the contrast where a reader would otherwise land on the wrong one.
        said = [
            "The bound is read in the header, not in the .c, and the caller never sees it."
        ]
        hits = [
            token
            for _, pattern, token in docs_check.banned_hits(said)
            if ", not " in pattern
        ]
        self.assertEqual(
            hits, [], "the mid-sentence appositive was reported: %s" % hits
        )


class TierBIsBoundedToConstructions(unittest.TestCase):
    """Section 143: a word that reads as a tic in one construction is bounded to that construction.

    The thirteen bare word bans that used to sit in BANNED are the reason this class exists. Each
    of them fired on the standards' own prose, and eleven of the thirteen are used by one or both
    standards as ordinary technical English in the documents that authorize this tool.
    """

    # The sentence in the standard that each withdrawn word appears in. Quoted and not cited,
    # because what has to be visible is that the standard USES the word and a citation alone does not show that.
    THE_STANDARDS_OWN_USE = (
        ("carries", "carries this list as regexes"),
        ("holds", "holds the list as regexes"),
        ("reads", "reads .c and .h comments and docstrings, not only .md"),
        ("spends", "it spends a reader's trust before it wastes their time"),
        (
            "buys",
            "breaks the line the prose is walking and buys nothing the reader asked for",
        ),
        ("construction", "are essay construction, not comment construction"),
        ("slots", "the slots are already the explanation"),
        ("earned", "each one earned its place by measurement"),
    )

    def test_the_standards_own_sentences_are_not_reported(self):
        for word, sentence in self.THE_STANDARDS_OWN_USE:
            hits = [
                token
                for _, _, token in docs_check.banned_hits([sentence], comments=True)
            ]
            self.assertNotIn(
                word,
                [one.lower() for one in hits],
                "%r is reported, and the standard writes it: %r" % (word, sentence),
            )

    def test_the_construction_is_still_caught(self):
        # What the bare bans were reaching for, bounded. The is-what-VERB family is the construction
        # both standards name, and the withdrawn verbs went into it.
        for sentence in (
            "The manifest is what carries the digest.",
            "The column is what holds the year.",
            "The header is what reads the length.",
            "The retry is what costs the round.",
        ):
            hits = list(docs_check.banned_hits([sentence]))
            self.assertTrue(
                hits, "the bounded construction was not caught: %r" % sentence
            )
            self.assertEqual({docs_check.tier_of(one[1]) for one in hits}, {"A"})

    def test_the_plain_technical_verb_is_left_standing(self):
        for sentence in (
            "The header carries the checksum.",
            "The buffer holds the segment.",
            "The parser reads the option list.",
            "A retry costs one round trip.",
        ):
            hits = [token for _, _, token in docs_check.banned_hits([sentence])]
            self.assertEqual(
                hits,
                [],
                "a correct technical verb was reported in %r: %s" % (sentence, hits),
            )

    def test_withdrawn_records_every_word_that_came_out(self):
        # The table is the record. A later reader who meets only the absence puts the ban back.
        for word in (
            "carry",
            "hold",
            "read",
            "slot",
            "cost",
            "buy",
            "pay",
            "spend",
            "earn",
            "afford",
            "win",
            "price",
            "book",
            "construction",
        ):
            self.assertIn(word, docs_check.WITHDRAWN)
            self.assertTrue(
                len(docs_check.WITHDRAWN[word]) > 40,
                "WITHDRAWN[%r] gives a rule and no reason" % word,
            )

    def test_no_withdrawn_word_is_banned_bare_again(self):
        # The shape that must not come back: a pattern that matches the word in any context at all.
        for word in docs_check.WITHDRAWN:
            for pattern in docs_check.BANNED:
                if re.fullmatch(
                    r"\\b%s(?:\(\?:[^)]*\)|\[[^\]]*\])?\??\\b" % word, pattern
                ):
                    self.fail("%r is banned bare again by %r" % (word, pattern))


class NamedSpansAreNamesAndNotUses(unittest.TestCase):
    """A token a document sets off in backticks, italics or quotes is being NAMED, not used."""

    def test_a_backticked_token_is_not_a_use(self):
        said = ["The list bans `rather` in every form."]
        self.assertEqual(list(docs_check.banned_hits(said, quotations=True)), [])

    def test_the_same_token_outside_the_span_is_a_use(self):
        said = ["The bound is read here."]
        self.assertTrue(list(docs_check.banned_hits(said, quotations=True)))

    def test_an_italic_citation_is_not_a_use(self):
        said = ["It opens the consequence clause every time: *so a build is asked*."]
        self.assertEqual(list(docs_check.banned_hits(said, quotations=True)), [])

    def test_a_short_quoted_form_is_not_a_use(self):
        # Ten characters. PASSAGE needs sixteen, and these walked past it.
        said = ['Avoid *"Certainly!"* and *"load-bearing"* in a file a person wrote.']
        self.assertEqual(list(docs_check.banned_hits(said, quotations=True)), [])

    def test_italic_does_not_straddle_a_table_cell(self):
        # ProtoCore TUNING.md:154. Two unrelated asterisks in different cells paired across the row
        # and swallowed a real `so a`. A citation of a form does not cross a cell boundary.
        said = ["| *a* | tracks `MAX_CONNS`, a raised pool never trips it | *b* |"]
        hits = [token for _, _, token in docs_check.banned_hits(said, quotations=True)]
        self.assertIn("so a", [one.lower() for one in hits])

    def test_bold_is_not_exempt(self):
        # Bold marks a heading far more often than a citation here. It exempted one site on the
        # standards and five in ProtoCore/docs, three of which were real TIER A findings inside a
        # heading label. The arm came out and this holds it out.
        said = ["- **Why it is deferred."]
        hits = [
            token.lower()
            for _, _, token in docs_check.banned_hits(said, quotations=True)
        ]
        self.assertIn("rather", hits)

    def test_a_backtick_span_is_exempt_in_a_comment_too(self):
        # Not bounded to markdown. A comment names a symbol in backticks the same way a page does.
        self.assertEqual(
            list(docs_check.banned_hits(["# the `rather` pattern fires here"])), []
        )


class TheReportSaysWhatItMeasured(unittest.TestCase):
    """Reporting text. Each of these lines prevented a real confusion.

    The largest of them: the unmeasured branch printed "unused in 1.1M human words" on 3,981
    of 4,296 prose lines in this tree's own default run. 1,108,054 is the UNGATED token count that
    the table's own header says is the wrong denominator, the measured branch eleven lines away was
    already dividing by 759,815, and the corpus behind both is 154 Salishan linguistics papers and
    not a general sample of English. Wrong number, wrong corpus, on 92.7 percent of the output.
    """

    def test_the_1_1m_claim_is_gone_from_the_source(self):
        with open(docs_check.__file__, encoding="utf-8") as handle:
            source = handle.read()
        emitted = re.findall(r'"[^"\n]*1\.1M[^"\n]*"', source)
        self.assertEqual(
            emitted, [], "a report string still claims 1.1M human words: %s" % emitted
        )

    def test_every_unmeasured_finding_names_the_corpus(self):
        said = ["The retry is what costs the round and nothing more."]
        got = docs_check.banned_tokens(said)
        self.assertTrue(got)
        for _, what in got:
            self.assertNotIn("human words", what)
            if "not seen in" in what or "per 100k" in what:
                self.assertIn(docs_check.CORPUS, what)

    def test_the_corpus_is_named_by_its_gated_english_size(self):
        # 759,815 is the papers after english_gate takes them down to English. 1,108,054 is the raw
        # token count including Salishan orthography, glosses and IPA, and every rate divided by it
        # was low by about 40 percent.
        self.assertIn("759,815", docs_check.CORPUS)
        self.assertNotIn("1,108,054", docs_check.CORPUS)
        self.assertNotIn("1.1M", docs_check.CORPUS)

    def test_a_tier_a_finding_names_the_section_that_bans_it(self):
        got = docs_check.banned_tokens(["The bound is read here."])
        self.assertEqual(len(got), 1)
        self.assertIn("tier A", got[0][1])
        self.assertIn("code-documentation:110", got[0][1])

    def test_a_measured_tier_b_finding_carries_its_rate(self):
        got = docs_check.banned_tokens(["The result is a remarkable improvement."])
        self.assertTrue(got)
        self.assertIn("per 100k in %s" % docs_check.CORPUS, got[0][1])


class ProseNeverFailsABuild(unittest.TestCase):
    """Verbatim in both standards, in the same sentence that names this tool.

    "A hit is a prose finding. It never fails a build, because a person has to decide each site: a
    proper name, a quoted title, or a term of art is left standing and reported as a false
    positive."  code-documentation:145, and code-comments:208 says it again.

    Asserted by running the tool, not by reading main(), because the contract is about the exit
    status a commit hook sees.
    """

    def run_tool(self, *where):
        done = subprocess.run(
            [sys.executable, os.path.join(HERE, "docs_check.py")] + list(where),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        return done.returncode, done.stdout.decode("utf-8", "replace")

    def test_a_tier_a_finding_alone_does_not_fail(self):
        for name, path in STANDARDS.items():
            if not os.path.isfile(path):
                self.skipTest("the standards are not installed")
        # The standards carry em dashes, which are structural. They are the wrong fixture for
        # this. idemIP/src is the right one: thousands of prose findings and no structural finding.
        tree = sibling_repository("idemIP")
        if not tree or not os.path.isdir(os.path.join(tree, "src")):
            self.skipTest("idemIP is not checked out beside this tree")
        where = os.path.join(tree, "src")
        status, said = self.run_tool(where)
        breaking = [
            one for one in said.splitlines() if one.strip().startswith("BREAK ")
        ]
        prose = [one for one in said.splitlines() if one.strip().startswith("prose ")]
        print(
            "\n  idemIP/src at %s: %d breaking, %d prose, exit %d"
            % (describe_ref(tree), len(breaking), len(prose), status)
        )
        self.assertEqual(breaking, [], "the fixture stopped being prose-only")
        self.assertTrue(
            len(prose) > 100, "the fixture stopped producing prose findings"
        )
        self.assertEqual(
            status,
            0,
            "%d prose findings and no structural finding exited %d. Both standards "
            "say a prose hit never fails a build." % (len(prose), status),
        )

    def test_strict_is_the_cleanup_pass_and_does_fail(self):
        tree = sibling_repository("idemIP")
        if not tree or not os.path.isdir(os.path.join(tree, "src")):
            self.skipTest("idemIP is not checked out beside this tree")
        status, _ = self.run_tool(os.path.join(tree, "src"), "--strict")
        self.assertEqual(
            status, 1, "--strict is the mode a cleanup pass wants and it did not fail"
        )

    def test_anchor_sift_itself_is_held_to_the_same_contract(self):
        # Named because the brief for this tool has been read the other way before. anchor_sift owns
        # the checker and gets no stricter a setting than any repository it is pointed at.
        tier_a = [one for one in docs_check.BANNED if docs_check.tier_of(one) == "A"]
        self.assertTrue(tier_a)
        source = open(docs_check.__file__, encoding="utf-8").read()
        self.assertIn(
            "if breaking or (strict and prose):",
            source,
            "the exit rule moved. Prose must not reach the exit status without --strict",
        )


class TheStructuralStageIsUntouched(unittest.TestCase):
    """A guard for the work beside this one. It cannot be quietly undone here.

    The structural repair to dead_links() and everything commit 915b3a9 landed in the private-root
    block are outside this pass's scope, and a rebuild of the token table drops them
    without anyone deciding to.
    """

    def test_dead_links_still_has_its_path_candidate_gate(self):
        self.assertTrue(hasattr(docs_check, "path_candidate"))
        self.assertFalse(docs_check.path_candidate("@ref HTTP_10"))
        self.assertFalse(
            docs_check.path_candidate("const char *user, const char *pass")
        )
        self.assertTrue(docs_check.path_candidate("docs/README.md"))

    def test_the_private_survey_still_answers_in_two_halves(self):
        held, absent = docs_check.private_survey()
        self.assertEqual(len(held) + len(absent), len(docs_check.PRIVATE_NAMES))
        print("\n  private roots: %d held, %d absent" % (len(held), len(absent)))

    def test_locale_and_checked_were_not_this_pass_and_have_since_been_done(self):
        # This test used to assert ten patterns and five extensions, because both were known gaps
        # and both belonged to the coverage pass. That pass has landed.
        # The assertion is kept and inverted instead of deleted: it still says the two are not this
        # pass's to define, and it now fails if a rebuild of the token table takes the coverage work
        # back out with it. test_docs_check_coverage.py holds what those two are for.
        self.assertGreater(len(docs_check.LOCALE), 10)
        for one in (".md", ".py", ".c", ".h", ".tex"):
            self.assertIn(one, docs_check.CHECKED)
        self.assertTrue(docs_check.build_file("CMakeLists.txt"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
