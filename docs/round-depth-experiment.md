# Round count as depth: measuring the decay instead of hunting the hole

An experiment the tree can run today, on instruments it already has. It does not try to break
SHA-256. It measures how fast the interior stops reaching the boundary as a function of how many
rounds it passed through, and reports where that curve crosses below the detection floor.

## The idea in one line

The boundary work measured information reaching a surface as a function of depth, and found it falls
as `(r/R)^l`. Here depth is the round number. The question is the same one: how much of the input
reaches the output, measured against how far in it started.

## Why this is the right question and breaking it is the wrong one

A break needs a boundary observable that departs from flat by more than sample noise, at full
rounds. The tree's own instruments say there is none: `H(digest | input) = 0`, so the bias bound is
limited by sample size alone with no floor beneath it, and the keyhole, SAC and Renyi benches read
flat at full rounds. Twenty years of linear and differential cryptanalysis reach about 31 of 64
rounds and no further. Hunting the full-round hole is hunting a thing the detector already says is
not there.

Measuring the decay is different. Reduced rounds leak, everyone knows they leak, and nobody has
written down the leak as a curve in the depth variable with a detection floor drawn on the same
axes. That curve is a real result. It quantifies the difficulty instead of asserting it, and it
makes a falsifiable claim: the leak at round k is this size, and here is where it falls under what
this many samples can see.

## What is measured

Run SHA-256 truncated at `k` rounds, for `k` from 1 to 64, and read a boundary observable at each.
The observable is one already built:

- **strict avalanche.** Flip one input bit, count how often each output bit flips, over many inputs.
  A flat function sits every counter at half the sample size. The departure from half, summed
  across output bits, is the leak. This is the keyhole scan with the round count as a parameter.
- **bit bias.** How far each output bit's one-rate departs from half. The survey bench, truncated.
- **collision entropy of the output byte histogram.** The Renyi bench, truncated.

Each returns a single number per round count, so the run is one curve per observable, 64 points
each.

## The detection floor, drawn on the same axes

A bias of size `b` needs about `1/b^2` samples to see above the noise. So `N` samples can see down
to about `1/sqrt(N)`. That floor is a horizontal line on the same plot as the decay curve, and where
the curve crosses under it is the round count past which this run cannot tell the function from flat.

The floor is not a nuisance to be hidden. It carries the result: it says what was in reach of this
much compute, and a later run with more samples can lower the line and show the curve continuing
underneath, or show it genuinely flattening.

## The exact-arithmetic role

The decay spans many orders of magnitude, from a large leak at a few rounds to nothing measurable at
full rounds. Read in single precision the small end is noise about noise. The `representation`
arm's exact contract carries the small counts without rounding, so the curve stays a curve down to
where sample size and not arithmetic stops it. That separates measuring the decay from
measuring the floating-point floor, and it is the reason this experiment belongs in this tree and
nowhere else.

## What each outcome would mean

- **The curve falls smoothly and crosses the floor around the round count cryptanalysis already
  reaches.** The expected result. It turns the known reduced-round weakness into a measured decay
  rate and puts a number on the margin.
- **The curve has a step, a shoulder, or a bump that does not fall.** A round range where more
  structure survives than the smooth decay predicts. That is where a cryptanalyst would look, and
  the framework would have pointed at it instead of guessing. Almost certainly it will not happen at
  full rounds, but the experiment is what would show it if it did.
- **The curve is already under the floor by a few rounds.** The samples were too few. Lower the line
  with more samples and run again. Nothing is concluded from a curve that starts under its own
  floor, and passing that check is what a run does before its flat tail means anything.

## What this does not claim

It does not claim a break, a bias at full rounds, or a shortcut to a preimage. It claims a
measurement: the leak as a function of depth, with the floor that says how far down the measurement
could see. A flat tail under a floor is not evidence the function is flat there. It is evidence the
run could not see a leak that small, a statement about the run and not about SHA-256.

## Running it

The benches exist in `src/bench`. This experiment is a driver that calls them with a round-count
parameter and collects the curve, plus a plot through `build_chart_view.py` with the floor drawn as
a second series. The one piece of new engine work is truncating the compression function at an
arbitrary round, which the early-exit path in `sha256_core.c` already does for the anchor and would
be extended to stop at any `k`.
