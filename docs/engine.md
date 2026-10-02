# The engine

**Purpose:** Say what the engine is made of, what each part does today, and where its record is.
**Scope:** `src/c/`, `src/cu/`, `src/sims/`

The engine is the machine every measurement runs on, in C under [`src/c/`](https://github.com/dstroy0/orior/tree/main/src/c), its device code under [`src/cu/`](https://github.com/dstroy0/orior/tree/main/src/cu), and its simulations under [`src/sims/`](https://github.com/dstroy0/orior/tree/main/src/sims). [engine_table.md](https://github.com/dstroy0/orior/blob/main/theory/workbooks/engine/engine_table.md) holds it part by part: what each part computes, the exact algebra it holds to, what it does today, what it wants, every hypothesis tried, its status, and the next move.

**The engine is optimized for no scale.** A size, a spacing, an order, a window, a width, a cell or a voxel count is never written into the machine. Each comes in with the request or is read from the data. The machine is exact at every scale its words can hold, and where a word is too narrow it says so (a request error, or `needed_bits`) and never rounds.

A sample is held as 16-bit lanes over the axes (t, z, y, x), and the atom is all of the thing under inspection, held as one integer. Every value is in ℤ; nothing is rounded.

| step        | from → to               | what happens                                                                                        |
| ----------- | ----------------------- | --------------------------------------------------------------------------------------------------- |
| 1 ingest    | a source → lanes        | read any source format into 16-bit lanes in key order, with its side bytes                          |
| 2 seal      | lanes → signa           | the dimensional Merkle DAG over rows, planes, volumes and lanes, and the witness against the source |
| 3 lift      | lanes ↔ crystal         | the tower lifts the lattice into the stored stream, and lowers it back exactly                      |
| 4 measure   | lattice → fields        | the residual, the moments, the entropy windows                                                      |
| 5 partition | fields → bodies         | the component tree and its cut into bodies                                                          |
| 6 relate    | bodies × frames → links | overlap, matching, motion, division, the links between frames                                       |

## The parts

| part                           | status                                                                                                                  |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| M1. Exact numbers              | built; the engine build takes it from this tree                                                                         |
| M2. The residual operator      | proved (exact); the sweeps 2× faster; any input width proved (the planes)                                               |
| M3. The component tree         | built, error-wired                                                                                                      |
| M4. The moments                | built, error-wired                                                                                                      |
| M5. The correlation operator C | built; the box proved                                                                                                   |
| M6. The exact marginal         | built                                                                                                                   |
| M7. One-to-one matching        | built                                                                                                                   |
| M8. The entropy history        | built, error-wired                                                                                                      |
| M9. The files                  | proved: the field, and the RSNA knee as `.kcr`                                                                          |
| M10. The record machine        | built, error-wired; the table, register reuse and the division proved; 12 to 17 times the interpreter's speed compiled |
| M11. The golden ladder         | built                                                                                                                   |
| M12. Errors and integrity      | wiring in progress                                                                                                      |
| M13. The seal                  | built and proved: the crystal and the set                                                                               |
| M14. The scheduler             | ledger, frame, measure and the daemon end to end proved on Windows                                                      |
| M15. The sift                  | built and run here on four configurations                                                                               |
| M16. Render                    | built and run here                                                                                                      |
| M17. Memory operations         | built; the x86 arms proved, the aarch64 arms built and emitting                                                         |
| M18. The period reading        | built, proved against its reference                                                                                     |
| M19. The sims                  | built; every sim run recorded here passes every check                                                                   |
| M20. The root universal        | built and proved in `tower`; not in the crystal path                                                                    |
| M21. The ask and the state     | built as a sim; proved exact on the host                                                                                |
| M22. Exact qubit states        | built; exact on the host; the device code proved, 44 checks, 0 failed                                                   |
| M23. The refinement loop       | wanted, not built                                                                                                       |
| M24. The ask                   | proved: the ask on the host and in the cell, the gate, the order and its solve; theory: the run channel                 |

Every status names the run behind it in the table. [`src/README.md`](https://github.com/dstroy0/orior/blob/main/src/README.md) is how to use the engine: its calls and errors, one body on one lattice, n bodies across frames, the record machine with its programs and its config, and tessera, the one daemon per device that admits every process's device jobs.

## The files

The k-files are the faces the compiler reads and writes.

| suffix | name                                    | holds                                                |
| ------ | --------------------------------------- | ---------------------------------------------------- |
| `.ksc` | Kolmogorov system classification        | the language map                                     |
| `.krs` | Kolmogorov information ruleset          | the coherence rules: one language's forms            |
| `.kcr` | Kolmogorov information crystal          | a set written close to the floor its own noise sets  |
| `.knf` | Kolmogorov noise floor                  | a measured noise floor                               |
| `.kcs` | Kolmogorov information construction set | what reconstructs information                        |
| `.kdm` | Kolmogorov device map                   | the hardware map                                     |
| `.g`   | gnascor high order language             | semantic plain language, plus the shortcut operators |
| `.gsm` | gnascor assembly language               | the same program with the switch thrown              |

**The stem is the join and the suffix is the face.** Files sharing a stem are one member's set, whatever the stem happens to be. `pair.kdm` and `pair.knf` are a pair's map and that map's floor. `set.kcr`, `set.kcs` and `set.knf` are one set's crystal, the set that reconstructs it, and its floor. Nothing outside the filename binds them, and no member is required to carry every face.

**`.kcr`**, the crystal, read front to back: head (12 words), the seal (6 roots, every lane node, every chunk leaf), offsets and stream, the deflated side bytes, the member tables and names, EOF. Every file the machine writes is proved by reading it back: pixels voxel for voxel against a second read of the source, and every part by its seal. Integer lifting is exactly invertible.

The ingest readers are zarr v2/v3/N5 with every codec, TIFF, HDF5, npy/npz, NRRD, NIfTI, DICOM, zip and `.stack`. The export writes the crystal back out as any source format: the DICOM zip byte for byte from the side bytes, npy, NIfTI, TIFF and zarr.

## Compression

The true floor is the Kolmogorov complexity K(x) of a set: the length of the shortest program that prints it. K is not computable, and it cannot be measured directly. What can be measured is a ladder of bounds, each one exact for a named class of coder, and each lower than the one before as the coder is allowed to see more. [compression_table.md](https://github.com/dstroy0/orior/blob/main/theory/workbooks/compression/compression_table.md) holds the ladder set by set.

| rung | the bound                        | exact for                                                                   |
| ---- | -------------------------------- | --------------------------------------------------------------------------- |
| F0   | raw: the source's own bytes      | nothing; this is the reference every percentage is taken of                 |
| F1   | values, order 0                  | any coder that treats the voxels as a bag of values and sees no position    |
| F2   | coefficients, order 0, per floor | a coder that sees the tower's lifted coefficients floor by floor            |
| F3   | coefficients in context          | context coders: a coefficient coded given its neighbors                     |
| F3′  | a two-part code                  | a coder that stores a model and then the residue the model does not predict |
| F4   | the noise floor                  | every coder: what is left of one frame after all structure is taken         |
| F5   | the integrated noise functionals | a coder driven by the functionals' exact counts                             |

Each bound is an integer count of bits, and each is the bit length of an exact integer. Stating it needs no logarithm or float.

| set                                    | `.kcr` bytes               | of raw | status   |
| -------------------------------------- | -------------------------- | ------ | -------- |
| RSNA knee, 1 × 34 × 960 × 960 unsigned | 25,218,496                 | 40.2%  | proved   |
| RSNA knee, 1 × 24 × 640 × 640 signed   | 11,319,416                 | 57.5%  | proved   |
| RSNA test_series, 15 of 15             | 192,020,272 of 599,191,552 | 32.0%  | proved   |
| the noise floor (F4) on the 25         | 6.229 bits a voxel         | 38.9%  | measured |

Every crystal is rebuilt voxel for voxel, pixel for pixel and node for node.

## The transforms

The engine carries a large set of transforms, maps that put the object into another representation and, where they invert, back. They are integer and exact, and a transform with an inverse returns the input to the bit on the round trip.

**The number-theoretic transform.** One transform modulo the prime 998244353, the exact stand-in for the Fourier transform with no float formed and no root of unity approximated. `exact_translation_by_ntt.py` recovers a translation by NTT convolution and agrees to the digit with the direct correlation. `ntt_double_transform_inverts.py` shows the transform applied twice is a reflection. The transform is its own inverse up to reversal and scale, and `ntt_twiddle_certificate.py` certifies the prime, the primitive root and the order it rests on.

**Layout and space-filling bijections.** Every render layout is a bijection on the cell index, computed in integers and checked for zero collisions by `bench_raster`: four for a sheet (rows, serpentine, columns, diagonal) and four for a volume (slabs, boustrophedon, Morton, helix). The partition carries the same idea for reading, a Morton interleave and a Hilbert curve that fold any number of dimensions through one without being told the shape.

**Representation embeddings.** A row-major file goes back into the plane it came from given its width. A re-seating renumbers the alphabet so its values spread as little as any numbering allows. Exact decimal ingestion keeps every digit the source wrote as an integer pair and forms no float. A Gray-coded embedding places any corpus as points in a binary volume, one bit changing between neighbors.

**Exact codes.** A redundant residue number system carries an integer as residues over coprime moduli and reconstructs it by the Chinese remainder theorem, the extra moduli making it detect error. Hamming(7,4) carries four data bits as seven and corrects one flip.

**Reference backgrounds.** A maximum-entropy background is built by a transform that deletes a property. A permutation or block shuffle draws the null the whole engine measures against, a phase fold groups positions congruent modulo a period and reassembles them, and a windowed median and a self-similar context map each build a background by nearness or by shared context.

**The image transform program.** [`theory/theory/image_transforms`](https://github.com/dstroy0/orior/tree/main/theory/theory/image_transforms) is a research paper of exact image transforms: translation, rotation with scale and perspective, observed motion, and waves on a surface. Translation is built, and it is the number-theoretic transform above. The rest are stated in the research paper and not yet implemented in the tree, and the research paper says which is which.

The full set lives one per file under `src/python/` and in the C renderer, and the workbook records what each has been shown to do. A defensible count is eleven invertible transform families, or seventeen if every render layout is counted on its own, beside several one-way maps.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
