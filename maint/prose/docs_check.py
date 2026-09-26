#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# What the prose standard says, checked instead of remembered.
#
#   Usage:  python maint/prose/docs_check.py [root]
#
# It exists because a table header was left standing with every row removed under it, and that
# rendered as an empty table on the site for a day before anyone looked. Nothing read the documents
# and nothing could have caught it. Each check below is a defect that actually reached a published
# page, and none of them is a matter of taste.
#
# Exit status: 0 when nothing breaking was found, 1 when something breaking was. Prose findings are
# printed and exit 0, because the prose backlog predates the check and a hook nobody can satisfy
# gets turned off. So it fails a pipeline without needing a flag, and only on the tier that stops a
# commit.
#
# THIS LINE READ "the count of findings" UNTIL 2026-09-16 AND THAT WAS NEVER TRUE. A count is the
# wrong shape for an exit status, as the note beside main() already said: they wrap at 256. 256
# findings would report success. The header and the code had disagreed long enough that a hook was
# written against the header, tested for exit 2, and would have let every breaking finding through
# while printing it. It was caught by running this checker on a file holding one em dash and not
# by reading this comment. Ask the instrument, do not model it, and that applies to its own header.
#
# WHAT THIS TOOL IS TO THE REST OF THE TREE. Both writing standards name it by path and hand it the
# list: code-documentation section 145 and code-comments section 208. Its location inside
# anchor_sift is where it is kept and not what it governs. The table below is the standard for every
# .md page, every .py, .c and .h comment and every .tex body in every repository here.
#
# THE TWO TIERS. Read the note above AUTHORITY for the rule that assigns them and for why the regex
# never decides. In short: TIER A is a construction one of the two standards bans in a sentence, and
# it is tree-wide with no opt-in; TIER B is vocabulary, scored against what it costs a human writer
# where that has been measured. Neither tier fails a build, in any repository, --strict included.
#
# THE FAULT THIS TABLE KEEPS MAKING, in both directions at once, and it is a transcription failure
# and not a judgement failure. A rule is read for its EXAMPLES and coded as a list, or read for one
# INSTANCE and coded as a bare word:
#
#   OVER-REACH. code-documentation:126 bans "is what holds" and thirteen bare word bans were
#   written from it, hold and carry and read and ten more. :143 states the escape in the same
#   section: "a word that reads as a tic in one construction only is bounded to that construction."
#   Those thirteen are gone, and WITHDRAWN at the foot of BANNED records each with what it cost.
#   UNDER-REACH. code-documentation:149 states the British ban as a PATTERN, "the ban is on the
#   pattern. It is patterns now, and the note
#   above LOCALE records what each arm reaches and what came out of it on measurement.
#   A THIRD, STRUCTURAL. LOCALE was referenced at one site that only chose a
#   word in the report, and BANNED held a hand-written second copy of the same ten. A rule table
#   duplicated into the table that enforces it drifts with no signal at all. BANNED splices LOCALE
#   in now. There is one copy.
#
# Line numbers throughout are against the SKILL.md files as installed under ~/.claude/skills, read
# at the time this was written. Cite the sentence, not only the number: a number moves when a
# document is edited and the sentence is what the rule is.
#
# So re-check every rule against the sentence that states it, and not only the two anybody has
# pointed at. Running the standards' own illustrations through the checker is how four more were
# found: `make clear`, both of section 146's X-not-Y examples, and the `spelling` token ban.


import os
import re
import subprocess
import sys

# ====================================================================
# THE LOCALE STAGE. BRITISH CONVENTION AGAINST AMERICAN, AS A PATTERN AND NOT AS A LIST
# ====================================================================
#
# code-documentation:149 states this rule in one sentence and states it as a shape: "Never a British
# variant, and the ban is on the pattern rather than on a list: no `-ise` or `-isation` where
# American takes `-ize` or `-ization`, no `-our` for `-or`, no `-re` for `-er`, no doubled `l` in
# `modelled`, `labelled`, `signalled`." code-comments:157 says the same thing shorter.
#
# This tuple was ten literals until now, and the sentence says not to write ten literals.
# Measured against idemIP at 242ec74, which is pushed and reachable from origin/main: 22 distinct
# British word forms are present in that tree and the ten literals reached 7 of them. The 5-hit
# `analys*` class, the 9-hit `cancell*` class, `defence`, `distil`, `initialis*`, `licence`,
# `normalisation`, `optimis*`, `parenthesised`, `recognised` and `signalled` were all invisible.
# The arms below reach 22 of 22 at that ref. Re-derive both numbers before quoting either one:
# maint/prose/test_docs_check_coverage.py does it from the tree at run time.
#
# LOCALE WAS NOT A SCAN, AND THAT IS THE STRUCTURAL HALF OF THE SAME FAULT. It was referenced at
# exactly one site, stage_of(), where it only decided a word in the report. The ten British patterns
# were enforced because BANNED held a second copy of them, written out by hand. Adding a pattern
# here changed the label on a finding and never produced one. BANNED now splices this tuple in
# directly. The two cannot drift and there is one place to edit.
#
# THE TEN ORIGINALS ARE CARRIED FORWARD CHARACTER FOR CHARACTER, in their original order, ahead of
# everything new. HUMAN_RATE is keyed by pattern string and holds a measured rate for eight of them,
# and rewriting one to fold it into a general arm would take that rate out of submission_check.py's
# table with nothing to say it had gone. The general arms overlap them and banned_hits dedupes on
# (line, offset, token). An overlap costs a wasted match and never a doubled finding.
#
# WHAT THE -ise ARM ACTUALLY ENFORCES, and this is worth a sentence because somebody will read it
# as dialect detection and correct it toward Oxford. `-ise` is not reliably British. Oxford usage
# is `-ize` and always was. A tree written in Oxford English trips none of this and a tree
# written in American English trips none of it either. The arm enforces a HOUSE AMERICAN convention
# against one common British convention. It is not a claim about where the writer is from.
#
# PRECISION, MEASURED BEFORE THESE LANDED. The arms were run over five repositories here and over
# 544 files of CPython's standard library and site-packages, which is a large body of American and
# British English nobody here wrote. 530 hits across the five repositories, of which one is a false
# positive: `storyrevised` at theory/theory/Salishan/chapters/chapter_Salishan_refs.tex:463, a
# filename fragment that tex_prose leaves behind because a `\texttt` holding nested `\allowbreak{}`
# braces defeats its stripper. 1,216 hits across the Python tree, of which 34 are identifiers and
# not prose: `vonmises` and `cramervonmises` in scipy, `caretsloperise` in pygments, `sanssecours`,
# `miniser`, and one `suprises` that is a typo for `surprises`. Every other hit in both bodies is a
# British form in running prose. Call that 2.8 percent on somebody else's tree and 0.2 percent on
# this one.
#
# WHAT CAME OUT ON THE SAME EVIDENCE. An `-isable` arm matched `controldisable` and every other
# compound ending in `disable`, and bought three real hits across everything measured. It is gone.
# A general doubled-l arm is not written and cannot be: `controlled`, `installed`, `enrolled` and
# `spelled` are American with two l's. The doubled-l rule stays the named list the standard's own
# sentence gives it. A general `-re` arm is not written for the same reason: `are`, `here`, `more`,
# `figure` and `structure` are the majority of English words ending in those two letters.
#
# The standard's sentence names four shapes. It does not name the `ae` and `oe` digraphs
# (`haemoglobin`, `foetus`, `anaesthetic`). No arm is written for them. Nothing in any tree here
# fired one in the measurement above, and a rule with no measured hit is a rule nobody can tune.

# The ten this file carried before the arms below, in their original order and form.
LOCALE_NAMED = (
    r"\blabelled\b",
    r"\bmodelled\b",
    r"\bneighbour",
    r"\bbehaviour",
    r"\bcolour",
    r"\bcentre\b",
    r"\bwhilst\b",
    r"\bamongst\b",
    # Bounded to the verb and its forms. A bare \borganis also matches organism, which is a word.
    r"\borganis(e|es|ed|ing|ation|ations)\b",
    # KNOWN FALSE POSITIVE, named here so the next reader does not rediscover it. `analyses` is also
    # the American plural of `analysis`, and this pattern cannot tell the noun from the verb. It is
    # carried forward unchanged because narrowing it would drop the measured rate keyed to this
    # exact string in HUMAN_RATE. Every `analyse*` site measured in idemIP at 242ec74 is a verb.
    r"\banalyse(s|d)?\b",
)

# The suffixes an -ise stem takes. `-isable` and `-isability` were tried and came out: see above.
_ISE_TAIL = r"(?:e|es|ed|ing|er|ers)"

# English words ending in -ise where American also writes -ise, because the s belongs to the stem
# instead of to the Greek -ize suffix. Held as stems so one entry covers every inflection, and
# matched with any letters allowed in front of them. `madvise`, `imprecise`, `keycompromise` and
# `saxexerciser` are all left alone. Every one of those turned up in the measurement.
#
# TWO ENTRIES WERE REMOVED AFTER TESTING AND MUST NOT COME BACK. `anis` exempts `organise`, which
# ends in those five letters, and `mortis` exempts `amortise`, which ends in those six. A stem
# matched from the end of a word has to be checked against the British words that end the same way.
_ISE_STEMS = (
    "advis",
    "revis",
    "devis",
    "televis",
    "improvis",
    "supervis",
    "chastis",
    "advertis",
    "exercis",
    "excis",
    "incis",
    "concis",
    "precis",
    "circumcis",
    "promis",
    "premis",
    "surmis",
    "demis",
    "compromis",
    "despis",
    "franchis",
    "merchandis",
    "paradis",
    "treatis",
    "expertis",
    "valis",
    "enterpris",
    "compris",
    "surpris",
    "appris",
    "repris",
    "upris",
    "sunris",
    "denis",
)

# Words ending in -our that American spells the same way. `our`, `your`, `four`, `hour`, `tour`,
# `pour`, `sour`, `dour`, `flour`, `scour` and `amour` are absent on purpose: the {3,} floor in the
# arm already refuses them, and listing a short one here would exempt every British word ending in
# the same letters. `dour` would take `ardour` and `candour` with it.
_OUR_WORDS = (
    "devour",
    "contour",
    "detour",
    "velour",
    "glamour",
    "paramour",
    "troubadour",
    "bonjour",
    "seymour",
    "hour",
)

_OUR_TAIL = r"(?:s|ed|ing|er|ers|ite|ites|able|ably|ful|fully|less|ly|al|ally)?"

LOCALE = LOCALE_NAMED + (
    # -ise where American takes -ize. The letter before `is` must be a consonant, which refuses
    # `noise`, `raise`, `praise`, `guise`, `cruise`, `tortoise` and `malaise` without naming one of
    # them. `w` is out of the class, which refuses `otherwise`, `likewise` and every `-wise`
    # compound. The {2,} floor refuses `wise`, `rise`, `prise`, `arise` and `anise`, which are too
    # short to reach it. What is left is the suffix attached to a stem, and _ISE_STEMS names the
    # English words that reach that shape and are not British.
    r"\b(?![A-Za-z]*(?:%s)%s\b)[A-Za-z]{2,}[bcdfghjklmnpqrstvxz]is%s\b"
    % ("|".join(_ISE_STEMS), _ISE_TAIL, _ISE_TAIL),
    # -isation, -isations and -isational, where American takes -ization. This arm needs no
    # exemption list: no American word ends in those letters.
    r"\b[A-Za-z]{3,}isation(?:al|s)?\b",
    # -yse where American takes -yze. `analys` is here for the forms the named pattern above cannot
    # reach, which are `analyser`, `analysers` and `analysing`. The two overlap on `analysed` and
    # banned_hits reports the site once.
    r"\b(?:analys|paralys|catalys|dialys|electrolys|hydrolys)(?:e|ed|ing|er|ers)\b",
    # -our where American takes -or. The {3,} floor carries most of the work and _OUR_WORDS carries
    # the rest. The tail reaches `behavioural`, `colourful`, `favourite`, `labourer` and
    # `neighbourless`, which the two named patterns above never did.
    r"\b(?![A-Za-z]*(?:%s)%s\b)[A-Za-z]{3,}our%s\b"
    % ("|".join(_OUR_WORDS), _OUR_TAIL, _OUR_TAIL),
    # -re where American takes -er, as the named list the shape demands. The leading [A-Za-z]*
    # reaches `kilometres`, `millimetre`, `epicentre` and `multicentre`.
    r"\b[A-Za-z]*(?:centre|metre|theatre|fibre|litre|calibre|sabre|sombre|spectre"
    r"|lustre|meagre|manoeuvre|sceptre)s?\b",
    # The doubled l the standard names by name, plus the rest of the same class. A general rule is
    # impossible here: American doubles the l in `controlled`, `installed`, `enrolled`, `spelled`
    # and `called`. Only a list can separate them.
    r"\b(?:labell|modell|signall|travell|cancell|levell|totall|fuell|diall|marvell"
    r"|counsell|equall|initiall|spirall|tunnell|quarrell|refuell|shovell)"
    r"(?:ed|ing|er|ers|ors|or)\b",
    # The other half of the l rule, where British writes one and American writes two. Bounded to the
    # forms that differ: `fulfilled` and `appalling` are spelled the same on both sides, and the
    # word boundary after `fulfil` keeps them out.
    r"\b(?:fulfil|fulfils|fulfilment|fulfilments|enrol|enrols|enrolment|enrolments"
    r"|instal|instals|instalment|instalments|skilful|skilfully|wilful|wilfully"
    r"|enthral|enthrals|appal|appals|distil|distils|instil|instils)\b",
    # -ce where American takes -se, for the four nouns that differ. British usage splits `licence`
    # the noun from `license` the verb and American writes `license` for both. Only the -ce form
    # is ever wrong here and the verb needs no exemption.
    #
    # A `licence` inside an SPDX or copyright block is a legal artifact and a different question
    # from a house convention. That distinction belongs to the exclusions pass and is not made here:
    # this arm reports the site and a person decides it. A prose finding exists for that.
    # The four sites in idemIP at tools/dev_env/readclean.py:12 and :36 and strip_comments.py:4 and
    # :12 are prose ABOUT a license block, sitting beside real SPDX headers that are not.
    r"\b(?:defence|offence|pretence|licence)s?\b",
    # -ogue for the two the standard names, `catalog` and `analog`. `dialogue`, `monologue`,
    # `epilogue` and `prologue` are standard American and are deliberately absent.
    r"\b(?:catalogue|analogue)[sd]?\b",
    # `programme`, but never `programmed` or `programming`, which are American. Getting this wrong
    # cost 835 false positives in the first measurement pass.
    r"\bprogrammes?\b",
    # Named words with no shared shape to generalize over. Each one differs from its American
    # form in a way none of the arms above describes.
    r"\b(?:artefact|aluminium|sulphur|storey|tyre|cheque|draught|mould|speciality"
    r"|jewellery|woollen|aeroplane|moustache|pyjamas|kerb|plough|gaol)s?\b",
    # `gray` is named at code-documentation:149. Bounded so `greyhound` is untouched, and a proper
    # name spelled Grey is a false positive a person decides, and a prose finding exists for that.
    r"\bgrey(?:scale|s|ish)?\b",
)


