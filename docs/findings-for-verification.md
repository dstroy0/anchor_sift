# Engine session findings, for verification

**Purpose:** Hand the theorist every claim this session produced, each with where it is recorded and the exact command or argument that settles it, so none of it has to be taken on my word.
**Scope:** `src/engine/c/`, `test/engine/`, `maint/engine/`, `docs/steering.md`, `theory/workbook/chapters/chapter_anchor_sift_workbook.tex`, and the engine workbook chapter staged for upstream.

Every claim below is in one of three states. **Holds** means checked and standing. **Retracted** means it was published here and is now withdrawn, with the reason. **Open** means it is not settled and is not to be quoted as though it were.

Builds referenced are MSVC 19.44 x64 Release and MinGW gcc, both exercised. Run everything from the worktree root.

    maint/engine/build_engine.ps1     # Windows, imports MSVC, compiles the device rasterizer
    maint/engine/build_engine.sh      # POSIX or Git Bash, pins gcc or clang where MSVC has no environment

## Holds

### F1. The engine is one translation unit and one header

`anchor_sift.c` and `anchor_sift.h` carry the search, the steering and the scan. `anchor_steer.{c,h}` and `anchor_steer_arm.{c,h}` are gone, absorbed. The `anchor_steer` and `anchor_steer_arms` CMake targets are gone; everything links `anchor_sift_kernel`.

**Check:** `ls src/engine/c/portable/` shows eight files and no `anchor_steer*`. `grep -rn "anchor_steer\.h\|anchor_steer_arm\.h" src/ test/ docs/` returns nothing.

### F2. The vectorized scan is flag confined to its own source

`/arch:AVX2` and `-mavx2` are set with `set_source_files_properties` on `vectorized_win/anchor_steer_avx2.c`, not on the target. A target level flag would let the compiler emit AVX2 into the portable path, which is an illegal instruction on a machine without it rather than a slower answer.

**Check:** `grep -n "set_source_files_properties" src/engine/c/CMakeLists.txt`.

### F3. The vectorized scan actually runs, and this is asserted rather than assumed

A correctness suite cannot detect an unused implementation: an engine compiled, graded and never called returns the reference engine's answer, so every differential passes. That defect was live here, AVX2 built and benched while the planner ran its own scalar loop. Two counters make the wiring assertable and `test_steer` requires a 100 percent share.

**Check:** `test_steer` prints `THE ARM IS WIRED, not merely compiled` with `avx2 189 189 100%`. `bench_steer_arms` reports 39.18 times portable.

### F4. Steering measured across five fields, not one

Reads per alignment, unsteered to best steered: uniform 1.003 to 1.003, synthetic skewed 1.562 to 1.001, skewed 1.877 to 1.067, period 16 1.187 to an exact 1.000 with one probe where the unsteered route places four, natural AGPL English text 1.072 to an exact 1.000.

**Corrected 2026-09-16 after the theorist ran it.** An earlier form of this entry gave the license text as 1.072 to 1.066 and called it the weakest field. 1.066 is the recursive reorder column; the field's result is its best route and that is 1.000 on coarms. **Uniform is the weakest field** and it is weak for a reason worth stating: a uniform field has no rarity for the steering to spend, so no route moves it and 1.003 to 1.003 is the honest worst case.

Two things one field could not show. Steering pays nothing on a uniform field, where no symbol is rarer than another. And the mechanisms separate: on the skewed field the recursive reorder moves 1.877 to 1.875 while spawning coarms moves it to 1.067, so the spawning pays and the ordering does not.

**Check:** run `test_steer`, read the route table per field.

### F5. The read floor

An engine deciding each alignment using only reads taken at that alignment performs at least one read per alignment. An alignment decided on zero reads is decided by a function whose domain is the empty tuple, so its range holds one value and it answers identically whatever the corpus holds there. An adversary edits the corpus at that alignment, flips whether it is an occurrence, and the engine observes nothing different, so one of the two answers is wrong.

It binds this class only. A skipping search decides ranges from one read and never visits most alignments, so its reads per alignment are taken over a sparse subset of the alignment set. Same name, different denominator.

**Check:** `test_steer` asserts total reads at or above the alignment count on every route and every field, and asserts the empty probe set takes exactly zero probe reads and exactly one compare per alignment.

