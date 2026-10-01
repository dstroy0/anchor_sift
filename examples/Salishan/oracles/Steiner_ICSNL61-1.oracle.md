# Steiner_ICSNL61-1.oracle.tsv

Extraction of Locative Demonstratives in nɬeʔkepmxcín by Reed Steiner, University of British
Columbia, ICSNL 61.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 8646 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is nɬeʔkepmxcín. The examples come from the author's three consultants, Bev Phillips
(BP), c̓úʔsinek Marty Aspinall (CMA) and kʷaɬtèzetkʷuʔ Bernice Garcia (KBG), each tagged SF for a
sentence the author supplied or VF for one the speaker volunteered, with the date. A few come from
Thompson and Thompson 1996, Koch 2008b, Hall and Phillips 2024 and kʷałtèzetkʷ, Hannon and Stacey
2024. (96) is St’át’imcets and (97) ʔayʔaǰuθəm, both after Davis and Mellesmoen 2019.

The who for each tier of an example is the language. The who for a translation is the work cited on
its line, Bev Phillips where the tag carries VT, and the author where it carries SF or VF. A
consultant's comment is theirs. The formulas of §5 and §6.2 and their paraphrases, the trees, the
tables' heads and the prose carry the author.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á è é í ó ú ƛ ǝ Ǭ ǰ Ǽ ə ɣ ɬ ʔ
ʕ ʷ ́ ̌ ̓ ̕ ̣ ̨ ͋ α θ λ σ χ ⃗ ∅. The paper writes ɬ and sometimes ł for the lateral fricative,
kʷaɬtèzetkʷuʔ beside kʷałtèzetkʷuʔ, and c̓ beside c̕ for the glottalized c, c̓úʔsinek beside
c̕úʔsinek. The formulas write ⃗v for a vector, U+20D7 COMBINING RIGHT ARROW ABOVE, and σ for the
spatial trace.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 4 page-read
corrections. The text layer of this paper runs the words of 540 lines together. The source here
takes each line from whichever of the text layer and the glyph positions keeps more of the page's
spaces. The denotation brackets ⟦ ⟧ come out of the text layer as J and K, the frowning face of (73)
as h, and the pictograms of the iconographic variables as single glyphs of a picture font, σ(Ǭ) for
the basket. Pages 2, 3, 4 and 40 were read at 200 to 300 dpi for the spaces the page prints and the
text layer drops.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 2323
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
26684 distinct tokens in the paper, 0 language tokens are held by no row.

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
