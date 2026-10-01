# Tree layout plan

**Purpose:** The map `src/` is projected onto. Every tracked file under `src/` and under the test tree has a place here, read from the file itself.
**Scope:** The 647 files `git ls-files src` lists and the 178 `git ls-files utils/test` lists. `src/import/` is outside this plan and is left to the sessions working in it.

Nothing is moved by this file. It is the tally a move reads from, and every count in it is computed from the file list.

## Rules the tree follows

- `src/` holds one container per host entry point: `c/`, `cu/` and `python/`. Every other language waits.
- `src/sims/` holds the sims, one container per language, `c/`, `cu/` and `python/`, each mirroring its language's container: a sim sits at the path of what it exercises. The R and the MATLAB/Octave sims are `evidence/`'s, in `evidence/sims/r/` and `evidence/sims/matlab/`.
- Inside a container the categories are the skeleton's. `types/` holds what a value or a file is. `includes/` holds what the rest builds on and does not own: arithmetic, codecs, external file formats, and the answers that come from outside the sample. `apxrep/` becomes `kcmplx/`, the crystal's reader and writer. `engine/` holds analysis, render, runtime, prg_sch and nbody, with `cycle/`, `keymath/` and `key_schedule/` in `engine/analysis/`. `transpiler/` holds the rest of what `compiler/` holds now, and the qasm reader, which reads OpenQASM into programs on the record machine.
- `types/file_defs/` defines the file types, one directory per suffix `gnascor.md` names: `ksc/` and `krs/` for coherence, `kcr/`, `knf/` and `kcs/` for data, `kdm/` for the host ruleset, and `g/` and `gsm/` for the compiler's two faces. A directory holds the code that defines its type, the format and the reader and writer, and never the files of that type: a ruleset, a device map or a classification sits beside the code that reads it. `krep/` holds the head and the words every k-file shares, and `KCR`, `KNF` and `KCS` are its kinds.
- A file's container is its language. A `.c` file is `c`, a `.cu` file is `cu`, a `.py` file is `python`. A `.h` file is `cu` where it uses `__device__`, `__global__`, `__host__`, `template`, `std::`, `class` or `<<<`, and `c` otherwise, since a C header builds under both.
- The Python engine's parts take the category of what they do: `measure/`, `reference/` and `partition/` are analysis, `sift/` and `instrument/` are anchor_sift's, `render/` is the renderer, `oracle/` is an answer from outside, `representation/` is ingest, and its `exact.py` and `constants/` are the exact integers.
- The test tree mirrors `src/` the same way, under `utils/test/src/`. `evidence/` and `examples/` carry a sims tree and a test tree of their own in the same shape.

## `src/`

Each directory carries the count of code files in it and below it.

