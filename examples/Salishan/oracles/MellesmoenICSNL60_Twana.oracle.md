# MellesmoenICSNL60_Twana.oracle.tsv

Extraction of Reduce, Reuse, Reduplicate: “Wrong Side” Reduplication in Twana by Gloria Mellesmoen,
University of British Columbia, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 488 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The paper's data are cited from published sources. Every Twana form comes from Drachman 1969 and
each Tillamook form from Egesdal and Thompson 1998, and each translation's who is the source its tag
names, (Drachman 1969: 41). The who of each form is its language.

The tableaux (9), (13), (17), (18), (20), (22), (24) and (25) are the author's: each candidate is a
row whose who is Twana, except the schematic candidates of (9), which are the author's notation, and
its violation marks are a note of the author's beside it. The definition (10) is McCarthy and
Prince's as cited in Urbanczyk 1996; DEP (8b) is Kager's, *FLOAT (8c) Kirchner's, ONSET (12b)
Blake's, MAX and LINEARITY (15) McCarthy and Prince's, and SYLLCON (23) Urbanczyk's. The other
constraints, the rankings, the tables, the prose, the headings and the notes carry Gloria
Mellesmoen.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á é ó č š ƛ ə ɬ ʔ ʷ ́ ̓ ̣ μ σ.
The Twana and Tillamook forms are in the Americanist orthography of Drachman 1969 and Egesdal and
Thompson 1998, with the glottalization of a consonant as U+0313, the dot below of a uvular as
U+0323, and stress as an acute accent on the vowel. A tilde joins the reduplicant to the root,
s-q~téqaw, and a hyphen sets off a prefix. The analysis writes C for a consonant, V for a vowel, S
for a sonorant or voiced obstruent and O for a voiceless obstruent; σ is a syllable and μ a mora.
The constraint names are small capitals on the page and ASCII capitals in the text layer.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC. The page marks the
winning candidate of each tableau with a pointing hand, U+F046 in the text layer; the table drops it
and says so in the candidate's gloss. The text layer sets a space after a glottalized letter, q̓ ʷ
for q̓ʷ, and the table closes it. The page underlines the segments between a copied consonant and
its source in kt̓ə́keʔəs and qəbə́qsəd; the text layer breaks kt̓ə́keʔəs at the underline and writes
C1C2 in its translation as C 1C2. Figures 1 and 2 are drawings, and only their captions are in the
text layer.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 461
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
11862 distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     transcription  an example tier in the orthography
         segmentation   an example tier broken into morphemes
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
