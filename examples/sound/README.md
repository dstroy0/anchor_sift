# Sound

**Purpose:** Explain why this subject has only one stage, and record the representation error that was found here.
**Scope:** `examples/sound/`

| stage | present |
|---|---|
| `1_represent` | `vocalization_scale.py` |
| `2_partition` through `6_oracle` | none |

## The scale error

The vocalizations were read at 8 kHz with one byte per sample. A whale song unit lasts one to three seconds, so at that rate the statistic was reading inside a single call and never saw how the calls were arranged. Animal and human recordings overlapped in the results. Reading one symbol every 10 ms separates them completely.

That mistake cost a published ordering, and it is why the only script here is a stage one script. Getting the scale right was the entire job. `vocalization_scale.py` reads the same recordings at both scales and shows that the two answer different questions.

## Missing stages

**Stage three is missing, and it blocks everything after it.** There is no useful shuffle of a vocalization yet. The unit is a call, not a byte, so permuting bytes destroys the calls themselves instead of their order. What is needed is a null that keeps each call intact and permutes the sequence of calls. Nobody has written it.

**Stage four depends on stage three.** Without that null there is no background to measure a departure from.

The recordings are fetched by `maint/data/fetch/vocalization_domain.py` and `maint/data/fetch/infrasound_domain.py`.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
