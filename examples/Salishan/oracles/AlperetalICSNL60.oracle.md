# AlperetalICSNL60.oracle.tsv

Extraction of Towards low-resource text-to-speech generation for Indigenous Pacific Northwest
languages: The case of Haida X̱aad Kíl by Morris Alper, Independent Scholar, Samopriya Basu, Simon
Fraser University, Nathan Bennett, Future Ancestors Alliance, Ryan Kessler and S. Verlaine Ravana,
X̱aadas Kíl Ḵuyáas Foundation, and Wendy F. K’ah Skáahluwaa Todd, X̱aadas Kíl Ḵuyáas Foundation &
University of Alaska Southeast–Juneau, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 120 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The Haida of this paper is Áljuhl's (Erma Lawrence), from her recordings of 1974 and 2003 on
haidalanguage.org, parallel to her two books. The phrases cited in the prose, the six of Figure 1
and the fourteen test sentences of Figure 5 are hers or her books'. The IPA transcripts of Figure 3
are the authors', made by their grapheme-to-phoneme function.

The who for a Haida word is X̱aad Kíl. The prose, the table, the figures, the footnote and the
references carry the six authors.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á í ̱ Ḵ. The classic Alaskan
Haida orthography writes high tone as an acute, á é í ó ú, the epiglottals as underlined ⟨g̱ x̱⟩
(U+0331 COMBINING MACRON BELOW in the text layer), ḵ for the uvular, the apostrophe for
glottalization, hl and tl for the laterals, and ĝ x̂ in loanwords. The IPA transcripts write ꜛ
U+A71B before a high-tone vowel and ʡ ʜ for the epiglottals.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 1 page-read
correction. The text layer spaces inside words: pro pose, low -resource, P acific, trade -off.
page_text.py closed 79 lines from the glyph positions. The page sets ⟨g̱ x̱⟩ with a space, which the
inserted-space repair closes; that is the page-read correction. Figures 1 to 5 are pictures with no
text layer; each is written out in a symbol note, and the underlines of Figure 5 are uncertain at
the chart's resolution.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 182
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
13174 distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     cited form     a word of the language named in the prose, a note or a table
         cited affix    an affix named on its own
         place          a place name
         language       a language name
         name           a person or a proper name
         note           a paragraph, a context, a table, a footnote or a word that is not the language
         reference      an entry of the reference list, whole
         heading        a section heading
         title          the title
         symbol note    a note on which character a mark is
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