**Known imprecision, corrected:** see R5. The floor is about bytes read at an alignment. The test charges one byte per compare, which is the bound's accounting and not a cost, and the empty probe set attains the floor only in those units.

### F6. The trichotomy

A descent stops, recurses, or refuses. It stops when the destroy test fires, recurses when a level prunes, and refuses when the question is malformed. There is no branch in which it revisits a state it already held.

**Check:** `test_adversarial` case 12. Seven malformed questions refused, each against a sentinel filled buffer so a refusal that returned zero after writing would be caught. Placed offsets required pairwise distinct, since placing an already placed probe leaves the survivor set unchanged and would be a revisit.

### F7. The descent is greedy submodular coverage maximization

A probe rejects a definite set of alignments; a probe set rejects their union; `f(P)` counting that union is monotone because adding a probe un-rejects nothing, and submodular because an alignment already rejected contributes nothing when rejected again. Neither property assumes anything about the corpus. Choosing the candidate leaving fewest survivors is choosing the largest marginal gain, because the alive count is fixed at the level. Nemhauser, Wolsey and Fisher 1978 then gives at least `1 - 1/e` of the best probe set of the same size.

**Confirmed by the theorist.** Two scope limits they and I agree on: the bound is on alignments rejected and not on reads, and it assumes the argmax is exact, which holds at `sample_stride` one and not above it, where greedy is running on an estimate.

### F8. The sweep enumerates the whole legal probe set

`anchor_steer_probe_fits` is the boundary function, domain probes by needle length, range `{0,1}`. `anchor_steer_sweep_probes` enumerates origins to `needle_len`, lengths to `max_length` and steps to `needle_len`, putting every candidate to the boundary function before scoring it. Every bound is an argument or a compile time constant and none is read from the corpus. That is what makes the argmax exact rather than sampled, which is what F7 needs.

### F9. The volume renderer, with its bijection checked

`AnchorVolumeConfig` renders a block: four layouts by the raster's five channels, two reduce rules and gain, named by reference to the same enums. Every layout is a bijection on the cell index computed in integers. `bench_raster` maps every alignment through every layout at every channel and counts collisions.

**Check:** `bench_raster` prints 20 volume rows, every one zero collisions, alongside 20 sheet rows graded host against device byte for byte.

**Honest gap:** there is no device volume kernel. `anchor_volume_device_available` returns 0 on every build and the entry is named `_host`. It does not fall back silently.

### F10. Two build defects that made measurements impossible

`bench_dispatch` and `bench_scaling_cycles` gated their cycle counter on `__x86_64__`, a GCC and Clang predefine MSVC never sets, so both fell through to a POSIX `clock_gettime` MSVC does not ship and failed to compile. Neither had ever run on Windows. Fixed by carrying the MSVC spelling.

`build_engine.sh` failed in Git Bash with `target anchor_sift_kernel did not build`, because CMake prefers `cl.exe` on Windows even where gcc is on PATH and Ninja does not import the MSVC environment, so every compile died on `Cannot open include file: 'stddef.h'`. A check that merely found gcc passed, because finding a compiler is not the same as CMake choosing it. It pins the compiler now and names why.

`build_engine.ps1` announced the MSVC environment and the device arm while a stale CMake cache from a Git Bash run silently produced gcc with no CUDA. The only symptom was a render column reading `host only` inside a grader printing zero failures. It now passes the decisive settings on every configure, wipes a cache naming a different toolchain, and re-reads the cache to confirm a CUDA compiler before building.

## Retracted

### R1. The dispatch rule's cost

Recorded as "around one percent of the cycles the worst rule gives up". Measured, with the gate in F10 fixed so the driver runs at all, it is **0.035** on x64 MSVC 19.44 at Release, 39 of 42 rows, 9131790 cycles. The one percent corresponds to no run recoverable from this tree.

**And 0.035 does not reproduce either.** The theorist ran the same bench under gcc and got 41 of 42 at 86511 cycles, share 0.000. A hundredfold gap in cycles, not rounding, and both are real runs. The figure belongs to the toolchain that produced it and must be quoted with one. A rule scored by row count is fragile precisely where two engines sit within noise of each other, which is the argument the bench's own closing note makes for scoring by cycles given up.

