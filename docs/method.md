# The algorithm

**Purpose:** State the one construction every reading here is made of, and what it does not do.
**Scope:** `src/python/`, `examples/`

Measure how far something sits from the most disordered arrangement of its own parts. (Shannon's information entropy)

That is the most basic construction.

Every domain is that sentence with a different answer to what counts as a part:

- atoms in a cell
- symbols in a corpus
- bytes in a file
- coordinates in a board layout

The reference is built from the object's own parts. There is no prior to estimate, no training set, no model, and no neural net representation of the domain.

Building a reference by maximizing entropy under the constraints the object supplies is Jaynes's principle. The departure from it is the free energy above equilibrium.

## The six parts

The basic construction, Identity:Null Permutation, runs through all six parts. Represent the object as points carrying values, fix a partition over those points, build the maximum entropy reference that partition allows, and read the departure from it. The sift and the oracle sit either side, one discarding candidates and one supplying an answer from outside the sample.

| part             | what it does                                                                                       |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| `representation` | any domain written as points carrying values, and the re-seatings that put one symbol in one place |
| `partition`      | the unit(s) and the scale those points are read at                                                 |
| `reference`      | the maximum entropy background under the constraints the object supplies                           |
| `measure`        | the departure from that background                                                                 |
| `sift`           | the sound filter, a necessary condition over any index set                                         |
| `oracle`         | agreement with ground truth that somebody else published                                           |

Each part is an import name in [`src/python/manifest.tsv`](https://github.com/dstroy0/orior/blob/main/src/python/manifest.tsv), beside `instrument` and `render`. One row a name: the name a program imports, and the path under `src/python/` that answers it. A program puts `src/python/` on its path and imports `manifest` first. Everything downstream of `representation` sees points and values and is blind to what an object is. One instrument reads both. Seven subjects have their own directories under `representation`, the only part that knows a domain exists: `atom`, `game`, `particle`, `picture`, `sound`, `structure` and `text`. `representation.constants` derives the natural constants, each by two routes agreeing.

[`src/python/README.md`](https://github.com/dstroy0/orior/blob/main/src/python/README.md) is the map. [`examples/`](https://github.com/dstroy0/orior/tree/main/examples) runs the same six names end to end on real corpora, one stage directory per part.

## No bounding, no tuning

The method picks no tolerance, no threshold, and no parameter by judgment. Bounding is choosing a cutoff to make a result come out the way it was expected to. It is the failure this work is built to avoid, and it is not permitted anywhere in it.

Every comparison is exact integer arithmetic. The engine holds no floating-point value, and there is no rounding to hide a chosen bound inside. The null a departure is measured against is drawn by permuting the object's own parts, never computed from a formula that could be tuned. Where a reading appears to need a cutoff, the cutoff is swept and the reading is reported across the whole sweep, as a curve. A positive control runs beside every negative result, because a negative result with no positive control has measured nothing.

A number picked to make a result come out is not a measurement. This work does not carry one, and a contribution that adds one does not land.

## The detector and the measure are not the same reading

The engine carries many readers, one per file under [`src/python/engine/analysis/measure/`](https://github.com/dstroy0/orior/tree/main/src/python/engine/analysis/measure) and [`src/python/engine/analysis/reference/`](https://github.com/dstroy0/orior/tree/main/src/python/engine/analysis/reference), and the examples run each on a corpus. Two of them are mistaken for each other more than any others, and reporting one as the other is an error.

The shift agreement detector reads a period or an offset, from how often a shift agrees with itself. The permutation null measure reads how far an object sits from a shuffle of its own parts, and its bit form reads the exact invariances that survive the shuffle. A number from one is not a number from the other.

What each reader has and has not been shown to do is in the workbook, row by row, including the rows that failed. Read it before quoting any reading. The one reading whose answer came from outside this work is the crystal cell edge, recorded under [Areas of research](research.md).

## What it knows

Nothing. There is no model, no training, no corpus of examples, no prior. It has no knowledge of language, chemistry or images and never acquires any. It computes one distance and every result came out of that.

It runs on human timescales: seconds on a laptop against a database somebody else published. Its reach is unbounded, because it assumes nothing about the domain and needs only that the object is not already at maximum entropy. Every single reading is finite and carries a stated floor. Where the floor is not cleared, the honest answer is that nothing was read. [Reading the result](usage.md#reading-the-result) says what a floor is.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
