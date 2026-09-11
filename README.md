# Anchor sift

**Purpose:** Find out what this method measures, what it has read, and where it fails, without running anything first.
**Scope:** `src/`, `data/`, `analysis/`, `maint/`, `examples/`, `evidence/`, `theory/`

## Contents

1. [The algorithm](#the-algorithm)
2. [Areas of research](#areas-of-research)
3. [Where things are](#where-things-are)
4. [Two instruments, and they are not interchangeable](#two-instruments-and-they-are-not-interchangeable)
5. [The sift](#the-sift)
6. [Ports](#ports)
7. [What it knows](#what-it-knows)
8. [Whose language this is](#whose-language-this-is)
9. [The condition of use](#the-condition-of-use)
10. [Where to start](#where-to-start)
11. [What is not here](#what-is-not-here)
12. [Licensing, dual](#licensing-dual)
13. [A note on how this is written](#a-note-on-how-this-is-written)

## The algorithm

Measure how far something sits from the most disordered arrangement of its own parts.

That is the construction. Every domain below is that sentence with a different answer to what counts as a part: atoms in a cell, symbols in a corpus, bytes in a file, coordinates in a board layout. The reference is built from the object's own parts, so there is no prior to estimate, no training set to collect, and no model of the domain to write.

Building a reference by maximizing entropy under the constraints the object supplies is Jaynes's principle. The departure from it is the free energy above equilibrium.

One construction runs through all six parts. Represent the object as points carrying values, fix a partition over those points, build the maximum entropy reference that partition allows, and read the departure from it. The sift and the oracle sit either side, one discarding candidates and one supplying an answer from outside the sample.

| part | what it holds |
|---|---|
| `representation` | any domain written as points carrying values, and the re-seatings that put one symbol in one place |
| `partition` | the unit and the scale those points are read at |
| `reference` | the maximum entropy background under the constraints the object supplies |
| `measure` | the departure from that background |
| `sift` | the sound filter, a necessary condition over any index set |
| `oracle` | agreement with ground truth somebody else published |

Everything downstream of `representation` sees points and values and cannot tell a painting from a paragraph, so one instrument reads both. Four subjects have their own directories: `text`, `sound`, `picture` and `structure`, all under `representation`, the only part that knows a domain exists.

`src/engine/python/README.md` is the map. `examples/` runs the same six names end to end on real corpora.

## Areas of research

Seven domains have been run end to end under `examples/`: language, art, crystals, proteins, sound, source code and arbitrary corpora. The proofs that pin the numbers are under `evidence/proofs/`. The same six parts read all of them.

Published cell edges from the Crystallography Open Database, tiled and voxelized and handed over with nothing told to the detector, come back three of three exact, to 0.0006 angstroms against a voxel of 0.25. No other positive control here took its answer from outside the work.

A dialect border inside Lushootseed, labeled by Mellesmoen and Kye and then held out, comes back as the stressed schwa, southern, beaten by 1 of 200 random borders over the same forms.

An image read as a byte sequence returns its own width. A Vigenère cipher returns its key length. A protein backbone returns bond lengths of 1.45, 1.52 and 1.33 against chemistry's 1.46, 1.52 and 1.33. None of them was told anything.

The ledger holds the rest, including every row that failed and why.

## Where things are

Each directory answers one question, and that question is the rule for what goes in it. There is no `tools/`, deliberately: a directory meaning "a script" takes everything, and this repository had the engine's own measure library, a research subject's whole pipeline and the prose checker filed together under that name.

| | what it operates on | |
|---|---|---|
| `src/` | points and values, no domain | the engine |
| `evidence/` | the claims | the proofs, and the R and MATLAB ports |
| `data/` | external material | fetchers, and the Salishan pipeline |
| `analysis/` | a corpus, through `src/` | surveys the books ask for |
| `examples/` | a corpus, through `src/` | 99 numbered demonstrations, seven domains |
| `maint/` | the repository itself | records, gates, prose checks, the book build |
| `theory/` | the argument | seven books |
| `docs/` | the reader | setup and usage |

`build/` is generated and disposable, and nothing irreplaceable is reachable through it.

## Two instruments, and they are not interchangeable

Most of the confusion this work has had to correct came from reporting one as the other.

| | what it reads | external ground truth |
|---|---|---|
| shift agreement detector | a period or an offset, from how often a shift agrees with itself | three times, from published crystal cell edges |
| permutation null measure | a departure from the maximum entropy arrangement of the same multiset | none |

The permutation null measure carries most of the findings and has only been shown not to invent structure on memoryless input. Read the ledger before quoting any row of it.

## The sift

`src/engine/c/sift/anchor_sift.c` builds and runs with a C11 compiler alone. The Python in `src/engine/python/sift/` implements the same construction, shares no code with it, and the two are checked against each other by agreeing on counts.

**It is a sound filter.** A subset of a pattern's points is a necessary condition, so no arrangement of anchors can lose a true occurrence. That is a proof, using no order, no dimension and no alphabet. The measurement beside it: across 35 rows of corpora, needle lengths and strides, no search ever reported fewer occurrences than exist. Errors are one directional. A discrepancy is always an over-count and is detectable without knowing the answer.

**It carries `m` bits of state**, for a pattern of length `m`, independent of alphabet and dimension. Nothing is indexed and no table is built over the alphabet. A real-valued or unenumerable alphabet therefore costs it nothing. That is a capability claim and it is separate from any speed claim.

**It searches with no pattern at all.** Given only bytes it recovered a multiple of a record period from 512 reads, at 92 shifts against 0 on a shuffle of the same bytes.

**The kernel dispatches, and grades itself.** `anchor_sift_choose` picks an arm from two numbers already free: collision entropy from one histogram pass, and the needle length known at the call. `bench_cycles.c` times every arm and prints what the dispatcher chose beside what was fastest. It picks the fastest on 19 of 21 rows and its worst miss costs 1.40x.

That miss is the interesting row. A period-16 counter uses sixteen symbols evenly, so its collision entropy reads 4.0 and the dispatcher calls a perfectly structured corpus memoryless. Collision entropy is permutation invariant and cannot see an arrangement, and the dispatcher inherits that blindness exactly. Fixing it needs a quantity that reads arrangement, and no threshold on this one reaches it.

```sh
cmake -S src/engine/c -B build/engine_c -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/engine_c
./build/engine_c/bench_lattice
```

## Ports

The permutation null measure on its own is the part a statistician or corpus linguist reaches for.

| language | file | status |
|---|---|---|
| Python | `src/engine/python/` | the reference every figure came out of |
| R | `evidence/sims/r/departure.R` | runs, checked against the reference |
| MATLAB and Octave | `evidence/sims/matlab/anchor_sift_departure.m` | logic checked, not executed here |

A port is correct when it lands inside the reseeding floor of the Python, since each language draws its null from a different generator and none can agree to the last digit. Checked on 200000 symbols over twelve seeds: a clustered sequence reads 0.4228 in Python and 0.4282 in R against a floor of 0.0092, and a memoryless one reads 0.9953 and 0.9933 against a floor of 0.0044. Both gaps sit at about half a floor.

## What it knows

Nothing. There is no model, no training, no corpus of examples, no prior. It has no knowledge of language, chemistry or images and never acquires any. It computes one distance and every result came out of that.

It runs on human timescales: seconds on a laptop against a database somebody else published. Its reach is unbounded, because it assumes nothing about the domain and needs only that the object is not already at maximum entropy. Every single reading is finite and carries a stated floor. Where the floor is not cleared, the honest answer is that nothing was read.

## Whose language this is

The corpus everything is measured against is Salishan speech, written down. **This work does not exist without the speakers.**

Every table opens with the person who spoke, before the linguist who published and before anyone who read it into a file. Where a paper cites a published dictionary and never says who spoke, its entry says so instead of guessing. The Salishan book carries that index, written speaker first, from `paper_config.py`, the only file where a speaker's name is typed.

A linguist wrote the paper. A person read the paper into a table. Neither of those is whose language it is.

## The condition of use

These tools read a language and can put one back. `to_phonemes.py`, `encode_percussive.py` and the sound representation work do what they are named for, and `regeneration_limit.py` measures how much of a source a regeneration recovers. Saying otherwise would be a false claim about the code, and a safeguard resting on a false claim is not a safeguard.

Regeneration is faithful near the subject and escapes it with distance. Close to the center of mass of the subject the output is a copy. Move outward and it carries more, until at some distance it leaves the source distribution and is no longer that language. Past that it becomes obvious nonsense and nobody is fooled.

Immediately before that boundary is a narrow band where the output is still coherent and may already not be the language. **Nothing here marks which side of it a result fell on.**

That band is where a native speaker belongs. The question there is *is this mine*, which is a question of anthropology, of philosophy, and for many communities of what is sacred. No amount of measurement turns it into a question an algorithm can answer.

**Every tool for language that comes out of this work requires a human to review its output.** That is a condition of use, not a recommendation. For a language with few remaining speakers, publishing a form drawn from outside the distribution as though it were the language is not a recoverable harm.

## Where to start

The research is seven books under `theory/`. Build them:

```sh
sh maint/texbuild/build_theory.sh
```

| you want | book |
|---|---|
| the construction, the method, the vocabulary | `theory/anchor_sift` |
| what is settled, what is open, what was withdrawn | `theory/workbook` |
| whose words the corpus holds, and how wrong it could be | `theory/Salishan` |
| the posits whose experiment cannot be built | `theory/thought_experiments` |
| a published cell edge read back off a voxel grid, and whose result that is | `theory/crystallography` |
| where the structure in SHA-256 is, where it stops, and how each null was measured | `theory/cryptography/sha256` |
| the corpus, the state of the field, and what this toolkit reaches | `theory/millennium` |

## What is not here

The corpora, papers, audio and rendered pages run to about 1.9 GB and none of it is in git. `maint/data/salishan/get_papers.py` fetches the papers from the public archive and the tools rebuild the rest.

The hand extractions are forms transcribed out of published papers, so the tables are those papers' text and not this work's to redistribute. They live in a closed repository with the papers, inventoried and signed, and reach a checkout through `maint/corpus/verify_private_sync.py`. Everything that does not read a paper or a table runs without them.

## Licensing, dual

Licensed AGPL-3.0-or-later, with commercial contracts available. It will always be free to use under the AGPL.

Educators: for an exception to use this in classrooms or research projects, email dstroy0 (Douglas Quigg) <dquigg123@gmail.com> from your `.edu` or `.org` faculty address. Exceptions are granted case by case and govern your use, specifically the accreditation requirement of underlying systems in research or presentation materials. Where an academic exemption leads to a viable market product the license shifts to a royalty ladder, set off the goodwill shown and how well students and other faculty were credited. A portion goes to your institution at a minimum, and straight to your department where their rules allow.

**Every license already offered for this work under MMgr transfers here on the same terms.** Nobody holding one needs to do anything and no term changes because the files moved. `LICENSE` and `LICENSES/` are the same files that tree carries.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## A note on how this is written

The ledger keeps its own corrections. Claims that were withdrawn stay on the page with the measurement that killed them, because a document recording only what survived is not evidence. Several results are rediscoveries of published work, and where that is known the precedent is named.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-11
