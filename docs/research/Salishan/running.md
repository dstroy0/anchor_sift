# Running the scripts

**Purpose:** Go from an empty checkout to every corpus, check and sift result in this directory, without owning the archive first.
**Scope:** `tools/dev_env/Salishan/`

Run from the repository root. Everything writes under `build/`.

## Start here

```
python -m pip install pypdf pypdfium2 requests numpy soundfile
python tools/dev_env/Salishan/get_papers.py
```

That fetches the eleven papers the readers need and writes `build/papers/<name>.txt` for each. Nothing else in this directory works until it has run, and it is the only step that touches the network. `pypdfium2` renders a page to an image, which two of the eleven papers need and the other nine do not. `numpy` and `soundfile` are for the sound representation and nothing in the text pipeline imports them; `soundfile` is what decodes the mp3s in `build/audio/`, which are not fetched by this script.

`--all` fetches all 993 papers in the archive instead of the eleven. `--list` prints what would be fetched and stops. `--convert` converts PDFs already sitting in `build/papers/` and fetches nothing, skipping any PDF that already has text beside it. `--stem <name>` takes one paper by its filename.

A converted paper whose fonts renumber their codes and declare no `/ToUnicode` map gets a `.unfaithful` file written beside its text, naming those fonts, and the run says `NOT THE PAGE` on that line. The text is written anyway, because leaving a gap makes every later run try the paper again, and nothing downstream should read it as the paper. Six of the 146 PDFs on disk are in that class. `docs/research/Salishan/refs.md` names them and says what to do instead.

## Why there is a script for it

The instructions used to say to download the PDFs, convert each to text, and name the text after the PDF. Two of those three steps have a wrong answer that looks like a right one.

**The encoding.** `pdftotext` writes Latin-1 unless told otherwise, and Latin-1 has no ʔ, no ə and no ɬ. A paper converted that way still opens and still looks like a paper, with the language taken out of it.

**The reading order.** Given `-enc UTF-8` the characters survive, and the page comes out in layout order, so a running header prints above the title it sits under and a two-column table interleaves. `pypdf` reads a page in the order the PDF stores it, which is what the readers were written against, and `get_papers.py` uses it. Converting `Mellesmoen_Kye_ICSNL61.pdf` gives 1462 lines identical, in order, to the copy in `build/papers/`.

The script identifies itself by name, purpose and address in its user agent. The archive answers a request carrying none with an HTML page instead of the file; its `robots.txt` disallows only `wp-admin`, `wp-login`, the cache and trackbacks.

## Order

Nothing after the fetch needs the network. The sift depends on the readers, because its second anchor is the corpus they produce.

```
1. get_papers.py       build/papers/*.txt
2. pdf2png.py          build/pages/<stem>/page_NNN.png
3. draft_page_text.py  build/papers/<stem>.page.txt
4. the eleven readers  build/corpora/*.txt, *.pure.txt, *.unclassifiable.tsv
5. oracle_check.py     the hand extractions against the papers
6. reader_check.py     the readers against the hand extractions
7. coverage_check.py   reads 4, reports missing tokens
8. english_sift.py     reads 4 for both anchors
9. sift_extract.py     reads 4, writes build/corpora/sifted/
```

Steps 2 and 3 apply only to a paper the fetch flagged `NOT THE PAGE`, which is two of the eleven. For the other nine the extracted text is what the page says and both steps are skipped.

## Where the tools are

```
tools/dev_env/Salishan/get_papers.py                         the archive
tools/dev_env/Salishan/pdf2png.py                            the page as an image
tools/dev_env/Salishan/draft_page_text.py                    the page as a first draft
tools/dev_env/Salishan/hand_extraction/                      the control
tools/dev_env/Salishan/anchor_sift/                          the algorithm
tools/dev_env/Salishan/corpus_script_extraction/             the eleven readers
tools/dev_env/Salishan/anchor_sift_algorithmic_extraction/   the sift applied
tools/dev_env/Salishan/sound_representation/                 the recordings as bits
```

