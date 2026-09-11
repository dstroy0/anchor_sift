#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# One entry per paper: who spoke it, what it is written with, and which grains its extraction has.
#
#   Usage:  from paper_config import PAPERS, marks_for, repair_for, speakers_for
#
# Three files used to carry parts of this and they drifted. hand_extraction/papers.py held the
# alphabets, coverage_check.py held the same alphabets written out a second time as literals, and
# refs.md held the list of speakers by hand. A paper added to one and not the others was a paper the
# coverage check read with the wrong alphabet and reported as fully covered.
#
# WHO SPOKE IT COMES FIRST
#
# These languages belong to the people who speak them and none of this exists without them. The
# speakers are named here because naming them is a fact about the paper that a person establishes by
# reading it, the same way the alphabet is, and because a name is not something to derive from a
# column with a heuristic. Where a paper cites a published dictionary and never says who spoke, the
# entry is empty and the index says so. That is the honest answer, and the linguist does not go in
# the slot.
#
# WHAT AN ALPHABET IS FOR
#
# A token holding one of these characters is the language. Most of these papers share ʔ, ə and ɬ, and
# each entry is the shared space plus what that paper adds. A per-paper set is written as SHARED plus
# its additions and never as its own alphabet, because a checker that knows one paper's letters reads
# every other paper as empty and then reports nothing missing from it.
#
# WHAT A GRAIN IS
#
# A named kind of damage the extraction did, out of the five refs.md measures. A paper declares the
# ones it has and no others. The evidence for each declaration is the comment above it, because
# the count behind a decision is a fact about that paper.

from glyph_names import decoded as glyph_names_decoded
from mary_george_repair import repaired as mary_george_repaired
from repairs import composed, corrected, one_mark, sequence
from salish_marking import TEXT_SPACE
from whitespace import any_of, closed_after_bracket, closed_after_marks, stacked_but_not

# The space every paper here is represented in. salish_marking holds the one definition.
SHARED = TEXT_SPACE

# The stress accents, which the general space rule leaves alone. A word can end in a stressed vowel,
# and closing the space after one welds it to the word after it: LaFontaine and Janzen has
# ntes neʔé e sqyéytn, and closing there gives neʔée, which the language does not have.
STRESS = "́̀"

# The stacked marks plus the accents, for a paper whose own layout makes closing after an accent
# safe. Both papers that take this print two spaces at a real boundary, which leaves a lone space
# after an acute as the inserted one every time.
STACKED_AND_STRESS = "̓̌́̀̕"

# The two ways a paper can write the ejective. Where one letter is written both ways in one paper,
# the two are one mark and normalizing is arithmetic.
COMMA_ABOVE = "̓"
COMMA_ABOVE_RIGHT = "̕"

# The grain nearly every paper carries: a lone space left after a stacked diacritic. Counts are in
# inserted_space.py, which is where this grain's evidence lives.
INSERTED_SPACE = closed_after_marks(stacked_but_not(STRESS))

# The same grain on a paper that also breaks at an accent.
INSERTED_SPACE_AT_ACCENTS = closed_after_marks(any_of(STACKED_AND_STRESS))


class Paper(object):
    """One paper: who spoke it, what it is written with, and what its extraction did to it.

    coverage is the repair the coverage check applies, named where it differs from the one the
    oracle check applies. Two papers differ today and neither difference was deliberate: they are
    what two hand-kept lists drifting apart looks like. Reconciling them changes what the coverage
    check reports, so it is a measurement to run and not an edit to make quietly.
    """

    def __init__(self, stem, oracle, record, language, speakers=(), marks=SHARED, repair=None,
                 coverage=None, note=""):
        self.stem = stem
        self.oracle = oracle
        self.record = record
        self.language = language
        self.speakers = tuple(speakers)
        self.marks = marks
        self.repair = repair
        self.coverage = coverage if (coverage is not None) else ()
        self.note = note


# Two speakers of two Lushootseed dialects, the only external dialect label in the archive
# and the one the border test is scored against.
LUSHOOTSEED_STRESS = SHARED + "ǰᶻθáíúàìù" + "̌́̀"

# The 1983 typescript's damaged orthography. Nothing in the shared set appears in it: the glottal
# stop is ? and the schwa is ~, J or G.
DAMAGED = "?~JG@V%]!"

# Lyon's two Okanagan papers, checked against a drafted page text written in the shared orthography.
# The wedge over x in x̌ast and the raised dot of ya·ʕt are the two the shared set does not carry.
OKANAGAN = SHARED + "̌·"

# The 1975 typescript, whose glottal stop is ? and which keeps the rest of the orthography.
HILBERT_HESS = "?ə" + "čšɬƛᶻʷ" + "̌̓"

# Robertson writes his Thompson and Shuswap in Americanist symbols and says so on page 30.
ROBERTSON = SHARED + "̣čš"

# Wolfe's forms are affixes, not words, so the set has to reach a suffix written in plain letters
# with one accent on it. The accents are given composed and combining both: NFC makes á one
# character while ə́ has no composed form and keeps its acute standing alone.
WOLFE = SHARED + "ʸːɛεέŋᶿθǰčšĺ" + "áéíóú" + "̌́"

