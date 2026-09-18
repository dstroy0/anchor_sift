# NOTES

Written 2026-09-16 by the tree-wide objectives pass. Read this before working in anchor_sift. Paths
are relative to the repository root unless stated otherwise.

anchor_sift has more to change than any other public repository in this tree: it is the only one
whose tools directory is renamed, the only one carrying a committed copy of another repository's
content, and the only one whose prose gates actually run today.

## 1. Where the tools are, and where they go

Tools live under `maint/`, not `tools/`. `repotools.toml:27` states `tools = "maint"`, and the
comment at lines 19-20 calls it "the one line that differs from the template". Thirteen
directories plus a README:

| directory          | what is in it                                                                                                           |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| `maint/analysis/`  | `sound/`, `survey/`, its own README                                                                                     |
| `maint/catalog/`   | `catalog.py`, `catalog.tsv`, `catalog_verify.py`                                                                        |
| `maint/citations/` | `citations.py`, `corpus_crossref.py`, `prior_works.py`                                                                  |
| `maint/corpus/`    | `corpus_manifest.py`, `speech_gate.py`, `speech_order.py`, `verify_private_sync.py`                                     |
| `maint/data/`      | `fetch/`, `salishan/`, its own README                                                                                   |
| `maint/deps/`      | `get_deps.py`, `vendor_test_vectors.py`                                                                                 |
| `maint/engine/`    | `build_gpu_arm.sh`, `check_exact_limbs.py`, `digest_exact_emit.py`, `verify_arm_asm.sh`, `verify_gpu_arch.sh`           |
| `maint/prose/`     | `ai_detect.py`, `english_gate.py`, `docs_check.py` and ten more, plus `fixtures/`                                       |
| `maint/repotools/` | the fetched toolkit tree                                                                                                |
| `maint/source/`    | `codemask.py`, `dedup.py`, `readclean.py`, `readclean_mmgr.py`, `src2png.py`, `strip_comments.py`                       |
| `maint/texbuild/`  | `build_theory.sh`, `dotmap_svg.py`, `ledger_toc.py`, `markdown_to_latex.py`, `math_hazards.py`, `submission_package.py` |
| `maint/tree/`      | `write_survey.py`                                                                                                       |

Objective 5 renames `maint/` to `tools/`. That is a multi-file commit, not a directory move, and
every one of these has to land in it:

- `repotools.toml:27` becomes `tools = "tools"`, and the lines 19-20 comment explaining the
  exception is deleted.
- `repotools.toml:43-44` (`[prose] roots`) and `repotools.toml:62-63`
  (`[hooks.docs_check] roots`) both name `"maint"`. Both must change in the same commit. If one is
  missed, the prose walk reads a root that **emptied** and
  `docs_check.py`'s own guard catches the second case and not the first. Compare the file count at
  the foot of the run before and after — that count is the only thing distinguishing the two.
- `repotools.toml:61` (`[hooks.docs_check] tool`) is `"maint/prose/docs_check.py"` and becomes
  `tools/prose/docs_check.py`.
- `repotools.lock` records 20 entries whose `installed_path` all begin `maint/repotools/`. Every
  one is rewritten.
- `.githooks/pre-commit:22` and `:35` both name `maint/prose/docs_check.py` by path.
- **`README.md:59` says the opposite of the objective**: "There is no `tools/`, deliberately: a
  directory meaning 'a script' takes everything, and this repository had the engine's own measure
  library, a research subject's whole pipeline and the prose checker filed together under that
  name." Objective 5 overrides it. Rewrite that paragraph in the same commit or the README documents
  a layout the repository no longer has. The concern behind it is real and is answered by the
  thirteen named subdirectories, not by the top-level name.

Two stale paths to fix while touching this, both wrong **today** and both pointing at the same
file:

- `.gitignore:13` says `python tools/maintain/get_deps.py`. No such path has ever existed.
- The trailing comment in `src/engine/c/CMakeLists.txt` says `python maint/get_deps.py`, in the
  paragraph telling a user how to wire up the four older bench drivers.

The file is at `maint/deps/get_deps.py` now and `tools/deps/get_deps.py` after the move.