```text
src/
├── c/                                                        275
│   ├── types/                                                 31
│   │   ├── file_defs/                                          9
│   │   │   ├── kdm/                                            1
│   │   │   ├── krep/                                           2
│   │   │   ├── krs/                                            5
│   │   │   └── ksc/                                            1
│   │   ├── integers/                                          18
│   │   └── integerfloats/                                      4
│   │       ├── decimal_double/                                 2
│   │       └── double_fields/                                  2
│   ├── includes/                                              64
│   │   ├── codecs/                                            26
│   │   │   ├── blosc/                                          2
│   │   │   ├── crc/                                            3
│   │   │   ├── deflate/                                        4
│   │   │   ├── inflate/                                        4
│   │   │   ├── lz4/                                            2
│   │   │   ├── snappy/                                         2
│   │   │   ├── zip/                                            4
│   │   │   └── zstd/                                           5
│   │   └── formats/                                           38
│   │       ├── cfg_json/                                       2
│   │       ├── dicom/                                          6
│   │       ├── hdf5/                                           9
│   │       ├── nifti/                                          2
│   │       ├── npy/                                            4
│   │       ├── nrrd/                                           4
│   │       ├── stack/                                          1
│   │       ├── tiff/                                           6
│   │       └── zarr/                                           4
│   ├── compression/                                            1
│   ├── kcmplx/                                                 2
│   ├── engine/                                               109
│   │   ├── analysis/                                          16
│   │   │   ├── cycle/                                          2
│   │   │   ├── entropy_history/                                1
│   │   │   ├── golden_bands/                                   1
│   │   │   ├── key_schedule/                                   1
│   │   │   ├── keymath/                                        3
│   │   │   ├── noise_detector/                                 1
│   │   │   ├── period/                                         1
│   │   │   ├── residual/                                       1
│   │   │   ├── residual_survey/                                1
│   │   │   ├── shift_agreement/                                2
│   │   │   ├── tower/                                          1
│   │   │   └── unit_sweep/                                     1
│   │   ├── nbody/                                             42
│   │   │   ├── anchor_sift/                                   15
│   │   │   ├── bodies/                                         1
│   │   │   ├── body_overlap/                                   2
│   │   │   ├── box_history/                                    1
│   │   │   ├── climb_machine/                                  2
│   │   │   ├── contact_side/                                   1
│   │   │   ├── division/                                       1
│   │   │   ├── fingerprint/                                    1
│   │   │   ├── flatten/                                        1
│   │   │   ├── group_objects/                                  1
│   │   │   ├── grow/                                           1
│   │   │   ├── heaviest_matching/                              2
│   │   │   ├── link_objects/                                   2
│   │   │   ├── marginal/                                       2
│   │   │   ├── max_tree/                                       5
│   │   │   ├── print_pair/                                     1
│   │   │   ├── relate_frames/                                  2
│   │   │   └── velocity/                                       1
│   │   ├── prg_sch/                                            3
│   │   │   ├── answer_key/                                     1
│   │   │   ├── run_cfg/                                        1
│   │   │   └── run_log/                                        1
│   │   ├── render/                                             4
│   │   └── runtime/                                           38
│   │       ├── daemon/                                        26
│   │       ├── device_pool/                                    1
│   │       ├── obsignatio/                                     1
│   │       ├── radix_keys/                                     1
│   │       ├── schedule/                                       1
│   │       └── scriptura/                                      8
│   └── transpiler/                                            68
│       ├── bootstrap/                                         16
│       ├── cell/                                               3
│       ├── codegen/                                           16
│       ├── cubin/                                              3
│       ├── emit/                                               4
│       └── qasm/                                              26
├── cu/                                                       158
│   ├── types/                                                  6
│   │   ├── file_defs/                                          5
│   │   │   ├── krep/                                           2
│   │   │   └── krs/                                            3
│   │   └── integers/                                           1
│   ├── includes/                                               2
│   │   ├── codecs/                                             1
│   │   │   └── crc/                                            1
│   │   └── formats/                                            1
│   │       └── stack/                                          1
│   ├── compression/                                            1
│   ├── kcmplx/                                                 2
│   ├── engine/                                               108
│   │   ├── analysis/                                          47
│   │   │   ├── cycle/                                         15
│   │   │   ├── entropy_history/                                1
│   │   │   ├── golden_bands/                                   1
│   │   │   ├── key_schedule/                                   2
│   │   │   ├── keymath/                                        2
│   │   │   ├── noise_detector/                                13
│   │   │   ├── period/                                         3
│   │   │   ├── residual/                                       1
│   │   │   ├── residual_survey/                                1
│   │   │   ├── shift_agreement/                                3
│   │   │   ├── tower/                                          4
│   │   │   └── unit_sweep/                                     1
│   │   ├── nbody/                                             38
│   │   │   ├── anchor_sift/                                    2
│   │   │   ├── bodies/                                         1
│   │   │   ├── body_overlap/                                   1
│   │   │   ├── box_history/                                    1
│   │   │   ├── climb_machine/                                  8
│   │   │   ├── contact_side/                                   1
│   │   │   ├── division/                                       1
│   │   │   ├── fingerprint/                                    1
│   │   │   ├── flatten/                                        1
│   │   │   ├── group_objects/                                  1
│   │   │   ├── grow/                                           1
│   │   │   ├── link_objects/                                   3
│   │   │   ├── marginal/                                       1
│   │   │   ├── max_tree/                                      11
│   │   │   ├── print_pair/                                     1
│   │   │   ├── relate_frames/                                  2
│   │   │   └── velocity/                                       1
│   │   ├── prg_sch/                                            4
│   │   │   ├── answer_key/                                     1
│   │   │   ├── run_cfg/                                        2
│   │   │   └── run_log/                                        1
│   │   ├── render/                                             3
│   │   └── runtime/                                            7
│   │       ├── daemon/                                         2
│   │       ├── device_pool/                                    1
│   │       ├── obsignatio/                                     3
│   │       └── schedule/                                       1
│   └── transpiler/                                            39
│       ├── codegen/                                           30
│       ├── cubin/                                              1
│       └── qasm/                                               8
├── python/                                                    89
│   ├── types/                                                  3
│   │   └── integers/                                           3
│   │       └── constants/                                      2
│   ├── includes/                                              39
│   │   ├── formats/                                           34
│   │   │   └── representation/                                34
│   │   │       ├── atom/                                       2
│   │   │       ├── game/                                       8
│   │   │       ├── particle/                                   2
│   │   │       ├── picture/                                    2
│   │   │       ├── sound/                                      3
│   │   │       ├── structure/                                  4
│   │   │       └── text/                                       9
│   │   └── oracle/                                             5
│   │       └── language/                                       4
│   └── engine/                                                47
│       ├── analysis/                                          36
│       │   ├── measure/                                       21
│       │   ├── partition/                                      4
│       │   └── reference/                                     11
│       ├── nbody/                                              8
│       │   └── anchor_sift/                                    8
│       │       ├── instrument/                                 3
│       │       └── sift/                                       5
│       └── render/                                             3
└── sims/                                                      79
    ├── c/                                                      7
    │   ├── types/                                              1
    │   │   └── integers/                                       1
    │   │       └── ka_psi/                                     1
    │   ├── engine/                                             3
    │   │   └── analysis/                                       3
    │   │       ├── knf_identity/                               1
    │   │       ├── noise_terms/                                1
    │   │       └── root_universal/                             1
    │   └── transpiler/                                         1
    │       └── ask_state/                                      1
    ├── cu/                                                    72
    │   ├── types/                                             41
    │   │   └── integers/                                      41
    │   │       ├── chaitin_omega/                             11
    │   │       ├── goodstein/                                  3
    │   │       ├── ka_psi/                                     4
    │   │       ├── omega_computer/                             4
    │   │       ├── pi_plane/                                   9
    │   │       └── pi_tower/                                  10
    │   ├── engine/                                            25
    │   │   ├── analysis/                                      24
    │   │   │   ├── art/                                        3
    │   │   │   ├── floor_match/                                3
    │   │   │   ├── floor_track/                                4
    │   │   │   ├── knf_identity/                               3
    │   │   │   ├── noise_floor/                                3
    │   │   │   ├── noise_root/                                 1
    │   │   │   ├── noise_terms/                                4
    │   │   │   ├── period_power/                               1
    │   │   │   └── root_universal/                             2
    │   │   └── nbody/                                          1
    │   │       └── nbody_lattice/                              1
    │   └── transpiler/                                         2
    │       └── ask_state/                                      2
    └── python/                                                 0
```

