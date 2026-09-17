# Particle physics

**Purpose:** Write the atom as the electrons of its neutral state, and the Standard Model particle as its exact quantum numbers, and read the structure, the periodic law and the generations and the vanishing charge sum, out of the representation instead of asserting it.
**Scope:** `examples/particle_physics/`

| stage | script | what it answers |
|---|---|---|
| `1_represent` | `an_atom_as_exact_shells.py` | what an element keeps when it is written as points, and what a coarse reading loses |
| `1_represent` | `an_orbit_as_exact_rationals.py` | the Bohr orbit as an exact rational, a trajectory reproduced with no rounding |
| `1_represent` | `particles_as_exact_charges.py` | the Standard Model particles by exact quantum numbers, and the structure they emit |
| `1_represent` | `hadrons_from_quarks.py` | the baryons and mesons the quarks make, and the integer charge color-neutrality forces |
| `2_partition` | `what_a_quantum_number_costs.py` | what each quantum number is worth as a scale, and what a coarser one agglomerates |
| `3_reference` | `what_exclusion_builds.py` | how much of the periodic recurrence survives shuffling the counts, and removing Pauli |
| `4_measure` | `shell_closures_from_the_difference_set.py` | the row lengths, read off the accumulation with no table told to it |
| `5_sift` | `rarest_anchor_narrows_the_period.py` | a necessary condition the rarest anchor narrows to one lag, all by magnitude and equality |
| `5_sift` | `decays_pass_the_conservation_laws.py` | which decays a bound-free conservation check lets through, and why the proton is stable |
| `6_oracle` | `measured_configuration_vs_ideal.py` | whether the ideal filling matches the measured ground states, and where it does not |

All six stages are present.

## The element is its electrons, and the state is an integer

An element is its neutral atom: Z protons and Z electrons. The representation is the electron set. Each electron is a point at a quantum state, four integers, principal, azimuthal, magnetic and doubled spin, carrying its subshell as a value like `2p`. The spin is carried as its double, `+1` and `-1` for the two halves, so the state stays an integer, the way `src/engine/python/representation/structure/symmetry.py` carries thirds in units of 1/24. No decimal scale is used: `representation.exact` carries 1024 digits for a crystal coordinate, and an electron count is already an integer.

The element ledger, Z and symbol and the Madelung filling order, lives once at `src/engine/python/representation/atom/element.py`. This subject reads it for the periodic law, and `examples/chemistry` reads the same file for bonding, so the element table is transcribed one time and no two readers copy it apart.

## One element read twice

The crystallography reader put every site on a 0.25 angstrom grid on the way in, and the recovered cell edge then carried the grid instead of the deposit. An atom has the same failure available. `an_atom_as_exact_shells.py` reads each element two ways. The exact reading keeps the whole state and places Z electrons at Z distinct addresses. The subshell reading keeps only the first two numbers, principal and azimuthal, and a filled 2p then arrives as one address holding six electrons where the exact reading holds six.

The difference is a count, and only a count. Both readings agree on the value every electron carries, its subshell, and a check that compares values reports nothing. `exact.contested` returns empty on the collapsed reading, because the six electrons of a 2p all say `2p` and none disagrees. The loss sits in the cardinality, and `exact.placed`, a dict, is where the six become one without a word. Over the whole table the subshell reading collapses 5645 electron states, and a value-comparing check flags 0 of them. A reader who trusted the labels to disagree would miss every one.

## Pauli is a count, and it holds

`exact.contested` returns the positions carrying more than one value, and it is domain blind: in a crystal it finds a doped site, two elements at one position, and in an atom it finds two electrons at one state, a Pauli violation. For every element the exact reading places Z electrons at Z distinct states, so Pauli holds for 118 of 118, and no address is contested.

The check is proven by breaking its subject. A filling that placed two electrons at the same state gives `exact.placed`, a dict, one entry where the count expects two, so the distinct-state count drops below Z and the run reports the violation. A correct fill of two electrons keeps two distinct states; a doubled state keeps one. The count separates them and the labels do not.

## The periodic law is a recurrence in the census

The differentiating electron of an element is the last one Madelung order adds. Its group signature is its azimuthal type and how many electrons stand in that subshell, with the principal number dropped. Sodium and lithium both close on a lone s electron and both read `(s,1)`; carbon and silicon both read `(p,2)`. Dropping the principal number is what leaves them equal, and that recurrence down the table is the periodic law.

The census of signatures over 118 elements carries the block structure with nothing told to it:

| block | signatures | count each | elements |
|---|---|---|---|
| f | `(f,1)` to `(f,14)` | 2 | 28 |
| d | `(d,1)` to `(d,10)` | 4 | 40 |
| p | `(p,1)` to `(p,6)` | 6 | 36 |
| s | `(s,1)`, `(s,2)` | 7 | 14 |

A signature's magnitude is the total minus its count, larger meaning rarer, and it is what the sift stage probes on. The f-block signatures are rarest at magnitude 116, and a sift over the elements probes a lanthanide or an actinide first. The four blocks and their sizes are a fact about shell filling, and the census reads them off the representation before any measure runs.