`evidence/` (`proofs/posits`, `sims/matlab`, `sims/r`) and `examples/` are **not** tool
directories. `evidence/` holds results and `examples/` is user-facing. Objective 5 covers `maint/`
only. Do not sweep them in.

## 2. The dependency standard, and what anchor_sift must change

The decided standard is **submodule-first**. A directory taken from another repository is taken as
a git submodule, narrowed with `--no-cone` sparse patterns recorded in `.gitmodules` as
`sparsePaths`, and the bootstrap asserts the post-narrow shape.

anchor_sift has no `.gitmodules` at all today. It has three dependency edges, handled three
different ways.

### `theory_bucket/` is the only genuine committed copy in the tree

`git ls-files theory_bucket` returns 81 files, matching the upstream repository file for file, at
zero drift. This is the edge the whole objective is about. It becomes a submodule mounted at
`theory/`, pinned to theory_bucket's `7fdd2d77458ac0e5dcde7fbbd17753f63a7d11f1`, narrowed per book
so this repository takes only the books it asks for and not the whole bucket.

Retire with it: `.githooks/post-merge`, which exists to run `git subtree pull --prefix=theory_bucket`
and whose entire header documents the subtree direction.

Three measured hazards, all of which fail silently at exit 0:

- Without `MSYS2_ARG_CONV_EXCL='*'`, git on this machine records `--no-cone` patterns as
  `C:/Program Files/Git/Salishan/` and the mount comes out **completely empty**, exit 0, no error.
- A stock `git clone --recurse-submodules` applies no narrowing and gets the **superset** — all
  eight entries, with theory_bucket's `README.md` landing at `theory/README.md`.
- Cone mode keeps root files. `--cone` is not a substitute.

After applying sparse-checkout, count the entries under the mount, compare against the
`sparsePaths` count, and refuse naming both numbers on any mismatch.

### `deps/mmgr` is working-tree-only, and stays a script edge

`.gitignore:16` is `deps/` and `git ls-files deps` returns zero paths. Nothing here is committed.
`maint/deps/get_deps.py` populates it.

**Keep `get_deps.py` for exactly the two closed edges.** Lines 56-57 read the addresses from
`ANCHOR_SIFT_PRIVATE_REPO` and `ANCHOR_SIFT_CITATIONS_REPO` precisely so the private repository
names are absent from this public tree. A submodule with a literal URL would write those names into
a public `.gitmodules`, which is strictly more disclosure than today. This is the one documented
exception in the standard, and it is documented.

`deps/mmgr/.claude/` belongs to that vendored checkout. It is not this repository's and nothing in
this objectives pass touches it.

### repotools

`repotools.toml:65-85` fetches `lib/repotools`, `media_tools/source_render`, `docs/docs_maint` and
`repo/repo_maint` into `maint/repotools`, recorded in `repotools.lock` (20 entries,
`boot.py` at digest `348a8353fbfc289b`).

The measured reason the mount wins, in this repository specifically: `boot.toolkit_root()` resolves
by `TOOLKIT_MARKERS = ("lib/repotools", "repo/repo_template", "code")`. All three are present in
repo_tools. `maint/repotools` has `lib/` and `repo/`, but `repo/repo_template` and `code/` are
**absent**. The fetched copy provably cannot resolve as a toolkit root, and `check()` degrades
silently at `fetch.py` (`if not toolkit: continue`). A mount resolves; a copy cannot.

Under the standard the fetch mechanism, the lock and the stamp subsystem retire. The toolkit edge
carries the same documented exception as the two closed edges, because repo_tools is private.
Until that lands, leave `maint/repotools/` as it stands and do not edit a fetched file in place.

`.gitattributes` is **absent** from this repository. Add one before anything here is mounted
elsewhere or cloned on a machine with a different `core.autocrlf`. Under the fetch path `digest()`
normalized CRLF explicitly; a submodule has no such layer.

## 3. Backgrounded agents may commit

Backgrounded agents are permitted to commit in this repository. The message is **terse and names
category, subject and type only** — for example `docs build bugfix`. No body, no attribution
trailer, no prose.

anchor_sift is the only repository of the six where `core.hooksPath` is set
(`.githooks`). A commit here actually runs its gates. That is the model; do not regress it.

Stage explicitly with `git add <named paths>`. Do not use `git commit -a` or bare `git add .`.

