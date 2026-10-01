# Tree layout plan

**Purpose:** The map `src/` is projected onto. Every tracked file under `src/` and under the test tree has a row here, either a place in a tree below or a line in the undecided table.
**Scope:** The 646 files `git ls-files src` lists and the 178 `git ls-files utils/test` lists. `src/import/` is outside this plan and is left to the sessions working in it.

Nothing is moved by this file. It is the tally a move reads from, and every count in it is computed from the file list.

## Rules the tree follows

- `src/` holds one container per host entry point: `c/`, `cu/` and `python/`. Every other language waits.
- `src/sims/` holds the sims, one container per language, `c/`, `cu/` and `python/`, each mirroring its language's container: a sim sits at the path of what it exercises.
- Inside a container the categories are the skeleton's. `types/` holds what a value or a file is, with `file_defs/` one directory per internal file type. `includes/` holds what the rest builds on and does not own: arithmetic, codecs and external file formats. `apxrep/` becomes `kcmplx/`, the crystal's reader and writer. `engine/` holds analysis, render, runtime, prg_sch and nbody, with `cycle/`, `keymath/` and `key_schedule/` in `engine/analysis/`. `transpiler/` holds the rest of what `compiler/` holds now.
- A file's container is its language. A `.c` file is `c`, a `.cu` file is `cu`, a `.py` file is `python`. A `.h` file is `cu` where it uses `__device__`, `__global__`, `__host__`, `template`, `std::`, `class` or `<<<`, and `c` otherwise, since a C header builds under both.
- The test tree mirrors `src/` the same way, under `utils/test/src/`. `evidence/` and `examples/` carry a sims tree and a test tree of their own in the same shape.

The internal file types, as `RDMERF.md` names them:

| suffix | name | holds |
|---|---|---|
| `.kcr` | Kolmogorov information crystal | information at or near its Kolmogorov complexity |
| `.krs` | Kolmogorov information ruleset | the coherence rules |
| `.kcs` | Kolmogorov information crystal (re)construction set | what reconstructs information |
| `.knf` | Kolmogorov noise floor | a measured noise floor |
| `.kdm` | Kolmogorov device map | the hardware map |
| `.ksc` | Kolmogorov system classification | the language map |

## `src/`

Each directory carries the count of files in it and below it.

