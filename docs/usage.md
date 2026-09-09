# Using it

**Purpose:** Run the measure on something of your own, and know which of the six parts you are calling.
**Scope:** `src/engine/python/`, `examples/`.

## The shortest thing that works

Every example takes a corpus path and prints what it read. Nothing is configured first and no model is fitted.

```sh
python examples/any_corpus/4_measure/head_and_tail.py yours.sym
```

A `.sym` file is one symbol per line. Any sequence works: characters, words, byte values, note numbers, residue names. The measure never learns what a symbol means and cannot tell one domain from another.

Run an example with no argument and it prints the usage line and stops.

## The six parts

| part | what you call it for |
|---|---|
| `representation` | turn your object into points carrying values |
| `partition` | choose the unit and the scale to read at |
| `reference` | build the maximum entropy background the object's own constraints allow |
| `measure` | read the departure from that background |
| `sift` | filter candidates with a necessary condition |
| `oracle` | check against ground truth somebody else published |

Only `representation` knows a domain exists. It has `text`, `sound`, `picture` and `structure` under it. Everything downstream sees points and values.

`src/engine/python/README.md` is the map.

## Where the rest of it is

| | what it operates on |
|---|---|
| `src/` | points and values, no domain. The engine and the ports |
| `examples/` | a corpus, through `src/`. Numbered demonstrations |
| `theory/` | the books, and the ledger they cite |
| `maint/` | the repository itself. Records, gates, prose checks, fetchers, the book build |

`maint/` is sorted into eleven categories and holds no loose scripts. `maint/README.md` states what belongs in each, including `maint/data/` for external material and `maint/analysis/` for the surveys the books ask for.

## Reading the result

A measurement carries a floor. The floor is what the same measure returns on a shuffle of the same symbols, an arrangement carrying no structure at all.

**A reading below its floor read nothing.** Not a small result, nothing. Every example prints the floor beside the number for that reason.

The floor moves with sample size. One computed on a large corpus bounds nothing about a short file. The examples compute it at the size actually measured.

## The eight domains

`examples/` runs the same six parts end to end on real material.

| domain | examples | what it reads |
|---|---|---|
| `language` | 60 | corpora, orthographies, dialect borders |
| `any_corpus` | 18 | any symbol sequence, domain unspecified |
| `art` | 6 | images as byte sequences |
| `proofs` | 4 | the numbers that pin the ledger |
| `proteins` | 4 | backbone coordinates |
| `source` | 4 | source code as a symbol stream |
| `crystallography` | 6 | cell edges, against published ones |
| `sound` | 1 | recordings as bit fields |

Every example carries a catalog number in its header, `LNG-4-012` and so on. A citation to that number survives the file moving. `maint/catalog/catalog.py` is the registry.

## The search kernel

```sh
./build/engine_c/bench_lattice
```

The sift is a sound filter: no arrangement of anchors can lose a true occurrence. Errors are one directional and any discrepancy is an over-count. It carries `m` bits of state for a pattern of length `m`, with no table over the alphabet. A real-valued or unenumerable alphabet costs it nothing.

The Python in `src/engine/python/sift/` implements the same construction and shares no code with the C. The two are checked against each other by agreeing on counts.

## Other languages

| language | file |
|---|---|
| R | `src/engine/r/measure/departure.R` |
| MATLAB and Octave | `src/engine/matlab/measure/anchor_sift_departure.m` |

A port is correct when it lands inside the reseeding floor of the Python, since each language draws its null from a different generator and none agree to the last digit.

## If you are working on a language

Read [the condition of use](https://github.com/dstroy0/anchor_sift#the-condition-of-use) first. These tools regenerate language, and output near the edge of a source distribution can be coherent and already not be the language. Nothing here marks which side of that a result fell on, and a human review of the output is a condition of use.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-09
