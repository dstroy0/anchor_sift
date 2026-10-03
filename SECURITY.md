# Security

**Purpose:** Know what this repository is responsible for, what it is not, and where to report something.
**Scope:** `src/c/engine/`, `src/c/transpiler/`, `src/cu/`, `src/python/`, `utils/maint/`, and the ports under `src/engine/`

## What is here

A search kernel in C11, a driver that times it, Python tools that fetch and read published papers, and two ports of one statistic. The new parts are an engine that never leaves exact integers, from the first read to the last bit written. When every step is exact, a chain of steps composes into one program and runs on the device as one. The emitter writes such a program to PTX, C or SASS with each target's rules held as data, and where a rule is not known it asks the part and keeps the answer. There is no server, no daemon, no network listener and no persistent state. Nothing here runs unattended.

## The kernel

`src/c/engine/nbody/orior/orior_core.c` holds four search arms and a dispatcher.

**Every arm is sound and none is defensive.** A subset of a pattern's points is a necessary condition. No arm can lose a true occurrence. That is a proof, and nothing in the code tests for it. What no arm does is validate its arguments: `corpus`, `needle` and their lengths are used as given, with no null test and no overflow test on `corpus_len` or `needle_len`. It is bench code called from a driver that builds its own inputs.

**Do not put it behind untrusted input without bounding the call first.** A `needle_len` larger than `corpus_len` is handled, a `needle_len` of zero is not, and neither pointer is checked. If you reach for this from somewhere that takes input from outside, the bounds check is yours to add and belongs at your boundary.

**The dispatcher chooses speed and never correctness.** `orior_choose` returns an arm, every arm returns the same count, and a wrong choice costs cycles. A dispatch defect cannot produce a wrong answer.

## The Python tools

**They reach the network.** `utils/maint/data/salishan/get_papers.py` fetches from a public archive and is the only thing here that opens a socket. It identifies itself by name and purpose in its user agent. Nothing else in the tree fetches anything.

**They parse PDFs.** The readers run `pypdf` and `pypdfium2` over files downloaded from the web, which is a real parser surface and it is not this work's parser. Keep those dependencies current, and treat a PDF from anywhere else the way you would treat any untrusted document.

**They write only under `build/`.** One exception, at a fixed path: the two generators that emit documentation write chapters under `theory/theory/Salishan/chapters/`. `python utils/maint/tree/write_survey.py` reads every script for the files it opens and reports where each one lands. That list is checked instead of remembered.

## Reporting

Open a private security advisory at <https://github.com/dstroy0/orior/security/advisories/new>, or email dquigg123@gmail.com.

For a defect in the kernel, include the compiler, the corpus and needle that show it, and whether `orior_naive` disagrees. For anything in the Python, include the file and the input.

This is research maintained by one person. There is no patch schedule. Fixes land on `main`.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
