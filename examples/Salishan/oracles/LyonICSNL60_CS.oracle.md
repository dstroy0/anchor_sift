# LyonICSNL60_CS.oracle.tsv

Extraction of Change-of-State in Nsyilxcn Roots and Beyond by John Lyon, University of British
Columbia – Okanagan, ICSNL 60.

Drafted by the anchor_sift engine and read against the page by a person. The engine sorted every
line of the text layer with english_sift.sorted_into, first against its English reference and the
pure corpus, then against this paper's own English laid over that reference. What the paper's
English did not account for became the example tiers and the cited forms. The alphabet was taken
from the characters that sit outside that English, and word_web.web() built 950 edges over the
language forms. A person then matched the context: who, kind and gloss for each row, the names,
places and languages, and the notations, read off the page. This file is the control. The reader in
corpus_script_extraction is checked against it, and where they disagree the reader is wrong until
someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The language is Nsyilxcn, Okanagan, and its examples come from Delphine Derickson-Armstrong and Dave
Michele of Westbank reserve, whom footnote * thanks by their nsyilxcn names too, ɬk̓mxnalqs and
c̓skʕáknaʔ. The tag at the right of each translation names the speaker, and VF in it marks a
volunteered form. Examples without VF were built by the author and judged by the speakers. The
speaker comments are signed DD and DM, and each is the speaker's it names. The paper spells her
Derrickson-Armstrong in footnote * and some tags, and him Dave Michel in some tags.

The who of every tier of a Nsyilxcn example and of every word of the tables is nsyilxcn, and the
translations and the column glosses are John Lyon's. The St’át’imcets examples (43b), (61), (66a),
(67), (70) and (71) and the table (64) are cited from Davis (in prep.) and Davis 2024, and their
tiers are St’át’imcets and their translations the source's; the consultant's comment on (43b) is
cited from Davis 2024:310. The English examples (12) and (13) are English. The definitions (21) are
Beavers and Koontz-Garboden's and Beavers', (53) is Kennedy and Levin's, and footnote 24's (ii) is
Beavers and Koontz-Garboden's. The other denotations, the prose, the contexts, the headings and the
notes carry John Lyon.

THE LETTERS

Outside the paper's English the engine found these letters and marks: á í ú ƛ ǰ ə ɬ ʔ ʕ ʷ ́ ̌ ̓ ̕ Δ
θ. The forms are in the Americanist orthography the Nsyilxcn literature uses, with the
glottalization of a consonant as U+0313, the uvular of x̌ with a caron, U+030C, and the raised w of
kʷ as U+02B7. The bullet • marks C2 reduplication and <ʔ> the inchoative infix. The denotations use
the double brackets ⟦ ⟧, U+27E6 and U+27E7, and some variables are set in mathematical italic in the
text layer, 𝑑𝑥𝑠 in (21a) and (54b). The gloss labels are ASCII capitals in the text layer.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, and the check puts the text layer through the same repair: the space the PDF
sets after a stacked mark is closed, except before an opening quote, then NFC, then 2 page-read
corrections. The text layer leaves a space after a glottalized letter, nik̓ •ək̓ for nik̓•ək̓, and
the table closes it. It runs DET into the noun after it in (46e) and (49a), DETwind and DETrope, and
the table puts the space back. The page prints totarget in Section 5 and intepretation in Section 6,
labels the last row of (9) h., and gives (8k) and (4b) no closing quote; each is kept. The trees of
Figures 1 to 6 are drawings the text layer does not hold, and only their captions are rows.

anchor_sift's hand_extraction/oracle_check.py was run on this table through residue.py, leaving out
the notation and symbol note rows, whose form is a label and not a string the paper prints. Of 1026
rows asked, 0 hold a form the repaired paper does not, and 0 a form the repair took out. Of the
23696 distinct tokens in the paper, 0 language tokens are held by no row.

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
form     as printed, joined where the text layer breaks a word, with no footnote digits
gloss    the page, the paper's English for a form, and what the reader needs to know

Only transcription, segmentation, phonemic, cited form, cited affix and root rows whose who is a
language are the language. The gloss tiers are the authors' analysis in English and labels.
