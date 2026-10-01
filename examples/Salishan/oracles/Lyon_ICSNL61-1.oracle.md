# Lyon_ICSNL61-1.oracle.tsv

Extraction of Zero Prospectives, Zero Modals, and Modo-Temporal Interactions in nsyilxcn (Okanagan
Salish) by John Lyon, University of British Columbia - Okanagan, ICSNL 61.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 6683 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is nsyilxcn, Okanagan, and the examples were elicited from four speakers, each named in
the tag at the right of the translation: Delphine Derickson-Armstrong and Dave Michele of Westbank
reserve, and the Upper Nicola Elders Lottie Lindley and Sarah McLeod, whom footnote * thanks with
the word Limlmt. VF in a tag marks a form the speaker volunteered, CF a form the author constructed,
and VG a gloss or translation the speaker volunteered. The speaker comments after an example are
theirs, signed with their initials DD, DM and SM, and JL is the author.

The who for each tier of an example is nsyilxcn. The who for a translation tagged VG is the speaker
named in the tag, and John Lyon otherwise. The who for a speaker comment is the speaker who made it,
or the speaker named in the example's tag where the comment is unsigned. The prose, the contexts and
the notes carry John Lyon.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á é í ú ƛ ə ɬ ʔ ʕ ʷ ́ ̌ ̓ ̕ ∅.
The null morpheme ∅ is U+2205. Glottalization is U+0313 on the letter, and the caron of x̌ is
U+030C. The raised w of kʷ is U+02B7. The gloss labels are ASCII capitals in the text layer.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC. Pages 1 and 4 were
read against the text layer and agree with it letter for letter. The rest of the paper was
reconstructed by the engine and checked by the residue check alone.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 1475
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
27030 distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     transcription  an example tier in the orthography
         segmentation   an example tier broken into morphemes
         gloss          the morpheme gloss tier of an example
         translation    the English of an example
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
         symbol note    a note on which character a mark is
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
