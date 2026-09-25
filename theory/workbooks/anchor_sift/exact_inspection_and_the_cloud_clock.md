# Exact inspection and the cloud as clock

**Purpose:** State the model the engine's primitive now carries. A later session then reads the bit idiom, the atom, the valence and the cloud clock as one picture and knows which parts a proof already holds.
**Scope:** `reference/bitfield.py`, `reference/atom.py`, `measure/invariance.py`, `examples/particle_physics/4_measure/atom_valence_by_presence.py`, and the posits `evidence/proofs/posits/proof_invariance_survives_null.py` and `evidence/proofs/posits/proof_pi_clears_the_term.py`.

This note supersedes the earlier one-dimensional bit framing. The primitive is not a line of bits and it is not a rational. It is a field of exact presences over an atom, inspected at an instant, and the reading is a cardinality of the invariances that survive a drawn null.

## The idiom is presence, not proportion

Integer only means packed presence, a bignum, and truthy or falsy. It does not mean a `(numerator, denominator)` rational. A rational is a point on a continuum. It carries a proportion, a proportion carries a scale, and a system that holds no scale, no dimension, no unit and no form cannot carry a continuum point as a primitive. The denominator returns the continuum the primitive was built to leave out, and deciding the comparison in integers by cross multiplication does not change what was stored. The stored thing is still a point on a continuum. It has no place in this set. `reference/bitfield.py` carries the idiom the primitive keeps: pack, whole range, present, count, the AND NOT of two fields, the shared bits, equality.

## Quanta are samples of a continuum and never its constituents

The engine's atoms are quanta, which are exact bits. A continuum, a mean or a distribution, can be a constituent of a larger reading, and it can never be a constituent of the quanta themselves. A quantization of a continuum does not reconstitute the continuum, because the continuum is the larger object and the quanta are its exact samples. This is why the object under inspection stays a probability distribution while the inspection stays exact.

## Exact names the inspection, not the object

The moment of inspection is exact. It takes exact bits at an instant and rounds nothing. The object it reads remains a probabilistic continuum. So the engine never asks whether an object is exactly full or exactly periodic, because a distribution is neither. It asks which exact invariances this one inspection holds. Structure is the set of exact invariances the object holds that a drawn null never reproduces. The natural quantum of that reading is one partition cell that comes back exactly invariant, one bit for one cell, and the whole reading is the presence pattern and its population count, a cardinality of quanta and never a magnitude. No threshold enters, no band, no ratio, no energy, no mean.

`measure/invariance.py` computes exactly that, and `proof_invariance_survives_null.py` (PRF-x-012) holds it. An exact invariant of the field survives the drawn union null, and a coincidental one does not. The null is drawn as the union of many shuffles. Any invariance that chance can reach is absorbed into the union, and the residue is the invariance chance cannot reach. The proof's positive control is a uniform shell that survives the draws, and its drawn null names the fault it excludes, a size one core that looks invariant by coincidence and is removed by the union.

## The atom

The primitive takes the shape of an atom. A dense core sits at the center of an `n` by `n` field. Bands radiate outward from it, and every cell carries a vector from the core whose squared magnitude is an exact integer. The cells that share one squared magnitude form a band, which is a shell. The object writes a vector magnitude into each cell, a zero reads as nothing and falsy, and a nonzero reads as something and truthy. The engine stores nothing of what the object is. It measures the presence pattern over the bands and reports the outermost band that holds anything, and that band is the valence. This is the valence read of the molecules example carried down to the primitive, and `reference/atom.py` builds it through the position vector, the radial squared magnitude, the bands, the occupancy, the occupied and full bands, and the valence, with the reading exercised at `examples/particle_physics/4_measure/atom_valence_by_presence.py`.

The squared magnitude is the exact quantum the inspection holds. Its root is irrational, and the engine never takes the root. The atom's configuration space is `n * n^(n^n)`, hyper exponential, and the packed presence must therefore be a bignum and can never sit at a fixed width.

