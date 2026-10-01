# The engine in Python, in six parts

**Purpose:** Find the primitive you need without reading the whole tree, and know which part it belongs to before you add one.
**Scope:** `src/engine/python/{representation,partition,reference,measure,sift,oracle}/`, with `render/` and `instrument/` beside them

One construction runs through the six parts. Represent the object as points carrying values, fix a partition over those points, build the maximum entropy reference the partition allows, and read the departure from it. The sift kernel and the oracle sit either side, one discarding candidates and one supplying an answer from outside the sample.

| part             | what it holds                                                                                      |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| `representation` | any domain written as points carrying values, and the re-seatings that put one symbol in one place |
| `partition`      | the unit and the scale those points are read at                                                    |
| `reference`      | the maximum entropy background under the constraints the object supplies                           |
| `measure`        | the departure from that background                                                                 |
| `sift`           | the sound filter, a necessary condition over any index set                                         |
| `oracle`         | agreement with ground truth somebody else published                                                |

Every module here is a primitive. Two also carry a `main`: `representation/constants/naturals.py` prints the named constants to a count of places, and `instrument/english_sift.py` reads papers from the command line. What each one is for, run end to end on real corpora, is in `examples/` under the same six names. That split is deliberate: a worked example that other code imports stops being an example, and this tree spent a while with its most depended on module, at 32 importers, filed under `examples/` while the tooling reached into it.

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

Eight subjects have their own directories so far: `atom`, `constants`, `game`, `particle`, `picture`, `sound`, `structure` and `text`. All eight sit under `representation`, the only one of the six parts that knows a domain exists. `instrument/`, outside the six, knows text. `oracle` carries one subject, `language`, and its parent directory is deliberately empty. Everything downstream of representation sees points and values and cannot tell a painting from a paragraph. One instrument reads both.

## Nothing here writes to a stream

A primitive returns numbers. Printing them is the caller's, and an example that wants a table of results formats it in its own `main`. This is why `oracle.language.families.dravidian_check` hands back a dict of distances and verdicts instead of printing a paragraph itself.

The two mains above are the exceptions. Each opens standard output and writes to it, and `english_sift`'s `check` writes to the stream its main hands it.

## Where the parts touch

The parts are allowed to import each other and several have to. A transition web is a measure and the alphabet it is read over is a representation. A space filling curve is a partition and the exponent read along it is a measure. The split forbids one thing: a primitive kept in one part while its callers look for it in another. That was the state this replaced.

The one boundary that does not bend is `oracle`. Supervision is the only one of the three ways a partition is fixed that adds information the sample did not hold. Anything carrying an answer from outside belongs there. `FAMILY`, the language tree written from philology before any distance is computed, is an oracle table and not a measure constant.

## The output arm

`render/` is not one of the six. The six parts are the search; `render/` turns what the search saw into an image, as a sheet or a volume, and mirrors `src/engine/render/`. Its host arm is pure Python and shares no code with the C renderer. The two agreeing byte for byte is a check, run by `utils/test/python/render_test.py`. `render_raster` and `render_volume` prefer the device: where the C shared library is reachable they pass through the C dispatch, which renders on the CUDA arm when one is present, and where it is not they fall back to the pure Python host. Python owns no device path because the library ban forbids it one. The device is reached only through C.

## The instrument

`instrument/` is not one of the six either. It holds the language reading of theory/anchor_sift written once: `anchor_sift.py` carries its sections 1 to 4 (`squash`, `distance`, `self_distance`, `reading`), `corpus_gate.py` reads every corpus, with the purity check of its section 4.13, and `english_sift.py` finds the language in a paper by knowing English and taking what is left.

## Routes to the engine in C and CUDA

Six routes here mirror the engine at anchor_sift 1789287. Each shares no code with the engine and is not a binding for it. A grader under `utils/test/python/` runs both sides on the same inputs and prints each side's numbers, and where they disagree one of them has a defect. A grader that needs the device builds a probe under `utils/test/python/` that calls the engine's own entry points.

| Python route                                              | the engine it mirrors                                                                                      | grader                                                                         |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `render/host.py`, and `render_raster`, `render_volume`    | `src/engine/render/anchor_raster_*.c`, and the dispatch that prefers the device                              | `render_test.py`, byte for byte                                                |
| `representation/exact.py`, `scaled` and `measured`        | `anchor_exact_from_decimal`, `anchor_exact_from_measured` in `src/engine/arithmetic/no_rounding/exact_integer_decimal.c` | `exact_test.py`, text for text                                                 |
| `measure/shift_agreement.py`, `frame_shift`               | `shift_agreement_host` in `src/engine/analysis/shift_agreement/shift_agreement.c`                              | `shift_agreement_test.py`, count for count                                     |
| `measure/period.py`                                       | `period_read` and `period_draw` in `src/cu/engine/analysis/period/period_select.cu`                                      | `period_test.py` with `period_probe.cu`, line for line                         |
| `measure/periodic_energy.py`, the `energy_` functions     | `src/sims/cu/engine/analysis/art/periodic_energy.h`                                                                    | `periodic_energy_test.py` with `periodic_energy_probe.cu`, line for line       |
| `sift/anchors.py`, the functions under the kernel's names | `src/engine/nbody/anchor_sift/anchor_sift_*.c`, with its bench under `utils/bench/`                                | `sift_test.py` with `anchor_sift_probe.def`, count for count and read for read |

The rest of this tree is not graded against the engine.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
