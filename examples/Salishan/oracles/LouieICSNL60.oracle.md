# LouieICSNL60.oracle.tsv

Extraction of niniǰɛ ʔəkʷ χʷɛƛ̓ay, ƛ̓aɬəm, hega ɬəlkælɛ, niniǰɛ q̓ʷaq̓ʷθəms təsqanaməs ‘Mountain
goats, salt, and bullets’: A historical narrative told by late Freddie Louie by Freddie Louie,
Tla’amin Nation; Henry Davis, University of British Columbia; Laura Griffin, University of Toronto;
Marianne Huijsmans, University of Alberta; Gloria Mellesmoen, University of Victoria; Daniel K. E.
Reisinger, University of British Columbia; Bailey Trotter, University of British Columbia, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 1457 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is ʔayʔaǰuθəm, a.k.a. Comox-Sliammon, Central Salish, and the paper is one narrative
told by Freddie Louie of the Tla’amin Nation on May 17, 2016, with Elsie Paul, recorded,
transcribed, translated and glossed by the seven authors, Freddie Louie first among them.

A turn as said, in Section 2.1, and the words of a line as said, in Section 2.3, are the speaker's:
Freddie Louie for F and Elsie Paul for E, with the English they switch into kept in place. A line of
Section 2.3 said in English only is the speaker's too. The segmentation and gloss lines carry
ʔayʔaǰuθəm, and the English of Section 2.2 and of each glossed line is the authors' translation. The
cited words of Section 1, the prose, the headings and the footnotes carry the authors.

THE LETTERS

Outside the paper's English the engine found these letters and marks: æ í č š ƛ ǰ ə ɛ ɩ ɬ ʊ ʔ ʷ ́ ̌
̓ θ χ ᶿ. The line as said is in a practical orthography that writes what Freddie and Elsie say: ɛ,
ɩ, ʊ and æ for lowered and centralized vowels, o, χ for the uvular fricative, ǰ, č, θ, ɬ, ƛ̓ and the
superscript ᶿ of t̓ᶿ. The segmentation writes the underlying forms in a phonemic orthography, i, ə,
u and a for the vowels and x̌ for the uvular, θɛqɛtəm over θiq-it-əm. Affixes take a hyphen, clitics
=, portmanteaus +, infixes angled brackets, reduplication ∼, and an elided segment square brackets,
təq-ipa[n]-t-əm=k̓ʷa.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 13 page-read
corrections. The glossed lines set each word over its segmentation and gloss, read here by glyph
rows at a 0.112 em word space; the text layer, which sets each column on lines of its own, settled
the tokens the rows read differently, cedar.shakes, NEG ???, <STAT>, and the ‘ of ‘And, which the
glyph stream puts after the A. (101) prints Freddie's words as said in quotes. (56) and (76) print
no time. A footnote mark on a word, gɩǰɛ.2, is noted in the gloss; after a dash, na—6 and hiɬ-10, it
stays on the word. Footnote 13 prints sәnpoliyan with a Cyrillic ә.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 519
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the 7404
distinct tokens in the paper, 0 language tokens are held by no row.

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
         reference      an entry of the reference list, whole
         heading        a section heading
         title          the title
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
