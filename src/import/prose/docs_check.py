#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
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

# The tokens the writing standard bans outright, and the British definitions it bans by pattern.
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
    # The same shape with no copula and no article, which is how code-documentation section 146
    # writes both of the examples it bans by name: "Declared, not allocated." and "A number, not a
    # guess." Every X-not-Y pattern in this file wanted (is|was|are|were) and an article, so the two
    # sentences the standard names walked past all three of them. Derived by running the standard's
    # own illustrations through the checker: 4 of 28 named phrases were missed and two were these.
    #
    # Bounded to a whole short sentence of that shape, which is what both examples are. The
    # mid-sentence appositive, "the bound is read in the header, not in the .c", is left alone: the
    # standard permits the contrast where a reader would otherwise land on the wrong one, and
    # reaching for every comma costs more true sentences than the tic is worth.
    r"(?m)(?:\A|(?<=[.!?] ))(?:(?:An?|The) )?[\w-]+, not (?:(?:an?|the) )?[\w-]+\.(?:\s|\Z)",
    # Nothing inanimate speaks. The standard names the subjects it bans: a name, a definition, a token
    # or a type. A paper, a table and an entry are texts and legitimately say things, and an earlier
    # version of this pattern included them and reported nine sites that were all correct.
    #
    # make clear was missing from the verb alternation. Both standards name it in the same list as
    # say, signal, encode, convey, advertise and announce -- code-documentation section 147 and
    # code-comments section 156 -- and six of the seven were transcribed. "The header makes clear
    # that the payload follows" was not caught until this line took the seventh.
    r"\b(name|definition|token|type|structure|constraint)s?\s+(says|say|signals|signal|encodes|encode|"
    r"conveys|convey|announces|announce|advertises|advertise|makes clear|make clear)\b",
    # code-comments section 200 names three tokens and bounds them in the same sentence: "none has a
    # legitimate use in a comment here". Two are enforced here: rather (above) and the third token
    # (below).
    # The third, the bare article, is not, and was removed: a \ba\b pattern matches the article in
    # nearly every sentence of ordinary prose, so it fired on the great majority of findings on a
    # normal page and buried the real ones. If the section means a single-letter identifier named a
    # and not the article, that is a different pattern than this and belongs written as one.
    # The third token is banned in every form, in a comment and on every page alike, and the define
    # family stands in for it.
    r"\b(?:mis)?spell(?:s|ed|ing|ings)?\b",
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
    # The is-what-VERBs construction, generalized from the makes variant above. code-documentation
    # section 126 names ten verbs and code-comments section 205 names six of the same ten.
    #
    # The second alternation is this file's own, and it is where the bare carry, hold, cost, read,
    # buy, pay, spend, earn, win, price and slot bans went when they came out below. Section 143
    # states the rule those bans were breaking: "a word that reads as a tic in one construction only
    # is bounded to that construction." This is the construction.
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
    # imperative came off this line. code-comments/SKILL.md:99 requires "@brief Single-sentence
    # summary using imperative voice", so the grammatical mood is the field's own word here and the
    # rule reported the standard for naming it. Section 143's first escape: a term the field owns
    # stays.
    r"\b(indispensable|paramount)\b",
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
    # WITHDRAWN: \bworse than (not|nothing|none|no |having)\b and \bis worse than a\b. Both fired on
    # the standards. code-documentation/SKILL.md:84 writes "A wrong line number is a false claim and
    # worse than none", :165 writes "A stale section is worse than a missing one", and
    # code-comments/SKILL.md:122 writes the first of those again about a MISRA rule number. A
    # comparison of two failure modes by cost is the ordinary way to state which one to prefer.
    #
    # WITHDRAWN: \bstated (once|twice)\b, \btwo facts that\b and \bone fact per\b. These banned the
    # standards' own rule text. Both files write "One fact is stated once; a second copy is a future
    # contradiction" at :21, code-documentation writes "One fact per sentence" at :146 and
    # code-comments writes it at :199. A checker that reports the sentence stating a rule as a
    # violation of that rule is the over-reach class this pass exists to remove.
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
    # \band nothing else\b was written here a second time. One rule in two places is two rules that
    # can be edited apart, and banned_hits deduping on (line, offset, token) is what kept the second
    # copy from doubling every finding for as long as it stood. The copy near the head of this tuple
    # is the one that stays, beside the and-nothing-more and and-no-more forms it belongs with.
    # Tier five, the preachy register, and the whole tier came out of one session's own output.
    # Writing about a corpus that belongs to somebody else pulls prose toward the sermon, and the
    # sermon is worse than useless here: every line in this repository carries one person's name,
    # and a paragraph telling the reader how to feel about the material reads as that person
    # performing and not stating. The ethics are in the permission column and in what the gates
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
    # Tier six, and the first tier this file did not find by itself. A 340 word passage of
    # theory/crystallography/chapters/chapter_whose_result.tex was scored by an outside detector,
    # which returned 80.4 percent machine written and marked which sentences carried it. Every shape
    # below is out of a marked sentence and was not already in the table above.
    #
    # The outside number is worth little on its own. A detector reading perplexity marks plain
    # declarative technical prose as machine written because that prose is low perplexity, which is
    # a property of the register and not of the author. What makes this tier worth adding is that
    # two unrelated instruments picked the same file: the eight patterns below were counted across
    # 53 documents before any was kept, and chapter_whose_result.tex is 26 lines long and trips five
    # of them, at lines 10, 16, 18, 20 and 24. Nothing else in the tree is that dense.
    #
    # Counted first, per the rule the tiers above set: 11, 17, 3, and 1 apiece for the rest.
    #
    # The X-not-Y antithesis wearing definite articles. Line 30 and line 78 ask for a or an, so
    # "the good outcome and not the bad one" walks past both of them.
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
    # Half of a can-only against cannot pair. Each half is ordinary and the pairing is the tic, which
    # no single pattern reaches, so this catches the half that carries it.
    r"\bcan only show (that|whether)\b",

    # ---- Added 2026-09-11, found by a detector probe and not by a frequency table. ----
    #
    # Everything above came from comparing token frequencies against a human corpus, which finds
    # TOKENS. It cannot find a sentence whose every word is ordinary and whose SHAPE is the tell,
    # and those pass the gate and still read wrong.
    #
    # Method: prose was written in the register being hunted, then scored per sentence by Sapling's
    # detector - twice, with different wording carrying the same shapes. A sentence was kept only if
    # it scored high AND tripped nothing already in this tuple, and a shape only if it recurred
    # across both batches, since one high score is that detector's noise. No document from either
    # tree was sent anywhere: the register is what is being characterised, and prose about nothing
    # characterises it as well as prose about the work, with nothing at stake in it.
    #
    # Each was then run against the whole tree. These ten matched nothing already written.
    # "not merely" was REJECTED by the same test: it hit eighteen live lines, every one of them the
    # deliberate X-and-not-merely-Y idiom this work uses on purpose. Banning it would have removed a
    # construction rather than a tic, which is the failure a ban list has to be checked for before
    # anything is added to it.
    #
    # One calibration note for anyone extending this. The detector scored "It was a warm afternoon
    # and the window was open" at 0.99, which looks like a false positive and is not one: that
    # sentence is scene-setting, which belongs to fiction, and in technical prose a register
    # mismatch is exactly what it reads. Narrative openers are a real shape here and no pattern
    # below reaches them, because a regex cannot see register. They still have to be caught by eye.

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

    # Tier seven, and the first tier an outside detector found instead of a person. One passage of
    # theory/Salishan/chapters/chapter_Salishan_pure_corpus_README.tex read 35.6 percent machine
    # written. Six constructions came out of it and the same passage read 4.5 percent, with every
    # fact and every number unchanged. The patterns below are those six.
    #
    # What they share is that each one puts the document in the subject position and gives it a
    # verb of authority or of reading. A page does not settle a character and a reading is not an
    # authority. A person settled it, off that page.
    r"\bis (?:the|an?) authority for\b",
    r"\bit then reads as\b",
    r"\bare settled on page\b",
    # The temporal hedge on a state nobody dated. Either the table has the note or it does not.
    r"\b(?:table|document|page|file|row) first had no\b",
    # A colon splicing two independent clauses, which is the elaboration shape section 6 bans in
    # prose and which the detector scores the same way.
    r"\bhas no call and no text:",

    # Tier eight. Sapling scored the passage these came from at 0.1 percent, every sentence 0.0,
    # and the author read the same passage and said it was not his writing. An outside detector is
    # trained on published machine prose. Whether a page sounds like the person whose name is on
    # the book is a different question and it does not answer it.
    #
    # These four came out by ear. All of them name a table field and then give it something to do.
    # The tree already calls that field the who column, and somebody fills it in by hand.
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
    # Two sentences restating the sentence before them. Where the magnification already appeared,
    # saying it again is the paragraph explaining itself.
    r"\bat that magnification\b",
    # Declaring a field empty, in a document whose rule is that an empty field says so by being
    # empty.
    r"\bwho column empty\b",
    r"\bhis name does not go in it\b",
    # A participle standing in for the condition. Name the condition: doing it without saying so.
    r"\bmade quietly\b",
    r"\bif it were made quietly\b",
    # A pipeline given a dependency. Name the caller: no text tool calls it.
    r"\bnothing in the \w+ pipeline depends\b",
    r"\bnothing downstream depends\b",
    # A digest placed somewhere by itself. Name the file that carries it.
    r"\bits SHA-256 sits in\b",
    r"\b(?:hash|digest|checksum) sits in\b",
    # A tool or a representation given eyes. A script reads a file, a representation is the output.
    r"\b(?:sound|text|word) representation reads\b",
    r"\bthe representation reads\b",
    # Deixis repeating the heading it sits under.
    r"(?m)^This one does not read\b",
    r"\bno (?:text|other) tool calls it\b",
    # Exclusivity asserted about a set the reader cannot see. Either it is the only one, cited, or
    # the clause comes out.
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
    # WITHDRAWN 2026-09-16. carry and hold in every form used to sit here, and the bare word bans
    # for slot, book, construction, cost, buy, pay, spend, earn, afford, win, price and read sat
    # further down. All thirteen are gone. What replaced them is the is-what-VERB construction
    # above, and the narrow phrases each tier already carried stay where they are. WITHDRAWN at the
    # foot of this tuple records every one, with the count it cost and the sentence that removed it.
    #
    # The comment that used to stand here is kept, because the observation in it was real and the
    # rule built on it was not: "A digest is listed in a manifest. A value is in a column. A form
    # appears on a page." That is a house preference for a precise verb, and precise verbs are
    # worth wanting. It is not a register tell, and a bare word ban is not how it gets enforced.

    # The provenance section of the workbook, read out loud. Every one of these came out of one
    # page.
    #
    # shape, where nothing has a shape. The topology books use it for a real one and are the only
    # place it stands.
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
    # Position standing in for the relation. A reference is attached to a claim or it is missing.
    r"\bno reference beside it\b",
    # WITHDRAWN: bare \bbeside it\b. It fired on code-documentation/SKILL.md:84, "cite the line that
    # shows the thing being said, not the line beside it", where beside it is literal adjacency in a
    # file and is the whole of what that rule is about. The bounded form above stays.
    # The reading, as a thing that happens without a reader.
    r"\bthe reading has not been done\b",
    # A script given a character: it reports, it never decides, it is honest about itself.
    r"\bit reports and never decides\b",
    r"\breports and never\b",
    # An emphatic tail on a count that was already exact.
    r"\bare mixed at all\b",
    r"\b(?:is|are|was|were) \w+ at all\b",
    # slot, in every form. Nothing here has slots. A field has a name already: the who column, the
    # year field, the identifier. A chaining state has positions, and FIPS 180-4 calls its eight
    # a through h the working variables.
    #
    # 29 hits in theory/ when this went in, 25 of them in the SHA-256 chain chapter.
    #
    # WITHDRAWN 2026-09-16, bare \bslot(?:s|ted|ting)?\b. See WITHDRAWN at the foot of this tuple.
    # The narrow phrases the same tier wrote stay: the slot stays empty, the record slot is empty.
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
    # WITHDRAWN 2026-09-16, bare \bbooks?\b and \bconstruction\b. Both are naming rules about this
    # tree's own vocabulary and neither is a register claim, so section 143 has no construction to
    # bound them to. code-comments/SKILL.md:199 writes "Antithesis, parallelism, and
    # colon-then-elaboration are essay construction, not comment construction", so the second of the
    # two reported the standard twice in one sentence. See WITHDRAWN at the foot of this tuple.
    # A caveat given descendants, and the pair of clauses that always follows it.
    r"\binherits that\b",
    r"\brecorded here inherits\b",
    r"\bevery one of them \w+ and none of them\b",
    r"\bnone of them \w+s\b",
    # cost, in every form. A retrieval that took five attempts took five attempts. Say the number.
    #
    # No exception. Give the number and its units: corpus symbol accesses, character comparisons,
    # cycles, bytes.
    r"\ba measured cost\b",
    # The rest of the transaction. A fold does not buy rounds, an arm does not win, a measurement
    # does not earn or spend or pay. 84 of these in theory/ when they went in: buys 19, wins 17,
    # earns 8, spends 7.
    #
    # WITHDRAWN 2026-09-16: the bare cost, buy, bought, pay, paid, spend, spent, earn, afford, win,
    # won, read and price bans. The observation behind them stands and the bare word ban does not.
    # See WITHDRAWN at the foot of this tuple.
)

