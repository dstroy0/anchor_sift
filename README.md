# Orior: a unified computational foundation

**Purpose:** Find an object's information entropy, and compile the program that measures it to any part.
**Scope:** the whole repository; [the site](https://dstroy0.github.io/orior/) holds the rest

[Setup](docs/setup.md) · [Using it](docs/usage.md) · [The algorithm](docs/method.md) · [The engine](docs/engine.md) · [Areas of research](docs/research.md) · [Licensing](docs/licensing.md)

Measure how far an object sits from the most disordered arrangement of its own parts.

That is the entire method. Every discipline in this theory is that one sentence with a different answer to what counts as a part: atoms in a cell, symbols in a corpus, bytes in a file, coordinates in a board layout. The reference is the maximum entropy arrangement of those parts, and the measure is the exact departure from it. Under the method sits a machine that does arithmetic with no floor, and the reading runs on it at any scale its words can hold.

## What is here

1. **Arithmetic with no floor.** Every number in the engine is an exact integer, any power of two wide, with no ceiling. Nothing is rounded, a tie is broken by name and never by noise, and where a word is too narrow the machine says so. Pi runs to ten million digits in under two minutes, checked against a second series that shares no arithmetic with the first. The floor in published work belongs to the format, and the format is a choice. [The engine](docs/engine.md) · [Precision](theory/theory/precision)

2. **The exact departure from entropy.** The reference is built out of the object itself: keep its counts, shuffle its arrangement, and the shuffle is the maximum entropy background, unique and with nothing chosen. Any part of a pattern is a necessary condition for it. A filter built from any subset therefore never loses a true occurrence: 9,396,207 on byte strings and 213,840 across one to eight dimensions, none refused. The part cannot rebuild the whole, and the exact compare stays. [The algorithm](docs/method.md) · [The sift](docs/sift.md) · [Delta Null](theory/theory/delta_null)

3. **Vertical time compression.** When every step is exact, a chain of steps composes into one program before any input exists, and a thousand steps cost an input what one step costs. Seven hundred floors laid as one stack run 13 to 22 times faster than the same floors run one after another, and every record comes out equal. It does not evaluate fewer steps. It removes the time between them. [Vertical time compression](theory/workbooks/engine/vertical_time_compression.md)

4. **Compression near the floor.** The floor of a file is its Kolmogorov complexity, which no program computes. The engine bounds it with a ladder of exact bit counts and reads the noise as exact functions of the data, never as a model. On 25 volumes of cell tracking the floor is 38.9 percent of raw, the engine writes 42.0, and every volume rebuilds voxel for voxel. [Compression](theory/workbooks/compression)

5. **A register with no last digit.** A register is an integer read upward from its lowest bit without end, and a word of any width holds its lowest bits. A program of sums, differences, products, exclusive or and AND therefore gives the same answer at every width. The emitter writes a program straight to PTX, C or SASS with each target's rules held as data, and compiles itself to the same bytes. Where a target's rules are unknown, the engine derives them by asking the part. By the invariance theorem, the cost of carrying a program to another language is a constant. Above it sits an ordered machine with orders over the integers and a limit stage, and on it a program holds Chaitin's Omega between two exact numbers, with its first two bits proved. [Two crystals](theory/workbooks/engine/two_crystals.md) · [The engine, part by part](theory/workbooks/engine/engine_table.md)

6. **Laplace's demon, and its bill.** Its eyes read agreement at every lag at once, and its arms are null draws. Measured, the demon can refuse and cannot predict: an exclusion is permanent and free, and building the inside back from the boundary is not. There is no wall of principle in the way, only a bill in precision. [Thought experiments](theory/thought_experiments/orior)

7. **What an input stops reaching is a clock.** A value that stops depending on an input is a hard fact the machine gets for free. In SHA-256, no input reaches 214 of 256 positions at round seven, the support grows by about nine a round, and it closes near round 30 of 64. Nothing here claims a weakness in SHA-256. [Instruments](theory/theory/instruments) · [Cryptography](theory/theory/cryptography)

8. **Precision spread.** Given seeds to enough places, every quantity an exact identity reaches comes out to the same places. Two seeds, the square roots of 2 and 3, give 2,230,148 exact square roots up to 10^800. [Precision](theory/theory/precision)

9. **Measure the null under the same conditions as the effect.** An instrument that cannot be made to say no is not reporting anything when it says yes. Every bar is drawn and never derived, and every claim is kept with what killed it. [Areas of research](docs/research.md) · [Workbook](theory/workbooks/orior)

## Quick start

From a fresh clone, at the repository root:

```sh
utils/maint/engine/build_engine.sh                                  # the C engine: configure, build, run the graders
python examples/any_corpus/4_measure/collision_entropy.py           # a reading that knows nothing about its corpus
python examples/crystallography/6_oracle/proof_positive_control.py  # the positive control, against published cells
sh utils/maint/texbuild/build_theory.sh                             # the research papers
```

On Windows PowerShell the engine builds with `utils/maint/engine/build_engine.ps1`. Python needs only `numpy` to start. [Setup](docs/setup.md) covers the rest.

## What came back

- **A crystal.** Across 453 axes drawn from the Crystallography Open Database, every recovered period equals the published edge as an integer, with no tolerance applied. [Crystallography](theory/theory/crystallography)
- **A dialect border.** Given Lushootseed forms and never the labels, the border comes back as the stressed schwa, southern, beaten by 1 of 200 random borders. [Salishan](theory/theory/Salishan)
- **A game.** Subtraction games return their Grundy period on 383 of 383 rows the detector can score. [Game Theory](theory/theory/game_theory)
- **The periodic table.** The row lengths, 8, 8, 18, 18, 32, 32, are read off the shell closures as the differences between them. [Particle Physics](theory/theory/particle_physics)
- **A quantum state.** Every amplitude is an exact number and never a float, and a state of 100 quantum bits is held in 792 of them, the squares of its amplitudes summing to exactly 1. [Exact quantum states](theory/theory/exact_simulation)
- **Nothing told.** An image read as a byte sequence returns its own width. A Vigenère cipher returns its key length.
- **A negative.** Collision entropy is invariant under permutation. No bound built from a histogram can separate a structured domain from a rearrangement of the same symbols. [Delta Null](theory/theory/delta_null)

[Areas of research](docs/research.md) holds the rest and every row that failed, and [Where to start reading](docs/research_papers.md) names the twenty research papers.

## Where to go

| page                                                    | what it covers                                                                    |
| ------------------------------------------------------- | --------------------------------------------------------------------------------- |
| [Setup](docs/setup.md)                                  | dependencies, building the C engine, building the search kernel with no build system |
| [Using it](docs/usage.md)                               | running the measure on a corpus of your own, the six Python parts, and a C call to the search kernel |
| [The algorithm](docs/method.md)                         | the one construction, the six parts, and why nothing is bounded or tuned          |
| [The engine](docs/engine.md)                            | the parts and their status, the files, the compression floor and the transforms   |
| [The language: gnascor](docs/gnascor.md)                | the internal language, the query protocol, and the transpiler                     |
| [The sift](docs/sift.md)                                | the search kernel, what each grader answers, and the renderer                     |
| [Why the count is exact](docs/ENGINE_PROOF.md)          | the proofs that every probe set returns the exact count                           |
| [What those proofs license](docs/ENGINE_DIRECTIONS.md)  | searching an encoded corpus, searching by equality pattern, and planning from the census alone |
| [Areas of research](docs/research.md)                   | what came back from each subject, and every row that failed                       |
| [Where to start reading](docs/research_papers.md)       | the twenty research papers, each with what it holds                               |
| [The conditions of use](docs/condition_of_use.md)       | language, closed material, naming a writer, the scan of a patient, systems you do not own |

## The speakers come first

**This work does not exist without the speakers.** Every table in the Salishan corpus opens with the person who spoke, before the linguist who published and before anyone who read it into a file.

These tools read a language and can put one back. **Every tool for language that comes out of this work requires a human to review its output.** That is a condition of use, not a recommendation.

The method reads people as well as languages: it can name a writer, it reads medical scans, and it measures systems that belong to someone else. [The conditions of use](docs/condition_of_use.md) cover each of those, and every one is a condition of use.

## Licensing

It will always be free to use under the AGPL. A negotiated commercial contract and an educator's license are the other two, and each binds whoever signs it to every condition of use; [Licensing](docs/licensing.md) says which governs a use. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
