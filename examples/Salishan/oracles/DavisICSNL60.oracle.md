# DavisICSNL60.oracle.tsv

Extraction of A How-To Guide to Control Infinitives in St’át’imcets by Henry Davis, The University
of British Columbia, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 3128 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is St’át’imcets, Northern Interior Salish. All unattributed examples and judgements
come from Carl Alexander, Qwa7yán’ak, whom the acknowledgement thanks, and the Consultant of the
comments is him. Other examples are cited from texts and a dictionary: Alexander 2016, Matthewson
2005b, Mitchell 2022, van Eijk and Williams 1981 and Davis et al. in prep. The examples (40) and
(41) and those of footnote 9 are ʔayʔaǰuθəm, from Betty Wilson and Molly Harry.

The who for each tier of an example is its language. The who for a translation is the source its tag
cites, and Henry Davis for an untagged one. The comments signed Consultant are Carl Alexander's, and
the Interviewer's question is the author's. The English examples of (39) and (49) are the author's,
and (54), (66) and (67) are Landau's. The prose, the headings and the notes carry Henry Davis.

THE LETTERS

Outside the paper's English the engine found these letters and marks: Ø á í ú č š ƛ ə ɬ ʔ ʕ ʷ ́ ̌ ̓
̕ ̣ ᶿ ạ. St’át’imcets is written in the variant of the North American Phonetic Alphabet footnote 5
names, with the glottalization of a resonant as a comma above, U+0313, and the null object as Ø. The
gloss labels are ASCII capitals in the text layer.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 2 page-read
corrections. The text layer sets spaces inside words, wh ich and 200 5a, and the page text closes
the 181 lines the glyph positions contradict. A space the layer sets where the face or size changes,
EXCL get.forgotten, stays. The page itself prints some glosses run together, NTSDET and IPFVget, and
the table keeps them as printed.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 747
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
18160 distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     segmentation   an example tier broken into morphemes
         gloss          the morpheme gloss tier of an example
         translation    the English of an example
         speaker comment a speaker's own comment on an example, in their words
         cited form     a word of the language named in the prose, a note or a table
         cited affix    an affix named on its own
         root           a root named on its own
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
