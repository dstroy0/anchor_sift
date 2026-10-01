# MellesmoenICSNL60_BCHk.oracle.tsv

Extraction of Innovations on Classic Salish Morphology: Glottal Stop Codas in Nuxalk and
Halq̓eméylem by Gloria Mellesmoen, University of British Columbia, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 417 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The paper's data are cited from published sources, and each translation's who is the source its tag
names, (Nater 1990: 107) or (Galloway 2009: 10). The St’át’imcets examples (4) and (5) come from Van
Eijk 1997 and 2013, Davis & Mellesmoen 2023 and Davis et al. in prep; the Nuxalk examples (6) to (9)
and (18) from Nater 1978 and 1990 and Bagemihl 1991; the Halq̓eméylem examples (19) and (22) from
Galloway 2009; and the hən̓q̓əmin̓əm̓ examples (20) and (21) from Suttles 2004. The who of each tier
is the language of the example.

The tableaux (16), (17), (26), (27) and (29) are the author's: each candidate is a row whose who is
the language it is a candidate form of, and its violation marks are a note of the author's beside
it. The definition (1) and the ranking (2) are McCarthy and Prince's, and (25) is McCarthy's as
cited in Kager 1999. The other constraints, the rankings, the lexical entries (10) and (23), the
prose, the headings and the notes carry Gloria Mellesmoen.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á é í ƛ ə ɬ ʔ ʕ ʷ ː ́ ̓ ̣ ̩ μ
ḷ. The Nuxalk, St’át’imcets and Halkomelem forms are in the Americanist orthography of their
sources, with the glottalization of a consonant as U+0313, the dot below of the St’át’imcets
retracted consonants as U+0323, a syllabic sonorant with U+0329, and length as ː, U+02D0. An infix
and a copied segment stand in angle brackets, <ː> for length and <ʔ> for a glottal stop. Moras are μ
and syllables σ; the constraint names are small capitals on the page and ASCII capitals in the text
layer.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC. The page marks the
winning candidate of each tableau with a pointing hand, U+F046 in the text layer; the table drops it
and says so in the candidate's gloss. The text layer sets a space after a glottalized letter, k̓ ʷ
for k̓ʷ, and the table closes it. The page quotes the translations of (7) with a backtick and a
straight quote, `small deer', gives (20c)'s translation no closing quote, and prints k̓̓ with two
commas above in (19d); each is kept.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 417
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
12012 distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     transcription  an example tier in the orthography
         segmentation   an example tier broken into morphemes
         phonemic       an example tier in a phonemic alphabet
         gloss          the morpheme gloss tier of an example
         translation    the English of an example
         rule           a line of a rule, a derivation or a tree the authors display
         cited form     a word of the language named in the prose, a note or a table
         language       a language name
         name           a person or a proper name
         note           a paragraph, a context, a table, a footnote or a word that is not the language
         citation       a work cited in the text, or the tag at the right of an example
         reference      an entry of the reference list, whole
         heading        a section heading
         title          the title
         notation       a note on how the paper sets something, or where two printings disagree
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
