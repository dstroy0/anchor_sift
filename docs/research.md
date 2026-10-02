# Areas of research

**Purpose:** Say what the construction has been pointed at, what came back, and which research paper holds each.
**Scope:** `theory/`, `examples/`, `evidence/`

Twelve subjects have staged pipelines under [`examples/`](https://github.com/dstroy0/orior/tree/main/examples). Seven have run end to end and agree: language, art, crystals, proteins, sound, source code and arbitrary corpora. Chemistry, game theory, cell tracking, molecules and particle physics are being brought to the same standard. The proofs that pin the numbers are under [`evidence/proofs/`](https://github.com/dstroy0/orior/tree/main/evidence/proofs). The same six parts test each other end to end and agree.

## What came back

**A crystal.** A crystal carries an answer somebody else wrote down before this instrument existed. No other control in this work does. Tile a published unit cell, carry every site as an exact integer, and score how well the arrangement agrees with itself shifted along one axis. The offset where agreement peaks is the cell edge. Across 453 axes drawn from the Crystallography Open Database, every recovered period equals the published edge as an integer, with no tolerance applied and no error left to average. [Crystallography](https://github.com/dstroy0/orior/tree/main/theory/theory/crystallography)

**A dialect border.** The instrument found a border it was never shown. Mellesmoen and Kye label every form they cite as northern or southern Lushootseed. Given the forms and never the labels, the term that carries the border comes back as the stressed schwa, southern, at 45 against 6 over the same concepts, beaten by 1 of 200 random borders. [Salishan](https://github.com/dstroy0/orior/tree/main/theory/theory/Salishan)

**A game.** Subtraction games return their Grundy period on 383 of 383 rows the detector can score, against periods computed by a separate exact routine, at a worst margin of 16 floors. The same detector returns a confident number on a sequence that has no period at all, and what it is reading there is the continued fraction of the sequence's slope. [Game Theory](https://github.com/dstroy0/orior/tree/main/theory/theory/game_theory)

**The periodic table.** The exclusion principle appears here as a count: the same domain-blind primitive that finds two elements on one crystallographic site finds two electrons in one state, and over all 118 elements it finds none. The row lengths, 8, 8, 18, 18, 32, 32, are read off the shell closures as the differences between them. [Particle Physics](https://github.com/dstroy0/orior/tree/main/theory/theory/particle_physics)

**A hash.** Folding the dependency matrix onto (input bit − output bit) mod 32 puts 4096 cells behind each number. With what every class shares taken out, the band that stands is residues 0, 6, 11, 25 and 31, and each is a named operation: the diagonal, the three rotation amounts of Σ1, and −1 mod 32 for the carry. What decays at one thirty-second per round is that shared part. Past round twenty-three the fold reads 2.09, 2.07 and 2.04 against a null peak of 2.63, finding nothing. [SHA-256](https://github.com/dstroy0/orior/tree/main/theory/theory/cryptography/sha256)

**Nothing told.** An image read as a byte sequence returns its own width. A Vigenère cipher returns its key length. A protein backbone returns bond lengths of 1.45, 1.52 and 1.33 against chemistry's 1.46, 1.52 and 1.33. None of them was told anything.

The workbook holds the rest, including every row that failed and why.

## Where to start reading

The research is twenty research papers under `theory/`. [Where to start reading](research_papers.md) names each one and what it holds.

## What is not here

The corpora, papers, audio and rendered pages run to about 1.9 GB and none of it is in git. `utils/maint/data/salishan/get_papers.py` fetches the papers from their archive, [`utils/maint/data/fetch/`](https://github.com/dstroy0/orior/tree/main/utils/maint/data/fetch) fetches the other corpora, and the tools rebuild the rest.

The hand extractions are forms transcribed out of published papers. The tables are those papers' text and not this work's to redistribute. They are not carried here. Everything that does not read a paper or a table runs without them.

## A note on how this is written

1. The workbook always keeps its own corrections.
    - Claims that were withdrawn stay on the page with the measurement that killed them.
    - A document recording only what survived is not evidence.
2. Several results are rediscoveries of published work, and where that is known the precedent is named.
    - Citation is ongoing, any corrections are appreciated and welcome, and attribution is critical.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
