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
# Exit status is the count of findings, so it fails a pipeline without needing a flag.

import os
import re
import sys

# The tokens the writing standard bans outright, and the British spellings it bans by pattern.
BANNED = (
    r"\brather\b",
    r"\badd up\b",
    # Named by hand. The X-not-Y shape is banned generally by the writing standard and permitted
    # where a reader would otherwise land on the wrong one, which no regex can tell apart. This is
    # the instance that was called out, and the list grows one phrase at a time for that reason.
    r"cost and not a defect",
    # The same shape, caught by its grammar. It reports where the standard permits it too, so it is
    # a prose finding and never a breaking one: a person decides each site.
    r"\b(is|was|are|were) an? [\w-]+ and not an? [\w-]+",
    # Nothing inanimate speaks. The standard names the subjects it bans: a name, a spelling, a token
    # or a type. A paper, a table and an entry are texts and legitimately say things, and an earlier
    # version of this pattern included them and reported nine sites that were all correct.
    r"\b(name|spelling|token|type|structure|constraint)s?\s+(says|say|signals|signal|encodes|encode|"
    r"conveys|convey|announces|announce|advertises|advertise)\b",
    r"\bso a\b",
    r"load-bearing",
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
    r"\banalyse(s|d)?\b",
    # The register tics. These are not wrong facts, they are the sound of writing that is performing
    # instead of explaining, and they were found by reading a batch of this project's own prose back
    # and noticing the same shapes in every paragraph. Each one is a sentence that exists for its
    # rhythm: delete it and the paragraph loses nothing but its swagger.
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
    r"\bis what (separates|keeps|tells|puts|says|makes|supplies|gives|decides|holds|stops|lets)\b",
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
    # measurement, so none of them breaks a build. They are the words a reader has learned
    # to read as unwritten, and a page carrying them gets skimmed instead of read. Nothing in a
    # library about memory, entropy or crystal axes needs any of them.
    #
    # Two rules kept words off this list. A term the field owns stays: a grammatical paradigm, a
    # robust estimator, a significant difference, an alignment. And a word that only reads as a tic
    # in one construction is bounded to that construction instead of banned outright.
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
    # Talking to the reader instead of writing for them. Bounded to the contraction: lets is a verb.
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
    # sweeping came off this line. A parameter sweep is an operation this tree runs, and the rule
    # made three agents reword correct prose about one.
    r"\b(far.reaching|wide.ranging|all.encompassing|overarching)\b",
    r"\b(indispensable|paramount|imperative)\b",
    r"\b(sophisticated|layered|expansive|exhaustive)\b",
    r"\b(stunning|striking|breathtaking|awe.inspiring|mesmeri[sz]ing|dazzling)\b",
    r"\b(intuitive|elegant|sleek|polished|frictionless)\b",
    r"\b(rigorous|painstaking|diligent|thorough)\b",
    r"\b(innovative|disruptive|trailblazing|visionary)\b",
    # powerful came off this line. The thought experiments discuss power as a subject, and the rule
    # turned "selects for the powerful" into a rewrite of a claim about people.
    r"\b(scalable|versatile)\b",
    # Verbs that inflate what the code does.
    r"\b(uncover|unveil|illuminate|unearth|unravel|demystify)",
    # amplify, boost and maximize came off this line. All three are literal here: a controller arm
    # amplifies, an audio band is boosted, and a quantity is maximized in the ordinary math sense.
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
    # Tier four, and the test for it was a search. Each shape below was looked up and returned no
    # result dated before 2020. A phrase people did not write until models wrote it is a phrase to
    # cut. The distance instrument reads the same tree the same way: 79.6 percent of the margin on
    # docs/research/index.md sat on sentence shape.
    #
    # A clause that announces a conclusion and carries no fact.
    r"\bthat is (what|why|the (difference|point|whole|answer|test|reason|rule|shape|cost))\b",
    # Searched with the measuring word attached as well. "which is how far" returns nothing dated
    # before 2020 either, so the exemption it looked like it deserved was not there.
    r"\bwhich is (what|why|how|the (difference|point|whole|answer|reason|rule))\b",
    r"\band that is (what|why|the)\b",
    # Defining a thing by what it is not.
    r"\b(checking|reading|running|measuring|saying) [a-z]+ is not [a-z]+ing\b",
    r"\bis not an? (accusation|argument|claim|answer|excuse|guess|estimate)\b",
    # proof and evidence are the field's own words here. "a row that checked nothing is not
    # evidence that anything held" is a precise claim about a bench and it stays.
    r"\bis not (a pass|passing|failing)\b",
    r"\bworse than (not|nothing|none|no |having)\b",
    r"\bis worse than a\b",
    # A fact restated as its own inversion, which reads as a maxim and adds nothing.
    r"\bstated (once|twice)\b",
    r"\btwo facts that\b",
    r"\bone fact per\b",
    # Machinery given intent. A run does not say anything and a file does not answer.
    # A run of characters is the field's own term and predates all of this. Only the execution
    # sense is banned, so the verb has to be one a program does.
    r"\ba run that (finishes|reads|reports|says|passes|fails|completes|knows|decides)\b",
    r"\b(the (file|tool|check|hook|run|number|count|table)) (says|answers|knows|decides)\b",
    # Hedges, and a pointer left behind after the thing it pointed at was cut.
    r"\bthe ordinary (case|answer)\b",
    r"\bnothing else here\b",
    # "nothing here is a timing claim" states a scope and stays. The banned form is the flourish
    # that closes a paragraph on nothing.
    r"\bnothing here is (new|magic|special|clever|hidden|secret|surprising)\b",
    r"\band nothing else\b",
    # Tier five, the preachy register, and the whole tier came out of one session's own output.
    # Writing about a corpus that belongs to somebody else pulls prose toward the sermon, and the
    # sermon is worse than useless here: every line in this repository carries one person's name,
    # and a paragraph telling the reader how to feel about the material reads as that person
    # performing rather than stating. The ethics are in the permission column and in what the gates
    # refuse. They do not need narrating on top.
    #
    # The rule this tier enforces is that a fact is stated once, flat, and left alone.
    #
    # Moral entitlement. Whatever is owed here is settled in the licence and in SPEECH.tsv.
    r"\b(is|are|was|were) (the least|what) (they|we|he|she|you|somebody) (are |is |)?(owed|deserve)",
    r"\b(the least|more) (they|we|you) (deserve|are owed)\b",
    r"\bwe owe (them|him|her|you|it)\b",
    r"\bentitled to (make|take|say|claim)\b",
    # Ranking two things by worth. Three patterns were tried here and dropped after they fired on
    # real engineering prose in this tree. "a miss is worth more than a hit here" is a claim about
    # what a diagnostic tells you, "the whole point of the file" names what a function is for, and
    # "as distinctive as it should be" is a measurement against a prediction. None of those is the
    # register this tier is after, and banning them would have cost five true sentences to catch
    # two of mine. What is left is the shape that only ever shows up in a sermon.
    r"\bthe more valuable\b",
    r"\bthe (smallest|least) part of what\b",
    r"\bworth more than (the|their|his|her|any) \w+ (itself|themselves)\b",
    # Aphorism built on a moral antithesis. "something done, never something suffered" is the shape.
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
    # Announcing one's own virtue in doing the ordinary thing. The comma is what separates the
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
    # nothing" were tried here and dropped: six sites in this tree use them for exactly what they
    # say, as in "a shuffle holds nothing beyond one symbol" and "a domain that holds nothing".
    # What made the banned version preachy was the verb repeating against itself across a clause,
    # and no pattern separates that from the plain use. This is the third over-broad rule added to
    # this file and caught by running it, so run it before keeping the next one.
    r"\bwould (prove|buy) nothing\b",
    # A bare abstraction standing in for the subject, usually in a closing clause.
    r"\bthe (reproducible|checkable|measurable|honest|valuable) thing\b",
    # Arguing the design instead of describing it.
    r"\bagainst how (somebody|someone|anybody|people)\b",
    r"\bin nearly every (respect|way|case)\b",
    r"\bdoes not put a (reader|person|user) on the path\b",
    r"\ba (rule|check|gate|test) added here\b",
)

