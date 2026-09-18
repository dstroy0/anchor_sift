# Art

**Purpose:** Read a picture as points carrying values, recover the geometry it was stored with, and reject the noise a camera adds.
**Scope:** `examples/art/`

| stage         | script                                  | what it answers                                                                           |
| ------------- | --------------------------------------- | ----------------------------------------------------------------------------------------- |
| `1_represent` | `picture_true_size.py`                  | the true dimensions of the stored pictures                                                |
| `2_partition` | `morton_squash.py`                      | carrying a plane through one dimension by interleaving its coordinates                    |
| `4_measure`   | `a_picture_returns_its_width.py`        | an image read as a sequence, told nothing, returning its own width                        |
| `4_measure`   | `picture_width_agreement.py`            | whether the two instruments agree on one picture                                          |
| `4_measure`   | `regeneration_limit.py`                 | how much of a set a summary can put back                                                  |
| `4_measure`   | `scale_ladder.py`                       | separating what was made from how it was recorded, across scales                          |
| `4_measure`   | `fixed_pattern_removed_to_the_bit.py`   | fixed-pattern video noise removed to the bit                                              |
| `4_measure`   | `noise_across_formats_and_qualities.py` | the same removal held across image formats and kinds of noise                             |
| `4_measure`   | `classify_reject_recover.py`            | classify the noise on a stack, reject it, return the clean subject with exact uncertainty |

Stages three, five and six are not present for this subject.

## A picture is the case the construction was written for

A picture is a domain whose alphabet is a range of values and whose arrangement has two dimensions, which is exactly what the engine reads. Read row by row, the second dimension survives as a periodicity, because a pixel and the pixel below it lie one width apart in the sequence. `a_picture_returns_its_width.py` recovers that width from nothing, and the other stage-four scripts read the same picture through the rest of the construction.

## Fixed-pattern noise

`fixed_pattern_removed_to_the_bit.py` is the image subject's noise filter, and it is the same instrument the sound denoiser uses, on pictures instead of a waveform. Nothing is ported between them: `reference/periodic` and `measure/periodic_energy` read points carrying values and cannot tell a frame stack from a sound signal, which is the README's one instrument shown reading the second medium.

Fixed-pattern noise is the coherent noise of a camera, a per-pixel offset the sensor adds to every frame. Read a frame stack frame after frame and that offset repeats with a period of exactly one frame. It is the coherent-addend case: the fixed pattern is the per-pixel mean across the frames and the residual is the moving scene. Where the scene moves everywhere and sits still nowhere the pattern is removed to the last bit.

It runs on a **synthetic positive control** built in the script, because a full rejection is only provable against a known-clean signal. It reports a **drawn null**, **two independent routes** shown able to disagree, and a **stated floor** that is worth naming because it is the reason a real fixed-pattern correction needs a dark frame or motion: a scene feature that never moves is a constant per-pixel offset across the stack, which is the exact shape of the noise. It cannot be told apart and is removed with it.

It also carries a **negative control**, because a bit-exact 100% proves only that the pipeline is wired: a stack with no fixed pattern and a stack corrupted by impulses are both required to fall inside the null band and be declined. The 100% is reached only where a fixed pattern is genuinely present and not wherever something was injected. **The number a reader quotes is the 100%, and the thing that licenses it is the 0%** the wrong noise scores. The decision boundary is drawn, not chosen: the null is the spread of the strongest ratio over several shuffles, the reading counts only above its top, and the script prints that spread so a marginal case shows how much margin is the effect and how much is the draw. The figure is exact on the control; a real stack would report the measured reduction with that floor beside it. A native-C route is the natural hardening and is not claimed here.

**The tightest arm, named while it still passes.** The no-pattern arm is the closest call in the whole suite. It sits at about 2.9 inside a band spanning roughly 1.4 to 3.9, three quarters of the way to the ceiling it must stay under, while every other arm is decided by a factor: the matched pattern clears the band by more than a hundred times. So if any arm here ever flips, it is this one, and it will flip because eight shuffles happened to draw a low ceiling. Whoever sees it fail should look at the band and the draw count before looking at the filter, and widening the draw is the first thing to try.

## Across formats and qualities of noise

`noise_across_formats_and_qualities.py` (ART-4-006) runs the same removal along the two axes a reader asks about next: the format the pixels are stored in, and the kind of noise. It adds no instrument. The detector is `measure/periodic_energy` and the reject is `reference/periodic`, the same two files ART-4-005 used, fed pixels from more places and noise of more kinds. Every number is exact rational; the only floats are the ones printed.

