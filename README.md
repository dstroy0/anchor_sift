# Anchor sift

**Purpose:** Find out what this method measures, what it has actually read, and where it fails, without having to run anything first.
**Scope:** `tools/dev_env/`, `docs/research/`

## The languages here belong to the people who speak them

The corpus everything in this repository is measured against is Salishan speech, written down. **This work does not exist without the speakers**, and none of the results below would have been reachable without them.

Every table in `docs/research/Salishan/pure_corpus/` opens with the person who spoke, before the linguist who published and before anyone who read it into a file. [`pure_corpus/README.md`](docs/research/Salishan/pure_corpus/README.md) is the index and it is written speaker first. Where a paper cites a published dictionary and never says who spoke, its entry says so instead of guessing.

A linguist wrote the paper. A person read the paper into a table. Neither of those is whose language it is.

## What this is, stated plainly

**It knows nothing.** There is no model here, no training, no corpus of examples and no prior. It has no knowledge of language, of chemistry, of images or of anything else, and it never acquires any. What it computes is a distance between an object and a reference built out of that object's own parts. Every result below came from that one operation and nothing was taught to it.

**A speaker's words are their own.** The corpus holds what named people said, attributed to them, and nothing here transfers that. A form these tools recover, predict or regenerate is not a new utterance by that speaker and must never be presented as one.

**These tools can regenerate language and can produce predictive speech, and that capability is the reason the next paragraph exists.** `text_regeneration.py`, `to_phonemes.py` and the sound representation work are in this repository and they do what they are named for. Pretending otherwise would be a false claim about the code, and a safeguard resting on a false claim is not a safeguard.

**Regeneration is faithful near the subject and escapes it with distance, and nothing here marks where that happens.** Close to the center of mass of the subject the output is a copy and carries nothing new. Move outward and it carries more, until at some radix from that center it reaches escape velocity and is no longer that language at all. Past that point it becomes incoherent and the tail recursively explodes, each step compounding the last, so output taken far beyond the boundary is obvious nonsense and nobody is fooled by it.

Immediately before that boundary is a narrow band where the output is still coherent and may already not be the language. No result these tools produce is labeled with which side of it they fell on.

**That band is not an engineering problem and it is not mine to close.** It is where a native speaker belongs. The question there is *is this mine*, and that is a question of anthropology, of philosophy, and for many communities of what is sacred. It is not a question for an algorithm, and no amount of measurement turns it into one. A tool that answered it automatically would be taking a decision that was never its to take.

**I will not build it that way and I will not allow it to be built that way.** Every tool for language that comes out of this work requires a human to review its output. That is a condition of use and not a recommendation.

The rest follows from it. The sift finds candidates and it does not read them. Every corpus here was hand extracted and verified in two directions against its source paper by a person. A pipeline that took a regenerated form and published it, taught it, or fed it onward unread would be presenting something past escape velocity as a language, and for a language with few remaining speakers that harm is not recoverable.

**What it is instead:** a purpose built universal information miner that runs on human timescales. Seconds on a laptop, against a database somebody else published. Not a geological schedule and not a data center.

**Its discrimination is unbounded in reach and finite in every reading.** There is no class of thing it cannot be pointed at, because it assumes nothing about the domain and needs only that the object is not already at maximum entropy. What any single measurement returns is a finite number with a stated floor under it, and where the floor is not cleared the honest answer is that nothing was read.

## What the method is

Measure how far something sits from the most disordered arrangement of its own parts.

That is the whole construction. Every domain below is that one sentence with a different answer to what counts as a part: atoms in a cell, symbols in a corpus, bytes in a file, coordinates in a board layout. The reference is built from the object's own parts, so there is no prior to estimate, no training set to collect and no model of the domain to write.

Building a reference by maximizing entropy under the constraints the object supplies is Jaynes's principle, and the departure from it is the free energy above equilibrium. `docs/research/terms.md` gives the vocabulary, including which words here are the field's and which this work minted.

## The search kernel

`bench/kernel/` is the part with the widest reach outside this work, and it builds and runs on its own with a C11 compiler and nothing else.

**It is a sound filter.** A subset of a pattern's points is a necessary condition, so no arrangement of anchors can lose a true occurrence. That is a proof. It uses no order, no dimension and no alphabet, and no measurement stands behind it. The measurement beside it: across 35 rows of corpora, needle lengths and strides, no search ever reported fewer occurrences than exist. Errors are one directional, which means a discrepancy is always an over-count and is therefore detectable without knowing the answer.

**It carries `m` bits of state and nothing else**, where `m` is the pattern length, and that is independent of the alphabet and of the dimension. A Horspool shift table is the size of the alphabet; a q-gram index is the size of the text. On a real-valued or unenumerable alphabet neither of those can be built at any size, and this still runs. That is the capability claim, and it is separate from any speed claim.

**It searches with no pattern at all.** Given only bytes, it recovered a multiple of a record period from 512 reads, at 92 shifts against 0 on a shuffle of the same bytes. Horspool has nothing to build a table from and cannot be run at all in that case.

**Dependency depth two.** Every anchor probe is independent and the combine is one tree, which lets a superscalar machine issue them together. Horspool's next shift waits on the byte it just read. `bench/driver/bench_ancorae_cycles.c` measures what that is worth and the answer is conditional: on a skewed corpus the free-order arm is 2.8x to 3.1x faster than the short-circuiting one, and on a memoryless corpus it is 1.6x slower, because there the first probe rejects almost every alignment on its own.

