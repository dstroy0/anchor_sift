# The compression state deforming a boundary, twenty five slices

Twenty five frames of `sha_clock_view.html` at one fixed camera, one frame per listed round, with
every other input held still. The sequence exists because the surface visibly changes shape across
the clock, and a sequence taken under stated conditions is the difference between that being an
observation and being a measurement.

## What is in the picture

SHA-256 compressing the empty message, sixty four rounds. The 256 bits of the compression state
light 256 points on an eight by thirty two ring placement, so bit `i` lights point `i` and no
mapping had to be invented to make the instrument fit the object. The boundary field is expanded to
degree 10, which is 121 modes, with conduction `tau = 0.0008`. Two neutrino sources cast beams that
stop on lit bits, and the count of beams stopped equals the count of bits set.

## The conditions every frame was taken under

| | |
| --- | --- |
| message | the empty string, padded, one block |
| camera | fixed, `dist = 52`, unmoved across all twenty five frames |
| clock | paused, `speedBox = 0`, `motion = 0`, `tickRate = 0` |
| beam | fixed at `beamA = 40`, `beamB = 88`, `beamR = 17` |
| degree | 10 of 10, 121 modes, `conduct = 25` |
| scale | 0.34 of a 1288 by 930 viewport |

The camera is the important one. Perspective distortion is fixed when the camera is fixed, so it
cannot produce a change between frames. Every difference across this sequence belongs to the object.

## Files

`round-NN.jpg` for rounds 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31, 33, 35, 37,
39, 41, 45, 49, 55 and 64.

`side-round-01.png` and `side-round-32.png` are the same object from a viewpoint near the equator,
where the silhouette reads and the shape is legible. `core-zoom-op122.png` is the core alone, close,
showing the hot and cold bits arranged along spiral arms.

## What was measured on it

One mesh in the scene is deformed and only one. Its vertex radii have a standard deviation of 0.999
against a mean of 8.795, which is 11.4 percent. Every boundary shell measures a standard deviation
of exactly 0.0000, so the three nested boundaries are perfect spheres and the 256 bits sit on a
perfect sphere at radius 7.128.

Reading that surface as a radius field over the sphere:

| quantity | measured |
| --- | --- |
| quadrupole `q_zz` | near `-1.50` at every round, 17 percent of mean radius |
| dipole `d_z` | swings about `0.07` and changes sign several times |
| sign runs in `d_z` | 6 runs in 25 rounds against 13.3 plus or minus 2.4 expected |
| runs test | **z = -3.0** |

So the elongation is a fixed feature that never leaves, and the cone walks around and inverts more
than once. The runs figure says the motion is autocorrelated across the clock: the surface moves
continuously and does not jump.

## The intervention, which establishes the cause

An observation that the picture changes when the clock advances does not say what changed it,
because the clock advances everything. So the beam was moved instead, with the state held still:

| condition | mean radius | `d_z` | `q_zz` |
| --- | ---: | ---: | ---: |
| op 249, beam at its usual place | 8.7903 | 0.00848 | -1.5044 |
| op 249, beam swung 180 degrees in azimuth, 128 in elevation, 4.7 times in radius | 8.7903 | 0.00848 | -1.5044 |
| op 249, beam restored | 8.7903 | 0.00848 | -1.5044 |
| op 257, beam untouched | 8.9428 | **0.04313** | -1.5056 |

A large move of the probe changed nothing in any digit. One round of the clock moved the dipole by
five times. The surface is driven by the compression state and not by the probe, and that is
established by moving the suspect instead of by arguing about it.

## The likely cause, which is not exotic

The round computes two words and shifts the other six:

    a' = T1 + T2      e' = d + T1
    b' = a            f' = e
    c' = b            g' = f
    d' = c            h' = g

Six of the eight words at round `r` are words from round `r - 1` in a new position, measured at 63
of 63 rounds in `examples/proofing/state_deflection.py --check`. A surface computed from a state
that is five sixths unchanged cannot jump, so the autocorrelation this sequence shows is very
probably the shift register appearing in the shape.

That is worth saying plainly because it is the interesting reading and not a deflation. The viewer
was built to show a field. Nobody built it to show the compression function's internal structure,
and the structure turned up in it anyway, legible to the eye and holding at three deviations when
somebody goes and measures it.

**The control that would settle it** is to drive the same surface from independent states of equal
weight, with no carryover between rounds, and repeat the runs test. If `z` falls toward zero the
shift register accounts for all of it. That control has not been run.

## Reproducing the sequence

    python tools/view/build_sha_clock_view.py
    python -m http.server 8731        # from build/view

Open `sha_clock_view.html`, set `speedBox` to 0, set `opBox` to `(round - 1) * 8 + 1`, and read
`stops`, or read the deformed mesh directly from the scene graph. The numeric side is in
`examples/proofing/state_deflection.py`, whose compression agrees with the published digest of the
empty string before it reports anything.