# The tokens the writing standard bans outright, and the British spellings it bans by pattern.
BANNED = (
    (
        r"\brather\b",
        r"\badd up\b",
        # Named by hand. The X-not-Y shape is banned generally by the writing standard and permitted
        # where a reader would otherwise land on the wrong one, which no regex can tell apart. This
        # is the instance that was called out, and the list grows one phrase at a time for that
        # reason.
        r"cost and not a defect",
        # The same shape, caught by its grammar. It reports where the standard permits it too. It is
        # a prose finding and never a breaking one: a person decides each site.
        r"\b(is|was|are|were) an? [\w-]+ and not an? [\w-]+",
        # The same shape with no copula and no article, which is how code-documentation section 146
        # writes both of the examples it bans by name: "Declared, not allocated." and "A number, not
        # a guess." Every X-not-Y pattern in this file wanted (is|was|are|were) and an article. The
        # two sentences the standard names walked past all three of them. Derived by running the
        # standard's own illustrations through the checker: 4 of 28 named phrases were missed and
        # two were these.
        #
        # Bounded to a whole short sentence of that shape, as both examples are. The
        # mid-sentence appositive, "the bound is read in the header, not in the .c", is left alone:
        # the standard permits the contrast where a reader would otherwise land on the wrong one,
        # and reaching for every comma costs more true sentences than the tic is worth.
        r"(?m)(?:\A|(?<=[.!?] ))(?:(?:An?|The) )?[\w-]+, not (?:(?:an?|the) )?[\w-]+\.(?:\s|\Z)",
        # Nothing inanimate speaks. The standard names the subjects it bans: a name, a definition, a
        # token or a type. A paper, a table and an entry are texts and legitimately say things, and
        # an earlier version of this pattern included them and reported nine sites that were all
        # correct.
        #
        # make clear was missing from the verb alternation. Both standards name it in the same list
        # as say, signal, encode, convey, advertise and announce -- code-documentation section 147
        # and code-comments section 156 -- and six of the seven were transcribed. "The header makes
        # clear that the payload follows" was not caught until this line took the seventh.
        r"\b(name|definition|token|type|structure|constraint)s?\s+(says|say|signals|signal|encodes|encode|"
        r"conveys|convey|announces|announce|advertises|advertise|makes clear|make clear)\b",
        # `so an` is the same construction and was unmatched until 2026-09-16.
        # code-documentation:112 describes a CLAUSE -- "the personified consequence clause" -- and
        # this pattern implemented a TOKEN. Every `so a NN, down from NN` reported before this line
        # changed measured the matcher and not the tree: 21 of 105 instances across seven scoped
        # ProtoCore files were `so an`, and no tool had ever reported one. The inflection is the
        # article agreeing with the next word, which is not a property the ban turns on.
        r"\bso an?\b",
        # The comma-then-so consequence clause, widened from the two-token opener above. Douglas
        # ruled on 2026-09-16 that every comma-so clause is banned whatever word follows, not just
        # the article form: the-comma-so-the, comma-so-it and comma-so-every cases the opener
        # missed. runs() joins a comment block with a space, which places a comma ending one line
        # beside the so opening the next, and this pattern reads that join as one string, catching
        # the across-a-line-break case the same. Comma-so-that and comma-so-far are different
        # constructions and are excluded. The and-so-on, if-so and do-so forms carry no comma and
        # never reach this pattern.
        r",\s+so\s+(?!that\b|far\b)",
        # Banned outright by code-comments section 200, which names three tokens and bounds them in
        # the same sentence: "none has a legitimate use in a comment here". `so a` and `rather` are
        # banned for documentation as well by code-documentation section 110. `spelling` alone of
        # the three has a scoped ban, and COMMENT_ONLY below is where that scope is applied. A
        # page explaining a character encoding writes the word legitimately; a Doxygen block does
        # not.
        r"\bspelling\b",
        r"load-bearing",
    )
    # The locale stage, spliced in where its ten literals used to be hand-copied. LOCALE above is
    # the single copy. This is the position they held, kept so the order of BANNED does not move and
    # a pattern that overlaps a locale pattern still reports through whichever one BANNED reaches
    # first.
    + LOCALE
    + (
        # The register tics. These are not wrong facts, they are the sound of writing that is
        # performing instead of explaining, and they were found by reading a batch of this project's
        # own prose back and noticing the same shapes in every paragraph. Each one is a sentence
        # that exists for its rhythm: delete it and the paragraph loses nothing but its swagger.
        #
        # Raising a clause to a verdict.
        r"\bthe one that matters\b",
        r"\bis the one\b",
        r"\bthat is the whole\b",
        r"\bis the whole (of|rule|point|thing|question|claim|job|story)\b",
        r"\bthe whole (point|question|claim|rule|job|story) (is|was)\b",
        # Explaining the sentence just written instead of writing it once.
        r"\bwhich is (why|what|the)\b",
        r"\bthat is (what|why) \w+ (is|was|does|did)\b",
        r"\bis exactly (what|why|the)\b",
        r"\bis what makes\b",
        # Dramatic tags on the end of a clause.
        r"\band nothing else\b",
        r"\bon purpose\b",
        r"\bwhat survives\b",
        r"\bnever .{1,40}, always\b",
        #
        # Second pass. These were found by rewriting the first pass and watching which shapes the
        # rewrite reached for. A sweep that only removes the listed phrases moves the register into
        # whatever is one step away from them, and these are the steps it took.
        #
        # The is-what-VERBs construction, generalized from the makes variant above.
        # code-documentation section 126 names ten verbs and code-comments section 205 names six of
        # the same ten.
        #
        # The second alternation is this file's own, and it is where the bare carry, hold, cost,
        # read, buy, pay, spend, earn, win, price and slot bans went when they came out below.
        # Section 143 states the rule those bans were breaking: "a word that reads as a tic in one
        # construction only is bounded to that construction." This is the construction.
        r"\bis what (separates|keeps|tells|puts|says|makes|supplies|gives|decides|holds|stops|lets"
        r"|carries|costs|reads|buys|pays|spends|earns|wins|prices|slots|books)\b",
        # The X-not-Y shape wearing never instead of not. The first sweep wrote these by hand.
        r"\b(is|was|are|were) an? [\w-]+ and never an? [\w-]+",
        # The same dramatic tag as the else variant above, one synonym over.
        r"\band nothing more\b",
        r"\band no more\b",
        # Raising a definite article into a verdict, which is-the-one catches in one tense only.
        r"\bthe one (thing|place|case|word|reason|table|file|grain|repair|mistake|addition|column)\b",
        r"\bthe whole of (the|what|it)\b",
        r"\bis precisely (what|why|the)\b",
        r"\b(what|that) matters (is|here|most)\b",
        #
        # The machine-prose vocabulary. None of these is wrong English and none is a claim about a
        # measurement. None of them breaks a build. They are the words a reader has learned
        # to read as unwritten, and a page carrying them gets skimmed instead of read. Nothing in a
        # library about memory, entropy or crystal axes needs any of them.
        #
        # Two rules kept words off this list. A term the field owns stays: a grammatical paradigm, a
        # robust estimator, a significant difference, an alignment. And a word that only reads as a
        # tic in one construction is bounded to that construction instead of banned outright.
        r"\bdelve",
        r"\btapestry\b",
        r"\brealm\b",
        r"\bmyriad\b",
        r"\bplethora\b",
        r"\bseamless",
        r"\bgame.?chang",
        r"\bcutting.edge\b",
        r"\bstate.of.the.art\b",
        # Bounded to the shape. A grammatical paradigm is the field's own word and six sites use it.
        r"\bparadigm shift\b",
        r"\bsynergy\b",
        r"\bholistic\b",
        r"\bmeticulous",
        r"\bintricate\b",
        r"\bprofound\b",
        r"\bpivotal\b",
        r"\bcrucial\b",
        r"\bvital\b",
        r"\bnuanced\b",
        r"\bmultifaceted\b",
        r"\bcompelling\b",
        r"\binvaluable\b",
        r"\bunparalleled\b",
        r"\bunwavering\b",
        r"\btransformative\b",
        r"\bgroundbreaking\b",
        r"\brevolutioni[sz]",
        r"\bvibrant\b",
        r"\bbustling\b",
        r"\bnestled\b",
        r"\bcaptivat",
        r"\bresonat(e|es|ed|ing)\b",
        r"\btreasure trove\b",
        r"\bwealth of\b",
        r"\babundance of\b",
        r"\becosystem\b",
        r"\btestament to\b",
        r"\bboasts\b",
        r"\bshowcase",
        r"\bempower",
        r"\bstreamline",
        r"\bembark\b",
        r"\bendeavor\b",
        r"\bfoster(s|ing)?\b",
        r"\bcultivat(e|es|ing)\b",
        r"\belevat(e|es|ing)\b",
        r"\bbolster",
        r"\bunderpin",
        r"\bspearhead",
        r"\bleverag(e|es|ed|ing)\b",
        r"\butili[sz](e|es|ed|ing|ation)\b",
        r"\bfacilitat(e|es|ed|ing)\b",
        r"\bunleash",
        r"\bsupercharg",
        r"\beffortless",
        r"\buser.friendly\b",
        r"\btop.notch\b",
        r"\bworld.class\b",
        r"\bmust-have\b",
        r"\bunlock(s|ing)? the\b",
        r"\bharness(es|ing)? the\b",
        r"\bnavigat(e|es|ing) the\b",
        r"\bthe landscape of\b",
        r"\bjourney\b",
        r"\bdeep div",
        r"\bdiv(e|es|ing) (into|in|deeper)\b",
        r"\bunpack (this|the|that)\b",
        r"\bcircle back\b",
        r"\bever.(evolving|changing)\b",
        r"\brich history\b",
        r"\bkey (takeaway|insight)",
        r"\bactionable\b",
        r"\bbest practices\b",
        r"\bcomprehensive guide\b",
        r"\baforementioned\b",
        r"\balbeit\b",
        r"\bpertaining to\b",
        # Verbs and phrases that assert significance without stating any.
        r"\b(underscores|highlights|showcases|illustrates|exemplifies) the\b",
        r"\bsheds light on\b",
        r"\bpaves the way\b",
        r"\bplays an? [\w-]*\s?role\b",
        r"\b(serves|stands) as an?\b",
        r"\bstands out\b",
        r"\bsets it apart\b",
        r"\bat (its core|the heart of)\b",
        r"\blies at the\b",
        r"\bone of the most\b",
        r"\bsome of the most\b",
        # Filler that opens a sentence and carries nothing.
        r"\bit (is|'s) (important|worth|useful|helpful) (to note|noting|to remember|to mention|mentioning)\b",
        r"\bit should be noted\b",
        r"\b(furthermore|moreover|additionally)\b",
        r"\b(notably|interestingly|importantly|crucially|remarkably)\b",
        # Bounded to the punctuation the filler form carries. Unbounded, "in summary" matched
        # `for row in summary` and asked an agent to rewrite a list comprehension.
        r"\bin (conclusion|summary|essence)[,.:]",
        r"\bto sum up\b",
        r"\ball in all\b",
        r"\bthe bottom line\b",
        r"\bat the end of the day\b",
        r"\bin (today's|an era|the world of)\b",
        r"\bfirst and foremost\b",
        r"\blast but not least\b",
        r"\bneedless to say\b",
        r"\bit goes without saying\b",
        r"\bfor all intents and purposes\b",
        r"\bthat (being said|said),",
        r"\bon the other hand\b",
        r"\b(arguably|essentially|basically|fundamentally)\b",
        r"\bquite simply\b",
        r"\b(simply|put) put\b",
        r"\bin many ways\b",
        r"\bto some extent\b",
        r"\bwhen it comes to\b",
        r"\bin (order to|terms of)\b",
        r"\bdue to the fact that\b",
        r"\bwith regards? to\b",
        r"\ba (wide range|variety) of\b",
        r"\bthere is no denying\b",
        r"\blook no further\b",
        # Talking to the reader instead of writing for them. Bounded to the contraction: lets is a
        # verb.
        r"\blet['’]s\b",
        r"\blet us\b",
        r"\bwe (will|'ll) (explore|look|dive|examine|see)\b",
        r"\bas you can see\b",
        r"\bwhether you'?re\b",
        r"\bimagine (a|an|the|that|if)\b",
        r"\bpicture this\b",
        r"\bthink of it as\b",
        r"\bhere'?s (the thing|why|how)\b",
        r"\bthe truth is\b",
        r"\b(certainly|absolutely|of course)[!,]",
        r"\bgreat question\b",
        r"\b(hope this helps|happy to help|feel free to|let me know if)\b",
        r"\bas an ai\b",
        # The not-just-X-but-Y shape, the X-not-Y shape inflated.
        r"\bnot (just|only) .{1,40}\bbut (also )?\b",
        r"\bmore than just\b",
        r"\bit'?s not (just )?about\b",
        #
        # Superlative adjectives, which promise a size without giving one. A measurement states how
        # large it is; these state that it was large.
        r"\b(remarkable|noteworthy|impressive|exceptional|extraordinary|outstanding)\b",
        r"\b(stellar|superb|phenomenal|tremendous|immense|enormous|staggering)\b",
        r"\b(countless|endless|limitless|boundless|unmatched|unrivall?ed)\b",
        r"\b(premier|foremost|quintessential|iconic|legendary|timeless)\b",
        # sweeping came off this line. A parameter sweep is an operation this tree runs, and the
        # rule made three agents reword correct prose about one.
        r"\b(far.reaching|wide.ranging|all.encompassing|overarching)\b",
        # imperative came off this line. code-comments/SKILL.md:99 requires "@brief Single-sentence
        # summary using imperative voice". The grammatical mood is the field's own word here and the
        # rule reported the standard for naming it. Section 143's first escape: a term the field
        # owns stays.
        r"\b(indispensable|paramount)\b",
        r"\b(sophisticated|layered|expansive|exhaustive)\b",
        r"\b(stunning|striking|breathtaking|awe.inspiring|mesmeri[sz]ing|dazzling)\b",
        r"\b(intuitive|elegant|sleek|polished|frictionless)\b",
        r"\b(rigorous|painstaking|diligent|thorough)\b",
        r"\b(innovative|disruptive|trailblazing|visionary)\b",
        # powerful came off this line. The thought experiments discuss power as a subject, and the
        # rule turned "selects for the powerful" into a rewrite of a claim about people.
        r"\b(scalable|versatile)\b",
        # Verbs that inflate what the code does.
        r"\b(uncover|unveil|illuminate|unearth|unravel|demystify)",
        # amplify, boost and maximize came off this line. All three are literal here: a controller
        # arm amplifies, an audio band is boosted, and a quantity is maximized in the ordinary math
        # sense.
        r"\b(enhance|augment)\b",
        # transform came off this line and cost the most. A Fourier transform, inverse transform
        # sampling and a reversible transform are all nouns of art in this tree, and the pattern
        # reported 22 correct sites. The inflating use is a marketing verb; it is not worth this.
        r"\b(redefine|reimagine|reinvent)(s|ed|ing)?\b",
        r"\b(traverse|venture|spotlight|champion|nurture)\b",
        r"\btap into\b",
        r"\bbridge the gap\b",
        r"\b(open the door|set the stage|lay the foundation)\b",
        # Office idiom. Every one of these replaces a fact with a gesture at one.
        r"\ba double.edged sword\b",
        r"\bthe tip of the iceberg\b",
        r"\ba perfect storm\b",
        r"\bfood for thought\b",
        r"\bthe elephant in the room\b",
        r"\blow.hanging fruit\b",
        r"\bmov(e|es|ing) the needle\b",
        r"\bboil the ocean\b",
        r"\bnorth star\b",
        r"\bsecret sauce\b",
        r"\bsilver bullet\b",
        r"\bholy grail\b",
        r"\bforce multiplier\b",
        r"\btable stakes\b",
        r"\bquantum leap\b",
        r"\b(sea|step) change\b",
        r"\b(30|10),?000.foot view\b",
        r"\bon the same page\b",
        r"\bhit the ground running\b",
        r"\bthink outside the box\b",
        r"\bpush the envelope\b",
        r"\braise the bar\b",
        r"\bthe name of the game\b",
        r"\bin a nutshell\b",
        r"\bthe crux of\b",
        r"\bat its heart\b",
        # More of the array-of-things filler.
        r"\ba (wide array|host|multitude|spectrum|plethora) of\b",
        r"\ban array of\b",
        r"\bthe (intersection|convergence) of\b",
        # Transitions that announce a turn the sentence already made.
        r"\b(having said that|with that said)\b",
        r"\bin light of\b",
        r"\bas such,",
        r"\b(consequently|nevertheless|nonetheless|conversely)\b",
        r"\bindeed,",
        r"\bof note,",
        r"\b(it is here that|this is where)\b",
        r"\benter (the|a) \w+\.",
        # Blog scaffolding. None of it belongs in a comment or a research page.
        r"\bkey takeaways\b",
        r"\btl;?dr\b",
        r"\bpros and cons\b",
        r"\bin this (article|post|guide|section, we)\b",
        r"\bwe'?ll cover\b",
        r"\bby the end of this\b",
        r"\bwithout further ado\b",
        r"\bstay tuned\b",
        # Hedged attribution with nobody attached.
        r"\b(one might argue|some might say|it could be argued|it bears mentioning)\b",
        # The assistant register. None of this is written by a person about their own code.
        r"\bas a language model\b",
        r"\bi (don'?t|do not) have (the ability|access|personal)\b",
        r"\bmy training data\b",
        r"\b(i apologi[sz]e|my apologies|sorry for the)\b",
        # Tier four, and the test for it was a search. Each shape below was looked up and returned
        # no result dated before 2020. A phrase people did not write until models wrote it is a
        # phrase to cut. The distance instrument reads the same tree the same way: 79.6 percent of
        # the margin on docs/research/index.md sat on sentence shape.
        #
        # A clause that announces a conclusion and carries no fact.
        r"\bthat is (what|why|the (difference|point|whole|answer|test|reason|rule|shape|cost))\b",
        # Searched with the measuring word attached as well. "which is how far" returns nothing
        # dated before 2020 either. The exemption it looked like it deserved was not there.
        r"\bwhich is (what|why|how|the (difference|point|whole|answer|reason|rule))\b",
        # Bounded to the same noun list its sibling three lines up already carries. The bare `the`
        # arm was drift between two patterns written for one shape, and it fired on
        # code-documentation/SKILL.md:133, "and that is the defect: each occupies the place a fact
        # goes", where the clause carries the fact instead of standing in for one.
        r"\band that is (what|why|the (difference|point|whole|answer|test|reason|rule|shape|cost))\b",
        # Defining a thing by what it is not.
        r"\b(checking|reading|running|measuring|saying) [a-z]+ is not [a-z]+ing\b",
        r"\bis not an? (accusation|argument|claim|answer|excuse|guess|estimate)\b",
        # proof and evidence are the field's own words here. "a row that checked nothing is not
        # evidence that anything held" is a precise claim about a bench and it stays.
        r"\bis not (a pass|passing|failing)\b",
        # WITHDRAWN: \bworse than (not|nothing|none|no |having)\b and \bis worse than a\b. Both
        # fired on the standards. code-documentation/SKILL.md:84 writes "A wrong line number is a
        # false claim and worse than none", :165 writes "A stale section is worse than a missing
        # one", and code-comments/SKILL.md:122 writes the first of those again about a MISRA rule
        # number. A comparison of two failure modes by cost is the ordinary way to state which one
        # to prefer.
        #
        # WITHDRAWN: \bstated (once|twice)\b, \btwo facts that\b and \bone fact per\b. These banned
        # the standards' own rule text. Both files write "One fact is stated once; a second copy is
        # a future contradiction" at :21, code-documentation writes "One fact per sentence" at :146
        # and code-comments writes it at :199. A checker that reports the sentence stating a rule as
        # a violation of that rule is the over-reach class this pass exists to remove. Machinery
        # given intent. A run does not say anything and a file does not answer. A run of characters
        # is the field's own term and predates all of this. Only the execution sense is banned. The
        # verb has to be one a program does.
        r"\ba run that (finishes|reads|reports|says|passes|fails|completes|knows|decides)\b",
        r"\b(the (file|tool|check|hook|run|number|count|table)) (says|answers|knows|decides)\b",
        # Hedges, and a pointer left behind after the thing it pointed at was cut.
        r"\bthe ordinary (case|answer)\b",
        r"\bnothing else here\b",
        # "nothing here is a timing claim" states a scope and stays. The banned form is the flourish
        # that closes a paragraph on nothing.
        r"\bnothing here is (new|magic|special|clever|hidden|secret|surprising)\b",
        # \band nothing else\b was written here a second time. One rule in two places is two rules
        # that can be edited apart, and banned_hits deduping on (line, offset, token) kept
        # the second copy from doubling every finding for as long as it stood. The copy near the
        # head of this tuple stays, beside the and-nothing-more and and-no-more
        # forms it belongs with. Tier five, the preachy register, and the whole tier came out of one
        # session's own output. Writing about a corpus that belongs to somebody else pulls prose
        # toward the sermon, and the sermon is worse than useless here: every line in this
        # repository carries one person's name, and a paragraph telling the reader how to feel about
        # the material reads as that person performing and not stating. The ethics are in the
        # permission column and in what the gates refuse. They do not need narrating on top.
        #
        # The rule this tier enforces is that a fact is stated once, flat, and left alone.
        #
        # Moral entitlement. Whatever is owed here is settled in the licence and in SPEECH.tsv.
        r"\b(is|are|was|were) (the least|what) (they|we|he|she|you|somebody) (are |is |)?(owed|deserve)",
        r"\b(the least|more) (they|we|you) (deserve|are owed)\b",
        r"\bwe owe (them|him|her|you|it)\b",
        r"\bentitled to (make|take|say|claim)\b",
        # Ranking two things by worth. Three patterns were tried here and dropped after they fired
        # on real engineering prose in this tree. "a miss is worth more than a hit here" is a claim
        # about what a diagnostic tells you, "the whole point of the file" names what a function is
        # for, and "as distinctive as it should be" is a measurement against a prediction. None of
        # those is the register this tier is after, and banning them would have cost five true
        # sentences to catch two of mine. What is left is the shape that only ever shows up in a
        # sermon.
        r"\bthe more valuable\b",
        r"\bthe (smallest|least) part of what\b",
        r"\bworth more than (the|their|his|her|any) \w+ (itself|themselves)\b",
        # Aphorism built on a moral antithesis. "something done, never something suffered" is the
        # shape.
        r"\b(something|anything) [a-z]+ed, never (something|anything)\b",
        r"\bnever something (suffered|taken|lost|given)\b",
        # Declaring what a thing means to the reader.
        r"\bis what makes it (beautiful|worth|matter|special|right)\b",
        r"\bthat is the (beauty|tragedy|point) of\b",
        r"\ba person is not a\b",
        # Piety markers and the invitation to reflect.
        r"\b(it bears remembering|let us remember|we must remember|never forget)\b",
        r"\bwith the respect (it|they|that) deserve",
        r"\b(honou?r|honou?ring) (the|their|his|her) (memory|words|wishes|legacy)\b",
        # Announcing one's own virtue in doing the ordinary thing. The comma separates the
        # flourish from the measurement: "as distinctive as it should be" is a comparison and
        # ", as it should be" is a pat on the back.
        r"\bthe right thing to do\b",
        r",\s*as it should be\b",
        # The second half of the preachy tier, added after the first half missed a whole page of it.
        # The moral vocabulary was gone and the register was not: what replaced it was a comment
        # arguing for its own design against an imagined sceptic, with a closing line for emphasis.
        # A header states what a thing does and what it covers. Whoever reads it can decide for
        # themselves whether that was a good idea.
        #
        # Closers. A sentence added after the fact was already stated, to land it.
        r"\bis the kind nobody\b",
        r"\bnobody (looks at twice|reads twice|rechecks|checks twice)\b",
        r"\band they could not have\b",
        r"\bwhich is the whole\b",
        # Emphasis by repeating the verb against its own negation. "holds something" and "holds
        # nothing" were tried here and dropped: six sites in this tree use them for exactly what
        # they say, as in "a shuffle holds nothing beyond one symbol" and "a domain that holds
        # nothing". What made the banned version preachy was the verb repeating against itself
        # across a clause, and no pattern separates that from the plain use. This is the third
        # over-broad rule added to this file and caught by running it. Run it before keeping the
        # next one.
        r"\bwould (prove|buy) nothing\b",
        # A bare abstraction standing in for the subject, usually in a closing clause.
        r"\bthe (reproducible|checkable|measurable|honest|valuable) thing\b",
        # Arguing the design instead of describing it.
        r"\bagainst how (somebody|someone|anybody|people)\b",
        r"\bin nearly every (respect|way|case)\b",
        r"\bdoes not put a (reader|person|user) on the path\b",
        r"\ba (rule|check|gate|test) added here\b",
        # Tier six, and the first tier this file did not find by itself. A 340 word passage of
        # theory/theory/crystallography/chapters/chapter_whose_result.tex was scored by an outside
        # detector, which returned 80.4 percent machine written and marked which sentences carried
        # it. Every shape below is out of a marked sentence and was not already in the table above.
        #
        # The outside number is worth little on its own. A detector reading perplexity marks plain
        # declarative technical prose as machine written because that prose is low perplexity, which
        # is a property of the register and not of the author. What makes this tier worth adding is
        # that two unrelated instruments picked the same file: the eight patterns below were counted
        # across 53 documents before any was kept, and chapter_whose_result.tex is 26 lines long and
        # trips five of them, at lines 10, 16, 18, 20 and 24. No other file in the tree is that
        # dense.
        #
        # Counted first, per the rule the tiers above set: 11, 17, 3, and 1 apiece for the rest.
        #
        # The X-not-Y antithesis wearing definite articles. Line 30 and line 78 ask for a or an.
        # Therefore "the good outcome and not the bad one" walks past both of them.
        r"\b(is|was|are|were) the [\w-]+ and not the [\w-]+",
        # The pseudo-cleft, which holds a plain statement back and then delivers it as a reveal.
        r"\bwhat is \w+ is\b",
        # A hypothetical comparison the work makes about itself.
        r"\bit would be a (worse|better) [\w-]+ to\b",
        # Justifying a label by pointing at behavior, in a sentence that already gave the label.
        r"\bbecause of what \w+ (does|did|is|was)\b",
        # Naming a thing and then restating that it is one, to give the sentence a second beat.
        r"\band it is one\b",
        # Parallel negation hung off a passive claim.
        r"\band none is (wanted|claimed|needed|asked|offered|sought)\b",
        # The nothing-else tag one preposition away from the form banned above.
        r"\bon nothing else\b",
        # Half of a can-only against cannot pair. Each half is ordinary and the pairing is the tic,
        # which no single pattern reaches. This catches the half that carries it.
        r"\bcan only show (that|whether)\b",

        # ---- Added 2026-09-11, found by a detector probe and not by a frequency table. ----
        #
        # Everything above came from comparing token frequencies against a human corpus, which finds
        # TOKENS. It cannot find a sentence whose every word is ordinary and whose SHAPE is the
        # tell, and those pass the gate and still read wrong.
        #
        # Method: prose was written in the register being hunted, then scored per sentence by
        # Sapling's detector - twice, with different wording carrying the same shapes. A sentence
        # was kept only if it scored high AND tripped nothing already in this tuple, and a shape
        # only if it recurred across both batches, since one high score is that detector's noise. No
        # document from either tree was sent anywhere: the register is the thing being
        # characterised, and prose about nothing characterises it as well as prose about the work,
        # with nothing at stake in it.
        #
        # Each was then run against the whole tree. These ten matched nothing already written. "not
        # merely" was REJECTED by the same test: it hit eighteen live lines, every one of them the
        # deliberate X-and-not-merely-Y idiom this work uses on purpose. Banning it would have
        # removed a construction and not a tic, the failure a ban list has to be
        # checked for before anything is added to it.
        #
        # One calibration note for anyone extending this. The detector scored "It was a warm
        # afternoon and the window was open" at 0.99, which looks like a false positive and is not
        # one: that sentence is scene-setting, which belongs to fiction, and in technical prose a
        # register mismatch is exactly what it reads. Narrative openers are a real shape here and no
        # pattern below reaches them, because a regex cannot see register. They still have to be
        # caught by eye.

        # The hedge that closes a section while conceding nothing.
        r"\b(further|additional|more) (research|work|study|studies|investigation|analysis) (is|are) needed\b",
        # Announcing emphasis instead of emphasising.
        r"\bit is worth (emphasi[sz]ing|stressing|highlighting)\b",
        # The universal caveat, which says only that cases differ.
        r"\bone-size-fits-all\b",
        # A summary adverb opening a sentence that goes on to summarise nothing.
        r"(?m)^\s*Ultimately,",
        # Architectural metaphor doing the work a plain claim should do.
        r"\bthe foundation (up)?on which\b",
        # Frontier talk. Always about the field, never about the measurement.
        r"\bpush(?:ing|es|ed)? the boundaries\b",
        # Certainty about the future, in a sentence whose claim carries none.
        r"\bwill inevitably\b",
        # The paradox opener, promising depth before any has been shown.
        r"\bdeceptively simple\b",
        r"\bstay(?:ing)? ahead of the curve\b",
        r"\bhas never been more important\b",

        # Tier seven, and the first tier an outside detector found instead of a person. One passage
        # of theory/theory/Salishan/chapters/chapter_Salishan_pure_corpus_README.tex read 35.6 percent
        # machine written. Six constructions came out of it and the same passage read 4.5 percent,
        # with every fact and every number unchanged. The patterns below are those six.
        #
        # What they share is that each one puts the document in the subject position and gives it a
        # verb of authority or of reading. A page does not settle a character and a reading is not
        # an authority. A person settled it, off that page.
        r"\bis (?:the|an?) authority for\b",
        r"\bit then reads as\b",
        r"\bare settled on page\b",
        # The temporal hedge on a state nobody dated. Either the table has the note or it does not.
        r"\b(?:table|document|page|file|row) first had no\b",
        # A colon splicing two independent clauses, the elaboration shape section 6 bans in
        # prose and which the detector scores the same way.
        r"\bhas no call and no text:",

        # Tier eight. Sapling scored the passage these came from at 0.1 percent, every sentence 0.0,
        # and the author read the same passage and said it was not his writing. An outside detector
        # is trained on published machine prose. Whether a page sounds like the person whose name is
        # on the book is a different question and it does not answer it.
        #
        # These four came out by ear. All of them name a table field and then give it something to
        # do. The tree already calls that field the who column, and somebody fills it in by hand.
        r"\bthe slot stays empty\b",
        r"\bwere read off page\b",
        r"\bread by hand with no reader\b",
        r"\bthe record slot is empty\b",
        # Four words where one does. The entry that carried this now reads "No speaker named."
        r"\bis named as having\b",
        r"\bnobody wrote an? \w+ for this one\b",
        # Padding on a possessive. The paper's text is the paper.
        r"\b(?:paper|page|file|table|document)'s own text\b",
        # The instrument named by category and then given a passive. It has a filename: oracle.tsv,
        # and the entry now reads "Oracle.tsv checked against the paper."
        r"\bthe oracle is checked against\b",

        # One entry of chapter_Salishan_pure_corpus_README.tex was read out loud against these and
        # every one came out. What is left of that entry is eleven facts and no sentence about them.
        #
        # A reading, a page or a mark given authority over a question.
        r"\bneither (?:is|settles|decides|says) what\b",
        r"\bis (?:not )?the authority for what\b",
        # A count announced as a superlative instead of given.
        r"\bonly mark dropped\b",
        r"\bthe only place a \w+ was dropped\b",
        # A footnote reported as though its absence were an event.
        r"\bhas no call and no text\b",
        # The mark has a name. The book uses glottalization mark three times.
        r"\bglottal tick\b",
        r"\bwith a tick added\b",
        # Two sentences restating the sentence before them. Where the magnification already
        # appeared, saying it again is the paragraph explaining itself.
        r"\bat that magnification\b",
        # Declaring a field empty, in a document whose rule is that an empty field says so by being
        # empty.
        r"\bwho column empty\b",
        r"\bhis name does not go in it\b",
        # A participle standing in for the condition. Name the condition: doing it without saying
        # so.
        r"\bmade quietly\b",
        r"\bif it were made quietly\b",
        # A pipeline given a dependency. Name the caller: no text tool calls it.
        r"\bnothing in the \w+ pipeline depends\b",
        r"\bnothing downstream depends\b",
        # A digest placed somewhere by itself. Name the file that carries it.
        r"\bits SHA-256 sits in\b",
        r"\b(?:hash|digest|checksum) sits in\b",
        # A tool or a representation given eyes. A script reads a file, a representation is the
        # output.
        r"\b(?:sound|text|word) representation reads\b",
        r"\bthe representation reads\b",
        # Deixis repeating the heading it sits under.
        r"(?m)^This one does not read\b",
        r"\bno (?:text|other) tool calls it\b",
        # Exclusivity asserted about a set the reader cannot see. Either it is the only one, cited,
        # or the clause comes out.
        r"\band no other tool does\b",
        r"\bno other \w+ does\b",
        # A file given a residence. It is kept somewhere and run from somewhere, by somebody.
        r"\blives in the closed\b",
        r"\bit lives in\b",
        r"\band is run from there\b",
        # A script given eyes, under a heading that already named it.
        r"\breads the recordings\b",
        # The summarizing sentence at the end of a paragraph, restating what the paragraph said. The
        # paragraph is the statement.
        r"(?m)^A \w+ therefore\b",
        # WITHDRAWN 2026-09-16. carry and hold in every form used to sit here, and the bare word
        # bans for slot, book, construction, cost, buy, pay, spend, earn, afford, win, price and
        # read sat further down. All thirteen are gone. What replaced them is the is-what-VERB
        # construction above, and the narrow phrases each tier already carried stay where they are.
        # WITHDRAWN at the foot of this tuple records every one, with the count it cost and the
        # sentence that removed it.
        #
        # The comment that used to stand here is kept, because the observation in it was real and
        # the rule built on it was not: "A digest is listed in a manifest. A value is in a column. A
        # form appears on a page." That is a house preference for a precise verb, and precise verbs
        # are worth wanting. It is not a register tell, and a bare word ban is not how it gets
        # enforced.

        # The provenance section of the workbook, read out loud. Every one of these came out of one
        # page.
        #
        # shape, where nothing has a shape. The topology books use it for a real one and are the
        # only place it stands.
        r"\bfor that shape and reports\b",
        # WITHDRAWN: bare \bthat shape\b. It fired on code-documentation/SKILL.md:51, "putting that
        # shape at the head of a .md is a defect introduced rather than a rule satisfied", where the
        # shape is an SPDX header block and is a real one. The bounded form above stays.
        # A claim described by its three possible forms instead of stated.
        r"\ba claim that something here is new\b",
        r"\bnew, first,? or absent\b",
        # A repository given the power to settle things, then denied it.
        r"\bcannot settle that kind of claim\b",
        r"\bfrom inside itself\b",
        # Position standing in for the relation. A reference is attached to a claim or it is
        # missing.
        r"\bno reference beside it\b",
        # WITHDRAWN: bare \bbeside it\b. It fired on code-documentation/SKILL.md:84, "cite the line
        # that shows the thing being said, not the line beside it", where beside it is literal
        # adjacency in a file and is the whole of what that rule is about. The bounded form above
        # stays. The reading, as a thing that happens without a reader.
        r"\bthe reading has not been done\b",
        # A script given a character: it reports, it never decides, it is honest about itself.
        r"\bit reports and never decides\b",
        r"\breports and never\b",
        # An emphatic tail on a count that was already exact.
        r"\bare mixed at all\b",
        r"\b(?:is|are|was|were) \w+ at all\b",
        # slot, in every form. Nothing here has slots. A field has a name already: the who column,
        # the year field, the identifier. A chaining state has positions, and FIPS 180-4 calls its
        # eight a through h the working variables.
        #
        # 29 hits in theory/ when this went in, 25 of them in the SHA-256 chain chapter.
        #
        # WITHDRAWN 2026-09-16, bare \bslot(?:s|ted|ting)?\b. See WITHDRAWN at the foot of this
        # tuple. The narrow phrases the same tier wrote stay: the slot stays empty, the record slot
        # is empty.
        r"\bthe slot (?:holds|carries|gives|takes|decides)\b",
        # A copy given a job. The value is the same at both ends and nothing moved it.
        r"\ba copy that transports\b",
        r"\btransports a \w+ without\b",
        # A fact filed somewhere by itself, and a section named for an accounting nobody kept.
        r"\band is recorded\b",
        r"\bunder what it cost\b",
        # A verdict announced, then restated as its own announcement. The word is Unconfirmed, or
        # Inconclusive.
        r"\bis unconfirmed and is recorded\b",
        r"\bunconfirmed and written down\b",
        r"\bthe candidate mechanism\b",
        r"\brecorded as a candidate\b",
        # book. These are theories. 115 uses in theory/ when this went in, 24 of them in the ledger.
        # construction. It is a method.
        #
        # WITHDRAWN 2026-09-16, bare \bbooks?\b and \bconstruction\b. Both are naming rules about
        # this tree's own vocabulary and neither is a register claim. Section 143 has no
        # construction to bound them to. code-comments/SKILL.md:199 writes "Antithesis, parallelism,
        # and colon-then-elaboration are essay construction, not comment construction". The second
        # of the two reported the standard twice in one sentence. See WITHDRAWN at the foot of this
        # tuple. A caveat given descendants, and the pair of clauses that always follows it.
        r"\binherits that\b",
        r"\brecorded here inherits\b",
        r"\bevery one of them \w+ and none of them\b",
        # The verb has to be a verb. \w+s also matches is, was and has. This fired on
        # code-documentation/SKILL.md:133, "None of them is wrong English and none carries a
        # measurement", where the clause is a plain statement about a word list.
        r"\bnone of them (?!is\b|was\b|has\b|does\b)\w+s\b",
        # cost, in every form. A retrieval that took five attempts took five attempts. Say the
        # number.
        #
        # No exception. Give the number and its units: corpus symbol accesses, character
        # comparisons, cycles, bytes.
        r"\ba measured cost\b",
        # The rest of the transaction. A fold does not buy rounds, an arm does not win, a
        # measurement does not earn or spend or pay. 84 of these in theory/ when they went in: buys
        # 19, wins 17, earns 8, spends 7.
        #
        # WITHDRAWN 2026-09-16: the bare cost, buy, bought, pay, paid, spend, spent, earn, afford,
        # win, won, read and price bans. The observation behind them stands and the bare word ban
        # does not. See WITHDRAWN at the foot of this tuple.
    )
)

