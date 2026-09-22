# The dimensional transforms

Seven transforms carry this work. They look unrelated and they do one thing: they express the same
information in coordinates where a question is easier to ask. None of them creates information and
none destroys it, which is why each has an inverse or is lossless at full rank.

This records what each one translates between, what the translation buys, and the single condition
under which any of them helps at all.

## The seven

**The bitpack.** An integer and a run of 32-bit limbs are the same bytes named twice. `to_bytes` and
`from_bytes` are not conversions; they are two vocabularies for one object. This is what lets a
number be handed to a device that only knows arrays, without anything being computed.

**Fixed point.** A real to whatever depth is paid for, held as an integer scaled by a power of two.
The reals are the human coordinate and the integer is the machine's, and the translation is exact in
both directions. The whole floor question turns on this: a residual that stops at 1e-16 is speaking
float64, one that falls with the width is speaking the object.

**The number-theoretic transform.** Coefficients to evaluations and back. A polynomial of n
coefficients evaluated at n points costs n squared pointwise and n log n through the transform,
because the transform shares work between the points that pointwise evaluation repeats.

**The four-step fold.** One dimension of length N becomes two of P by Q, with a twiddle between
them. Nothing is lost - it is a relabelling of the same indices - and it is what makes a transform
too large for one pass fit in two.

**The golden placement.** An index becomes a direction. Index k goes to height 1 minus 2(k+0.5)/n at
longitude k gamma, and 256 bit positions become 256 points on a sphere with no seam and no pole
pile. A one-dimensional list becomes a two-dimensional surface.

**The harmonic expansion.** A set of points on that surface becomes (L+1) squared coefficients
sorted by angular scale. At full rank it is lossless, so it is a change of vocabulary and not a
summary, and the sorting is what it buys: structure at a scale concentrates in one band instead of
smearing across 256 numbers.

**The permutation as an orthogonal map.** k observations of a quantity become a vector in k
dimensions, and correlation becomes the cosine of an angle. A permutation is then a rotation within
the coordinate subgroup, preserving every length and randomising every angle. This is the one that
was hiding in plain sight all night as "shuffling the data".

## What they preserve and what they move

Every one preserves the information and moves the coordinates. That is the whole family resemblance
and it has a consequence worth stating flatly: **a transform cannot make a question answerable that
was unanswerable. It can only make an answerable question cheap.**

The engine is faster because of the NTT, not more capable. The boundary reading is legible because
of the harmonic expansion, not more informed. Nothing in this tree computes anything a slower
arrangement could not compute, and stating that plainly is what keeps the rest of the claims
defensible.

## The single condition: rank deficiency

A transform pays when the object has fewer coefficients than it has points. That is the entire
mechanism, in every case.

Multipoint evaluation is fast because a degree-n polynomial has n coefficients however many places
it is evaluated, so the work at one point overlaps the work at the next. Harmonic sorting is useful
because a smooth field has most of its power in low degrees, so the high ones can be dropped. The
arms pool because independent observations share a mean, so k of them carry one number's worth of
uncertainty rather than k.

Which says exactly when a transform is useless, and the test for it is direct. A Boolean function of
degree below k sums to zero over any k-dimensional affine subspace, so a cube of inputs collapses if
and only if the function is rank-deficient in that sense. Measured over 126 cells at every depth from
eight rounds to sixty-four, nothing collapsed: every cell sat near 128 of 256, which is full degree.

**An object at full rank in a basis has as many coefficients as points, and no change of basis
helps.** Not "the transform is slow" - there is nothing for it to share. That is why no transform in
this tree could shortcut a hash and why every one of them speeds up arithmetic: polynomials are
rank-deficient by construction and a hash is built specifically not to be.

## Where a translation earned its keep, and where it did not

**Earned it.** The permutation-as-rotation reading explained why independent observations discriminate
so sharply, and did it better than the counting argument it replaced: in k dimensions random vectors
are nearly perpendicular, with typical cosine root(2/pi k) - 0.051 at 245 dimensions, 0.025 at 1000.
The discrimination is concentration of measure, not sample size, and that framing predicts the right
scaling where counting did not.

**Earned it.** The harmonic expansion beat every rival scanner on spatial structure by a factor of
twenty-two, 328 standard errors against 14.8, because sorting by angular scale is exactly the
coordinate in which a shape is one coefficient instead of 256.

**Did not.** The same expansion read 2.43 against its own 3.75 floor on a forced parity - below its
own noise. A parity is not a linear property of which points are lit, so the expansion is blind to it
by construction, and the crudest scan in the comparison was the one that caught it. A transform
translates into one language and is deaf in every other.

**Did not.** Reading a state through a mirrored placement looked like a chirality test and was a
geometric identity: reflection negates every longitude, which conjugates every coefficient, which
negates every phase, for any data whatever. The answer was fixed before the data was consulted. A
transform's own symmetries can produce a result that says nothing about the object.

## The practical form

    1. Ask what coordinate the question is naturally cheap in.
    2. Check the object is rank-deficient in that coordinate, because otherwise the move is free
       of benefit as well as free of cost.
    3. Apply the transform, which changes nothing but the vocabulary.
    4. Check the result is not a symmetry of the transform rather than a property of the object -
       run the same reading on data with nothing in it and see whether the answer moves.
    5. Translate back, and state the finding in the coordinate the question was asked in.

Step four is the one this work learned the hard way, twice.
