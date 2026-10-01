# Gilmour_ICSNL61.oracle.tsv

Hand extraction of Alignment of revitalisation techniques and technologies for Salish and
neighbouring languages by Ian Gilmour, Bezoku Limited, ICSNL 61.

Read off the paper by a person, not produced by any script. This file is the control: the reader
in corpus_script_extraction is checked against it, and where they disagree the reader is wrong
until someone reads the paper again and says otherwise.

WHOSE WORDS THESE ARE

The paper is Ian Gilmour's prose about Universal Dependencies and Salish, and it has no numbered
examples. Its forms of a language are few: syəyəhub in Lushootseed, the Interior Salish suffixes
*iča and *aɬča inside a quotation from Hinkson 1998, and one Abaza word in Cyrillic. The rest are
language names, the name kʷaɬtèzetkʷ, and titles in the reference list.

The who for each form is its language. The who for the four block quotations is the person
quoted: Steven Bird, Clarence Sloat, Mercedes Q. Hinkson and Michael Fortescue, and for the three
maxims of §3.1 it is Christopher Manning, to whom the paper attributes them. Every other row
carries Ian Gilmour, including paragraphs that quote a few words from another work, whose source
the gloss names.

THE LETTERS

The page draws the lateral of *aɬča, kʷaɬtèzetkʷ and Nɬeʔkepmxcín as the belted ɬ, U+026C. At
400 dpi it reads as ł, U+0142. At 3200 dpi the loop on the left of the stem shows, and the text
layer holds U+026C. The page raises the w of kʷ in kʷaɬtèzetkʷ, and the text layer holds a plain
w set superscript. The page wins, as it does in Barreiro_ICSNL61, and the table writes ʷ,
U+02B7. The Abaza word carries the palochka ӏ, U+04CF, twice. The page draws it as a vertical
stroke that cannot be told from l, and the table follows the text layer. Symbol note rows give
each of these.

THE PAGE AND THE TEXT LAYER

The forms are in NFC, as every table in the corpus is, and the reader normalizes the text layer
to NFC before it compares. The text layer holds the proceedings line of page 1 ahead of the
title. The comparison also collapses each run of white space to one space on both sides, because
the text layer sets two spaces after model. in §5 and after polysynthesis. in the Fortescue
entry.

Every form was looked up in the text layer, and every word of the text layer carrying a mark
outside ASCII was looked up in the table. Of 188 forms, leaving out the 11 notation and symbol
note rows, 9 are not found verbatim. Four are paragraphs or bullet points that run across a
page, at the ends of pages 1, 3, 4 and 5, where the text layer sets the page number inside them,
and on page 4 footnote 1 as well. The Alper entry runs from page 7 onto page 8 the same way. The other four hold
kʷaɬtèzetkʷ with the raised w: the second bullet point of §6, its citation, the name row and the
kʷaɬtèzetkʷ entry. Of 93 marked words in the text layer, 2 distinct words are not in the form
column: kwaɬtèzetkw, spelled with the plain w, and the bullet ●, U+25CF, which the table leaves
off seventeen bullet points.

The page has two errors, and each has a damage row transcribed as printed. §5 cites the
Fortescue quotation as Fortsescue, 2007:22, and the reference list gives the pages of Bird 2020
as 3504–351. Notation rows record the rest: §2 cites Sloat 1968 and the reference list has 1967.
Three works are cited and not listed, and five are listed and not cited. Three works with two
authors are cited with et al.

where    the paper's locator: the title, the footer, the abstract, a section, footnote 1, table 1,
         the references, or all for a note about the whole paper
who      the language for a form, the person quoted for a block quotation or the maxims of §3.1,
         and Ian Gilmour for the paper's prose, the table, the references and the notes on the page
kind     cited form     a word of a language named in the prose
         cited affix    a suffix named on its own
         place          a place name
         language       a language name
         note           a sentence, paragraph, bullet point, block quotation or table row of the
                        paper
         citation       a work named in the text
         reference      an entry of the reference list, whole
         heading, title, name
         notation       a note on how the paper sets something, or where the text and the
                        reference list disagree
         symbol note    a note on which character a mark is
         damage         a string the page prints that is itself an error, transcribed as printed
form     as printed, joined where the text layer breaks a paragraph across a page, with no
         footnote digits and no bullet
gloss    what the paper says the form is, then what the reader needs to know about the row

Only cited form and cited affix are the language. The stars of *iča and *aɬča are printed and
kept.