## 4. The build script this repository needs

Objectives 8 and 18: one script that builds all of `src/` and `examples/` and walks a user through
it, with a worked invocation in the README.

What anchor_sift has today, at `README.md:100-102`:

```
cmake -S src/engine/c -B build/engine_c -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/engine_c
./build/engine_c/bench_lattice
```

That block is real — `bench_lattice` has `RUNTIME_OUTPUT_DIRECTORY` set to `CMAKE_BINARY_DIR`. But it covers **one of five** directories under `src/engine/`: `c`, `gpu`,
`matlab`, `python`, `r`. The README implies the C bench is the build; it is one fifth of it.

The gaps:

- `src/engine/python/` is described at `README.md:111` as "the reference every figure came out of"
  and has **no declared environment**. No `pyproject.toml`, `requirements.txt`, `setup.py` or
  environment file is tracked anywhere in this repository.
- `maint/engine/build_gpu_arm.sh` builds the GPU arm and the README never mentions it.
- `examples/` holds 122 tracked `.py` scripts across ten subject directories
  (`00_blob_viz_tools`, `0_experimental`, `any_corpus`, `art`, `cell_tracking`, `crystallography`,
  `language`, `proteins`, `sound`, `source`) with their own `examples/README.md`, and nothing
  builds, installs or smoke-runs any of them.

What is needed: a declared Python environment, then one top-level script that configures the C
engine, checks the Python imports resolve, and runs one example per subject as a smoke test.

## 5. Where the skills live

`D:/git_project/repos/owned/private/repo_tools/skills`

Five skills are there now: `code-python`, `code-shell`, `code-verify`, `docs-readme`,
`repotools-workflow`. None is installed anywhere a harness discovers skills, and four of five
declare a frontmatter `name` differing from their directory name. Cross-references between them
cite identifiers nobody can type. Objective 6 rebuckets and rewrites them; an install mechanism
lands first.

This repository is the largest Python surface of the six. `code-python` binds most of the work
here. Note its measured defect before relying on it: its section 0 rail orders grading "all seven
sections" over a file that carries eight. An agent following it literally never reaches section
8, which holds the only testability content in the set — run it from a working directory that is
not its own, run it over a tree that is not the one it was written against, prove the refusal and
not only the pass. Those are exactly the rules that catch the defects this tree has hit.

`maint/source/` and `maint/prose/` carry tools that already exist upstream or are candidates to be
promoted there. `math_hazards.py` and `src2png.py` are fetched from the toolkit **and** exist
locally under `maint/texbuild/` and `maint/source/`; resolve the duplication when the tools move.

## 6. The prose gates are becoming pre-commit gates

Objective 12 adds an AI-word detector and objective 13 adds a British-English ban, and both become
pre-commit gates in every repository. British spellings are banned in comments, docstrings and
description blocks unless the subject itself is British.

**anchor_sift is where these are built.** The reference implementations are already here:

`maint/prose/ai_detect.py`, `maint/prose/english_gate.py`, `maint/prose/docs_check.py`,
`maint/prose/claudese_distance.py`, `maint/prose/prose_distance.py`, `maint/prose/prose_era.py`,
`maint/prose/ban_evidence.py`, `maint/prose/gate_sample.py`, `maint/prose/submission_check.py`,
`maint/prose/api_gate.py`, `maint/prose/oracle_agreement.py`, and `maint/prose/fixtures/`.

`repotools.toml:52-55` names `gates = ["docs_check", "fetch_check"]`, `[hooks.docs_check] tool`
points at the local copy at line 61, and `core.hooksPath` is set. This is the only repository of
the six where the gate actually runs.

Three things follow:

- Objective 12's chunked, replayed AI-word tool and objective 13's British-English checker are
  written here first and then promoted into repo_tools. The other five repositories fetch rather
  than reimplement them.
- `fetch_check` goes away with the lock. Remove it from `gates` in the same commit that retires the
  fetch mechanism, not before — a gate named here that cannot be found stops the commit, and
  `repotools.toml:53-54` says so explicitly.
- The root lists at lines 43-44 and 62-63 change twice: once for `maint` becoming `tools`, once for
  `theory_bucket` becoming `theory` and `workbook` appearing. Do not let those two commits collide.