# ====================================================================
# WITHDRAWN: THE THIRTEEN UNBOUNDED WORD BANS, AND WHAT TOOK THEM OUT
# ====================================================================
#
# Recorded instead of deleted, because each of these was added for a reason somebody had and a
# later reader who only sees the absence will add it back. The table is the same device
# repo_tools/docs/docs_maint/ai_words.py used for its own six withdrawals.
#
# THE RULE THAT REMOVED THEM. code-documentation section 143: "a word that reads as a tic in one
# construction only is bounded to that construction: paradigm shift is banned where paradigm is
# not." And the escape immediately before it: "A term the field owns stays."
#
# THE TEST THAT FOUND THEM, and it is mechanical. Neither standard bans any of these thirteen. Both
# standards USE eleven of them as ordinary technical English, in the same documents that authorize
# this checker:
#
#   carries      code-documentation:145  "carries this list as regexes"
#   holds        code-comments:208       "holds the list as regexes"
#   reads        code-comments:208       "reads .c and .h comments and docstrings"
#   spends       code-documentation:84   "it spends a reader's trust before it wastes their time"
#   buys         code-documentation:85   "breaks the line the prose is walking and buys nothing"
#   construction code-comments:199       "are essay construction, not comment construction"
#   costs        code-documentation:108  the register a rule applied wrongly costs a paragraph
#   carry        code-documentation:104  "A documented pointer with no token is an unanswered
#                                        question"; :161 "correct when carried by a real name"
#   slot         code-comments:195       "Name a Handle by Its Slots" -- a handle slot is this
#                                        tree's own term of art, named in a section heading
#   earns        code-documentation:114  "each one earned its place by measurement"
#   book         code-documentation:158  "A name already sitting in the tree is not evidence"
#
# So the gate flagged the standard it enforces, 65 times across the two files before this pass,
# every one of them outside a code span and in the standard's own running prose. That is the whole
# of the over-reach class and it needed no enumeration to find.
#
# WHY NONE OF THEM COULD BE BOUNDED THE WAY paradigm shift IS. The construction these read as a tic
# in is an inanimate subject taking a human verb, and no regex separates it from the correct
# technical use. "The header carries the checksum" and "the buffer holds the segment" are the right
# verbs in a network stack, and they are character for character the shape the ban was after.
# What IS bounded, and what these went into, is the is-what-VERB construction near the head of this
# tuple, which both standards name.
#
# WHAT IT COST IN RECALL, derived at the refs named and not carried in from anywhere. Against
# idemIP/src at 29a808c these thirteen produced 1,727 of that run's 2,669 prose findings, 64.7
# percent of the whole report, and none of them is an AI tell: "the header carries the checksum"
# and "the buffer holds the segment" are the right verbs in a TCP/IP stack. Against the two
# SKILL.md files they produced 65 hits, all of them in running prose.
#
# Per word at idemIP/src 29a808c, which is where the weight actually sits: hold 658, carry 518,
# read 337, slot 134, cost 66, spend 6, win 3, pay 2, then one apiece for buy, earn and
# construction. afford, price and book fired nowhere in that tree at all.
#
# Re-derived at 2ec83d2, which is origin/main and the ref that repository sat on an hour later, and
# every one of those numbers is the same. Two refs are named because one is not enough: two sessions
# read 58 British hits and 15 for this repository and the difference between them was a ref and no
# defect at all.
#
# Each entry is the word, what it was after, and the sentence that removed it.
WITHDRAWN = {
    "carry": "the verb in every inflection, banned, a digest would be said to be listed in a "
    "manifest instead. Both standards use it and code-documentation:145 uses it about "
    "this file. 518 hits in idemIP/src at 29a808c.",
    "hold": "added when the repair pass for carry wrote hold everywhere instead. Chasing a "
    "synonym is the sign that the rule is on a word and not on a shape. 658 hits in "
    "idemIP/src at 29a808c, the single largest pattern in the table.",
    "read": "a fold does not read and a person does, which is true and is not what \\breads\\b "
    'tests. code-comments:208 writes "reads .c and .h comments". 337 hits.',
    "slot": "nothing in the theory books has slots, which is a house naming rule about one "
    "directory. code-comments:195 makes a handle slot a term of art in a section "
    "heading. 134 hits.",
    "cost": "say the number and its units. The instruction is right and the ban is not: a cost "
    "is what a number measures. 66 hits.",
    "buy": 'the transaction metaphor. code-documentation:85 writes "buys nothing the reader '
    'asked for" and code-comments:178 writes "The letter buys explicitness". 1 hit.',
    "pay": "the same metaphor, one verb over. 2 hits.",
    "spend": 'the same again. code-documentation:84 writes "it spends a reader\'s trust". 6 hits.',
    "earn": 'the same again. code-documentation:114 writes "each one earned its place by '
    'measurement", the sentence that justifies half this table. 1 hit.',
    "afford": "the same again, and one of the three that fired nowhere in idemIP/src at all.",
    "win": "an arm does not win. True, and the word has a plain use the ban could not see. 3 hits.",
    "price": "added, a repair pass could not swap cost for it. A ban added to close the exit "
    "from another ban is the shape of a rule that is chasing words. 0 hits.",
    "book": "these are theories, which is a naming rule about this tree's own vocabulary and "
    "carries no claim about register at all.",
    "construction": 'it is a method. Same shape as book, and code-comments:199 writes "essay '
    'construction, not comment construction" while stating a rule this file '
    "implements.",
}

# docs-check: quoting
# ====================================================================
# THE THREE STAGES, AND WHAT MEASURED THEM
# ====================================================================
# The list above is one flat table and it was built by noticing. maint/prose/ban_evidence.py
# scored every pattern in it against 1,108,054 words of human research papers under build/papers,
# and against the 403,111 words of prose in this tree. That run split the table into three stages
# that filter at different widths, and the stages behave nothing alike.
#
# ALPHABET. Orthography, and it recovers the locale before it says anything about a writer. The
# papers are Canadian and British convention linguistics. Neighbour fires at 17.3 per hundred
# thousand words in them and analyse at 8.9, behaviour at 4.8, labelled at 2.9, centre at 2.3.
# None of that is machine prose. It is where the author is, and the American spellings this tree
# uses are a house rule and not a defect in anybody's English.
#
# WORD. Vocabulary, and the measurement mostly refutes it. Humans write crucial at 5.5, vital at
# 0.5, journey at 2.2, delve at 0.4, synergy at 2.4, utilize at 2.3 and leverage at 0.5. A ban on
# these removes ordinary academic English. They stay in the table because a house style is allowed
# to be narrower than the field, and they are reported as the weaker class they measured as.
#
# PHRASE. The structural shapes, and every one of them is confirmed. These nine appear 23.3 times
# per hundred thousand words in this tree and exactly zero times in 1.1 million words of human
# writing: is what separates and its family, is what makes, what survives, is the whole of, the
# X-not-Y grammar, that is the whole, and nothing more, what matters is, the one that matters.
# A clause that explains the sentence just written is the signature, and the phrase stage
# catches it.
#
# One caution the numbers earn. Absence from the papers is not proof a phrase is machine written:
# the papers are linguistics and a phrase can be missing because the domain is.
# Re-run ban_evidence.py after changing this table.
#
# MEASURED AGAINST THE ASSISTANT'S OWN PROSE, WHICH SETTLED IT
#
# maint/prose/session_prose.py takes the assistant's messages out of a session transcript. That
# corpus needs no label to be trusted, and it is the only one here whose author is not in question.
# 38,702 gated English words of it, against 759,815 of the papers, per hundred thousand words:
#
#   the whole list            643.4 assistant   387.9 human   112.8 this tree after a day of repair
#   the eight phrase shapes    56.8 assistant     0.0 human    26.4 this tree
#
#   rather                    240.3 assistant    57.6 human      4.2 times the human rate
#   which is why/what/the     131.8 assistant     3.2 human     41 times
#   so a                       46.5 assistant     1.3 human     36 times
#   is the one                 43.9 assistant     2.5 human     18 times
#   is exactly what/why/the    25.8 assistant     0.4 human     65 times
#   and nothing else           12.9 assistant     0.1 human    129 times
#   is what makes              10.3 assistant     0.0 human     absent from 759,815 human words
#   the one that matters        7.8 assistant     0.0 human     absent, and banned here by name
#
# Two things follow. The list was built by noticing and the noticing was accurate: the phrases
# called out by hand are the ones carrying the largest ratios. And every rate above is a floor,
# because those messages were written while the same phrases were under active suppression.
#
# An earlier note here said the vocabulary tier was refuted because humans use those words. That
# was measured against a corpus from an earlier model generation, two years older, and
# it was wrong. Humans do use them. The assistant uses the list at 1.66 times the human rate.
# docs-check: end quoting