```text
src/
├── c/                                                    245
│   ├── types/                                             22
│   │   ├── integerfloats/                                  4
│   │   │   ├── decimal_double/                             2
│   │   │   └── double_fields/                              2
│   │   └── integers/                                      18
│   ├── includes/                                          64
│   │   ├── codecs/                                        26
│   │   │   ├── blosc/                                      2
│   │   │   ├── crc/                                        3
│   │   │   ├── deflate/                                    4
│   │   │   ├── inflate/                                    4
│   │   │   ├── lz4/                                        2
│   │   │   ├── snappy/                                     2
│   │   │   ├── zip/                                        4
│   │   │   └── zstd/                                       5
│   │   └── formats/                                       38
│   │       ├── cfg_json/                                   2
│   │       ├── dicom/                                      6
│   │       ├── hdf5/                                       9
│   │       ├── nifti/                                      2
│   │       ├── npy/                                        4
│   │       ├── nrrd/                                       4
│   │       ├── stack/                                      1
│   │       ├── tiff/                                       6
│   │       └── zarr/                                       4
│   ├── compression/                                        1
│   ├── kcmplx/                                             2
│   ├── engine/                                           109
│   │   ├── analysis/                                      16
│   │   │   ├── cycle/                                      2
│   │   │   ├── entropy_history/                            1
│   │   │   ├── golden_bands/                               1
│   │   │   ├── key_schedule/                               1
│   │   │   ├── keymath/                                    3
│   │   │   ├── noise_detector/                             1
│   │   │   ├── period/                                     1
│   │   │   ├── residual/                                   1
│   │   │   ├── residual_survey/                            1
│   │   │   ├── shift_agreement/                            2
│   │   │   ├── tower/                                      1
│   │   │   └── unit_sweep/                                 1
│   │   ├── nbody/                                         42
│   │   │   ├── anchor_sift/                               15
│   │   │   ├── bodies/                                     1
│   │   │   ├── body_overlap/                               2
│   │   │   ├── box_history/                                1
│   │   │   ├── climb_machine/                              2
│   │   │   ├── contact_side/                               1
│   │   │   ├── division/                                   1
│   │   │   ├── fingerprint/                                1
│   │   │   ├── flatten/                                    1
│   │   │   ├── group_objects/                              1
│   │   │   ├── grow/                                       1
│   │   │   ├── heaviest_matching/                          2
│   │   │   ├── link_objects/                               2
│   │   │   ├── marginal/                                   2
│   │   │   ├── max_tree/                                   5
│   │   │   ├── print_pair/                                 1
│   │   │   ├── relate_frames/                              2
│   │   │   └── velocity/                                   1
│   │   ├── prg_sch/                                        3
│   │   │   ├── answer_key/                                 1
│   │   │   ├── run_cfg/                                    1
│   │   │   └── run_log/                                    1
│   │   ├── render/                                         4
│   │   └── runtime/                                       38
│   │       ├── daemon/                                    26
│   │       ├── device_pool/                                1
│   │       ├── obsignatio/                                 1
│   │       ├── radix_keys/                                 1
│   │       ├── schedule/                                   1
│   │       └── scriptura/                                  8
│   └── transpiler/                                        47
│       ├── bootstrap/                                     16
│       ├── cell/                                           3
│       ├── codegen/                                       19
│       ├── cubin/                                          5
│       └── emit/                                           4
├── cu/                                                   148
│   ├── types/                                              1
│   │   └── integers/                                       1
│   ├── includes/                                           2
│   │   ├── codecs/                                         1
│   │   │   └── crc/                                        1
│   │   └── formats/                                        1
│   │       └── stack/                                      1
│   ├── compression/                                        1
│   ├── kcmplx/                                             2
│   ├── engine/                                           108
│   │   ├── analysis/                                      47
│   │   │   ├── cycle/                                     15
│   │   │   ├── entropy_history/                            1
│   │   │   ├── golden_bands/                               1
│   │   │   ├── key_schedule/                               2
│   │   │   ├── keymath/                                    2
│   │   │   ├── noise_detector/                            13
│   │   │   ├── period/                                     3
│   │   │   ├── residual/                                   1
│   │   │   ├── residual_survey/                            1
│   │   │   ├── shift_agreement/                            3
│   │   │   ├── tower/                                      4
│   │   │   └── unit_sweep/                                 1
│   │   ├── nbody/                                         38
│   │   │   ├── anchor_sift/                                2
│   │   │   ├── bodies/                                     1
│   │   │   ├── body_overlap/                               1
│   │   │   ├── box_history/                                1
│   │   │   ├── climb_machine/                              8
│   │   │   ├── contact_side/                               1
│   │   │   ├── division/                                   1
│   │   │   ├── fingerprint/                                1
│   │   │   ├── flatten/                                    1
│   │   │   ├── group_objects/                              1
│   │   │   ├── grow/                                       1
│   │   │   ├── link_objects/                               3
│   │   │   ├── marginal/                                   1
│   │   │   ├── max_tree/                                  11
│   │   │   ├── print_pair/                                 1
│   │   │   ├── relate_frames/                              2
│   │   │   └── velocity/                                   1
│   │   ├── prg_sch/                                        4
│   │   │   ├── answer_key/                                 1
│   │   │   ├── run_cfg/                                    2
│   │   │   └── run_log/                                    1
│   │   ├── render/                                         3
│   │   └── runtime/                                        7
│   │       ├── daemon/                                     2
│   │       ├── device_pool/                                1
│   │       ├── obsignatio/                                 3
│   │       └── schedule/                                   1
│   └── transpiler/                                        34
│       ├── codegen/                                       33
│       └── cubin/                                          1
├── python/                                                89
│   ├── instrument/                                         3
│   ├── measure/                                           21
│   ├── oracle/                                             5
│   │   └── language/                                       4
│   ├── partition/                                          4
│   ├── reference/                                         11
│   ├── render/                                             3
│   ├── representation/                                    37
│   │   ├── atom/                                           2
│   │   ├── constants/                                      2
│   │   ├── game/                                           8
│   │   ├── particle/                                       2
│   │   ├── picture/                                        2
│   │   ├── sound/                                          3
│   │   ├── structure/                                      4
│   │   └── text/                                           9
│   └── sift/                                               5
└── sims/                                                  64
    ├── c/                                                  4
    │   ├── engine/                                         1
    │   │   └── analysis/                                   1
    │   │       └── noise_terms/                            1
    │   └── transpiler/                                     1
    │       └── ask_state/                                  1
    ├── cu/                                                60
    │   ├── types/                                         37
    │   │   └── integers/                                  37
    │   │       ├── chaitin_omega/                         11
    │   │       ├── goodstein/                              3
    │   │       ├── omega_computer/                         4
    │   │       ├── pi_plane/                               9
    │   │       └── pi_tower/                              10
    │   ├── engine/                                        17
    │   │   ├── analysis/                                  16
    │   │   │   ├── floor_match/                            3
    │   │   │   ├── floor_track/                            4
    │   │   │   ├── noise_floor/                            3
    │   │   │   ├── noise_root/                             1
    │   │   │   ├── noise_terms/                            4
    │   │   │   └── period_power/                           1
    │   │   └── nbody/                                      1
    │   │       └── nbody_lattice/                          1
    │   └── transpiler/                                     2
    │       └── ask_state/                                  2
    └── python/                                             0
```

