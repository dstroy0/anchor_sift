# ICSNL59_Davis_final.oracle.tsv

Extraction of Central Salish from a Nooksack Perspective by Henry Davis, University of British
Columbia, ICSNL 59.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 892 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The examples are Nooksack, from the corpus of George Swanaset, Sindick Jimmy and Louisa George, but
for (4) and (8), Upriver Halkomelem from Galloway, (9), Squamish from Kuipers, (29) and (33),
nɬeʔkepmxcín, and (30) and (34), St’át’imcets, each with its source on the page. The cells of the
tables that are affixes or particles are given to the language of their column, and the prose's
forms to the language it names; the proto-forms are the author's reconstructions.

THE LETTERS

Outside the paper's English the engine found these letters and marks: Í Ó Ø à á é í ó ú č ĺ ŋ š ƛ ə
ɛ ɬ ʔ ʷ ̀ ́ ̌ ̓ ̕ θ. Each Nooksack example sets Galloway's practical orthography over an Americanist
line, with ʔ, ɬ, ƛ̓, x̌, xʷ, č, š and θ; the stressed vowel carries an acute accent. The tables and
the prose write affixes with a hyphen and clitics with an equals sign, and the proto-forms with a
star.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 11 page-read
corrections. The text layer ran each of the sixteen tables into the prose; the tables are read from
the glyph positions a cell a column. It drops the caron of x̌ and sets a space where it stood, in
twelve examples, and sets /k̓/ and /ky/ of footnote 33 with a space inside the slashes; each is read
off the page at 250 dpi.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 663
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
19374 distinct tokens in the paper, 0 language tokens are held by no row.

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
         notation       a note on how the paper sets something, or where two printings disagree
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