# The locale stage is defined above BANNED, because BANNED splices it in and a tuple has to exist
# before it can be spliced. It used to be written here, ten literals with a second copy of the same
# ten inside BANNED doing the actual work.

# docs-check: quoting
# What each pattern costs a human writer, per hundred thousand words of the research papers.
# Measured, not estimated. A pattern absent from this table fired zero times in all 154 of them.
#
# Counted over 759,815 words, the papers after english_gate takes them down to English.
# An earlier version of this table divided by 1,108,054 instead, the raw token count including the
# Salishan orthography, the interlinear glosses and the IPA that fill these pages. Every rate in it
# was low by about 40 percent: rather read 40.4 and is 57.6, in order to read 26.6 and is 44.4.
# docs-check: end quoting
# Regenerate with maint/prose/ban_evidence.py after any change to the table above.
HUMAN_RATE = {
    r"\brather\b": 57.6,
    r"\bin (order to|terms of)\b": 44.4,
    r"\bneighbour": 23.8,
    r"\bon the other hand\b": 16.7,
    r"\b(furthermore|moreover|additionally)\b": 15.7,
    r"\b(indispensable|paramount|imperative)\b": 14.6,
    r"\b(consequently|nevertheless|nonetheless|conversely)\b": 14.3,
    r"\b(notably|interestingly|importantly|crucially|remarkably)\b": 14.0,
    r"\banalyse(s|d)?\b": 12.2,
    r"\b(remarkable|noteworthy|impressive|exceptional|extraordinary|outstanding)\b": 10.9,
    r"\b(arguably|essentially|basically|fundamentally)\b": 9.3,
    r"\bnot (just|only) .{1,40}\bbut (also )?\b": 8.7,
    r"\ba (wide range|variety) of\b": 8.3,
    r"\b(innovative|disruptive|trailblazing|visionary)\b": 8.3,
    r"\bcrucial\b": 7.8,
    r"\bbehaviour": 6.8,
    r"\blet us\b": 4.9,
    r"\b(stunning|striking|breathtaking|awe.inspiring|mesmeri[sz]ing|dazzling)\b": 4.7,
    r"\bwith regards? to\b": 4.6,
    r"\b(underscores|highlights|showcases|illustrates|exemplifies) the\b": 4.3,
    r"\blabelled\b": 4.2,
    r"\b(rigorous|painstaking|diligent|thorough)\b": 3.9,
    r"\bsynergy\b": 3.6,
    r"\butili[sz](e|es|ed|ing|ation)\b": 3.3,
    r"\b(serves|stands) as an?\b": 3.3,
    r"\b(premier|foremost|quintessential|iconic|legendary|timeless)\b": 3.3,
    r"\bwhich is (why|what|the)\b": 3.2,
    r"\bjourney\b": 3.2,
    r"\b(enhance|augment)\b": 2.8,
    r"\bin light of\b": 2.6,
    r"\bfacilitat(e|es|ed|ing)\b": 2.6,
    r"\bcentre\b": 2.6,
    r"\b(uncover|unveil|illuminate|unearth|unravel|demystify)": 2.6,
    r"\bis the one\b": 2.5,
    r"\bit should be noted\b": 2.2,
    r"\bit (is|'s) (important|worth|useful|helpful) (to note|noting|to remember|to mention|mentioning)\b": 2.2,
    r"\b(intuitive|elegant|sleek|polished|frictionless)\b": 2.0,
    r"\bone of the most\b": 1.7,
    r"\bimagine (a|an|the|that|if)\b": 1.7,
    r"\b(sophisticated|layered|expansive|exhaustive)\b": 1.7,
    r"\bwe (will|'ll) (explore|look|dive|examine|see)\b": 1.6,
    r"\bplays an? [\w-]*\s?role\b": 1.6,
    r"\bpertaining to\b": 1.4,
    r"\bcompelling\b": 1.4,
    r"\bcolour": 1.4,
    # Deliberately NOT widened to `so an?` when the Tier A ban above was. The 1.3 is a measured
    # human rate over 759,815 words, and it was measured for `so a`. Widening the pattern would
    # carry a rate to a population it was never taken over, the fault the rate exists to
    # avoid. `so an` is caught by the Tier A ban and needs no frequency entry; if one is ever
    # wanted, measure it.
    r"\bso a\b": 1.3,
    r"\bwhen it comes to\b": 1.1,
    r"\bamongst\b": 1.1,
    r"\balbeit\b": 1.1,
    r"\b(stellar|superb|phenomenal|tremendous|immense|enormous|staggering)\b": 1.1,
    r"\b(open the door|set the stage|lay the foundation)\b": 1.1,
    r"\bthe one (thing|place|case|word|reason|table|file|grain|repair|mistake|addition|column)\b": 0.9,
    r"\bin this (article|post|guide|section, we)\b": 0.9,
    r"\bfoster(s|ing)?\b": 0.9,
    r"\bvital\b": 0.8,
    r"\brealm\b": 0.8,
    r"\binvaluable\b": 0.8,
    r"\bdue to the fact that\b": 0.8,
    r"\ba (wide array|host|multitude|spectrum|plethora) of\b": 0.8,
    r"\b(countless|endless|limitless|boundless|unmatched|unrivall?ed)\b": 0.8,
    r"\bto some extent\b": 0.7,
    r"\bthe (intersection|convergence) of\b": 0.7,
    r"\bleverag(e|es|ed|ing)\b": 0.7,
    r"\bin many ways\b": 0.7,
    r"\bfirst and foremost\b": 0.7,
    r"\b(far.reaching|wide.ranging|all.encompassing|overarching)\b": 0.7,
    r"\bthe landscape of\b": 0.5,
    r"\bsome of the most\b": 0.5,
    r"\bintricate\b": 0.5,
    r"\bdelve": 0.5,
    r"\b(traverse|venture|spotlight|champion|nurture)\b": 0.5,
    r"\b(it is here that|this is where)\b": 0.5,
    r"\btreasure trove\b": 0.4,
    r"\bthe whole of (the|what|it)\b": 0.4,
    r"\bstands out\b": 0.4,
    r"\bprofound\b": 0.4,
    r"\bplethora\b": 0.4,
    r"\bnuanced\b": 0.4,
    r"\bis precisely (what|why|the)\b": 0.4,
    r"\bis exactly (what|why|the)\b": 0.4,
    r"\bendeavor\b": 0.4,
    r"\baforementioned\b": 0.4,
    r"\badd up\b": 0.4,
    r"\b(name|definition|token|type|structure|constraint)s?\s+(says|say|signals|signal|encodes|encode|conveys|convey|announces|announce|advertises|advertise)\b": 0.4,
    r"\buser.friendly\b": 0.3,
    r"\bunlock(s|ing)? the\b": 0.3,
    r"\bunderpin": 0.3,
    r"\bto sum up\b": 0.3,
    r"\bthe bottom line\b": 0.3,
    r"\bstate.of.the.art\b": 0.3,
    r"\borganis(e|es|ed|ing|ation|ations)\b": 0.3,
    r"\bneedless to say\b": 0.3,
    r"\blet['’]s\b": 0.3,
    r"\bas you can see\b": 0.3,
    r"\band no more\b": 0.3,
    r"\ban array of\b": 0.3,
    r"\ball in all\b": 0.3,
    r"\babundance of\b": 0.3,
    r"\b(simply|put) put\b": 0.3,
    r"\b(scalable|versatile)\b": 0.3,
    r"\b(having said that|with that said)\b": 0.3,
    r"\bwealth of\b": 0.1,
    r"\bthink of it as\b": 0.1,
    r"\bthe crux of\b": 0.1,
    r"\bthat is (what|why) \w+ (is|was|does|did)\b": 0.1,
    r"\bsheds light on\b": 0.1,
    r"\bresonat(e|es|ed|ing)\b": 0.1,
    r"\bon purpose\b": 0.1,
    r"\bnavigat(e|es|ing) the\b": 0.1,
    r"\bmodelled\b": 0.1,
    r"\blook no further\b": 0.1,
    r"\blies at the\b": 0.1,
    r"\bin a nutshell\b": 0.1,
    r"\bembark\b": 0.1,
    r"\becosystem\b": 0.1,
    r"\bcaptivat": 0.1,
    r"\bbolster": 0.1,
    r"\bbest practices\b": 0.1,
    r"\bat (its core|the heart of)\b": 0.1,
    r"\band nothing else\b": 0.1,
    r"\b(what|that) matters (is|here|most)\b": 0.1,
}


def stage_of(pattern):
    """Which of the three filters a pattern belongs to: alphabet, word or phrase.

    A pattern is alphabet when it matches one spelled form. It is phrase when it matches across a
    space, and that makes it a shape instead of a vocabulary item. Everything else is word.

    This answers what a pattern LOOKS like. tier_of answers what authority it carries, and the two
    disagree on purpose: see the note above AUTHORITY.
    """
    if pattern in LOCALE:
        return "alphabet"
    if " " in pattern:
        return "phrase"
    return "word"


# ====================================================================
# THE TWO TIERS, AND WHAT DECIDES WHICH ONE A PATTERN IS IN
# ====================================================================
#
# TIER A is a NAMED-CONSTRUCTION BAN: a construction one of the two standards bans in a sentence,
# quoted below with the file and line it is on. Tree-wide, no opt-in, no per-repo setting, every hit
# a finding. A per-repo switch on this tier would exempt a repository from a standard it is already
# under, which is backwards: the standard is the tree's, not each repository's.
#
# TIER B is FREQUENCY-SCORED VOCABULARY: a word or an idiom, reported with what it costs a human
# writer where that has been measured. Most of it is the machine-prose vocabulary code-documentation
# section 135 through 141 lists by word. The rest is this file's own house style, calibrated on
# anchor_sift's theory books and named as such in the report.
#
# THE TIER IS DECIDED BY THE SENTENCE IN THE STANDARD, NEVER BY THE REGEX. This is the correction
# that matters and it runs both ways:
#
#   `rather` is one token and matches one word. Stage_of calls it a word. Its ban is stated
#   outright at code-documentation:110 and again at code-comments:200. It is TIER A.
#   `\bis what (separates|keeps|...)` is a construction by shape and by authority alike, and the
#   verbs this file added to it beyond the standard's ten are TIER A all the same, because the
#   construction is the thing banned and the verb list is how far it reaches.
#   The X-not-Y patterns span several words and are TIER A. The superlative-adjective group spans
#   several words too and is TIER B, because section 137 lists adjectives.
#
# WHAT THE TIER CHANGES. Nothing about whether a run passes: prose never fails a build in either
# tier, --strict included, and the exit rule at the foot of main() is the whole of that contract.
# It changes what the report says, and it is the line an autofix would have to respect.
#
# A BANNED HINGE IS DISSOLVED, NEVER REPLACED. There is no --fix here and there must never be one
# for TIER A. code-documentation:110 bans `rather`; its obvious repair is the X-not-Y shape, which
# section 146 bans forty lines later in the same document: "The X-not-Y shape sounds decisive and
# carries almost nothing... State the thing that is true and let the contrast go unsaid, unless the
# reader would otherwise land on the wrong one." An automatic repair of the first rule produces the
# second at scale and reports a fix for every one. The two legal treatments are to give the second
# half its own plain sentence, or to drop the weaker half, and section 146's test decides which. A
# machine cannot run that test. Section 143 says the same thing from the other side: bans name
# CONSTRUCTIONS. Detection AND repair operate on constructions and never on words. TIER A is
# report-only, permanently. A token-for-token orthographic swap is the only class an autofix could
# ever own here, and that is the alphabet stage and not this table.
AUTHORITY = {
    # Three tokens banned outright. code-comments:200: "Three Tokens Are Banned Outright:
    # `spelling`, `so a`, and `rather`." Two of the three also carry a documentation ban at
    # code-documentation:110, and `spelling` is scoped to comments by its own sentence.
    r"\brather\b": "code-documentation:110, code-comments:200",
    r"\bso an?\b": "code-documentation:110, code-comments:200",
    # The comma-so consequence clause code-documentation:112 describes, which the so-a token above
    # only partly reached. Douglas widened the ban to every comma-so clause on 2026-09-16, recorded
    # at PLANS/PROSE_SO_CLAUSE_BAN.md. It is a named construction and belongs in Tier A.
    r",\s+so\s+(?!that\b|far\b)": "code-documentation:112",
    r"\bspelling\b": "code-comments:200, comments only",
    r"\badd up\b": "code-documentation:110",
    # The measured tics. code-documentation:116 through :121 gives each one its rise.
    r"\bthe one that matters\b": "code-documentation:116",
    r"\bis the one\b": "code-documentation:116",
    r"\bwhich is (why|what|the)\b": "code-documentation:117, code-comments:206",
    r"\band nothing else\b": "code-documentation:118, code-comments:207",
    r"\bthat is the whole\b": "code-documentation:119",
    r"\bis the whole (of|rule|point|thing|question|claim|job|story)\b": "code-documentation:119",
    r"\bthe whole (point|question|claim|rule|job|story) (is|was)\b": "code-documentation:119",
    r"\bwhat survives\b": "code-documentation:120",
    # The second pass. code-documentation:126 through :131.
    r"\bis what makes\b": "code-documentation:126, code-comments:205",
    r"\bis what (separates|keeps|tells|puts|says|makes|supplies|gives|decides|holds|stops|lets"
    r"|carries|costs|reads|buys|pays|spends|earns|wins|prices|slots|books)\b": "code-documentation:126, code-comments:205",
    r"\b(is|was|are|were) an? [\w-]+ and never an? [\w-]+": "code-documentation:127",
    r"\band nothing more\b": "code-documentation:128, code-comments:207",
    r"\band no more\b": "code-documentation:128, code-comments:207",
    r"\bthe one (thing|place|case|word|reason|table|file|grain|repair|mistake|addition|column)\b": "code-documentation:129, code-comments:207",
    r"\bthe whole of (the|what|it)\b": "code-documentation:130, code-comments:207",
    r"\bis precisely (what|why|the)\b": "code-documentation:131",
    r"\b(what|that) matters (is|here|most)\b": "code-documentation:131",
    # No rhetorical sentence shapes. code-documentation:146, code-comments:199.
    r"cost and not a defect": "code-documentation:146",
    r"\b(is|was|are|were) an? [\w-]+ and not an? [\w-]+": "code-documentation:146",
    r"\b(is|was|are|were) the [\w-]+ and not the [\w-]+": "code-documentation:146",
    r"(?m)(?:\A|(?<=[.!?] ))(?:(?:An?|The) )?[\w-]+, not (?:(?:an?|the) )?[\w-]+\.(?:\s|\Z)": "code-documentation:146",
    r"\bhas no call and no text:": "code-documentation:146",
    # Nothing inanimate speaks. code-documentation:147, code-comments:156.
    r"\b(name|definition|token|type|structure|constraint)s?\s+(says|say|signals|signal|encodes|encode|"
    r"conveys|convey|announces|announce|advertises|advertise|makes clear|make clear)\b": "code-documentation:147, code-comments:156",
    # No conversational filler. Four forms are named by name in both files.
    r"load-bearing": "code-documentation:148",
    r"\blet['’]s\b": "code-documentation:148, code-comments:155",
    r"\bdiv(e|es|ing) (into|in|deeper)\b": "code-documentation:148, code-comments:155",
    r"\b(certainly|absolutely|of course)[!,]": "code-documentation:148, code-comments:155",
    r"\bit (is|'s) (important|worth|useful|helpful) (to note|noting|to remember|to mention|mentioning)\b": "code-documentation:148, code-comments:155",
    # The assistant register. code-documentation:141.
    r"\bas an ai\b": "code-documentation:141",
    r"\bas a language model\b": "code-documentation:141",
    r"\bmy training data\b": "code-documentation:141",
    r"\b(i apologi[sz]e|my apologies|sorry for the)\b": "code-documentation:141",
    # The which-is clause again, in the form the later tier wrote it.
    r"\bwhich is (what|why|how|the (difference|point|whole|answer|reason|rule))\b": "code-comments:206",
}

# A selector that names nothing is drift, and drift in a table like this is silent: the tier simply
# stops being claimed and every finding in it prints as house style. ai_words.py learned this the
# expensive way and checks its own selectors the same way. Raised at import, not reported at
# runtime, because a tier that quietly holds no patterns reports clean forever.
_ORPHANS = tuple(one for one in AUTHORITY if one not in BANNED)
if _ORPHANS:
    raise SystemExit(
        "docs_check: AUTHORITY names %d pattern(s) that are not in BANNED. A tier "
        "selector matching nothing reports clean forever.\n  %s"
        % (len(_ORPHANS), "\n  ".join(_ORPHANS))
    )


# The tokens whose ban the standard scopes to comments in the sentence that states it.
# code-comments:200 bans three outright and bounds them in the same breath: "none has a legitimate
# use in a comment here". `so a` and `rather` carry a documentation ban of their own at
# code-documentation:110. Only `spelling` is left scoped. A page about a character encoding
# writes the word for what it means; a Doxygen block reaching for it is standing in for the thing
# it will not name, as :201 says.
COMMENT_ONLY = frozenset((r"\bspelling\b",))


def tier_of(pattern):
    """A for a named-construction ban, B for frequency-scored vocabulary, alphabet for a locale form.

    Read AUTHORITY above for why this is not stage_of with different words.
    """
    if pattern in LOCALE:
        return "alphabet"
    return "A" if pattern in AUTHORITY else "B"


EM_DASH = "—"

# Spellings that are somebody's name and never this project's prose. The International Conference on
# Salish and Neighbouring Languages spells its own name that way, and thirteen extraction scripts
# cite it in their headers. Americanizing a title misquotes it. A hit inside one of these is
# dropped before it is reported.
QUOTED = (
    re.compile(r"neighbouring languages", re.IGNORECASE),
    # The same title, wrapped across two comment lines by half the extraction headers.
    re.compile(r"salish and neighbouring", re.IGNORECASE),
)

# A span the writing sets off as a citation of a form. A token inside one is a NAME and not a USE,
# and that is the same reasoning QUOTED already carries for a proper name: the document is pointing
# at the token, not reaching for it.
#
# WHAT MEASURED IT, and this is the single highest-leverage precision rule in the file. The two
# documents that authorize this checker were run against it. code-documentation/SKILL.md reported
# 283 prose findings and 228 hits in it sit inside one of these spans, code-comments/SKILL.md
# another 35. Every one is the standard writing out a token it bans, letting a reader see which
# token is meant. A checker that reports a standard for naming its own bans is reporting the wrong
# thing 263 times, and it was.
#
# THREE MARKERS, and a fourth that was tried and dropped. The backtick span is the bulk of it. The
# italic run is how both files quote a banned shape too long to be a token: code-comments:161 writes
# *That is the difference between a helper naming a step and a helper costing a call* to show what
# an aphoristic clause reads like. The quoted span is the same device with quotes, and its floor is
# one character against PASSAGE's sixteen, because the named forms are short: *"Certainly!"* is ten
# characters and *"load-bearing"* is twelve, and both walked past PASSAGE.
#
# BOLD WAS THE FOURTH AND IT CAME OUT, measured across the two standards, ProtoCore/docs at
# 7bbc628d, idemIP/src at 29a808c and this tree's own docs/ and maint/. Bold exempted one site on
# the standards and five in ProtoCore, and three of those five were real TIER A findings inside a
# heading label: BUGS.md:376 "**What survives from F1/F2:**", :518 "**Why it is deferred rather than
# fixed:**", :1576 "**What it uncovered:**". Bold marks a heading in this tree far more often than
# it marks a citation. The arm was a net loss and is recorded here.
#
# The italic arm refuses a span holding a table cell separator. ProtoCore TUNING.md:154 is a table
# row where two unrelated asterisks in different cells paired across the row and swallowed a real
# `so a`. A citation of a form does not straddle a cell boundary.
#
# WHAT IT COSTS AND WHAT IT BOUGHT, measured after bold came out. It removes 263 findings on the
# two standards, of which 93 are TIER A and 165 TIER B, and every one is the document writing out
# the token it bans. Across ProtoCore/docs, idemIP/src and all six of this tree's own roots it
# removes 5, all TIER B, all correct: `realm` in a fenced `on_http_auth(..., realm, ...)` signature
# and in a `WWW-Authenticate: Basic realm="..."` header, which is an HTTP field name. NOT ONE TIER A
# FINDING IS SILENCED ANYWHERE OUTSIDE THE TWO STANDARDS. A banned word that happens to sit in
# backticks anywhere goes quiet, the same trade QUOTED and PASSAGE already make. Bounded to
# markdown alongside PASSAGE, except the backtick span, which reads the same way in a comment and is
# where a comment names a symbol.
NAMED_SPAN = re.compile(r"`[^`\n]{1,300}`")
NAMED_IN_MARKDOWN = (
    # Italic, excluding a neighbouring asterisk so **bold** is not read as an italic span opening
    # on its second asterisk, and excluding a cell separator for the reason above.
    re.compile(r"(?<!\*)\*[^*\n|]{1,300}\*(?!\*)"),
    # The short quoted form. PASSAGE stays for the long quotation, which is a different thing: it
    # exempts somebody else's words, and this exempts the document's own citation of a form.
    re.compile(r"[\"“][^\"“”\n]{1,600}[\"”]"),
)

