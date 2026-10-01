# Hall-Luntzlara-Mellesmoen-Reid-ICSNL60.oracle.tsv

Extraction of The Long Schwa Paper: Stressed Schwa Epenthesis in nɬeʔkepmxcín by Brent Hall, Noah
Luntzlara and Gloria Mellesmoen, University of British Columbia; Danica Reid, Simon Fraser
University, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 1733 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

Every example is nɬeʔkepmxcín, and the who of each form, gloss and root is the language. The who of
a translation is the source its example cites: the speakers who worked on the project, Bev Phillips
(BP), Marty Aspinall, c̓úʔsinek (CMA), and Bernice Garcia, kʷaɬtèzetkʷuʔ (KBG), or Thompson and
Thompson's grammar (1992) and dictionary (1996), written T&T, or the two papers of Hall and
Phillips. The words of the figures of Appendix B carry the speaker who produced them. Bernice
Garcia's introduction of herself in footnote * is hers.

The analysis of Section 3 is the authors': the constraint definitions, the rankings and the sixteen
tableaux. In a tableau the input and the optimal candidate, marked ☞, are the language's; the losing
candidates are forms the analysis builds and carry the authors. Each candidate's gloss gives its
violation marks under the constraint heading each column, read off the glyph positions of the page.
The prose, the headings and the notes carry the four authors.

THE LETTERS

Outside the paper's English the engine found these letters and marks: µ á è é í ó ú ń ƛ ə ɬ ʔ ʕ ʷ ́
̓ ̣ ͜ μ ṣ. The forms are in the orthography of Thompson and Thompson (1992; 1996), with the
underlying representation between slashes and the surface form between square brackets, a period
between syllables. An acute marks accent in the input and primary stress in the output; a subscript
number ties an underlying segment to its surface correspondent, as n1 and e1; a subscript N marks a
nucleus, as nN; a tie bar under two letters marks a diphthong, as í͜yN; µ marks a mora in the
tableaux; a dot below marks a retracted vowel or consonant.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 14 page-read
corrections. The subscripts, N and the correspondence numbers, come through the text layer as
full-size letters and digits and are kept that way. The violation marks of tableaux (69), (72) and
(73) are partly in the Symbol font, U+F02A and U+F021 in the text layer, read as * and ! at 200 dpi;
the column each mark stands in is read off the glyph positions. The bold of the stressed syllables
in the tableau candidates does not come through the text layer. The layer doubles the acute of tí͜y,
sets every printed hyphen of the phonological notation as a soft hyphen, and puts spaces inside
words after a vowel with two marks (petə̣́leʔ) and before a mora (kə́µɬµpµ); all are repaired. The
italic face of footnote 25 and page 33 prints no dot below the stressed schwa of petə̣́leʔ,
stə̣́nwn, sxʷə̣́seʔ and sxʷsə̣́l̓ec, where the text layer has it, and the dot is kept as typed. The
page prints its broken cross-references to candidates, (69)(69), and numbers two figures B10; both
are kept.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 1059
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
20072 distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     transcription  an example tier in the orthography
         phonemic       an example tier in a phonemic alphabet
         gloss          the morpheme gloss tier of an example
         translation    the English of an example
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
