# Mellesmoen_Trotter_ICSNL61.oracle.tsv

Extraction of The Long and Short of Subject Clitics in ʔayʔaǰuθəm by Gloria Mellesmoen, University
of Victoria, and Bailey Trotter, University of British Columbia, ICSNL 61.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 371 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is ʔayʔaǰuθəm. Most examples are cited from Huijsmans 2023 and Watanabe 2003, and (14)
from Elsie Paul's stories, Paul in press. (18), (23) and (25) are volunteered forms tagged vf with
EP, FL or both: Elsie Paul and the late Freddie Louie, the two speakers footnote * thanks by name.

The who for each tier of an example is ʔayʔaǰuθəm. The who for a translation is the work cited on
its line, and the two authors where the line carries a speaker tag. The rules, trees and
derivations, the prose and the notes carry the two authors. =čən is Sechelt and =(ɬ)kan
St'át'imcets.

THE LETTERS

Outside the paper's English the engine found these letters and marks: µ č š ƛ ǰ ə ɛ ɩ ɬ ʊ ʔ ʷ ̓ θ χ
ω ᶿ ∅. The orthography tier writes ᶿ, U+1DBF, for the raised theta of tᶿ, and ɩ, U+0269, and ʊ,
U+028A, for lax vowels. The rules write µ, U+00B5 MICRO SIGN, for the mora, σ for the syllable and ω
for the prosodic word, and ⇔ between a feature bundle and its exponent.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 1 page-read
correction. The text layer of this paper runs the words of whole lines together and keeps the column
gaps of the examples, and the glyph positions, read with pypdfium2, keep the spaces of the prose and
lose the gaps of the examples. The source here takes each line from whichever of the two holds more
spaces. 106 lines came from the glyph positions. Page 17 prints In press. χʷaχʷaǰɩm with a space
both extractions lose, read at 400 dpi and entered as a page-read correction.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 375
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
10998 distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     transcription  an example tier in the orthography
         segmentation   an example tier broken into morphemes
         gloss          the morpheme gloss tier of an example
         translation    the English of an example
         rule           a line of a rule, a derivation or a tree the authors display
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