# Prose lives in pages, in comments, in the books and in the build, and the same voice writes all
# four.
#
# .tex was absent from this tuple until now. No theory book had ever been register checked. The
# books are the longest continuous prose in the tree and the only part written to be read straight
# through, which made them the worst thing to have been leaving out.
#
# BUILD FILES WERE THE SAME GAP A SECOND TIME. A comment in a CMakeLists.txt makes the same claim a
# comment in a header makes, in the same voice, to the same reader, and until now this tool could
# not open one. Pointed at idemIP's CMakeLists.txt it printed "0 file(s) checked, 0 breaking,
# 0 prose" and "no files were read", and exited 2. That file carries four British spellings at
# :123, :305, :311 and :321.
#
# THE TRAP IN THAT FILE, and it runs the opposite way from how it reads. :123 is `behaviour`, which
# was already in the locale stage and was hidden by the extension list alone. The three
# `optimisation` sites at :305, :311 and :321 were hidden twice, by the extension list AND by the
# locale stage being ten literals. An author who added the extension and not the pattern would have
# watched :123 fire, read the file as covered, and left the other three invisible 182 lines further
# down. Both halves of this pass are needed to see all four, and that is why they are one pass.
BUILD_SUFFIXES = (".sh", ".ps1", ".cmake", ".yml", ".yaml")

# Named, not suffixed. A build file is as likely to be named as it is to be extended, and an
# extension list cannot express `CMakeLists.txt`. Carried from
# repo_tools/docs/docs_maint/ai_words.py, which this pass supersedes.
BUILD_NAMES = ("CMakeLists.txt", "Makefile", "GNUmakefile", "Dockerfile")

# A git hook has no extension at all, and no extension list can ever select it.
# Also from ai_words.py, and it is the sharpest thing in that file: a four-extension sweep
# dropped a hook and took the gate with it. anchor_sift keeps its own hooks in .githooks/ and every
# one of them is a shell script full of comments.
HOOK_NAMES = (
    "pre-commit",
    "commit-msg",
    "prepare-commit-msg",
    "pre-push",
    "pre-rebase",
    "post-merge",
    "post-checkout",
)

CHECKED = (".md", ".py", ".c", ".h", ".tex") + BUILD_SUFFIXES


def build_file(path):
    """Whether this path is a build file, by extension or by the name it was given.

    Read as one question and not two. A caller cannot answer half of it. submission_check.py
    imports CHECKED and would otherwise select a .cmake and hand it to the C extractor.
    """
    name = os.path.basename(path)
    return name in BUILD_NAMES or name in HOOK_NAMES or path.endswith(BUILD_SUFFIXES)


def checked_file(path):
    """Whether this tool reads this path at all."""
    return path.endswith(CHECKED) or build_file(path)


# ====================================================================
# THE EXCLUSION LAYER. EVERY EXCLUSION REFUSES AND SAYS SO
# ====================================================================
#
# THE FOUR STAGES CALL IN HERE AND NONE OF THEM CARRIES A SKIP OF ITS OWN. A skip written four times
# is four places to forget it and four places for the four copies to drift apart. That is the same
# fault the note above LOCALE records about a rule table duplicated into the table that enforces it.
# There are three call sites and no others: prose_only applies the blanking rules once, and
# em_dashes, markdown_leftovers and banned_tokens therefore inherit them without knowing they exist;
# banned_hits applies the run-level context rules beside QUOTED; main() applies the file-level and
# region-level rules and prints what fired.
#
# NOTHING IS SKIPPED QUIETLY. A silent skip is how everything in this file got here. The canonical
# case came from the closed-repository scan this tool once ran: it covered zero closed repositories
# for the whole of a directory migration and nobody could see it, because "scanned none" and "there
# are none" printed the same nothing. So every exclusion below records what it dropped and why, into
# a Ledger, and main() prints that ledger under the counts. A file this tool declines to read is
# named by the run that declined to read it.
#
# EVERY EXCLUSION STATES ITS REASON IN THE SOURCE AND NOT ONLY ITS RULE. A bare list of paths is the
# kind of thing a later maintainer deletes as overcautious, and they are right to: a rule nobody can
# check is a rule nobody can keep. A list saying why survives. The prior art is idemIP's
# repotools.toml:40-43, followed here instead of reinvented:
#
#     # The two files in this tree that are prose. docs/ is deliberately not a root: everything
#     # under docs/learn is the RFC corpus as the RFC Editor published it, which is not ours to
#     # check and not ours to rewrite.
#
# Three parties reached that rule independently on one day: that config file, the custodian of the
# closed corpus about oracles/, and a prose pass about docs/learn/RFC/. Three arrivals at one rule
# make it a discovered rule and not three preferences, and a discovered rule gets written once.
#
# EVERY RULE HERE IS A FIRST-CLASS RULE AND NOT A SPECIAL CASE. Each one has a name, a reason, a
# measured cost and a test. A special case is a rule with none of those, and it is the thing the
# next person deletes.


class Ledger(object):
    """What a run excluded and why, kept so the run can say so.

    Held in first-appearance order, because the order an exclusion first fires is the order a reader
    meets the tree. Sites are kept whole and not only counted: the question after a surprising count
    is always which ones, and a ledger that cannot answer it sends a reader back to the source.

    A caller passing no ledger still gets the exclusion. Recording is the optional part, never the
    rule. A caller that has not been taught about the ledger cannot turn an exclusion off by
    forgetting to pass one.
    """

    def __init__(self):
        self.order = []
        self.held = {}

    def note(self, rule, reason, detail):
        """Record one exclusion: its class, why the class exists, and the site it fired on."""
        key = (rule, reason)
        if key not in self.held:
            self.order.append(key)
            self.held[key] = []
        self.held[key].append(detail)

    def total(self):
        return sum(len(one) for one in self.held.values())

    def report(self, shown=8):
        """Printable lines naming each rule, its reason, its count and the sites it fired on."""
        out = []
        for key in self.order:
            sites = self.held[key]
            out.append("    %s: %d, %s" % (key[0], len(sites), key[1]))
            for one in sites[:shown]:
                out.append("      %s" % one)
            if len(sites) > shown:
                out.append("      ... and %d more" % (len(sites) - shown))
        return out


# --------------------------------------------------------------------
# VERBATIM THIRD-PARTY TEXT
# --------------------------------------------------------------------
#
# Somebody else's words, reproduced byte for byte. A register finding inside one is a finding
# against its author, and a rewrite inside one corrupts a document this project does not own.
#
# THREE INSTANCES, FOUND SEPARATELY, AND THAT MAKES THIS A CONCEPT:
#
#   idemIP docs/learn/RFC             IETF documents as the RFC Editor published them. RFC 2119
#                                     MUST and SHOULD are normative keywords in that corpus, and
#                                     "Robustness Variable" at src/idemip_config.h:580 is the
#                                     literal name of an RFC 2236 section 8.1 field, quoted in a
#                                     Doxygen brief with its published default.
#   ProtoCore docs/learn/rfc          the same corpus again, lowercased, in a second repository.
#   ProtoCore docs/learn/datasheets   vendor datasheets and the .txt extracted from them.
#   salishan_corpus/oracles           tables transcribed by hand from other people's published
#                                     papers. Their numbers are the published numbers, and a
#                                     transcription that disagrees with its source is worthless.
#
# NAMED AS A CONCEPT AND NOT AS A PATH LIST, and that difference is the whole reason this is written
# as a rule. A path list is a chore somebody has to remember to extend, and the way a chore fails is
# that a fourth corpus arrives and nobody adds it. So there are two answers to the question and
# either one is sufficient: the path sits under one of the defaults below, or the directory declares
# itself by holding a VERBATIM_MARKER file. Nothing in any tree here carries that marker today. It
# exists so the default list is not the only way to answer, and a tree vendoring a corpus this tool
# has never heard of can say so without editing this tool.
#
# WHAT IT COSTS, named here.
# Two files of this project's own prose go quiet with the corpora they index: idemIP
# docs/learn/RFC/README.md and ProtoCore docs/learn/datasheets/README.md. The alternative is an
# allowlist inside each verbatim root, which is a second list to maintain for two files, and the
# ledger names both of them on every run that reads past them.
#
# THE RFC .txt FILES ARE NOT READ TODAY ANYWAY, because .txt is not in CHECKED. That is true and it
# is not the reason this rule exists: the rule has to hold when somebody adds .txt, and a rule whose
# correctness depends on an unrelated tuple staying short is not a rule.
VERBATIM_MARKER = ".verbatim"

VERBATIM_ROOTS = (
    (
        "docs/learn/RFC",
        "IETF documents as the RFC Editor published them. idemIP repotools.toml:40-43 says the same",
    ),
    ("docs/learn/rfc", "the same IETF corpus, lowercased, in ProtoCore"),
    ("docs/learn/datasheets", "vendor datasheets and the .txt extracted from them"),
    (
        "salishan_corpus/oracles",
        "tables transcribed by hand from other people's published papers",
    ),
)

# Two components at least for every entry, because a bare directory name is not distinctive enough
# to be a rule. `oracles` alone would match any directory anywhere with that name, and this tree has
# a build/papers holding a different thing from the corpus papers/.
_VERBATIM_CEILING = 24
_VERBATIM_CACHE = {}


def verbatim_root(path):
    """(root, reason) where this path holds text reproduced from a third party, else None.

    Two answers, either sufficient. A default root matched on the path, or a directory at or above
    the file holding the marker. The marker walk stops at a repository boundary and again at a depth
    ceiling. A junction pointing at its own parent cannot make this walk forever.
    """
    posix = os.path.abspath(path).replace(os.sep, "/")
    for one, why in VERBATIM_ROOTS:
        if ("/%s/" % one.strip("/")) in posix:
            return one, why

    here = os.path.dirname(os.path.abspath(path))
    walked = []
    for _ in range(_VERBATIM_CEILING):
        if here in _VERBATIM_CACHE:
            answer = _VERBATIM_CACHE[here]
            break
        walked.append(here)
        if os.path.isfile(os.path.join(here, VERBATIM_MARKER)):
            answer = (
                here.replace(os.sep, "/"),
                "declared by a %s marker in that directory" % VERBATIM_MARKER,
            )
            break
        if os.path.isdir(os.path.join(here, ".git")) or os.path.isfile(
            os.path.join(here, ".git")
        ):
            answer = None
            break
        up = os.path.dirname(here)
        if up == here:
            answer = None
            break
        here = up
    else:
        answer = None

    for one in walked:
        _VERBATIM_CACHE[one] = answer
    return answer


# --------------------------------------------------------------------
# SIGNED MANIFESTS
# --------------------------------------------------------------------
#
# The most dangerous exclusion in this file, and the only one whose cost is not a question of taste.
#
# salishan_corpus/MANIFEST.tsv records the SHA-256, the byte count and the row count of 2028 files.
# AUDIO_MANIFEST.tsv records another 3. Both carry a detached signature beside them,
# MANIFEST.tsv.asc and AUDIO_MANIFEST.tsv.asc. Changing one byte of a listed file makes its hash
# wrong, fails the reconcile that repository runs before every commit, and invalidates a signature
# whose whole purpose is to attest what a published measurement was taken over.
#
# A LISTED PATH IS THEREFORE REFUSED FOR REWRITING AND NEVER QUIETLY PASSED OVER, and a run that
# offered to rewrite anything in a tree carrying a manifest prints that manifest's own reconcile
# instruction under its output. The instruction is lifted from the manifest header and not written
# out here. It cannot drift from the tool that maintains it.
#
# WORSE HERE THAN ANYWHERE ELSE. The corpus is Salishan linguistics: Canadian and British convention
# throughout, and this file's own measurements put neighbour at 17.3 per 100k there, analyse at 8.9,
# behaviour at 4.8, labelled at 2.9 and centre at 2.3. Those are the source texts' own convention,
# they are what the hashes were taken over, and an alphabet-stage rewrite would change thousands of
# them and break every hash it touched.
#
# READING IS NOT WRITING, and this rule does not stop the scan. A listed file is read, and a finding
# in one is reported like any other, because reporting changes no bytes. Only the rewrite is
# refused.
MANIFEST_NAMES = ("MANIFEST.tsv", "AUDIO_MANIFEST.tsv")
SIGNATURE_SUFFIX = ".asc"

_MANIFEST_CEILING = 24
_MANIFEST_DIRS = {}
_MANIFEST_INDEX = {}


def manifest_home(start):
    """The nearest directory at or above `start` holding a signed manifest, or None.

    Stops at a repository boundary. A manifest attests one repository's contents, and a parent
    directory holding several repositories beside each other is not that repository.
    """
    here = os.path.abspath(start if os.path.isdir(start) else os.path.dirname(start))
    walked = []
    answer = None
    for _ in range(_MANIFEST_CEILING):
        if here in _MANIFEST_DIRS:
            answer = _MANIFEST_DIRS[here]
            break
        walked.append(here)
        if any(os.path.isfile(os.path.join(here, one)) for one in MANIFEST_NAMES):
            answer = here
            break
        if os.path.isdir(os.path.join(here, ".git")) or os.path.isfile(
            os.path.join(here, ".git")
        ):
            break
        up = os.path.dirname(here)
        if up == here:
            break
        here = up
    for one in walked:
        _MANIFEST_DIRS[one] = answer
    return answer


