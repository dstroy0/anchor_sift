# Art

**Purpose:** Read a picture as points carrying values, recover the geometry it was stored with, and reject the noise a camera adds.
**Scope:** `examples/art/`

| stage | script | what it answers |
|---|---|---|
| `1_represent` | `picture_true_size.py` | the true dimensions of the stored pictures |
| `2_partition` | `morton_squash.py` | carrying a plane through one dimension by interleaving its coordinates |
| `4_measure` | `a_picture_returns_its_width.py` | an image read as a sequence, told nothing, returning its own width |
| `4_measure` | `picture_width_agreement.py` | whether the two instruments agree on one picture |
| `4_measure` | `regeneration_limit.py` | how much of a set a summary can put back |
| `4_measure` | `scale_ladder.py` | separating what was made from how it was recorded, across scales |
| `4_measure` | `fixed_pattern_removed_to_the_bit.py` | fixed-pattern video noise removed to the bit |

Stages three, five and six are not present for this subject.

## A picture is the case the construction was written for

A picture is a domain whose alphabet is a range of values and whose arrangement has two dimensions, which is exactly what the engine reads. Read row by row, the second dimension survives as a periodicity, because a pixel and the pixel below it lie one width apart in the sequence. `a_picture_returns_its_width.py` recovers that width from nothing, and the other stage-four scripts read the same picture through the rest of the construction.

## Fixed-pattern noise

`fixed_pattern_removed_to_the_bit.py` is the image subject's noise filter, and it is the same instrument the sound denoiser uses, on pictures instead of a waveform. Nothing is ported between them: `reference/periodic` and `measure/periodic_energy` read points carrying values and cannot tell a frame stack from a sound signal, which is the README's one instrument shown reading the second medium.

Fixed-pattern noise is the coherent noise of a camera, a per-pixel offset the sensor adds to every frame. Read a frame stack frame after frame and that offset repeats with a period of exactly one frame, so it is the coherent-addend case: the fixed pattern is the per-pixel mean across the frames and the residual is the moving scene. Where the scene moves everywhere and sits still nowhere the pattern is removed to the last bit.

It runs on a **synthetic positive control** built in the script, because a full rejection is only provable against a known-clean signal. It reports a **drawn null**, **two independent routes** shown able to disagree, and a **stated floor** that is worth naming because it is the reason a real fixed-pattern correction needs a dark frame or motion: a scene feature that never moves is a constant per-pixel offset across the stack, which is the exact shape of the noise, so it cannot be told apart and is removed with it.

It also carries a **negative control**, because a bit-exact 100% proves only that the pipeline is wired: a stack with no fixed pattern and a stack corrupted by impulses are both required to fall inside the null band and be declined, so the 100% is reached only where a fixed pattern is genuinely present and not wherever something was injected. **The number a reader quotes is the 100%, and the thing that licenses it is the 0%** the wrong noise scores. The decision boundary is drawn, not chosen: the null is the spread of the strongest ratio over several shuffles, the reading counts only above its top, and the script prints that spread so a marginal case shows how much margin is the effect and how much is the draw. The figure is exact on the control; a real stack would report the measured reduction with that floor beside it. A native-C route is the natural hardening and is not claimed here.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
