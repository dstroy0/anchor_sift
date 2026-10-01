# SchneiderGriffinICSNL60.oracle.tsv

Extraction of On the ‘go’: Exploring auxiliary-hood in ʔayʔaǰuθəm in comparative perspective by
Lauren Schneider, University of Arizona, and Laura Griffin, University of Toronto, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 912 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

Each example's tiers go to the language named at the right of the first example of its run:
Hul’q’umi’num’ for (1), (4) and (5), (9) to (13), (32), (33) and (45); SENĆOŦEN for (14) to (17),
(34) to (38), (46) and (47); Klallam for (6) to (8); Nigerian Pidgin for (48); ʔayʔaǰuθəm for the
rest and for footnote 10's example. Each translation goes to the work it is cited from, and the
speaker's initials and the source after it make a citation row. The words the prose cites go to the
language the prose names before them. The prose, the tables, Figure 2 and the notes carry the
authors.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á é í ú č ŋ š ƛ ǝ ǰ Ɂ ə ɛ ɩ ɫ
ɬ ʊ ʔ ʷ ́ ̌ ̓ ̕ ̣ θ χ ᶿ. ʔayʔaǰuθəm is written two ways: the practical line of Paul's stories, with
ɛ and ɩ, and the Americanist line beneath it, with ǰ, x̌, χ and ʔ or Ɂ. Hul’q’umi’num’ examples set
the community orthography, with ’ and tth, over an Americanist line with ̓ U+0313 and tθ; SENĆOŦEN
examples set the capitals of its alphabet, with ¸ and W̱, over an Americanist line. Square brackets
mark words unpronounced in fast speech, * an ungrammatical sentence and ? an awkward one.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 3 page-read
corrections. Closing the space after a mark below runs three pairs of words together that the page
sets apart, SW̱ YÁ¸ in (36) and (38), qayx̣ kʷum in (24) and Qayx̣ (Mink) on page 3; a 400 dpi
render and the glyph positions part them. Figure 1 is a map, and only its caption is in the text
layer. The text layer sets each reference's link at the head of the entry after it; the references
are read off the page again one entry a row.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 558
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
14192 distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     transcription  an example tier in the orthography
         segmentation   an example tier broken into morphemes
         gloss          the morpheme gloss tier of an example
         translation    the English of an example
         cited form     a word of the language named in the prose, a note or a table
         cited affix    an affix named on its own
         language       a language name
         name           a person or a proper name
         note           a paragraph, a context, a table, a footnote or a word that is not the language
         citation       a work cited in the text, or the tag at the right of an example
         reference      an entry of the reference list, whole
         heading        a section heading
         title          the title
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
