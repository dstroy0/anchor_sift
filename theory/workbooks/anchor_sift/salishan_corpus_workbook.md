# Salishan corpus workbook

**Purpose:** Record what the hand-extracted Salishan oracle tables say when they are pointed at questions
Salishanists have asked in print, one question at a time, with a control run before any answer is read.
**Scope:** `maint/data/salishan/experiments/` (`corpus_rows.py`, `subgrouping_check.py`,
`lexical_suffix_origins.py`, `reduplication_glottalization.py`, `vowelless_words.py`,
`nuxalk_obstruent_words.py`), and this file.

This is a workbook, not a result. It follows the rail the other workbooks beside it follow:

- Claim nothing past the measurement. A number here is a count over these tables, and these tables are
  what 138 papers chose to print. Every entry says which papers a number rests on.
- Cite nothing unread. Each question below is quoted from its source, and the source was read from the
  corpus copy unless the entry says it arrived by report.
- A known answer runs first. No comparison across languages is read until the same code has recovered
  something the field already knows (entry P0).
- Withdrawn entries stay on the page with what killed them. Five are recorded below.

These words belong to the people who speak them. The conditions their speakers set are recorded per
table in the Salishan book, under "Whose words these are", and they hold here. The tables stay closed
(`salishan_corpus/README.md`); the scripts read them where they sit and print counts. The few forms
quoted below are quoted from the published papers named beside them, as a reader of those papers would.

## The problem table

| # | Question, as asked | Asked by | Test | Control | Status |
|---|---|---|---|---|---|
| P0 | Does meaning-matched vocabulary from these tables recover the accepted Salish subgrouping? | the field's classification (known answer) | Dolgopolsky classes, first two consonants, excess over a meaning shuffle | criteria (a) to (d) fixed before the run | **passes** (a, b, c; d as revised) |
| P1 | Are lexical suffixes phonologically related to nouns of the same meaning, as consonant + suffix nouns ([C + LS])? | Kinkade 1998 against Mithun 1984 (via Kinkade) | same-meaning suffix/noun pairs, Kinkade shape and tail shape | meanings shuffled among each language's nouns, 5000 times | **tail relation above chance; [C + LS] shape too rare to test** |
| P2 | How does a glottalized resonant fare under reduplication in the five languages left Unclear? | Mellesmoen & Urbanczyk 2021, Table 4 | doubled consonant pairs, glottalization of each copy | the survey's classified languages, its own papers left out | **method agrees 7 of 8; the blanks stay blank on these tables** |
| P3 | Is Nuxalk's reputation for vowelless words in large part spacing, clitics printed apart? | Robertson 2020 (blog comment, read) | obstruent-only tokens in two oral texts, clitics joined and opened | the same text counted both ways | **supported: 0.9% joined, 18.5% opened** |
| P4 | How common are free obstruent-only words in Nuxalk, and is there more than one made of stops only? | Mellesmoen 2021 against Nater 2024 | Mellesmoen's own definition applied outside both disputants' papers | both disputants' papers excluded | **9.2% of 1332 distinct free words; three stops-only words attested** |
| P5 | Which branch does Nuxalk share most vocabulary with? | the family's standing puzzle | P0's measure, Nuxalk rows | P0 | **undetermined: 15 to 21 shared meanings per pair** |
| P6 | Do Southern Interior languages with word-initial glottalized resonants also shift the quality of schwa? | Mellesmoen & Urbanczyk 2021, section 4 | none possible here | none | **not testable on these tables**: it needs phonetic measurement |

## What the tables hold

`python maint/data/salishan/experiments/corpus_rows.py`. The loader folds the papers' spellings of one
language to one name (nɬeʔkepmxcín, Nɬeʔkepmxcín and Nłeʔkepmxcín are one language; Bella Coola is
Nuxalk) and gives each its branch. A form row whose "who" is a speaker or an author takes the language
the paper states in its ops header, or the one recorded in `paper_config.PAPERS` for the 23 papers
extracted before ops files existed, or the language of 70% or more of the paper's own placed form rows.