546 of the 646 files have a place above. The `python/` container keeps the Python engine's parts as they stand; which category each part takes inside it is in the undecided table.


### Files with no language

These sit in the category directory the tree gives them, in the container of the code that reads them.

| category | files |
|---|---|
| `engine/prg_sch` | `README.md` |
| `engine/prg_sch/cfg` | 10 files: `allframes.cfg` and the rest |
| `engine/prg_sch/nbody_program` | `program.json` |
| `engine/runtime/daemon` | `README.md`, `tessera@.service`, `tessera@.socket` |
| `python/` | `README.md` |
| `python/measure` | `README.md` |
| `python/oracle` | `README.md` |
| `python/partition` | `README.md` |
| `python/reference` | `README.md` |
| `python/representation` | `README.md` |
| `python/representation/constants` | `README.md` |
| `python/sift` | `README.md` |
| `sims` | `run.sh` |
| `src/engine_plan.md` | `engine_plan.md` |
| `transpiler` | `gnascor.md` |
| `transpiler/emit` | `elf64_nvidia.tsv` |
| `types/file_defs/kdm` | `sm_86.kdm` |
| `types/file_defs/krs` | 5 files: `c.krs` and the rest |
| `types/file_defs/ksc` | `sm_86.ksc` |

## The test tree, `utils/test/src/`

107 of the 155 files under `utils/test/engine/`, placed by the same map. Runner scripts are listed under the tree.

```text
utils/test/src/
├── c/                                                     51
│   ├── types/                                              1
│   │   └── integers/                                       1
│   ├── engine/                                            30
│   │   ├── analysis/                                      10
│   │   │   ├── cycle/                                      9
│   │   │   └── period/                                     1
│   │   ├── nbody/                                         12
│   │   │   ├── anchor_sift/                                9
│   │   │   └── max_tree/                                   3
│   │   └── runtime/                                        8
│   │       ├── daemon/                                     6
│   │       ├── obsignatio/                                 1
│   │       └── scriptura/                                  1
│   └── transpiler/                                        20
│       ├── bootstrap/                                      9
│       ├── cell/                                          10
│       └── codegen/                                        1
└── cu/                                                    56
    ├── types/                                              2
    │   └── integers/                                       2
    ├── engine/                                            46
    │   ├── analysis/                                      37
    │   │   ├── cycle/                                     31
    │   │   ├── period/                                     2
    │   │   ├── residual/                                   1
    │   │   ├── shift_agreement/                            1
    │   │   ├── tower/                                      1
    │   │   └── unit_sweep/                                 1
    │   ├── nbody/                                          1
    │   │   └── anchor_sift/                                1
    │   └── runtime/                                        8
    │       ├── daemon/                                     3
    │       ├── device_pool/                                1
    │       └── obsignatio/                                 4
    └── transpiler/                                         8
        ├── cell/                                           4
        ├── codegen/                                        3
        └── emit/                                           1
```

