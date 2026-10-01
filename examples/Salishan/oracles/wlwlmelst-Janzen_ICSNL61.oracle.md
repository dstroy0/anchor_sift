# wlwlmelst-Janzen_ICSNL61.oracle.tsv

Extraction of ɬe meʔmʔéw̓s te nk̓y̓ep eɬ x̣aʔx̣ʔéyqʷ nqəmmín - Mr. and Mrs. Coyote and their Magic
Kettle by wlwlmelst (Maurice Michell) and Jonathan Janzen, Kanaka Bar Indian Band, ICSNL 61.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 909 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The story is a back-translation. Stewart 1941 printed it in English, attributed to James Teit, and
wlwlmelst (Maurice Michell) translated it back into nɬeʔkepmxcín, transcribed it, and read it aloud
for a recording with his brother nk̓y̓ep (Ernie Michell), who gives the English. Jonathan Janzen
made the interlinear analysis.

The who for the story of §3.1 is wlwlmelst. The who for each tier of an example in §3.3 is
nɬeʔkepmxcín, and for the English word by word under the gloss, Jonathan Janzen. The who for a
translation, and for the English of §3.2, is Stewart 1941. The prose, the footnotes, the references
and the appendix carry the two authors.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á é í ú ƛ ə ɣ ɬ ʔ ʕ ʷ ́ ̓ ̣ ∅.
The orthography follows Thompson & Thompson 1996. It writes ɬ, ƛ̓, ʔ, ʕ, ə, ɣ, ʷ, x̣ with U+0323
COMBINING DOT BELOW, and U+0313 COMBINING COMMA ABOVE on glottalized letters, n̓, w̓, y̓, k̓, q̓.
Stress is an acute. The tiers write ∅ for a null morpheme and the appendix ⦰.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC. The text layer of
this paper is not the page. Its font names the comma above as the letter ƛ (w in the bold title),
the acute as ə and the dot below as x, and gives í as i; the text layer reads ƛ ƛ qƛ əmcin for
ƛ̓q̓əmcín. The source here is the page read from the glyph positions with pypdfium2: each misread
mark is set on the letter it sits over or under, each row of an example is rebuilt by the glyphs'
height, and an i is read as í where the page prints a slanted stroke over it, 12 to 16 pixels wide
at 600 dpi against the dot's 8 to 10. Every í of §3.1 was checked against a render of page 2 at 400
dpi.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 491
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the 7520
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
         symbol note    a note on which character a mark is
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