### Files with no language

Each sits in the directory named, and the files at `src/` itself serve every container.

| directory | files |
|---|---|
| `(root)` | `README.md`, `build_engine.sh`, `engine_plan.md`, `manifest.tsv` |
| `c` | `CMakeLists.txt` |
| `cu` | `long_paths.manifest` |
| `engine/prg_sch` | `README.md` |
| `engine/prg_sch/cfg` | 10: `allframes.cfg` and the rest |
| `engine/prg_sch/nbody_program` | `program.json` |
| `engine/runtime/daemon` | `README.md`, `tessera@.service`, `tessera@.socket` |
| `python` | `README.md` |
| `python/engine/analysis/measure` | `README.md` |
| `python/engine/analysis/partition` | `README.md` |
| `python/engine/analysis/reference` | `README.md` |
| `python/engine/nbody/anchor_sift/sift` | `README.md` |
| `python/includes/formats/representation` | `README.md` |
| `python/includes/oracle` | `README.md` |
| `python/types/integers/constants` | `README.md` |
| `sims` | `run.sh` |
| `transpiler` | `gnascor.md` |
| `transpiler/codegen/rulesets` | 5: `c.krs` and the rest |
| `transpiler/cubin/machines` | `sm_86.kdm`, `sm_86.krs`, `sm_86.ksc` |
| `transpiler/emit/layouts` | `elf64_nvidia.tsv` |
| `transpiler/qasm` | `build.sh`, `run.sh` |

### Leaving `src/`

| now | goes to | what it is |
|---|---|---|
| `src/engine/r/` | `evidence/sims/r/` | the R hypothesis tests over the CSVs the Python engine writes |
| `src/engine/matlab/sim_cluster_rapid_deploy/` | `evidence/sims/matlab/` | the runner that deploys a `.m` sim on MATLAB or Octave across a cluster |

## The test tree, `utils/test/src/`

