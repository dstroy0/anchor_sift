# Trotter_ICSNL.oracle.tsv

Extraction of The past tense suffix and 2PCs in ʔayʔaǰuθəm (Comox-Sliammon) by Bailey Trotter, The
University of British Columbia, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 392 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is ʔayʔaǰuθəm, its Mainland dialect. The examples come from Watanabe 2003, Huijsmans
2023 and Kroeber 2002, each named in brackets at the right of the translation, and from the author's
elicitation with Betty Wilson, tagged [sf | BW.date].

The who for each tier of an example is the language, and for a translation the author. The lexical
entries (3), (15) and (18) and the tables give their allomorphs to the language. The footings of (9)
and (10), the steps of the derivations (21) and (22), the features (1) and (2) and the prose carry
the author.

THE LETTERS

Outside the paper's English the engine found these letters and marks: Ø í č š ƛ ǰ ə ɛ ɩ ɬ ʊ ʔ ʷ ̌ ̓
θ χ ω ᶿ. The transcription lines write the practical orthography with ɛ, ʊ and ɩ, hɛkʷ čɛ, and the
segmentation lines the phonemic forms, hiɬ+kʷ=ča. ω marks a prosodic word, μ a mora, Ft a foot, and
Ø a null allomorph.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC. The engine took the
last cell of Table 2, 3 Ø, for the heading of section 3, and ran the headings of §2.3, §2.4 and §3
into the prose; the rows between are given back to their sections here. The lexical entries (3),
(15) and (18) and Tables 1 to 3 are read off the page one cell a row, their columns placed by glyph
position.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 319
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the 9446
distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     transcription  an example tier in the orthography
         segmentation   an example tier broken into morphemes
         gloss          the morpheme gloss tier of an example
         translation    the English of an example
         rule           a line of a rule, a derivation or a tree the authors display
         cited form     a word of the language named in the prose, a note or a table
         cited affix    an affix named on its own
         place          a place name
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
