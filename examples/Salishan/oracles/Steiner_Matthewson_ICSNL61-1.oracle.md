# Steiner_Matthewson_ICSNL61-1.oracle.tsv

Extraction of That moon has risen: The semantics of nɬeʔkepmxcín nominal demonstratives by Reed
Steiner and Lisa Matthewson, University of British Columbia, ICSNL 61.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 5356 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is nɬeʔkepmxcín. The examples come from Bev Phillips (BP) and kʷaɬtèzetkʷ Bernice
Garcia (KBG), each tagged SF for a sentence the authors supplied or VF for one the speaker
volunteered, with the date. c̓úʔsinek Marty Aspinall (CMA) is heard in recorded conversation. (11)
is St’át’imcets, Carl Alexander's sentence from Alexander et al. 2025, and footnote 13's (i) is
ʔayʔaǰuθəm, reported by Marianne Huijsmans.

The who for each tier of an example is the language. The who for a translation is the authors where
the tag carries SF or VF, and the work cited where it names one. A consultant's comment is that
consultant's, and the discussion under (21c) is kʷaɬtèzetkʷ's and the researcher's. The trees, the
table heads and the prose carry the authors.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á è é í ó ø ú š ƛ ə ɛ ɩ ɬ ʔ ʕ
ʷ ́ ̓ ̕ ̣ ḿ ṣ ∅. The paper writes ɬ and sometimes ł for the lateral fricative, kʷaɬtèzetkʷ beside
kʷałtèzetkʷ, and c̓ beside c̕ for the glottalized c, c̓úʔsinek beside c̕úʔsinek. Glottalized
resonants take U+0313 COMBINING COMMA ABOVE, n̓ and w̓.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 1 page-read
correction. The text layer of this paper puts a space at every change of font, inside words: n
ɬeʔkepmxcín, demonstrative s, c̓ úʔsinek, ƛ̓ q̓ mcín. The source here closes each such gap where the
glyph positions, read with pypdfium2, show none, and keeps the widths of the column gaps between the
cells of an example. The trees of (44) and (50) are drawn as pictures and have no text layer; their
content is written out in a symbol note each, read at 110 and 150 dpi.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 1321
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
24082 distinct tokens in the paper, 0 language tokens are held by no row.

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
         speaker comment a speaker's own comment on an example, in their words
         cited form     a word of the language named in the prose, a note or a table
         place          a place name
         language       a language name
         name           a person or a proper name
         note           a paragraph, a context, a table, a footnote or a word that is not the language
         citation       a work cited in the text, or the tag at the right of an example
         reference      an entry of the reference list, whole
         heading        a section heading
         title          the title
         notation       a note on how the paper sets something, or where two printings disagree
         symbol note    a note on which character a mark is
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
