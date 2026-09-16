# Sound

**Purpose:** Record the representation error found here, and the noise filters that read a sound signal as points carrying values.
**Scope:** `examples/sound/`

| stage | present |
|---|---|
| `1_represent` | `vocalization_scale.py` |
| `2_partition` | none |
| `3_reference` | `period_background_and_its_null.py` |
| `4_measure` | `coherent_hum_removed_to_the_bit.py`, `impulses_removed_to_the_bit.py` |
| `5_sift`, `6_oracle` | none |

## The scale error

The vocalizations were read at 8 kHz with one byte per sample. A whale song unit lasts one to three seconds, so at that rate the statistic was reading inside a single call and never saw how the calls were arranged. Animal and human recordings overlapped in the results. Reading one symbol every 10 ms separates them completely.

That mistake cost a published ordering, and it is why the first script here is a stage one script. Getting the scale right was the entire job. `vocalization_scale.py` reads the same recordings at both scales and shows that the two answer different questions.

## The noise filters

The stage three and stage four scripts are a different line of work on the same subject: a noise filter that reads a sound signal as points carrying values and rejects a component it can identify. They rest on one principle. A noise is rejectable exactly when it is identifiable as separate from the target, and it is identifiable in one of two ways.

A **coherent** noise repeats. A hum adds the same short cycle over and over, so its energy gathers into the phase classes of its period, and `measure/periodic_energy` reads that period off how far the phase grouping stands above a shuffle. `reference/periodic` then builds the phase mean, which is the maximum entropy background the period allows, and the residual is the target with the hum gone. `coherent_hum_removed_to_the_bit.py` removes it to the last bit where the target sits orthogonal to the hum's period.

An **incoherent** noise does not repeat. An impulse replaces a sample with a value from nowhere, and it is identified only by the target it lands on: when the target repeats, `measure/shift_agreement` reads its period and `reference/periodic` restores each corrupted sample from the value its phase class agrees on. `impulses_removed_to_the_bit.py` removes them to the last bit where each corrupted class keeps a clean majority.

`period_background_and_its_null.py` is the stage three reading under both: the phase-mean background at the true period against the same background on a shuffle, so the part of the reading that clears the null is visible.

### What these are and are not

Each of the three runs on a **synthetic positive control built in the script**, because a full rejection can only be proved against a signal whose clean form is known. Every one reports a **drawn null** and a **stated floor**: the noise shaped exactly like the target, which no instrument can reject. Every one runs **two independent routes** that agree bit-exact where both hold and split where the data no longer carries an answer, and each shows that the routes can genuinely disagree, so their agreeing is evidence and not an identity typed twice.

Each also carries a **negative control**, because a bit-exact 100% on a matched control proves only that the pipeline is wired and the arithmetic exact: it cannot tell a detector from an identity that cancels whatever was injected. So each script runs the cases that must **not** read 100% beside the one that must. A signal with no noise, and the wrong kind of noise, are both required to fall inside the null band and be declined, leaving the signal untouched or the noise intact. The 100% is reached only where a noise the detector is built for is genuinely present. The figures are exact on the controls; a reading on a real recording would report the measured reduction with its floor beside it. A native-C route is the natural hardening of the reconstruction and is not claimed here.

## The vocalization null is still missing

The stage three script above is a null for a **byte-valued signal at sample scale**, which is what the filters need. It is **not** the null a vocalization reading needs, and that one is still unwritten. The unit of a vocalization is a call, not a byte, so permuting bytes destroys the calls themselves instead of their order. What that reading needs is a null that keeps each call intact and permutes the sequence of calls. Until it exists, a departure measure over segmented calls has no background to stand against.

The recordings are fetched by `maint/data/fetch/vocalization_domain.py` and `maint/data/fetch/infrasound_domain.py`.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
