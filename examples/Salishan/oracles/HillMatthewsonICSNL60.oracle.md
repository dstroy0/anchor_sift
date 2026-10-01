# HillMatthewsonICSNL60.oracle.tsv

Extraction of Gidaxan aa? Yagayt halaayin by Hector Hill, Gitsegukla Nation; Lisa Matthewson,
University of British Columbia, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 1 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is Gitksan, Interior Tsimshianic. The examples were given or judged by five fluent
speakers, tagged by initials: Vincent Gogag (VG), of Git-anyaaw, who speaks Giyaanimx; Hector Hill
(HH), an author, and Ray Jones (RJ), of Gijigyukwhla, who speak Gitsenimux; Jeanne Harris (JH) and
Barbara Sennott (BS), of Ansba'yaxw, who speak Gitxsanimx. (2) is cited from Rigsby 1986, and so is
footnote 5's (i).

The who for each tier of an example is Gitksan. The who for a translation is the authors', as the
English the speakers were asked about or gave a sentence for, and a cited example's is its source. A
comment is the speaker's its initials name, and Lisa and Hector under (11) and (14) are the two
authors. Hector Hill's own Gitksan, closing his introduction and the paper, is his. The forms the
prose cites are the italic runs of the page, glossed with the English the prose gives them. The
prose, the headings and the notes carry Hector Hill and Lisa Matthewson.

THE LETTERS

Outside the paper's English the engine found these letters and marks: . The forms are in the
practical orthography many community members use (Hindle and Rigsby 1973), with the apostrophe for
glottalization. The second line of an example breaks the sentence into its parts, = before a clitic
and - before a suffix; # marks an infelicitous sentence, ? and ?? a doubtful one, / two speakers'
forms, and square brackets in a gloss a pronoun the form elides.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC. The page prints
several cross-references as (7), [(6)] and 0 where a letter or a number is missing; they are kept as
printed. (9) labels Betty's line B: and Adam's three answers A1: to A3:, written here as (9A1) to
(9A3). (10) sets a paragraph between its number and its context. (14b) and (14c) have no line in the
orthography. Footnote * spells Jeannie Harris where page 3 and the prose have Jeanne Harris.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 586
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
13832 distinct tokens in the paper, 0 language tokens are held by no row.

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
         symbol note    a note on which character a mark is
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