```text
utils/test/src/
├── c/                                                         53
│   ├── types/                                                  1
│   │   └── integers/                                           1
│   ├── engine/                                                30
│   │   ├── analysis/                                          10
│   │   │   ├── cycle/                                          9
│   │   │   └── period/                                         1
│   │   ├── nbody/                                             12
│   │   │   ├── anchor_sift/                                    9
│   │   │   └── max_tree/                                       3
│   │   └── runtime/                                            8
│   │       ├── daemon/                                         6
│   │       ├── obsignatio/                                     1
│   │       └── scriptura/                                      1
│   └── transpiler/                                            22
│       ├── bootstrap/                                          9
│       ├── cell/                                              10
│       ├── codegen/                                            1
│       └── qasm/                                               2
├── cu/                                                        63
│   ├── types/                                                  2
│   │   └── integers/                                           2
│   ├── engine/                                                48
│   │   ├── analysis/                                          39
│   │   │   ├── cycle/                                         31
│   │   │   ├── period/                                         2
│   │   │   ├── residual/                                       1
│   │   │   ├── shift_agreement/                                1
│   │   │   ├── tower/                                          1
│   │   │   └── unit_sweep/                                     1
│   │   ├── nbody/                                              1
│   │   │   └── anchor_sift/                                    1
│   │   └── runtime/                                            8
│   │       ├── daemon/                                         3
│   │       ├── device_pool/                                    1
│   │       └── obsignatio/                                     4
│   └── transpiler/                                            13
│       ├── cell/                                               4
│       ├── codegen/                                            3
│       ├── emit/                                               1
│       └── qasm/                                               5
└── python/                                                     6
    ├── types/                                                  1
    │   └── integers/                                           1
    └── engine/                                                 5
        ├── analysis/                                           3
        ├── nbody/                                              1
        │   └── anchor_sift/                                    1
        └── render/                                             1
```

### Test files with no language

| directory | files |
|---|---|
| `engine/analysis` | `period_test.sh`, `periodic_energy_test.sh` |
| `engine/analysis/cycle` | 15: `record_bitwise_test.sh` and the rest |
| `engine/analysis/period` | `period_test.sh` |
| `engine/analysis/residual` | `residual_odd_test.sh` |
| `engine/analysis/shift_agreement` | `shift_agreement_hold_test.sh` |
| `engine/analysis/tower` | `tower_edge_test.sh` |
| `engine/analysis/unit_sweep` | `unit_sweep_planes_test.sh` |
| `engine/nbody/anchor_sift` | `anchor_sift_probe.def` |
| `engine/nbody/max_tree` | `run.sh` |
| `engine/runtime/daemon` | `run.sh`, `tessera_device_test.sh`, `tessera_run_test.sh` |
| `engine/runtime/device_pool` | `device_pool_test.sh` |
| `engine/runtime/obsignatio` | `run.sh`, `test_vectors.json` |
| `transpiler/cell` | `cell_ptx_test.sh`, `cell_sass_test.sh`, `cell_test.sh` |
| `transpiler/codegen` | `codegen_device_test.sh`, `ruleset_read_test.sh`, `vhdl_construction_set.sh`, `web_check.sh` |
| `transpiler/codegen/rulesets/flagless` | `c.krs`, `ptx.krs` |
| `transpiler/qasm` | 11: `MANIFEST.json` and the rest |
| `types/integers` | `exact_divide_test.sh`, `exact_transform_test.sh` |

`utils/test/maint/` is the test mirror of `utils/maint/`, and `harness.py`, `__init__.py` and `test_matrix.json` run every test from the root of `utils/test/`; all of them stay where they are.

## `evidence/` and `examples/`

```text
evidence/
├── proofs/posits/                                      15
└── sims/
    ├── matlab/                                          4  (2 + src/engine/matlab/)
    └── r/                                               5  (1 + src/engine/r/)
examples/                                              391
└── sims/                                                (empty)
utils/test/evidence/                                     (empty)
utils/test/examples/
└── cell_tracking/                                      13  <- examples/cell_tracking/test/
```

`examples/language/4_measure/*_test.py` are measures, `LNG-4-001` and its siblings for Section 4.13, and stay in `4_measure/`.

## What defines each file type

| suffix | defined by | files of the type, beside the code that reads them |
|---|---|---|
| `.krs` | `ruleset_core.h`, `ruleset_core_read.h`, `ruleset_core_scratch.h`, `ruleset_core_words.h`: the reader the host and the device both run; `ruleset_flat.{h,cu}`: that reader laid out for the host, and the file read; `sass_machine.{c,h}`: the machine file's format, reader and writer | `transpiler/codegen/rulesets/{c,ptx,sass,vhdl,yosys}.krs`; `transpiler/cubin/machines/sm_86.krs`, the file now named `sm_86` |
| `.kdm` | `kdm_write.c`, which reads and writes a part's `.kdm`, from `utils/maint/engine/` | `transpiler/cubin/machines/sm_86.kdm` |
| `.ksc` | `cell_sass_probe_class.c`, which writes `<part>.ksc`, from `utils/test/engine/compiler/cell/` | `transpiler/cubin/machines/sm_86.ksc` |
| `.kcr`, `.knf`, `.kcs` | `krep/`: the head every k-file opens with, and the kinds `KCR`, `KNF` and `KCS` | written by the engine at run time |
| `.g`, `.gsm` | nothing yet | none yet |

`kdm_write.c` and `cell_sass_probe_class.c` come into `c/types/file_defs/kdm/` and `c/types/file_defs/ksc/` from `utils/`, since they are the definitions. `sm_86` takes its suffix, `.krs`, where it stands.