# Nater's voiceless words. The apostrophe is deliberately absent: it is his ejective mark and also
# the closing quote of every gloss, and carrying it makes every English gloss a word of the language.
NATER_VOICELESS = SHARED + "̩̌"

# Lyon's inchoatives, where the root sign is the only thing making half the roots visible at all.
LYON_INCH = SHARED + "̌́" + "áíúé" + "ɣš√"

# Kim writes the lateral fricative ɫ, a third character for it, and marks a rule-derived glottal
# stop ˀ against phonemic ʔ.
KIM = SHARED + "ɫˀščóéɔ" + "̦́ʹ"

# Footnote 9 cites four Moses-Columbian forms and the extraction damages each of them twice: it
# inserts a space inside the onset and it repeats the combining mark. x̦̦ carries two commas below
# where the page prints one, and ƛ̓̓ two commas above.
#
# That doubling is its own kind and Robertson has it too, where page 1's epigraph prints one ɬ and
# one ʔ and the text holds four of each. It is not decidable from the text, because a language may
# genuinely stack two marks, so these four were read off the page and are listed one at a time.
KIM_DOUBLED = (
    ("[p ʰtíx̦̦ʷ]", "[pʰtíx̦ʷ]"),
    ("[p ətíx̦̦ʷ]", "[pətíx̦ʷ]"),
    ("[x ƛ̓̓út]", "[xƛ̓út]"),
    ("[xəƛ̓̓út]", "[xəƛ̓út]"),
)

# Nater's etymological database, which writes the schwa two ways NFC does not unify: ǝ U+01DD 183
# times and ə U+0259 52 times.
NATER_ETYM = SHARED + "ǝ√" + "áíúà" + "ᴗɢʁʒščɣλˑ"

# Hall and colleagues on the control directive. The dot below is its rounded uvular; ǰ and θ are
# here to make the Comox forms visible so the who column can keep them out of the target stream.
HALL_CTR = SHARED + "̣" + "áéíóúè" + "́" + "ǰθ"

# Davis and Mellesmoen on St'át'imcets reduplication. The caron is its x̌, the dot below its
# retracted vowels, and √ opens 27 root citations carrying nothing else a check could see.
DAVIS_MELLESMOEN = SHARED + "̣̌́̀" + "áíú" + "ɣ√ǰθ"

