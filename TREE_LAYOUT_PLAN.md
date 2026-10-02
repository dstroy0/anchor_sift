# Tree layout plan

**Purpose:** The map every tree is checked against. Every file of `src/`, of its sims, of the test tree, of
`evidence/` and of `examples/` has a row in `TREE_LAYOUT_PLAN.tsv`: where it is, where it goes, and why. Every
function the three host entry points share has a row in each of them, and a row with nothing at it yet says
what is to be written there.
**Scope:** 2725 rows: 1660 files `git ls-files` lists under `src/`, `utils/test/`, `evidence/` and `examples/`, the
2 definitions that come in from `utils/`, and 1063 files to write. `src/import/` is outside this plan.

Nothing is moved by this file. `python utils/maint/engine/tree_layout_check.py` reads the map against the tree
and names every file the map does not hold, every row whose file is not there, and every file still to write.

## Rules the tree follows

- `src/` holds one container per host entry point: `c/`, `cu/` and `python/`. Every other language waits.
- Every function is in all three containers, under one name. A function in one container and not in another is
  a row to write in the other, at the same path, with the same name and the container's suffix: `.c`, `.cu`
  or `.py`. A file whose name carries `avx2`, `avx512`, `neon`, `sve` is a form of its function for that CPU, and its function is in the
  three trees through the file without it.
- A name does not say its container, since the container says it. A source file's name drops `cuda`, `device`, `host`, `kernel`, `kernels`, `portable`, except
  where the word is part of its module's own name, as in `device_pool`. Where dropping it would give two files
  in one directory the same name, both keep theirs.
- A `.c` file is `c`, a `.cu`, `.cuh` or `.cpp` file is `cu`, a `.py` file is `python`. A `.h` file is `c`
  where C reads it alone or a `.c` file includes it, and `cu` where only C++ or CUDA does. A header in `c/` serves `cu/` as well.
- A file of no language sits beside the code that runs it or reads it: with its runner where one shares its
  name, and otherwise in the container holding the most code at its path, nearest first. The files at a
  root serve every container under it.
- `src/sims/` holds the sims, one container per language, each mirroring its language's container: a sim
  sits at the path of what it exercises, and every sim is in all three. The R and the MATLAB/Octave sims are
  `evidence/`'s, in `evidence/sims/r/` and `evidence/sims/matlab/`.
- Inside a container the categories are the skeleton's. `types/` holds what a value or a file is.
  `includes/` holds what the rest builds on and does not own: arithmetic, codecs, external file formats, and
  the answers that come from outside the sample. `apxrep/` becomes `kcmplx/`. `engine/` holds analysis,
  render, runtime, prg_sch and nbody, with `cycle/`, `keymath/`, `key_schedule/` and `compression/` in
  `engine/analysis/`. `transpiler/` holds the rest of what `compiler/` holds now, and the qasm reader.
- `types/file_defs/` defines the file types, one directory per suffix `gnascor.md` names, and holds the code
  that defines its type and never the files of that type.
- The tracker's modules, its configurations and its program are `examples/cell_tracking/`'s, where its build
  reads them. Its own copies are the ones kept, and no copy of one sits in `src/`.
- A Python program puts `src/python/` on `sys.path` and imports `manifest`. `src/python/manifest.tsv` names
  the path of every import name the container answers, `representation.exact` and
  `representation.constants` among them, and `src/python/manifest.py` reads it and nothing else.
- The test tree mirrors `src/` under `utils/test/src/`. Every module has a test, and every test is in all
  three containers. A module with none has one to write, named for the module with `_test`.
  `examples/`'s tests sit in `utils/test/examples/` in the same containers. `examples/` and `evidence/`
  otherwise keep their domains.

## `src/`

