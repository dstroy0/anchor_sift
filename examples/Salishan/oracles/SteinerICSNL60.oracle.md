# SteinerICSNL60.oracle.tsv

Extraction of nɬeʔkepmxcín Somatic Suffixes by Reed Steiner, University of British Columbia, ICSNL
60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 1917 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is nɬeʔkepmxcín. The examples come from the author's three consultants, Bev Phillips
(BP), c̓úʔsinek Marty Aspinall (CMA) and kʷaɬtèzetkʷuʔ Bernice Garcia (KBG), each tagged sf for a
supplied form or vf for a volunteered form, with the date, and from Thompson and Thompson 1992 and
1996. (74) on page 33 is Nahuatl, after Mithun 1984.

The who for each tier of an example is the language. The who for a translation is the work cited on
its line, and the author's where the line carries a consultant's tag. A consultant's comment is
theirs, and RS in (33b) is the author. The denotations of §3 and §4 and their paraphrases, the
captions and the prose carry the author.

THE LETTERS

Outside the paper's English the engine found these letters and marks: Ø á è é í ó ú č š ƛ ə ɣ ɬ ʔ ʕ
ʷ ́ ̓ ̕ ̣ ∅. The paper writes the glottalized stops with a comma above, c̓ and q̓, and in places
with a reversed comma, q̕ and w̕, both in the same dialect name, ƛ̓q̕əmcín beside ƛ̓q̓əmcín. ∅ marks
a null morpheme and [ ] a segment the segmentation restores. The denotations write ⟦ ⟧ for the
interpretation brackets, λ for abstraction and ∧ for conjunction, with the types as subscripts the
text layer sets on the line, λxe for λxₑ.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 3 page-read
corrections. The text layer runs each denotation and its paraphrase into the prose around it; the
displays of §3 and §4 are read off the page again here, one row a line of formula and one a
paraphrase. The paper numbers two examples (74), the Restrict2 display on page 30 and the Nahuatl
example on page 33, and prints the third step of (48) as (ii) again. The text layer sets a space
after the accented schwa of sɣə́p, cʕə́p and c̓k̓ʷə́m, which the glyph positions close; those three
are corrected before the page is read.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 958
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
17172 distinct tokens in the paper, 0 language tokens are held by no row.

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
