# Splitting the repository: `internal` for the advantage, `main` for the precision work

Written 2026-09-11. **Every git command below is for Douglas to run.** Nothing here has been
executed. Version control is his and the one time that rule was broken it was broken by branching
without being asked.

---

## 1. The trap, which decides the whole shape

**A branch does not remove history.** If the advantage work is already committed on `main`, then

    git branch internal

leaves every one of those commits on `main` as well. Both branches share the same ancestry. Anyone
who clones `main` gets the advantage work out of the history whether or not a single advantage file
is present in the working tree, and `git log -p` reads it back in full.

So the split cannot be "branch off the internal work". It has to be **`main` starting over with no
shared history**, while `internal` keeps everything.

    internal    the current history, untouched, everything in it
    main        a new ROOT commit containing only the external set, no ancestor in common

That is an orphan branch. It is not a rewrite: nothing is deleted, nothing is rebased, and `internal`
still holds every commit it holds now.

## 2. The external set cannot build or verify as it stands

Two dependencies reach out of the external set into held files. Both have to be resolved first or
`main` ships hollow, which is the thing the gatekeeping test forbids.

**`bench_ntt_cuda.cu` must come along.** `gpu_multiply.py` runs `build/bench_ntt_cuda.exe` and says
`build it first: powershell src/scripts/build_ntt.ps1`, which compiles `src/bench/bench_ntt_cuda.cu`.
Searched for the advantage domain, that kernel returns nothing, so it is external and it has to be,
or the device half of the engine does not exist on `main`.

**`natural_constants.py` has to be split.** `digit_engine.py` imports it, and so does `host_bench.py`.
What they use is entirely general: `pi_machin`, `pi_euler`, `PI_PREFIX`, `golden_angle`,
`harmonic_unit`, `shown`. Those are the independent series the engine is GRADED AGAINST - without
them `digit_engine.py --check` cannot run, and an external repository whose own verification cannot
run is worth less than nothing.

The SHA-256 content in that file is two functions, `round_constants()` and `starting_words()`, which
recompute the published tables from cube and square roots of primes. They are the only part that
names the domain.

    external    the constants and the independent series, as natural_constants.py
    internal    the two SHA table functions, moved to a separate file

This is a real piece of work and it is a prerequisite, not a detail.

## 3. The file list for `main`

    examples/proofing/series.py                 the recurrences, multiply passed in
    examples/proofing/digit_engine.py           host engine
    examples/proofing/device_engine.py          device engine
    examples/proofing/gpu_multiply.py           the NTT multiply
    examples/proofing/natural_constants.py      AFTER the split above
    examples/proofing/twiddle_proof.py          Proth certificates, proved twiddle order
    examples/proofing/twiddle_placement.py
    examples/proofing/four_step.py
    examples/proofing/proth_reach.py
    examples/proofing/digit_reach.py
    examples/proofing/host_bench.py
    examples/proofing/relation_search.py        integer relation detection
    examples/proofing/bbp_search.py
    examples/proofing/bbp_sweep.py
    examples/proofing/bbp_scaling.py            the precision^2.64 result
    src/bench/bench_ntt_cuda.cu                 the transform kernel
    src/scripts/build_ntt.ps1                   how to build it
    docs/twiddle-proof.md
    theory/theory/precision/                           main.tex, titlepage, chapter_twiddle_proof
    theory/preamble.tex, theory/macros.tex      layout the book needs
    LICENSE
    README.md                                   A NEW ONE. The current README describes the viewers.

Explicitly NOT on `main`: `exact_harmonics.py`, `precision_floor.py`, `precision_plot.py`. All three
derive anisotropic properties through Legendre columns, and anisotropy is internal.

## 4. The commands

Run from the repository root, one at a time, reading the output of each.

    # Name the current work internal. Renames the branch; touches no commit.
    git branch -m main internal

    # Start main over with no ancestor. The working tree is left alone.
    git checkout --orphan main

    # Nothing is staged yet: unstage everything the orphan checkout carried over.
    git rm -r --cached . 

    # Stage only the external set.
    git add examples/proofing/series.py examples/proofing/digit_engine.py \
            examples/proofing/device_engine.py examples/proofing/gpu_multiply.py \
            examples/proofing/natural_constants.py examples/proofing/twiddle_proof.py \
            examples/proofing/twiddle_placement.py examples/proofing/four_step.py \
            examples/proofing/proth_reach.py examples/proofing/digit_reach.py \
            examples/proofing/host_bench.py examples/proofing/relation_search.py \
            examples/proofing/bbp_search.py examples/proofing/bbp_sweep.py \
            examples/proofing/bbp_scaling.py \
            src/bench/bench_ntt_cuda.cu src/scripts/build_ntt.ps1 \
            docs/twiddle-proof.md theory/theory/precision theory/preamble.tex theory/macros.tex \
            LICENSE README.md .gitignore

    # Check what is about to be committed BEFORE committing it.
    git status --short

    git commit -m "Arbitrary-precision arithmetic, certified NTT moduli, integer relation detection"

## 5. Two things that can still leak after this

**An untracked file is one `git add .` away from tracked.** On `main` every internal file is still
sitting in the working tree, untracked. A `.gitignore` on `main` listing the internal paths is what
stops a future `git add .` sweeping them into a public branch. Write it before the first commit, not
after.

**`git push --all` pushes `internal` too.** If both branches share a remote, one careless push
publishes everything. Either `internal` never goes to that remote, or it goes to a separate private
one. Pushing `main` by name every time, never `--all` and never `--mirror`, is the habit that makes
the mistake hard.

## 6. What this does not do

It does not remove the advantage work from anything already pushed. If `main` has ever been pushed
to a remote with the advantage work in it, that history exists wherever it was fetched, and a new
orphan `main` force-pushed over it does not recall the copies. That question is about what has
already left this machine and no local command answers it.
