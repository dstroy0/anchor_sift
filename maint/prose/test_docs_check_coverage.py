#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Tests for what docs_check.py can open and what its alphabet stage can see.
#
#   Usage:  python maint/prose/test_docs_check_coverage.py
#
# Two gaps, one pass, and they are one pass because either one alone hides the other. A build file
# was outside every extension list, and the alphabet stage was ten literals where the standard
# states a pattern. idemIP's CMakeLists.txt is the fixture that shows why: `behaviour` at :123 was
# hidden by the extension alone and would have fired the moment the extension landed, and the three
# `optimisation` sites at :305, :311 and :321 were hidden twice. Fixing half of this is how an
# author reads a file as covered while three quarters of it stays invisible.
#
# Every count here is measured when the test runs, against a named revision, with whether that
# revision is reachable from a remote printed beside it. A hand-carried number in this tree has been
# wrong every time somebody carried one.
#
# WHAT THIS PASS IS NOT, stated because a green run of it must not be read as more than it is.
# Four independent reasons idemIP's British spellings survived, each sufficient on its own:
#   1. INSTALL. idemIP/.git/hooks holds fourteen files and every one ends in .sample. The gate is
#      declared in that repository's config and has never executed.
#   2. SCOPE. idemIP's repotools.toml declares roots = ["README.md", "test"] for both [prose] and
#      [hooks.docs_check]. src/ is not a prose root and neither is CMakeLists.txt.
#   3. TOOL. The alphabet stage had no arm for `optimis`, `initialis`, `signall` or the -ce nouns.
#   4. TOOL. The extension list could not open a CMakeLists.txt.
# This pass is 3 and 4. Axes 1 and 2 change what every committer in that repository has to satisfy,
# they are its captain's and Douglas's to decide, and its captain has correctly refused to decide
# them alone. A gate that is correct, installed nowhere, and scoped to two paths still catches
# nothing, and these tests passing does not say otherwise.

import io
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import docs_check

# The two refs this file pins a fixture to, both in idemIP and both PUSHED. The test asserts the
# reachability; a comment claiming it is not a check. A revision is authority only while somebody
# else can fetch it, and a fixture pinned to a local-only commit is a fixture of one machine.
BEFORE_REF = "82dc143"
AFTER_REF = "242ec74"


def sibling_repository(name):
    """A repository checked out beside this one, or None.

    Resolved through main_checkout() for the reason commit 915b3a9 records. A linked worktree lives
    under .claude/worktrees/, and a sibling computed from __file__ lands inside .claude and finds
    nothing there.
    """
    named = os.environ.get(name.upper() + "_TREE")
    if named:
        return named if os.path.isdir(named) else None
    beside = os.path.join(os.path.dirname(docs_check.main_checkout()), name)
    return beside if os.path.isdir(beside) else None


