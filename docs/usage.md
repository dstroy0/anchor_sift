# Using it

**Purpose:** Run the measure on something of your own, and know which of the six parts you are calling.
**Scope:** `src/python/`, `src/c/engine/nbody/orior/orior.h`, `examples/`.

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

Only `representation` knows a domain exists. It has `atom`, `constants`, `game`, `particle`, `picture`, `sound`, `structure` and `text` under it. Everything downstream sees points and values.

[`src/python/README.md`](https://github.com/dstroy0/orior/blob/main/src/python/README.md) is the map.

## Where the rest of it is

| | what it operates on |
|---|---|
| [`src/`](https://github.com/dstroy0/orior/tree/main/src) | points and values, no domain. The engine |
| [`evidence/`](https://github.com/dstroy0/orior/tree/main/evidence) | the claims. The proofs, and the R and MATLAB ports |
| [`examples/`](https://github.com/dstroy0/orior/tree/main/examples) | a corpus, through `src/`. Numbered demonstrations |
| [`utils/test/`](https://github.com/dstroy0/orior/tree/main/utils/test) | the engine. The correctness checks in `utils/test/src/`, laid out as `src/` is, and the published test vectors |
| [`utils/bench/`](https://github.com/dstroy0/orior/tree/main/utils/bench) | the engine. The benches: how fast it is |
| [`theory/`](https://github.com/dstroy0/orior/tree/main/theory) | the research papers, and the ledger they cite |
| [`utils/maint/`](https://github.com/dstroy0/orior/tree/main/utils/maint) | the repository itself. Records, gates, prose checks, fetchers, the research paper build |

`utils/maint/` is sorted into categories and holds no loose scripts. [`utils/maint/README.md`](https://github.com/dstroy0/orior/blob/main/utils/maint/README.md) states what belongs in each, including `utils/maint/data/` for external material and `utils/maint/analysis/` for the surveys the research papers ask for.

## Reading the result

A measurement carries a floor. The floor is what the same measure returns on a shuffle of the same symbols, an arrangement carrying no structure at all.

**A reading below its floor read nothing.** Not a small result, nothing. Every example prints the floor beside the number for that reason.

The floor moves with sample size. One computed on a large corpus bounds nothing about a short file. The examples compute it at the size actually measured.

## The twelve domains

`examples/` runs the same six parts end to end on real material. The proofs that pin the ledger sit apart, under `evidence/proofs/posits/`.

| domain | examples | what it reads |
|---|---|---|
| `language` | 60 | corpora, orthographies, dialect borders |
| `any_corpus` | 19 | any symbol sequence, domain unspecified |
| `game_theory` | 16 | games, by how open the result stays after a move |
| `proteins` | 13 | backbone coordinates |
| `particle_physics` | 11 | atoms and particles as exact quantum numbers |
| `crystallography` | 9 | cell edges, against published ones |
| `art` | 9 | images as byte sequences |
| `cell_tracking` | 7 | cell positions across frames |
| `chemistry` | 5 | molecules as atoms and bonds |
| `source` | 4 | source code as a symbol stream |
| `sound` | 3 | recordings as bit fields |
| `molecules` | 3 | molecular formulae, legal from illegal by valence |

Every example carries a catalog number in its header, `LNG-4-012` and so on. A citation to that number survives the file moving. [`utils/maint/catalog/catalog.py`](https://github.com/dstroy0/orior/blob/main/utils/maint/catalog/catalog.py) is the registry.

## The search kernel

`anchor_steer_count` counts the occurrences of a needle in a corpus. Its last argument is 1 to order the probes by rarity and 0 to leave them in spatial order, and the count is the same either way ([`orior_descent.h:342-368`](https://github.com/dstroy0/orior/blob/main/src/c/engine/nbody/orior/orior_descent.h#L342-L368)). Both buffers are [BORROWS] for the call.

```c
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "orior.h"

int main(void)
{
    const char *corpus = "abracadabra abracadabra";
    const char *needle = "abra";
    const size_t corpus_len = strlen(corpus);
    const size_t needle_len = strlen(needle);

    const size_t count = anchor_steer_count((const uint8_t *)corpus, corpus_len,
                                            (const uint8_t *)needle, needle_len, 1);
    printf("%lu occurrences, scanned by the %s engine\n", (unsigned long)count,
           anchor_steer_best_engine()->name);
    return 0;
}
```

Built with the four-source line in [Setup](setup.md#the-c-engine) under gcc on x86-64 Windows, it prints `4 occurrences, scanned by the portable engine`.

The sift is a sound filter: no arrangement of anchors can lose a true occurrence. Errors are one directional and any discrepancy is an over-count. It carries `m` bits of state for a pattern of length `m`, with no table over the alphabet. A real-valued or unenumerable alphabet costs it nothing.

The Python in [`src/python/engine/nbody/orior/sift/`](https://github.com/dstroy0/orior/tree/main/src/python/engine/nbody/orior/sift) implements the same construction and shares no code with the C. The two are checked against each other by agreeing on counts.

## Other languages

| language | file | status |
|---|---|---|
| R | [`evidence/sims/r/departure.R`](https://github.com/dstroy0/orior/blob/main/evidence/sims/r/departure.R) | runs, checked against the reference |
| MATLAB and Octave | [`evidence/sims/matlab/orior_departure.m`](https://github.com/dstroy0/orior/blob/main/evidence/sims/matlab/orior_departure.m) | run on Octave 11.3.0, inside the reference floor; MATLAB proper not run here |

A port is correct when it lands inside the reseeding floor of the Python, since each language draws its null from a different generator and none agree to the last digit. Checked on 200000 symbols over twelve seeds: a clustered sequence reads 0.4228 in Python and 0.4282 in R against a floor of 0.0092, and a memoryless one reads 0.9953 and 0.9933 against a floor of 0.0044. Both gaps sit at about half a floor.

## If you are working on a language

Read [the conditions of use](condition_of_use.md) first. These tools regenerate language, and output near the edge of a source distribution can be coherent and already not be the language. Nothing here marks which side of that a result fell on, and a human review of the output is a condition of use.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
