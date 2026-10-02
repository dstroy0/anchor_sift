# Orior: a unified computational foundation

**Purpose:** Find an object's information entropy, and compile the program that measures it to any part.
**Scope:** the whole repository; [the site](https://dstroy0.github.io/orior/) holds the rest

[Setup](docs/setup.md) · [Using it](docs/usage.md) · [The algorithm](docs/method.md) · [The engine](docs/engine.md) · [Areas of research](docs/research.md) · [Licensing](docs/licensing.md)

Measure how far an object sits from the most disordered arrangement of its own parts.

That is the entire method. Every discipline in this theory is that one sentence with a different answer to what counts as a part: atoms in a cell, symbols in a corpus, bytes in a file, coordinates in a board layout. The reference is the maximum entropy arrangement of those parts, and the measure is the exact departure from it.

## What is here

- **There is no prior estimate, no training set, no model or neural net.** An exact reading never merges two states that differ. [The algorithm](docs/method.md)
- **A filter built from a subset never loses a true occurrence,** whatever picked the subset, whatever the alphabet is, and whether or not positions are ordered. Soundness is free; the reading is not. [The sift](docs/sift.md) · [Why the count is exact](docs/ENGINE_PROOF.md)
- **The engine is optimized for no scale.** A size, a spacing, an order, a window, a width, a cell or a voxel count is never written into the machine. The machine is exact at every scale its words can hold, and where a word is too narrow it says so and never rounds. [The engine](docs/engine.md)
- **The objective is to compile a program written in gnascor to any language,** including one nobody has met, and prove it is the same program everywhere. Where the language is unknown, the engine derives it by asking. [The language: gnascor](docs/gnascor.md)
- **Measure the null under the same conditions as the effect.** An instrument that cannot be made to say no is not reporting anything when it says yes. [Areas of research](docs/research.md)
- **Every claim, what killed it, and what still stands.** Hypotheses and refutations are kept. [Workbook](theory/workbooks/orior)

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

It will always be free to use under the AGPL. A negotiated commercial contract and an educator's license are the other two; [Licensing](docs/licensing.md) says which governs a use. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