# The marks this paper's extraction dropped outright, put back. Every one of these is a word whose
# combining mark is gone from the text while the space the typesetter made room for stays, and no
# rule reaches them: this paper writes l followed by a space for both l̓ and a plain l at a real
# boundary, and l=ta=q̓íl q-s=a is the second of those.
#
# Provenance is one of two things and there is no third. Four pairs were read by symbol_sift.py,
# which finds a restoration the paper itself writes elsewhere and reports the rate a random mark
# reaches it: xʷəlp, qʷal út twice, and Secwep emctsín, at scores of 160.9 and 75.9 against a chance
# rate of 0.136. The rest were read off rendered pages, and the page is named on each line.
#
# Order matters. The longer contexts come first, because qʷəl -qʷal út has to be taken before
# qʷal út or the second fires inside the first and leaves it half repaired.
DAVIS_MELLESMOEN_DROPPED = (
    # Read by symbol_sift from the paper's own second printing of the word.
    ("xʷəlp-í<p>l əx", "xʷəlp-í<p>l̓əx"),
    ("qʷə-qʷəl -qʷal út", "qʷə-qʷəl̓-qʷal̓út"),
    ("qʷəl -qʷə-qʷal út", "qʷəl̓-qʷə-qʷal̓út"),
    ("qʷəl -qʷal út", "qʷəl̓-qʷal̓út"),
    ("qʷə-qʷal út", "qʷə-qʷal̓út"),
    ("qʷal ə́<l >t", "qʷal̓ə́<l̓>t"),
    ("qʷal út", "qʷal̓út"),
    ("Secwep emctsín", "Secwepemctsín"),
    ("S kwxwú7mesh", "Skwxwú7mesh"),
    # Page 13.
    ("ti  ́pə  ḷ", "típəḷ"),
    ("tə́<t>pə  l", "tə́<t>pəḷ"),
    ("k̓ə  ́ḷən", "k̓ə́ḷən"),
    ("k̓ə̣́́<k̓>l  ən", "k̓ə́<k̓>ḷən"),
    # Page 14.
    ("s-k̓ə  ḷ-ə̣́́<l ̣́>c̓aʔ", "s-k̓əḷ-ə́<ḷ̓>c̓aʔ"),
    ("s-k̓ə  ḷ-íc̓aʔ", "s-k̓əḷ-íc̓aʔ"),
    ("qḷ-ə ̣́́<l ̣́̓>kaʔ", "qḷ-ə́<ḷ̓>kaʔ"),
    ("qḷ-a  ́kaʔ", "qḷ-ákaʔ"),
    # Page 15.
    ("ṣtə ̣́́<t>əw", "ṣtə́<t>əw"),
    ("lapḷə̣́́<l ̣́>s", "lapḷə́<ḷ̓>s"),
    ("lapḷa  ́s", "lapḷás"),
    ("kḷə̣́́<l ̣́>si", "kḷə́<ḷ̓>si"),
    ("kḷi  ́si", "kḷísi"),
    ("ka-mə́<m>l -a", "ka-mə́<m>l̓-a"),
    ("ta=ṣtu ́h=a", "ta=ṣtụ́h=a"),
    ("ta=ṣtə ́tw̓=a", "ta=ṣtə́tw̓=a"),
    ("ta=ṣtə ́t(h)=a", "ta=ṣtə́t(h)=a"),
    # Page 18.
    ("q̓ʷə<q̓ʷ>l -ən-ás", "q̓ʷə<q̓ʷ>l̓-ən-ás"),
    ("kʷu=ḷə ̣́́<ḷ>ạy̓s", "kʷu=ḷə́<ḷ>ạy̓s"),
    ("n-ká<k>əl -xal", "n-ká<k>əl̓-xal"),
    # Page 20. mil carries its following quote so the pair cannot fire inside another word.
    ("q̓í<q̓>ɬil", "q̓í<q̓>ɬil̓"),
    ("ʕí<ʕ >ƛ̓-əm", "ʕí<ʕ̓>ƛ̓-əm"),
    ("ƛ̓a ̣́́<ƛ̓>l  -ən", "ƛ̓á<ƛ̓>ḷ-ən"),
    ("ƛ̓a  ́ḷ-ạn", "ƛ̓áḷ-ạn"),
    ("n-mí<m>l -ən", "n-mí<m>l̓-ən"),
    ("mil   ‘", "mil̓   ‘"),
    ("q̓əɬʔ-ál xən", "q̓əɬʔ-álxən"),
    ("la-líl təm", "la-líl̓təm"),
    # Pages 22 and 24, the double pluractionals.
    ("q̓əy-q̓ə́<q̓>əy-l əx", "q̓əy-q̓ə́<q̓>əy-l̓əx"),
    ("ɬəʕʷ-ɬʕʷ-í<ʕʷ>l əx", "ɬəʕʷ-ɬʕʷ-í<ʕʷ>l̓əx"),
    ("ɬəʕʷ-ɬʕʷí-<ʕʷ>l əx", "ɬəʕʷ-ɬʕʷí-<ʕʷ>l̓əx"),
    # Page 25, the neologisms.
    ("√ta  ́wən", "√táwən"),
    ("təw-tə̣́́<t>wən", "təw-tə́<t>wən"),
    ("pə ̣́y-pə ̣́́<p>y̓ət", "pə́y-pə́<p>y̓ət"),
    # Page 23, where the extraction breaks a lexical suffix off its own stem.
    ("ɬəʕʷ-í<ʕ>l əx", "ɬəʕʷ-í<ʕ>l̓əx"),
    ("k̓ʷs-á<s>l ic̓aʔ", "k̓ʷs-á<s>l̓ic̓aʔ"),
    ("cə́<c>l əkst", "cə́<c>l̓əkst"),
    ("məc-xə<x>əl =ɬkán", "məc-xə<x>əl̓=ɬkán"),
    ("pə mí-<m>l̓əx", "pəmí-<m>l̓əx"),
    ("pə m-ílx", "pəm-ílx"),
    ("l=ta=q̓íl q-s=a", "l=ta=q̓ílq-s=a"),
)

# Hess's Snohomish, read off the pages of the 1967 typescript. The glottal stop is ?, the uvular is
# x under a dot, and ŋ is there once, in the Straits cognate of the suffix the paper is about. Every
# character in this set was counted in the hand extraction before it was written here.
HESS_SNOHOMISH = "?ə" + "čšɬƛŋ" + "ʷ" + "áéíúàìù" + "̣̓́̀"

# Elmendorf's comparative vocabularies, thirteen languages in one paper. The uvular is again x under
# a dot, and this one adds the Americanist small capitals ɪ and ᴀ for lax vowels, θ, a raised y, and
# a raised dot for length. The apostrophe is in the set because Boas and Haeberlin's forms carry one
# inside the word, as in sča'u, and dropping it would split those forms in two.
ELMENDORF_COMPARATIVE = "?ə" + "čšɬƛθɪᴀ" + "ʷʸ" + "áäéíóú" + "̣̓́" + "·'"

# Hamp on Tillamook. This paper cites no words: what it sets out is four consonant inventories and
# two feature matrices, so its language content is segments and not forms.
#
# Reichard's chart is the one of the four that carries the plain lateral affricate as well as the
# glottalized, the other three carrying the glottalized alone. That is a fact about the charts and
# not about this set, because SHARED already holds ƛ; naming it here as an addition would be a
# character that changes nothing and a comment that reads as though it does.
#
# ɔ and ɨ are the two vowel colorings TT give for q and k. The ɨ is a reading taken from its
# pairing with ɔ and not from the glyph, which is a typed i carrying a raised mark, and the table
# says so on a row of its own and does not promote it here.
HAMP_TILLAMOOK = SHARED + "?" + "̣" + "ɔɨæʌɪ"