**The needle length term is dead weight on this data, which R1 never mentioned.** Flatness alone ties the kernel exactly, same rows and same cycles on the theorist's run, so the length term changes no answer across 42 rows. "Flatness then length, as documented" scores strictly worse than the flatness it contains, and the shipped rule of length alone is worse than both. So the document is beaten by the kernel it documents and the kernel is behaviorally the simpler rule. The sweep's own text already supports it: a structured corpus takes the free order engine at every length, and the ceiling of 16 it used to carry survives at no value. A tunable with no reader is an integration point, never deleted and never called unimplemented, so it is named and kept until a row is found where it pays.

### R2. The steering figure from one corpus

`docs/steering.md` led with 1.072 falling to 1.066 on a single 24 KB file. That file is the **weakest** field in the family, see F4. Quoting it alone understated the mechanism on three of the other four fields and concealed the spawn against reorder distinction.

### R3. Submodularity discharging the destroy premise

I claimed diminishing returns makes the non-increasing enumeration premise unnecessary. **Refuted by the theorist with a counterexample.** Alignments `{1,2,3}`. Let `R_p` be empty with candidate set `{p}` at level 0: best marginal gain zero, destroy fires. Let the candidate set at level 1 be `{p,q}` with `R_q = {1,2,3}`: nothing was placed, the population is unchanged, `q` has gain three. Stopping rejects none, continuing rejects all, and `f` is monotone and submodular throughout.

Submodularity bounds the gain of a **fixed** candidate as the placed set grows. It says nothing about a candidate absent from the earlier set, because there is no earlier gain to bound it by. The enumeration premise is load bearing and stays stated.

### R4. Three classifications of the engine, two of them mine and wrong

**First:** the engine is a total language, every loop bounded before the run, so the halting question does not arise. Wrong. That analyzed one **invocation** and concluded about the **system**, and a system halting on every input decides its own halting, so the claim needed the outer loop and never looked at it. The outer loop is self examination and nothing bounds it. The methodological error is the durable finding and survives whatever the answer is.

**Second:** the engine is Turing complete. Wrong, and further from the truth than the first. Failing to halt is not Turing completeness; a process can fail to halt by cycling among three states. Turing completeness needs storage that grows during execution.

**Third:** the engine is a linear bounded automaton, tape linear in input. Wrong, and Douglas broke it: the corpus is not the input, it is a window. **The universe is the tape and the exam set is the surviving set.** An LBA's bound is linear in an input this construction does not have, because the engine chooses what it reads next.

### R5. The read floor's attainment, and a row in the wrong units

I wrote that the empty probe set attains the floor at exactly `N`. A full compare is not one read; it reads up to `m` bytes and exactly one only when the first byte differs. The test charges one byte per compare, which is the bound's accounting. So the empty probe set attains the floor **in floor units**, and in real bytes it is the most expensive route there is, since every alignment takes a full compare.

That row was also briefly printed inside the route table, whose column counts probe reads only. Read down one column it invited the conclusion that not steering matches the best steering. It is reported outside the table now.

### R6. The byte constraint was this engine's, not the construction's

I presented the equality oracle as lifting a constraint on the engine. It lifted one on the C entries only, and the framing implied more than that.

The python cascade has never needed bytes. `survivors` reads `places.get(needle[offset], ())` and `positions_by_symbol` builds `places` with `setdefault(value, set())` over any iterable, so a symbol there is a dict key and the requirement is equality and hashability (`src/engine/python/sift/anchors.py:104`, `src/engine/python/sift/anchors.py:110-115`). `examples/crystallography/5_sift/lattice_breaks_the_product_rule.py` runs the cascade over crystals with element strings as symbols, importing `representation.exact` and `representation.structure.crystal` and no shared library at all. Checked, not taken: the crystallography session reported it and both claims verify.

So the C entries were narrower than the proof they implement AND narrower than the python engine they are graded against, and the byte framing in the C headers is what a reader would have concluded the construction required.

**The two are still not equivalent, and the gap now runs the other way.** A dict key must be hashable. The oracle asks only whether two positions are equal. A value that cannot be hashed, or whose equality is real while a hash of it would be a lie, can be searched by the C engine and cannot be searched by the python one. Anyone grading the two against each other needs to know which fields only one of them accepts, because the grading assumes they answer the same question over the same inputs.

### F11. The projection needs transitivity and the descent does not, which is a soundness precondition

Found by the crystallography session pointing at the protein subject, verified here.

A descent's oracle is asked only whether two positions agree. That is a pairwise necessary condition and it survives any predicate whatever, including one that is not transitive.

