# Nater_ICSNL60_resonants.oracle.tsv

Extraction of Origins of Velar and Pharyngeal Resonants in Interior Salish: Chains of Events by Hank
Nater, Independent Linguist, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 527 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The paper traces sounds across the stages of Salish and Athabascan. Each sound cited on its own goes
to the stage the prose gives it: the resonants ɣ ʕ ʕʷ to Interior Salish, the continuants *ɣy *ɣ̌
*ɣ̌ʷ to Proto-Athabascan, from which the paper argues pre-Interior Salish copied them, and ḥ ḥʷ to
Columbian. The reconstructions (1) to (54) are Proto-Salish and pre-Interior Salish forms of Kuipers
2002 as Van Eijk & Nater 2020 cite them, and (e) to (h) Proto-Athabascan forms of Krauss & Leer
1981; each gloss's who is its source. The words of the lexical copies (a) to (d) and of footnote 2
go to the language the prose names before each.

The block quotations are Kinkade 1990, Seymour 2012 and Van Eijk & Nater 2020. The prose, the
tables, the tree of Figure 1, the headings and the notes carry Hank Nater.

THE LETTERS

Outside the paper's English the engine found these letters and marks: č ł š ƛ ǯ Ɂ ə ɣ ɬ ʕ ʷ ˑ ̌ ḥ.
The forms are in Americanist letters with IPA in square brackets: ɣ, ʕ, ʕʷ, ḥ with U+0323 dot below,
x̌ and ɣ̌ with U+030C caron for the uvulars, ʷ for rounding, ʔ and Ɂ for the glottal stop, ’ for
glottalization, and ˑ for half length. The approximants carry U+031E down tack below, ʕ̞. A star
marks a reconstruction and √ a root. Van Eijk & Nater 2020, quoted in §4, write γ with Greek gamma
and ʕw and ḥw with a plain w.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 5 page-read
corrections. The page's radical before seven roots, *√ɣ̌eˑn, Carrier √k’ʷaʔ and the others, is a
Symbol-font glyph the text layer holds as U+F0D6; the table writes √, read off a 300 dpi render. The
text layer spaces a letter from its marks, x̌ ʷ, and the page text closes them from the glyph
positions; the closing also runs together the members of four lists of sounds, ʕ̞ ʕ̞ʷ, ḥ ḥʷ, ḥ ḥw
and č č’, which the table keeps apart as the glyphs space them. Figures 2 and 3 are maps, and only
their captions are in the text layer; Figure 1 is a tree of text, one row a line. Footnote 9 falls
among the references on page 7 and is given its own where.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 361
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the 6848
distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     translation    the English of an example
         cited form     a word of the language named in the prose, a note or a table
         root           a root named on its own
         language       a language name
         name           a person or a proper name
         note           a paragraph, a context, a table, a footnote or a word that is not the language
         citation       a work cited in the text, or the tag at the right of an example
         reference      an entry of the reference list, whole
         heading        a section heading
         title          the title
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
