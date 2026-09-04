# Security

**Purpose:** Know what this repository is responsible for, what it is not, and where to report something.
**Scope:** `bench/kernel/`, `bench/driver/`, `tools/dev_env/`, `ports/`

## What is here

A search kernel in C11, a driver that times it, Python tools that fetch and read published papers, and two ports of one statistic. There is no server, no daemon, no network listener and no persistent state. Nothing here runs unattended.

## The kernel

`bench/kernel/anchor_sift.c` holds four search arms and a dispatcher.

**Every arm is sound and none is defensive.** A subset of a pattern's points is a necessary condition, so no arm can lose a true occurrence, and that is a proof and not a check. What no arm does is validate its arguments: `corpus`, `needle` and their lengths are used as given, with no null test and no overflow test on `corpus_len` or `needle_len`. It is bench code called from a driver that builds its own inputs.

**Do not put it behind untrusted input without bounding the call first.** A `needle_len` larger than `corpus_len` is handled, a `needle_len` of zero is not, and neither pointer is checked. If you reach for this from somewhere that takes input from outside, the bounds check is yours to add and belongs at your boundary.

**The dispatcher chooses speed and never correctness.** `anchor_sift_choose` returns an arm, every arm returns the same count, and a wrong choice costs cycles. A dispatch defect cannot produce a wrong answer.

## The Python tools

**They reach the network.** `tools/dev_env/Salishan/get_papers.py` fetches from a public archive and is the only thing here that opens a socket. It identifies itself by name and purpose in its user agent. Nothing else in the tree fetches anything.

**They parse PDFs.** The readers run `pypdf` and `pypdfium2` over files downloaded from the web, which is a real parser surface and it is not this work's parser. Keep those dependencies current, and treat a PDF from anywhere else the way you would treat any untrusted document.

**They write only under `build/`.** No tool writes outside it except the generators that emit documentation, and those write to fixed paths under `docs/`.

## The vendored library

`bench/deps/` is [MMgr](https://github.com/dstroy0/MMgr), vendored so the kernel builds standalone, and it keeps its own attribution. Its security properties are its own and are documented in that repository. Nothing here extends or restates them.

## The concern that is not a vulnerability

The largest risk this work carries is not a memory bug. **The tools can regenerate language and can produce predictive speech**, and regeneration stays faithful near the subject and escapes it with distance, with nothing marking where that happens. Output taken from past that boundary and presented as somebody's language is the harm, and for a language with few remaining speakers it is not recoverable.

**A tool for language that comes out of this work requires a human to review its output.** That is a condition of use. If you find this work being run without one, that is worth reporting here even though no CVE describes it.

## Reporting

Open a private security advisory at <https://github.com/dstroy0/anchor_sift/security/advisories/new>, or email dquigg123@gmail.com.

For a defect in the kernel, include the compiler, the corpus and needle that show it, and whether `anchor_sift_naive` disagrees. For anything in the Python, include the file and the input.

This is research maintained by one person. There is no patch schedule. Fixes land on `main`.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-04