`anchor_field_project` groups positions into classes by comparing each against a representative, which assumes agreement partitions the field. Under a predicate that is not transitive the grouping depends on which representative a position meets first, two positions that do agree can land in different classes, same symbol stops implying same rank, and a rank probe stops being a necessary condition. It then rejects alignments holding true occurrences, silently, with nothing failing.

**The case that motivates having an oracle is the case that breaks it.** `examples/proteins/5_sift/protein_domain.py:66-74` matches a point within a tolerance of a displaced position, and its docstring states why exact equality is the wrong test on a continuous domain: coordinates are real, so two occurrences of one motif never land on identical voxel offsets. A tolerance relation is not transitive, since `a` within tolerance of `b` and `b` of `c` does not put `a` within tolerance of `c`. That predicate is sound in a descent and unsound in the projection.

Verifying transitivity costs a cube of the field, so this is a precondition and not a check. It is stated in the header at the declaration, loudly, because the failure mode is a wrong answer and not a refusal.

**Check:** read the warning on `anchor_field_project` in `src/engine/c/portable/anchor_sift.h`, and `examples/proteins/5_sift/protein_domain.py:66-74` for the predicate that breaks it.

### F12. A crystal derived field would be half selected by crystal system, and the selection tracks mineral family

Measured by the crystallography session over `build/cod` with `maint/analysis/survey/crystal_gate_census.py`, reported here because it is a trap for this engine's benches and not for theirs.

Of 7459 entries, 3708 are admitted to the exact reading (49.7 percent), 3747 are refused for a cell that is not right angled (50.2 percent), and 4 carry no cell. The refusal is nowhere near uniform: spinel 96.1 percent admitted, garnet 98.0, olivine 95.3, melilite 95.4, perovskite 91.0, against feldspar 2.3, apatite 2.4, amphibole 4.2, tourmaline 4.6, carbonate 5.2, clay 8.8, serpentine 10.0.

The gate selects by crystal system, and crystal system is confounded with mineral family. **Any field drawn from that cache is the cubic and orthorhombic half of it**, with the monoclinic and triclinic families all but absent, and a bench run over it would report a property of that half while naming the whole corpus.

Nothing in the engine touches it today. `bench_lattice` and `bench_coherence` build synthetic periods and are unaffected, and F4's natural field is the AGPL licence text. It is recorded because F4 establishes the habit of reaching for a natural field, and this is the natural field nearest to hand.

**Check:** `maint/analysis/survey/crystal_gate_census.py` over `build/cod`, in the crystallography worktree.

### R7. "Nothing is committed" was wrong

I told the crystallography session that nothing of the engine work was committed and that there was no branch to merge. The second half holds for this session's work. The first half does not.

`0474582 src anchor_sift rewrite`, authored 2026-09-16 08:47:49, is HEAD of `worktree-engine-steer-exact` and touches `src/engine/c/portable/anchor_sift.{c,h}`, three benches, `CMakeLists.txt` and `test/engine/test_arm_agreement.c`. Verified by `git log` and `git show` here after they reported it from their own worktree.

So the rewrite is in the tree and only the work on top of it is uncommitted. The distinction matters to whoever commits next, because a commit lands on a branch that has already moved rather than on a branch that has not.

### R8. The overflow merged by arrival order, and the header claimed it merged by rarity

Measured by the theorist on a 400 class field, corrected here.

The header stated that classes beyond 255 share rank 255 and that those are the commonest, since ranks run rarest first. The reasoning is sound. The code did not implement it. The overflow was assigned inside the discovery pass, before the rarity sort ran at all, so the merged set was chosen by **arrival order**.

Two fields with the same frequency multiset and opposite arrangements, 256 classes at nine occurrences and 144 at one: the merged sets had mean occupancies of 1.06 and 9.00. Same count merged either way, 400 minus 256 plus 1, so the mechanism is exactly the table filling. A histogram cannot tell those two fields apart, which puts this in the same class as every other arrangement-invisible-to-a-histogram defect in this workbook.

**The natural arrangement is the harmful one.** A class occurring once has one chance to arrive early; a class occurring nine times has nine. Rare classes therefore arrive late and the overflow ate exactly them, at mean occupancy 1.06. The rarest class is the best probe the steering has, so the degradation spent the thing the projection exists to find.