```text
src/                                                             now   write
├── c/                                                           261    +177
│   ├── types/                                                    27      +5
│   │   ├── file_defs/                                             5      +3
│   │   │   ├── kdm/                                               1        
│   │   │   ├── krep/                                              1      +2
│   │   │   ├── krs/                                               2      +1
│   │   │   └── ksc/                                               1        
│   │   ├── integers/                                             18      +2
│   │   │   └── constants/                                         0      +1
│   │   └── integerfloats/                                         4        
│   │       ├── decimal_double/                                    2        
│   │       └── double_fields/                                     2        
│   ├── includes/                                                 64     +30
│   │   ├── codecs/                                               26        
│   │   │   ├── blosc/                                             2        
│   │   │   ├── crc/                                               3        
│   │   │   ├── deflate/                                           4        
│   │   │   ├── inflate/                                           4        
│   │   │   ├── lz4/                                               2        
│   │   │   ├── snappy/                                            2        
│   │   │   ├── zip/                                               4        
│   │   │   └── zstd/                                              5        
│   │   ├── formats/                                              38     +27
│   │   │   ├── cfg_json/                                          2        
│   │   │   ├── dicom/                                             6        
│   │   │   ├── hdf5/                                              9        
│   │   │   ├── nifti/                                             2        
│   │   │   ├── npy/                                               4        
│   │   │   ├── nrrd/                                              4        
│   │   │   ├── representation/                                    0     +26
│   │   │   │   ├── atom/                                          0      +1
│   │   │   │   ├── game/                                          0      +7
│   │   │   │   ├── particle/                                      0      +1
│   │   │   │   ├── picture/                                       0      +1
│   │   │   │   ├── sound/                                         0      +2
│   │   │   │   ├── structure/                                     0      +3
│   │   │   │   └── text/                                          0      +8
│   │   │   ├── stack/                                             1      +1
│   │   │   ├── tiff/                                              6        
│   │   │   └── zarr/                                              4        
│   │   └── oracle/                                                0      +3
│   │       └── language/                                          0      +3
│   ├── kcmplx/                                                    1      +2
│   ├── engine/                                                  104    +118
│   │   ├── analysis/                                             15     +68
│   │   │   ├── compression/                                       1      +1
│   │   │   ├── cycle/                                             2      +9
│   │   │   ├── entropy_history/                                   1      +1
│   │   │   ├── golden_bands/                                      1      +1
│   │   │   ├── key_schedule/                                      1      +1
│   │   │   ├── keymath/                                           1      +1
│   │   │   ├── measure/                                           0     +20
│   │   │   ├── noise_detector/                                    1     +12
│   │   │   ├── partition/                                         0      +3
│   │   │   ├── period/                                            1      +2
│   │   │   ├── reference/                                         0     +10
│   │   │   ├── residual/                                          1      +1
│   │   │   ├── residual_survey/                                   1      +1
│   │   │   ├── shift_agreement/                                   2      +1
│   │   │   ├── tower/                                             1      +3
│   │   │   └── unit_sweep/                                        1      +1
│   │   ├── nbody/                                                37     +32
│   │   │   ├── orior/                                      16      +7
│   │   │   │   ├── instrument/                                    0      +3
│   │   │   │   └── sift/                                          0      +4
│   │   │   ├── body_overlap/                                      2        
│   │   │   ├── box_history/                                       1      +1
│   │   │   ├── climb_machine/                                     2      +7
│   │   │   ├── contact_side/                                      1      +1
│   │   │   ├── division/                                          1      +1
│   │   │   ├── fingerprint/                                       1      +1
│   │   │   ├── flatten/                                           1      +1
│   │   │   ├── grow/                                              1      +1
│   │   │   ├── heaviest_matching/                                 2        
│   │   │   ├── marginal/                                          2        
│   │   │   ├── max_tree/                                          5     +10
│   │   │   ├── print_pair/                                        1      +1
│   │   │   └── velocity/                                          1      +1
│   │   ├── prg_sch/                                               1        
│   │   ├── render/                                                4      +4
│   │   └── runtime/                                              42      +5
│   │       ├── daemon/                                           30      +1
│   │       │   └── service/                                       2        
│   │       ├── device_pool/                                       1      +1
│   │       ├── obsignatio/                                        1      +2
│   │       ├── radix_keys/                                        1        
│   │       ├── schedule/                                          1      +1
│   │       └── scriptura/                                         8        
│   └── transpiler/                                               64     +22
│       ├── bootstrap/                                            16        
│       ├── cell/                                                  3        
│       ├── codegen/                                               4     +16
│       ├── cubin/                                                 7        
│       │   └── machines/                                          3        
│       ├── emit/                                                  5        
│       │   └── layouts/                                           1        
│       └── qasm/                                                 28      +6
├── cu/                                                          170    +179
│   ├── types/                                                    10     +14
│   │   ├── file_defs/                                             9      +3
│   │   │   ├── kdm/                                               0      +1
│   │   │   ├── krep/                                              3        
│   │   │   ├── krs/                                               6      +1
│   │   │   └── ksc/                                               0      +1
│   │   ├── integers/                                              1      +9
│   │   │   └── constants/                                         0      +1
│   │   └── integerfloats/                                         0      +2
│   │       ├── decimal_double/                                    0      +1
│   │       └── double_fields/                                     0      +1
│   ├── includes/                                                  2     +64
│   │   ├── codecs/                                                1     +12
│   │   │   ├── blosc/                                             0      +1
│   │   │   ├── crc/                                               1        
│   │   │   ├── deflate/                                           0      +2
│   │   │   ├── inflate/                                           0      +2
│   │   │   ├── lz4/                                               0      +1
│   │   │   ├── snappy/                                            0      +1
│   │   │   ├── zip/                                               0      +2
│   │   │   └── zstd/                                              0      +3
│   │   ├── formats/                                               1     +49
│   │   │   ├── cfg_json/                                          0      +1
│   │   │   ├── dicom/                                             0      +4
│   │   │   ├── hdf5/                                              0      +7
│   │   │   ├── nifti/                                             0      +1
│   │   │   ├── npy/                                               0      +2
│   │   │   ├── nrrd/                                              0      +2
│   │   │   ├── representation/                                    0     +26
│   │   │   │   ├── atom/                                          0      +1
│   │   │   │   ├── game/                                          0      +7
│   │   │   │   ├── particle/                                      0      +1
│   │   │   │   ├── picture/                                       0      +1
│   │   │   │   ├── sound/                                         0      +2
│   │   │   │   ├── structure/                                     0      +3
│   │   │   │   └── text/                                          0      +8
│   │   │   ├── stack/                                             1        
│   │   │   ├── tiff/                                              0      +4
│   │   │   └── zarr/                                              0      +2
│   │   └── oracle/                                                0      +3
│   │       └── language/                                          0      +3
│   ├── kcmplx/                                                    3        
│   ├── engine/                                                   99     +72
│   │   ├── analysis/                                             50     +34
│   │   │   ├── compression/                                       1        
│   │   │   ├── cycle/                                            15      +1
│   │   │   ├── entropy_history/                                   1        
│   │   │   ├── golden_bands/                                      1        
│   │   │   ├── key_schedule/                                      2        
│   │   │   ├── keymath/                                           4        
│   │   │   ├── measure/                                           0     +20
│   │   │   ├── noise_detector/                                   13        
│   │   │   ├── partition/                                         0      +3
│   │   │   ├── period/                                            3        
│   │   │   ├── reference/                                         0     +10
│   │   │   ├── residual/                                          1        
│   │   │   ├── residual_survey/                                   1        
│   │   │   ├── shift_agreement/                                   3        
│   │   │   ├── tower/                                             4        
│   │   │   └── unit_sweep/                                        1        
│   │   ├── nbody/                                                30     +16
│   │   │   ├── orior/                                       1     +12
│   │   │   │   ├── instrument/                                    0      +3
│   │   │   │   └── sift/                                          0      +4
│   │   │   ├── body_overlap/                                      1        
│   │   │   ├── box_history/                                       1        
│   │   │   ├── climb_machine/                                     8        
│   │   │   ├── contact_side/                                      1        
│   │   │   ├── division/                                          1        
│   │   │   ├── fingerprint/                                       1        
│   │   │   ├── flatten/                                           1        
│   │   │   ├── grow/                                              1        
│   │   │   ├── heaviest_matching/                                 0      +1
│   │   │   ├── marginal/                                          1        
│   │   │   ├── max_tree/                                         11      +3
│   │   │   ├── print_pair/                                        1        
│   │   │   └── velocity/                                          1        
│   │   ├── render/                                                3      +4
│   │   └── runtime/                                               6     +18
│   │       ├── daemon/                                            1     +16
│   │       ├── device_pool/                                       1        
│   │       ├── obsignatio/                                        3        
│   │       ├── schedule/                                          1        
│   │       └── scriptura/                                         0      +2
│   └── transpiler/                                               55     +29
│       ├── bootstrap/                                             0      +7
│       ├── cell/                                                  0      +2
│       ├── codegen/                                              47        
│       │   └── rulesets/                                          5        
│       ├── cubin/                                                 0      +2
│       ├── emit/                                                  0      +2
│       └── qasm/                                                  8     +16
└── python/                                                       97    +215
    ├── types/                                                     4     +16
    │   ├── file_defs/                                             0      +6
    │   │   ├── kdm/                                               0      +1
    │   │   ├── krep/                                              0      +2
    │   │   ├── krs/                                               0      +2
    │   │   └── ksc/                                               0      +1
    │   ├── integers/                                              4      +8
    │   │   └── constants/                                         3        
    │   └── integerfloats/                                         0      +2
    │       ├── decimal_double/                                    0      +1
    │       └── double_fields/                                     0      +1
    ├── includes/                                                 41     +36
    │   ├── codecs/                                                0     +12
    │   │   ├── blosc/                                             0      +1
    │   │   ├── deflate/                                           0      +2
    │   │   ├── inflate/                                           0      +2
    │   │   ├── lz4/                                               0      +1
    │   │   ├── snappy/                                            0      +1
    │   │   ├── zip/                                               0      +2
    │   │   └── zstd/                                              0      +3
    │   ├── formats/                                              35     +24
    │   │   ├── cfg_json/                                          0      +1
    │   │   ├── dicom/                                             0      +4
    │   │   ├── hdf5/                                              0      +7
    │   │   ├── nifti/                                             0      +1
    │   │   ├── npy/                                               0      +2
    │   │   ├── nrrd/                                              0      +2
    │   │   ├── representation/                                   35        
    │   │   │   ├── atom/                                          2        
    │   │   │   ├── game/                                          8        
    │   │   │   ├── particle/                                      2        
    │   │   │   ├── picture/                                       2        
    │   │   │   ├── sound/                                         3        
    │   │   │   ├── structure/                                     4        
    │   │   │   └── text/                                          9        
    │   │   ├── stack/                                             0      +1
    │   │   ├── tiff/                                              0      +4
    │   │   └── zarr/                                              0      +2
    │   └── oracle/                                                6        
    │       └── language/                                          4        
    ├── kcmplx/                                                    0      +2
    ├── engine/                                                   51    +110
    │   ├── analysis/                                             39     +37
    │   │   ├── compression/                                       0      +1
    │   │   ├── cycle/                                             0     +10
    │   │   ├── entropy_history/                                   0      +1
    │   │   ├── golden_bands/                                      0      +1
    │   │   ├── key_schedule/                                      0      +1
    │   │   ├── keymath/                                           0      +1
    │   │   ├── measure/                                          22        
    │   │   ├── noise_detector/                                    0     +12
    │   │   ├── partition/                                         5        
    │   │   ├── period/                                            0      +2
    │   │   ├── reference/                                        12        
    │   │   ├── residual/                                          0      +1
    │   │   ├── residual_survey/                                   0      +1
    │   │   ├── shift_agreement/                                   0      +2
    │   │   ├── tower/                                             0      +3
    │   │   └── unit_sweep/                                        0      +1
    │   ├── nbody/                                                 9     +37
    │   │   ├── orior/                                       9      +6
    │   │   │   ├── instrument/                                    3        
    │   │   │   └── sift/                                          6        
    │   │   ├── body_overlap/                                      0      +1
    │   │   ├── box_history/                                       0      +1
    │   │   ├── climb_machine/                                     0      +7
    │   │   ├── contact_side/                                      0      +1
    │   │   ├── division/                                          0      +1
    │   │   ├── fingerprint/                                       0      +1
    │   │   ├── flatten/                                           0      +1
    │   │   ├── grow/                                              0      +1
    │   │   ├── heaviest_matching/                                 0      +1
    │   │   ├── marginal/                                          0      +1
    │   │   ├── max_tree/                                          0     +13
    │   │   ├── print_pair/                                        0      +1
    │   │   └── velocity/                                          0      +1
    │   ├── render/                                                3      +4
    │   └── runtime/                                               0     +23
    │       ├── daemon/                                            0     +17
    │       ├── device_pool/                                       0      +1
    │       ├── obsignatio/                                        0      +2
    │       ├── schedule/                                          0      +1
    │       └── scriptura/                                         0      +2
    └── transpiler/                                                0     +51
        ├── bootstrap/                                             0      +7
        ├── cell/                                                  0      +2
        ├── codegen/                                               0     +16
        ├── cubin/                                                 0      +2
        ├── emit/                                                  0      +2
        └── qasm/                                                  0     +22
```

