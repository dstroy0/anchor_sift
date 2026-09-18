#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# What the prose standard says, checked instead of remembered.
#
#   Usage:  python maint/prose/docs_check.py [root]
#

import os
import re
import subprocess
import sys

LOCALE_NAMED = (
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

# The suffixes an -ise stem takes. `-isable` and `-isability` were tried and came out: see above.
_ISE_TAIL = r"(?:e|es|ed|ing|er|ers)"

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
    r"\b(?![A-Za-z]*(?:%s)%s\b)[A-Za-z]{2,}[bcdfghjklmnpqrstvxz]is%s\b"
    % ("|".join(_ISE_STEMS), _ISE_TAIL, _ISE_TAIL),
    r"\b[A-Za-z]{3,}isation(?:al|s)?\b",
    r"\b(?:analys|paralys|catalys|dialys|electrolys|hydrolys)(?:e|ed|ing|er|ers)\b",
    r"\b(?![A-Za-z]*(?:%s)%s\b)[A-Za-z]{3,}our%s\b"
    % ("|".join(_OUR_WORDS), _OUR_TAIL, _OUR_TAIL),
    r"\b[A-Za-z]*(?:centre|metre|theatre|fibre|litre|calibre|sabre|sombre|spectre"
    r"|lustre|meagre|manoeuvre|sceptre)s?\b",
    r"\b(?:labell|modell|signall|travell|cancell|levell|totall|fuell|diall|marvell"
    r"|counsell|equall|initiall|spirall|tunnell|quarrell|refuell|shovell)"
    r"(?:ed|ing|er|ers|ors|or)\b",
    r"\b(?:fulfil|fulfils|fulfilment|fulfilments|enrol|enrols|enrolment|enrolments"
    r"|instal|instals|instalment|instalments|skilful|skilfully|wilful|wilfully"
    r"|enthral|enthrals|appal|appals|distil|distils|instil|instils)\b",
    r"\b(?:defence|offence|pretence|licence)s?\b",
    r"\b(?:catalogue|analogue)[sd]?\b",
    r"\bprogrammes?\b",
    r"\b(?:artefact|aluminium|sulphur|storey|tyre|cheque|draught|mould|speciality"
    r"|jewellery|woollen|aeroplane|moustache|pyjamas|kerb|plough|gaol)s?\b",
    r"\bgrey(?:scale|s|ish)?\b",
)


