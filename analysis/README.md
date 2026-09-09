# analysis

**Purpose:** Say what belongs in this directory and what does not, leaving a new script one obvious place.
**Scope:** `analysis/survey/`, `analysis/sound/`.

**Everything here reads a corpus through the engine and reports a number.** It uses `src/`, it does not extend it, and it writes nothing outside `build/`.

The rule against `examples/`: an example demonstrates the method on one corpus and is written to be read. A survey runs the method across everything to answer a question the books ask. Both read a corpus through `src/`, and the difference is who the output is for.

## survey

Questions asked across the whole tree at once, feeding sections of `theory/anchor_sift`.

| | |
|---|---|
| `gate_report.py`, `gate_sweep.py` | every corpus in the tree through the English gate, and what has been standing in the poles |
| `paper_slice.py` | one paper cut out of an extracted proceedings volume, so it can be read whole |
| `papers_probe.py` | where the same problem has been worked on, language by language |
| `read_length_stability.py` | replacing a statistic that grows with the amount of data read |

## sound

`binary_sound.py` writes the binary sound representation of every recording in `build/audio`, one row per 10 ms frame. The method is in `src/engine/python/representation/sound/perceived_sound.py`.

It reads any recording and knows no language. It sat in the closed corpus for a while on the reasoning that a faithful representation deserves the terms the recordings have, and that was the wrong lever: withholding a generic tool protects nothing, because whoever has audio can write one. What prevents casual misuse is that the corpus is not shipped, which leaves the hard part hard.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-09