**Against Horspool the crossover is measured and it runs the opposite way from the read count.** On a skewed corpus at 65536 bytes the free-order arm is 2.54x faster at a needle of 4 and loses from 32 upward, because Horspool's shift grows with the needle. Counted in reads the advantage grows with the needle; counted in cycles it shrinks. Reads are the right unit for a bound and the wrong one for a dispatch decision.

**So the kernel carries a dispatcher, and it grades itself.** `anchor_sift_choose` picks an arm from two numbers that are already free: collision entropy from one histogram pass, and the needle length, known at the call. The driver times every arm and prints what the dispatcher chose beside what was actually fastest. It picks the fastest on 19 of 21 rows, and its worst miss costs 1.40x.

That miss is the interesting row. A period-16 counter uses sixteen symbols evenly, so its collision entropy reads 4.0 and its effective alphabet equals the symbols it uses, and the dispatcher calls a perfectly structured corpus memoryless. Collision entropy is permutation invariant and cannot see an arrangement, which this document's first proposition states, and the dispatcher inherits that blindness exactly. Fixing it needs a quantity that reads arrangement. No threshold on this one reaches it.

```
cmake -S bench -B build/bench -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/bench
./build/bench/bench_ancorae_cycles
```

## Ports, for people who do not want to run the C

`ports/` carries the permutation null measure on its own, which is the part a statistician or a corpus linguist actually reaches for. The search kernel is a systems artifact; this is the instrument.

| language | file | status |
|---|---|---|
| R | `ports/R/anchor_sift.R` | runs, checked against the reference |
| MATLAB and Octave | `ports/matlab/anchor_sift_departure.m` | logic checked, not executed here |
| Python | `tools/dev_env/proof_conservation.py` | the reference every figure came out of |

The reference is the Python. A port is correct when it lands inside the reseeding floor of it, since each language draws its null from a different generator and none of them can agree to the last digit.

Checked on 200000 symbols over twelve seeds: a clustered sequence reads 0.4228 in Python and 0.4282 in R against a floor of 0.0092, and a memoryless one reads 0.9953 and 0.9933 against a floor of 0.0044. Both gaps sit at about half a floor.

```r
source("ports/R/anchor_sift.R")
anchor_sift_departure(as.integer(charToRaw(paste(readLines("book.txt"), collapse = " "))))
```

## Two instruments, and they are not interchangeable

Most of the confusion this work has had to correct came from reporting one of these as the other.

| | what it does | external ground truth |
|---|---|---|
| shift agreement detector | reads a period or an offset by how often a shift agrees with itself | three times, from published crystal cell edges |
| permutation null measure | reads a departure from the maximum entropy arrangement of the same multiset | none |

The permutation null measure carries most of the findings here and has only been shown not to invent structure on memoryless input. Read `docs/research/anchor-sift-ledger.md` before quoting any row of it.

## What it has read

Published cell edges from the Crystallography Open Database, tiled and voxelized and handed over with nothing told to the detector, come back three of three exact, to 0.0006 angstroms against a voxel of 0.25. That is the one positive control here whose answer came from outside the work.

A dialect border inside Lushootseed, labeled by Mellesmoen and Kye and then held out, comes back as the stressed schwa, southern, beaten by 1 of 200 random borders over the same forms.

An image read as a byte sequence returns its own width. A Vigenère cipher returns its key length. Neither was told anything.

The ledger holds the rest, including every row that failed and why.

## What is not here

The corpora, papers, audio and rendered pages are about 1.9 GB and none of it is in git. `tools/dev_env/Salishan/get_papers.py` fetches the papers and the tools rebuild the rest. Addresses for everything are in `docs/research/Salishan/refs.md`.

The C implementation of the sift, its benches and its cycle timer live in [MMgr](https://github.com/dstroy0/MMgr) under `src/impensa_ancorae_acus/` and `test/bench/`. The ledger cites those paths and they are in that repository, not this one.

## Where to start

| you want | read |
|---|---|
| the vocabulary | `docs/research/terms.md` |
| what is settled and what is open | `docs/research/anchor-sift-ledger.md` |
| the method itself | `docs/research/anchor-sift-method.md` |
| whose words the corpus holds | `docs/research/Salishan/pure_corpus/README.md` |
| how wrong the corpus could be | `docs/research/Salishan/corpus-derivation.md` |
| every source, held or cited | `docs/research/Salishan/refs.md` |

## Licensing - This work is dual licensed.

Licensed AGPL-3.0-or-later. // various commercial contracts available
It will always be free to use under the AGPL.
Educators: If you would like an exception to use this in your classrooms or research projects,
please feel free to email dstroy0 (Douglas Quigg) <dquigg123@gmail.com> from your _.edu or _.org
faculty email address, I would be happy to grant you an exception on a case-by-case basis. Your exception
governs your use, specifically the accreditation requirement of underlying systems in any research/presentation materials.
Academic exemptions can lead to viable market products, in which case this license shifts to a royalty ladder,
based arbitrarily off of the amount of goodwill you've shown and how well you've adhered to crediting students and
other faculty involved in the project, a portion of the royalties go directly to your institution at a minimum and
straight to your department if their rules allow for it.
See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

**Every license already offered for this work under MMgr is transferred here and applies on the same terms.** Nobody holding one needs to do anything, and no term changes because the files moved. `LICENSE` and `LICENSES/` are the same files that tree carries.

## A note on how this is written

The ledger keeps its own corrections. Claims that were withdrawn stay on the page with the measurement that killed them, because a document that only records what survived is not evidence of anything. Several results here are rediscoveries of published work, and where that is known the precedent is named.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-04