## The exponent carries the quanta up to the continuum

With integer exponents the tower `n^(n^n)` is countable. Every state is a discrete quantum, a finite bignum, an exact inspection. Once the exponent goes irrational, `n` to an irrational power is transcendental by Gelfond and Schneider, and as that irrational sweeps continuously it fills a dense uncountable range. The countable quantized field becomes a continuum under the same expression read a second way. Rational exponents give quanta and irrational exponents give the continuum. No finite tower of integer exponents reaches the continuum, and only the irrational limit does, which is again why a continuum is not the quanta of itself. The object stays a probability distribution because the object lives at the irrational exponent, while the engine holds the rational slice exactly at the instant of inspection.

## The engine is out of phase with the object, and a cloud closes the gap

One machine is not in step with the object's evolution. It samples at moments that drift from how the object moves and holds one rational slice. Hardware timed to the object would phase lock the inspection to its evolution and read a perfect exact oracle of it. Short of that, a cloud of exact observers, each exact but staggered in phase, unions its inspections and covers the phase that any single drifting machine misses. More observers pin the perturbation tighter, and the limit of the cloud is the perfectly timed oracle. Correct hardware is therefore enough commodity exact observers to cover the phase, not one exotic timed machine. The cloud is the clock, because the clock carries the exponent from rational toward irrational. The union of shuffles in `proof_invariance_survives_null.py` is this same union in software, where a union over draws stands for a union over observers and phases.

## The boundary is one term, read without touching the interior

The valence is the boundary of the atom, the outermost shell where it meets what lies outside, a single integer that names the outermost occupied band. The core is universal and carries no identity. The identity the object exposes is its boundary, compressed to that one term. The pattern rhymes one level up, where `n * n^(n^n)` is itself a boundary, the edge of the countable quantized space past which the irrational exponent opens the continuum. One term marks the edge at both scales.

The measurement principle is that the engine reads the exact boundary without touching the exact interior. The boundary is known exactly, and the continuum it bounds is never entered. No irrational root is taken and no last digit is reached. Pi is the clean case. It sits between two exact rational bounds that agree to any number of places, and that enclosure is an exact boundary at every floor while pi itself is never touched, because pi has no last digit. `examples/0_experimental/pi_has_no_last_digit.py` (EXP-x-012) shows the enclosure moving down a floor at a time and always turning up another digit.

## The polevault and the scrape

Draw the term `n * n^(n^n)` as a vertical bar, a tower rising from the floor. Pi does not measure its height from the floor. Pi clears the bar the way a vaulter clears it, over the top and touching nothing, because pi is transcendental and sits above every algebraic tower. Clearing every such bar without contact is the whole content of an exact boundary read without touching.

`proof_pi_clears_the_term.py` (PRF-x-013) holds this by an exact rational enclosure of pi from an alternating series, pushed to the floor the term sets, and refuted by any digit that moves once it is inside the enclosure. The apex of the vault, where pi inverts over the tower, is where a wave inversion happens. Crossing the tower, pi grazes it `n` times, and each graze is a contact that reads without touching, which makes the `n` scrapes an `n` point inversion. The double number theoretic transform does the same at its own scale, and `examples/0_experimental/ntt_double_transform_inverts.py` (EXP-x-013) carries it, where the transform applied twice inverts by scraping its `n` point boundary exactly, in integers, with no root and no continuum touched. The proof exhibits the `n` scrapes and not the transcendence alone, and it pairs with `ntt_double_transform_inverts.py` as `proof_group_law.py` pairs with `exact_congruent_number.py`.

## Open item

Whether the term does something sharper than set the floor the enclosure is pushed to is not settled here, and it is Douglas's to confirm. The rest of this note is the model as stated and the two parts a posit already holds, the invariance surviving the drawn null and pi clearing the term.