Each script finds the repository by walking up to the tree holding `build/`, so they run from any working directory.

## The twelve readers

One per paper. Each takes no arguments and rebuilds that paper's corpus. Written `S/` for `tools/dev_env/Salishan/corpus_script_extraction/`.

```
python S/extract_garcia.py
python S/extract_hall_phillips.py
python S/extract_lafontaine_janzen.py
python S/extract_matthewson_redan.py
python S/extract_alexander_davis.py
python S/extract_mary_george.py
python S/extract_nater_bella_coola.py
python S/extract_lyon_priests.py
python S/extract_lindley_lyon.py
python S/extract_hilbert.py
python S/extract_mellesmoen_kye.py
python S/extract_robertson.py
```

Each prints its line counts, how many target-language forms reached the pure stream, and how many lines it could not sort. The two Lyon readers also report how many interlinear blocks read cleanly.

## The workflow the readers exist inside

A reader is not the source of the corpus. The hand extraction is, and the reader is graded against it. Written `H/` for `tools/dev_env/Salishan/hand_extraction/`.

```
python H/oracle_check.py
```

Checks each hand extraction against the paper it was read off, in both directions. A form written down that the paper does not hold is a typing slip. A word in the paper that no row holds is a row somebody skipped, which is what a person reading a thirty-seven page paper into a table actually produces. Both must be zero.

Two papers are checked against a drafted page text and the output line says so. For those, direction one measures the draft and not the table: a form the table holds and the draft does not is a place where a person read the page and a rule in `lyon_encoding.py` got it wrong. Direction two still means what it means everywhere else.

```
python H/reader_check.py
```

Checks each reader against the hand extraction. Grades whether it found each form, whether it says the same kind, and whether it says the same dialect. Kind is the one that decides the corpus. A rejected tableau candidate filed as a citation puts a form the paper's own analysis rejects into the pure stream, and nothing downstream asks again.

## When the text is not the page

`19-Lyon_ICSNL50_final-78` and `2013_Lindley_Lyon` are set in a font that renumbers its glyph codes and declares no map back to Unicode, so their `build/papers/*.txt` holds the font's alphabet and not what the page prints. `refs.md` has the detail, the other four papers in the same class, and why the damaged text is kept.

```
python tools/dev_env/Salishan/pdf2png.py 2013_Lindley_Lyon 1 70
python tools/dev_env/Salishan/draft_page_text.py 2013_Lindley_Lyon
```

The first renders each page to `build/pages/<stem>/page_NNN.png`. Arguments are the stem, the first page, the last page, and optionally a scale, which defaults to 3 and puts a 12pt body around 50 pixels tall, where a stacked diacritic stops being a guess.

The second writes `build/papers/<stem>.page.txt`, line for line with the extraction so a page of one is a page of the other. It is a draft, and `oracle_check.py` reads it in place of the extraction for these two papers, which makes it the thing being graded and not the thing that grades. The rules are in `lyon_encoding.py`. Two of them cannot be settled without looking at the page: which `w` is a labialized consonant, and which inserted space is a word boundary. `refs.md` names those and the four other classes the check keeps reporting.

Both of these papers' readers take that file too, and so does `coverage_check.py`. They swap `page_text.py` in for `font_repair.py` to do it, because applying the mapping to text it has already been applied to destroys the text. Steps 2 and 3 therefore have to run before step 4 for these two, and running the readers without them leaves the last drafted text on disk in the corpus.

## Checks

```
python S/coverage_check.py
```

Diffs every language token in each paper against the corpus built from it. Both sides go through the same repairs first. Expected result is 0 missing on all eleven. For the two papers named above it reads the extracted text, so 0 there means the reader got everything the font's encoding held, which is a weaker statement than it is for the other nine.

```
python S/font_substitution.py <damaged paper> <clean reference> [more]
python S/font_substitution.py 19-Lyon_ICSNL50_final-78 LyonICSNL60_Inch-2
```

Tests a candidate character mapping by counting how many damaged tokens become forms attested in a clean paper. Read the change between the two rates, not either one alone.

