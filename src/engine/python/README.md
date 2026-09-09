# The engine in Python, in six parts

**Purpose:** Find the primitive you need without reading the whole tree, and know which part it belongs to before you add one.
**Scope:** `src/engine/python/{representation,partition,reference,measure,sift,oracle}/`

One construction runs through the six parts. Represent the object as points carrying values, fix a partition over those points, build the maximum entropy reference the partition allows, and read the departure from it. The sift kernel and the oracle sit either side, one discarding candidates and one supplying an answer from outside the sample.

| part | what it holds |
|---|---|
| `representation` | any domain written as points carrying values, and the re-seatings that put one symbol in one place |
| `partition` | the unit and the scale those points are read at |
| `reference` | the maximum entropy background under the constraints the object supplies |
| `measure` | the departure from that background |
| `sift` | the sound filter, a necessary condition over any index set |
| `oracle` | agreement with ground truth somebody else published |

Every module here is a primitive and none carries a `main`. What each one is for, run end to end on real corpora, is in `examples/` under the same six names. That split is deliberate: a worked example that other code imports stops being an example, and this tree spent a while with its most depended on module, at 32 importers, filed under `examples/` while the tooling reached into it.

## Reaching it

Nothing here computes where the repository is. A caller puts `src/engine/python` on the path and passes directories in, which keeps the engine from knowing anything about the tree it is checked out into.

```python
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.web import leave_one_out, web
from representation.text.corpus import load_language_texts
```

## Subjects and what is shared

Inside a part, anything that knows about one kind of thing goes in its own directory and anything shared across kinds sits in the parent. `measure/dispersion.py` reads any sequence of symbols and stays in `measure/`. `representation/text/corpus.py` knows what a publisher's line wrapping is and goes under `text/`.

The test is what the module would have to be told. A primitive that would need nothing changed to read a protein instead of a paragraph is shared. One that carries a fact about encodings, or about how long a whale call lasts, is a subject.

Four subjects have their own directories so far: `text`, `sound`, `picture` and `structure`. All four sit under `representation`, the only part that knows a domain exists. `oracle` carries one subject, `language`, and its parent directory is deliberately empty. Everything downstream of representation sees points and values and cannot tell a painting from a paragraph, so one instrument reads both.

## Nothing here writes to a stream

A primitive returns numbers. Printing them is the caller's, and an example that wants a table of results formats it in its own `main`. This is why `oracle.language.families.dravidian_check` hands back a dict of distances and verdicts instead of the paragraph three examples used to print from three copies of the same code.

## Where the parts touch

The parts are allowed to import each other and several have to. A transition web is a measure and the alphabet it is read over is a representation. A space filling curve is a partition and the exponent read along it is a measure. The split forbids one thing: a primitive living in one part while its callers assume it lives in another. That was the state this replaced.

The one boundary that does not bend is `oracle`. Supervision is the only one of the three ways a partition is fixed that adds information the sample did not hold, so anything carrying an answer from outside belongs there. `FAMILY`, the language tree written from philology before any distance is computed, is an oracle table and not a measure constant.

## The C implementation

`src/engine/c/` holds the sift as C11, with its own bench. It shares no code with this and is not a binding for it. The two implement the same construction and are checked against each other by agreeing on counts. Where they disagree, one of them has a defect.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
