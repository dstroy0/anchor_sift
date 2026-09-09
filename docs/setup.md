# Setup

**Purpose:** Get the engine building and the examples running, and know what each dependency is actually for.
**Scope:** `src/engine/`, `examples/`, `maint/`, `data/`.

Nothing here needs a GPU, a service, or a network connection except the fetchers, and those are named below.

## Python

Python 3.9 or newer. Developed on 3.14.

```sh
python -m pip install numpy
```

The measure, the reference and every example that reads a corpus you already have need nothing beyond that. The rest are per-tool and each one says so when it is missing:

| package | what needs it |
|---|---|
| `numpy` | the engine, and 75 call sites across the tree |
| `pypdf` | reading papers, `data/salishan/get_papers.py --convert` |
| `requests` | the corpus fetchers under `data/fetch/` and `get_papers.py` |
| `matplotlib` | the corpus derivation figure |
| `soundfile` | the sound representation, which reads recordings |
| `Pillow` | reading an image as a byte sequence |

Install what a tool asks for when it asks. A missing package is reported by name with the install line, and the rest of the tree keeps working.

## The C engine

A C11 compiler and CMake. Ninja is the generator used here; a bare `cmake` picks NMake on Windows and fails.

```sh
cmake -S src/engine/c -B build/engine_c -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/engine_c
```

That produces the benches. Start with `build/engine_c/bench_lattice`.

`src/engine/c/sift/anchor_sift.c` compiles on its own with no build system at all, if you only want the search kernel.

## The books

LuaLaTeX, from TeX Live or MiKTeX. The build runs it twice per book, because the table of contents is written on the first pass and read on the second.

```sh
sh maint/book/build_theory.sh
```

PDFs land in `build/theory/<book>/main.pdf`. One book on its own:

```sh
sh maint/book/build_theory.sh workbook
```

The build fails if a book drops a glyph. That is deliberate: these books set Salishan orthography, and a missing character is a silently wrong page.

## Corpora

None are in git. `examples/` takes a corpus path as an argument, so anything you already have works.

To build the language corpora this work measured, the fetchers under `data/fetch/` pull from public archives:

```sh
python data/fetch/fetch_parallel_corpus.py
python data/fetch/fetch_treebanks.py
```

Each one names its source and writes under `build/corpora/`.

The Salishan papers come from the ICSNL archive:

```sh
python data/salishan/get_papers.py
```

The hand extractions are not fetchable. They are transcribed out of published papers and live in a closed repository, described in [Research](research/index.md). Everything that does not read a paper or a table runs without them.

## Checks

```sh
python maint/prose/docs_check.py      the register check over every document and comment
python maint/catalog.py --check       every example carries its catalog number
python maint/catalog_verify.py        where an example's description and its code disagree
python maint/write_survey.py          every file write in the tree, and where it lands
```

Four more gates run against the two closed repositories and say so and stop without them: `maint/corpus_manifest.py`, `maint/verify_private_sync.py`, `maint/speech_gate.py` and `maint/citations.py`. Each takes `--bypass`, and `ANCHOR_SIFT_BYPASS=1` carries that into a commit hook.

`.githooks/pre-commit` runs the first of these. Turn it on once per clone:

```sh
git config core.hooksPath .githooks
```

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-09
