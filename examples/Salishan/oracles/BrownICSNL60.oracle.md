# BrownICSNL60.oracle.tsv

Extraction of Clause typing and clitic linearization in Gitksan by Colin Brown, University of
British Columbia, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 7 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is Gitksan, Interior Tsimshianic, and the examples were elicited from four consultants,
named in footnote * and tagged by initials at the right of a translation: Barbara Sennott (BS),
Jeanne Harris, Vincent Gogag (VG) and Hector Hill (HH). Other examples are cited from Hunt 1993,
Forbes 2018, Brown et al. 2020, Matthewson 2024, Matthewson et al. 2022 and Rigsby 1986, and four
come from stories in Forbes et al. in prep., each tagged with its teller and title.

The who for each tier of an example is Gitksan. The who for a translation is the source its tag
cites, Forbes et al. in prep. for a story, and Colin Brown for an example tagged with a consultant's
initials. The comment under (60) is Vincent Gogag's. The prose, the headings, the displays and the
notes carry Colin Brown.

THE LETTERS

Outside the paper's English the engine found these letters and marks: ̱ ̲ ∅. Gitksan is written in
its practical orthography, with ’ for glottalization and the underlined g̲ and k̲ of the story in
(59), U+0332, beside the g̱ of (60), U+0331. The segmentations write the transitive vowel as @. The
gloss labels are ASCII capitals in the text layer.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 1 page-read
correction. The page text was read by glyph rows, a word space over 0.133 em, and a smaller gap
where a roman word meets an italic one. The trees of (35), (44), (47), (48), (50), (51) and (52) are
given one row for each depth of nodes. The reference to Huijsmans 2023 prints ʔayʔajuθəm, which the
text layer holds as PayPajuθəm, read at 600 dpi.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 469
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
11074 distinct tokens in the paper, 0 language tokens are held by no row.

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