| category | runner scripts and data |
|---|---|
| `engine/analysis/cycle` | 15 |
| `engine/analysis/period` | 1 |
| `engine/analysis/residual` | 1 |
| `engine/analysis/shift_agreement` | 1 |
| `engine/analysis/tower` | 1 |
| `engine/analysis/unit_sweep` | 1 |
| `engine/nbody/max_tree` | 1 |
| `engine/runtime/daemon` | 3 |
| `engine/runtime/device_pool` | 1 |
| `engine/runtime/obsignatio` | 2 |
| `transpiler/cell` | 3 |
| `transpiler/codegen` | 4 |
| `types/file_defs/krs` | 2 |
| `types/integers` | 2 |

## `evidence/` and `examples/`

```text
evidence/
├── proofs/posits/                                      15
└── sims/
    ├── matlab/                                          2
    └── r/                                               1
examples/                                              391
└── sims/                                                (empty)
utils/test/evidence/                                     (empty)
utils/test/examples/
└── cell_tracking/                                      13  <- examples/cell_tracking/test/
```


## Undecided

| now | files | what it is | could go |
|---|---|---|---|
| `src/engine/python/` parts | 97 | the Python engine: `representation/` 39, `measure/` 22, `reference/` 12, `oracle/` 6, `sift/` 6, `partition/` 5, `instrument/` 3, `render/` 3, and its `README.md` | the category inside `python/` each part serves |
| `src/engine/compiler/` | 1 | `sm_86`, the part's machine file, its instructions as the cell's probes read them back | `types/file_defs/kdm/` beside `sm_86.kdm`, or `transpiler/cubin/` beside `sass_machine.{c,h}` |
| `src/engine/formats/` | 4 | the krep format's reader and writer | `types/file_defs/`, or `includes/formats/` |
| `src/engine/matlab/` | 2 | tools for deploying the sims on a cluster | `evidence/sims/matlab/` |
| `src/engine/quantum/` | 35 | the OpenQASM reader and its exact, symbolic, dense and device simulators, C and CUDA | `c/` and `cu/` by file, under the category its numbers are or one of its own |
| `src/engine/r/` | 4 | the R hypothesis tests the other implementations' statistics rest on | `evidence/sims/r/` beside `departure.R` |
| `src/engine/sims/` | 15 | sims whose headers name no category: `art/` 3, `ka_psi/` 5, `knf_identity/` 4, `root_universal/` 3 | `sims/cu/` under the category each exercises |
| `src/engine/` build, front page and records | 5 | `CMakeLists.txt`, `README.md`, `build_engine.sh`, `long_paths.manifest`, `manifest.tsv` | `src/`, or the `engine/` of each container |
| `includes/arithmetic/` | 0 | named by the skeleton, nothing placed in it | the shared headers of `types/integers/`: `exact_integer.h`, `exact_integer_api.h`, `arm.h` |
| `utils/test/engine/quantum/qasm/` | 10 | qasm's tests | follows `quantum/qasm/` |
| `utils/test/python/` | 11 | the Python engine's tests and the CUDA probes they drive | `utils/test/src/python/`, under each part's category |
| `utils/test/vectors/` | 8 | the NIST CAVP and Wycheproof SHA-256 and HMAC vectors | beside the tests of whatever hashes in `src/` |
| `utils/test/maint/` | 1 | a test of a `utils/maint/` tool | a test mirror of `utils/maint/` |
| `utils/test/` root | 3 | `__init__.py`, `harness.py`, `test_matrix.json`, what runs every test | the root of `utils/test/` |
| `examples/language/4_measure/*_test.py` | 4 | author, Malagasy, Nguni and Uralic measures named as tests | `utils/test/examples/language/`, or measures where they are |
