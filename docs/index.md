# anchor sift

**Purpose:** Find the page that answers how to build the library, call it, or rely on it.
**Scope:** `docs/`

| page | what it covers |
|---|---|
| [Setup](setup.md) | dependencies, building the C engine, building the search kernel with no build system |
| [Using it](usage.md) | running the measure on a corpus of your own, the six Python parts, and a C call to the search kernel |
| [Why the count is exact](ENGINE_PROOF.md) | the proofs that every probe set returns the exact count, that the planner cannot endanger it, and that the descent terminates |
| [What those proofs license](ENGINE_DIRECTIONS.md) | uses that follow from the proofs: searching an encoded corpus, searching by equality pattern, and planning from the census alone |

The repository is at [github.com/dstroy0/anchor_sift](https://github.com/dstroy0/anchor_sift). A tool for language built on this work requires a human to review its output. The [condition of use](https://github.com/dstroy0/anchor_sift#the-condition-of-use) states why.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