## The filling is the ideal, and the exceptions are the oracle

`element.electrons` fills Madelung order under Hund's rule. That is the ideal filling, the necessary condition the periodic law would follow if nothing competed with it. Chromium reads `(d,4)` here, an ideal `3d4 4s2`. Its measured configuration is `3d5 4s1`, and copper, niobium, molybdenum, palladium and the rest of the aufbau exceptions deviate the same way. Those published configurations are the oracle stage, `6_oracle`, and the represent stage does not carry them. It carries the model and says so, and the oracle reads the departures off the measurement. The next section is what it found.

## The partition is the quantum numbers

`what_a_quantum_number_costs.py` reads the accumulated electrons at each of five partitions: keep all four numbers of a state, then drop the spin, the magnetic number, the subshell and the shell in turn. The sweep over the whole table:

| partition | tells apart | distinct states | capacity | keeps all distinct |
|---|---|---|---|---|
| spin-orbital | every electron | 7021 | 1 | 118 of 118 |
| orbital | spins folded | 3640 | 2 | 1 of 118 |
| subshell | one subshell | 1376 | 14 | 1 of 118 |
| shell | one shell | 620 | 32 | 1 of 118 |
| atom | the whole atom | 118 | 118 | 1 of 118 |

Distinct is the states summed over the table; the accumulation is 7021 electrons, the sum of the atomic numbers. Capacity is the fullest one cell ever gets at that partition, and it lands on the Pauli number for that level with nothing put in: one per spin-orbital, two per orbital, fourteen at the f subshell, thirty two at the full n=4 shell. Only the full partition keeps every element's electrons apart. Every coarser one agglomerates an accumulation of fermions into fewer states, and hydrogen alone survives every partition, because it has one electron to fold.

## What Pauli builds, read against two backgrounds

`what_exclusion_builds.py` measures the recurrence against two references, each deleting a property from the data. The match rate at a lag is how often a group signature equals the one that many elements ahead.

| arm | floor | lag 8 | lag 18 | lag 32 | tallest |
|---|---|---|---|---|---|
| real accumulation | 0.030 | 0.091 | 0.280 | 0.558 | 0.558 at 32 |
| counts kept, order deleted | 0.030 | 0.027 | 0.060 | 0.035 | 0.094 at 22 |
| no exclusion | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 at 1 |

The first background is `reference.shuffles.permuted`, a uniform arrangement of the same signatures. Its floor is identical to the real one, 0.030, because it keeps every count exactly, and its match rate at the row lengths falls to that floor. The recurrence is in the order Pauli fills the shells in, not in the counts. The second background deletes the exclusion: every electron drops to 1s, and an element is then only a count of electrons in one state; every signature is distinct, and the floor and the match rate are both zero. Without exclusion there is a ladder and no table. The real accumulation is the positive control and the only arm carrying the recurrence.

## The row lengths, off the difference set

`shell_closures_from_the_difference_set.py` reads the match rate at every lag. It stands above the floor at 32, 18 and 8, and at their sums 50 and 26, and no single lag carries the recurrence, because the rows are 2, 8, 8, 18, 18, 32, 32 and not one length. A reader reporting one period would be wrong for most of the table, the same harmonic trap `measure/periodicity.py` records from the other side.

The one number per row is the gap between shell closures. A closure is a filled p subshell, signature `(p,6)`, with helium closing the first row. Read off the signatures, the closures sit at Z 2, 10, 18, 36, 54, 86, 118, the noble gases, and the gaps between them are 8, 8, 18, 18, 32, 32, the row lengths, with no row told to the reader. That is the crystallography difference-set reading in one dimension: a period is a difference between two things that agree, so the differences are the complete candidate set.

## The rarest anchor narrows the period

`rarest_anchor_narrows_the_period.py` is the necessary condition, a sift. A period is a difference between two positions carrying the same signature, and a candidate period must therefore lie in the difference set of every signature that appears; the candidates are the lags common to all of them. The anchors are applied rarest first, by census magnitude, and the rarest are the f-block signatures, each at two places, a lanthanide and an actinide thirty two apart. A signature at two places has a difference set of one lag, and the rarest anchor cuts 117 candidate lags to a single one, 32, in a single step, where a common anchor would leave many.

That lag is where every signature recurs, and it is not an exact period: the sufficiency check reads the sequence at lag 32, finds hydrogen against gallium at the first place, and the table has no period, the same result the measure stage read from the other side. The whole sift is equality and magnitude, a lag is a difference or it is not, and no tolerance is chosen anywhere.

A second sift reads the same necessary condition on particle decays. `decays_pass_the_conservation_laws.py` sums the electric charge, baryon number and lepton number of a decay's products, each an exact integer in thirds, and asks whether they equal the parent's. Beta decay, muon decay and both pion decays pass all three; a proton to a positron and a photon balances the charge and breaks the baryon and lepton numbers, so the gate closes on it, and the proton's stability is that closed gate read in integers. No mass and no tolerance enters.

## The exceptions, read off the ground states