# Kinkade on Columbian deictics, with Kalispel, Coeur d'Alene and three Colville forms beside it.
# Read off the oracle's own form column and not composed by hand: acute, grave, caron, dot below, æ
# and small capital ɪ are what those rows hold past SHARED.
#
# The grave is a live contrast in this paper and not decoration. Three -ákst pairs print an acute in
# the base and a grave on that same vowel in the derived form, scxaʔánəm against scxaʔànəmákst being
# the clearest. A set without U+0300 reads half of that alternation as unmarked.
#
# æ and ɪ belong to the two authors quoted, not to Kinkade: æ is Reichard's throughout her Coeur
# d'Alene forms, and ɪ is the reduplicant vowel of cɪciʔ and cɪciy̓æ, which the table records as an
# assigned reading of a short curled stroke and not as a glyph anyone identified.
KINKADE_COLUMBIAN = SHARED + "̣" + "́̀̌" + "æɪ"

# Givens and Hall on Bev Phillips's telling of The Moon and the Birchbark Canoe. Read off the
# oracle's own form column: past SHARED these rows hold the acute and the dot below, and nothing
# else. No grave and no caron anywhere in the paper.
#
# Its lateral is U+026C, which is what the file encodes and what every other Nɬeʔkepmxcín row in the
# corpus uses. The embedded font draws that character with a bar through the stem. A reader working
# from page renders sees U+0142 and writes it. The table's symbol note records the trap.
#
# The paper's own footnote 1 names the orthography: a form of the North American Phonetic Alphabet
# employed by Thompson and Thompson 1992 and 1996. That is a paper stating what its characters are,
# which is the strongest provenance available for a marks set here.
GIVENS_HALL_NLEKEPMXCIN = SHARED + "́" + "̣"

# This paper's extraction flattens its own labialization in 24 places and gets it right in 94. The
# raised w is U+02B7 ninety four times and a plain full size w twenty four, for the same segment, in
# words the text layer also writes correctly elsewhere. The page is consistent and the extraction is
# not, so the hand extraction differing from it is the extraction's defect and not the reading's.
#
# Every site was enumerated and every one read off a page render before it was entered here, which
# is what corrected() asks of a pair. Seven patterns cover all twenty four:
#
#   xwúy̓   xʷúy̓ceʔs on page 2 lines 2, 6 and 14 and in the segmentation of examples 4, 11, 20, 24
#   xwʔít  xʷʔít on page 2 lines 3 and 5, example 5, example 9, example 18
#   cúkw   cúkʷsc on page 2 line 1 and cúkʷ-s-c in example 2
#   tox̣w   tox̣ʷtés on page 2 line 1, read again at 34x in example 3 where the dot below is visible
#   zxwé   szxʷépmx on page 2 line 4 and s-zxʷép-mx in example 7
#   tmixw  tmixʷíyxs on page 2 line 4 and e=tmixʷ-íyxs in example 7
#   pkw    npkʷə́ps on page 2 line 7 and s=n-pkʷ-ə́p=s in example 13
#
# Written as seven patterns and not as a rule mapping every Cw to Cʷ. The rule is the guess
# draft_page_text.py already makes and papers.py already warns about, that page kʷ and page wist both
# arrive as w and a draft labializes whichever consonant takes it. Here the sites are counted, so
# each pattern is evidence about one word. None of them is a rule about a letter.
GIVENS_HALL_FLATTENED = (
    ("xwúy̓", "xʷúy̓"),
    ("xwʔít", "xʷʔít"),
    ("cúkw", "cúkʷ"),
    ("tox̣w", "tox̣ʷ"),
    ("zxwé", "zxʷé"),
    ("tmixw", "tmixʷ"),
    ("pkw", "pkʷ"),
)