**A lossless format changes nothing, and a lossy one is a noise source.** The detector reads points carrying values and cannot see a container. The same synthetic stack written to 8-bit PNG, to 16-bit TIFF, and to 8-bit RGB PNG, then read back, is identical to the bit, and the removal stays at 100%. JPEG at quality 92 is the exception and the point: its block quantization depends on the local content, the one fixed pattern added to different frames decodes to a different pattern per frame, the per-pixel mean is no longer the pattern, and the removal reaches 97.82%. That row measures how much noise the format itself injected.

**The exact removal holds for one kind of noise, and amplitude decides whether it is seen, not whether it is removed.** A coherent additive fixed pattern is removed to the bit at every amplitude, because the arithmetic is exact at every amplitude. What amplitude moves is the detector's margin over the drawn null: at amplitude 4 the reading sits at 2.86 inside a band topping 7.44 and is declined, and only from amplitude 8 up, at 11.84 over 7.45, does it clear the band and remove. A weak pattern fails to be seen, not to be removed, and that detection limit is the honest signal-to-noise floor. Every incoherent kind is declined and left almost untouched: independent per-frame Gaussian at 1.42%, impulses at 2.33%, Poisson shot at 2.23%, each sitting inside its own band. A fixed pattern under Gaussian, the mix a real sensor gives, reports 52.30%, the coherent fraction, a measured number between the two and not 100%.

**Real CTC frames carry the floor.** Real 16-bit fluorescence tiles from Fluo-N2DH-SIM+, read straight from the local zip under `repos/external/datasets`, give two readings. The tile as it is declines: the detector sits at 2.235 below a band topping 3.427, a real-world negative control that shows the 100% is not handed out for free. The tile with a known fixed pattern added removes it and reaches 96.83%, not 100%, because real content does not sum to zero at each pixel across the frames. The shortfall is the floor the fixed-pattern section named, now shown on real data: a static background is a per-pixel offset across the stack, the exact shape of the pattern, and it leaves with it. This is the measured reduction on real content that the bit-exact control stood in for.

**Running it.** This script needs numpy and Pillow, which `fixed_pattern_removed_to_the_bit.py` did not. The CTC arm also needs the dataset present; fetch it with `python maint/data/fetch/fetch_ctc.py --fetch Fluo-N2DH-SIM+`, and where the zip is absent that arm prints that it did not run and every other arm still reports.

```
python examples/art/4_measure/noise_across_formats_and_qualities.py
```

## The proofing filter: classify, reject, recover

`classify_reject_recover.py` (ART-4-007) reads a stack of same-source images: it classifies the noise, rejects it, and returns the clean subject with the uncertainty stated exactly, zero where two exact routes agree and flagged where they do not.

The honest core is that a coherent per-pixel component across a stack is either the subject, when it is the same in every frame, or the noise, when the subject varies and a pattern is fixed. No measurement on the stack separates them, because which one counts as signal is a declaration and not a finding. The filter therefore takes a mode. `--mode fixed-pattern` treats the shared component as noise and subtracts the per-pixel mean, exact to the bit where the subject sums to zero at each pixel across the stack. `--mode repeat` treats it as the subject and keeps it by per-pixel consensus, exact where a strict majority of the frames survives. Running one mode's reject on the other's case erases the answer, and the mode is the guard, with no default that guesses.

The controls, run with no arguments, walk both modes across their boundaries. A fixed pattern over a varying subject recovers the subject to the bit with zero pixels flagged. Incoherent noise over a varying subject is declined, because it does not clear the drawn null band. Impulses over a repeated subject recover it to the bit by consensus. Incoherent noise over a repeat leaves 54 of 64 pixels flagged, the honest statement that averaging is not exact recovery where no per-pixel majority exists.

On how far this goes: the reject runs on unbounded integers. It has no size or depth limit and introduces no rounding, and that is where the zero uncertainty lives. The constant that bites is registration, the exact translation that aligns a real stack. For binary thresholded pages each correlation coefficient stays below the modulus and the alignment is exact with one prime; grayscale needs CRT over the three word-lane primes. The real limit on a set of scanned pages is not a prime but the registration: pages that drift in size are not pixel-aligned, translation alone cannot absorb a scale drift, and scale and rotation registration are design-only today. The exact zero is delivered on a registered stack and a measured reduction with its floor on one that is not.

**Running it.** Needs numpy and Pillow. With `--mode {fixed-pattern,repeat} --in DIR --out DIR` it runs a real same-size stack and writes the clean frames or the consensus image and an uncertainty map; with no arguments it runs the controls.

```
python examples/art/4_measure/classify_reject_recover.py
```

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
