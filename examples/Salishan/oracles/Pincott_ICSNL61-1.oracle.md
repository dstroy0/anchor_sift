# Pincott_ICSNL61-1.oracle.tsv

Extraction of Philology of Secwepemctsín: The Phonology of Studies on Shuswap by Ethan Pincott,
Simon Fraser University, ICSNL 61.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 698 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is Secwepemctsín. The oldest forms are Le Jeune's, from Studies on Shuswap, 1925: his
Latin spelling in ⟨ ⟩ and his Chinook Shorthand, romanized in { }. The author reconstructs their
pronunciation in [* ] and gives the modern word in the community orthography with its phonemic and
phonetic forms, from Kuipers 1974 and 1989.

Every one of those is a Secwepemctsín row, whatever its notation. The cognate columns and labels of
(1), (4), (8) and (13) give nɬeʔkepmxcín, St’át’imcets, nsyilxcən, Moses-Columbian, Kalispel,
Sḵwx̱wú7mesh and Proto-Salish forms, from the sources §4 names, and each carries its language as
who. The glosses, the reconstructions of sound laws, the prose and the notes carry the author.

THE LETTERS

Outside the paper's English the engine found these letters and marks: à á è é í ò ú č š ƛ ə ɣ ɬ ʔ ʕ
ʷ ́ ̌ ̓ θ. The community orthography writes 7 for the glottal stop, ll for ɬ and c for x, as Table 1
sets out, and the phonemic forms use ƛ̓ and x̌. Le Jeune's own spellings are ASCII with grave
accents. C₁ and C₂ carry U+2081 and U+2082 SUBSCRIPT ONE and TWO, and l̩ U+0329 COMBINING VERTICAL
LINE BELOW.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 17 page-read
corrections. The text layer sets a space before a letter from the IPA font, Secwepemcts ín for
Secwepemctsín nineteen times, St’ át’imcets, n ɬeʔkepmxcín, nsyilxc ən, / əy, əw/ and /xt éwméɬxʷ/,
and a space inside the closing bracket of ⟨s, j, sh, z ⟩. The page prints each whole, and each is a
page-read correction. The check also puts back the space the inserted-space repair closes before an
opening slash, t̓ /t̓/, where an even count of slashes before it on the line shows the slash opens a
form.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 845
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
15284 distinct tokens in the paper, 0 language tokens are held by no row.

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
         place          a place name
         language       a language name
         name           a person or a proper name
         note           a paragraph, a context, a table, a footnote or a word that is not the language
         reference      an entry of the reference list, whole
         heading        a section heading
         title          the title
         notation       a note on how the paper sets something, or where two printings disagree
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
