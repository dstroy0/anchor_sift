---
hide:
  - navigation
  - toc
---

<div class="orior-hero" markdown>

<div class="orior-title" markdown>

# orior

A unified computational foundation.
{ .orior-lede }

</div>

Orior finds the pattern in anything, from a crystal to a language to a file. It compares the thing with a shuffled copy of itself, and the pattern is what the copy lost. Every number is exact, with nothing rounded, guessed or trained.

[Setup](setup.md){ .md-button .md-button--primary }
[The algorithm](method.md){ .md-button }
[The engine](engine.md){ .md-button }
[The transpiler](gnascor.md#the-transpiler){ .md-button }
[Kolmogorov Complexity filetypes](engine.md#the-files){ .md-button }
[Areas of research](research.md){ .md-button }

</div>

## Where to go

<div class="grid cards" markdown>

-   :material-play-circle-outline:{ .lg .middle } __[Using it](usage.md)__

    ---

    Run the measure on something of your own, and know which of the six parts you are calling.

-   :material-code-braces:{ .lg .middle } __[The language: gnascor](gnascor.md)__

    ---

    The internal language, the query protocol every ask takes, and the transpiler.

-   :material-filter-variant:{ .lg .middle } __[The sift](sift.md)__

    ---

    A sound filter: no arrangement of anchors can lose a true occurrence.

-   :material-check-decagram:{ .lg .middle } __[Why the count is exact](ENGINE_PROOF.md)__

    ---

    The proofs that every probe set returns the exact count, and that the descent terminates.

-   :material-book-open-variant:{ .lg .middle } __[Where to start reading](research_papers.md)__

    ---

    The twenty research papers, each with what it holds.

-   :material-account-voice:{ .lg .middle } __[The conditions of use](condition_of_use.md)__

    ---

    Whose language this is, what is held closed, naming a writer, the scan of a patient, and systems you do not own.

</div>

## Quick start

From a fresh clone, at the repository root:

```sh
utils/maint/engine/build_engine.sh                                  # the C engine: configure, build, run the graders
python examples/any_corpus/4_measure/collision_entropy.py           # a reading that knows nothing about its corpus
python examples/crystallography/6_oracle/proof_positive_control.py  # the positive control, against published cells
sh utils/maint/texbuild/build_theory.sh                             # the research papers
```

## What is here

Some of this will read as too much. Nothing here asks to be believed: every result names the file that holds it and the run that checks it, every one was measured against a null that could have said no, and every claim the work took back is kept beside the measurement that took it back. Most of the parts are old, and they are named as old.

<div class="grid cards" markdown>

-   :material-infinity:{ .lg .middle } __Exact integers, from end to end__

    ---

    Every number is an integer of whatever width it needs. Nothing is rounded, and a value too wide for its word is refused instead of cut. A big number library holds the same integers; this engine never leaves them.

    [:octicons-arrow-right-24: The engine](engine.md)

-   :material-chart-bell-curve:{ .lg .middle } __The pattern is what a shuffle destroys__

    ---

    Keep the counts, shuffle the arrangement, and the shuffle is the background. A filter built from any part of a pattern never loses a true occurrence, and the exact compare stays.

    [:octicons-arrow-right-24: The algorithm](method.md)

-   :material-cube-outline:{ .lg .middle } __The number of dimensions is not in the state__

    ---

    The filter holds one bit for each alignment. Neither the alphabet nor the number of dimensions appears in it, and the same expression gives the cost from a line to an eight dimensional cube.

    [:octicons-arrow-right-24: The sift](sift.md)

-   :material-layers-triple:{ .lg .middle } __Exact steps join before any input exists__

    ---

    A chain of exact steps composes into one program and runs on the device as one. It runs the same steps, and what it removes is the time between them.

    [:octicons-arrow-right-24: The stack](https://github.com/dstroy0/orior/blob/main/theory/workbooks/engine/vertical_time_compression.md)

-   :material-package-down:{ .lg .middle } __Compression held to the noise of the camera__

    ---

    No program computes Kolmogorov complexity, and nothing here claims to. On 25 volumes of cell tracking the noise of the camera puts a floor at 38.9 percent of raw, and the engine writes 42.0.

    [:octicons-arrow-right-24: Compression](https://github.com/dstroy0/orior/tree/main/theory/workbooks/compression)

-   :material-chip:{ .lg .middle } __One program at every width__

    ---

    A program of sums, products, exclusive or and AND gives the same answer at every width. The emitter writes it to PTX, C or SASS, and where a rule of a target is not known it asks the part.

    [:octicons-arrow-right-24: Two crystals](https://github.com/dstroy0/orior/blob/main/theory/workbooks/engine/two_crystals.md)

-   :material-eye-outline:{ .lg .middle } __Laplace's demon, and its bill__

    ---

    Measured, a boundary can refuse and cannot predict. An exclusion is permanent and free, and finer detail costs precision that grows exponentially. There is no wall of principle, only that bill.

    [:octicons-arrow-right-24: Thought experiments](https://github.com/dstroy0/orior/tree/main/theory/thought_experiments/orior)

-   :material-clock-outline:{ .lg .middle } __What an input stops reaching is a clock__

    ---

    In SHA-256, no input reaches 214 of 256 positions at round seven, and the support closes near round 30 of 64. Nothing here claims a weakness in SHA-256.

    [:octicons-arrow-right-24: Instruments](https://github.com/dstroy0/orior/tree/main/theory/theory/instruments)

-   :material-arrow-expand-all:{ .lg .middle } __Precision spread__

    ---

    Given seeds to enough places, every quantity an exact identity reaches comes out to the same places. Two seeds, the square roots of 2 and 3, give 2,230,148 exact square roots up to 10^800.

    [:octicons-arrow-right-24: Precision](https://github.com/dstroy0/orior/tree/main/theory/theory/precision)

</div>

## What came back

<div class="orior-stats">
<div><strong>453 of 453</strong><span>crystal axes equal to the published edge as an integer, with no tolerance</span></div>
<div><strong>0 refused</strong><span>of 9,396,207 true occurrences on byte strings, and of 213,840 across one to eight dimensions</span></div>
<div><strong>1 of 200</strong><span>random borders as good as the dialect border it found, never given the labels</span></div>
<div><strong>383 of 383</strong><span>subtraction games that return their Grundy period</span></div>
<div><strong>13 to 22 times</strong><span>faster for seven hundred steps laid as one stack, every record equal</span></div>
<div><strong>792</strong><span>exact numbers that hold 100 quantum bits all 0 or all 1 together</span></div>
</div>

## What it does not claim

- It does not compute Kolmogorov complexity. It bounds a file from above, by writing it.
- It claims no weakness in SHA-256.
- It does not hold every quantum state in a few numbers. A general state of 100 quantum bits still needs 2^100.
- It is not a model and nothing in it is trained.
- Several results were found first by others, and where that is known the published work is named.
- The thought experiments hold ideas whose experiment cannot be built as written. They are kept apart from the results, and none of them is one.