## `src/sims/`

```text
src/sims/                                                        now   write
├── c/                                                             0     +57
│   ├── types/                                                     0     +33
│   │   └── integers/                                              0     +33
│   │       ├── chaitin_omega/                                     0      +7
│   │       ├── goodstein/                                         0      +2
│   │       ├── ka_psi/                                            0      +4
│   │       ├── omega_computer/                                    0      +3
│   │       ├── pi_plane/                                          0      +8
│   │       └── pi_tower/                                          0      +9
│   ├── engine/                                                    0     +21
│   │   ├── analysis/                                              0     +20
│   │   │   ├── art/                                               0      +2
│   │   │   ├── floor_match/                                       0      +2
│   │   │   ├── floor_track/                                       0      +3
│   │   │   ├── knf_identity/                                      0      +3
│   │   │   ├── noise_floor/                                       0      +2
│   │   │   ├── noise_root/                                        0      +1
│   │   │   ├── noise_terms/                                       0      +4
│   │   │   ├── period_power/                                      0      +1
│   │   │   └── root_universal/                                    0      +2
│   │   └── nbody/                                                 0      +1
│   │       └── nbody_lattice/                                     0      +1
│   └── transpiler/                                                0      +2
│       └── ask_state/                                             0      +2
├── cu/                                                           79        
│   ├── types/                                                    42        
│   │   └── integers/                                             42        
│   │       ├── chaitin_omega/                                    11        
│   │       ├── goodstein/                                         3        
│   │       ├── ka_psi/                                            5        
│   │       ├── omega_computer/                                    4        
│   │       ├── pi_plane/                                          9        
│   │       └── pi_tower/                                         10        
│   ├── engine/                                                   28        
│   │   ├── analysis/                                             27        
│   │   │   ├── art/                                               3        
│   │   │   ├── floor_match/                                       3        
│   │   │   ├── floor_track/                                       4        
│   │   │   ├── knf_identity/                                      4        
│   │   │   ├── noise_floor/                                       3        
│   │   │   ├── noise_root/                                        1        
│   │   │   ├── noise_terms/                                       5        
│   │   │   ├── period_power/                                      1        
│   │   │   └── root_universal/                                    3        
│   │   └── nbody/                                                 1        
│   │       └── nbody_lattice/                                     1        
│   └── transpiler/                                                3        
│       └── ask_state/                                             3        
└── python/                                                        0     +57
    ├── types/                                                     0     +33
    │   └── integers/                                              0     +33
    │       ├── chaitin_omega/                                     0      +7
    │       ├── goodstein/                                         0      +2
    │       ├── ka_psi/                                            0      +4
    │       ├── omega_computer/                                    0      +3
    │       ├── pi_plane/                                          0      +8
    │       └── pi_tower/                                          0      +9
    ├── engine/                                                    0     +21
    │   ├── analysis/                                              0     +20
    │   │   ├── art/                                               0      +2
    │   │   ├── floor_match/                                       0      +2
    │   │   ├── floor_track/                                       0      +3
    │   │   ├── knf_identity/                                      0      +3
    │   │   ├── noise_floor/                                       0      +2
    │   │   ├── noise_root/                                        0      +1
    │   │   ├── noise_terms/                                       0      +4
    │   │   ├── period_power/                                      0      +1
    │   │   └── root_universal/                                    0      +2
    │   └── nbody/                                                 0      +1
    │       └── nbody_lattice/                                     0      +1
    └── transpiler/                                                0      +2
        └── ask_state/                                             0      +2
```