```
python S/case_delta.py
```

Matches the sifted output case-sensitively against the pure corpus. A form that matches only once case is folded is the same word written wrong, and the count of those is the formatting damage.

## The sift

Written `A/` for `tools/dev_env/Salishan/anchor_sift/` and `X/` for `tools/dev_env/Salishan/anchor_sift_algorithmic_extraction/`.

```
python A/english_sift.py --check
```

Calibrates against the control. Prints how the known-pure corpus and the known-English spans separate, under one anchor and under two.

```
python A/english_sift.py <paper stem> [more stems]
python A/english_sift.py 1983_Hilbert
```

Scores one paper's lines against English and prints the twenty English accounts for least. A stem is a filename in `build/papers/` without its extension.

```
python X/paper_language.py
python X/sift_extract.py
python X/language_check.py
python X/corpus_growth.py
python X/corpus_admit.py
```

The first reads which language each paper is about out of its own title and abstract. The second sorts every paper without a reader against both anchors and writes `build/corpora/sifted/`. The third asks whether the distributions agree with what each paper says it is about, with section 3 deciding whether the reading may be made at all. The last two print each corpus's split-half distance, support and entropy as it grows, and admit candidates in batches while the corpus stays on that curve.

## The sound representation

This one does not read `build/papers/` and nothing in the text pipeline depends on it. It reads the recordings.

```
python tools/dev_env/Salishan/sound_representation/binary_sound.py
python tools/dev_env/Salishan/sound_representation/binary_sound.py <stem>
```

Writes `build/sound/<stem>.bits.tsv`, one row per 10 ms frame: the time, a 24 bit segment field, and a 4 bit prosody field. With no argument it does every recording in `build/audio/`; a stem is a filename there without its extension.

What it prints is the delta from a flat distribution over each field, at 6, 8, 10, 12, 14 and 24 bits, with how many states each width reached. Read the narrow widths. A 24 bit field has 16.8 million states and the longest recording has 135 thousand frames, so the wide figure is about the frame count. `refs.md` has the measured numbers and the four facts about hearing the method is built on.

## What the modules are for

These are imported, not run.

| Module | Holds |
|---|---|
| `A/anchor_sift.py` | the method itself: squash, total variation, split-half, support, entropy |
| `A/english_sift.py` | the English anchor and the per-line screen built on it |
| `S/salish_marking.py` | the T and N marking convention, `tagged_spans`, `TEXT_SPACE`, `CAPS_RUN`, ligatures |
| `S/page_text.py` | what a reader needs where its source is the drafted page text: every repair a pass-through, and the language test asked on the orthography |
| `S/salish_unsorted.py` | the flag file, and what counts as a language token |
| `S/font_repair.py` | the Lyon substitution table and the three forms of applying it |
| `S/space_repair.py` | putting back together words the Lyon extraction split internally |
| `S/inserted_space.py` | closing the space a PDF leaves after a stacked diacritic |
| `S/mellesmoen_kye_repair.py` | the same, with a wider mark set that paper's two spaces allow |
| `S/mary_george_repair.py` | the same again, where the grave is glottalization and the acute is stress |
| `S/glyph_names.py` | the glyph names Robertson's extraction printed, read back as the characters they name |
| `S/line_breaks.py` | putting back a word that extraction broke across two lines, shared by that reader and the coverage check |
| `lyon_encoding.py` | the NimbusRomNo9L codes read as the orthography, for the drafted page text |
| `H/papers.py` | which hand extraction goes with which paper, its repair, and its marks |
| `sound_representation/perceived_sound.py` | a recording as bits: the log spaced bands, the audiogram, the shift invariant segment field, the prosody field, and the rotation that brings the sample to maximum entropy |

`TEXT_SPACE` is the one definition of what characters these orthographies are written with. `salish_unsorted.py` and `H/papers.py` each held their own copy of that union until the copies were noticed; both read it from `salish_marking.py` now, and a per-paper set is written as that plus what the paper adds.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-04
