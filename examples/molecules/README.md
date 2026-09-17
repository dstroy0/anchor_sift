# Molecules

**Purpose:** Read how atoms assemble from the atomic properties alone, and detect which molecular formulae can carry a valence structure: the bond count an atom carries is a vector magnitude off its outermost shell, an integer with no tolerance, and it dictates the assembly and gates the legal from the illegal.
**Scope:** `examples/molecules/`

| stage | script | what it answers |
|---|---|---|
| `1_represent` | `assembly_from_atomic_properties.py` | the bonds an atom forms, read off its shell, and the assembly they dictate |
| `1_represent` | `build_legal_molecules.py` | build the molecules the valence rules allow, ten thousand and more, from the ledger |
| `6_oracle` | `legal_against_a_wide_set.py` | whether a formula can carry a valence structure, tested against ten thousand real molecules |

The other stages are not written. This subject reads the count. The measured side of a bond, its length, its angle and its energy, is the chemistry subject's oracle, and nothing here reaches for it.

## The capacity is the vector magnitude

An atom assembles by one magnitude its outermost shell carries: the deficit to a closed shell. A shell closes at two electrons for the first and at eight for the main-group shells past it, the duet and the octet, and those are the shell closures the periodic-law measure stage read off the accumulation in `examples/particle_physics/4_measure`. An atom with `v` electrons in its outermost shell is `v` short of empty one way and `closed - v` short of full the other, and it forms the smaller of the two in bonds, `min(v, closed - v)`. That integer is the capacity.

Nothing in the rule is put in. The capacity is read from `element.electrons`, the same ledger the atom stage represents, and the closures are read from the same shells. What comes out is the simplest hydride of each element, the capacity counting hydrogens: carbon at four binds four for methane, nitrogen at three for ammonia, oxygen at two for water, and the noble gases at zero bind nothing. The same capacity gives the bond order of the elements that pair off as gases, H2 single, N2 triple, O2 double, F2 and Cl2 single. It is the deficit to the octet, an integer, with no measured length and no chosen tolerance anywhere.

## Where it stops

One magnitude reads the main group, the first eighteen elements, where the outermost shell is s and p. Beyond argon a d electron arrives, the valence stops being a single number, and this reads no further and says so. The transition metals and their variable valence are left for a later stage or a later hand.

## Building the legal space

`build_legal_molecules.py` walks the assembly the other way. It enumerates the compositions of carbon, hydrogen, nitrogen and oxygen within a bound, turns each into the degree list its atoms carry, and keeps the ones a molecule graph can hold. Each atom's degree is its capacity, read from the ledger through the assembly stage, and the build takes its valences from the shells and puts none in by hand. Over carbon zero to twenty, hydrogen to forty-four, nitrogen to six and oxygen to eight, 17499 compositions carry a legal valence structure.

The keep decision is `connected_multigraph` in `src/engine/python/measure/graph_realizable.py`, a domain-blind test of whether a connected multigraph exists for a given list of degrees, and it is the same gate the wide-set detector runs: what is built legal and what is detected legal are one test. It is a necessary condition and not a sufficient one, and the built space is far larger than the molecules that exist. CO2 is in it, and so are CO4 through CO8, which are not molecules.

The build carries the verification itself, the way the crystallography oracle checks a deposit: it never read which molecules exist, and it agrees with the existing set on a truth it did not use. Of 3982 existing neutral C/H/N/O molecules inside the bound, 3979 are built, and the three misses are named by the gate, two net-neutral salts and carbon monoxide, whose triple bond and lone pair one fixed valence cannot hold. The built space is the outer bound the valence rules draw, and reality is a subset of it: of the 17499 built, 3979 are confirmed by this existing set.

## Legal against a wide set

`legal_against_a_wide_set.py` asks whether a molecular formula can carry a valence structure at all. Read the valence of each atom, the bonds it makes, and three integer conditions decide it: the sum of the valences is even, because a bond spends two, one at each end; no atom carries more valence than all the others together; and the sum is at least twice the atom count less one, or there are too few bonds to join the atoms into one piece. Each is an equality or a comparison on integers, with no tolerance.

The conditions are necessary, not sufficient. This is a sift, and it is measured as one against a wide set: the molecular formulae of the first ten thousand PubChem compounds, fetched by `maint/data/fetch/fetch_pubchem_formulae.py`, a range of identifiers and not a curated pick. Of 10050 formulae, 530 are ions and 292 carry an element the table does not, and both are set aside and counted. Of the 9228 that are neutral and covered, 9183 pass, 99.5 percent, and 45 are refused, 44 for too few bonds and one for an over-connected atom. Inspected, the 44 are net-neutral salts, an organic cation and a separate counter-ion written as one formula, not one covalent molecule and right to refuse. The crafted illegal formulae are the negative control: CH5 for an odd valence sum, CH2 for an over-connected carbon, a lone C for a single atom, each refused for its own reason.

This detects the formula that could be a molecule. It does not check a particular structure: whether a given arrangement satisfies the octet at every atom at once, degree equal to capacity everywhere, is a whole-molecule proposition, and it is the chemistry subject's sift, not this one.

## The boundary with chemistry

This reads the integer count off the atomic structure, the atom subject's to give. How long a bond is, what angle two of them make, and how much energy one holds are measured, and they are the chemistry subject's oracle. The chemistry subject also carries the octet as a whole-molecule sift, degree equal to capacity at every atom at once against a permutation null; this subject stops at the per-atom count and the formula-level existence above. The two do not overlap: one counts the bonds the shells force, the other measures the bonds that form.

The two meet at one integer as a cross-check. The capacity here, `min(valence, closure - valence)`, equals the degree that closes the chemistry subject's octet at a main-group atom: the same number reached by two routes across two subjects. A disagreement on a main-group atom would mean one of the two is wrong.

## Running it

```
python examples/molecules/1_represent/assembly_from_atomic_properties.py
python examples/molecules/1_represent/build_legal_molecules.py
python maint/data/fetch/fetch_pubchem_formulae.py
python examples/molecules/6_oracle/legal_against_a_wide_set.py
```

The assembly stage is generated from the element ledger, with no corpus and no fetch, and its output does not drift between runs. The detector reads a wide set the fetcher gathers from PubChem once, in polite chunks, cached under `build/pubchem`; run without it, the detector still runs its controls.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-17
