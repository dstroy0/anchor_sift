# anchor sift

Measure how far something sits from the most disordered arrangement of its own parts.

That is the construction. Every domain is that one sentence with a different answer to what counts as a part: atoms in a cell, symbols in a corpus, bytes in a file, coordinates in a board layout. The reference is built from the object's own parts, so there is no prior to estimate, no training set to collect and no model of the domain to write.

| | |
|---|---|
| [Setup](setup.md) | dependencies, building the engine, building the books |
| [Using it](usage.md) | run the measure on something of your own |
| [Research](research/index.md) | the four books under `theory/`, and how to build them |

The repository is at [github.com/dstroy0/anchor_sift](https://github.com/dstroy0/anchor_sift). Its README covers the algorithm, the areas of research, and the licensing.

## One condition, before anything else

The tools here can regenerate language and can produce predictive speech. **A tool for language that comes out of this work requires a human to review its output.**

Regeneration stays faithful near the subject and escapes it with distance, and nothing marks where that happens. The narrow band where output is still coherent and is already not the language is where a native speaker belongs. The question there is *is this mine*, and that is a question of anthropology, of philosophy, and for many communities of what is sacred. It is not for an algorithm to answer.

## The languages here belong to the people who speak them

The corpus this work is measured against is Salishan speech, written down. **It does not exist without the speakers.** The Salishan book opens every entry with the person who spoke, before the linguist who published and before anyone who read a paper into a file.

A linguist wrote the paper. A person read the paper into a table. Neither of those is whose language it is.

## Two instruments, and they are not interchangeable

| | reads | external ground truth |
|---|---|---|
| shift agreement detector | a period or an offset, by how often a shift agrees with itself | 453 of 453 axes, from published crystal cell edges |
| permutation null measure | a departure from the maximum entropy arrangement of the same multiset | none |

The permutation null measure carries most of the findings and has only been shown not to invent structure on memoryless input. Most of the confusion this work has had to correct came from reporting one of these as the other.

**Read the ledger before quoting any figure.** It keeps its own corrections: claims that were withdrawn stay on the page beside the measurement that killed them, and several results here are rediscoveries of published work with the precedent named.