`measured_configuration_vs_ideal.py` holds the ideal filling against the published ground states and reports where they disagree. The measured configurations come from the NIST Atomic Spectra Database, fetched by `maint/data/fetch/fetch_nist_ground_states.py`, which carries neutral atoms through element 108. For 109 to 118 no neutral atom has been measured, so those ten take the predicted relativistic configurations, marked predicted and kept apart from the measured ones. Every configuration is checked to account for exactly Z electrons before it is compared.

All 118 elements are covered: 108 measured, 10 predicted. Of the measured, 88 agree with the ideal filling and 20 differ; the 10 predicted all agree. The 20 disagreements are read off, not listed by hand:

| | Z | ideal | ground state |
|---|---|---|---|
| Cr | 24 | 3d4 4s2 | 3d5 4s1 |
| Cu | 29 | 3d9 4s2 | 3d10 4s1 |
| Nb | 41 | 4d3 5s2 | 4d4 5s1 |
| Mo | 42 | 4d4 5s2 | 4d5 5s1 |
| Ru | 44 | 4d6 5s2 | 4d7 5s1 |
| Rh | 45 | 4d7 5s2 | 4d8 5s1 |
| Pd | 46 | 4d8 5s2 | 4d10 |
| Ag | 47 | 4d9 5s2 | 4d10 5s1 |
| La | 57 | 4f1 | 5d1 |
| Ce | 58 | 4f2 | 4f1 5d1 |
| Gd | 64 | 4f8 | 4f7 5d1 |
| Pt | 78 | 5d8 6s2 | 5d9 6s1 |
| Au | 79 | 5d9 6s2 | 5d10 6s1 |
| Ac | 89 | 5f1 | 6d1 |
| Th | 90 | 5f2 | 6d2 |
| Pa | 91 | 5f3 | 5f2 6d1 |
| U | 92 | 5f4 | 5f3 6d1 |
| Np | 93 | 5f5 | 5f4 6d1 |
| Cm | 96 | 5f8 | 5f7 6d1 |
| Lr | 103 | 6d1 | 7p1 |

Most agree, the positive control: a reading where nothing agreed would be broken, not a table of exceptions. The disagreements are the transition metals that borrow an s electron for a fuller d shell, the lanthanides and actinides that seat an early d electron before the f shell fills, and lawrencium's 7p ground state. The ten predicted configurations follow the ideal order, so every exception is a measured one.

## The particles, and the structure the exact numbers emit

The subject also reads the level below the atom. `particles_as_exact_charges.py` represents the confirmed Standard Model particles, six quarks, six leptons and five force carriers, by exact integer quantum numbers held in `src/engine/python/representation/particle/standard_model.py`. Charge is carried in thirds, an up quark being +2 and an electron -3, and spin is doubled, so the ledger is read by equality and by exact sums. No mass enters and no tolerance is chosen: a mass would force a bound, and this reading takes none. The particles and their masses come from the Particle Data Group at CERN, nothing is derived, and what emerges is how the exact numbers organize themselves.

Three things emerge. The three generations recur: the up, charm and top quarks are one signature, the three charged leptons another, and a generation is one structure seen three times, the way a periodic group was one signature seen down a column. Each generation's electric charge, with every quark counted in its three colors, sums to exactly zero, the anomaly-free condition and the reason an atom is neutral, the proton's quarks and the electron balancing to the digit. The free particles, the leptons and the bosons, carry a charge that divides by three while the six quarks do not, the exact statement of why a quark is never seen alone. The spin census ranks the scalar rarest, and a sift over the particles probes the Higgs first, the one the collider found last.

## The hadrons, from the quarks

`hadrons_from_quarks.py` reads one level up from the quarks. A baryon is three quarks and a meson is a quark and an antiquark, the color-neutral combinations, and the charge of each is the exact sum in thirds. Over the light quarks u, d and s, the ten three-quark combinations carry the charges of the baryon decuplet, among them the proton at +1, the neutron at 0 and the omega at -1, and the nine quark-antiquark combinations carry the pion and kaon charges. All 19 carry an integer charge, a multiple of three thirds, where a single quark carries a fraction. That is confinement stated in charge alone: a color-neutral combination is integer-charged and free, and a lone quark is fractional and is not, by exact arithmetic and no other input. The proton at +1 balances the electron at -1, and a hydrogen atom is neutral, the thread back to the first stage. Nothing here derives why quarks bind or what a hadron weighs; the charge is an integer sum, read as one.

## Running it

```
python examples/particle_physics/1_represent/an_atom_as_exact_shells.py
python examples/particle_physics/1_represent/an_orbit_as_exact_rationals.py
python examples/particle_physics/1_represent/particles_as_exact_charges.py
python examples/particle_physics/1_represent/hadrons_from_quarks.py
python examples/particle_physics/2_partition/what_a_quantum_number_costs.py
```

The atom stages, the trajectory and the particle ledger generate from the exact numbers, with no corpus and no fetch, so their outputs do not drift between runs. The oracle alone reads outside data:

```
python maint/data/fetch/fetch_nist_ground_states.py
python examples/particle_physics/6_oracle/measured_configuration_vs_ideal.py
```

The fetcher pulls the NIST ground-state table once, about half a megabyte, and caches it under `build/nist`. The oracle reads that cache.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
