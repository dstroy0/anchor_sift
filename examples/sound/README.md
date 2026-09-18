# Sound

**Purpose:** Record the representation error found here, and the noise filters that read a sound signal as points carrying values.
**Scope:** `examples/sound/`

| stage                | present                             |
| -------------------- | ----------------------------------- |
| `1_represent`        | `vocalization_scale.py`             |
| `2_partition`        | none                                |
| `3_reference`        | `period_background_and_its_null.py` |
| `4_measure`          | `noise_removed_to_the_bit.py`       |
| `5_sift`, `6_oracle` | none                                |

## The scale error

The vocalizations were read at 8 kHz with one byte per sample. A whale song unit lasts one to three seconds. At that rate the statistic was reading inside a single call and never saw how the calls were arranged. Animal and human recordings overlapped in the results. Reading one symbol every 10 ms separates them completely.

That mistake cost a published ordering, and it is why the first script here is a stage one script. Getting the scale right was the entire job. `vocalization_scale.py` reads the same recordings at both scales and shows that the two answer different questions.

## The noise filters

The stage three and stage four scripts are a different line of work on the same subject: a noise filter that reads a sound signal as points carrying values and rejects a component it can identify. They rest on one principle. A noise is rejectable exactly when it is identifiable as separate from the target, and the target is identifiable by an invariant the noise does not share. Every filter here is that one construction -- group the positions an invariant makes equivalent, take the value the group agrees on, and the residual is what the group could not have predicted -- over a different grouping.

`noise_removed_to_the_bit.py` is that construction run over four noises as one sweep, printing one table so the four figures sit in the same units and can be read against each other. The four paragraphs below are its four rows.

A **coherent** noise repeats. The invariant is POSITION. A hum adds the same short cycle over and over, its energy gathers into the phase classes of its period, and `measure/periodic_energy` reads that period off how far the phase grouping stands above a shuffle. `reference/periodic` builds the phase mean and the residual is the target with the hum gone. The **coherent hum** row removes it to the last bit where the target sits orthogonal to the hum's period. This is a comb filter.

An **incoherent impulse** does not repeat. It is identified by the target it lands on. When the target repeats, `measure/shift_agreement` reads its period and `reference/periodic` restores each corrupted sample from the value its phase class agrees on. The **incoherent impulse** row removes them to the last bit where each corrupted class keeps a clean majority. It sweeps two floors, because the class breaks at a different count depending on whether one stuck value fills it or the impulses are scattered across it.

A **recurring motif** is identified by CONTENT. `reference/self_similar` groups the places that share a surrounding context and averages their centers. A motif occurring at positions with no period between them is still recovered. The **recurring motif** row is non-local means reached through the same construction, and it reads what a comb filter cannot, because it never asked for a period.

An **outlier on a locally flat signal** is identified by NEARNESS. `measure/local_outlier` flags a sample that leaves the band its own neighbors draw, and `reference/windowed` replaces it with their median. The **sparse outlier** row is the Hampel filter with its magic number removed: the band is drawn from the neighbourhood instead of chosen as a multiple of the median absolute deviation. It sweeps two floors as well, because impulses crowding a window and a signal that varies under them are separate ways for the median to stop being the right answer.

`period_background_and_its_null.py` is the stage three reading under the first two: the phase-mean background at the true period against the same background on a shuffle. The part of the reading that clears the null is visible.

### What these are and are not

Each method runs on a **synthetic positive control built in the script**, because a full rejection can only be proved against a signal whose clean form is known. Every one reports a **drawn null** and a **stated floor**: the noise shaped exactly like the target, which no instrument can reject. A method with two ways to fail reports two floors, since a floor quoted at one setting is a different claim from a floor that moves with a parameter. Every one runs **two independent routes** that agree bit-exact where both hold and split where the data no longer carries an answer, and each shows that the routes can genuinely disagree. Their agreeing is evidence and not an identity typed twice.

Each also carries a **negative control**, because a bit-exact 100% on a matched control proves only that the pipeline is wired and the arithmetic exact: it cannot tell a detector from an identity that cancels whatever was injected. So each method runs the cases that must **not** read 100% beside the one that must, which in the sweep is the wrong-reference column standing next to the matched one. A signal with no noise, and the wrong kind of noise, are both required to be declined, leaving the signal untouched or the noise intact. **The number a reader will quote is the 100%, and the thing that licenses it is the 0%**: a coherent remover scoring zero on impulses, an impulse remover scoring zero on a hum, non-local means scoring zero where no context recurs, and the rank filter drawing no flags on a smooth signal, are what separate detecting what is present from cancelling what was injected. Without that arm, a real 100% and an identity's 100% read the same.

The decision boundary is itself drawn, not chosen, and each filter draws it in the terms of its own invariant. The comb filter's is a **band**, the spread of the strongest dispersion ratio over several shuffles, printed beside the live ratio so a marginal single-digit case shows how much margin is the effect and how much is the draw. Non-local means declines a context that recurs only once, a group of one with no other evidence. The rank filter declines a sample inside the spread its neighbors already show. None of the three is a constant chosen until the output looked right. The 100% figures are exact on the controls; a reading on a real recording would report the measured reduction with its floor beside it. A native-C route is the natural hardening of the reconstruction and is not claimed here.

### What maps to this engine, and what does not

The filters here are the ones whose identifying invariant can be drawn from the data and read exactly. Not every named filter can. The families sort by which of the tree's rules a filter would have to break, and naming the ones that do not fit is as much the point as building the ones that do.

- **Fit, and are built here.** The comb and notch (periodic), the impulse consensus, non-local means (self-similarity), and the rank or Hampel outlier filter. Each has an invariant -- position, a repeating target, recurring content, local nearness -- that a grouping reads and a null draws.
- **The matched filter is already here** as the anchor sift: a subset of a pattern's points is a necessary condition over any index set, the necessary-condition half of matched filtering, in `src/engine/python/sift/`.
- **Excluded by principle: the model-based filters.** Wiener needs the signal and noise power spectra, and Kalman and the adaptive LMS and RLS filters learn a model from the stream. This engine has no model, no prior and no training by construction. These are outside it not by capability but by what it refuses to assume.
- **Excluded by the pure-Python constraint: the transform filters.** A low-pass, high-pass or band-pass filter, wavelet thresholding and spectral subtraction all read a frequency basis, the dense-array and FFT path the dependency ban keeps out. The engine's own answer to scale is `partition/coarsen`, reading at the scale where structure sits. A true spectral filter belongs to a numpy port, stated as such.
- **Excluded by no bounding: the tuned-tolerance filters.** Bilateral filtering picks an intensity kernel width, total-variation denoising picks a regularization weight, and the classic Hampel picks a multiple of the median absolute deviation. Each is a judgement-picked tolerance. Where the tree has a relative it draws the boundary instead: non-local means with an exact context in place of a bilateral bandwidth, and the drawn-band outlier filter in place of the MAD multiple.

## The vocalization null is still missing

The stage three script above is a null for a **byte-valued signal at sample scale**, which is what the filters need. It is **not** the null a vocalization reading needs, and that one is still unwritten. The unit of a vocalization is a call, not a byte. Permuting bytes destroys the calls themselves instead of their order. What that reading needs is a null that keeps each call intact and permutes the sequence of calls. Until it exists, a departure measure over segmented calls has no background to stand against.

The recordings are fetched by `maint/data/fetch/vocalization_domain.py` and `maint/data/fetch/infrasound_domain.py`.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
