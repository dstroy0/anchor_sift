# Phillips_et_al_ICSNL61-1.oracle.tsv

Extraction of e sqʷincút kt (Our Speech) by Bev Phillips, Lytton First Nation, Brent Hall and Lisa
Matthewson, University of British Columbia, and Danica Reid, Simon Fraser University, ICSNL 61.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 2713 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The story is Bev Phillips's. She wrote it in the Lytton orthography and told it to UBC's
nɬeʔkepmxcín Lab over Zoom on October 23, 2025, and the other three authors transcribed the
recording in the NAPA orthography of Thompson & Thompson and glossed each sentence. Bev marked where
each sentence begins and ends and volunteered a translation for each one.

The who for the story lines of §3 and for each tier of an example in §5 is nɬeʔkepmxcín. The who for
a translation, and for the English of §4, is Bev Phillips, because she volunteered every
translation. The prose, the footnotes, the references and the Appendix carry the four authors. The
people the story describes are the lab's members, and the paper does not name them, footnote 4.

THE LETTERS

Outside the paper's English the engine found these letters and marks: Ø á é í ó ú ƛ ə ɬ ʔ ʕ ʷ ́ ̓ ̣.
The orthography is the NAPA one of Thompson & Thompson 1992 and 1996. The segmentation line writes Ø
for a null morpheme and puts unpronounced sounds in square brackets. Thompson & Thompson 1996 write
ł in the dictionary's title where the paper writes ɬ, and scw̕exmxcín carries U+0315 COMBINING COMMA
ABOVE RIGHT on its w.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 3 page-read
corrections. The text layer sets a space inside some words: nɬeʔkepmxc ín in §1.1, n ɬeʔkepmxcín in
§2 and in Koch 2011, and N ɬeʔkepmxcín in Garcia, Hannon & Stacey 2024. These are the page-read
corrections. It also sets the dot below of the retracted schwa after a space, k̓ə ̣pqns, and the
check puts every combining mark that follows a space back on its letter. Footnotes 5 and 6 fall
between the segmentation and the gloss of (2), and footnote 4 inside the first paragraph of §4. Both
are notes, and (2) and the paragraph go on over the page break.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 491
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the 7444
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
         cited form     a word of the language named in the prose, a note or a table
         cited affix    an affix named on its own
         root           a root named on its own
         place          a place name
         language       a language name
         name           a person or a proper name
         note           a paragraph, a context, a table, a footnote or a word that is not the language
         reference      an entry of the reference list, whole
         heading        a section heading
         title          the title
         notation       a note on how the paper sets something, or where two printings disagree
         damage         a string the page prints that is itself an error, transcribed as printed
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