def manifest_index(home):
    """{relative posix path: (manifest, signature or None)} for every manifest in one directory.

    The file is a comment header, one header row naming its columns, then one row per attested file
    with the path last. Read by taking the last tab-separated field. A manifest that grows a
    column still parses. A row with no tab is not a row.
    """
    if home in _MANIFEST_INDEX:
        return _MANIFEST_INDEX[home]

    held = {}
    for name in MANIFEST_NAMES:
        where = os.path.join(home, name)
        if not os.path.isfile(where):
            continue
        signature = where + SIGNATURE_SUFFIX
        signed = signature if os.path.isfile(signature) else None
        with open(where, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.rstrip("\n").rstrip("\r")
                if line.startswith("#") or ("\t" not in line):
                    continue
                listed = line.split("\t")[-1].strip()
                # The header row names the columns and attests nothing.
                if (not listed) or (listed == "path"):
                    continue
                held[listed.replace("\\", "/")] = (where, signed)
    _MANIFEST_INDEX[home] = held
    return held


def manifest_listed(path):
    """(manifest, signature, listed path) where this file's bytes are attested, else None."""
    home = manifest_home(path)
    if not home:
        return None
    listed = os.path.relpath(os.path.abspath(path), home).replace(os.sep, "/")
    held = manifest_index(home).get(listed)
    if not held:
        return None
    return (held[0], held[1], listed)


def reconcile_command(manifest):
    """The manifest's own instruction for reconciling a tree against it.

    Lifted from the manifest header instead of written out here. corpus_manifest.py maintains both
    the file and the sentence. Quoting the sentence keeps this from drifting away from the tool
    that would have to be run.
    """
    try:
        with open(manifest, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                if not line.startswith("#"):
                    break
                said = line.lstrip("#").strip()
                if ".py" in said:
                    return said
    except OSError:
        pass
    return (
        "reconcile this tree against %s and re-sign it before committing"
        % os.path.basename(manifest)
    )


# --------------------------------------------------------------------
# LEGAL BLOCKS: SPDX AND COPYRIGHT
# --------------------------------------------------------------------
#
# An SPDX identifier and a copyright grant are legal artifacts, and the register of a license grant
# is the license's business. idemIP carries "SPDX-License-Identifier: AGPL-3.0-or-later" on every
# file, and this tree carries a three-way LicenseRef line on every file of its own. Rewriting a word
# inside one edits the artifact.
#
# BLANKED PER BLOCK AND NEVER PER LINE. A GPL grant runs fifteen lines and two of them hold anything
# a regex can find. Blanking the two that matched would leave thirteen lines of legal text standing
# in front of the register scan. Carried from repo_tools/docs/docs_maint/ai_words.py, which this
# pass supersedes.
#
# WHERE A BLOCK ENDS IS THE WHOLE RULE, and getting it wrong in either direction has a cost that was
# measured before this landed. A first attempt split blocks on blank source lines. A `#` alone on a
# line is not blank. The entire 28-line comment header of a maint script read as one block and
# 164 findings went quiet across this tree alone, among them six hits in a file about orthography
# and two tier A hits in another. A block is split instead on MARKER-stripped emptiness, the same
# test runs() already makes, and again wherever the comment form changes or closes.
#
# WITH THAT RULE IT SILENCES NOTHING TODAY. Measured over anchor_sift's six roots, idemIP's whole
# tree, ProtoCore/docs, MMgr and both closed repositories: zero findings. Every legal block in every
# one of those trees is already clean prose, the outcome to want from a rule whose job is
# to protect an artifact. The number is worth re-deriving after any
# change to the block walker, because a walker reaching too far reports the same zero.
#
# THE FIXTURE THIS WAS BUILT AROUND, and it is the sharpest available because both halves sit in one
# file four lines apart. idemIP tools/dev_env/strip_comments.py:2-3 is a real copyright and SPDX
# pair and is not ours to edit. Its :4 and :12 say `licence` in prose ABOUT a license block, which
# is ordinary British convention a person may fix. :4 is the line directly under the header with no
# blank line between them. A block rule reaching one line too far takes it with the header. What
# separates them is the change of comment form from `#` to a docstring. readclean.py:12 and :36 are
# the same shape with a blank line to help, and all four sites survive this rule.
LEGAL = re.compile(
    r"SPDX-(?:License-Identifier|FileCopyrightText)"
    r"|\bCopyright\b\s*(?:\(c\)|©|(?:19|20)\d\d)"
    r"|\(c\)\s*(?:19|20)\d\d"
    r"|©\s*(?:19|20)\d\d"
    r"|All rights reserved"
    r"|Licensed under"
    r"|LicenseRef-"
    r"|GNU (?:Affero |Lesser )?General Public License"
    r"|This (?:program|file) is free software"
    r"|WITHOUT ANY WARRANTY"
    r"|MERCHANTABILITY",
    re.IGNORECASE,
)

# The comment forms a block can be written in. Tested in this order. `/*` is read before `*` and
# a docstring before a bare quote. `plain` is a continuation line inside a block opened above it.
COMMENT_FORMS = (
    ("cblock", ("/*", "*")),
    ("docstring", ('"""', "'''")),
    ("slash", ("//",)),
    ("hash", ("#",)),
    ("percent", ("%",)),
)


def comment_form(line):
    """Which comment form a line is written in, or `plain` for a continuation."""
    body = line.strip()
    for name, markers in COMMENT_FORMS:
        if body.startswith(markers):
            return name
    return "plain"


def form_closes(form, line, opening):
    """Whether this line ends the block it is in.

    A C block ends at its `*/` and a docstring at its closing triple quote, and both can be followed
    on the next line by a second block of the same form. The @file block sits directly under the
    SPDX block in every header the comment standard specifies. Without this test the two read as
    one and every @file brief in the tree would go unchecked.
    """
    body = line.strip()
    if form == "cblock":
        return "*/" in body
    if form == "docstring":
        marks = body.count('"""') + body.count("'''")
        return marks >= 2 if opening else marks >= 1
    return False


def comment_blocks(said):
    """(start, stop) for each contiguous comment block in a prose view, as 0-based half-open spans.

    Emptiness is measured on the MARKER-stripped text, which is what makes a lone `#` a separator.
    A lone ` */` strips to empty too, and it closes the C block above it: it belongs to that block
    and ends it. Read as a separator it was left behind when a license block was blanked.
    """
    spans = []
    at = 0
    while at < len(said):
        if not MARKER.sub("", said[at]).strip():
            at += 1
            continue
        form = comment_form(said[at])
        stop = at
        while stop < len(said):
            if stop > at:
                if not MARKER.sub("", said[stop]).strip():
                    if (comment_form(said[stop]) == form) and form_closes(form, said[stop], False):
                        stop += 1
                    break
                if comment_form(said[stop]) != form:
                    break
            done = form_closes(form, said[stop], stop == at)
            stop += 1
            if done:
                break
        spans.append((at, stop))
        at = stop
    return spans


def legal_blank(said, path=None, ledger=None):
    """The same prose view with every comment block holding a legal line blanked out.

    Line numbers are preserved, the way every other view in this file preserves them. A finding
    still names a line a reader can open.
    """
    kept = list(said)
    for start, stop in comment_blocks(said):
        if not any(LEGAL.search(one) for one in kept[start:stop]):
            continue
        if ledger is not None and path is not None:
            ledger.note(
                "legal block",
                "an SPDX or copyright block is a legal artifact and its wording is the "
                "license's, not this project's",
                "%s:%d-%d" % (path.replace("\\", "/"), start + 1, stop),
            )
        for at in range(start, stop):
            kept[at] = ""
    return kept


# --------------------------------------------------------------------
# GENERATED REGIONS
# --------------------------------------------------------------------
#
# REPORTED AND ATTRIBUTED, NEVER SUPPRESSED, and this is the single decision in this section a
# reader is likely to want to reverse. Here is the evidence against reversing it.
#
# ProtoCore's README.md and TOOLS.md carry BEGIN and END GENERATED marker pairs, 20 pairs across 11
# tracked files, and CI regenerates them on push to main. An edit inside one is reverted by the next
# regeneration: the gate reports a fix, the fix disappears, and the finding comes back forever. That
# argues for skipping the region, and it is the wrong move.
#
# THE TREE SAYS WHY. The single genuine structural finding in the whole of ProtoCore/docs is an
# empty table at docs/README.md:2404, and the region from :2399 to :2408 is generated by
# tools/ci_tooling/generate/gen_readme_sections.py. A rule that skips marked regions deletes the one
# finding worth having in that tree and reports it clean. The generator emits a header and a
# separator with no rows under them, unconditionally. Every CI regeneration republishes an empty
# table on a public README. That is a generator defect, a person has to fix it in the generator, and
# the finding is how they find out.
#
# A FINDING INSIDE A MARKED REGION THEREFORE KEEPS ITS PLACE IN THE COUNT and carries the
# generator's name with it. The marker already holds the generator. The attribution is read from the
# document and cannot go stale. What the region buys is a refusal: a rewrite never goes inside one,
# because writing there is writing to a file CI overwrites.
#
# AND A SOURCE FIX IS PAIRED WITH REGENERATION. ProtoCore's docs/features.html is generated from
# docs/FEATURES.md by tools/ci_tooling/generate/gen_features_page.py, which writes its OUT at that
# file's :24, and CI gates on `ci gen --check` per tools/harness.py:1330. Fixing the source without
# rerunning the generator reds the pull request that carried the fix. Skipping the generated copy is
# necessary and it is not sufficient. The refusal below names the generator and says to run it.
#
# AN UNCLOSED MARKER IS ITSELF REPORTED. A BEGIN with no END would otherwise annotate the rest of
# the file as generated, the fail-open shape this whole section exists against.
GENERATED_OPEN = re.compile(r"<!--\s*BEGIN GENERATED\b\s*(?P<label>[^>]*?)\s*-->")
GENERATED_CLOSE = re.compile(r"<!--\s*END GENERATED\b")
GENERATED_BY = re.compile(r"\(([^)]+)\)\s*$")


def generated_regions(lines):
    """({line number: generator}, [(line number, complaint)]) for one document.

    The generator is the parenthesized tail of the BEGIN marker where there is one, and the marker's
    label otherwise. ProtoCore writes both shapes: docs/README.md:2399 names a path and
    test/README.md:72 names a command to run instead.
    """
    inside = {}
    complaints = []
    opened_at = None
    generator = None
    for at, line in enumerate(lines):
        hit = GENERATED_OPEN.search(line)
        if hit:
            if opened_at is not None:
                complaints.append(
                    (
                        opened_at + 1,
                        "BEGIN GENERATED with no END GENERATED under it, and a second "
                        "BEGIN at line %d" % (at + 1),
                    )
                )
            label = hit.group("label").strip()
            named = GENERATED_BY.search(label)
            generator = (
                named.group(1).strip() if named else (label or "an unnamed generator")
            )
            opened_at = at
            continue
        if GENERATED_CLOSE.search(line):
            opened_at = None
            generator = None
            continue
        if opened_at is not None:
            inside[at + 1] = generator
    if opened_at is not None:
        complaints.append(
            (
                opened_at + 1,
                "BEGIN GENERATED with no END GENERATED anywhere under it. Every line "
                "to the end of the file reads as generated",
            )
        )
    return inside, complaints


# --------------------------------------------------------------------
# THE SUBJECT IS BRITISH, AND OTHER RUN-LEVEL CONTEXT
# --------------------------------------------------------------------
#
# A British convention is banned unless the subject IS British convention, and this is that clause.
# A passage about it has to be able to write the word it is about. "British English writes colour"
# is a correct sentence, and an alphabet-stage finding on it is the same error as a checker
# reporting a standard for naming its own bans.
#
# THIS EXTENDS THE COMPILED CONTEXT EXEMPTION QUOTED ALREADY IS. That tuple exists for exactly this
# question one instance at a time: the International Conference on Salish and Neighbouring Languages
# spells its own name that way and thirteen extraction headers cite it. Pointing this at the same
# shape is why it is two tuples of compiled patterns and not a new stage.
#
# BOUNDED TO THE ALPHABET TIER AND TO THE RUN, and that keeps it from being a bypass. A
# paragraph mentioning Canada does not get to write `is what makes`. Only a convention finding goes
# quiet, and only inside the run carrying the subject.
#
# THE SUBJECT IS THE CONVENTION AND NOT THE COUNTRY, and the pattern says so. A bare \bbritish\b
# would exempt "British Telecom's optimisation", where the subject is a company and the convention
# is a live finding. Each arm names a word about writing: `english`, `spelling`, `convention`,
# `usage`, `variant`, `orthography`.
#
# MEASURED COST, over anchor_sift's six roots, idemIP's whole tree, ProtoCore/docs, MMgr and both
# closed repositories: zero findings silenced. Nothing in any tree here writes about the convention
# today. The rule is the objective's own clause written down before a document needs it, and
# maint/prose/test_docs_check_exclusions.py re-derives that zero from the trees on disk, and a
# reader checks it instead of trusting this sentence.
BRITISH_SUBJECT = (
    re.compile(
        r"\b(?:british|american|canadian|commonwealth|oxford)\s+"
        r"(?:english|definition|spellings|convention|conventions|usage|variant|variants"
        r"|orthograph\w*|dictionar\w*)",
        re.IGNORECASE,
    ),
    re.compile(r"\ben[-_]GB\b"),
)

# A standard named by number. The terms around it are that standard's own field names, and
# "Robustness Variable" in idemIP's src/idemip_config.h:580 is one: RFC 2236 section 8.1 spells it
# that way and the Doxygen brief quotes it with its published default. Rewriting a field name makes
# a comment cite something that is not in the document it names.
#
# THIS IS A REWRITE REFUSAL AND NOT A SCAN EXEMPTION, AND IT WAS WRITTEN AS ONE AND MEASURED OUT.
# The first draft exempted a run naming a standard, the way the clause above exempts a run about
# convention. Unbounded it silenced 1,733 findings in idemIP alone, because that tree cites an RFC
# in nearly every comment it has. The register gate would have been off in the one repository it
# was written for. Bounded to the alphabet tier it silenced 20 and bought nothing: every one of the
# 20 is ordinary prose that happens to sit in a paragraph citing a standard. `behaviour` five times
# in ProtoCore BUGS.md, `initialised`, `labelled` and `behaviours` together at CHANGELOG.md:702,
# `defence` at idemIP dad.c:26, `neighbour` at test_dad.c:961. Not one of the 20 is a field name
# from the standard beside it. The site the rule was written for, "Robustness Variable", matches no
# pattern in LOCALE and produced no finding to exempt in the first place.
#
# A rule that silences twenty correct findings and buys zero is a net loss, and precision over
# recall means exactly that when it costs something. So it moved to fix_refusal, where it refuses a
# rewrite on a line quoting a named standard and costs nothing at all.
NAMED_STANDARD = re.compile(
    r"\b(?:RFC|STD|BCP|IEEE|ISO|IEC|ANSI|FIPS|NIST(?:\s+SP)?)\s*\d", re.IGNORECASE
)

# A normative keyword as RFC 2119 defines it, in capitals. Case matters and the pattern is compiled
# without IGNORECASE on purpose: "this may be null" is prose and "the sender MAY retransmit" is a
# requirement whose wording is not this tree's to edit.
#
# NOT A SCAN EXEMPTION. Nothing in BANNED matches a capitalized normative keyword. Exempting a
# run for carrying one would buy nothing and cost whatever else is in the run. It is a rewrite
# refusal and only that: a line carrying one is never rewritten, because reflowing a requirement is
# how a requirement stops being the one that was agreed.
RFC_2119 = re.compile(
    r"\b(?:MUST NOT|MUST|SHALL NOT|SHALL|SHOULD NOT|SHOULD|NOT RECOMMENDED|RECOMMENDED"
    r"|REQUIRED|MAY|OPTIONAL)\b"
)


CONTEXT_REASON = (
    "the subject of the passage is a writing convention, and a passage about one has "
    "to be able to write the word it is about"
)


def context_exempt(text):
    """Tiers that go quiet in one run because of what the run is about.

    Returns a frozenset of tier names. Empty for every run in every tree measured today, and that is
    the point: an exemption that fires often is a rule that was written too wide.
    """
    if any(one.search(text) for one in BRITISH_SUBJECT):
        return frozenset(("alphabet",))
    return frozenset()


# --------------------------------------------------------------------
# WHAT A REWRITE MAY TOUCH, AND IT IS ALMOST NOTHING
# --------------------------------------------------------------------
#
# A BANNED HINGE IS DISSOLVED AND NEVER REPLACED. Detection is mechanical. SUBSTITUTION is where the
# judgement lives, and it is exactly where an automatic rewrite does damage.
#
# THE REASON IS CHECKABLE IN ONE DOCUMENT AND IT IS WHY THIS IS A PERMANENT LIMIT AND NOT A GAP.
# A construction ban targets a rhetorical move and not a word. The nearest synonym preserves the
# move and lands on another banned item. `rather` is banned at code-documentation:110. Its obvious
# repair is the X-not-Y shape, which is banned at :146 of the same document, thirty-six lines later:
# "The X-not-Y shape sounds decisive and carries almost nothing". Anyone repairing the first without
# reading the second produces the second at scale. A pass turning fifty `rather` sites into fifty
# X-not-Y sites reports fifty fixes and leaves the tree measurably worse.
#
# IT HAS HAPPENED. Three times in one day, three different people, all caught before shipping:
# `seamless` proposed as `fast`, where both are named in one praise-adjective ban; "in the header,
# not in the .c" nearly written to replace a `rather than`; and eleven X-not-Y substitutions across
# one ProtoCore file, rejected on review.
#
# THE TWO LEGAL TREATMENTS, from :110 and :146 read together. Give the second half its own plain
# declarative sentence, or drop the weaker half. Dropping is the default, and :146's test is whether
# the reader would otherwise land on the wrong one. THE TEST FOR A BAD REPAIR IS MECHANICAL: if the
# two halves are still adjacent across a comma, the shape survived and only its wording changed.
#
# SO THE ALPHABET TIER IS THE ONLY TIER A REWRITE MAY REACH. initialised to initialized, licence to
# license, behaviour to behavior. Those are token for token and the replacement cannot change the
# shape of the sentence. TIER A AND TIER B STAY REPORT-ONLY permanently. This is not a feature
# nobody has written yet. Read code-documentation:110 and :146 before changing this line.
#
# Pair it with :143, which the note above AUTHORITY already quotes: a word that reads as a tic in
# one construction only is bounded to that construction. Together the two say the whole thing. Bans
# name constructions. Detection AND repair both operate on constructions and never on words, and
# there is no construction a machine can repair.
#
# THE REWRITING HALF IS DELIBERATELY NOT IMPLEMENTED. `--fix` runs this policy over the findings and
# prints what it would and would not touch, and writes nothing. The gate is here first, and on
# purpose: whoever adds the writing half has to come through fix_refusal, and cannot add it without
# meeting the manifest, verbatim, generated and legal refusals that are already tested beside it.
FIX_TIERS = frozenset(("alphabet",))


def fix_refusal(path, tier, at=None, regions=None, line=""):
    """Why a rewrite may not touch this site, or None where it may.

    Every branch is a refusal and the order decides only which reason is printed first. The tier
    test leads because it alone holds everywhere and is never lifted.
    """
    if tier not in FIX_TIERS:
        return (
            "a tier %s finding is a construction and not a token. No replacement can be "
            "mechanical: code-documentation:110 bans `rather` and :146 bans the X-not-Y shape "
            "that repairs it. An automatic repair produces the second ban while removing "
            "the first. Report only, permanently." % tier
        )

    held = verbatim_root(path)
    if held:
        return "under %s, which is %s" % (held[0], held[1])

    listed = manifest_listed(path)
    if listed:
        manifest, signature, named = listed
        return (
            "attested as %s in %s%s. Changing one byte makes its hash wrong and invalidates a "
            "signature whose purpose is to say what a published measurement was taken over. "
            "After any run that writes in this tree: %s"
            % (
                named,
                os.path.basename(manifest),
                ", signed by %s" % os.path.basename(signature) if signature else "",
                reconcile_command(manifest),
            )
        )

    if regions and (at in regions):
        return (
            "inside a region generated by %s. CI regenerates it. An edit here is reverted "
            "and the finding returns. Fix the generator, then rerun it: a source fix not paired "
            "with regeneration reds the pull request that carried it." % regions[at]
        )

    if RFC_2119.search(line):
        return (
            "the line carries an RFC 2119 normative keyword in capitals. Its wording is a "
            "requirement somebody agreed to and not this project's prose"
        )

    if NAMED_STANDARD.search(line):
        return (
            "the line names a standard by number. The terms around it are that standard's "
            "own field names. Rewriting one makes the comment cite something that is not in "
            "the document it names"
        )

    return None


# Every place this project keeps prose. A README beside the code makes the same claims a page under
# docs makes, and is read by the same people.
#
# Held against the repository and not against the working directory. These were plain relative names
# once, and from anywhere but the root they matched nothing: the run reported zero files, zero
# findings and success. A commit hook calling it that way lets every commit through and reports the
# prose as checked.
REPOSITORY = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting broke
# every path in this tree the last time anything moved.
while (REPOSITORY != os.path.dirname(REPOSITORY)) and not os.path.isdir(
    os.path.join(REPOSITORY, "src", "engine")
):
    REPOSITORY = os.path.dirname(REPOSITORY)

# Every directory holding writing of this project's own. It named tools/ until that directory was
# split into data/, analysis/ and maint/, and the run then read 188 files instead of 317 and still
# exited 0. data/ and analysis/ later moved under maint/ and stayed listed here as though they were
# still at the top: the same defect a second time.
#
# A root that no longer exists is not an error this could see. The guard below turns that
# into one, and the count at the foot is still the thing to watch after a move.
#
# theory_bucket was the third instance. Seven books moved out of theory/ into a subtree at
# theory_bucket/, and theory/ still existed because the workbook stayed in it. The guard below stayed
# quiet and eighty files of prose went unread. The guard catches a root that vanished and never a
# root that emptied, and the count at the foot is the only thing that shows the difference. The
# seven moved back under theory/ on 2026-09-25.
DEFAULT_ROOTS = tuple(
    os.path.join(REPOSITORY, one)
    for one in ("docs", "src", "examples", "maint", "theory")
)

for one in DEFAULT_ROOTS:
    if not os.path.isdir(one):
        raise SystemExit(
            "docs_check: %s is listed as a prose root and does not exist. A missing "
            "root reads as zero findings and exits 0, which passes every commit." % one
        )


# The environment a git query runs under, with the caller's own repository handed off.
#
# Git EXPORTS GIT_DIR and GIT_WORK_TREE to a hook. A rev-parse that inherits them answers about that
# repository instead of about the directory it was asked from. --show-toplevel returns the hook's
# own checkout as the root of whatever tree this tool was pointed at. The worktree repair that
# landed --git-common-dir was written against this and the clearing did not come with it, which is
# how a correct query kept giving a wrong answer under a hook. Every git query in this file goes
# through here. There is one place to add the next variable to.
GIT_HANDOFF = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_PREFIX",
    "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_NAMESPACE",
)


def git_env():
    """A copy of the environment with every variable naming somebody else's repository removed."""
    kept = dict(os.environ)
    for one in GIT_HANDOFF:
        kept.pop(one, None)
    return kept


def git_say(where, args):
    """One git command's stdout from `where`, stripped, or None where git cannot answer.

    None covers three cases a caller treats alike: git is not installed, the directory is not a
    checkout, and the command failed. A report that cannot name a revision says so; it does not
    guess one.
    """
    if not os.path.isdir(where):
        return None
    try:
        answer = subprocess.check_output(
            ["git"] + list(args), cwd=where, stderr=subprocess.PIPE, env=git_env()
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return answer.decode("utf-8", "replace").strip()


def main_checkout():
    """The main working tree, the one the closed repositories sit beside.

    A linked worktree lives at <repo>/.claude/worktrees/<name>. A sibling path computed from
    REPOSITORY lands inside .claude/ and finds nothing. --git-common-dir names the shared .git for
    the main tree and every linked worktree alike, and its parent is the main checkout. Falls back
    to REPOSITORY where git cannot answer, which is an exported tree with no history.
    """
    common = git_say(REPOSITORY, ("rev-parse", "--git-common-dir"))
    if not common:
        return REPOSITORY
    if not os.path.isabs(common):
        common = os.path.join(REPOSITORY, common)
    base = os.path.dirname(os.path.abspath(common))
    return base if os.path.isdir(base) else REPOSITORY


# ====================================================================
# REPORTING: A COUNT IS NOT A RESULT UNTIL IT SAYS WHAT IT COUNTED
# ====================================================================
#
# Three lines, and each one prevented a real confusion.
#
# PRINT THE REVISION MEASURED. One repository read 58 British sites on one branch and 15 on another,
# and the difference looked like a defect in this tool to two separate readers for most of a day. A
# count without its revision is a count about an unspecified tree. And a revision is only authority
# while it is REACHABLE FROM SOMEWHERE DURABLE: a local-only commit is a tree of one, and a fixture
# that lived only inside a linked worktree dies with the session that made it. So the revision is
# printed with its reachability, and "NOT PUSHED" is printed in those words when nothing on a remote
# contains it.
#
# PRINT THE ROOTS SCANNED AND THE ROOTS LOOKED FOR AND NOT FOUND. The closed-repository scan this
# tool once ran taught the reason, and it generalizes: "scanned none" and "there are none" must
# never be the same output, for any root and not only a closed one.
#
# PRINT THE ROOTS IT WAS CONFIGURED WITH, and this is the line that matters most. One repository
# declares roots = ["README.md", "test"] for both its prose gate and its commit hook. Its sixty
# translation units and its CMakeLists.txt are outside that declared scope, and they stay outside it
# after every repair this tool has had. A run reporting "0 findings" over two configured roots reads
# exactly like a clean tree, and that is how a repository carrying dozens of British spellings reads
# as green. The roots go at the top of the report, and a reader meets the scope before the count.
#
# AND SAY WHAT THIS TOOL DOES NOT ANSWER FOR. There are four independent reasons a finding survives
# a gate and each is sufficient alone: the hook is not installed, the declared roots exclude the
# file, the rule cannot match it, and the extension cannot be opened. This file owns the last two.
# The first two are per-repository decisions that change what every committer has to satisfy, they
# belong to each repository's captain, and a tool implying it has settled them is worse than one
# that says nothing. A gate that is correct, installed nowhere, and scoped to two paths still
# catches nothing. The footer says so in one line.

_REF_CACHE = {}


def tree_ref(path):
    """(repository, revision, reachability, dirty) for the tree a scanned root sits in, or None.

    Reachability is answered by asking which remote-tracking ref contains the revision. That is the
    only durable test available locally: a branch name proves nothing, since a local branch that was
    never pushed has one. Cached per repository, because a run reads hundreds of files out of a
    handful of checkouts.
    """
    where = path if os.path.isdir(path) else os.path.dirname(os.path.abspath(path))
    top = git_say(where, ("rev-parse", "--show-toplevel"))
    if not top:
        return None
    top = os.path.abspath(top)
    if top in _REF_CACHE:
        return _REF_CACHE[top]

    revision = git_say(top, ("rev-parse", "--short", "HEAD"))
    if not revision:
        _REF_CACHE[top] = None
        return None
    remote = git_say(
        top,
        (
            "for-each-ref",
            "--contains",
            revision,
            "--format=%(refname:short)",
            "refs/remotes",
        ),
    )
    if remote:
        reach = "reachable from %s" % remote.splitlines()[0].strip()
    else:
        reach = "NOT PUSHED, no remote-tracking ref contains it"
    dirty = bool(git_say(top, ("status", "--porcelain")))
    answer = (top, revision, reach, dirty)
    _REF_CACHE[top] = answer
    return answer


def refs_for(roots):
    """One (repository, revision, reachability, dirty) per distinct checkout among the roots."""
    held = []
    for one in roots:
        answer = tree_ref(one)
        if answer and answer not in held:
            held.append(answer)
    return held


def manifests_covering(roots):
    """Every signed manifest that attests anything under the roots being scanned.

    Printed after a run that offered to write. Nobody has to already know the corpus is hashed to
    find out that it is. A manifest is a repository-level fact and there are one or two of them.
    This asks once per root and not once per file.
    """
    found = []
    for one in roots:
        home = manifest_home(one)
        if not home:
            continue
        for name in MANIFEST_NAMES:
            where = os.path.join(home, name)
            if os.path.isfile(where) and where not in found:
                found.append(where)
    return found


def fix_plan(path, lines, said, regions, refusals, allowed):
    """Sort one file's findings into what a rewrite could touch and what it is refused.

    Appends to the two lists the caller holds. Writes nothing and is never going to: the note above
    FIX_TIERS says why the construction tiers are report-only permanently, with the two sections
    that say it. What this does is make the refusal visible before anybody writes the other half.
    """
    quotations = path.endswith(".md")
    comments = not path.endswith((".md", ".tex"))
    shown = path.replace("\\", "/")
    for at, pattern, token in banned_hits(said, quotations, comments, path):
        tier = tier_of(pattern)
        line = lines[at - 1] if 0 < at <= len(lines) else ""
        why = fix_refusal(path, tier, at, regions, line)
        said_token = " ".join(token.split())
        if why:
            refusals.append("%s:%d %r: %s" % (shown, at, said_token, why))
        else:
            allowed.append("%s:%d %r, token for token" % (shown, at, said_token))

# Fetched or generated. Nothing in them was written here. fixtures holds the positive control for
# claudese_distance.py, written deliberately in the assistant register. Repairing it would delete
# the only sample of the thing being detected. `.claude` is here because a linked worktree lives
# under `.claude/worktrees/<name>/` and holds a full checkout. Without the skip, a repository with N
# worktrees reports every finding N+1 times: measured at 50 echo lines of 1039, 34 distinct
# findings, several repeated three times. The ratio is a property of how many worktrees happened to
# exist that day. Nobody can correct a total by it.
#
# It hides the real site as well as inflating the count. Grepping the same tree, the first ten hits
# were all worktree copies, because `.claude` sorts before every source directory, and a reader
# stopping at the first page concludes a finding exists only in scratch.

SKIP_DIRS = (
    ".git",
    "build",
    "site",
    "deps",
    "__pycache__",
    ".vscode",
    "fixtures",
    ".claude",
)

# A markdown table separator: | --- | --- |
SEPARATOR = re.compile(r"^\s*\|[\s:|-]+\|\s*$")
ROW = re.compile(r"^\s*\|")

# A relative markdown link, skipping anything with a scheme and anything anchored to a heading.
LINK = re.compile(r"\[[^\]]*\]\(([^)#][^)]*)\)")
# Markdown renders nothing inside an inline code span as a link. A formula set as code, such as
# `C[a, b](v)`, is blanked out before LINK reads the line.
CODE_SPAN = re.compile(r"`[^`\n]*`")

# A Doxygen cross-reference written in markdown link syntax: [`HTTP_10`](@ref HTTP_10). Doxygen
# resolves the target against the symbol table it builds from the source. The word after the command
# is an identifier. The filesystem has no answer to give about it, and producing one means reading
# Doxygen's tag file, which this tool does not do.
#
# Both spellings of every command are accepted, since Doxygen takes @ref and \ref alike.
DOXYGEN_TARGET = re.compile(r"^[@\\](ref|subpage|page|link|anchor|cite|see|copydoc)\b")

# C declarator syntax that LINK matches by accident. A lambda in a fenced example writes its capture
# list in square brackets and its parameter list in parentheses. `[](uint8_t slot, HttpReq *req)`
# is character for character the shape a markdown link has.
#
# Three signals, each one sufficient, and each one chosen because a relative path cannot carry it:
# a pointer star anywhere in the target, a C type qualifier or specifier opening it, or a
# comma-separated run where every item is two words. A path with a comma in it is legal and rare,
# and `docs/a.md, docs/b.md` fails the last test because neither item has an interior space.
DECLARATOR_HEAD = re.compile(
    r"^(const|volatile|unsigned|signed|struct|enum|union|static)\s"
)


def empty_tables(lines):
    """A separator row with no data row under it renders as a table with a head and no body."""
    found = []
    for at, line in enumerate(lines):
        if not SEPARATOR.match(line):
            continue
        following = lines[at + 1] if (at + 1) < len(lines) else ""
        if not ROW.match(following):
            found.append((at + 1, "table header with no rows under it"))
    return found


# What opens a comment or continues a wrapped one. Stripped before lines are joined: a phrase
# broken across two comment lines reads as prose and not as prose with a marker in the middle.
MARKER = re.compile(r"^\s*(#+|//+|\*+/?|/\*+)\s?")


def runs(lines):
    """Consecutive non-blank prose lines joined into one string, with a map back to line numbers.

    Yields (text, offsets) where offsets[i] is the source line number of character i. A banned
    phrase that wraps across a line break is invisible to a per-line scan, and one escaped that way
    into a ledger heading: `is the` ended a line and `whole of the mechanism` opened the next.
    Joining the run finds it and the offset map still reports the line a reader has to open.
    """
    held = []
    where = []
    for at, line in enumerate(lines):
        text = MARKER.sub("", line).strip()
        if not text:
            if held:
                yield "".join(held), where
                held = []
                where = []
            continue
        if held:
            held.append(" ")
            where.append(at + 1)
        held.append(text)
        where.extend([at + 1] * len(text))
    if held:
        yield "".join(held), where


# A quoted passage in a page: an opening double quote, a run of text, a closing one. Somebody
# else's words, and never this project's prose to repair. Jaynes is quoted twice in the ledger and
# once in an engine README, and joining wrapped lines put his wording in front of the scanner.
# Bounded to markdown, because a docstring's own """ marker would otherwise open a span that
# swallowed the rest of the file.
PASSAGE = re.compile(r"[\"“][^\"“”]{16,600}[\"”]")


def banned_hits(lines, quotations=False, comments=False, path=None, ledger=None):
    """Every banned token in one file, as (line number, pattern, matched text).

    One site is yielded once. A run is scanned whole, and two patterns that overlap would otherwise
    report the same words twice: "which is exactly what" matches both which-is-what and
    is-exactly-what, and repairing the sentence closes both at once.

    banned_tokens turns these into the findings a reader sees, and submission_check counts them per
    pattern against the rate a human writer carries. Both read the same hits. A count and a
    finding cannot disagree about what fired.

    quotations exempts a long quoted passage and the markdown citation spans, and is set for .md.

    comments turns on the COMMENT_ONLY patterns, which are the ones a standard scopes to a comment
    in the sentence that bans them. main() sets it for the extensions whose prose lives in comments.
    It defaults off. A caller that has not been taught the scope gets the documentation reading,
    the one both standards share. submission_check.py is that caller.

    The run-level context exemption is applied here, beside QUOTED, because it answers the same
    question QUOTED does about a different subject: a run whose subject is a writing convention has
    to be able to write the word it is about. It is tier-aware and QUOTED is not. It cannot be a
    span list, and it is the single call site in this file that knows both the run and the tier.
    """
    seen = set()
    for text, offsets in runs(lines):
        exempt = context_exempt(text)
        quoted = [span.span() for name in QUOTED for span in name.finditer(text)]
        # A backticked token is a name in a comment as much as in a page. This one is not
        # bounded to markdown the way the emphasis and quote spans are.
        quoted.extend(span.span() for span in NAMED_SPAN.finditer(text))
        if quotations:
            quoted.extend(span.span() for span in PASSAGE.finditer(text))
            quoted.extend(
                span.span()
                for name in NAMED_IN_MARKDOWN
                for span in name.finditer(text)
            )
        for pattern in BANNED:
            if (not comments) and (pattern in COMMENT_ONLY):
                continue
            tier = tier_of(pattern) if exempt else None
            for hit in re.finditer(pattern, text, re.IGNORECASE):
                start, stop = hit.span()
                if any(
                    (start >= opens) and (stop <= closes) for opens, closes in quoted
                ):
                    continue
                at = offsets[start] if start < len(offsets) else offsets[-1]
                token = hit.group(0)
                if tier in exempt:
                    if ledger is not None:
                        ledger.note(
                            "the subject is the convention",
                            CONTEXT_REASON,
                            "%s:%d %r" % ((path or "?").replace("\\", "/"), at, token),
                        )
                    continue
                # One phrase reported once. A run is scanned as a whole. A duplicate here would
                # be the same site seen through two patterns that overlap.
                key = (at, start, token.lower())
                if key in seen:
                    continue
                seen.add(key)
                yield (at, pattern, token)


# The only human corpus this file has a rate against, named wherever a rate is printed.
#
# It is the 154 research papers under build/papers, cut down to English by english_gate, which is
# 759,815 words. They are Salishan linguistics: Canadian and British convention throughout, carrying
# orthography, interlinear glosses, IPA and tables of forms. english_gate's own header names
# ban_evidence.py, which generates HUMAN_RATE, as one of three measurements this corpus corrupted,
# and the header above HUMAN_RATE records that correction.
#
# WHAT THIS REPLACES, AND IT WAS WRONG TWICE OVER. The unmeasured branch printed "unused in 1.1M
# human words". 1,108,054 is the UNGATED token count, which the HUMAN_RATE header states is the
# wrong denominator and low by about 40 percent, while the measured branch beside it was already
# dividing by 759,815. Two branches, two denominators, one corpus, in eleven lines of each other.
# And "human words" describes a general English sample, which 154 linguistics papers are not: the
# sentence read as a claim about English and was a claim about these papers.
#
# HOW MUCH OF THE TOOL'S OUTPUT IT WAS. Derived over this tree's own default run immediately before
# this change, at 51f492f with the structural repair applied: 3,981 of 4,296 prose lines carried the
# unmeasured wording and 315 carried the measured one. 92.7 percent of every prose line the tool
# emitted made a claim about 1.1 million human words. The misdescription was not an edge case in the
# report, it was almost the whole of it.
#
# Absence from these papers is weak evidence and the wording now says which papers. A reader can
# weigh it. A phrase can be missing because the domain is. Re-cut this against an English corpus, or
# keep naming the corpus. Never print a rate or an absence without the corpus behind it.
CORPUS = "the 759,815-word reference papers"


def banned_tokens(
    lines, quotations=False, comments=False, path=None, ledger=None, regions=None
):
    """Findings a reader sees, one per hit, carrying the tier and what stands behind it.

    A TIER A line names the section that bans the construction. A reader can go and read the
    sentence. A TIER B line carries a frequency where one was
    measured and says which corpus it was measured in where one was not. Neither fails a build.

    A finding inside a generated region keeps its place in the count and names the generator. Read
    the note above generated_regions for why it is attributed and not suppressed: in the one tree
    measured, suppressing it would have deleted the only genuine structural finding there was.
    """
    found = []
    for at, pattern, token in banned_hits(lines, quotations, comments, path, ledger):
        rate = HUMAN_RATE.get(pattern, 0.0)
        shape = stage_of(pattern)
        tier = tier_of(pattern)
        said = " ".join(token.split())
        if tier == "A":
            note = "tier A %s %r, banned at %s" % (shape, said, AUTHORITY[pattern])
        elif tier == "alphabet":
            note = "definition %r, American convention is the house rule" % said
        elif rate:
            note = "tier B %s %r, %.1f per 100k in %s" % (shape, said, rate, CORPUS)
        else:
            note = "tier B %s %r, not seen in %s" % (shape, said, CORPUS)
        found.append((at, attributed(note, at, regions)))
    return sorted(found)


def attributed(note, at, regions):
    """The same finding with its generator named, where it sits inside a generated region."""
    if regions and (at in regions):
        return "%s [generated by %s: fix the generator, then rerun it]" % (
            note,
            regions[at],
        )
    return note


def em_dashes(lines):
    return [(at + 1, "em dash") for at, line in enumerate(lines) if EM_DASH in line]


# Markdown that survived the conversion into .tex. Every one of these is valid LaTeX. The book
# compiles with no error, no warning and no dropped glyph, and carries the artifact to the archive.
#
# The em dash rule above could not see any of it. A --- is an em dash after typesetting and the
# check was looking for the character. The one form a converter actually produces was the one
# form it missed.
#
# All three were found by reading rendered pages, and this exists to stop that. In delta_null a
# --- set as a stray dash above the attribution on printed page 53, two claims wrapped in asterisks
# set as literal asterisks, and seventeen titles wrapped in escaped underscores set as literal
# underscores around Don Quixote, Faust and the Kalevala.
#
# Read against the stripped prose, and that keeps a filename out of the count: tex_prose
# removes \texttt{} with its braces. The escaped underscores inside a path are gone before this sees
# the line.
MARKDOWN_RULE = re.compile(r"^\s*-{3,}\s*$")
MARKDOWN_BOLD = re.compile(r"\*\*(?=\S)[^*]*\S\*\*")
MARKDOWN_ITALIC = re.compile(r"(?<![A-Za-z0-9])\\_(?=[A-Za-z])[^\\]*\\_(?![A-Za-z0-9])")

# A drawing, not emphasis. The SHA-256 shadow chapters plot one row per bit and the asterisks in
# those rows are ink. Three or more of the characters a plot is ruled with says so.
ASCII_ART = re.compile(r"[#=|+~^]{3,}")


def markdown_leftovers(lines):
    """Markdown left in a .tex source, which typesets as punctuation a reader sees on the page."""
    found = []
    for at, line in enumerate(lines):
        if ASCII_ART.search(line):
            continue
        if MARKDOWN_RULE.match(line):
            found.append(
                (at + 1, "markdown rule left in .tex, which typesets as an em dash")
            )
        if MARKDOWN_BOLD.search(line):
            found.append(
                (
                    at + 1,
                    "markdown bold left in .tex, which typesets as literal asterisks",
                )
            )
        if MARKDOWN_ITALIC.search(line):
            found.append(
                (
                    at + 1,
                    "markdown italics left in .tex, which typesets as literal underscores",
                )
            )
    return found


def path_candidate(target):
    """Whether a matched link target is a path at all, before asking whether the path is there.

    dead_links is a structural check and a structural finding fails a commit. A target this
    returns True about has to be something the filesystem can actually answer for. Two shapes wear
    markdown link syntax without being paths. Both were measured against a Doxygen C repository.

    Measured at ProtoCore f3e96f68, `python maint/prose/docs_check.py <protocore>/docs` reported 251
    breaking findings where 4 were real. 244 were Doxygen references and 3 were C declarators. The
    gate is correct in anchor_sift, a tree of Python and markdown that uses no Doxygen. Pointed at a
    repository that does use it, the gate would have refused every commit ProtoCore could make. That
    is why this test sits in front of os.path.exists instead of in an exemption list somewhere.

    Doxygen references, 244 of them. [`HTTP_10`](@ref HTTP_10) resolves against documented symbols.
    HTTP_10, HttpVersion, HttpReq::version, send_chunked, WS_FRAME_SIZE, MAX_HEADERS and
    PROTOCORE_ENABLE_KEEPALIVE were each confirmed as live symbols in ProtoCore's source. Every
    one of those findings reported a working cross-reference as a broken link.

    C declarators, 3 of them, at SECURITY.md:903, SSH.md:91 and SSH.md:94. A lambda in a fenced
    example writes `[](const char *user, const char *pass)`, and a parenthesized group following a
    bracketed one is the shape LINK looks for.

    Which signal earns its place. Across anchor_sift, ProtoCore, idemIP, MMgr and embedded_types,
    646 targets are skipped here and not one of them names a path that is on disk. Nothing that
    was a real finding has been silenced. 496 of the 646 are Doxygen commands and the other 150 hold
    a pointer star. Of the three declarator signals only the star fired. The type-keyword head and
    the comma-separated list caught nothing in those five trees and are kept for the parameter list
    that has neither star nor keyword, as in `(uint8_t slot, size_t len)`. The comma rule is the
    loosest of the three and is bounded to items of two words each. `docs/a.md, docs/b.md` stays
    a pair of paths.
    """
    if (not target) or ("://" in target) or target.startswith("/"):
        return False
    if DOXYGEN_TARGET.match(target):
        return False
    if "*" in target:
        return False
    if DECLARATOR_HEAD.match(target):
        return False
    parts = [one.strip() for one in target.split(",")]
    if (len(parts) > 1) and all(" " in one for one in parts):
        return False
    return True


def dead_links(path, lines):
    """A relative link to a file that is not there. Absolute and external links are left alone.

    A target that is not a path is skipped by path_candidate before anything is read from disk.
    """
    here = os.path.dirname(path)
    found = []
    for at, line in enumerate(lines):
        line = CODE_SPAN.sub(lambda span: " " * len(span.group(0)), line)
        for hit in LINK.finditer(line):
            target = hit.group(1).split("#")[0].strip()
            if not path_candidate(target):
                continue
            if not os.path.exists(os.path.join(here, target)):
                found.append((at + 1, "link to a file that is not there: %s" % target))
    return found


# The first line of every chapter theory_tex.py writes from a book's markdown.
#
# Ruled 2026-09-25: the gate checks the markdown and skips the chapters built from it. The
# exemptions a verbatim text is held under (a quoted span, a quiet block, a .verbatim marker) are
# read in the .md and are lost in the conversion, so the same quote passed in the .md and failed
# in its chapter. The cost: markdown the converter left in a chapter is no longer caught here.
# The dstroy0/theory repository's copy of this file, anchor_sift's theory/ as a submodule, skips
# them the same way.
GENERATED_CHAPTER = "% Generated by maint/texbuild/theory_tex.py"


def generated_chapter(path):
    """Whether a .tex was written by theory_tex.py from a markdown source."""
    if not path.endswith(".tex"):
        return False
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.readline().startswith(GENERATED_CHAPTER)


def walk_markdown(roots, ledger=None):
    """Every prose file under the given roots, taking a file argument as itself.

    Source files are included because a comment makes the same claims a page does, in the same
    voice, to the same reader. Checking only the pages left the register unchecked everywhere it is
    actually written.

    Directories that hold fetched or generated material are skipped. A published page under `site`
    is a copy of one already checked here, and reporting it twice trains a reader to skip the output.

    Selection goes through checked_file, which answers for a named file as well as an extension. A
    git hook has no extension and a CMakeLists.txt is a name, and both were invisible to the
    endswith test this used to make.

    A file holding text reproduced from a third party is declined here and named in the ledger. It
    is the only exclusion in this file that stops the read instead of shaping it, because a finding
    inside somebody else's document is a finding against its author and there is nothing for a
    reader of this report to decide about one.
    """
    found = []
    for root in roots:
        if os.path.isfile(root):
            if checked_file(root):
                found.append(root)
            continue
        for here, dirs, names in os.walk(root):
            dirs[:] = [one for one in dirs if one not in SKIP_DIRS]
            found.extend(
                os.path.join(here, name)
                for name in names
                if checked_file(os.path.join(here, name))
            )
    # This file writes down every phrase it bans. It matches itself on nearly all of them. The
    # markers below were tried first and did not hold up. Quieting 258 patterns one pair at a time
    # buries the list under its own pragmas, and a reader scrolling past a hundred of them stops
    # reading them.
    mine = os.path.abspath(__file__)
    my_dir = os.path.dirname(mine)
    kept = []
    for one in found:
        if os.path.abspath(one) == mine:
            continue
        # This tool's own test files carry banned prose on purpose, to prove the gate flags it.
        # Repairing them would break the tests. They sit beside this file and are excluded here, the
        # exclusion recorded like every other. A fixtures/ directory is already skipped by
        # SKIP_DIRS; these are the tests that live next to the gate.
        one_name = os.path.basename(one)
        if (os.path.dirname(os.path.abspath(one)) == my_dir) and one_name.startswith(
            "test_docs_check"
        ):
            if ledger is not None:
                ledger.note(
                    "gate self-test",
                    "carries banned prose to prove the gate flags it",
                    one.replace("\\", "/"),
                )
            continue
        held = verbatim_root(one)
        if held:
            if ledger is not None:
                ledger.note("verbatim third-party", held[1], one.replace("\\", "/"))
            continue
        if generated_chapter(one):
            if ledger is not None:
                ledger.note(
                    "generated chapter",
                    "written by theory_tex.py from a markdown file, and the markdown is checked",
                    one.replace("\\", "/"),
                )
            continue
        kept.append(one)
    return kept


# Turns the scan off between the two markers, for the other files that have to quote a banned phrase
# to explain it. Hyphenating one into is-what-makes would satisfy the regex and cost the reader the
# phrase they came to see. The markers are explicit and a reader can see what is exempt and why,
# where a silent per-file exemption shows them neither.
QUIET_OPEN = "docs-check: quoting"
QUIET_CLOSE = "docs-check: end quoting"


def quieted(lines):
    """The same lines with anything between the two markers blanked, line numbers preserved."""
    kept = []
    quiet = False
    for line in lines:
        if QUIET_OPEN in line:
            quiet = True
            kept.append("")
            continue
        if QUIET_CLOSE in line:
            quiet = False
            kept.append("")
            continue
        kept.append("" if quiet else line)
    return kept


# The audit on the mechanism above, written because the mechanism was found being misused. A marker
# pair protects a quotation, and a quotation has edges: it opens and closes where a sentence does. A
# pair used to silence a finding lands wherever the token sits, in the middle of a sentence. The two
# misused pairs in this tree closed on "four megabytes" and on "is not placed by this, and", where
# all four correct pairs closed on a finished sentence.
#
# Only the closing marker is tested. An opening marker sits above the quoted material in both shapes
# and tells them apart from nothing.
#
# Both halves of the tell have to agree before anything is reported: no sentence-ending punctuation
# before the marker, and a lowercase word after it. Either half alone fires on a table that ends in
# a bracket, or on a paragraph that happens to open lowercase.
#
# Reported and never refused. The evidence is six pairs, four correct against two misused, and the
# failure mode is a legitimate quotation of a fragment, which is a real thing to want to write. The
# one correct pair quoting two words closes cleanly because the sentence around it was written to
# close cleanly, and that will not hold for every future one. Raising this to breaking wants more
# pairs to have been right about, and not more confidence about six.
SENTENCE_END = (".", "?", "!", ":", ";", '"', "'", ")", "`")
CONTINUATION = re.compile(r"^[a-z]")


def near_marker(lines, at, step):
    """The nearest line carrying text on one side of a marker, without its comment marker.

    Blank lines and bare comment markers are stepped over. A pair set off by an empty comment line
    above and below is the shape that reads best, and stopping on one would report every block that
    was laid out with any care.
    """
    walk = at + step
    while 0 <= walk < len(lines):
        body = lines[walk].strip().lstrip("#/*%").strip()
        if body:
            return body
        walk += step
    return None


def marker_edges(lines):
    """Findings for a quiet block whose closing marker cuts a sentence in half."""
    found = []
    for at, line in enumerate(lines):
        if QUIET_CLOSE not in line:
            continue
        before = near_marker(lines, at, -1)
        after = near_marker(lines, at, 1)
        if (before is None) or (after is None):
            continue
        if before.endswith(SENTENCE_END) or not CONTINUATION.match(after):
            continue
        found.append(
            (
                at + 1,
                "quiet block closes in the middle of a sentence. A marker pair "
                "protects a quotation, and this pair is hiding a finding",
            )
        )
    return found


def tex_prose(lines):
    """A LaTeX source with its markup blanked and its sentences left, line numbers preserved.

    A .tex file is prose all the way down, unlike a source file where prose sits in the comments.
    What has to come out is the markup, and only the markup that is not language: a \\textbf or an
    \\emph wraps a sentence somebody wrote and it stays, while a \\texttt wraps a path and a \\label
    wraps an identifier, and reading either as prose reports findings against a filename.

    Math is dropped whole. A displayed equation is symbols, and an inline $x$ carries no sentence.

    Nothing here parses TeX. It removes the constructs that produce false findings and leaves the
    rest, the same trade prose_only already makes about string literals in source.
    """
    kept = []
    for line in lines:
        held = line

        # Comment to end of line, on an unescaped percent. A note to a co-author is prose and would
        # be worth checking, but it is also where a stray brace or a half sentence lives. It goes
        # with the markup and is not reported against.
        held = re.sub(r"(?<!\\)%.*$", "", held)

        # Math, inline and displayed. Done before commands, since a command inside math goes with
        # it.
        held = re.sub(r"\$\$.*?\$\$", " ", held)
        held = re.sub(r"(?<!\\)\$.*?(?<!\\)\$", " ", held)
        held = re.sub(r"\\\[.*?\\\]", " ", held)
        held = re.sub(r"\\\(.*?\\\)", " ", held)

        # Commands whose braces hold an identifier and never a sentence. The argument goes with the
        # command. \allowbreak{} appears mid-path in this tree's citations and would otherwise leave
        # its fragments behind as words.
        held = re.sub(
            r"\\(texttt|verb|url|href|path|label|ref|eqref|cite\w*|input|include|"
            r"includegraphics|usepackage|documentclass|bibliography\w*|hypersetup|"
            r"newcommand|renewcommand|def|allowbreak|textbackslash)\s*(\[[^\]]*\])?"
            r"(\{[^{}]*\})*",
            " ",
            held,
        )

        # Environment openers and closers, which name the environment and carry no sentence.
        held = re.sub(
            r"\\(begin|end)\s*\{[^{}]*\}(\[[^\]]*\])?(\{[^{}]*\})*", " ", held
        )

        # Every remaining command keeps its braces, since \textbf{a sentence} is a sentence. The
        # command name itself goes, and so do the braces around it.
        held = re.sub(r"\\[A-Za-z@]+\s*(\[[^\]]*\])?", " ", held)
        held = held.replace("{", " ").replace("}", " ")

        # Alignment and cell separators in a table, which glue unrelated words into a phrase.
        held = held.replace("&", " ").replace("\\\\", " ")

        kept.append(held)
    return quieted(kept)


# A quoted or apostrophized span, blanked before a `#` is looked for. A hash inside a string is
# not read as a comment marker. Carried from ai_words.py, which this pass supersedes.
STRING_SPAN = re.compile(r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'")


def hash_tail(line):
    """The `#` comment on one line, or empty where there is none.

    The hash has to open a word: at the start of the line, or after whitespace. Without that rule
    `$#` in a shell script and `${#name}` in both shell and CMake read as comment markers, and a run
    of argument arithmetic gets scanned as prose.

    Strings are masked first. `message("count: #1")` is not read as a comment either.
    """
    masked = STRING_SPAN.sub(lambda hit: " " * len(hit.group(0)), line)
    for at, character in enumerate(masked):
        if character != "#":
            continue
        if at == 0 or masked[at - 1].isspace():
            return line[at:]
    return ""


def comment_prose(lines):
    """The comment text of a build file, with the rest blanked and line numbers preserved.

    Blanked. A finding still names the line a reader has to open. Handles the
    `#` form shell, CMake, YAML and make all share, and PowerShell's `<# ... #>` block.

    A shebang is dropped. It is the only line of a shell script that is an instruction to the kernel
    and not a sentence, and `#!/usr/bin/env python3` reported nothing but was read every time.

    THE CMake STRING IS DELIBERATELY NOT READ. idemIP's CMakeLists.txt:122 puts a banned phrase
    inside a `set(... CACHE BOOL "...")` description, which is a string and reaches a person through
    `ccmake`. Reading it wants a CMake parser, and guessing at one
    would report every quoted path in every add_custom_command. Named here because it is a known
    gap and not an oversight.
    """
    kept = []
    in_block = False
    for at, line in enumerate(lines):
        if at == 0 and line.startswith("#!"):
            kept.append("")
            continue
        if in_block:
            kept.append(line)
            if "#>" in line:
                in_block = False
            continue
        if "<#" in line:
            in_block = "#>" not in line
            kept.append(line)
            continue
        kept.append(hash_tail(line))
    return kept


def prose_only(path, lines, ledger=None):
    """The comment and docstring lines of a source file, with the code blanked out.

    Line numbers are preserved by replacing code with an empty string instead of dropping it, and a
    finding still points at the line a reader has to open. Deliberately crude about string literals:
    a banned word inside one is worth looking at anyway, since it is usually output text.

    THE LEGAL BLANKING HAPPENS HERE AND NOWHERE ELSE, on every branch, and that keeps the four
    stages from each carrying a skip of their own. em_dashes, markdown_leftovers and banned_tokens
    all read what this returns. An em dash inside a copyright grant and a British form inside
    one go quiet together and by one rule. empty_tables and dead_links read the raw lines instead,
    because a table and a link are structure and a legal block holds neither.
    """
    if path.endswith(".md"):
        return legal_blank(quieted(lines), path, ledger)
    if path.endswith(".tex"):
        return legal_blank(tex_prose(lines), path, ledger)
    # Tested before .py, because a build file can be named or extended and a .py never is.
    if build_file(path):
        return legal_blank(quieted(comment_prose(lines)), path, ledger)

    kept = []
    in_block = False
    for line in lines:
        stripped = line.strip()
        if path.endswith(".py"):
            # Count the markers on the line instead of testing how it starts and ends. The earlier
            # form closed a block by testing that the line was longer than five characters. A
            # closing triple quote on its own line measured three and reopened the block it was
            # closing. Every code line after the first multi-line docstring in a file was then read
            # as prose. EM_DASH = "-" then reported itself as an em dash, and a
            # `for row in summary` reported itself as the filler phrase.
            marks = stripped.count('"""') + stripped.count("'''")
            if marks:
                kept.append(line)
                # An odd count opens or closes. An even count is a docstring written on one line.
                if marks % 2:
                    in_block = not in_block
                continue
            kept.append(line if (in_block or stripped.startswith("#")) else "")
            continue

        # C and its headers.
        if "/*" in line:
            in_block = True
        was = in_block
        if "*/" in line:
            in_block = False
        if was or stripped.startswith("//"):
            kept.append(line)
        elif "//" in line:
            # A trailing // or ///< comment on a code line. The gate read only a line-leading //
            # before. Every banned phrase in a trailing comment went unflagged, and about sixty of
            # them sat unread across idemIP's headers. Keep from the first // to the end and blank
            # the code before it, which preserves the line number a finding points at. A trailing /*
            # */ block is already caught by in_block above; this is the slash form it missed. Crude
            # about a // inside a string literal, the same trade this function makes for the leading
            # case.
            cut = line.index("//")
            kept.append(line[cut:])
        else:
            kept.append("")
    return legal_blank(quieted(kept), path, ledger)


RATCHET_HEADER = (
    "# Prose findings per file, the most each file may carry. docs_check.py --ratchet reads it.\n"
    "# A count may fall and never rise: a commit that raises one is stopped, and a commit that\n"
    "# lowers one writes the lower number here. Regenerate by hand with --ratchet-write only when a\n"
    "# file moves, since a moved file starts again at zero under its new name.\n"
)


def ratchet_read(path):
    """The per-file ceilings in a ratchet file, or None where the file is absent."""
    if not os.path.isfile(path):
        return None
    ceilings = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if not line.strip() or line.startswith("#"):
                continue
            name, count = line.rstrip("\n").rsplit("\t", 1)
            ceilings[name] = int(count)
    return ceilings


def ratchet_write(path, ceilings):
    """Write the ceilings sorted by path, leaving out every file that carries none."""
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(RATCHET_HEADER)
        for name in sorted(ceilings):
            if ceilings[name]:
                handle.write("%s\t%d\n" % (name, ceilings[name]))


def staged_paths():
    """Repository-relative paths the commit being written adds, copies, modifies or renames."""
    said = git_say(REPOSITORY, ("diff", "--cached", "--name-only", "--diff-filter=ACMR"))
    return set(one.strip() for one in (said or "").splitlines() if one.strip())


def option_value(name):
    """The value of a --name=value option, or None where it was not given."""
    for one in sys.argv[1:]:
        if one.startswith(name + "="):
            return one[len(name) + 1:]
    return None


def main():
    # Findings quote the text they flag, which can hold any character (U+2212 in a formula). A
    # Windows console defaults to cp1252 and raised on it, ending the run before later findings
    # printed.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    # Structure fails a commit. Prose is reported and does not, because the prose backlog predates
    # this check and a hook nobody can satisfy is a hook somebody turns off. Pass --strict to fail
    # on everything, the setting a cleanup pass wants.
    #
    # PROSE NEVER FAILS A BUILD, IN EITHER TIER, IN ANY REPOSITORY, ANCHOR_SIFT INCLUDED. Both
    # standards state it in the same sentence that names this tool, verbatim and word for word:
    # "A hit is a prose finding. It never fails a build, because a person has to decide each site: a
    # proper name, a quoted title, or a term of art is left standing and reported as a false
    # positive." That is code-documentation:145, and code-comments:208 says it again.
    #
    # So --strict is a cleanup-pass mode and is never a pre-commit setting anywhere. A tier does not
    # change this: TIER A carries more authority than TIER B and still only reports.
    strict = "--strict" in sys.argv
    ratchet = option_value("--ratchet")
    ratchet_out = option_value("--ratchet-write")
    staged = "--staged" in sys.argv
    counts = {}
    # --fix RUNS THE POLICY AND WRITES NOTHING. The rewriting half is deliberately not implemented;
    # read the note above FIX_TIERS for why the only tier it could ever reach is the alphabet one.
    # The gate is here first so whoever writes the other half has to come through fix_refusal and
    # cannot skip the manifest, verbatim, generated and normative-keyword refusals already tested
    # beside it. Never a pre-commit setting in any repository, in either mode.
    planning = "--fix" in sys.argv
    where_given = [one for one in sys.argv[1:] if not one.startswith("-")]
    if ratchet and where_given:
        print("  --ratchet holds the whole repository to its ceilings and does not take roots.")
        return 4
    # Every place this project keeps prose, since a README beside the code is read the same way a
    # page under docs is. Checking only docs left the twelve engine and example READMEs unchecked,
    # and one of them was carrying a paragraph sitting inside a table.
    # A named root is taken as given, then tried against the repository. A hook runs from wherever
    # git puts it, and `docs` meaning nothing from there is how this came to check zero files.
    roots = []
    for one in where_given or DEFAULT_ROOTS:
        if os.path.exists(one):
            roots.append(one)
            continue
        beside = os.path.join(REPOSITORY, one)
        roots.append(beside if os.path.exists(beside) else one)

    # THE ROOTS GO FIRST, BEFORE ANY FINDING. A reader has to know the scope before the count, since
    # "0 findings" over two configured roots and "0 findings" over a whole tree are the same three
    # characters and mean opposite things.
    print(
        "  roots configured: %d, %s"
        % (
            len(roots),
            (
                "given on the command line"
                if where_given
                else "this tool's own defaults, inside this repository only"
            ),
        )
    )
    for one in roots:
        print(
            "    %s%s"
            % (one.replace("\\", "/"), "" if os.path.exists(one) else "   NOT FOUND")
        )

    for top, revision, reach, dirty in refs_for(roots):
        print(
            "  measured at %s %s, %s%s"
            % (
                os.path.basename(top),
                revision,
                reach,
                ", working tree has uncommitted changes" if dirty else "",
            )
        )

    ledger = Ledger()
    breaking = 0
    prose = 0
    checked = 0
    refusals = []
    allowed = []

    for path in sorted(walk_markdown(roots, ledger)):
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
        checked += 1
        said = prose_only(path, lines, ledger)

        # A generated region is reported and attributed, never skipped. The one genuine structural
        # finding in the tree this was measured against sits inside one. A rule that skipped
        # marked regions would have reported that tree clean. The marker carries the generator.
        # The attribution is read from the document and cannot go stale.
        regions = {}
        if path.endswith(".md"):
            regions, unclosed = generated_regions(lines)
            for at, complaint in unclosed:
                print("  BREAK %s:%d: %s" % (path.replace("\\", "/"), at, complaint))
                breaking += 1

        # A reader sees these as a broken page. They stop a commit. Tables and links exist only
        # in markdown; an em dash is wrong in a comment too.
        structural = em_dashes(said)
        if path.endswith(".md"):
            structural += empty_tables(lines) + dead_links(path, lines)
        # Markdown left in a .tex builds clean and reaches the reader as punctuation. That is the
        # same failure an em dash is and belongs in the same column.
        if path.endswith(".tex"):
            structural += markdown_leftovers(said)
        # These read wrong and render fine. marker_edges reads the raw lines, since quieted() has
        # already blanked the content the tell is measured on by the time prose_only returns.
        # comments says whether this file's prose sits in comments, the scope code-comments
        # section 200 gives its three outright tokens. A .md is a page and a .tex is prose all
        # the way down. Neither is a comment; everything else here is read for its comments.
        wording = banned_tokens(
            said,
            quotations=path.endswith(".md"),
            comments=not path.endswith((".md", ".tex")),
            path=path,
            ledger=ledger,
            regions=regions,
        ) + marker_edges(lines)

        for at, what in sorted(structural):
            print(
                "  BREAK %s:%d: %s"
                % (path.replace("\\", "/"), at, attributed(what, at, regions))
            )
        for at, what in sorted(wording):
            print("  prose %s:%d: %s" % (path.replace("\\", "/"), at, what))

        if planning:
            fix_plan(path, lines, said, regions, refusals, allowed)

        breaking += len(structural)
        prose += len(wording)
        # relpath raises across Windows drives. A file on another drive lies outside the repository,
        # and no ratchet entry names it by a relative path.
        try:
            name = os.path.relpath(path, REPOSITORY)
        except ValueError:
            name = path
        counts[name.replace("\\", "/")] = len(wording)

    print("  %d file(s) checked, %d breaking, %d prose" % (checked, breaking, prose))

    risen = []
    if ratchet_out:
        ratchet_write(ratchet_out, counts)
        print("  ratchet written: %d file(s) carry prose findings" % sum(1 for n in counts.values() if n))

    if ratchet:
        ceilings = ratchet_read(ratchet)
        if ceilings is None:
            print("  no ratchet at %s. Nothing to compare against, and that is never a pass." % ratchet)
            print("  write one with: python %s --ratchet-write=%s" % (sys.argv[0], ratchet))
            return 4
        # Only what this commit carries is held to its ceiling. Other files in the working tree are
        # other people's work in progress, and stopping a commit over them stops the wrong person.
        scope = staged_paths() if staged else set(counts)
        lowered = 0
        for name in sorted(scope):
            if name not in counts:
                continue
            ceiling = ceilings.get(name, 0)
            if counts[name] > ceiling:
                risen.append((name, counts[name], ceiling))
            elif counts[name] < ceiling:
                ceilings[name] = counts[name]
                lowered += 1
        if lowered:
            ratchet_write(ratchet, ceilings)
        print(
            "  ratchet: %d file(s) held to their ceiling, %d lowered, %d risen"
            % (len([one for one in scope if one in counts]), lowered, len(risen))
        )
        for name, count, ceiling in risen:
            print("  RISEN %s: %d prose finding(s), ceiling %d" % (name, count, ceiling))

    # What was excluded and why. Printed even when nothing was, because "excluded: 0" and a silence
    # are the same two states, and a reader has to be able to tell them apart.
    print("  excluded: %d" % ledger.total())
    for line in ledger.report():
        print(line)

    if planning:
        print(
            "  --fix is a plan only. Nothing was written, and the rewriting half of it is "
            "deliberately not implemented."
        )
        print("    would rewrite: %d" % len(allowed))
        for where in allowed[:20]:
            print("      %s" % where)
        if len(allowed) > 20:
            print("      ... and %d more" % (len(allowed) - 20))
        print("    REFUSED: %d" % len(refusals))
        for where in refusals[:20]:
            print("      %s" % where)
        if len(refusals) > 20:
            print("      ... and %d more" % (len(refusals) - 20))
        for one in manifests_covering(roots):
            print(
                "    this tree carries a signed manifest, %s. After anything writes here: %s"
                % (os.path.basename(one), reconcile_command(one))
            )

    # The one line that keeps this report from claiming more than it measured. Four independent
    # reasons a finding survives a gate, each sufficient alone: the hook is not installed, the
    # declared roots exclude the file, no rule matches it, and the extension cannot be opened. This
    # tool answers for the last two. The first two are per-repository decisions and belong to
    # whoever owns that repository.
    print(
        "  this run read %d file(s) under %d root(s) and nothing outside them. Whether a hook is "
        "installed and which roots a repository declares are that repository's decisions, not "
        "this tool's: a gate that is correct, installed nowhere, and scoped to two paths still "
        "catches nothing." % (checked, len(roots))
    )

    # Checking nothing is not passing. A run that reads no files and reports success is the failure
    # a commit hook cannot see, and it is how a wrong path goes unnoticed for as long as it takes
    # somebody to wonder why the count never moves.
    if checked == 0:
        print("  no files were read. Nothing was checked. Nothing passed.")
        for one in roots:
            print(
                "    %s%s" % (one, "" if os.path.exists(one) else "   does not exist")
            )
        return 2

    # One for a refusal and two for the sentinel, never a count. Returning the number of findings
    # made a run with exactly two breaking findings indistinguishable from a run that read nothing,
    # and the commit hook tests for 2 by name and would have printed "the docs check read nothing"
    # over a real pair of em dashes. Pointing this at theory/ for the first time produced exactly
    # that: 43 files, 2 breaking, and an exit code that said the opposite of what happened.
    #
    # A count is the wrong shape for an exit status besides. They wrap at 256. 256 findings
    # would have exited 0.
    if breaking or (strict and prose):
        return 1
    if risen:
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