# ====================================================================
# WITHDRAWN: THE THIRTEEN UNBOUNDED WORD BANS, AND WHAT TOOK THEM OUT
# ====================================================================
#
# Recorded rather than deleted, because each of these was added for a reason somebody had and a
# later reader who only sees the absence will add it back.
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
# So the gate flagged the standard it enforces, 63 times in running prose across the two files
# before this pass. That is the whole of the over-reach class and it needed no enumeration to find.
#
# WHY NONE OF THEM COULD BE BOUNDED THE WAY paradigm shift IS. The construction these read as a tic
# in is an inanimate subject taking a human verb, and no regex separates it from the correct
# technical use. "The header carries the checksum" and "the buffer holds the segment" are the right
# verbs in a network stack, and they are character for character the shape the ban was after.
# What IS bounded, and what these went into, is the is-what-VERB construction near the head of this
# tuple, which both standards name.
#
# Each entry is the word, what it was after, and the sentence that removed it.
WITHDRAWN = {
    "carry": "the verb in every inflection, banned a digest would be said to be listed in a "
             "manifest instead. Both standards use it and code-documentation:145 uses it about "
             "this file.",
    "hold": "added when the repair pass for carry wrote hold everywhere instead. Chasing a "
            "synonym is the sign that the rule is on a word and not on a shape.",
    "read": "a fold does not read and a person does, which is true and is not what \\breads\\b "
            "tests. code-comments:208 writes \"reads .c and .h comments\". 337 hits.",
    "slot": "nothing in the theory books has slots, which is a house naming rule about one "
            "directory. code-comments:195 makes a handle slot a term of art in a section "
            "heading. 134 hits.",
    "cost": "say the number and its units. The instruction is right and the ban is not: a cost "
            "is what a number measures. 66 hits.",
    "buy": "the transaction metaphor. code-documentation:85 writes \"buys nothing the reader "
           "asked for\" and code-comments:178 writes \"The letter buys explicitness\".",
    "pay": "the same metaphor, one verb over.",
    "spend": "the same again. code-documentation:84 writes \"it spends a reader's trust\".",
    "earn": "the same again. code-documentation:114 writes \"each one earned its place by "
            "measurement\", which is the sentence that justifies half this table.",
    "afford": "the same again, and the only one of the ten with no hit anywhere measured.",
    "win": "an arm does not win. True, and the word has a plain use the ban could not see.",
    "price": "added a repair pass could not swap cost for it. A ban added to close the exit "
             "from another ban is the shape of a rule that is chasing words.",
    "book": "these are theories, which is a naming rule about this tree's own vocabulary and "
            "carries no claim about register at all.",
    "construction": "it is a method. Same shape as book, and code-comments:199 writes \"essay "
                    "construction, not comment construction\" while stating a rule this file "
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
# ALPHABET. Definition, and it recovers the locale before it says anything about a writer. The
# papers are Canadian and British convention linguistics, so neighbour fires at 17.3 per hundred
# thousand words in them and analyse at 8.9, behaviour at 4.8, labelled at 2.9, centre at 2.3.
# None of that is machine prose. It is where the author is, and the American definitions this tree
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
#   a                       46.5 assistant     1.3 human     36 times
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

# The definition stage. British convention against American, which is a locale and a house rule.
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

    A pattern is alphabet when it is a definition. It is phrase when it matches across a space, and that
    makes it a shape instead of a vocabulary item. Everything else is word.

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
# orior's theory books and named as such in the report.
#
# THE TIER IS DECIDED BY THE SENTENCE IN THE STANDARD, NEVER BY THE REGEX. This is the correction
# that matters and it runs both ways:
#
#   `rather` is one token and matches one word, so stage_of calls it a word. Its ban is stated
#   outright at code-documentation:110 and again at code-comments:200. It is TIER A.
#   `\bis what (separates|keeps|...)` is a construction by shape and by authority alike, and the
#   verbs this file added to it beyond the standard's ten are TIER A all the same, because the
#   construction is what is banned and the verb list is how far it reaches.
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
# CONSTRUCTIONS, so detection AND repair operate on constructions and never on words. TIER A is
# report-only, permanently. A token-for-token definition swap is the only class an autofix could ever
# own here, and that is the alphabet stage and not this table.
AUTHORITY = {
    # code-comments:200 bans three tokens outright. rather and the third token are enforced; the bare
    # article a is not (a \ba\b pattern matches the article in nearly every sentence of prose -- see
    # BANNED above). rather also carries a documentation ban of its own at code-documentation:110,
    # and the third token is banned in every form and on every page.
    r"\brather\b": "code-documentation:110, code-comments:200",
    r"\b(?:mis)?spell(?:s|ed|ing|ings)?\b": "code-comments:200, every page",
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
    r"|carries|costs|reads|buys|pays|spends|earns|wins|prices|slots|books)\b":
        "code-documentation:126, code-comments:205",
    r"\b(is|was|are|were) an? [\w-]+ and never an? [\w-]+": "code-documentation:127",
    r"\band nothing more\b": "code-documentation:128, code-comments:207",
    r"\band no more\b": "code-documentation:128, code-comments:207",
    r"\bthe one (thing|place|case|word|reason|table|file|grain|repair|mistake|addition|column)\b":
        "code-documentation:129, code-comments:207",
    r"\bthe whole of (the|what|it)\b": "code-documentation:130, code-comments:207",
    r"\bis precisely (what|why|the)\b": "code-documentation:131",
    r"\b(what|that) matters (is|here|most)\b": "code-documentation:131",
    # No rhetorical sentence shapes. code-documentation:146, code-comments:199.
    r"cost and not a defect": "code-documentation:146",
    r"\b(is|was|are|were) an? [\w-]+ and not an? [\w-]+": "code-documentation:146",
    r"\b(is|was|are|were) the [\w-]+ and not the [\w-]+": "code-documentation:146",
    r"(?m)(?:\A|(?<=[.!?] ))(?:(?:An?|The) )?[\w-]+, not (?:(?:an?|the) )?[\w-]+\.(?:\s|\Z)":
        "code-documentation:146",
    r"\bhas no call and no text:": "code-documentation:146",
    # Nothing inanimate speaks. code-documentation:147, code-comments:156.
    r"\b(name|definition|token|type|structure|constraint)s?\s+(says|say|signals|signal|encodes|encode|"
    r"conveys|convey|announces|announce|advertises|advertise|makes clear|make clear)\b":
        "code-documentation:147, code-comments:156",
    # No conversational filler. Four forms are named by name in both files.
    r"load-bearing": "code-documentation:148",
    r"\blet['’]s\b": "code-documentation:148, code-comments:155",
    r"\bdiv(e|es|ing) (into|in|deeper)\b": "code-documentation:148, code-comments:155",
    r"\b(certainly|absolutely|of course)[!,]": "code-documentation:148, code-comments:155",
    r"\bit (is|'s) (important|worth|useful|helpful) (to note|noting|to remember|to mention|mentioning)\b":
        "code-documentation:148, code-comments:155",
    # The assistant register. code-documentation:141.
    r"\bas an ai\b": "code-documentation:141",
    r"\bas a language model\b": "code-documentation:141",
    r"\bmy training data\b": "code-documentation:141",
    r"\b(i apologi[sz]e|my apologies|sorry for the)\b": "code-documentation:141",
    # The which-is clause again, in the form the later tier wrote it.
    r"\bwhich is (what|why|how|the (difference|point|whole|answer|reason|rule))\b":
        "code-comments:206",
}

# A selector that names nothing is drift, and drift in a table like this is silent: the tier simply
# stops being claimed and every finding in it prints as house style. ai_words.py learned this the
# expensive way and checks its own selectors the same way. Raised at import, not reported at
# runtime, because a tier that quietly holds no patterns reports clean forever.
_ORPHANS = tuple(one for one in AUTHORITY if one not in BANNED)
if _ORPHANS:
    raise SystemExit("docs_check: AUTHORITY names %d pattern(s) that are not in BANNED. A tier "
                     "selector matching nothing reports clean forever.\n  %s"
                     % (len(_ORPHANS), "\n  ".join(_ORPHANS)))


# The tokens whose ban holds in comments only. None is: of the three code-comments:200 bans
# outright, `rather` carries a documentation ban of its own at code-documentation:110, the bare
# article `a` is not enforced at all, and the third is banned on every page. The set stays for a
# ban a standard scopes to comments.
COMMENT_ONLY = frozenset()


def tier_of(pattern):
    """A for a named-construction ban, B for frequency-scored vocabulary, alphabet for a definition.

    Read AUTHORITY above for why this is not stage_of with different words.
    """
    if pattern in LOCALE:
        return "alphabet"
    return "A" if pattern in AUTHORITY else "B"


EM_DASH = "—"

# Definitions that are somebody's name and never this project's prose. The International Conference on
# Salish and Neighbouring Languages defines its own name that way, and thirteen extraction scripts
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
# 283 prose findings and 220 of them, 77.7 percent, sat inside a markdown code span. Every one was
# the standard writing out a token it bans a reader can see which token is meant. A checker that
# reports a standard for naming its own bans is reporting the wrong thing 220 times.
#
# THREE MARKERS, and each one was needed. The backtick span is the bulk of it. The emphasis run is
# how both files quote a banned shape that is longer than a token: code-comments:161 writes
# *That is the difference between a helper naming a step and a helper costing a call* to show what
# an aphoristic clause reads like. The quoted span is the same device with quotes, and its floor is
# one character rather than PASSAGE's sixteen, because the named forms are short: *"Certainly!"* is
# ten characters and *"load-bearing"* is twelve, and both walked past PASSAGE.
#
# WHAT IT COSTS. A banned word that happens to sit in backticks anywhere in the tree goes quiet. A
# token inside backticks is a symbol or a quoted form in every markdown convention, and a symbol is
# not this checker's business, so that trade is the one already made for QUOTED and for PASSAGE.
# Bounded to markdown alongside PASSAGE, except the backtick span, which reads the same way in a
# comment and is where a comment names a symbol.
NAMED_SPAN = re.compile(r"`[^`\n]{1,300}`")
NAMED_IN_MARKDOWN = (
    # Bold, then italic. Italic excludes a neighbouring asterisk so **bold** is not read as an
    # italic span opening on its second asterisk.
    re.compile(r"\*\*[^*\n]{1,300}\*\*"),
    re.compile(r"(?<!\*)\*[^*\n]{1,300}\*(?!\*)"),
    # The short quoted form. PASSAGE stays for the long quotation, which is a different thing: it
    # exempts somebody else's words, and this exempts the document's own citation of a form.
    re.compile(r"[\"“][^\"“”\n]{1,600}[\"”]"),
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
# every path in this tree the last time anything moved. The sentinel upstream is
# src/engine, which this repository renamed to src/core and src/device, so the walk ran
# past the repository and every prose root resolved to the drive root. It is .git here,
# which marks a repository by definition and which no rename can move.
while (REPOSITORY != os.path.dirname(REPOSITORY)) \
        and not os.path.exists(os.path.join(REPOSITORY, ".git")):
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


# Fetched or generated, so nothing in them was written here.
# fixtures holds the positive control for machine_distance.py, written deliberately in the
# assistant register. Repairing it would delete the only sample of the thing being detected.
SKIP_DIRS = (".git", "build", "site", "deps", "__pycache__", ".vscode", "fixtures")

# A markdown table separator: | --- | --- |
SEPARATOR = re.compile(r"^\s*\|[\s:|-]+\|\s*$")
ROW = re.compile(r"^\s*\|")

# A relative markdown link, skipping anything with a scheme and anything anchored to a heading.
LINK = re.compile(r"\[[^\]]*\]\(([^)#][^)]*)\)")

# A Doxygen cross-reference written in markdown link syntax: [`HTTP_10`](@ref HTTP_10). Doxygen
# resolves the target against the symbol table it builds from the source. The word after the command
# is an identifier. The filesystem has no answer to give about it, and producing one means reading
# Doxygen's tag file, which this tool does not do.
#
# Both definitions of every command are accepted, since Doxygen takes @ref and \ref alike.
DOXYGEN_TARGET = re.compile(r"^[@\\](ref|subpage|page|link|anchor|cite|see|copydoc)\b")

# C declarator syntax that LINK matches by accident. A lambda in a fenced example writes its capture
# list in square brackets and its parameter list in parentheses, so `[](uint8_t slot, HttpReq *req)`
# is character for character the shape a markdown link has.
#
# Three signals, each one sufficient, and each one chosen because a relative path cannot carry it:
# a pointer star anywhere in the target, a C type qualifier or specifier opening it, or a
# comma-separated run where every item is two words. A path with a comma in it is legal and rare,
# and `docs/a.md, docs/b.md` fails the last test because neither item has an interior space.
DECLARATOR_HEAD = re.compile(r"^(const|volatile|unsigned|signed|struct|enum|union|static)\s")


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


def banned_hits(lines, quotations=False):
    """Every banned token in one file, as (line number, pattern, matched text).

    One site is yielded once. A run is scanned whole, and two patterns that overlap would otherwise
    report the same words twice: "which is exactly what" matches both which-is-what and
    is-exactly-what, and repairing the sentence closes both at once.

    banned_tokens turns these into the findings a reader sees, and submission_check counts them per
    pattern against the rate a human writer carries. Both read the same hits, a count and a
    finding cannot disagree about what fired.
    """
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
                yield (at, pattern, token)


def banned_tokens(lines, quotations=False):
    found = []
    for at, pattern, token in banned_hits(lines, quotations):
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


# Markdown that survived the conversion into .tex. Every one of these is valid LaTeX, so the book
# compiles with no error, no warning and no dropped glyph, and carries the artifact to the archive.
#
# The em dash rule above could not see any of it. A --- is an em dash after typesetting and the
# check was looking for the character, so the one definition a converter actually produces was the one
# definition it missed.
#
# All three were found by reading rendered pages, which is what this exists to stop. In delta_null a
# --- set as a stray dash above the attribution on printed page 53, two claims wrapped in asterisks
# set as literal asterisks, and seventeen titles wrapped in escaped underscores set as literal
# underscores around Don Quixote, Faust and the Kalevala.
#
# Read against the stripped prose, which is what keeps a filename out of the count: tex_prose removes
# \texttt{} with its braces, so the escaped underscores inside a path are gone before this sees the
# line.
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
            found.append((at + 1, "markdown rule left in .tex, which typesets as an em dash"))
        if MARKDOWN_BOLD.search(line):
            found.append((at + 1, "markdown bold left in .tex, which typesets as literal asterisks"))
        if MARKDOWN_ITALIC.search(line):
            found.append((at + 1,
                          "markdown italics left in .tex, which typesets as literal underscores"))
    return found


def path_candidate(target):
    """Whether a matched link target is a path at all, before asking whether the path is there.

    dead_links is a structural check and a structural finding fails a commit, a target this
    returns True about has to be something the filesystem can actually answer for. Two shapes wear
    markdown link syntax without being paths. Both were measured against a Doxygen C repository.

    This test sits in front of os.path.exists instead of in an exemption list somewhere.

    Doxygen references. [`HTTP_10`](@ref HTTP_10) resolves against documented symbols, and a
    finding on one reports a working cross-reference as a broken link.

    C declarators. A lambda in a fenced example writes `[](const char *user, const char *pass)`,
    and a parenthesized group following a bracketed one is what LINK looks for.

    No target skipped here names a path that is on disk. The type-keyword head and the
    comma-separated list are kept for the parameter list that has neither star nor keyword, as in `(uint8_t slot, size_t len)`. The comma rule is the
    loosest of the three and is bounded to items of two words each, so `docs/a.md, docs/b.md` stays
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
        for hit in LINK.finditer(line):
            target = hit.group(1).split("#")[0].strip()
            if not path_candidate(target):
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
        found.append((at + 1, "quiet block closes in the middle of a sentence. A marker pair "
                              "protects a quotation, and this pair is hiding a finding"))
    return found


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
        # with the markup and is not reported against.
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
    for one in (where_given or DEFAULT_ROOTS):
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
        # Markdown left in a .tex builds clean and reaches the reader as punctuation, which is the
        # same failure an em dash is and belongs in the same column.
        if path.endswith(".tex"):
            structural += markdown_leftovers(said)
        # These read wrong and render fine. marker_edges reads the raw lines, since quieted() has
        # already blanked the content the tell is measured on by the time prose_only returns.
        wording = banned_tokens(said, quotations=path.endswith(".md")) + marker_edges(lines)

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
