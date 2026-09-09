# data

**Purpose:** Say what belongs in this directory and what does not, leaving a new script one obvious place.
**Scope:** `data/fetch/`, `data/salishan/`.

**Everything here operates on external material.** Getting it, and turning it into something measurable. Nothing here measures anything, and nothing here reads the engine.

The membership rule stops there. A script that fetches, converts, transcribes or repairs somebody else's material belongs here. A script that reads a corpus and reports a number belongs in `analysis/` or `examples/`.

## fetch

Network acquisition, one script per source. Each names the archive it reads, identifies itself in its user agent, and writes under `build/corpora/`.

They range from a single work to a whole archive: Project Gutenberg, OPUS, Deutsches Textarchiv, Aozora Bunko, Universal Dependencies, Tatoeba, eBible, and the Estonian and Austrian national collections. `maint/citations.py` carries the registry of what each one is, bucketed by the domain it feeds.

## salishan

One subject's pipeline, from the archive to a checked corpus. This is the largest single thing in the repository and it is a data pipeline, not a tool. It sits here under its own name for that reason, instead of inside a directory called tools.

| | |
|---|---|
| `get_papers.py`, `paper_supervisor.py` | the ICSNL archive, and tracking every paper from index to converted text |
| `pdf2png.py`, `draft_page_text.py` | a page as an image, and as a first draft, for the papers whose extracted text is not what the page prints |
| `hand_extraction/` | the control. Forms read off a page by a person, and the checks that grade a reader against them |
| `corpus_script_extraction/` | the readers, one per paper |
| `anchor_sift_algorithmic_extraction/` | the sift applied to the same papers |
| `corpus_derivation.py` | how wrong the corpus could be, from what the checks have seen |

The papers and the hand extractions are not here. They are somebody else's copyright and somebody else's language, they live in a closed repository, and `build/papers` and `build/oracles` reach them. `maint/verify_private_sync.py` checks that what `build/` reaches is what the signature covers.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-09
