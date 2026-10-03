# Orior: a unified computational foundation

**Purpose:** Find an object's information entropy, and compile the program that measures it to any part.
**Scope:** the whole repository; [the site](https://dstroy0.github.io/orior/) holds the rest

[Setup](docs/setup.md) · [Using it](docs/usage.md) · [The algorithm](docs/method.md) · [The engine](docs/engine.md) · [Areas of research](docs/research.md) · [Licensing](docs/licensing.md)

Orior finds the pattern in anything, from a crystal to a language to a file. It compares the thing with a shuffled copy of itself, and the pattern is what the copy lost. Every number is exact, with nothing rounded, guessed or trained.

Some of what follows will read as too much, and a reader who has met claims like these before has every reason to doubt them. Nothing here asks to be believed. Every result names the file that holds it and the run that checks it, every one was measured against a null that could have said no, and every claim the work took back is kept beside the measurement that took it back.

Most of the parts are old, and they are named as old. The shuffle is a permutation null. Exact integers of any width are what every big number library holds. The new parts are an engine that never leaves exact integers, from the first read to the last bit written, and what came back when it was pointed at a crystal, a language, a digest and a camera.

## What is here, and how to check it

1. **Exact integers, from end to end.** Every number in the engine is an integer of whatever width it needs. Nothing is rounded, a tie is broken by name and never by noise, and a value too wide for its word is refused instead of cut. Pi to ten million digits, checked against a second series that shares no arithmetic with the first, is a test the engine runs on itself and not a record. [The engine](docs/engine.md) · [Precision](theory/theory/precision)

2. **The pattern is what a shuffle destroys.** Keep an object's counts and shuffle its arrangement, and the shuffle is the maximum entropy background, built from the object with nothing chosen. Any part of a pattern is a necessary condition for it, and a filter built from any subset therefore never loses a true occurrence: 9,396,207 on byte strings and 213,840 across one to eight dimensions, none refused. The part cannot rebuild the whole, and the exact compare stays. [The algorithm](docs/method.md) · [The sift](docs/sift.md) · [Delta Null](theory/theory/delta_null)

3. **The number of dimensions is not in the state.** The filter holds one bit for each alignment, alive or dead. Neither the size of the alphabet nor the number of dimensions appears in that state, and neither needs a bound. The same expression gives the cost from a line to an eight dimensional cube, set by one number, the collision entropy, and the two sizes. What still grows is the field: one bit for each place a pattern could sit. [Delta Null, Section 5.1](theory/theory/delta_null)

4. **Exact steps join before any input exists.** When every step is exact, a chain of steps composes into one program and runs on the device as one. Run one after another, each round of the chain pays to start, to wait and to carry its state through memory. Seven hundred of them laid as one stack run 13 to 22 times faster than the same seven hundred run one after another, and every record comes out equal. It runs the same steps, and what it removes is the time between them. [Vertical time compression](theory/workbooks/engine/vertical_time_compression.md)

5. **Compression held to the noise of the camera.** No program computes the Kolmogorov complexity of a file, and nothing here claims to. On 25 volumes of cell tracking, the noise read off the response of the camera itself puts a floor at 38.9 percent of raw. The engine writes them at 42.0, and every volume comes back voxel for voxel. [Compression](theory/workbooks/compression)

6. **One program at every width.** Sums, differences, products, exclusive or and AND read only the lowest bits of what they are given, and a program of them gives the same answer at every width. The emitter writes such a program to PTX, C or SASS with each target's rules held as data, and where a rule is not known it asks the part and keeps the answer. On the device, the part that writes the text writes its own text byte for byte. For the lambda calculus written in bits, two exact bounds put Chaitin's Omega below one eighth, and its first two bits are proved. [Two crystals](theory/workbooks/engine/two_crystals.md) · [The engine, part by part](theory/workbooks/engine/engine_table.md)

7. **Laplace's demon, and its bill.** The demon knows a boundary and computes what is inside. Measured, a boundary can refuse and cannot predict: a point it has excluded is excluded for good and for free, and no proper part of a pattern determines the rest. Reading finer detail off a boundary needs precision that grows exponentially as the detail gets finer. There is no wall of principle in the way, only that bill. The resemblance to physics is an analogy, and nothing here tests it. [Thought experiments](theory/thought_experiments/orior)

8. **What an input stops reaching is a clock.** A value that stops depending on an input is a hard fact the machine gets for free. In SHA-256, no input reaches 214 of 256 positions at round seven, the support grows by about nine a round, and it closes near round 30 of 64. Nothing here claims a weakness in SHA-256. [Instruments](theory/theory/instruments) · [Cryptography](theory/theory/cryptography)

9. **Precision spread.** Given seeds to enough places, every quantity an exact identity reaches comes out to the same places. Two seeds, the square roots of 2 and 3, give 2,230,148 exact square roots up to 10^800. [Precision](theory/theory/precision)

## What it does not claim

- It does not compute Kolmogorov complexity. It bounds a file from above, by writing it.
- It claims no weakness in SHA-256.
- It does not hold every quantum state in a few numbers. A state as plain as 100 quantum bits all 0 or all 1 together fits in 792, and a general state of 100 still needs 2^100.
- It is not a model and nothing in it is trained.
- Several results were found first by others, and where that is known the published work is named.
- [Thought experiments](theory/thought_experiments) holds the ideas whose experiment cannot be built as written. They are kept apart from the results, and none of them is one.

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
- **A quantum state.** Every amplitude is an exact number and never a float. The state where 100 quantum bits are all 0 or all 1 together is held in 792 of them, and the squares of its amplitudes sum to exactly 1. [Exact quantum states](theory/theory/exact_simulation)
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

## Licensing

It will always be free to use under the AGPL. A negotiated commercial contract and an educator's license are the other two, and each binds whoever signs it to every condition of use; [Licensing](docs/licensing.md) says which governs a use. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