# docs-check: quoting
# ====================================================================
# THE THREE STAGES, AND WHAT MEASURED THEM
# ====================================================================
# The list above is one flat table and it was built by noticing. maint/prose/ban_evidence.py
# scored every pattern in it against 1,108,054 words of human research papers under build/papers,
# and against the 403,111 words of prose in this tree. That run split the table into three stages
# that filter at different widths, and the stages behave nothing alike.
#
# ALPHABET. Spelling, and it recovers the locale before it says anything about a writer. The
# papers are Canadian and British convention linguistics, so neighbour fires at 17.3 per hundred
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
# A clause that explains the sentence just written is the signature, and the phrase stage is what
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
# was measured against a corpus labelled Claude 3 Opus, a different model and a different year, and
# it was wrong. Humans do use them. The assistant uses the list at 1.66 times the human rate.
# docs-check: end quoting

# The spelling stage. British convention against American, which is a locale and a house rule.
LOCALE = (
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

# docs-check: quoting
# What each pattern costs a human writer, per hundred thousand words of the research papers.
# Measured, not estimated. A pattern absent from this table fired zero times in all 154 of them.
#
# Counted over 759,815 words, which is the papers after english_gate takes them down to English.
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
    r"\b(name|spelling|token|type|structure|constraint)s?\s+(says|say|signals|signal|encodes|encode|conveys|convey|announces|announce|advertises|advertise)\b": 0.4,
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

    A pattern is alphabet when it is a spelling. It is phrase when it matches across a space, and that
    makes it a shape instead of a vocabulary item. Everything else is word.
    """
    if pattern in LOCALE:
        return "alphabet"
    if " " in pattern:
        return "phrase"
    return "word"


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

# Prose lives in pages, in comments, and in the books, and the same voice writes all three.
#
# .tex was absent from this tuple until now, so no theory book had ever been register checked. The
# books are the longest continuous prose in the tree and the only part written to be read straight
# through, which made them the worst thing to have been leaving out.
CHECKED = (".md", ".py", ".c", ".h", ".tex")

# Every place this project keeps prose. A README beside the code makes the same claims a page under
# docs makes, and is read by the same people.
#
# Held against the repository and not against the working directory. These were plain relative names
# once, and from anywhere but the root they matched nothing: the run reported zero files, zero
# findings and success. A commit hook calling it that way lets every commit through and reports the
# prose as checked.
REPOSITORY = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while (REPOSITORY != os.path.dirname(REPOSITORY)) \
        and not os.path.isdir(os.path.join(REPOSITORY, "src", "engine")):
    REPOSITORY = os.path.dirname(REPOSITORY)

# Every directory holding writing of this project's own. It named tools/ until that directory was
# split into data/, analysis/ and maint/, and the run then read 188 files instead of 317 and still
# exited 0. data/ and analysis/ later moved under maint/ and stayed listed here as though they were
# still at the top, which is the same defect a second time.
#
# A root that no longer exists is not an error this could see. The guard below is what turns that
# into one, and the count at the foot is still the thing to watch after a move.
DEFAULT_ROOTS = tuple(os.path.join(REPOSITORY, one)
                      for one in ("docs", "src", "examples", "maint", "theory"))

for one in DEFAULT_ROOTS:
    if not os.path.isdir(one):
        raise SystemExit("docs_check: %s is listed as a prose root and does not exist. A missing "
                         "root reads as zero findings and exits 0, which passes every commit."
                         % one)


def private_roots():
    """The closed repositories beside this one, where they are present.

    Their READMEs, licences, registers and tools are written here and were going unchecked. Two
    banned forms sat in the corpus licence for a day because this scan stopped at the public tree.
    A checkout without them scans four roots and says four, which is the ordinary case for anyone
    outside this work.
    """
    beside = os.path.join(os.path.dirname(REPOSITORY), "private_repos")
    held = []
    for one in ("salishan_corpus", "anchor_sift_citations"):
        where = os.environ.get("ANCHOR_SIFT_PRIVATE") if one == "salishan_corpus" else None
        where = where or os.path.join(beside, one)
        if os.path.isdir(where):
            held.append(where)
    return tuple(held)

# Fetched or generated, so nothing in them was written here.
# fixtures holds the positive control for claudese_distance.py, written deliberately in the
# assistant register. Repairing it would delete the only sample of the thing being detected.
SKIP_DIRS = (".git", "build", "site", "deps", "__pycache__", ".vscode", "fixtures")

# A markdown table separator: | --- | --- |
SEPARATOR = re.compile(r"^\s*\|[\s:|-]+\|\s*$")
ROW = re.compile(r"^\s*\|")

# A relative markdown link, skipping anything with a scheme and anything anchored to a heading.
LINK = re.compile(r"\[[^\]]*\]\(([^)#][^)]*)\)")


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


def banned_tokens(lines, quotations=False):
    found = []
    seen = set()
    for text, offsets in runs(lines):
        quoted = [span.span() for name in QUOTED for span in name.finditer(text)]
        if quotations:
            quoted.extend(span.span() for span in PASSAGE.finditer(text))
        for pattern in BANNED:
            for hit in re.finditer(pattern, text, re.IGNORECASE):
                start, stop = hit.span()
                if any((start >= opens) and (stop <= closes) for opens, closes in quoted):
                    continue
                at = offsets[start] if start < len(offsets) else offsets[-1]
                token = hit.group(0)
                # One phrase reported once. A run is scanned as a whole. A duplicate here would
                # be the same site seen through two patterns that overlap.
                key = (at, start, token.lower())
                if key in seen:
                    continue
                seen.add(key)
                rate = HUMAN_RATE.get(pattern, 0.0)
                where = stage_of(pattern)
                if rate:
                    note = "%s token %r, humans use it %.1f per 100k" % (
                        where, " ".join(token.split()), rate)
                else:
                    note = "%s token %r, unused in 1.1M human words" % (
                        where, " ".join(token.split()))
                found.append((at, note))
    return sorted(found)


def em_dashes(lines):
    return [(at + 1, "em dash") for at, line in enumerate(lines) if EM_DASH in line]


def dead_links(path, lines):
    """A relative link to a file that is not there. Absolute and external links are left alone."""
    here = os.path.dirname(path)
    found = []
    for at, line in enumerate(lines):
        for hit in LINK.finditer(line):
            target = hit.group(1).split("#")[0].strip()
            if (not target) or ("://" in target) or target.startswith("/"):
                continue
            if not os.path.exists(os.path.join(here, target)):
                found.append((at + 1, "link to a file that is not there: %s" % target))
    return found


def walk_markdown(roots):
    """Every prose file under the given roots, taking a file argument as itself.

    Source files are included because a comment makes the same claims a page does, in the same
    voice, to the same reader. Checking only the pages left the register unchecked everywhere it is
    actually written.

    Directories that hold fetched or generated material are skipped. A published page under `site`
    is a copy of one already checked here, and reporting it twice trains a reader to skip the output.
    """
    found = []
    for root in roots:
        if os.path.isfile(root):
            if root.endswith(CHECKED):
                found.append(root)
            continue
        for here, dirs, names in os.walk(root):
            dirs[:] = [one for one in dirs if one not in SKIP_DIRS]
            found.extend(os.path.join(here, name) for name in names if name.endswith(CHECKED))
    # This file writes down every phrase it bans, so it matches itself on nearly all of them. The
    # markers below were tried first and did not hold up. Quieting 258 patterns one pair at a time
    # buries the list under its own pragmas, and a reader scrolling past a hundred of them stops
    # reading them.
    mine = os.path.abspath(__file__)
    return [one for one in found if os.path.abspath(one) != mine]


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


def tex_prose(lines):
    """A LaTeX source with its markup blanked and its sentences left, line numbers preserved.

    A .tex file is prose all the way down, unlike a source file where prose sits in the comments.
    What has to come out is the markup, and only the markup that is not language: a \\textbf or an
    \\emph wraps a sentence somebody wrote and it stays, while a \\texttt wraps a path and a \\label
    wraps an identifier, and reading either as prose reports findings against a filename.

    Math is dropped whole. A displayed equation is symbols, and an inline $x$ carries no sentence.

    Nothing here parses TeX. It removes the constructs that produce false findings and leaves the
    rest, which is the same trade prose_only already makes about string literals in source.
    """
    kept = []
    for line in lines:
        held = line

        # Comment to end of line, on an unescaped percent. A note to a co-author is prose and would
        # be worth checking, but it is also where a stray brace or a half sentence lives, so it goes
        # with the markup rather than being reported against.
        held = re.sub(r"(?<!\\)%.*$", "", held)

        # Math, inline and displayed. Done before commands, since a command inside math goes with it.
        held = re.sub(r"\$\$.*?\$\$", " ", held)
        held = re.sub(r"(?<!\\)\$.*?(?<!\\)\$", " ", held)
        held = re.sub(r"\\\[.*?\\\]", " ", held)
        held = re.sub(r"\\\(.*?\\\)", " ", held)

        # Commands whose braces hold an identifier and never a sentence. The argument goes with the
        # command. \allowbreak{} appears mid-path in this tree's citations and would otherwise leave
        # its fragments behind as words.
        held = re.sub(r"\\(texttt|verb|url|href|path|label|ref|eqref|cite\w*|input|include|"
                      r"includegraphics|usepackage|documentclass|bibliography\w*|hypersetup|"
                      r"newcommand|renewcommand|def|allowbreak|textbackslash)\s*(\[[^\]]*\])?"
                      r"(\{[^{}]*\})*", " ", held)

        # Environment openers and closers, which name the environment and carry no sentence.
        held = re.sub(r"\\(begin|end)\s*\{[^{}]*\}(\[[^\]]*\])?(\{[^{}]*\})*", " ", held)

        # Every remaining command keeps its braces, since \textbf{a sentence} is a sentence. The
        # command name itself goes, and so do the braces around it.
        held = re.sub(r"\\[A-Za-z@]+\s*(\[[^\]]*\])?", " ", held)
        held = held.replace("{", " ").replace("}", " ")

        # Alignment and cell separators in a table, which glue unrelated words into a phrase.
        held = held.replace("&", " ").replace("\\\\", " ")

        kept.append(held)
    return quieted(kept)


def prose_only(path, lines):
    """The comment and docstring lines of a source file, with the code blanked out.

    Line numbers are preserved by replacing code with an empty string instead of dropping it, and a
    finding still points at the line a reader has to open. Deliberately crude about string literals:
    a banned word inside one is worth looking at anyway, since it is usually output text.
    """
    if path.endswith(".md"):
        return quieted(lines)
    if path.endswith(".tex"):
        return tex_prose(lines)

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
        kept.append(line if (was or stripped.startswith("//")) else "")
    return quieted(kept)


def main():
    # Structure fails a commit. Prose is reported and does not, because the prose backlog predates
    # this check and a hook nobody can satisfy is a hook somebody turns off. Pass --strict to fail
    # on everything, the setting a cleanup pass wants.
    strict = "--strict" in sys.argv
    where_given = [one for one in sys.argv[1:] if not one.startswith("-")]
    # Every place this project keeps prose, since a README beside the code is read the same way a
    # page under docs is. Checking only docs left the twelve engine and example READMEs unchecked,
    # and one of them was carrying a paragraph sitting inside a table.
    # A named root is taken as given, then tried against the repository. A hook runs from wherever
    # git puts it, and `docs` meaning nothing from there is how this came to check zero files.
    roots = []
    for one in (where_given or (DEFAULT_ROOTS + private_roots())):
        if os.path.exists(one):
            roots.append(one)
            continue
        beside = os.path.join(REPOSITORY, one)
        roots.append(beside if os.path.exists(beside) else one)

    breaking = 0
    prose = 0
    checked = 0

    for path in sorted(walk_markdown(roots)):
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
        checked += 1
        said = prose_only(path, lines)

        # A reader sees these as a broken page, so they stop a commit. Tables and links exist only
        # in markdown; an em dash is wrong in a comment too.
        structural = em_dashes(said)
        if path.endswith(".md"):
            structural += empty_tables(lines) + dead_links(path, lines)
        # These read wrong and render fine.
        wording = banned_tokens(said, quotations=path.endswith(".md"))

        for at, what in sorted(structural):
            print("  BREAK %s:%d: %s" % (path.replace("\\", "/"), at, what))
        for at, what in sorted(wording):
            print("  prose %s:%d: %s" % (path.replace("\\", "/"), at, what))

        breaking += len(structural)
        prose += len(wording)

    print("  %d file(s) checked, %d breaking, %d prose" % (checked, breaking, prose))

    # Checking nothing is not passing. A run that reads no files and reports success is the failure
    # a commit hook cannot see, and it is how a wrong path goes unnoticed for as long as it takes
    # somebody to wonder why the count never moves.
    if checked == 0:
        print("  no files were read. Nothing was checked, so nothing passed.")
        for one in roots:
            print("    %s%s" % (one, "" if os.path.exists(one) else "   does not exist"))
        return 2

    # One for a refusal and two for the sentinel, never a count. Returning the number of findings
    # made a run with exactly two breaking findings indistinguishable from a run that read nothing,
    # and the commit hook tests for 2 by name and would have printed "the docs check read nothing"
    # over a real pair of em dashes. Pointing this at theory/ for the first time produced exactly
    # that: 43 files, 2 breaking, and an exit code that said the opposite of what happened.
    #
    # A count is the wrong shape for an exit status besides. They wrap at 256, so 256 findings
    # would have exited 0.
    if breaking or (strict and prose):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