# The tokens the writing standard bans outright, and the British spellings it bans by pattern.
BANNED = (
    (
        r"\brather\b",
        r"\badd up\b",
        r"cost and not a defect",
        r"\b(is|was|are|were) an? [\w-]+ and not an? [\w-]+",
        r"(?m)(?:\A|(?<=[.!?] ))(?:(?:An?|The) )?[\w-]+, not (?:(?:an?|the) )?[\w-]+\.(?:\s|\Z)",
        r"\b(name|spelling|token|type|structure|constraint)s?\s+(says|say|signals|signal|encodes|encode|"
        r"conveys|convey|announces|announce|advertises|advertise|makes clear|make clear)\b",
        r"\bso an?\b",
        r",\s+so\s+(?!that\b|far\b)",
        r"\bspelling\b",
        r"load-bearing",
    )
    + LOCALE
    + (
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
        r"\bis what (separates|keeps|tells|puts|says|makes|supplies|gives|decides|holds|stops|lets"
        r"|carries|costs|reads|buys|pays|spends|earns|wins|prices|slots|books)\b",
        r"\b(is|was|are|were) an? [\w-]+ and never an? [\w-]+",
        r"\band nothing more\b",
        r"\band no more\b",
        r"\bthe one (thing|place|case|word|reason|table|file|grain|repair|mistake|addition|column)\b",
        r"\bthe whole of (the|what|it)\b",
        r"\bis precisely (what|why|the)\b",
        r"\b(what|that) matters (is|here|most)\b",
        r"\bdelve",
        r"\btapestry\b",
        r"\brealm\b",
        r"\bmyriad\b",
        r"\bplethora\b",
        r"\bseamless",
        r"\bgame.?chang",
        r"\bcutting.edge\b",
        r"\bstate.of.the.art\b",
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
        r"\bit (is|'s) (important|worth|useful|helpful) (to note|noting|to remember|to mention|mentioning)\b",
        r"\bit should be noted\b",
        r"\b(furthermore|moreover|additionally)\b",
        r"\b(notably|interestingly|importantly|crucially|remarkably)\b",
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
        r"\bnot (just|only) .{1,40}\bbut (also )?\b",
        r"\bmore than just\b",
        r"\bit'?s not (just )?about\b",
        r"\b(remarkable|noteworthy|impressive|exceptional|extraordinary|outstanding)\b",
        r"\b(stellar|superb|phenomenal|tremendous|immense|enormous|staggering)\b",
        r"\b(countless|endless|limitless|boundless|unmatched|unrivall?ed)\b",
        r"\b(premier|foremost|quintessential|iconic|legendary|timeless)\b",
        r"\b(far.reaching|wide.ranging|all.encompassing|overarching)\b",
        r"\b(indispensable|paramount)\b",
        r"\b(sophisticated|layered|expansive|exhaustive)\b",
        r"\b(stunning|striking|breathtaking|awe.inspiring|mesmeri[sz]ing|dazzling)\b",
        r"\b(intuitive|elegant|sleek|polished|frictionless)\b",
        r"\b(rigorous|painstaking|diligent|thorough)\b",
        r"\b(innovative|disruptive|trailblazing|visionary)\b",
        r"\b(scalable|versatile)\b",
        r"\b(uncover|unveil|illuminate|unearth|unravel|demystify)",
        r"\b(enhance|augment)\b",
        r"\b(redefine|reimagine|reinvent)(s|ed|ing)?\b",
        r"\b(traverse|venture|spotlight|champion|nurture)\b",
        r"\btap into\b",
        r"\bbridge the gap\b",
        r"\b(open the door|set the stage|lay the foundation)\b",
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
        r"\ba (wide array|host|multitude|spectrum|plethora) of\b",
        r"\ban array of\b",
        r"\bthe (intersection|convergence) of\b",
        r"\b(having said that|with that said)\b",
        r"\bin light of\b",
        r"\bas such,",
        r"\b(consequently|nevertheless|nonetheless|conversely)\b",
        r"\bindeed,",
        r"\bof note,",
        r"\b(it is here that|this is where)\b",
        r"\benter (the|a) \w+\.",
        r"\bkey takeaways\b",
        r"\btl;?dr\b",
        r"\bpros and cons\b",
        r"\bin this (article|post|guide|section, we)\b",
        r"\bwe'?ll cover\b",
        r"\bby the end of this\b",
        r"\bwithout further ado\b",
        r"\bstay tuned\b",
        r"\b(one might argue|some might say|it could be argued|it bears mentioning)\b",
        r"\bas a language model\b",
        r"\bi (don'?t|do not) have (the ability|access|personal)\b",
        r"\bmy training data\b",
        r"\b(i apologi[sz]e|my apologies|sorry for the)\b",
        r"\bthat is (what|why|the (difference|point|whole|answer|test|reason|rule|shape|cost))\b",
        r"\bwhich is (what|why|how|the (difference|point|whole|answer|reason|rule))\b",
        r"\band that is (what|why|the (difference|point|whole|answer|test|reason|rule|shape|cost))\b",
        r"\b(checking|reading|running|measuring|saying) [a-z]+ is not [a-z]+ing\b",
        r"\bis not an? (accusation|argument|claim|answer|excuse|guess|estimate)\b",
        r"\bis not (a pass|passing|failing)\b",
        r"\ba run that (finishes|reads|reports|says|passes|fails|completes|knows|decides)\b",
        r"\b(the (file|tool|check|hook|run|number|count|table)) (says|answers|knows|decides)\b",
        r"\bthe ordinary (case|answer)\b",
        r"\bnothing else here\b",
        r"\bnothing here is (new|magic|special|clever|hidden|secret|surprising)\b",
        r"\b(is|are|was|were) (the least|what) (they|we|he|she|you|somebody) (are |is |)?(owed|deserve)",
        r"\b(the least|more) (they|we|you) (deserve|are owed)\b",
        r"\bwe owe (them|him|her|you|it)\b",
        r"\bentitled to (make|take|say|claim)\b",
        r"\bthe more valuable\b",
        r"\bthe (smallest|least) part of what\b",
        r"\bworth more than (the|their|his|her|any) \w+ (itself|themselves)\b",
        r"\b(something|anything) [a-z]+ed, never (something|anything)\b",
        r"\bnever something (suffered|taken|lost|given)\b",
        r"\bis what makes it (beautiful|worth|matter|special|right)\b",
        r"\bthat is the (beauty|tragedy|point) of\b",
        r"\ba person is not a\b",
        r"\b(it bears remembering|let us remember|we must remember|never forget)\b",
        r"\bwith the respect (it|they|that) deserve",
        r"\b(honou?r|honou?ring) (the|their|his|her) (memory|words|wishes|legacy)\b",
        r"\bthe right thing to do\b",
        r",\s*as it should be\b",
        r"\bis the kind nobody\b",
        r"\bnobody (looks at twice|reads twice|rechecks|checks twice)\b",
        r"\band they could not have\b",
        r"\bwhich is the whole\b",
        r"\bwould (prove|buy) nothing\b",
        r"\bthe (reproducible|checkable|measurable|honest|valuable) thing\b",
        r"\bagainst how (somebody|someone|anybody|people)\b",
        r"\bin nearly every (respect|way|case)\b",
        r"\bdoes not put a (reader|person|user) on the path\b",
        r"\ba (rule|check|gate|test) added here\b",
        r"\b(is|was|are|were) the [\w-]+ and not the [\w-]+",
        r"\bwhat is \w+ is\b",
        r"\bit would be a (worse|better) [\w-]+ to\b",
        r"\bbecause of what \w+ (does|did|is|was)\b",
        r"\band it is one\b",
        r"\band none is (wanted|claimed|needed|asked|offered|sought)\b",
        r"\bon nothing else\b",
        r"\bcan only show (that|whether)\b",
        r"\b(further|additional|more) (research|work|study|studies|investigation|analysis) (is|are) needed\b",
        r"\bit is worth (emphasi[sz]ing|stressing|highlighting)\b",
        r"\bone-size-fits-all\b",
        r"(?m)^\s*Ultimately,",
        r"\bthe foundation (up)?on which\b",
        r"\bpush(?:ing|es|ed)? the boundaries\b",
        r"\bwill inevitably\b",
        r"\bdeceptively simple\b",
        r"\bstay(?:ing)? ahead of the curve\b",
        r"\bhas never been more important\b",
        r"\bis (?:the|an?) authority for\b",
        r"\bit then reads as\b",
        r"\bare settled on page\b",
        r"\b(?:table|document|page|file|row) first had no\b",
        r"\bhas no call and no text:",
        r"\bthe slot stays empty\b",
        r"\bwere read off page\b",
        r"\bread by hand with no reader\b",
        r"\bthe record slot is empty\b",
        r"\bis named as having\b",
        r"\bnobody wrote an? \w+ for this one\b",
        r"\b(?:paper|page|file|table|document)'s own text\b",
        r"\bthe oracle is checked against\b",
        r"\bneither (?:is|settles|decides|says) what\b",
        r"\bis (?:not )?the authority for what\b",
        r"\bonly mark dropped\b",
        r"\bthe only place a \w+ was dropped\b",
        r"\bhas no call and no text\b",
        r"\bglottal tick\b",
        r"\bwith a tick added\b",
        r"\bat that magnification\b",
        r"\bwho column empty\b",
        r"\bhis name does not go in it\b",
        r"\bmade quietly\b",
        r"\bif it were made quietly\b",
        r"\bnothing in the \w+ pipeline depends\b",
        r"\bnothing downstream depends\b",
        r"\bits SHA-256 sits in\b",
        r"\b(?:hash|digest|checksum) sits in\b",
        r"\b(?:sound|text|word) representation reads\b",
        r"\bthe representation reads\b",
        r"(?m)^This one does not read\b",
        r"\bno (?:text|other) tool calls it\b",
        r"\band no other tool does\b",
        r"\bno other \w+ does\b",
        r"\blives in the closed\b",
        r"\bit lives in\b",
        r"\band is run from there\b",
        r"\breads the recordings\b",
        r"(?m)^A \w+ therefore\b",
        r"\bfor that shape and reports\b",
        r"\ba claim that something here is new\b",
        r"\bnew, first,? or absent\b",
        r"\bcannot settle that kind of claim\b",
        r"\bfrom inside itself\b",
        r"\bno reference beside it\b",
        r"\bthe reading has not been done\b",
        r"\bit reports and never decides\b",
        r"\breports and never\b",
        r"\bare mixed at all\b",
        r"\b(?:is|are|was|were) \w+ at all\b",
        r"\bthe slot (?:holds|carries|gives|takes|decides)\b",
        r"\ba copy that transports\b",
        r"\btransports a \w+ without\b",
        r"\band is recorded\b",
        r"\bunder what it cost\b",
        r"\bis unconfirmed and is recorded\b",
        r"\bunconfirmed and written down\b",
        r"\bthe candidate mechanism\b",
        r"\brecorded as a candidate\b",
        r"\binherits that\b",
        r"\brecorded here inherits\b",
        r"\bevery one of them \w+ and none of them\b",
        r"\bnone of them (?!is\b|was\b|has\b|does\b)\w+s\b",
        r"\ba measured cost\b",
    )
)

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

    This answers what a pattern LOOKS like. tier_of answers what authority it carries, and the two
    disagree on purpose: see the note above AUTHORITY.
    """
    if pattern in LOCALE:
        return "alphabet"
    if " " in pattern:
        return "phrase"
    return "word"


AUTHORITY = {
    r"\brather\b": "code-documentation:110, code-comments:200",
    r"\bso an?\b": "code-documentation:110, code-comments:200",
    r",\s+so\s+(?!that\b|far\b)": "code-documentation:112",
    r"\bspelling\b": "code-comments:200, comments only",
    r"\badd up\b": "code-documentation:110",
    r"\bthe one that matters\b": "code-documentation:116",
    r"\bis the one\b": "code-documentation:116",
    r"\bwhich is (why|what|the)\b": "code-documentation:117, code-comments:206",
    r"\band nothing else\b": "code-documentation:118, code-comments:207",
    r"\bthat is the whole\b": "code-documentation:119",
    r"\bis the whole (of|rule|point|thing|question|claim|job|story)\b": "code-documentation:119",
    r"\bthe whole (point|question|claim|rule|job|story) (is|was)\b": "code-documentation:119",
    r"\bwhat survives\b": "code-documentation:120",
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
    r"cost and not a defect": "code-documentation:146",
    r"\b(is|was|are|were) an? [\w-]+ and not an? [\w-]+": "code-documentation:146",
    r"\b(is|was|are|were) the [\w-]+ and not the [\w-]+": "code-documentation:146",
    r"(?m)(?:\A|(?<=[.!?] ))(?:(?:An?|The) )?[\w-]+, not (?:(?:an?|the) )?[\w-]+\.(?:\s|\Z)": "code-documentation:146",
    r"\bhas no call and no text:": "code-documentation:146",
    r"\b(name|spelling|token|type|structure|constraint)s?\s+(says|say|signals|signal|encodes|encode|"
    r"conveys|convey|announces|announce|advertises|advertise|makes clear|make clear)\b": "code-documentation:147, code-comments:156",
    r"load-bearing": "code-documentation:148",
    r"\blet['’]s\b": "code-documentation:148, code-comments:155",
    r"\bdiv(e|es|ing) (into|in|deeper)\b": "code-documentation:148, code-comments:155",
    r"\b(certainly|absolutely|of course)[!,]": "code-documentation:148, code-comments:155",
    r"\bit (is|'s) (important|worth|useful|helpful) (to note|noting|to remember|to mention|mentioning)\b": "code-documentation:148, code-comments:155",
    r"\bas an ai\b": "code-documentation:141",
    r"\bas a language model\b": "code-documentation:141",
    r"\bmy training data\b": "code-documentation:141",
    r"\b(i apologi[sz]e|my apologies|sorry for the)\b": "code-documentation:141",
    r"\bwhich is (what|why|how|the (difference|point|whole|answer|reason|rule))\b": "code-comments:206",
}


_ORPHANS = tuple(one for one in AUTHORITY if one not in BANNED)
if _ORPHANS:
    raise SystemExit(
        "docs_check: AUTHORITY names %d pattern(s) that are not in BANNED. A tier "
        "selector matching nothing reports clean forever.\n  %s"
        % (len(_ORPHANS), "\n  ".join(_ORPHANS))
    )


COMMENT_ONLY = frozenset((r"\bspelling\b",))


def tier_of(pattern):
    """A for a named-construction ban, B for frequency-scored vocabulary, alphabet for a spelling.

    Read AUTHORITY above for why this is not stage_of with different words.
    """
    if pattern in LOCALE:
        return "alphabet"
    return "A" if pattern in AUTHORITY else "B"


EM_DASH = "—"

QUOTED = (
    re.compile(r"neighbouring languages", re.IGNORECASE),
    re.compile(r"salish and neighbouring", re.IGNORECASE),
)

NAMED_SPAN = re.compile(r"`[^`\n]{1,300}`")
NAMED_IN_MARKDOWN = (
    re.compile(r"(?<!\*)\*[^*\n|]{1,300}\*(?!\*)"),
    re.compile(r"[\"“][^\"“”\n]{1,600}[\"”]"),
)

BUILD_SUFFIXES = (".sh", ".ps1", ".cmake", ".yml", ".yaml")


BUILD_NAMES = ("CMakeLists.txt", "Makefile", "GNUmakefile", "Dockerfile")


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


class Ledger(object):

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

_VERBATIM_CEILING = 24
_VERBATIM_CACHE = {}


def verbatim_root(path):

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


MANIFEST_NAMES = ("MANIFEST.tsv", "AUDIO_MANIFEST.tsv")
SIGNATURE_SUFFIX = ".asc"

_MANIFEST_CEILING = 24
_MANIFEST_DIRS = {}
_MANIFEST_INDEX = {}


def manifest_home(start):

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


GENERATED_OPEN = re.compile(r"<!--\s*BEGIN GENERATED\b\s*(?P<label>[^>]*?)\s*-->")
GENERATED_CLOSE = re.compile(r"<!--\s*END GENERATED\b")
GENERATED_BY = re.compile(r"\(([^)]+)\)\s*$")


def generated_regions(lines):

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


BRITISH_SUBJECT = (
    re.compile(
        r"\b(?:british|american|canadian|commonwealth|oxford)\s+"
        r"(?:english|spelling|spellings|convention|conventions|usage|variant|variants"
        r"|orthograph\w*|dictionar\w*)",
        re.IGNORECASE,
    ),
    re.compile(r"\ben[-_]GB\b"),
)

NAMED_STANDARD = re.compile(
    r"\b(?:RFC|STD|BCP|IEEE|ISO|IEC|ANSI|FIPS|NIST(?:\s+SP)?)\s*\d", re.IGNORECASE
)

RFC_2119 = re.compile(
    r"\b(?:MUST NOT|MUST|SHALL NOT|SHALL|SHOULD NOT|SHOULD|NOT RECOMMENDED|RECOMMENDED"
    r"|REQUIRED|MAY|OPTIONAL)\b"
)


CONTEXT_REASON = (
    "the subject of the passage is a writing convention, and a passage about one has "
    "to be able to write the word it is about"
)


def context_exempt(text):

    if any(one.search(text) for one in BRITISH_SUBJECT):
        return frozenset(("alphabet",))
    return frozenset()


FIX_TIERS = frozenset(("alphabet",))


def fix_refusal(path, tier, at=None, regions=None, line=""):

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


REPOSITORY = os.path.dirname(os.path.abspath(__file__))

while (REPOSITORY != os.path.dirname(REPOSITORY)) and not os.path.isdir(
    os.path.join(REPOSITORY, "src", "engine")
):
    REPOSITORY = os.path.dirname(REPOSITORY)

DEFAULT_ROOTS = tuple(
    os.path.join(REPOSITORY, one)
    for one in ("docs", "src", "examples", "maint", "theory", "theory_bucket")
)

for one in DEFAULT_ROOTS:
    if not os.path.isdir(one):
        raise SystemExit(
            "docs_check: %s is listed as a prose root and does not exist. A missing "
            "root reads as zero findings and exits 0, which passes every commit." % one
        )


PRIVATE_NAMES = ("salishan_corpus", "anchor_sift_citations")

PRIVATE_OVERRIDES = {
    "salishan_corpus": "ANCHOR_SIFT_PRIVATE",
    "anchor_sift_citations": "ANCHOR_SIFT_CITATIONS",
}

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

    common = git_say(REPOSITORY, ("rev-parse", "--git-common-dir"))
    if not common:
        return REPOSITORY
    if not os.path.isabs(common):
        common = os.path.join(REPOSITORY, common)
    base = os.path.dirname(os.path.abspath(common))
    return base if os.path.isdir(base) else REPOSITORY


def private_survey():

    base = main_checkout()
    owned = os.path.dirname(os.path.dirname(base))

    held = []
    absent = []
    for one in PRIVATE_NAMES:
        named = os.environ.get(PRIVATE_OVERRIDES[one])

        tried = (
            [named]
            if named
            else [
                # Where they live after the move into owned/{public,private}.
                os.path.join(owned, "private", one),
                # The layout before it, kept, an unreorganized checkout still works.
                os.path.join(os.path.dirname(base), "private_repos", one),
            ]
        )

        found = next((where for where in tried if where and os.path.isdir(where)), None)
        if found:
            held.append(found)
        else:
            absent.append((one, tuple(where for where in tried if where)))

    return tuple(held), tuple(absent)


def private_roots():
    """The closed repositories that are present, for adding to the roots being scanned."""
    return private_survey()[0]


_REF_CACHE = {}


def tree_ref(path):

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

DOXYGEN_TARGET = re.compile(r"^[@\\](ref|subpage|page|link|anchor|cite|see|copydoc)\b")


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


MARKER = re.compile(r"^\s*(#+|//+|\*+/?|/\*+)\s?")


def runs(lines):

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


PASSAGE = re.compile(r"[\"“][^\"“”]{16,600}[\"”]")


def banned_hits(lines, quotations=False, comments=False, path=None, ledger=None):

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


CORPUS = "the 759,815-word reference papers"


def banned_tokens(
    lines, quotations=False, comments=False, path=None, ledger=None, regions=None
):

    found = []
    for at, pattern, token in banned_hits(lines, quotations, comments, path, ledger):
        rate = HUMAN_RATE.get(pattern, 0.0)
        shape = stage_of(pattern)
        tier = tier_of(pattern)
        said = " ".join(token.split())
        if tier == "A":
            note = "tier A %s %r, banned at %s" % (shape, said, AUTHORITY[pattern])
        elif tier == "alphabet":
            note = "spelling %r, American convention is the house rule" % said
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


MARKDOWN_RULE = re.compile(r"^\s*-{3,}\s*$")
MARKDOWN_BOLD = re.compile(r"\*\*(?=\S)[^*]*\S\*\*")
MARKDOWN_ITALIC = re.compile(r"(?<![A-Za-z0-9])\\_(?=[A-Za-z])[^\\]*\\_(?![A-Za-z0-9])")

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


def walk_markdown(roots, ledger=None):

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

    mine = os.path.abspath(__file__)
    my_dir = os.path.dirname(mine)
    kept = []
    for one in found:
        if os.path.abspath(one) == mine:
            continue

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
        kept.append(one)
    return kept


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


SENTENCE_END = (".", "?", "!", ":", ";", '"', "'", ")", "`")
CONTINUATION = re.compile(r"^[a-z]")


def near_marker(lines, at, step):

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

    kept = []
    for line in lines:
        held = line

        held = re.sub(r"(?<!\\)%.*$", "", held)

        held = re.sub(r"\$\$.*?\$\$", " ", held)
        held = re.sub(r"(?<!\\)\$.*?(?<!\\)\$", " ", held)
        held = re.sub(r"\\\[.*?\\\]", " ", held)
        held = re.sub(r"\\\(.*?\\\)", " ", held)

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


STRING_SPAN = re.compile(r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'")


def hash_tail(line):

    masked = STRING_SPAN.sub(lambda hit: " " * len(hit.group(0)), line)
    for at, character in enumerate(masked):
        if character != "#":
            continue
        if at == 0 or masked[at - 1].isspace():
            return line[at:]
    return ""


def comment_prose(lines):

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

            cut = line.index("//")
            kept.append(line[cut:])
        else:
            kept.append("")
    return legal_blank(quieted(kept), path, ledger)


def main():

    strict = "--strict" in sys.argv

    planning = "--fix" in sys.argv
    where_given = [one for one in sys.argv[1:] if not one.startswith("-")]

    roots = []
    for one in where_given or (DEFAULT_ROOTS + private_roots()):
        if os.path.exists(one):
            roots.append(one)
            continue
        beside = os.path.join(REPOSITORY, one)
        roots.append(beside if os.path.exists(beside) else one)

    print(
        "  roots configured: %d, %s"
        % (
            len(roots),
            (
                "given on the command line"
                if where_given
                else "this tool's own defaults plus every closed repository found"
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

        regions = {}
        if path.endswith(".md"):
            regions, unclosed = generated_regions(lines)
            for at, complaint in unclosed:
                print("  BREAK %s:%d: %s" % (path.replace("\\", "/"), at, complaint))
                breaking += 1

        structural = em_dashes(said)
        if path.endswith(".md"):
            structural += empty_tables(lines) + dead_links(path, lines)

        if path.endswith(".tex"):
            structural += markdown_leftovers(said)

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

    print("  %d file(s) checked, %d breaking, %d prose" % (checked, breaking, prose))

    if not where_given:
        held, absent = private_survey()
        print("  private roots scanned: %d of %d" % (len(held), len(PRIVATE_NAMES)))
        for one in held:
            print("    %s" % one.replace("\\", "/"))
        for name, tried in absent:
            print("    %s NOT FOUND, looked at:" % name)
            for where in tried:
                print("      %s" % where.replace("\\", "/"))

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

    print(
        "  this run read %d file(s) under %d root(s) and nothing outside them. Whether a hook is "
        "installed and which roots a repository declares are that repository's decisions, not "
        "this tool's: a gate that is correct, installed nowhere, and scoped to two paths still "
        "catches nothing." % (checked, len(roots))
    )

    if checked == 0:
        print("  no files were read. Nothing was checked. Nothing passed.")
        for one in roots:
            print(
                "    %s%s" % (one, "" if os.path.exists(one) else "   does not exist")
            )
        return 2

    if breaking or (strict and prose):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