**Fixed by refusing.** A field holding more classes than a byte rank can name now returns 0 with `distinct` set to 0, rather than degrading silently. That also enforces the advice already given to three sessions whose fields are this shape: do not project, hand the oracle to a descent, which needs no ranks, no closure and no table. Tested: 400 distinct classes refused, `distinct` reporting 0.

The theorist's alternative fix, labelling with a separate `uint32_t` array of `length` entries so the component count runs unbounded and the clamp applies at relabel time, would make the original sentence true. It needs caller supplied scratch, because the kernel allocates nothing, and it is not taken here. Refusing is smaller and it is the honest answer for a byte ranked output.

**Also fixed:** `distinct` used to report 256 on a 400 class field, so a caller could not distinguish a field with exactly 256 classes from one that had overflowed and was running degraded. Both reported 256.

### F13. The projection's inequality is strict, and it is reachable

Measured by the theorist on the same 400 class field, 2448 positions, 256 ranks, needle length 4.

Across every needle position: 150 needles where the projected survivor count is strictly above the exact one, and **zero** where it falls below. Sample rows show exact 6 against projected 150.

So F7's inequality is the right assertion and my own test could not reach the strict case, because 6 classes against 256 ranks means no merge occurred and projected and exact were identical. An equality assertion would have passed that run unchanged, which is the thing that made the test weak evidence rather than wrong.

Unchanged under the transitive closure, for a stated reason: a different rank means no edge in the closure, so the predicate is false on that pair, so agreement still implies a shared rank. The closure only makes same-rank weaker, which widens the gap the inequality allows and cannot invert it.

## Open

### O1. What the engine actually is, given the universe is the tape

The crux is the coarm count. The finite automaton argument takes the state to be one survivor vector over a fixed alignment set, at most `2^|A|` states. If an engine spawns coarms that each carry their own survivor vector, the state is a tuple of vectors and its size grows with the number of arms. `ANCHOR_STEER_ANCHORS` pins that at four today, which makes the question moot for this tree.

Against a growing answer: a strictly growing placed set drawn from a finite probe family must terminate, so unbounded recursion needs each new arm to bring a fresh family rather than draw from one shared one. For a growing answer: the trichotomy says the engine does not cycle, so an unbounded run is a strictly deepening recursion, which is the shape that needs growing storage.

**This is not settled and is recorded as unverified in the workbook.** It should not be quoted in either direction.

### O2. The interface is what blocks the construction

The entries take `const uint8_t *corpus` with a `corpus_len`: a window nailed down. The engine cannot ask for more universe. The change is one interface, a reader the engine may call for more in place of a pointer and a length. Until that exists the construction is what the implementation admits and not what it is.

### O3. The alphabet size bench, which would produce a new number

I killed my own best candidate for a problem the engine uniquely solves. Main and Lorentz give `Omega(n log n)` for repetition detection over a general alphabet, which reads like a barrier the engine walks past. It is not: the bound is `Theta(n log sigma)` and the `n log n` form assumes `Omega(n)` distinct symbols. At `sigma = 256` the factor is 8 and it is linear, so on byte corpora the engine beats nothing asymptotically.

I then observed that the regime which would demonstrate the advantage and the regime we cannot test are the same regime. The theorist's answer is that this is escapable and it is the only item here that would produce a new number: you cannot test `sigma` unenumerable, but you **can** test `sigma` growing. Four byte symbols give `sigma = 2^32`, or exact rational symbols compared by equality. Measure the engine's state against a bad character table's as `sigma` climbs. The table grows linearly in `sigma` and the engine's state stays at `m` bits. A flat line against a rising one over three or four decades is the demonstration and it never needs the untestable limit. The claim to make is about the trend, which is measurable, and not the limit, which is not.

**Not built.**

### O4. The space lower bound, scope unverified

Online exact pattern matching carries an `Omega(m)` bits space lower bound, and the engine carries `m` bits. I have not verified the theorem's scope and it is deliberately absent from the workbook as a result. A space lower bound usually carries model conditions that decide whether that `m` is the same `m`. If it goes in, it goes in with the hypotheses quoted.

## What the theorist is asked to do

Transcribe the holds and the retractions into the workbooks in their own words, and verify rather than copy. The three I most want attacked are F5, because the domain and range argument is mine and short enough to be wrong quickly; F8, because F7's bound depends on the enumeration being complete and I have asserted completeness from reading the loops rather than from a test; and O1, which is open and which two competent arguments currently split.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
