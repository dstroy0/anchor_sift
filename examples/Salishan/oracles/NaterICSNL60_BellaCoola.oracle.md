# NaterICSNL60_BellaCoola.oracle.tsv

Extraction of Jargon and European Origins of some Bella Coola Lexicon by Hank Nater, Independent
Linguist, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 499 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The paper compares words across languages, and each cited form's who is the language the prose names
before it: BeCo (Bella Coola) from the author's dictionary, Nater 1990, and his 1972 field notes;
Coeur d’Alene, Tillamook, Lushootseed and Comox from Kuipers 2002; Chinook Jargon from CTGR 2011,
Zenk et al 2010, Shaw 1909 and Gibbs 1863; and Alsea, Chinook Proper, Quileute, South Wakashan,
Makah, Nootka, Upper Chehalis, Klamath, Molala, Tahltan, Tlingit, Haida, Heiltsuk, Nishga,
Oowekyala, Cree, French, Russian and Spanish as the prose cites them. A starred reconstruction goes
to the language it is the ancestor of, or to Proto-Salish.

The two block quotations are Kinkade 1990 and Kinkade 2005. Table 3 sets each word in four cells,
its gloss, BeCo, the Chinook Jargon form and its origin. The prose, the tables' captions, the
headings and the notes carry Hank Nater.

THE LETTERS

Outside the paper's English the engine found these letters and marks: ú ł ə ʷ ˑ ̩ β χ ḥ. The BeCo
forms are in the author's practical Americanist orthography, Nater 1990: ’ for the glottal stop and
for glottalization, written after the letter, t’ and k’ʷ, ł, ƛ, χ, ʷ for rounding, and a syllabic
sonorant with U+0329 where it is not predictable. Other languages keep their sources' letters: ǯ and
ʒ, γ, β, ɲ, ḥ, ˑ for half length, ˬ in /elˬnabo/, · in c’a·bap, and Russian in Cyrillic, баня.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 2 page-read
corrections. Figures 1 to 3 are maps, and only their captions are in the text layer. Table 2's heads
space the letters of OBSTRUENT and SONORANT apart and are kept as printed. Footnote 1 runs from page
3 onto page 4 and is joined. Table 3's last row carries footnote 4's mark on its gloss, and its
caption footnote 3's. The page's radical, which marks a root in √smiw, √t’uχ, √t’uḥʷ, √c’a and
√músmuski, and the bullets of §4.2 and §5 are Symbol-font glyphs the text layer holds in the private
use area, U+F0D6 and U+F0A8; the table writes them √ and ♦, read off a 300 dpi render. The ⬧ bullets
of §1.1 are in the text layer as printed.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 294
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the 6876
distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     transcription  an example tier in the orthography
         phonemic       an example tier in a phonemic alphabet
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
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
