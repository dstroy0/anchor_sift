# HannonICSNL60.oracle.tsv

Extraction of Prospective aspect in nɬeʔkepmxcín by Ella Hannon, University of British Columbia,
ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 1999 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is nɬeʔkepmxcín, northern Interior Salish, and the examples were elicited by the author
from three speakers footnote * names: Bernice Garcia, kʷaɬtèzetkʷuʔ (KBG), and Marty Aspinall,
c̓úʔsinek (CMA), of the Nicola Valley dialect, and Bev Phillips (BP), of the Lytton dialect. Each
example's tag gives the speaker, the dialect and whether the form was suggested (SF) or volunteered
(VF). Examples (1) and (2) come from recorded conversation between KBG and CMA.

The who for each tier of an example is nɬeʔkepmxcín. The who for a translation is the speaker or
speakers its tag names, and the English of a sentence a speaker rejected, marked Intended:, is Ella
Hannon's. A comment under an example is the tagged speaker's, and the comments printed as the first
line of the paragraph after (30), (38) and (44) name their speaker. Bernice Garcia's introduction in
footnote * and its English are hers. The prose, the headings, the denotations and the notes carry
Ella Hannon.

THE LETTERS

Outside the paper's English the engine found these letters and marks: Ø á è é í ó ú ƛ ɬ ʔ ʕ ʷ ́ ̓ ̣
ә ṣ ∅. The forms are in the orthography of Thompson and Thompson (1992; 1996). The segmentation
marks a clitic boundary with =, an affix with -, reduplication with ∼ and an infix with angle
brackets, cú<ʔi>et; square brackets hold the segments of a morpheme the surface form does not
pronounce, and ∅ is the null third person. # marks an infelicitous sentence. The glosses follow the
Leipzig conventions and footnote 2 lists the others; from Section 3 on xʷúy̓ is glossed PROSP.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 12 page-read
corrections. The page text was read by glyph rows, with the word spaces pdfium sets on tight
justified lines kept (of the, Section 2 presents). The text layer types the null sign as 0/,
repaired to ∅, and the denotation brackets of (22) and (49) as J and K, repaired to ⟦ and ⟧, read at
300 dpi. The superscript g and the subscript type <l,st> of a denotation are set on the line. (20),
(21), (23), (24), (29) and (30) print the letter Ø for the null sign, kept as printed. The page
prints the(in)felicity and anlysis in footnote 4 and theroetically in footnote 5, kept. Example (28)
sets its context with no Context: label.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 531
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
11978 distinct tokens in the paper, 0 language tokens are held by no row.

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