## The test tree, `utils/test/src/`

```text
utils/test/src/                                                  now   write
├── c/                                                            55    +123
│   ├── types/                                                     1     +10
│   │   ├── file_defs/                                             0      +4
│   │   │   ├── kdm/                                               0      +1
│   │   │   ├── krep/                                              0      +1
│   │   │   ├── krs/                                               0      +1
│   │   │   └── ksc/                                               0      +1
│   │   ├── integers/                                              1      +4
│   │   │   └── constants/                                         0      +1
│   │   └── integerfloats/                                         0      +2
│   │       ├── decimal_double/                                    0      +1
│   │       └── double_fields/                                     0      +1
│   ├── includes/                                                  0     +25
│   │   ├── codecs/                                                0      +7
│   │   │   ├── blosc/                                             0      +1
│   │   │   ├── deflate/                                           0      +1
│   │   │   ├── inflate/                                           0      +1
│   │   │   ├── lz4/                                               0      +1
│   │   │   ├── snappy/                                            0      +1
│   │   │   ├── zip/                                               0      +1
│   │   │   └── zstd/                                              0      +1
│   │   ├── formats/                                               0     +17
│   │   │   ├── cfg_json/                                          0      +1
│   │   │   ├── dicom/                                             0      +1
│   │   │   ├── hdf5/                                              0      +1
│   │   │   ├── nifti/                                             0      +1
│   │   │   ├── npy/                                               0      +1
│   │   │   ├── nrrd/                                              0      +1
│   │   │   ├── representation/                                    0      +8
│   │   │   │   ├── atom/                                          0      +1
│   │   │   │   ├── game/                                          0      +1
│   │   │   │   ├── particle/                                      0      +1
│   │   │   │   ├── picture/                                       0      +1
│   │   │   │   ├── sound/                                         0      +1
│   │   │   │   ├── structure/                                     0      +1
│   │   │   │   └── text/                                          0      +1
│   │   │   ├── stack/                                             0      +1
│   │   │   ├── tiff/                                              0      +1
│   │   │   └── zarr/                                              0      +1
│   │   └── oracle/                                                0      +1
│   │       └── language/                                          0      +1
│   ├── kcmplx/                                                    0      +1
│   ├── engine/                                                   28     +75
│   │   ├── analysis/                                              3     +49
│   │   │   ├── compression/                                       0      +1
│   │   │   ├── cycle/                                             3     +28
│   │   │   ├── entropy_history/                                   0      +1
│   │   │   ├── golden_bands/                                      0      +1
│   │   │   ├── key_schedule/                                      0      +1
│   │   │   ├── keymath/                                           0      +1
│   │   │   ├── measure/                                           0      +1
│   │   │   ├── noise_detector/                                    0      +1
│   │   │   ├── partition/                                         0      +1
│   │   │   ├── period/                                            0      +4
│   │   │   ├── reference/                                         0      +1
│   │   │   ├── residual/                                          0      +1
│   │   │   ├── residual_survey/                                   0      +1
│   │   │   ├── shift_agreement/                                   0      +2
│   │   │   ├── tower/                                             0      +1
│   │   │   └── unit_sweep/                                        0      +1
│   │   ├── nbody/                                                15     +15
│   │   │   ├── orior/                                      11      +3
│   │   │   │   ├── instrument/                                    0      +1
│   │   │   │   └── sift/                                          0      +1
│   │   │   ├── body_overlap/                                      0      +1
│   │   │   ├── box_history/                                       0      +1
│   │   │   ├── climb_machine/                                     0      +1
│   │   │   ├── contact_side/                                      0      +1
│   │   │   ├── division/                                          0      +1
│   │   │   ├── fingerprint/                                       0      +1
│   │   │   ├── flatten/                                           0      +1
│   │   │   ├── grow/                                              0      +1
│   │   │   ├── heaviest_matching/                                 0      +1
│   │   │   ├── marginal/                                          0      +1
│   │   │   ├── max_tree/                                          4        
│   │   │   ├── print_pair/                                        0      +1
│   │   │   └── velocity/                                          0      +1
│   │   ├── render/                                                0      +1
│   │   └── runtime/                                              10      +9
│   │       ├── daemon/                                            8      +3
│   │       ├── device_pool/                                       0      +1
│   │       ├── obsignatio/                                        1      +4
│   │       ├── schedule/                                          0      +1
│   │       └── scriptura/                                         1        
│   └── transpiler/                                               26     +12
│       ├── bootstrap/                                             9        
│       ├── cell/                                                 13      +2
│       ├── codegen/                                               2      +3
│       ├── cubin/                                                 0      +1
│       ├── emit/                                                  0      +1
│       └── qasm/                                                  2      +5
├── cu/                                                          110    +102
│   ├── types/                                                     4      +9
│   │   ├── file_defs/                                             0      +4
│   │   │   ├── kdm/                                               0      +1
│   │   │   ├── krep/                                              0      +1
│   │   │   ├── krs/                                               0      +1
│   │   │   └── ksc/                                               0      +1
│   │   ├── integers/                                              4      +3
│   │   │   └── constants/                                         0      +1
│   │   └── integerfloats/                                         0      +2
│   │       ├── decimal_double/                                    0      +1
│   │       └── double_fields/                                     0      +1
│   ├── includes/                                                  0     +25
│   │   ├── codecs/                                                0      +7
│   │   │   ├── blosc/                                             0      +1
│   │   │   ├── deflate/                                           0      +1
│   │   │   ├── inflate/                                           0      +1
│   │   │   ├── lz4/                                               0      +1
│   │   │   ├── snappy/                                            0      +1
│   │   │   ├── zip/                                               0      +1
│   │   │   └── zstd/                                              0      +1
│   │   ├── formats/                                               0     +17
│   │   │   ├── cfg_json/                                          0      +1
│   │   │   ├── dicom/                                             0      +1
│   │   │   ├── hdf5/                                              0      +1
│   │   │   ├── nifti/                                             0      +1
│   │   │   ├── npy/                                               0      +1
│   │   │   ├── nrrd/                                              0      +1
│   │   │   ├── representation/                                    0      +8
│   │   │   │   ├── atom/                                          0      +1
│   │   │   │   ├── game/                                          0      +1
│   │   │   │   ├── particle/                                      0      +1
│   │   │   │   ├── picture/                                       0      +1
│   │   │   │   ├── sound/                                         0      +1
│   │   │   │   ├── structure/                                     0      +1
│   │   │   │   └── text/                                          0      +1
│   │   │   ├── stack/                                             0      +1
│   │   │   ├── tiff/                                              0      +1
│   │   │   └── zarr/                                              0      +1
│   │   └── oracle/                                                0      +1
│   │       └── language/                                          0      +1
│   ├── kcmplx/                                                    0      +1
│   ├── engine/                                                   78     +48
│   │   ├── analysis/                                             66     +14
│   │   │   ├── compression/                                       0      +1
│   │   │   ├── cycle/                                            52      +1
│   │   │   ├── entropy_history/                                   0      +1
│   │   │   ├── golden_bands/                                      0      +1
│   │   │   ├── key_schedule/                                      0      +1
│   │   │   ├── keymath/                                           0      +1
│   │   │   ├── measure/                                           0      +1
│   │   │   ├── noise_detector/                                    0      +1
│   │   │   ├── partition/                                         0      +1
│   │   │   ├── period/                                            5      +1
│   │   │   ├── reference/                                         0      +1
│   │   │   ├── residual/                                          2        
│   │   │   ├── residual_survey/                                   0      +1
│   │   │   ├── shift_agreement/                                   2      +1
│   │   │   ├── tower/                                             2        
│   │   │   └── unit_sweep/                                        2        
│   │   ├── nbody/                                                 0     +25
│   │   │   ├── orior/                                       0     +11
│   │   │   │   ├── instrument/                                    0      +1
│   │   │   │   └── sift/                                          0      +1
│   │   │   ├── body_overlap/                                      0      +1
│   │   │   ├── box_history/                                       0      +1
│   │   │   ├── climb_machine/                                     0      +1
│   │   │   ├── contact_side/                                      0      +1
│   │   │   ├── division/                                          0      +1
│   │   │   ├── fingerprint/                                       0      +1
│   │   │   ├── flatten/                                           0      +1
│   │   │   ├── grow/                                              0      +1
│   │   │   ├── heaviest_matching/                                 0      +1
│   │   │   ├── marginal/                                          0      +1
│   │   │   ├── max_tree/                                          0      +2
│   │   │   ├── print_pair/                                        0      +1
│   │   │   └── velocity/                                          0      +1
│   │   ├── render/                                                0      +1
│   │   └── runtime/                                              12      +7
│   │       ├── daemon/                                            4      +5
│   │       ├── device_pool/                                       2        
│   │       ├── obsignatio/                                        6        
│   │       ├── schedule/                                          0      +1
│   │       └── scriptura/                                         0      +1
│   └── transpiler/                                               28     +19
│       ├── bootstrap/                                             0      +8
│       ├── cell/                                                  3      +9
│       ├── codegen/                                               8      +1
│       │   └── rulesets/                                          2        
│       │       └── flagless/                                      2        
│       ├── cubin/                                                 0      +1
│       ├── emit/                                                  1        
│       └── qasm/                                                 16        
│           └── vectors/                                           8        
└── python/                                                        8    +153
    ├── types/                                                     1     +10
    │   ├── file_defs/                                             0      +4
    │   │   ├── kdm/                                               0      +1
    │   │   ├── krep/                                              0      +1
    │   │   ├── krs/                                               0      +1
    │   │   └── ksc/                                               0      +1
    │   ├── integers/                                              1      +4
    │   │   └── constants/                                         0      +1
    │   └── integerfloats/                                         0      +2
    │       ├── decimal_double/                                    0      +1
    │       └── double_fields/                                     0      +1
    ├── includes/                                                  0     +25
    │   ├── codecs/                                                0      +7
    │   │   ├── blosc/                                             0      +1
    │   │   ├── deflate/                                           0      +1
    │   │   ├── inflate/                                           0      +1
    │   │   ├── lz4/                                               0      +1
    │   │   ├── snappy/                                            0      +1
    │   │   ├── zip/                                               0      +1
    │   │   └── zstd/                                              0      +1
    │   ├── formats/                                               0     +17
    │   │   ├── cfg_json/                                          0      +1
    │   │   ├── dicom/                                             0      +1
    │   │   ├── hdf5/                                              0      +1
    │   │   ├── nifti/                                             0      +1
    │   │   ├── npy/                                               0      +1
    │   │   ├── nrrd/                                              0      +1
    │   │   ├── representation/                                    0      +8
    │   │   │   ├── atom/                                          0      +1
    │   │   │   ├── game/                                          0      +1
    │   │   │   ├── particle/                                      0      +1
    │   │   │   ├── picture/                                       0      +1
    │   │   │   ├── sound/                                         0      +1
    │   │   │   ├── structure/                                     0      +1
    │   │   │   └── text/                                          0      +1
    │   │   ├── stack/                                             0      +1
    │   │   ├── tiff/                                              0      +1
    │   │   └── zarr/                                              0      +1
    │   └── oracle/                                                0      +1
    │       └── language/                                          0      +1
    ├── kcmplx/                                                    0      +1
    ├── engine/                                                    7     +87
    │   ├── analysis/                                              5     +47
    │   │   ├── compression/                                       0      +1
    │   │   ├── cycle/                                             0     +29
    │   │   ├── entropy_history/                                   0      +1
    │   │   ├── golden_bands/                                      0      +1
    │   │   ├── key_schedule/                                      0      +1
    │   │   ├── keymath/                                           0      +1
    │   │   ├── measure/                                           0      +1
    │   │   ├── noise_detector/                                    0      +1
    │   │   ├── partition/                                         0      +1
    │   │   ├── period/                                            2      +3
    │   │   ├── reference/                                         0      +1
    │   │   ├── residual/                                          0      +1
    │   │   ├── residual_survey/                                   0      +1
    │   │   ├── shift_agreement/                                   1      +1
    │   │   ├── tower/                                             0      +1
    │   │   └── unit_sweep/                                        0      +1
    │   ├── nbody/                                                 1     +24
    │   │   ├── orior/                                       1     +10
    │   │   │   ├── instrument/                                    0      +1
    │   │   │   └── sift/                                          0      +1
    │   │   ├── body_overlap/                                      0      +1
    │   │   ├── box_history/                                       0      +1
    │   │   ├── climb_machine/                                     0      +1
    │   │   ├── contact_side/                                      0      +1
    │   │   ├── division/                                          0      +1
    │   │   ├── fingerprint/                                       0      +1
    │   │   ├── flatten/                                           0      +1
    │   │   ├── grow/                                              0      +1
    │   │   ├── heaviest_matching/                                 0      +1
    │   │   ├── marginal/                                          0      +1
    │   │   ├── max_tree/                                          0      +2
    │   │   ├── print_pair/                                        0      +1
    │   │   └── velocity/                                          0      +1
    │   ├── render/                                                1        
    │   └── runtime/                                               0     +15
    │       ├── daemon/                                            0      +8
    │       ├── device_pool/                                       0      +1
    │       ├── obsignatio/                                        0      +4
    │       ├── schedule/                                          0      +1
    │       └── scriptura/                                         0      +1
    └── transpiler/                                                0     +30
        ├── bootstrap/                                             0      +8
        ├── cell/                                                  0     +11
        ├── codegen/                                               0      +4
        ├── cubin/                                                 0      +1
        ├── emit/                                                  0      +1
        └── qasm/                                                  0      +5
```