# Every paper, and whose language is in it.
#
# The speakers are named from the papers themselves. Where a paper cites a published dictionary and
# never says who spoke, the list is empty and the index prints that. A linguist's name never goes in
# the slot: they wrote the paper down, and the language is not theirs.
PAPERS = (
    Paper("Mellesmoen_Kye_ICSNL61",
          "Mellesmoen_Kye_ICSNL61.oracle.tsv",
          "MarthaLamont-AnnieJack_AComparativeAnalysisOfStressInNorthernAndSouthernLushootseed"
          "_MellesmoenKye_Salish_lushootseed_2026_mixed.txt",
          "Lushootseed",
          speakers=("Martha Lamont, Northern dialect", "Annie Jack, Southern dialect"),
          marks=LUSHOOTSEED_STRESS,
          repair=sequence(INSERTED_SPACE_AT_ACCENTS, closed_after_bracket(),
                          one_mark(COMMA_ABOVE_RIGHT, COMMA_ABOVE), composed()),
          coverage=("mellesmoen",),
          note="Both recorded by Leon Metcalf in the 1950s. The only paper here that labels "
               "every form by dialect, and the border test is scored against it."),
    Paper("1983_Hilbert",
          "1983_Hilbert.oracle.tsv",
          "SusieSampsonPeter-MarthaLaMont_PokingFunInLushootseed_Hilbert"
          "_Salish_lushootseed_1983_mixed.txt",
          "Lushootseed",
          speakers=("Susie Sampson Peter, Upper Skagit", "Martha LaMont, Tulalip-Skagit"),
          marks=DAMAGED,
          note="Vi taqʷšəblu Hilbert wrote the paper; the twenty-one examples were said by her "
               "aunt Susie Sampson Peter and by Martha LaMont, recorded by Leon Metcalf between "
               "1950 and 1958 and by Thom Hess in 1963. The record credited Hilbert as the "
               "speaker until the hand extraction found it."),
    Paper("Matthewson_Redan_ICSNL61",
          "Matthewson_Redan_ICSNL61.oracle.tsv",
          "Kweswapaw-LindaRedan_Cw7aozKati7Lati7KuNaxwit_MatthewsonRedan"
          "_Salish_statimcets_2026_mixed.txt",
          "St'át'imcets",
          speakers=("K̓weswapáw̓ (Linda Redan), Qayqáyten",
                    "Sam Mitchell, in van Eijk and Williams 1981"),
          repair=INSERTED_SPACE, coverage=("inserted spaces",),
          note="K̓weswapáw̓ told the story over Zoom on 31 October 2025, three minutes twenty-eight "
               "seconds, and the audio and video are held by her. Sam Mitchell is the speaker of "
               "the earlier text the paper cites."),
    Paper("AlexanderDavis_ICSNL61",
          "AlexanderDavis_ICSNL61.oracle.tsv",
          "Qwa7yanak-CarlAlexander_ITsicwasSQwa7yanakAku7GraveyardValley_AlexanderDavis"
          "_Salish_statimcets_2026_mixed.txt",
          "St'át'imcets",
          speakers=("Qwa7yán'ak (Carl Alexander), Nxwísten",),
          note="Recorded at Nxwísten on 7 July 2025, just over half an hour."),
    Paper("22-Nater-Bella-Coola-tale-10",
          "22-Nater-Bella-Coola-tale-10.oracle.tsv",
          "MargaretSiwallace_ABellaCoolaTale_Nater_Salish_nuxalk_2015_nomixed.txt",
          "Nuxalk",
          speakers=("Dr. Margaret Siwallace",),
          note="Recorded about 1975, published 2015."),
    Paper("ICSNL59_LaFontaine_Janzen_final",
          "ICSNL59_LaFontaine_Janzen_final.oracle.tsv",
          "wlwlmelst-MauriceMichell_FourStoriesByWlwlmelst_LaFontaineJanzen"
          "_Salish_nlekepmxcin_2024_mixed.txt",
          "nɬeʔkepmxcín",
          speakers=("wlwlmelst (Maurice Michell), Southern yutémkt dialect",),
          repair=INSERTED_SPACE, coverage=("inserted spaces",),
          note="He shares his four stories freely for people connecting with the language. They "
               "came from his mother nxwelinek and his grandmother ʔústko."),
    Paper("ICSNL59_Garcia_Hannon_Stacey_final",
          "ICSNL59_Garcia_Hannon_Stacey_final.oracle.tsv",
          "Kweltezetkwu-BerniceGarcia_ThreeGlossedNlekepmxcinNarratives_GarciaHannonStacey"
          "_Salish_nlekepmxcin_2024_mixed.txt",
          "nɬeʔkepmxcín",
          speakers=("Kʷəɬtəzétkʷu (Bernice Garcia), c̓əɬétkʷu (Coldwater)",),
          repair=INSERTED_SPACE, coverage=("inserted spaces",),
          note="She asks it be acknowledged she is a Kamloops Indian Residential School speaker "
               "re-learning her language."),
    Paper("ICSNL56_DavisJ_2_final-1",
          "ICSNL56_DavisJ_2_final-1.oracle.tsv",
          "MaryGeorge_MaryGeorgePersonalNarratives_JohnHamiltonDavis"
          "_Salish_ayajuthem_2021_mixed.txt",
          "Mainland Comox (ayajuthem)",
          speakers=("Mary George, Sliammon", "Noel George Harry", "Tommy Paul"),
          repair=mary_george_repaired, coverage=(),
          note="Recorded 1969 to 1980. The oracle check applies this paper's own repair and the "
               "coverage check applies none, which is one of the two drifts named above."),
    Paper("HallPhillipsICSNL60",
          "HallPhillipsICSNL60.oracle.tsv",
          "BevPhillips_WhenOldOneCreatedTheEarth_HallPhillips"
          "_Salish_nlekepmxcin_2025_nomixed.txt",
          "nɬeʔkepmxcín",
          speakers=("Bev Phillips, Lytton First Nation (ƛ̓q̓əmcín)",),
          repair=INSERTED_SPACE, coverage=("spaces",),
          note="Her own reading of the story is in build/audio, so it is an oracle for the "
               "extraction and not only a source. The coverage check applies a cruder space "
               "closer here than the oracle check does, the other drift named above."),
    Paper("19-Lyon_ICSNL50_final-78",
          "19-Lyon_ICSNL50_final-78.oracle.tsv",
          "GeorgeLezard-NellieGuitterez-AndrewMcGinnis_ThreeOkanaganStoriesAboutPriests_Lyon"
          "_Salish_nsyilxcen_2015_nomixed.txt",
          "Nsyilxcən",
          speakers=("George Lezard, Penticton Indian Reserve",
                    "Nellie Guitterez, Upper Nicola Indian Band",
                    "Kiláwnaʔ (Andrew McGinnis), Penticton Indian Reserve"),
          marks=OKANAGAN, coverage=("page", "columns"),
          note="George Lezard recorded 1966 by Randy Bouchard, transcribed by Larry Pierre 1970, "
               "updated by permission of Arnie Baptiste, his son. Nellie Guitterez recorded 1978 "
               "or 1979 by Yvonne Hébert, reprinted by permission of Lynne Jorgesen, her "
               "great-granddaughter."),
    Paper("2013_Lindley_Lyon",
          "2013_Lindley_Lyon.oracle.tsv",
          "LottieLindley_TwelveMoreUpperNicolaOkanaganNarratives_LindleyLyon"
          "_Salish_nsyilxcen_2013_nomixed.txt",
          "Nsyilxcən",
          speakers=("Lottie Lindley, Upper Nicola",),
          marks=OKANAGAN, coverage=("page", "columns")),
    Paper("1975_Hilbert_Hess",
          "1975_Hilbert_Hess.oracle.tsv",
          "ViHilbert-ThomHess_ANoteOnAeConstructionsInLushootseed_HilbertHess"
          "_Salish_lushootseed_1975_mixed.txt",
          "Lushootseed",
          marks=HILBERT_HESS,
          note="A 1975 typescript, scanned, and what is on disk is OCR of the scan. The paper "
               "names no speaker for its examples. The OCR carries none of the orthography: zero "
               "schwas, zero raised w, zero barred l, zero wedges, against 169, 77, 41 and 33 in "
               "the hand extraction. It writes taqWsablu for taqʷšəblu and slahal for sləhal. All "
               "200 direction-one disagreements filed against this paper come from that, and "
               "they are the source text and not the reader. It needs a drafted page text and a "
               "place in NOT_FAITHFUL, the way the two Lyon papers have, before the check against "
               "it means anything."),
    Paper("2012_Robertson",
          "2012_Robertson.oracle.tsv",
          "CharleyAlexisMayoos-WilliamCelestin_BCIndigenousPeoplesChinukPipaScript_Robertson"
          "_Salish_nlekepmxcin-secwepemctsin_2012_mixed.txt",
          "nɬeʔkepmxcín and Secwepemctsín",
          speakers=("Charley Alexis Mayoos", "William Celestin"),
          marks=ROBERTSON, repair=glyph_names_decoded,
          coverage=("glyph names", "line joins"),
          note="Their texts are written in Chinuk pipa. Texts 3 to 6 are Chinook Jargon, which "
               "is a pidgin and is not Salish, and the who column keeps those out."),
    Paper("WolfeICSNL60",
          "WolfeICSNL60.oracle.tsv",
          "unstated_LexicalSuffixesAndConnectivesInProtoCentralSalishAndBeyond_Wolfe"
          "_Salish_centralsalish_2025_mixed.txt",
          "eighteen Central Salish languages",
          marks=WOLFE, repair=INSERTED_SPACE, coverage=("inserted spaces",),
          note="Every form is cited from a published dictionary of one of eighteen languages, so "
               "there is nobody this corpus is of. The who column carries the language instead, "
               "and the reader writes a .pure.tsv keyed by it and no flat pure file."),
    Paper("ICSNL59_Nater_2_final",
          "ICSNL59_Nater_2_final.oracle.tsv",
          "unstated_VoicelessWordsInBellaCoolaFactVsFiction_Nater"
          "_Salish_nuxalk_2024_mixed.txt",
          "Nuxalk",
          marks=NATER_VOICELESS, repair=INSERTED_SPACE, coverage=("inserted spaces",),
          note="Nater's own records, from his 1990 dictionary and 1984 grammar. No speaker is "
               "named. Six entries and two tables are Heiltsuk, Oowekyala, Kwak̓wala and Haisla, "
               "which are North Wakashan and not Salish at all."),
    Paper("LyonICSNL60_Inch-2",
          "LyonICSNL60_Inch-2.oracle.tsv",
          "DelphineDerricksonArmstrong-DaveMichele_NsyilxcnInchoativesAndTheirDistributions"
          "AcrossRootTypes_Lyon_Salish_nsyilxcen_2025_mixed.txt",
          "Nsyilxcən",
          speakers=("ɬk̓mxnalqs (Delphine Derrickson-Armstrong), stq̓aʔtkʷɬniw̓t",
                    "c̓əskʕáknaʔ (Dave Michele), stq̓aʔtkʷɬniw̓t"),
          marks=LYON_INCH, repair=INSERTED_SPACE, coverage=("inserted spaces",),
          note="Elicited from both speakers. Most cells of its two tables are starred, which is "
               "a form the linguist built and the speakers rejected, and those are held out."),
    Paper("Kim_TwanaReduplication_final",
          "Kim_TwanaReduplication_final.oracle.tsv",
          "unstated_TheTruncatedReduplicationInTwana_Kim"
          "_Salish_twana_2017_mixed.txt",
          "Twana",
          marks=KIM,
          # Composition runs before the corrections for the reason it does everywhere: corrected()
          # composes its own patterns. A pattern meets composed text or it matches nothing.
          repair=sequence(INSERTED_SPACE, composed(), corrected(KIM_DOUBLED)),
          coverage=("inserted spaces",),
          note="Every Twana form is Drachman's, out of a 1969 dissertation the paper calls the "
               "only reliable reference in existence for this. No speaker is named. Footnote 9's "
               "four Moses-Columbian forms are the only place its extraction repeats a combining "
               "mark, and those are corrected from the page."),
    Paper("2013_Nater",
          "2013_Nater.oracle.tsv",
          "unstated_HowSalishIsBellaCoola_Nater"
          "_Salish_nuxalk_2013_mixed.txt",
          "Nuxalk",
          marks=NATER_ETYM, repair=INSERTED_SPACE, coverage=("inserted spaces",),
          note="1407 numbered entries out of Nater's own 1990 dictionary. No speaker is named."),
    Paper("Hall-et-al_-ICSNL_61-1",
          "Hall-et-al_-ICSNL_61-1.oracle.tsv",
          "unstated_CtrlAltDeleteTheControlDirectiveAndAssociatedTDeletionInNlekepmxcin"
          "_HallLuntzlaraMellesmoenReid_Salish_nlekepmxcin_2026_mixed.txt",
          "nɬeʔkepmxcín",
          speakers=("Bev Phillips", "c̓úʔsinek (Marty Aspinall)",
                    "kʷaɬtèzetkʷ (Bernice Garcia)"),
          marks=HALL_CTR,
          note="The forms are cited from Thompson and Thompson's grammar and dictionary. These "
               "three are the speakers the paper thanks, two examples are Bev Phillips reading "
               "her own story, and kʷaɬtèzetkʷ introduces herself in the acknowledgement."),
    Paper("ICSNL58_Davis_Mellesmoen_final",
          "ICSNL58_Davis_Mellesmoen_final.oracle.tsv",
          "unstated_ANewlyDiscoveredReduplicationPatternInStatimcetsAndItsImplications"
          "_DavisMellesmoen_Salish_statimcets_2023_mixed.txt",
          "St'át'imcets",
          speakers=("Qwa7yán'ak (Carl Alexander), Nxwísten",),
          marks=DAVIS_MELLESMOEN,
          # The dropped marks go back last, after the other grains and after composition. Each pair
          # was read off a line that had already been through them. A pair matches the repaired
          # text and not the raw text: running it first matched nothing at all.
          repair=sequence(INSERTED_SPACE_AT_ACCENTS, closed_after_bracket(),
                          one_mark(COMMA_ABOVE_RIGHT, COMMA_ABOVE), composed(),
                          corrected(DAVIS_MELLESMOEN_DROPPED)),
          coverage=("mellesmoen",),
          note="Its data has three sources: van Eijk's dictionary, Davis et al. in preparation, "
               "and elicitation with Carl Alexander. It labels forms (U) and (L) for Upper and "
               "Lower St'át'imcets, the second external dialect label in the archive."),
    Paper("1967_Hamp",
          "1967_Hamp.oracle.tsv",
          "",
          "Tillamook",
          marks=HAMP_TILLAMOOK,
          note="Eric P. Hamp, Another Look at Tillamook Phonology, ICSNL 2. It cites no words, so "
               "its language content is four consonant inventories set side by side and two "
               "feature matrices. No speaker is named, and the paper works throughout from "
               "Thompson and Thompson, Reichard, Kinkade, Drachman and Edel. What it does record "
               "is that a Tillamook speaker was living in 1967 and it does not say who: the "
               "urgency of the matter is put as being that there is yet a surviving speaker "
               "available for possible re-check, and page 2 grants one sense of its claim only "
               "on the assumption that a last remaining speaker is typical of a community. Both "
               "sentences are in the table. The Twana chart is used, in the page's own words, "
               "without his permission, meaning Drachman's. The dot under the uvular fricatives "
               "prints solid in some cells of these charts and as an open ring in others, and the "
               "two positions swap between the Tillamook and Twana charts, so it is one mark and "
               "the variation is the typewriter."),
    Paper("ICSNL58_Givens_Hall_final",
          "ICSNL58_Givens_Hall_final.oracle.tsv",
          "",
          "nɬeʔkepmxcín",
          speakers=("Bev Phillips, Lytton (ƛ̓q̓əmcín) dialect",),
          marks=GIVENS_HALL_NLEKEPMXCIN,
          # Composition before the corrections, for the reason it runs first everywhere: corrected()
          # composes its own patterns, and a pattern meeting decomposed text matches nothing.
          repair=sequence(INSERTED_SPACE, composed(), corrected(GIVENS_HALL_FLATTENED)),
          coverage=("inserted spaces", "flattened labialization"),
          note="Katherine Givens and Brent Hall, The Moon and the Birchbark Canoe "
               "(ɬ máʕxetn pe ɬ qʷɬinéwɬ), ICSNL 58. Seven pages, read one at a time off page "
               "renders. Page 1: the story was recounted in Nɬeʔkepmxcín by Bev Phillips, a "
               "native speaker of the Lytton dialect, who also helped with the translation, and "
               "Givens and Hall transcribed and glossed it. She is quoted on the page choosing "
               "the story and saying creation stories are not just stories to us, and the paper's "
               "first footnote thanks her for entrusting it to them. The recording is held as "
               "speech/icsnl_proceedings/ICSNL58_GivensHall_MoonAndBirchbarkCanoe.mp3, "
               "the only one of the three whose name carries the transcribers and not the "
               "speaker, and a reader working from that filename alone read it as a second "
               "speaker. Footnote 4 defines (VG), a volunteered gloss, as a translated sentence "
               "BP offered, so the parenthesis at the right margin is the only thing separating "
               "her English from the authors', and examples 12, 13 and 14 lack it. Its section 4 "
               "repeats every sentence of section 2 in morpheme-broken form, which gave a second "
               "independent reading of every word and turned up three places where the two tiers "
               "disagree. Footnotes 2, 6, 7 and 8 each declare a mark or a parsing the authors "
               "reached by ear or by inference, which is more than any other paper here states "
               "about its own readings."),
    Paper("1967_Hess",
          "1967_Hess.oracle.tsv",
          "",
          "Snohomish",
          marks=HESS_SNOHOMISH,
          note="Thom Hess, The Morph /-(ə)b/ in Snohomish, ICSNL 2. Oracle.tsv checked against the "
               "paper. No speaker named. The forms are Hess's Snohomish data. Marked characters, "
               "page 3, by eye and inside one table: xáyəb 'laugh' and xʷúyub 'sell' print a bare "
               "x where ƛ̓áɬəb 'salty' prints a barred x body with a glottalization mark, t̓ádəb "
               "'bitter' prints the same t as the English word taste on the first line of that "
               "page with a glottalization mark added, and d̓áƛ̓əb 'cloud' carries a hook at the "
               "top of its d and a bar across the foot, one composite, where the d of t̓ádəb one "
               "column away is bare. Below 16x either half of that composite drops out. Glyphs in "
               "the printed text unclear. 1975_Hilbert_Hess sets the same character in "
               "dəxʷgʷəƛ̓əlads, and Nater's Coast Salish *ƛ̓aɬ 'bitter, salt' matches ƛ̓áɬəb "
               "segment for segment."),
    Paper("1967_Elmendorf",
          "1967_Elmendorf.oracle.tsv",
          "",
          "Twana",
          marks=ELMENDORF_COMPARATIVE,
          note="William W. Elmendorf, Word Tabu and Change Rates, ICSNL 2. Thirteen languages are "
               "cited in it and Twana is its subject, so that is the language named here; "
               "every row carries its own language in the who column. No speaker is named "
               "anywhere: the forms come from Boas and Haeberlin 1927, Krueger 1967, McIlwraith "
               "1948, Walters 1938 and Ray 1932, from Warren Snyder's Suquamish list and Wayne "
               "Suttles' Squamish field notes, and from Elmendorf's own field data. This "
               "typescript writes its uvular as x under a dot where 1975_Hilbert_Hess writes it "
               "under a caron, and 1967_Hess agrees with it, which is two papers of one "
               "conference against one of a later year. One mark is unresolved and marked so in "
               "the table: a short raised stroke over the s of the Columbia ska'u on page 7, "
               "which is not the wedge the Upper Chehalis sča'u carries two words earlier."),
    Paper("1967_Kinkade",
          "1967_Kinkade.oracle.tsv",
          "",
          "Columbian",
          marks=KINKADE_COLUMBIAN,
          note="M. Dale Kinkade, Deictics in Columbian: A Work Paper, ICSNL 2. Twelve pages, read "
               "one at a time off page renders. Columbian is what it is about; Kalispel comes from "
               "Vogt 1940, Coeur d'Alene from Reichard 1938, and three Colville forms from an "
               "unnamed speaker who also knew Columbian. Every row carries its own language in the "
               "who column. No speaker is named anywhere in the paper: it says my Cm informants "
               "and says no more than that, so the forms in this table were said by people it "
               "does not identify. Its typewriter has three raised marks and the table's symbol notes turn "
               "on telling them apart, a comma with a thick head and a curling tail, a V wedge, "
               "and a straight acute. čén̓ on page 10 carries all three in one word and is the "
               "control. The wedge appears only in the Kalispel and Coeur d'Alene forms, ten times "
               "for ten, and never in the Columbian ones, whose seven caron readings are assigned "
               "and are all x̌ or the č of čiílx. Whether that split is about the language or about "
               "page order is not decidable here, because the wedge first appears on page 8 and "
               "every Columbian form was typed on pages 1 to 7. 1967_Elmendorf, from the same "
               "conference, distinguishes a wedge from a short raised stroke in its own table, so "
               "the distinction is one these typescripts can carry."),
)


def by_stem(stem):
    """One paper's config, by the stem its text sits under in build/papers."""
    for paper in PAPERS:
        if paper.stem == stem:
            return paper
    return None


def marks_for(stem):
    """What a paper writes its language with."""
    paper = by_stem(stem)
    return paper.marks if paper else SHARED


def repair_for(stem):
    """The grains a paper's extraction carries, composed, or None where it carries none."""
    paper = by_stem(stem)
    return paper.repair if paper else None


def speakers_for(stem):
    """Whose language is in a paper, or an empty tuple where the paper never says."""
    paper = by_stem(stem)
    return paper.speakers if paper else ()