def git(tree, *args):
    """One git query against a tree, or None where git cannot answer."""
    try:
        answer = subprocess.check_output(
            ("git",) + args, cwd=tree, stderr=subprocess.PIPE
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return answer.decode("utf-8", "replace").strip()


def reachability(tree, ref):
    """Where a revision is reachable from, or the words that say it is not.

    Printed with every count this file reports. Two sessions read 58 British hits in idemIP and 15,
    and the difference between them was two unnamed revisions.
    """
    remote = git(tree, "branch", "-r", "--contains", ref)
    if remote is None:
        return "no git history"
    return remote.splitlines()[0].strip() if remote else "NOT PUSHED"


def tree_at(repository, ref, into):
    """One revision of a repository unpacked into a directory, or None.

    git archive is used instead of a worktree. A worktree writes into the repository being read and
    has to be removed afterward, and a test that leaves one behind changes the thing it measured.
    """
    try:
        blob = subprocess.check_output(
            ["git", "archive", "--format=tar", ref],
            cwd=repository,
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    with tarfile.open(fileobj=io.BytesIO(blob)) as bundle:
        bundle.extractall(into, filter="data")
    return into


# ============================================================================
# GROUND TRUTH FOR THE ALPHABET STAGE
# ============================================================================
#
# Plain literals, written by hand, sharing no code with the patterns under test. "The stage reaches
# N of N" is then two independent enumerations agreeing, instead of a regex agreeing with itself.
#
# Held as a tuple of single-quoted strings, deliberately. A triple-quoted block here would be a
# docstring, prose_only keeps docstrings, and this tree's own run would then report every word in
# the list as a British variant, against the file that tests for British variants.
BRITISH_FORMS = (
    "initialise",
    "initialised",
    "initialises",
    "initialising",
    "initialiser",
    "initialisers",
    "initialisation",
    "optimise",
    "optimised",
    "optimises",
    "optimising",
    "optimiser",
    "optimisation",
    "optimisations",
    "recognise",
    "recognised",
    "recognises",
    "recognising",
    "recognisable",
    "normalise",
    "normalised",
    "normalises",
    "normalising",
    "normalisation",
    "serialise",
    "serialised",
    "serialises",
    "serialising",
    "serialisation",
    "authorise",
    "authorised",
    "authorises",
    "authorising",
    "authorisation",
    "synchronise",
    "synchronised",
    "synchronises",
    "synchronising",
    "synchronisation",
    "minimise",
    "minimised",
    "minimises",
    "minimising",
    "maximise",
    "maximised",
    "maximises",
    "maximising",
    "summarise",
    "summarised",
    "summarises",
    "summarising",
    "standardise",
    "standardised",
    "standardising",
    "utilise",
    "utilised",
    "utilises",
    "utilising",
    "categorise",
    "categorised",
    "categorising",
    "organise",
    "organised",
    "organises",
    "organising",
    "organisation",
    "organisations",
    "parenthesise",
    "parenthesised",
    "parenthesises",
    "specialise",
    "specialised",
    "generalise",
    "generalised",
    "finalise",
    "finalised",
    "customise",
    "customised",
    "sanitise",
    "sanitised",
    "randomise",
    "randomised",
    "localise",
    "localised",
    "realise",
    "realised",
    "emphasise",
    "emphasised",
    "amortise",
    "amortised",
    "vectorise",
    "vectorised",
    "devirtualise",
    "devirtualises",
    "parallelise",
    "parallelised",
    "centralise",
    "centralised",
    "materialise",
    "materialised",
    "analyse",
    "analysed",
    "analyses",
    "analysing",
    "analyser",
    "analysers",
    "paralyse",
    "paralysed",
    "catalyse",
    "catalysed",
    "dialyse",
    "dialysed",
    "behaviour",
    "behaviours",
    "behavioural",
    "colour",
    "colours",
    "coloured",
    "colouring",
    "colourful",
    "neighbour",
    "neighbours",
    "neighbouring",
    "neighbourhood",
    "favour",
    "favours",
    "favoured",
    "favourite",
    "honour",
    "honours",
    "honoured",
    "honouring",
    "humour",
    "humours",
    "labour",
    "labours",
    "laboured",
    "armour",
    "armoured",
    "rumour",
    "rumours",
    "vapour",
    "vapours",
    "odour",
    "odours",
    "harbour",
    "harbours",
    "savour",
    "savoured",
    "valour",
    "endeavour",
    "endeavours",
    "parlour",
    "splendour",
    "candour",
    "fervour",
    "rigour",
    "vigour",
    "tumour",
    "tumours",
    "clamour",
    "demeanour",
    "saviour",
    "flavour",
    "flavours",
    "flavoured",
    "ardour",
    "centre",
    "centres",
    "centred",
    "theatre",
    "theatres",
    "fibre",
    "fibres",
    "litre",
    "litres",
    "metre",
    "metres",
    "kilometre",
    "kilometres",
    "millimetre",
    "millimetres",
    "micrometre",
    "calibre",
    "calibres",
    "sabre",
    "sombre",
    "spectre",
    "lustre",
    "meagre",
    "manoeuvre",
    "manoeuvred",
    "sceptre",
    "labelled",
    "labelling",
    "labeller",
    "modelled",
    "modelling",
    "modeller",
    "signalled",
    "signalling",
    "travelled",
    "travelling",
    "traveller",
    "cancelled",
    "cancelling",
    "levelled",
    "levelling",
    "totalled",
    "totalling",
    "fuelled",
    "fuelling",
    "dialled",
    "dialling",
    "marvelled",
    "counselled",
    "counselling",
    "equalled",
    "equalling",
    "spiralled",
    "spiralling",
    "tunnelled",
    "tunnelling",
    "quarrelled",
    "jewelled",
    "fulfil",
    "fulfils",
    "fulfilment",
    "enrol",
    "enrols",
    "enrolment",
    "instal",
    "instals",
    "instalment",
    "skilful",
    "skilfully",
    "wilful",
    "wilfully",
    "enthral",
    "appal",
    "distil",
    "distils",
    "instil",
    "instils",
    "defence",
    "defences",
    "offence",
    "offences",
    "pretence",
    "pretences",
    "licence",
    "licences",
    "practise",
    "practised",
    "practises",
    "practising",
    "catalogue",
    "catalogues",
    "catalogued",
    "analogue",
    "analogues",
    "programme",
    "programmes",
    "whilst",
    "amongst",
    "grey",
    "greyscale",
    "artefact",
    "artefacts",
    "aluminium",
    "sulphur",
    "storey",
    "storeys",
    "tyre",
    "tyres",
    "cheque",
    "cheques",
    "draught",
    "draughts",
    "mould",
    "moulds",
    "speciality",
    "jewellery",
    "woollen",
    "aeroplane",
    "moustache",
    "pyjamas",
    "kerb",
    "plough",
    "gaol",
)

GROUND_TRUTH = re.compile(
    r"\b(?:%s)\b" % "|".join(sorted(set(BRITISH_FORMS), key=len, reverse=True)),
    re.IGNORECASE,
)


def forms_present(tree):
    """Every ground-truth form that occurs in the prose view of a tree, with how many sites.

    Reads through docs_check's own extractor. A word inside code is then not counted, and the two
    enumerations are measuring the same text.
    """
    found = {}
    for path in docs_check.walk_markdown([tree]):
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
        for line in docs_check.prose_only(path, lines):
            for hit in GROUND_TRUTH.finditer(line):
                word = hit.group(0).lower()
                found[word] = found.get(word, 0) + 1
    return found


def stage_reaches(word):
    """Whether the alphabet stage matches one word on its own."""
    return any(re.search(one, word, re.IGNORECASE) for one in docs_check.LOCALE)


def spelling_findings(path):
    """Every alphabet-stage finding in one file, as (line, matched text)."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    said = docs_check.prose_only(path, lines)
    found = []
    for at, pattern, token in docs_check.banned_hits(
        said,
        quotations=path.endswith(".md"),
        comments=not path.endswith((".md", ".tex")),
    ):
        if docs_check.tier_of(pattern) == "alphabet":
            found.append((at, token.lower()))
    return sorted(found)


class BuildFilesAreReadAtAll(unittest.TestCase):
    """The extension list could not open a build file, and said as success.

    Pointed at idemIP's CMakeLists.txt the tool printed "0 file(s) checked, 0 breaking, 0 prose"
    and "no files were read". The exit status was 2. That sentinel for reading nothing was the only
    part of the output telling that run apart from a clean one.
    """

    def test_a_cmakelists_is_selected_by_its_name(self):
        # The one selection rule an extension list can never express. CMakeLists.txt has an
        # extension and it is .txt, which this tool does not read and should not start reading.
        self.assertTrue(docs_check.build_file("some/where/CMakeLists.txt"))
        self.assertTrue(docs_check.checked_file("some/where/CMakeLists.txt"))
        self.assertFalse(docs_check.checked_file("some/where/NOTES.txt"))

    def test_a_git_hook_is_selected_although_it_has_no_extension(self):
        # A four-extension sweep dropped a hook and took the gate with it. That is the failure
        # HOOK_NAMES exists for, and anchor_sift keeps three of these under roots it already scans.
        for name in ("pre-commit", "commit-msg", "pre-push"):
            self.assertTrue(docs_check.build_file(os.path.join("hooks", name)), name)

    def test_the_build_suffixes_are_all_selected(self):
        for suffix in docs_check.BUILD_SUFFIXES:
            self.assertTrue(docs_check.checked_file("build" + suffix), suffix)

    def test_the_default_run_now_reads_build_files(self):
        # Asserted against the roots this repository actually scans. The selection rule is
        # measured where it has to work and not only against a made-up path.
        roots = list(docs_check.DEFAULT_ROOTS)
        got = [
            one for one in docs_check.walk_markdown(roots) if docs_check.build_file(one)
        ]
        kinds = sorted(
            set(
                (
                    os.path.basename(one)
                    if os.path.basename(one) in docs_check.BUILD_NAMES
                    or os.path.basename(one) in docs_check.HOOK_NAMES
                    else os.path.splitext(one)[1]
                )
                for one in got
            )
        )
        print(
            "\n  build files under this tree's own roots: %d, of kinds %s"
            % (len(got), kinds)
        )
        self.assertGreater(
            len(got), 0, "no build file was selected under this tree's own roots"
        )
        self.assertIn("CMakeLists.txt", kinds)
        self.assertIn("pre-commit", kinds)


class TheCMakeListsFixture(unittest.TestCase):
    """idemIP's CMakeLists.txt, the best fixture in the tree for this pair of gaps.

    Skipped where idemIP is not checked out beside this repository. Set IDEMIP_TREE to point at it
    somewhere else.
    """

    @classmethod
    def setUpClass(cls):
        tree = sibling_repository("idemIP")
        if not tree:
            raise unittest.SkipTest("idemIP is not checked out beside this repository")
        cls.tree = tree
        cls.path = os.path.join(tree, "CMakeLists.txt")
        if not os.path.isfile(cls.path):
            raise unittest.SkipTest("idemIP has no CMakeLists.txt at its root")
        cls.ref = git(tree, "rev-parse", "--short", "HEAD")
        cls.where = reachability(tree, "HEAD")

    def test_the_four_british_sites_are_reported_by_line(self):
        # BY SITE and never by count. A count falling to the right number for the wrong reason
        # reads exactly like a repair. The three `optimisation` sites are 182 lines below the
        # `behaviour` one. An author watching :123 fire has seen one quarter of this file's British
        # variants and none of the class that was hidden twice.
        got = spelling_findings(self.path)
        print(
            "\n  idemIP CMakeLists.txt at %s (%s): %d definition finding(s) %s"
            % (self.ref, self.where, len(got), got)
        )
        self.assertEqual([one for one, _ in got], [123, 305, 311, 321])
        self.assertEqual(
            [two for _, two in got],
            ["behaviour", "optimisation", "optimisation", "optimisation"],
        )

    def test_three_of_the_four_need_the_pattern_and_not_only_the_extension(self):
        # The half of this pass that a reader is most likely to undo. Held as an assertion so the
        # claim in the header is checked and not only written down.
        was_ten = (
            r"\blabelled\b",
            r"\bmodelled\b",
            r"\bneighbour",
            r"\bbehaviour",
            r"\bcolour",
            r"\bcentre\b",
            r"\bwhilst\b",
            r"\bamongst\b",
            r"\borganis(e|es|ed|ing|ation|ations)\b",
            r"\banalyse(s|d)?\b",
        )
        reached = [
            word
            for _, word in spelling_findings(self.path)
            if any(re.search(one, word, re.IGNORECASE) for one in was_ten)
        ]
        self.assertEqual(reached, ["behaviour"])

    def test_the_file_reads_and_does_not_report_reading_nothing(self):
        checked = docs_check.walk_markdown([self.path])
        self.assertEqual(
            [os.path.abspath(one) for one in checked], [os.path.abspath(self.path)]
        )

    def test_a_build_file_of_prose_findings_still_exits_zero(self):
        # Prose never fails a build, in any repository, and a new extension does not get to be the
        # exception. Both standards say it in the sentence that names this tool.
        run = subprocess.run(
            [sys.executable, os.path.join(HERE, "docs_check.py"), self.path],
            capture_output=True,
            text=True,
        )
        self.assertIn("0 breaking", run.stdout)
        self.assertIn("prose", run.stdout)
        self.assertEqual(run.returncode, 0, run.stdout)


class TheCommentExtractorForTheHashForm(unittest.TestCase):
    """The `#` comment, which shell, CMake, YAML and make all share, and the traps in finding it."""

    def test_a_hash_inside_a_string_is_not_a_comment(self):
        self.assertEqual(docs_check.hash_tail('message("a # b")'), "")
        self.assertEqual(docs_check.hash_tail("set(x 'a # b')"), "")

    def test_shell_argument_arithmetic_is_not_a_comment(self):
        # Without the open-a-word rule, `$#` and `${#name}` read as comment markers and a run of
        # argument handling gets scanned as prose.
        self.assertEqual(docs_check.hash_tail('if [ "$#" -lt 2 ]; then'), "")
        self.assertEqual(docs_check.hash_tail("len=${#name}"), "")

    def test_a_comment_after_code_is_found(self):
        self.assertEqual(docs_check.hash_tail("set(x 1)  # the reason"), "# the reason")
        self.assertEqual(docs_check.hash_tail("# at the start"), "# at the start")

    def test_line_numbers_are_preserved(self):
        # A finding has to name the line a reader opens. Blanked and never dropped.
        said = docs_check.comment_prose(["code()", "# one", "code()", "# two"])
        self.assertEqual(len(said), 4)
        self.assertEqual(said[1], "# one")
        self.assertEqual(said[0], "")

    def test_a_shebang_is_not_prose(self):
        said = docs_check.comment_prose(["#!/usr/bin/env bash", "# a real comment"])
        self.assertEqual(said[0], "")
        self.assertEqual(said[1], "# a real comment")

    def test_the_powershell_block_comment_is_read(self):
        said = docs_check.comment_prose(["<#", "the note", "#>", "code"])
        self.assertEqual(said[1], "the note")
        self.assertEqual(said[3], "")

    def test_the_extractor_is_reached_through_prose_only(self):
        # The dispatch and not only the helper, because a caller that has to know which extractor to
        # call is a caller that will get it wrong. submission_check.py imports CHECKED and
        # prose_only and never asks what kind of file it has.
        said = docs_check.prose_only(
            "x/CMakeLists.txt", ["set(a 1)", "# undefined behaviour"]
        )
        self.assertEqual(said[0], "")
        self.assertIn("behaviour", said[1])


class TheAlphabetStageIsAPatternAndNotAList(unittest.TestCase):
    """code-documentation:149 states the rule as a shape, and this stage was ten literals.

    docs-check: quoting
    "Never a British variant, and the ban is on the pattern rather than on a list: no `-ise` or
    `-isation` where American takes `-ize` or `-ization`, no `-our` for `-or`, no `-re` for `-er`,
    no doubled `l` in `modelled`, `labelled`, `signalled`."
    docs-check: end quoting
    """

    def test_the_stage_is_spliced_into_the_table_that_enforces_it(self):
        # THE STRUCTURAL HALF OF THE SAME FAULT, and the part nobody had named. LOCALE was read at
        # one site that chose a word in the report, and BANNED carried a second hand-written copy of
        # the same ten patterns. Adding a pattern to LOCALE alone changed a label and produced no
        # finding, and the two copies could be edited apart with no signal at all.
        for pattern in docs_check.LOCALE:
            self.assertIn(
                pattern,
                docs_check.BANNED,
                "a definition pattern that BANNED does not hold reports nothing: %r"
                % pattern,
            )
        self.assertEqual(len(set(docs_check.LOCALE)), len(docs_check.LOCALE))

    def test_the_ten_it_used_to_be_are_carried_forward_character_for_character(self):
        # Nine of the ten are keys in HUMAN_RATE, which is keyed by the pattern string itself.
        # Rewriting one to fold it into a general arm takes a measured rate out of
        # submission_check.py's table with nothing left to say it was ever there. `whilst` carries
        # no rate, because it fired zero times in the papers HUMAN_RATE was counted over.
        was_ten = (
            r"\blabelled\b",
            r"\bmodelled\b",
            r"\bneighbour",
            r"\bbehaviour",
            r"\bcolour",
            r"\bcentre\b",
            r"\bwhilst\b",
            r"\bamongst\b",
            r"\borganis(e|es|ed|ing|ation|ations)\b",
            r"\banalyse(s|d)?\b",
        )
        self.assertEqual(docs_check.LOCALE[: len(was_ten)], was_ten)
        dead = [one for one in was_ten if one not in docs_check.HUMAN_RATE]
        self.assertEqual(
            dead, [r"\bwhilst\b"], "a measured rate lost its key: %s" % (dead,)
        )

    def test_every_spelling_pattern_is_the_alphabet_tier(self):
        for pattern in docs_check.LOCALE:
            self.assertEqual(docs_check.tier_of(pattern), "alphabet", pattern)
            self.assertNotIn(pattern, docs_check.AUTHORITY, pattern)

    def test_each_shape_the_standard_names_has_an_arm(self):
        # The four shapes in that one sentence, each checked through a word the sentence does not
        # itself contain. The arm is tested and not the literal.
        for word in (
            "categorising",
            "tokenisation",
            "harbour",
            "kilometres",
            "tunnelled",
        ):
            self.assertTrue(stage_reaches(word), "no arm reaches %r" % word)

    def test_the_twelve_american_spellings_the_standard_names_are_left_alone(self):
        # code-documentation:149 names these as the correct forms. A rule that reports one of them
        # is a rule enforcing the opposite of what it cites.
        for word in (
            "initialize",
            "behavior",
            "synchronize",
            "optimization",
            "devirtualize",
            "analog",
            "color",
            "center",
            "defense",
            "gray",
            "catalog",
            "license",
        ):
            self.assertFalse(
                stage_reaches(word),
                "the stage reports an American definition: %r" % word,
            )


class PrecisionOverRecall(unittest.TestCase):
    """Every one of these was a false positive in the measurement, and each is held out by name.

    A gate that reports everything and leaves a person to sort it gets switched off inside a week.
    """

    def test_english_words_ending_in_ise_are_not_british(self):
        # The s belongs to the stem here, not to the Greek -ize suffix. American writes all of
        # these with an s too.
        for word in (
            "advise",
            "advised",
            "adviser",
            "revise",
            "devise",
            "supervise",
            "televise",
            "improvise",
            "exercise",
            "exercises",
            "excise",
            "concise",
            "precise",
            "imprecise",
            "incise",
            "circumcise",
            "promise",
            "promises",
            "premise",
            "surmise",
            "demise",
            "compromise",
            "despise",
            "franchise",
            "merchandise",
            "paradise",
            "treatise",
            "expertise",
            "enterprise",
            "comprise",
            "surprise",
            "apprise",
            "reprise",
            "chastise",
            "advertise",
        ):
            self.assertFalse(stage_reaches(word), "reported as British: %r" % word)

    def test_the_shapes_the_arm_refuses_without_naming_them(self):
        # The consonant class and the two-character floor carry these. None of them has to be
        # written into a list that a later reader has to maintain.
        for word in (
            "noise",
            "raise",
            "praise",
            "braise",
            "chaise",
            "guise",
            "disguise",
            "cruise",
            "bruise",
            "poise",
            "tortoise",
            "porpoise",
            "malaise",
            "appraise",
            "rise",
            "arise",
            "prise",
            "wise",
            "wiser",
            "otherwise",
            "likewise",
            "clockwise",
            "bitwise",
            "stepwise",
            "pairwise",
            "anise",
        ):
            self.assertFalse(stage_reaches(word), "reported as British: %r" % word)

    def test_a_safe_stem_is_matched_from_the_end_of_a_word(self):
        # These are the compounds the measurement turned up. An exemption anchored at the start of
        # the word missed every one of them.
        for word in (
            "madvise",
            "keycompromise",
            "aacompromise",
            "saxexerciser",
            "unadvisable",
        ):
            self.assertFalse(stage_reaches(word), "reported as British: %r" % word)

    def test_two_stems_that_were_removed_stay_removed(self):
        # `anis` exempts `organise`, which ends in those five letters. `mortis` exempts `amortise`,
        # which ends in those six. A stem matched from the end has to be checked against the British
        # words that end the same way, and these two were not.
        self.assertTrue(stage_reaches("organise"))
        self.assertTrue(stage_reaches("amortise"))
        self.assertTrue(stage_reaches("amortised"))

    def test_american_doubled_l_words_are_not_reported(self):
        # Why the doubled-l rule is a list. American doubles the l in all of these, and a general
        # rule would report a quarter of the verbs in the tree.
        for word in (
            "controlled",
            "controlling",
            "installed",
            "installing",
            "enrolled",
            "spelled",
            "called",
            "filled",
            "pulled",
            "rolled",
            "billed",
        ):
            self.assertFalse(stage_reaches(word), "reported as British: %r" % word)

    def test_programmed_and_programming_are_american(self):
        # Getting this wrong cost 835 false positives in the first measurement pass, which was more
        # than half of everything the arms reported.
        self.assertFalse(stage_reaches("programmed"))
        self.assertFalse(stage_reaches("programming"))
        self.assertTrue(stage_reaches("programme"))

    def test_the_our_arm_refuses_the_short_words_and_holds_the_long_ones(self):
        for word in (
            "our",
            "your",
            "four",
            "hour",
            "tour",
            "pour",
            "sour",
            "flour",
            "scour",
            "dour",
            "amour",
            "devour",
            "contour",
            "contours",
            "detour",
            "glamour",
            "byhour",
            "numberofcontours",
            "encourage",
            "journal",
            "resourceful",
        ):
            self.assertFalse(stage_reaches(word), "reported as British: %r" % word)
        for word in (
            "ardour",
            "candour",
            "behaviour",
            "behavioural",
            "colourful",
            "favourite",
            "neighbourless",
            "labourer",
            "harbour",
            "endeavour",
        ):
            self.assertTrue(stage_reaches(word), "not reached: %r" % word)

    def test_the_single_l_arm_stops_at_the_word_boundary(self):
        # `fulfilled` and `appalling` are spelled the same on both sides of the Atlantic. Only the
        # forms that differ are in the arm, and the word boundary keeps the rest out.
        self.assertTrue(stage_reaches("fulfil"))
        self.assertTrue(stage_reaches("fulfilment"))
        self.assertFalse(stage_reaches("fulfilled"))
        self.assertFalse(stage_reaches("appalling"))

    def test_the_isable_arm_was_removed_and_stays_removed(self):
        # It matched `controldisable` and every other compound ending in `disable`, and bought
        # three real hits across five repositories and the whole of CPython.
        for word in (
            "disable",
            "disabled",
            "disabling",
            "controldisable",
            "autodisabled",
        ):
            self.assertFalse(stage_reaches(word), "reported as British: %r" % word)

    def test_the_two_tier_line_in_idemip_is_reported_as_two_findings(self):
        # idemIP tools/dev_env/strip_comments.py:12 is the best demonstration in any tree here of
        # where an autofix may and may not go. One line carries a `licence` and a `rather`. The
        # first is token for token: `licence` becomes `license` and the sentence is unchanged. The
        # second is a construction, and code-documentation:110 bans it while :146 bans its obvious
        # repair forty lines later. No machine can make that edit. The alphabet stage is the only
        # class an autofix could ever own, and this test marks where its edge falls.
        tree = sibling_repository("idemIP")
        if not tree:
            self.skipTest("idemIP is not checked out beside this repository")
        path = os.path.join(tree, "tools", "dev_env", "strip_comments.py")
        if not os.path.isfile(path):
            self.skipTest("idemIP has no tools/dev_env/strip_comments.py")
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
        said = docs_check.prose_only(path, lines)
        tiers = sorted(
            set(
                docs_check.tier_of(pattern)
                for at, pattern, _ in docs_check.banned_hits(said, comments=True)
                if at == 12
            )
        )
        print("\n  idemIP strip_comments.py:12 reports tiers %s" % tiers)
        self.assertEqual(tiers, ["A", "alphabet"])

    def test_the_stage_reports_nothing_in_either_standard(self):
        # The governing test, in the slice this pass owns. A gate that flags the documents that
        # authorize it is wrong by construction, and a new pattern arm is the most likely way to
        # break that. The standards write `initialise` and `behaviour` by name at :149 and :157,
        # inside backticks. The document is naming a form there, and a name is not a use.
        skills = os.path.join(os.path.expanduser("~"), ".claude", "skills")
        checked = 0
        for name in ("code-documentation", "code-comments"):
            path = os.path.join(skills, name, "SKILL.md")
            if not os.path.isfile(path):
                continue
            checked += 1
            got = spelling_findings(path)
            self.assertEqual(
                got, [], "%s/SKILL.md reported on definition: %s" % (name, got)
            )
        if not checked:
            self.skipTest("neither SKILL.md is installed under ~/.claude/skills")


class TheStageAgainstAPushedRef(unittest.TestCase):
    """Two independent enumerations of one tree, at a revision anybody can fetch.

    The ground-truth list above is plain literals and shares no code with the patterns. The
    assertion is that the two enumerations agree, plus the count the old list reached, plus the size
    of the correction between two refs derived as a difference and never as a total.
    """

    @classmethod
    def setUpClass(cls):
        tree = sibling_repository("idemIP")
        if not tree:
            raise unittest.SkipTest("idemIP is not checked out beside this repository")
        if git(tree, "rev-parse", "--verify", AFTER_REF + "^{commit}") is None:
            raise unittest.SkipTest("idemIP does not hold %s" % AFTER_REF)
        cls.repository = tree
        cls.holding = tempfile.TemporaryDirectory(prefix="docs_check_refs_")
        cls.at = {}
        for ref in (BEFORE_REF, AFTER_REF):
            into = os.path.join(cls.holding.name, ref)
            os.makedirs(into, exist_ok=True)
            cls.at[ref] = tree_at(tree, ref, into)
        if not all(cls.at.values()):
            cls.holding.cleanup()
            raise unittest.SkipTest("git archive could not unpack one of the refs")

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "holding"):
            cls.holding.cleanup()

    def test_both_refs_are_reachable_from_a_remote(self):
        # A revision is authority only while somebody else can fetch it. The 43-hit fixture was
        # briefly reachable only through a worktree that dies with the session that made it.
        for ref in (BEFORE_REF, AFTER_REF):
            where = reachability(self.repository, ref)
            print("\n  idemIP %s: %s" % (ref, where))
            self.assertNotEqual(
                where, "NOT PUSHED", "%s is a fixture nobody else can fetch" % ref
            )

    def test_the_stage_reaches_every_british_form_in_the_tree(self):
        # N OF N, DERIVED. The denominator is the ground-truth list intersected with the tree at
        # run time. It moves when the tree moves and no constant can rot here.
        tree = self.at[AFTER_REF]
        present = forms_present(tree)
        missed = sorted(one for one in present if not stage_reaches(one))
        was_ten = (
            r"\blabelled\b",
            r"\bmodelled\b",
            r"\bneighbour",
            r"\bbehaviour",
            r"\bcolour",
            r"\bcentre\b",
            r"\bwhilst\b",
            r"\bamongst\b",
            r"\borganis(e|es|ed|ing|ation|ations)\b",
            r"\banalyse(s|d)?\b",
        )
        before = sorted(
            one
            for one in present
            if any(re.search(two, one, re.IGNORECASE) for two in was_ten)
        )
        print(
            "\n  idemIP %s (%s): %d distinct British form(s) present over %d site(s)"
            % (
                AFTER_REF,
                reachability(self.repository, AFTER_REF),
                len(present),
                sum(present.values()),
            )
        )
        print("    the ten literals reached %d of %d" % (len(before), len(present)))
        print(
            "    the pattern arms reach   %d of %d"
            % (len(present) - len(missed), len(present))
        )
        print(
            "    forms: %s"
            % ", ".join("%s(%d)" % (one, present[one]) for one in sorted(present))
        )
        self.assertGreater(
            len(present), 0, "the ground truth found nothing. It proves nothing"
        )
        self.assertEqual(missed, [], "the stage misses: %s" % missed)
        self.assertLess(
            len(before),
            len(present),
            "the ten literals already reached everything. This pass bought nothing",
        )

    def test_the_correction_between_the_two_refs_is_derived_as_a_difference(self):
        # A difference and never a total. Two sessions read 58 and 15 for this repository and both
        # numbers were about an unnamed tree. The difference between two named refs is the thing
        # that survives a pattern set changing under it.
        counted = {}
        for ref, tree in self.at.items():
            found = 0
            for path in docs_check.walk_markdown([tree]):
                found += len(spelling_findings(path))
            counted[ref] = found
        moved = counted[BEFORE_REF] - counted[AFTER_REF]
        print(
            "\n  idemIP definition findings: %s at %s, %s at %s, corrected by hand: %d"
            % (counted[BEFORE_REF], BEFORE_REF, counted[AFTER_REF], AFTER_REF, moved)
        )
        self.assertGreater(
            moved, 0, "the later ref is not cleaner. This is not the fixture it was"
        )
        self.assertEqual(counted[AFTER_REF] + moved, counted[BEFORE_REF])

    def test_the_build_file_sites_are_the_same_at_both_refs(self):
        # The direct proof of what this pass is for. A person corrected British spellings by hand
        # between these two refs, in files the tool could open. The build files were not touched,
        # because nothing could show them, and a commit gate would not have shown them either.
        at_both = {}
        for ref, tree in self.at.items():
            sites = []
            for path in docs_check.walk_markdown([tree]):
                if not docs_check.build_file(path):
                    continue
                rel = os.path.relpath(path, tree).replace("\\", "/")
                sites.extend((rel, at, word) for at, word in spelling_findings(path))
            at_both[ref] = sorted(sites)
        print(
            "\n  build-file definition sites: %d at %s, %d at %s"
            % (len(at_both[BEFORE_REF]), BEFORE_REF, len(at_both[AFTER_REF]), AFTER_REF)
        )
        self.assertGreater(
            len(at_both[AFTER_REF]),
            0,
            "no build-file site at either ref. This proves nothing",
        )
        self.assertEqual(
            at_both[BEFORE_REF],
            at_both[AFTER_REF],
            "a build-file site moved between the refs. The fixture has changed "
            "and the claim above it needs re-deriving",
        )


class TheWorkBesideThisOneIsUntouched(unittest.TestCase):
    """Guards for the two passes this one sits between. A rebuild drops them without deciding to."""

    def test_the_structural_gate_still_refuses_a_doxygen_reference(self):
        self.assertFalse(docs_check.path_candidate("@ref HTTP_10"))
        self.assertFalse(
            docs_check.path_candidate("const char *user, const char *pass")
        )
        self.assertTrue(docs_check.path_candidate("docs/README.md"))

    def test_the_tier_split_still_names_its_sections(self):
        self.assertEqual(docs_check.tier_of(r"\brather\b"), "A")
        self.assertIn("code-documentation:110", docs_check.AUTHORITY[r"\brather\b"])

    def test_a_new_extension_added_no_breaking_rule(self):
        # The structural stage fails a commit. A build file becoming readable must not turn a
        # comment in one into a refused commit by accident. em_dashes is the only structural rule
        # that runs on every extension, and it already ran that way on .py, .c and .h.
        said = docs_check.prose_only("x/build.sh", ["# a plain comment", "echo hi"])
        self.assertEqual(docs_check.em_dashes(said), [])
        self.assertEqual(docs_check.em_dashes(["# " + chr(0x2014)]), [(1, "em dash")])


if __name__ == "__main__":
    unittest.main(verbosity=2)
