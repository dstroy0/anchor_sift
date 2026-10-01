# Kelly_Huijsmans_McCarthy_ICSNL61-1.oracle.tsv

Extraction of Variation in the ʔayʔaǰuθəm determiner system by Rachel Kelly, Marianne Huijsmans and
Mary McCarthy, University of Alberta, ICSNL 61.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 535 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is ʔayʔaǰuθəm, spoken by the Tla’amin, Homalco, Klahoose and K’ómoks First Nations. The
speaker of the main task, and of (5) to (15), is Molly Harry, a mother-tongue speaker from Homalco,
and the translations marked (vt) are her own English. (16) to (19) are the late Freddie Louie's,
from Tla’amin: (16) is cited to Louie et al. 2025 and (17) to (19) carry his tag FL with a date. (i)
carries the tag EP.2024/03/08. Doreen Point, the late Marion Harry, Ochele (Betty Wilson) and
qaʔaχstalɛs (Dr. Elsie Paul) are thanked in footnote 1, and the paper closes that footnote and §1.1
with č̓ɛč̓ɛhatanapɛšt. (1) to (3) are cited to Reisinger et al. 2021 and (4) to Huijsmans &
Reisinger 2025.

The who for each tier of an example is ʔayʔaǰuθəm. The who for a translation is the work cited on
its line, Molly Harry for a (vt) translation, and the three authors otherwise. The prose, the
tables, the contexts and the notes carry the three authors.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á í č š ƛ ǰ ə ɛ ɩ ɬ ʊ ʔ ʷ ̓ ̣
θ χ ᶿ. The gloss labels are Unicode small capitals in the text layer, as ᴄᴅᴇ.ᴅᴇᴛ, and several person
digits are U+1D7E3 and U+1D7E5, MATHEMATICAL SANS-SERIF DIGIT ONE and THREE, as 𝟣ꜱɢ. The page draws
them as small capitals and plain digits, and the table keeps the text layer's code points. The
orthography tier writes ᶿ, U+1DBF, for the raised theta of tᶿ, and the NAPA tier writes x̣ with
U+0323 where the orthography has χ. Glottalization is U+0313 throughout.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 3 page-read
corrections. The text layer breaks ʔayʔaǰuθəm after ʔayʔa on pages 1, 3, 14 and 16, and Sḵwx̱wú7mesh
after its S in footnote 9, and the page prints both whole. Those two are page-read corrections in
the residue check. (14) prints a raised θ after χaƛ̓ that the text layer also holds, and (7) sets
its second segmentation above its orthography, both read at 500 dpi and recorded as notations.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 349
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
13046 distinct tokens in the paper, 0 language tokens are held by no row.

where    the paper's locator: the title, the front matter, a section, a footnote, an example
         line such as (3) line 2, the references, or all for a note about the whole paper
who      the language for an example tier and a cited form; the work cited on an example's
         line, or the speaker for a volunteered translation, for its English; the authors for
         the prose, the tables and the notes
kind     transcription  an example tier in the orthography
         segmentation   an example tier broken into morphemes
         gloss          the morpheme gloss tier of an example
         translation    the English of an example
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
         damage         a string the page prints that is itself an error, transcribed as printed
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
