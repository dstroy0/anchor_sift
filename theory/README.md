# The theory research papers

**Purpose:** Move all research to one place.
**Scope:** every research paper

All of these are licensed under the AGPLv3 or later. All papers require CC BY 4.0 for citation, and your codebases must remain open under the AGPLv3 or later under the terms of the license.

The precision measurement specifically IS detectable in ANY form, because it works the same way regardless of approach. The cascade is unique and is itself a fingerprint.

It is detectable in encrypted compiled binaries. If you are a large company trying to steal my research, thanks for the easy win and the free money. I will make the case.

You have no choice but to comply with the licensing terms or be left in the dust by the exactness.

## Building

From the repository root:

```sh
sh maint/texbuild/build_theory.sh                      # every research paper
sh maint/texbuild/build_theory.sh workbooks/engine     # one of them
```

It compiles with xelatex. A research paper is named by its path below `theory/`, as in `theory/delta_null`, `workbooks/engine` or `theory/cryptography/sha256`.

Output goes to `build/theory/<research_paper>/` and nothing is written beside the source. A figure a chapter includes from `build/theory/figures/` is reached by a relative path, and that path counts the paper's depth below the repository root.

## Layout

- `theory/theory/` holds the research papers. Some are complete; most are at preprint status.
- `theory/workbooks/` holds the workbooks, one per program.
- `theory/thought_experiments/` holds the thought experiments, kept apart from what was measured.

A thought experiment may be wacky. It is classified as wacky and stays wacky until it is measured.

Commit a change to a research paper with the work it belongs to. The project's hook runs on it.

## Generated chapters

Change these through their generator. An edit to the chapter is lost the next time it is generated.

Citations sit beside them as separate `.tsv` files, because there are many.

## What is here

Each research paper's subtitle is the line from its title page.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-26