## 7. The theory layout

Every repository, public and private, gets exactly two directories for written work:

- `workbook/` — locally authored, top level, a sibling of `src/`, `test/`, `examples/` and
  `tools/`. The book about **this** repository.
- `theory/` — wholly a git dependency of the `theory_bucket` repository. Nothing is authored here.
  Everything inside arrived from the theory_bucket remote, and the whole directory can be deleted
  and re-fetched without losing work. Each upstream book is pulled individually.

All theory, from every public and private repository, is authored upstream in theory_bucket.

**anchor_sift violates this in both directions today, and both are named in the decision:**

| today                                                                                                            | becomes                                                  |
| ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| `theory/workbook/` — locally authored: `main.tex`, `preamble.tex`, `chapters/`, `frontmatter/`, `dedication.tex` | `workbook/` at the repository root                       |
| `theory_bucket/` — 81 committed files, seven upstream books                                                      | `theory/`, populated by the submodule, never by a commit |

The separation is the point: after the move `theory/` has exactly one owner and is safe to
overwrite on fetch, and nothing this repository authors may ever sit inside it.

Everything that has to move with it:

- `repotools.toml:24` reads `docs = ["docs", "theory", "theory_bucket"]` and its comment at lines
  22-23 describes the current arrangement. Both change.
- `[prose] roots` (43-44) and `[hooks.docs_check] roots` (62-63) both list `"theory"` and
  `"theory_bucket"`. Both become `"theory"` and `"workbook"`.
- `theory/workbook/` currently carries its own build output beside the source: `main.aux`,
  `main.log`, `main.pdf`, `main.synctex.gz`, `main.toc`. The move is the moment to push that under
  `build/`.
- **theory_bucket must get its own prose gate before the mount lands.** It has no `repotools.toml`
  and no `docs_check` gate today, and this repository's two root lists are the only reason those 81
  files are checked anywhere. `docs_check.py`'s own comment block calls theory_bucket "the third
  instance" of exactly this failure.
- **Decide the generator question before the mount, not after.** Two tools here write chapters into
  what becomes `theory/Salishan/chapters/`:
  `maint/data/salishan/hand_extraction/pure_corpus_index.py` at line 48
  (`INDEX = os.path.join(ROOT, "theory_bucket", "Salishan", "chapters", ...)`) and
  `maint/data/salishan/corpus_derivation.py` at lines 77-79 (`CHAPTERS`, `TARGET` and `FIGURE`, the
  last being `corpus-derivation.pdf`, a tracked binary among theory_bucket's 81 files). Under the mount these become generators writing into
  a dependency, and under the refusal rule they turn the next bootstrap into a refusal. Either the
  generator writes upstream and the chapter returns through the dep, or generated chapters land
  outside the mount and are `\input`. This is the one place the move makes a workflow worse and no
  mechanism resolves it.
- **The reproduction-path convention.** `preamble.tex:10` in the workbook and in every book under
  `theory_bucket/` names `maint/texbuild/build_theory.sh`. A bare repo-relative path means the
  consuming repository — that is the convention already in the books. But this is anchor_sift's
  path, and it becomes a lie the instant a second repository mounts the same book. Qualify it as
  `anchor_sift/tools/texbuild/build_theory.sh` wherever the book is not exclusively this tree's.
  The convention itself survives the mount unchanged, because the book sits at
  `anchor_sift/theory/Salishan/` and a repo-root-relative path is exactly what a reader types.
- **Objectives 19 and 20 are affected and have to be read through this.** They ask for
  `theory/cell_tracking` and a `theory/game` here. Under the decided layout nothing is authored in
  `theory/`. Both books are authored upstream in theory_bucket and arrive through the mount.
  theory_bucket already carries an untracked `cell_tracking/` with `chapters/`, `frontmatter/` and
  `preamble.tex` but no `main.tex`; that is where objective 19's book goes. The datasets objective
  19 pulls are a separate matter — they land in `repos/external/datasets/`, not in a book and not in
  the mount.
- This edge goes **last** in the dependency work, despite being the easiest. All 81 files are at
  zero drift right now, which makes it the only edge that can wait safely. MMgr's two histories are
  step 0, theory_bucket's two untracked items are step 1.
