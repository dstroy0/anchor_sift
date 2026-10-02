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

Measure how far an object sits from the most disordered arrangement of its own parts. The reference is the maximum entropy arrangement of those parts, and the measure is the exact departure from it. Under the method sits a machine that does arithmetic with no floor, and the reading runs on it at any scale its words can hold.

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

<div class="grid cards" markdown>

-   :material-infinity:{ .lg .middle } __Arithmetic with no floor__

    ---

    Every number is an exact integer, any power of two wide. Nothing is rounded, and where a word is too narrow the machine says so. The floor in published work belongs to the format.

    [:octicons-arrow-right-24: The engine](engine.md)

-   :material-chart-bell-curve:{ .lg .middle } __The exact departure from entropy__

    ---

    Keep the counts, shuffle the arrangement, and the shuffle is the background. A filter built from any part of a pattern never loses a true occurrence.

    [:octicons-arrow-right-24: The algorithm](method.md)

-   :material-layers-triple:{ .lg .middle } __Vertical time compression__

    ---

    When every step is exact, a chain composes into one program before any input exists. It runs the same steps and removes the time between them.

    [:octicons-arrow-right-24: The stack](https://github.com/dstroy0/orior/blob/main/theory/workbooks/engine/vertical_time_compression.md)

-   :material-package-down:{ .lg .middle } __Compression near the floor__

    ---

    The floor is bounded by a ladder of exact bit counts, and the noise is read as exact functions of the data, never as a model. On 25 volumes of cell tracking the floor is 38.9 percent of raw and the engine writes 42.0.

    [:octicons-arrow-right-24: Compression](https://github.com/dstroy0/orior/tree/main/theory/workbooks/compression)

-   :material-chip:{ .lg .middle } __A register with no last digit__

    ---

    A program gives the same answer at every width. The emitter compiles itself to the same bytes, derives an unknown target by asking the part, and holds Chaitin's Omega between two exact numbers.

    [:octicons-arrow-right-24: Two crystals](https://github.com/dstroy0/orior/blob/main/theory/workbooks/engine/two_crystals.md)

-   :material-eye-outline:{ .lg .middle } __Laplace's demon, and its bill__

    ---

    Measured, the demon can refuse and cannot predict. An exclusion is permanent and free. There is no wall of principle in the way, only a bill in precision.

    [:octicons-arrow-right-24: Thought experiments](https://github.com/dstroy0/orior/tree/main/theory/thought_experiments/orior)

-   :material-clock-outline:{ .lg .middle } __What an input stops reaching is a clock__

    ---

    In SHA-256, no input reaches 214 of 256 positions at round seven, and the support closes near round 30 of 64. Nothing here claims a weakness in SHA-256.

    [:octicons-arrow-right-24: Instruments](https://github.com/dstroy0/orior/tree/main/theory/theory/instruments)

-   :material-arrow-expand-all:{ .lg .middle } __Precision spread__

    ---

    Given seeds to enough places, every quantity an exact identity reaches comes out to the same places. Two seeds, the square roots of 2 and 3, give 2,230,148 exact square roots up to 10^800.

    [:octicons-arrow-right-24: Precision](https://github.com/dstroy0/orior/tree/main/theory/theory/precision)

-   :material-scale-balance:{ .lg .middle } __Measure the null under the same conditions__

    ---

    An instrument that cannot be made to say no is not reporting anything when it says yes. Every bar is drawn, and every claim is kept with what killed it.

    [:octicons-arrow-right-24: Areas of research](research.md)

</div>

## What came back

<div class="orior-stats">
<div><strong>453 of 453</strong><span>crystal axes equal to the published edge as an integer, with no tolerance</span></div>
<div><strong>0 refused</strong><span>of 9,396,207 true occurrences on byte strings, and of 213,840 across one to eight dimensions</span></div>
<div><strong>1 of 200</strong><span>random borders as good as the dialect border it found, never given the labels</span></div>
<div><strong>383 of 383</strong><span>subtraction games that return their Grundy period</span></div>
<div><strong>13 to 22 times</strong><span>faster for seven hundred floors laid as one stack, every record equal</span></div>
<div><strong>792</strong><span>exact numbers that hold a state of 100 quantum bits</span></div>
</div>

[Licensing](licensing.md) says which license governs a use.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
