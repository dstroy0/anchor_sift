---
hide:
  - navigation
  - toc
---

<div class="orior-hero" markdown>

# orior

A unified computational foundation.
{ .orior-lede }

Measure how far an object sits from the most disordered arrangement of its own parts. The reference is the maximum entropy arrangement of those parts, and the measure is the exact departure from it.

[Setup](setup.md){ .md-button .md-button--primary }
[Using it](usage.md){ .md-button }
[Areas of research](research.md){ .md-button }

</div>

## Quick start

From a fresh clone, at the repository root:

```sh
utils/maint/engine/build_engine.sh                                  # the C engine: configure, build, run the graders
python examples/any_corpus/4_measure/collision_entropy.py           # a reading that knows nothing about its corpus
python examples/crystallography/6_oracle/proof_positive_control.py  # the positive control, against published cells
sh utils/maint/texbuild/build_theory.sh                             # the research papers
```

## Where to go

<div class="grid cards" markdown>

-   :material-sigma:{ .lg .middle } __[The algorithm](method.md)__

    ---

    The one construction every reading here is made of, the six parts it runs through, and what it does not do.

-   :material-download:{ .lg .middle } __[Setup](setup.md)__

    ---

    Get the engine building and the examples running, and know what each dependency is actually for.

-   :material-play-circle-outline:{ .lg .middle } __[Using it](usage.md)__

    ---

    Run the measure on something of your own, and know which of the six parts you are calling.

-   :material-chip:{ .lg .middle } __[The engine](engine.md)__

    ---

    What the engine is made of, what each part does today, the files it writes and the compression floor.

-   :material-code-braces:{ .lg .middle } __[The language: gnascor](gnascor.md)__

    ---

    The internal language, the query protocol every ask takes, and the transpiler.

-   :material-filter-variant:{ .lg .middle } __[The sift](sift.md)__

    ---

    A sound filter: no arrangement of anchors can lose a true occurrence. How to build it and what each grader answers.

-   :material-check-decagram:{ .lg .middle } __[Why the count is exact](ENGINE_PROOF.md)__

    ---

    The proofs that every probe set returns the exact count, that the planner cannot endanger it, and that the descent terminates.

-   :material-compass-outline:{ .lg .middle } __[What those proofs license](ENGINE_DIRECTIONS.md)__

    ---

    Searching an encoded corpus, searching by equality pattern, and planning from the census alone.

-   :material-flask-outline:{ .lg .middle } __[Areas of research](research.md)__

    ---

    What came back from crystals, a dialect border, games, the periodic table and a hash. [Where to start reading](research_papers.md) names the twenty research papers.

-   :material-account-voice:{ .lg .middle } __[The conditions of use](condition_of_use.md)__

    ---

    Whose language this is, what is held closed, naming a writer, the scan of a patient, systems you do not own, and how a result is reported.

</div>

The repository is at [github.com/dstroy0/orior](https://github.com/dstroy0/orior). [Licensing](licensing.md) says which license governs a use.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