## `utils/test/examples/`

```text
utils/test/examples/                                             now   write
├── c/                                                             2        
│   └── cell_tracking/                                             2        
├── cu/                                                           10        
│   └── cell_tracking/                                            10        
└── python/                                                        1        
    └── cell_tracking/                                             1        
```

## Leaving `src/`

- `src/engine/matlab/sim_cluster_rapid_deploy/README.md` goes to `evidence/sims/matlab/sim_cluster_rapid_deploy/README.md`.
- `src/engine/matlab/sim_cluster_rapid_deploy/chk_run.sh` goes to `evidence/sims/matlab/sim_cluster_rapid_deploy/chk_run.sh`.
- `src/engine/r/README.md` goes to `evidence/sims/r/README.md`.
- `src/engine/r/hypotheses/ladder_analysis.R` goes to `evidence/sims/r/hypotheses/ladder_analysis.R`.
- `src/engine/r/hypotheses/language_variance.R` goes to `evidence/sims/r/hypotheses/language_variance.R`.
- `src/engine/r/hypotheses/ratio_normality.R` goes to `evidence/sims/r/hypotheses/ratio_normality.R`.

## One name

| file | goes to |
|---|---|
| `src/engine/analysis/shift_agreement/shift_agreement_kernels.cu` | `src/cu/engine/analysis/shift_agreement/shift_agreement.cu` |
| `src/engine/analysis/tower/tower_kernels.cu` | `src/cu/engine/analysis/tower/tower.cu` |
| `src/engine/arithmetic/no_rounding/arm_cuda.cu` | `src/cu/types/integers/arm.cu` |
| `src/engine/arithmetic/no_rounding/arm_portable.c` | `src/c/types/integers/arm.c` |
| `src/engine/compiler/codegen/codegen_device_kernels.cu` | `src/cu/transpiler/codegen/codegen.cu` |
| `src/engine/compiler/codegen/codegen_device_lowering.cu` | `src/cu/transpiler/codegen/codegen_lowering.cu` |
| `src/engine/compiler/codegen/codegen_device_output.cu` | `src/cu/transpiler/codegen/codegen_output.cu` |
| `src/engine/compiler/codegen/codegen_device_reader.cu` | `src/cu/transpiler/codegen/codegen_reader.cu` |
| `src/engine/compiler/codegen/codegen_device_rules.cu` | `src/cu/transpiler/codegen/codegen_rules.cu` |
| `src/engine/compiler/cycle/cycle_compile_host.cu` | `src/cu/engine/analysis/cycle/cycle_compile.cu` |
| `src/engine/compiler/cycle/cycle_record_kernel.cu` | `src/cu/engine/analysis/cycle/cycle_record.cu` |
| `src/engine/nbody/orior/scan_cuda.cu` | `src/cu/engine/nbody/orior/scan.cu` |
| `src/engine/nbody/orior/scan_portable.c` | `src/c/engine/nbody/orior/scan.c` |
| `src/engine/nbody/max_tree/max_tree_device_code.cu` | `src/cu/engine/nbody/max_tree/max_tree_code.cu` |
| `src/engine/nbody/max_tree/max_tree_device_contract.cu` | `src/cu/engine/nbody/max_tree/max_tree_contract.cu` |
| `src/engine/nbody/max_tree/max_tree_device_grade.cu` | `src/cu/engine/nbody/max_tree/max_tree_grade.cu` |
| `src/engine/nbody/max_tree/max_tree_device_label.cu` | `src/cu/engine/nbody/max_tree/max_tree_label.cu` |
| `src/engine/nbody/max_tree/max_tree_device_objects.cu` | `src/cu/engine/nbody/max_tree/max_tree_objects.cu` |
| `src/engine/nbody/max_tree/max_tree_device_pack.cu` | `src/cu/engine/nbody/max_tree/max_tree_pack.cu` |
| `src/engine/nbody/max_tree/max_tree_device_select.cu` | `src/cu/engine/nbody/max_tree/max_tree_select.cu` |
| `src/engine/nbody/max_tree/max_tree_device_slide.cu` | `src/cu/engine/nbody/max_tree/max_tree_slide.cu` |
| `src/engine/quantum/qasm/qasm_device_kernels.cu` | `src/cu/transpiler/qasm/qasm.cu` |
| `src/engine/quantum/qasm/qasm_device_program.cu` | `src/cu/transpiler/qasm/qasm_program.cu` |
| `src/engine/quantum/qasm/qasm_device_run.cu` | `src/cu/transpiler/qasm/qasm_run.cu` |
| `src/engine/render/anchor_raster_host.c` | `src/c/engine/render/anchor_raster.c` |
| `src/engine/render/raster_cuda_entry.cu` | `src/cu/engine/render/raster_entry.cu` |
| `src/engine/render/raster_cuda_kernels.cu` | `src/cu/engine/render/raster.cu` |
| `src/engine/runtime/daemon/tessera_device.cu` | `src/cu/engine/runtime/daemon/tessera.cu` |
| `src/engine/runtime/scriptura/scriptura_arm_portable.c` | `src/c/engine/runtime/scriptura/scriptura_arm.c` |
| `src/engine/sims/chaitin_omega/chaitin_omega_device.cu` | `src/sims/cu/types/integers/chaitin_omega/chaitin_omega.cu` |
| `utils/test/engine/compiler/codegen/codegen_device_test.cu` | `utils/test/src/cu/transpiler/codegen/codegen_test.cu` |
| `utils/test/engine/compiler/cycle/record_host_test.c` | `utils/test/src/c/engine/analysis/cycle/record_test.c` |
| `utils/test/engine/runtime/daemon/tessera_device_test.cu` | `utils/test/src/cu/engine/runtime/daemon/tessera_test.cu` |