Salish form rows placed, by branch: Northern Interior 10,585; Central 9,755; Nuxalk 2,993; Southern
Interior 2,500; Tsamosan 332; Tillamook 52. 209 form rows stay unplaced. Most carry a label for a group
("Salish" 82, "Interior Salish" 23) or a language outside the family cited in a typological comparison;
14 name a person in a paper that states no language. 6,343 segmentation rows pair with a gloss row. The
tables are weighted toward modern syntax and semantics papers, and it matters for every entry below:
they are rich in glossed sentences and poor in the body-part vocabulary and word lists historical
questions need.

## P0, 2026-09-24: the known answer

`python maint/data/salishan/experiments/subgrouping_check.py 2000`.

Forms are reduced to Dolgopolsky sound classes after the practical orthographies' digraphs are read as
one sound. Two forms of one meaning match when their first two classes agree, the criterion Turchin,
Peiros and Gell-Mann (2010) use; that paper is cited from report and was not read. A match counts only
between forms from different papers, since a comparative paper prints two languages' forms side by side
because they resemble each other. For each pair of languages with 15 or more shared meanings, the excess
is the observed match rate less the mean over 2000 shuffles of one language's meanings.

Twelve languages carry 40 or more meanings: Halkomelem 349, Lushootseed 104, ʔayʔaǰuθəm 461,
Nɬeʔkepmxcín 518, Secwepemctsín 262, St'át'imcets 221, Nsyilxcən 477, Nuxalk 61, and outside the family
Chinuk Wawa 69, Gitksan 99, Haisla 78 and Nuuchahnulth 69. Result, criteria fixed before the first run:

- (a) Each Interior language's best Salish partner is Interior: Nɬeʔkepmxcín with St'át'imcets,
  Secwepemctsín, St'át'imcets and Nsyilxcən each with Nɬeʔkepmxcín. Pass.
- (b) Each Central language's best Salish partner is Central: Halkomelem with Lushootseed, Lushootseed
  and ʔayʔaǰuθəm with Halkomelem. Pass.
- (c) Mean excess inside Interior +0.268 over 6 pairs, inside Central +0.134 over 3, between the two
  +0.037 over 11. Pass.
- (d) As revised (see Withdrawn): no pair of a language outside the family and a Salish language has a
  shuffle p below 0.01. Chinuk Wawa, Gitksan, Haisla and Nuuchahnulth all pass; the largest excess
  among them is Gitksan with St'át'imcets, +0.067 over 33 meanings.

The measure is coarse and it sorts the family the way the field does. It is trusted below for broad
structure and not for anything finer.

## P1, 2026-09-24: lexical suffixes and the nouns of their meaning

`python maint/data/salishan/experiments/lexical_suffix_origins.py 5000`.

The question. Kinkade (1998, "Origins of Salishan Lexical Suffixes", ICSNL 33) defines lexical suffixes
as suffixes with the meaning of a noun that "lack phonological similarity" to it, then argues that each
language keeps a handful of nouns built as a consonant plus the suffix of the same meaning, his [C + LS]
forms (Upper Chehalis mus 'eye' beside =us), from which the suffixes came. He found "anywhere from 6 to
14" per language. He quotes Mithun (1984:887) that "a derivational relationship between the affixes and
independent N's is not now discernable". Mithun is cited here through Kinkade's quotation.

The test. Suffixes are cited-affix rows, and =-morphemes after a root carrying an English gloss. Nouns
are single-morpheme forms, an s- nominalizer set aside. Both are kept only when a sense falls in a fixed
list of 53 generic nominal meanings (hand, foot, head, face, eye, mouth, water, house and the rest, with
81 English glosses folded to them). The Kinkade shape is a noun one or two segments longer than a
same-meaning suffix and ending in it; the tail shape is any longer noun ending in it. The null shuffles
which meaning each noun carries, inside its language, 5000 times.

The result. Six languages give 86 same-meaning suffix/noun pairs: Halkomelem, Lushootseed, ʔayʔaǰuθəm,
Nɬeʔkepmxcín, Twana and Upper Chehalis. The tail shape: 5 observed, shuffled mean 0.45, shuffled maximum
4, p = 0.0002. The Kinkade shape: 1 observed (Halkomelem xʷəlməxʷ 'people' beside =əlməxʷ, consonant plus
suffix exactly), shuffled mean 0.11, p = 0.11.

