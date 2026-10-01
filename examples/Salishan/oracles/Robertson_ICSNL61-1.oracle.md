# Robertson_ICSNL61-1.oracle.tsv

Extraction of Good and bad news about Nicola Dene by David Douglas Robertson, PhD, consultant
linguist, Spokane, WA; Tk’emlúps te Secwépemc, ICSNL 61.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 324 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The Nicola forms in < > are the nineteenth-century spellings of Le Jeune (Kamloops Wawa 1895) and of
Teit, Dawson and Mackay as Boas (1895) printed them. Their who is Nicola. The third column of (4) is
Dakelh (Carrier), from Carrier Dictionary Committee 1974. The Salish forms set beside the Nicola
words in (5) to (12) are Nɬeʔkepmxcín, from Thompson & Thompson 1996 (footnote 17), and their who is
Nɬeʔkepmxcín. A form in the prose carries the language the paper names for it: Nsyilxcən from Somday
1980, St’át’imcets from Van Eijk 2013, Dakelh, Athabaskan, Chinuk Wawa.

The English glosses are the author's, taken from the sources named. The block quote on page 2 is Le
Jeune's, with J.M.R. Le Jeune as who. The prose, the notes and the references carry the author.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á é ê í ú ə ɬ ʔ ʕ ʷ ́ ̓ ̣ ΄ ḷ.
The Nicola spellings use the Roman alphabet of their collectors, with ΄ (U+0384, Greek tonos) for
Boas' stress mark, and â, ê, î, û, ä, ē and ā. The Nɬeʔkepmxcín forms write x̣́ for the uvular with
its dot below and acute, ə, ɬ, ʔ, ʕ and a dot under a vowel for retracted tongue root. • marks
length inside the brackets of an infix, s[x̣́a•].

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 7 page-read
corrections. The text layer sets a space inside Teit’s on page 1, St’át’imcets on page 2, petə́le(ʔ)
on page 3, s-/mələ́q=amxʷ on page 4, /tə̣́mɬ and LIGATURE on page 5, and <taki΄nktcîn> on page 7,
each read off the page render. On page 5 it also puts the acute of /tə̣́mɬ both before and after
that space. A root mark stands a space before its root in / ʔéyk and / ɬəq’=á[•q’]n’ek, and the
table keeps those rows without the slash. The first two columns of (4l) and (4m) wrap onto the next
line, and each row is joined back before it is split into cells.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 431
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
10260 distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     transcription  an example tier in the orthography
         translation    the English of an example
         cited form     a word of the language named in the prose, a note or a table
         cited affix    an affix named on its own
         root           a root named on its own
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
