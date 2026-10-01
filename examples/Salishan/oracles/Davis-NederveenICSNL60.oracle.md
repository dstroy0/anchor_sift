# Davis-NederveenICSNL60.oracle.tsv

Extraction of Intransitive -t in Salish by Henry Davis and Sander Nederveen, University of British
Columbia, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 670 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The paper compares four Interior Salish languages: nɬeʔkepmxcín, Secwepemctsín and St’át’imcets of
the Northern Interior, and nxaʔamxcín of the Southern Interior. Each example's heading or list label
names its language, and the who of each tier and each listed word is that language. The unattributed
examples come from fieldwork with the speakers footnote * thanks: Carl Alexander, Qwa7yán’ak, for
St’át’imcets, whose are the Consultant's comments of (17) and (18a) and the consultant's translation
of (26); Bridget Dan, Julie Antoine and Garlene Dodson for Secwepemctsín; Bernice Garcia, Marty
Aspinall, Gene Moses and Bev Phillips for nɬeʔkepmxcín. Bernice Garcia's introduction of herself in
footnote * is hers. The word lists of (1), (4) and (5) cite Willet 2003, Kuipers 1974, Thompson and
Thompson 1992 and Kinkade 1989 where their labels say so.

Table 1 gives one reflex of each of three adjectives across the family; each cell's who is the
language that heads its row, by the traditional English name the table uses. The who for a
translation is the source its tag cites, and the authors for an untagged one. The formulas of
Section 3.2 and 3.3 are the authors', and the definition (21), the paraphrase under (23) and the
principle (30) are Kennedy and Levin's and Kennedy's. The prose, the headings and the notes carry
Henry Davis and Sander Nederveen.

THE LETTERS

Outside the paper's English the engine found these letters and marks: Ø á è é í ú č š ƛ ə ɣ ɬ ʔ ʕ ʷ
́ ̌ ̓ ̕ ̣ λ ḷ ạ ∅. The forms are in the Salish version of the North American Phonetic Alphabet,
footnote 2, with the glottalization of a resonant as a comma above, U+0313, and a null subject as Ø
or ∅. The gloss labels are ASCII capitals in the text layer.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 12 page-read
corrections. The text layer drops the dot below in nine words, most often leaving a space where it
was, sə̣́n<sə̣n>-t and ʔi=pə̣tạ́k=a among them, and sets the existential ∃ of the formulas as the
katakana ﾖ or the Latin Ǝ; each was read off the page at 600 dpi. The ɬɬ of kʷaɬɬtèzetkʷuʔ,
nɬɬeʔkepmxcín, peɬɬt and e=n-ɬɬeɬɬúxʷ, the space in scwew̓ xmx and the k̓̓ of footnote 20 are
printed so and kept.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 623
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
18926 distinct tokens in the paper, 0 language tokens are held by no row.

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