What it shows. Across these tables, nouns of a suffix's own meaning end in that suffix far more often
than chance, against the letter of "lack phonological similarity". It does not decide Kinkade's
direction of derivation. The longer nouns in the tail pairs (Lushootseed sxəyʼus 'head' beside =us,
Twana sčka·psəb 'neck' beside =psəb) may themselves be derived with the suffix, and synchronic tables
cannot tell a noun built with a suffix from the noun a suffix came from. The [C + LS] shape proper is
seen once and cannot be tested at this size; the nouns inside the meaning list number 14 to 37 per
language. The test is ready for tables with a dictionary's worth of nouns.

## P2, 2026-09-24: glottalized resonants under reduplication

`python maint/data/salishan/experiments/reduplication_glottalization.py`.

The question. Mellesmoen and Urbanczyk (2021, "Some Remarks on the Distribution and Representation of
Glottalized Resonants in Salish", ICSNL 56) classify each language in their Table 4 by what
reduplication does to a glottalized resonant: glottalized in both copies, or plain in one. Pentlatch,
Sechelt, Upper Chehalis, Cowlitz and Bella Coola are Unclear, and they write that "the blanks in the
charts can serve as a guide for further research".

The test. A form is taken as doubled when its consonant skeleton holds some consonant pair twice in a
row (CVC reduplication); where a resonant of the pair is glottalized in either copy, the pair scores
IDENTICAL or SPLIT. Each doubled pair is counted once per language. The survey's own two papers are left
out. The classified languages then test the method and not the survey's agreement with itself.

The result. Seven of eight classified languages agree with Table 4. The five with 7 or more comparisons
all agree: St'át'imcets 7 identical to 0 split, Nɬeʔkepmxcín 11 to 3 and Nsyilxcən 7 to 2 (Table 4:
identical), ʔayʔaǰuθəm 1 to 7 (Table 4: split), Halkomelem 4 to 5 (Table 4: both, by dialect). Twana
disagrees, 3 identical to 1 split, all four from one paper (Mellesmoen, ICSNL 60, on Twana). Of the
five Unclear languages the tables hold one doubled root, in Upper Chehalis, split (from Mellesmoen,
ICSNL 57), and none for the other four.

What it shows. The method sorts the languages the survey could classify. The blanks cannot be filled
from these tables: the forms that would fill them are not in the 138 papers extracted so far. The Twana
count is four roots from one paper, and whether they are the reduplication type Table 4 classifies was
not checked. It is a question for the authors, not a correction.

## P3, 2026-09-24: Nuxalk vowelless words and the spacing of clitics

`python maint/data/salishan/experiments/nuxalk_obstruent_words.py`.

The question. On Victor Mair's Language Log post "Words without vowels" (2 March 2020), David D.
Robertson commented that "any apparent preponderance of vowelless 'words' in Nuxalk derives in big part
from the community writing system's choice of visually isolating several clitics from the words they
inflect". What the community orthography does with clitics is taken from his comment; it was not
checked against that orthography.

The test. Nater's two oral texts in these tables (the Bella Coola tale in the ICSNL 50 volume, and "An
Oral Tradition from Sackʷ", ICSNL 59) write a clitic group as one token, joined with ˽ in the first and
ˬ in the second. Each text is counted as written, then with every joiner opened into a space. A token is
obstruent-only under Mellesmoen's 2021 definition: no vowel and no sonorant.

The result. As written, 7 of 772 tokens are obstruent-only (0.9%). With the clitics opened, 313 of
1692 are (18.5%). The two texts agree separately: 1 of 199 against 65 of 421 in the tale, 6 of 573
against 248 of 1271 in the ICSNL 59 text. The 6 tokens made of stops only all appear once the clitics
are opened; none does as written.

What it shows. In these two texts the difference between a Nuxalk with few vowelless words and one with
many is the spacing of clitics, by a factor of twenty. For comparison, `vowelless_words.py` puts running
text as the other papers write it at 10% vowelless tokens for Nɬeʔkepmxcín, 15% for Nsyilxcən and 21%
for Lushootseed (over 425 tokens; vowelless there allows a sonorant), against 5% for Nuxalk.

## P4, 2026-09-24: how many Nuxalk words are made only of obstruents

Same script.

The question. Mellesmoen (2021, "Syllables and Reduplication in Bella Coola (Nuxalk)", ICSNL 56) counts
51 obstruent-only words among 1506 FirstVoices entries, "under 4%" of the lexical items, and finds one
made only of stops, tp 'spotted', noting that the root is not given as a standalone word in Nater
(1990:133). Nater (2024, "Voiceless Words in Bella Coola: Fact vs. Fiction", ICSNL 59) answers her,
lists 127 voiceless words and roots, and maintains that the language is non-syllabic.

The test. Mellesmoen's definition, applied to the Nuxalk free words in every paper except those two:
cited forms that are one token, not starred, not a root, not an affix or clitic. Stops are p, t, k, q
and their ejectives; c and ƛ are affricates, kept apart as she keeps them.

The result. 1332 distinct free words, 122 obstruent-only (9.2%). 1262 of them come from Nater's 2013
comparative list "How Salish is Bella Coola?", and 118 of those are obstruent-only. Three are made of
stops only: kp, tk‟ and tq‟, which Nater 2024 glosses 'each, all, every', 'sticky' and 'arrive by boat,
land'. With affricates counted as stops, 14 qualify.

What it shows. The rate is 2.7 times the FirstVoices figure. The sources differ: Nater's 2013 list was
built to compare Bella Coola with Salish, and nearly every form here is in his transcription. Three free
stops-only words are attested in a paper printed eight years before the exchange. The rate does not
decide syllabicity, the substance of the exchange.

## P5, 2026-09-24: Nuxalk's nearest branch

From P0. Nuxalk shares 15 to 21 meanings with each language it can be compared with. Its excesses:
Nɬeʔkepmxcín +0.118, ʔayʔaǰuθəm +0.080, Nsyilxcən -0.036, Secwepemctsín -0.051. Mean with Interior
+0.011 over three languages, with Central +0.080 over one. At this many meanings a single match moves an
excess by about 0.05. Undetermined.

## Open, not done

- P1 and P2 are limited by what has been extracted, not by the method. The corpus holds 987 papers as
  PDF and 138 have an oracle table. Extracting the Sechelt, Pentlatch, Cowlitz, Upper Chehalis and
  Nuxalk papers and any dictionary-like papers first would fill P2's blanks and give P1 the nouns it
  needs.
- P4's rate rests almost entirely on one author's transcription and one comparative list. A second
  lexicon in another hand would show whether the 9% or the 4% belongs to the lexicon and not the sample.
- P0's measure is Dolgopolsky's coarse one. A measure built on regular sound correspondences would be
  needed before anything finer than the Interior/Central split is read.

## Withdrawn

- **Withdrawn.** P1's first run, which read noun meanings from any short gloss.
  **What killed it:** the diagnostics. The commonest "noun meanings" were provenance notes ("wordlist",
  "orthography"), and the =-morphemes of the Interior papers were proclitic hosts, not suffixes.
  Replaced by the fixed list of nominal meanings, applied to suffixes and nouns alike before any pair
  was counted.
- **Withdrawn.** P0 criterion (d) as first fixed: no outside language above the largest excess its own
  shuffles produce. **What killed it:** the maximum of a shuffle depends on how many shuffles are run.
  Kwak'wala with ʔayʔaǰuθəm (+0.144 over 17 meanings, against a ceiling of +0.086) failed at 200
  shuffles and passed at 500. Replaced, after that run and recorded as a change, by a shuffle p below
  0.01.
- **Withdrawn.** P0's first reading that Nuxalk stands nearest ʔayʔaǰuθəm (+0.235 over 22 meanings).
  **What killed it:** the matching meanings were 'mother', 'father', 'child' and 'money'. Parent and
  child terms built on m, n, p, t match across unrelated languages, and 'money' is a loan. Those
  meanings and other post-contact ones are now excluded, a choice made after seeing this run; the P0
  verdicts held after it, and the excess fell to +0.080 over 18.
- **Withdrawn.** P2's first counts, which scored each word and read Nsyilxcən as disagreeing with Table 4
  (10 identical to 4 split). **What killed it:** one Nsyilxcən word was counted three times with footnote
  numbers stuck to it, and one doubled root was counted again in each derived word. Counting each root
  once turned the verdict into agreement (7 to 2). The correction was made after the disagreement was
  seen, and it is recorded here for that reason.
- **Withdrawn.** P3's first reading that Nuxalk's lexicon is 24% vowelless, the highest in the corpus.
  **What killed it:** the breakdown by paper. The figure was carried by Nater's reconstructions and
  roots, and by a paper written to list voiceless words. P4 replaces it with Mellesmoen's definition and
  both disputants' papers excluded.
