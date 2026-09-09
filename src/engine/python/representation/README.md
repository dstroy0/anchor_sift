# Representation

**Purpose:** Turn a file of any kind into points carrying values, and know what that choice already costs before anything is measured.
**Scope:** `src/engine/python/representation/`

This is the only part of the engine that knows a domain exists. Everything downstream sees points and values and cannot tell a painting from a paragraph, so one instrument reads both.

A subject goes in its own directory and anything shared across subjects sits here in the parent.

| module | subject | what it holds |
|---|---|---|
| `bit_volume.py` | shared | `gray_bits`, `spectrum_gap`, `spectrum_excess`, `load_symbols`, for a corpus as points in a binary volume |
| `seating.py` | shared | `tightest`, `spread_of`. A canonical numbering, which keeps a reading from belonging to the numbering |
| `levels.py` | shared | `to_levels`. Real numbers held to the eight bits every corpus here is read at |
| `text/corpus.py` | text | `load_language_texts`, `load_by_source`, `fold_lines`, and the constants `CAP`, `LEAST`, `SKIP`, `SOURCES` |
| `text/symbols.py` | text | `utf8_shape` reads the encoding's own framing; `reseat` puts one symbol in one byte |
| `text/case.py` | text | `case_runs`, `long_run_share`, `run_profile`. Letter case as a second channel |
| `text/marks.py` | text | `strip_marks`, `every_mark`, `TONE`, `QUALITY`. Deleting one channel exactly |
| `text/clusters.py` | text | `aksharas`. The unit a writing system keeps its context in, which is not always the codepoint |
| `text/indic.py` | text | `collapsed`. Every Indic script read at one set of distinctions |
| `text/shared_alphabet.py` | text | `as_codes`, `WIDTHS`. One code space for a logographic language and a Celtic one |
| `text/treebank.py` | text | `read_sentences`, `read_sentences_both`, `capped`, `TOKEN_CAP`. Tokens that arrive with their reading |
| `sound/envelope.py` | sound | `envelope`, `symbols_per_second`, for a waveform re-sliced to the scale its units occupy |
| `picture/raster.py` | picture | `WIDTHS`, `as_grid`, `center_crop`, `as_points`. A row major file put back into its plane |
| `structure/protein.py` | structure | `fetch`, `atoms`, `density`, `backbone`, `walk`, `bonds`, `steps`. A deposited model read three ways |
| `structure/crystal.py` | structure | `parse_cif`, `voxel_grid`, `tiles_for`, `VOXEL`. A published cell tiled into the arrangement it describes |

`bit_volume`, `seating` and `levels` are in the parent because they read any corpus and know nothing about any of them. The subject directories know what a character encoding is, what a whale song unit is, what a decoder reported as a picture's width, or where a PDB record puts its coordinates, and each of those is knowledge about one kind of thing.

`structure/protein.py` keeps all three readings of a protein even though two of them failed, because the comparison between them is the finding. A grid discards the order and leaves a scatter of points in a box that is mostly empty. Alpha carbon steps keep the order and discard the bonds. The backbone walk keeps both, and every step of it is a bond whose length chemistry fixed before anyone measured it.

## What this part costs, before any measurement

Three of these four exist because a representation choice was made silently and then measured.

**The symbol width was never justified and it is not free.** Discrimination per bit read falls with width on every corpus: English gives 0.984 at one bit and 0.856 at eight, so the byte slice forfeits 15% and a sixteen bit symbol forfeits 40%. Soundness is indifferent to it, since the proposition never mentions a width. Cost is not.

**The width can be wrong by orders of magnitude.** The vocalizations were read at 8 kHz with one byte a sample, and a whale song unit runs one to three seconds, so the statistic read inside a single call and never saw how calls were arranged. At sample scale the animals and the people interleaved. At one symbol every 10 ms they separate without overlap.

**Folding line endings is right for prose and wrong for source.** A publisher chose a prose file's wrapping. A programming language ignores its own whitespace, so every break in one was put there by a person, and folding it discards the authored layer and moves H2 by 0.187 bits.

**Reading an abugida at the codepoint counts how its script decomposes.** A letter sequence works for an alphabet because that is where an alphabet keeps its context. In an abugida a consonant carries a vowel already and a virama binds one consonant to the next, so the unit is the whole cluster. Read as codepoints, four Dravidian languages came out further from each other than from Indo-Aryan, and the pair that separated most recently read as the widest distance in the matrix. `text/clusters.py` and `text/indic.py` are the two repairs, and alphabetic text passes through both unchanged.

## What does not belong here

Anything that chooses a scale is `partition`. Anything that scores is `measure`. The line is not always obvious: `bit_volume` supplies windows and does not choose their width, and `envelope` supplies a block size the caller states.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
