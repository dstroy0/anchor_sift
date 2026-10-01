# MichelletalICSNL60.oracle.tsv

Extraction of mus te kʷúkʷpiʔs he sɬaʔx̣áns - The Four Food Chiefs by wlwlmelst (Maurice Michell),
Maria Adams, Jonathan Janzen, Kanaka Bar Indian Band, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 1768 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

wlwlmelst (Maurice Michell) wrote the story out from memory in nɬeʔkepmxcín, transcribed and
translated it himself, and was recorded reading it. Jonathan Janzen made the interlinear analysis
and edited the recording.

The who for the story of §3.1 and the English of §3.2 is wlwlmelst. The who for each tier of an
example in §3.3 is nɬeʔkepmxcín, for the English word by word under the gloss, Jonathan Janzen, and
for the translation after the tiers, wlwlmelst, whose English of §3.2 it repeats. The prose, the
footnotes, the references and the appendix carry the three authors.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á é í ó ú ƛ ə ɣ ɬ ʔ ʕ ʷ ̓ ̣ ∅.
The orthography follows the Thompson River Salish Dictionary, Thompson & Thompson 1996. It writes ɬ,
ƛ̓, ʔ, ʕ, ə, ɣ, ʷ, x̣ with U+0323 COMBINING DOT BELOW, and U+0313 COMBINING COMMA ABOVE on
glottalized letters, n̓, w̓, y̓, k̓, q̓. Stress is an acute. The tiers write ∅ for a null morpheme
and the appendix ⦰.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC. The text layer sets a
space after a glottalized letter and before the dot below, ƛ̓ uʔ for ƛ̓uʔ and x ̣iyms for x̣iyms;
the page text is closed up from the glyph positions. Example (3) runs over a page break under
footnote 2, and (7)'s translation over a line after which footnote 3's mark stands. (14) opens on
its whole sentence set on one line and prints its second transcription line twice, and (13) has no
line of English word by word; each is kept as printed.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 368
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the 6690
distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     transcription  an example tier in the orthography
         segmentation   an example tier broken into morphemes
         gloss          the morpheme gloss tier of an example
         word gloss     an English tier under the gloss, word for word
         translation    the English of an example
         cited form     a word of the language named in the prose, a note or a table
         cited affix    an affix named on its own
         place          a place name
         language       a language name
         name           a person or a proper name
         note           a paragraph, a context, a table, a footnote or a word that is not the language
         reference      an entry of the reference list, whole
         heading        a section heading
         title          the title
         notation       a note on how the paper sets something, or where two printings disagree
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