## Names that stay

| file | would be | why it stays |
|---|---|---|
| `src/engine/nbody/max_tree/max_tree_device_overlap.cu` | `max_tree_overlap.cu` | another file there has that name |
| `src/engine/nbody/max_tree/max_tree_device_overlap_kernels.cu` | `max_tree_overlap.cu` | another file there has that name |

## Functions under two names

Each of these modules is in more than one container and its containers share no function name, so one
function may stand under two names. The map writes each name into the containers that lack it until the
names are one.

| module | functions |
|---|---|
| `src/*/engine/analysis/cycle` | c: `cycle`; cu: `cycle_compile`, `cycle_compile_cache`, `cycle_compile_route`, `cycle_compile_toolchain`, `cycle_launch`, `cycle_prelude`, `cycle_record`, `cycle_record_launch`, `cycle_sweep` |
| `src/*/engine/nbody/max_tree` | c: `max_tree_build`, `max_tree_nodes`, `max_tree_pairs`; cu: `max_tree_code`, `max_tree_contract`, `max_tree_device_overlap`, `max_tree_device_overlap_kernels`, `max_tree_grade`, `max_tree_label`, `max_tree_objects`, `max_tree_pack`, `max_tree_select`, `max_tree_slide` |
| `src/*/engine/render` | c: `anchor_raster`, `anchor_raster_output`; cu: `raster`, `raster_entry`; python: `host`, `native` |
| `src/*/engine/runtime/daemon` | c: `tessera_client_jobs`, `tessera_client_socket`, `tessera_daemon_admission`, `tessera_daemon_main`, `tessera_daemon_peers`, `tessera_daemon_state`, `tessera_frame`, `tessera_ledger`, `tessera_measure`, `tessera_paths`, `tessera_run_child`, `tessera_run_common`, `tessera_run_main`, `tessera_run_posix`, `tessera_run_windows`, `tessera_self`; cu: `tessera` |
| `src/*/transpiler/qasm` | c: `qasm_chain_apply`, `qasm_chain_matrix`, `qasm_dense`, `qasm_exact`, `qasm_expression`, `qasm_field_number`, `qasm_field_rational`, `qasm_gates`, `qasm_lens_hash`, `qasm_lens_rank`, `qasm_lexer`, `qasm_read`, `qasm_statements`, `qasm_symbolic_function`, `qasm_symbolic_polynomial`, `qasm_trig`; cu: `qasm`, `qasm_bitstring`, `qasm_program`, `qasm_run`, `qasm_self_program`, `qasm_self_run` |
| `src/*/types/file_defs/krs` | c: `sass_machine`; cu: `ruleset_flat` |
| `src/*/types/integers` | c: `arm`, `exact_integer_add`, `exact_integer_decimal`, `exact_integer_divide`, `exact_integer_gcd`, `exact_integer_hash`, `exact_integer_limbs`, `exact_integer_multiply`; cu: `arm`; python: `exact` |
| `utils/test/src/*/engine/analysis` | cu: `periodic_energy_probe`; python: `periodic_energy_test` |
| `utils/test/src/*/engine/analysis/cycle` | c: `record_test`; cu: `record_bitwise_test_lifting`, `record_bitwise_test_oracle`, `record_bitwise_test_prove`, `record_boundary_test_codes`, `record_boundary_test_floors`, `record_boundary_test_identity`, `record_boundary_test_main`, `record_boundary_test_run`, `record_boundary_test_transform`, `record_c_test`, `record_coherence_test_inverse`, `record_coherence_test_programs`, `record_coherence_test_residue`, `record_divide_test_main`, `record_divide_test_run`, `record_gaussian_test_inverse`, `record_gaussian_test_main`, `record_guide_test`, `record_lane_test_enumerate`, `record_lane_test_run`, `record_order_test_floors`, `record_order_test_omega`, `record_speed_test`, `record_table_test_compose`, `record_table_test_run`, `record_tower_test_oracle`, `record_tower_test_ruleset`, `record_vhdl_test` |
| `utils/test/src/*/engine/analysis/period` | cu: `period_probe`, `period_test_main`, `period_test_reference`; python: `period_test` |
| `utils/test/src/*/engine/analysis/shift_agreement` | cu: `shift_agreement_hold_test`; python: `shift_agreement_test` |
| `utils/test/src/*/engine/nbody/orior` | c: `test_adversarial_cases`, `test_adversarial_joint`, `test_adversarial_plans`, `test_adversarial_projection`, `test_o2_spawn`, `test_steer_checks`, `test_steer_grading`, `test_steer_projection`; python: `sift_test` |
| `utils/test/src/*/engine/runtime/daemon` | c: `tessera_burn`, `tessera_frame_test`, `tessera_ledger_test_heap`, `tessera_ledger_test_scenarios`, `tessera_socket_probe`; cu: `tessera_job_test`, `tessera_measure_test`, `tessera_test` |
| `utils/test/src/*/transpiler/cell` | c: `cell_probe`, `cell_ptx_test`, `cell_sass_probe_ask`, `cell_sass_probe_check`, `cell_sass_probe_cubin`, `cell_sass_probe_machine`, `cell_sass_probe_main`, `cell_sass_probe_read`, `cell_test`; cu: `cell_ptx_probe_main`, `cell_ptx_probe_questions` |
| `utils/test/src/*/transpiler/codegen` | c: `web_check`; cu: `codegen_test`, `ruleset_read_test`, `vhdl_construction_set` |
| `utils/test/src/*/types/integers` | c: `test_arm_agreement`; cu: `exact_divide_test`, `exact_transform_test`; python: `exact_test` |
