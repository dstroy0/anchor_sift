# Engine session findings, for verification

**Purpose:** Hand the theorist every claim this session produced, each with where it is recorded and the exact command or argument that settles it. None of it has to be taken on my word.
**Scope:** `src/engine/c/`, `test/engine/`, `maint/engine/`, `docs/steering.md`, `theory/workbook/chapters/chapter_anchor_sift_workbook.tex`, and the engine workbook chapter staged for upstream.

Every claim below is in one of three states. **Holds** means checked and standing. **Retracted** means it was published here and is now withdrawn, with the reason. **Open** means it is not settled and is not to be quoted as though it were.

Builds referenced are MSVC 19.44 x64 Release and MinGW gcc, both exercised. Run everything from the worktree root.

    maint/engine/build_engine.ps1     # Windows, imports MSVC, compiles the device rasterizer
    maint/engine/build_engine.sh      # POSIX or Git Bash, pins gcc or clang where MSVC has no environment

## Holds

### F1. The engine is one translation unit and one header

`anchor_sift.c` and `anchor_sift.h` carry the search, the steering and the scan. `anchor_steer.{c,h}` and `anchor_steer_arm.{c,h}` are gone, absorbed. The `anchor_steer` and `anchor_steer_arms` CMake targets are gone; everything links `anchor_sift_kernel`.

**Check:** `ls src/engine/c/engine/` shows `anchor_sift.{c,h}` and `scan_avx2.c` and no `anchor_steer*`. `grep -rn "anchor_steer\.h\|anchor_steer_arm\.h" src/ test/ docs/` returns nothing.

### F2. The vectorized scan is flag confined to its own source

`/arch:AVX2` and `-mavx2` are set with `set_source_files_properties` on `vectorized_win/anchor_steer_avx2.c`, not on the target. A target level flag would let the compiler emit AVX2 into the portable path, which is an illegal instruction on a machine without it.

**Check:** `grep -n "set_source_files_properties" src/engine/c/CMakeLists.txt`.

### F3. The vectorized scan actually runs, and this is asserted rather than assumed

A correctness suite cannot detect an unused implementation: an engine compiled, graded and never called returns the reference engine's answer. Every differential passes. That defect was live here, AVX2 built and benched while the planner ran its own scalar loop. Two counters make the wiring assertable and `test_steer` requires a 100 percent share.

**Check:** `test_steer` prints `THE ARM IS WIRED, not merely compiled` with `avx2 189 189 100%`. `bench_steer_arms` reports 39.18 times portable.

### F4. Steering measured across five fields, not one

Reads per alignment, unsteered to best steered: uniform 1.003 to 1.003, synthetic skewed 1.562 to 1.001, skewed 1.877 to 1.067, period 16 1.187 to an exact 1.000 with one probe where the unsteered route places four, natural AGPL English text 1.072 to an exact 1.000.

**Corrected 2026-09-16 after the theorist ran it.** An earlier form of this entry gave the license text as 1.072 to 1.066 and called it the weakest field. 1.066 is the recursive reorder column; the field's result is its best route and that is 1.000 on coarms. **Uniform is the weakest field** and it is weak for a reason worth stating: a uniform field has no rarity for the steering to spend. No route moves it and 1.003 to 1.003 is the honest worst case.

Two things one field could not show. Steering pays nothing on a uniform field, where no symbol is rarer than another. And the mechanisms separate: on the skewed field the recursive reorder moves 1.877 to 1.875 while spawning coarms moves it to 1.067. The spawning pays and the ordering does not.

**Check:** run `test_steer`, read the route table per field.

### F5. The read floor

An engine deciding each alignment using only reads taken at that alignment performs at least one read per alignment. An alignment decided on zero reads is decided by a function whose domain is the empty tuple. Its range holds one value and it answers identically whatever the corpus holds there. An adversary edits the corpus at that alignment, flips whether it is an occurrence, and the engine observes nothing different. One of the two answers is wrong.

It binds this class only. A skipping search decides ranges from one read and never visits most alignments. Its reads per alignment are taken over a sparse subset of the alignment set. Same name, different denominator.

**Check:** `test_steer` asserts total reads at or above the alignment count on every route and every field, and asserts the empty probe set takes exactly zero probe reads and exactly one compare per alignment.

**Known imprecision, corrected:** see R5. The floor is about bytes read at an alignment. The test charges one byte per compare, the bound's accounting and not a cost, and the empty probe set attains the floor only in those units.

### F6. The trichotomy

A descent stops, recurses, or refuses. It stops when the destroy test fires, recurses when a level prunes, and refuses when the question is malformed. There is no branch in which it revisits a state it already held.

**Check:** `test_adversarial` case 12. Seven malformed questions refused, each against a sentinel filled buffer, a refusal that returned zero after writing would be caught. Placed offsets required pairwise distinct, since placing an already placed probe leaves the survivor set unchanged and would be a revisit.

### F7. The descent is greedy submodular coverage maximization

A probe rejects a definite set of alignments; a probe set rejects their union; `f(P)` counting that union is monotone because adding a probe un-rejects nothing, and submodular because an alignment already rejected contributes nothing when rejected again. Neither property assumes anything about the corpus. Choosing the candidate leaving fewest survivors is choosing the largest marginal gain, because the alive count is fixed at the level. Nemhauser, Wolsey and Fisher 1978 then gives at least `1 - 1/e` of the best probe set of the same size.

**Confirmed by the theorist.** Two scope limits they and I agree on: the bound is on alignments rejected and not on reads, and it assumes the argmax is exact, which holds at `sample_stride` one and not above it, where greedy is running on an estimate.

### F8. The sweep enumerates the whole legal probe set

`anchor_steer_probe_fits` is the boundary function, domain probes by needle length, range `{0,1}`. `anchor_steer_sweep_probes` enumerates origins to `needle_len`, lengths to `max_length` and steps to `needle_len`, putting every candidate to the boundary function before scoring it. Every bound is an argument or a compile time constant and none is read from the corpus. That is what makes the argmax exact.

### F9. The volume renderer, with its bijection checked

`AnchorVolumeConfig` renders a block: four layouts by the raster's five channels, two reduce rules and gain, named by reference to the same enums. Every layout is a bijection on the cell index computed in integers. `bench_raster` maps every alignment through every layout at every channel and counts collisions.

**Check:** `bench_raster` prints 20 volume rows, every one zero collisions and, where a device is present, graded host against device voxel for voxel, alongside 20 sheet rows graded host against device byte for byte.

**Gap closed, 2026-09-17:** this earlier read that there was no device volume kernel and that `anchor_volume_device_available` returned 0 on every build. That is no longer true. `src/engine/c/render/raster_cuda.cu` carries a device volume renderer (`render_volume`, `device_volume_cell`, and the `anchor_volume_device` entry), `anchor_volume_device_available` returns 1 where a device is present and the build carries the kernel and 0 otherwise, and `bench_raster` grades the volume host against device voxel for voxel. `anchor_volume_render_host` stays host only and named so, and nothing falls back silently.

### F10. Two build defects that made measurements impossible

`bench_dispatch` and `bench_scaling_cycles` gated their cycle counter on `__x86_64__`, a GCC and Clang predefine MSVC never sets. Both fell through to a POSIX `clock_gettime` MSVC does not ship and failed to compile. Neither had ever run on Windows. Fixed by carrying the MSVC definition.

`build_engine.sh` failed in Git Bash with `target anchor_sift_kernel did not build`, because CMake prefers `cl.exe` on Windows even where gcc is on PATH and Ninja does not import the MSVC environment. Every compile died on `Cannot open include file: 'stddef.h'`. A check that merely found gcc passed, because finding a compiler is not the same as CMake choosing it. It pins the compiler now and names why.

`build_engine.ps1` announced the MSVC environment and the device arm while a stale CMake cache from a Git Bash run silently produced gcc with no CUDA. The only symptom was a render column reading `host only` inside a grader printing zero failures. It now passes the decisive settings on every configure, wipes a cache naming a different toolchain, and re-reads the cache to confirm a CUDA compiler before building.

## Retracted

### R1. The dispatch rule's cost

Recorded as "around one percent of the cycles the worst rule gives up". Measured, with the gate in F10 fixed so the driver runs at all, it is **0.035** on x64 MSVC 19.44 at Release, 39 of 42 rows, 9131790 cycles. The one percent corresponds to no run recoverable from this tree.

**And 0.035 does not reproduce either.** The theorist ran the same bench under gcc and got 41 of 42 at 86511 cycles, share 0.000. A hundredfold gap in cycles, not rounding, and both are real runs. The figure belongs to the toolchain that produced it and must be quoted with one. A rule scored by row count is fragile precisely where two engines sit within noise of each other.

**The needle length term is dead weight on this data, which R1 never mentioned.** Flatness alone ties the kernel exactly, same rows and same cycles on the theorist's run. The length term changes no answer across 42 rows. "Flatness then length, as documented" scores strictly worse than the flatness it contains, and the shipped rule of length alone is worse than both. So the document is beaten by the kernel it documents and the kernel is behaviorally the simpler rule. The sweep's own text already supports it: a structured corpus takes the free order engine at every length, and the ceiling of 16 it used to carry survives at no value. A tunable with no reader is an integration point, never deleted and never called unimplemented. It is named and kept until a row is found where it pays.

### R2. The steering figure from one corpus

`docs/steering.md` led with 1.072 falling to 1.066 on a single 24 KB file. That file is the **weakest** field in the family, see F4. Quoting it alone understated the mechanism on three of the other four fields and concealed the spawn against reorder distinction.

### R3. Submodularity discharging the destroy premise

I claimed diminishing returns makes the non-increasing enumeration premise unnecessary. **Refuted by the theorist with a counterexample.** Alignments `{1,2,3}`. Let `R_p` be empty with candidate set `{p}` at level 0: best marginal gain zero, destroy fires. Let the candidate set at level 1 be `{p,q}` with `R_q = {1,2,3}`: nothing was placed, the population is unchanged, `q` has gain three. Stopping rejects none, continuing rejects all, and `f` is monotone and submodular throughout.

Submodularity bounds the gain of a **fixed** candidate as the placed set grows. It says nothing about a candidate absent from the earlier set, because there is no earlier gain to bound it by. The enumeration premise is load bearing and stays stated.

### R4. Three classifications of the engine, two of them mine and wrong

**First:** the engine is a total language, every loop bounded before the run. The halting question does not arise. Wrong. That analyzed one **invocation** and concluded about the **system**, and a system halting on every input decides its own halting. The claim needed the outer loop and never looked at it. The outer loop is self examination and nothing bounds it. The methodological error is the durable finding and survives whatever the answer is.

**Second:** the engine is Turing complete. Wrong, and further from the truth than the first. Failing to halt is not Turing completeness; a process can fail to halt by cycling among three states. Turing completeness needs storage that grows during execution.

**Third:** the engine is a linear bounded automaton, tape linear in input. Wrong, and Douglas broke it: the corpus is not the input, it is a window. **The universe is the tape and the exam set is the surviving set.** An LBA's bound is linear in an input this construction does not have, because the engine chooses what it reads next.

### R5. The read floor's attainment, and a row in the wrong units

I wrote that the empty probe set attains the floor at exactly `N`. A full compare is not one read; it reads up to `m` bytes and exactly one only when the first byte differs. The test charges one byte per compare, the empty probe set attains the floor **in floor units**, and in real bytes it is the most expensive route there is, since every alignment takes a full compare.

That row was also briefly printed inside the route table, whose column counts probe reads only. Read down one column it invited the conclusion that not steering matches the best steering. It is reported outside the table now.

### R6. The byte constraint was this engine's, not the construction's

I presented the equality oracle as lifting a constraint on the engine. It lifted one on the C entries only, and the framing implied more than that.

The python cascade has never needed bytes. `survivors` reads `places.get(needle[offset], ())` and `positions_by_symbol` builds `places` with `setdefault(value, set())` over any iterable. A symbol there is a dict key and the requirement is equality and hashability (`src/engine/python/sift/anchors.py:104`, `src/engine/python/sift/anchors.py:110-115`). `examples/crystallography/5_sift/lattice_breaks_the_product_rule.py` runs the cascade over crystals with element strings as symbols, importing `representation.exact` and `representation.structure.crystal` and no shared library at all. Checked, not taken: the crystallography session reported it and both claims verify.

So the C entries were narrower than the proof they implement AND narrower than the python engine they are graded against, and the byte framing in the C headers is what a reader would have concluded the construction required.

**The two are still not equivalent, and the gap now runs the other way.** A dict key must be hashable. The oracle asks only whether two positions are equal. A value that cannot be hashed, or whose equality is real while a hash of it would be a lie, can be searched by the C engine and cannot be searched by the python one. Anyone grading the two against each other needs to know which fields only one of them accepts, because the grading assumes they answer the same question over the same inputs.

### F11. The projection needs transitivity and the descent does not, which is a soundness precondition

Found by the crystallography session pointing at the protein subject, verified here.

A descent's oracle is asked only whether two positions agree. That is a pairwise necessary condition and it survives any predicate whatever, including one that is not transitive.

`anchor_field_project` groups positions into classes by comparing each against a representative, which assumes agreement partitions the field. Under a predicate that is not transitive the grouping depends on which representative a position meets first, two positions that do agree can land in different classes, same symbol stops implying same rank, and a rank probe stops being a necessary condition. It then rejects alignments holding true occurrences, silently, with nothing failing.

**The case that motivates having an oracle is the case that breaks it.** `examples/proteins/5_sift/protein_domain.py:66-74` matches a point within a tolerance of a displaced position, and its docstring states why exact equality is the wrong test on a continuous domain: coordinates are real. Two occurrences of one motif never land on identical voxel offsets. A tolerance relation is not transitive, since `a` within tolerance of `b` and `b` of `c` does not put `a` within tolerance of `c`. That predicate is sound in a descent and unsound in the projection.

Verifying transitivity costs a cube of the field. This is a precondition and not a check. It is stated in the header at the declaration, loudly, because the failure mode is a wrong answer and not a refusal.

**Check:** read the warning on `anchor_field_project` in `src/engine/c/engine/anchor_sift.h`, and `examples/proteins/5_sift/protein_domain.py:66-74` for the predicate that breaks it.

### F12. A crystal derived field would be half selected by crystal system, and the selection tracks mineral family

Measured by the crystallography session over `build/cod` with `maint/analysis/survey/crystal_gate_census.py`, reported here because it is a trap for this engine's benches and not for theirs.

Of 7459 entries, 3708 are admitted to the exact reading (49.7 percent), 3747 are refused for a cell that is not right angled (50.2 percent), and 4 carry no cell. The refusal is nowhere near uniform: spinel 96.1 percent admitted, garnet 98.0, olivine 95.3, melilite 95.4, perovskite 91.0, against feldspar 2.3, apatite 2.4, amphibole 4.2, tourmaline 4.6, carbonate 5.2, clay 8.8, serpentine 10.0.

The gate selects by crystal system, and crystal system is confounded with mineral family. **Any field drawn from that cache is the cubic and orthorhombic half of it**, with the monoclinic and triclinic families all but absent, and a bench run over it would report a property of that half while naming the whole corpus.

Nothing in the engine touches it today. `bench_lattice` and `bench_coherence` build synthetic periods and are unaffected, and F4's natural field is the AGPL licence text. It is recorded because F4 establishes the habit of reaching for a natural field, and this is the natural field nearest to hand.

**Check:** `maint/analysis/survey/crystal_gate_census.py` over `build/cod`, in the crystallography worktree.

### R7. "Nothing is committed" was wrong

I told the crystallography session that nothing of the engine work was committed and that there was no branch to merge. The second half holds for this session's work. The first half does not.

`0474582 src anchor_sift rewrite`, authored 2026-09-16 08:47:49, is HEAD of `worktree-engine-steer-exact` and touches `src/engine/c/portable/anchor_sift.{c,h}`, three benches, `CMakeLists.txt` and `test/engine/test_arm_agreement.c`. Verified by `git log` and `git show` here after they reported it from their own worktree.

So the rewrite is in the tree and only the work on top of it is uncommitted. The distinction matters to whoever commits next, because a commit lands on a branch that has already moved.

### R8. The overflow merged by arrival order, and the header claimed it merged by rarity

Measured by the theorist on a 400 class field, corrected here.

The header stated that classes beyond 255 share rank 255 and that those are the commonest, since ranks run rarest first. The reasoning is sound. The code did not implement it. The overflow was assigned inside the discovery pass, before the rarity sort ran at all. The merged set was chosen by **arrival order**.

Two fields with the same frequency multiset and opposite arrangements, 256 classes at nine occurrences and 144 at one: the merged sets had mean occupancies of 1.06 and 9.00. Same count merged either way, 400 minus 256 plus 1. The mechanism is exactly the table filling. A histogram cannot tell those two fields apart, which puts this in the same class as every other arrangement-invisible-to-a-histogram defect in this workbook.

**The natural arrangement is the harmful one.** A class occurring once has one chance to arrive early; a class occurring nine times has nine. Rare classes therefore arrive late and the overflow ate exactly them, at mean occupancy 1.06. The rarest class is the best probe the steering has. The degradation spent the thing the projection exists to find.

**Fixed by refusing.** A field holding more classes than a byte rank can name now returns 0 with `distinct` set to 0,. That also enforces the advice already given to three sessions whose fields are this shape: do not project, hand the oracle to a descent, which needs no ranks, no closure and no table. Tested: 400 distinct classes refused, `distinct` reporting 0.

The theorist's alternative fix, labelling with a separate `uint32_t` array of `length` entries so the component count runs unbounded and the clamp applies at relabel time, would make the original sentence true. It needs a caller supplied label array, because the kernel allocates nothing, and it is not taken here. Refusing is smaller and it is the honest answer for a byte ranked output.

**Also fixed:** `distinct` used to report 256 on a 400 class field. A caller could not distinguish a field with exactly 256 classes from one that had overflowed and was running degraded. Both reported 256.

### F13. The projection's inequality is strict, and it is reachable

Measured by the theorist on the same 400 class field, 2448 positions, 256 ranks, needle length 4.

Across every needle position: 150 needles where the projected survivor count is strictly above the exact one, and **zero** where it falls below. Sample rows show exact 6 against projected 150.

So F7's inequality is the right assertion and my own test could not reach the strict case, because 6 classes against 256 ranks means no merge occurred and projected and exact were identical. An equality assertion would have passed that run unchanged.

Unchanged under the transitive closure, for a stated reason: a different rank means no edge in the closure. The predicate is false on that pair. Agreement still implies a shared rank. The closure only makes same-rank weaker, which widens the gap the inequality allows and cannot invert it.

### R9. The volume renderer documented a census parameter it discards

Found by the theorist in published code, verified here, fixed at `ca62234`.

`anchor_volume_render_host` took a `census` parameter documented as "Rarity source for ANCHOR_CHANNEL_RARITY, or NULL". It discarded it (`src/engine/c/render/anchor_raster.c:473`) and built its own from `corpus` (`src/engine/c/render/anchor_raster.c:502`). A document describing behavior the code does not have.

**The failure it enables has no symptom.** A caller passing NULL is correct, and every caller in this tree passes NULL. Nothing crashed and nothing was unsound. A caller passing a census built over something ELSE, a reference distribution or a census taken over a sampled slice, would have that rarity source silently replaced by one computed from the corpus in front of it. The render succeeds. The picture is plausible. Nothing reports anything.

**Verification passed straight over it.** The theorist tested this renderer the same morning and reported 20 volume rows filled 32768 with 0 collisions, which is true and which never touches this parameter. "The volume renderer is verified" was a sentence both of us wrote and it did not cover this.

**Fixed by correcting the document, not by removing the parameter**, because a tunable with no reader is an integration point that is never deleted and never described as unimplemented. The declaration now says the call builds its own census from `corpus`, that this parameter is reserved for a caller supplied rarity source, and that an earlier form of the line called it the rarity source and was wrong. The same note sits at the discard site. A reader of either meets it.

\*\*Swept for the class. Every discarded parameter in the engine and the renderer was checked: `raster_value`'s is a static helper, and `anchor_raster_device`'s are the stub arm on a build with no CUDA, which is documented as refusing. `census` was the only public parameter documented as used and not used.

## Open

### F15. O1 settled: one descent is bounded above by a constant, and depth IS data dependent

**Premise replaced 2026-09-16 after Douglas caught it. The conclusion stands; the reasoning under it did not.**

The first version of this entry rested on `src/engine/c/portable/anchor_sift.h:676`, which said "Nothing in the descent lets corpus content change the DEPTH, only the choice made at a level". **That line is false on the default path**, it is now corrected in the header, and this entry no longer uses it.

`steer_descend` breaks on `(force_full_depth == 0) && (best_standing >= steer_truthy_total(...))` (`src/engine/c/engine/anchor_sift.c:1024-1025`). `best_standing` is returned by `steer_truthy_after`, which reads the corpus. `force_full_depth` is zero unless a caller names it, and an omitted member is zero. **on the default path corpus content decides the depth**. The existence of `force_full_depth` is the proof by itself: there would be nothing for it to override if depth were always `wanted`.

**The counterevidence was in F14 the whole time.** The `placed` column reads 2 at sigma 2^8 and 2^12 and 1 from 2^16 up, with `wanted` fixed at 4 on every row, and F14 explains it as the destroy rule firing because a larger alphabet lets the first probe cut far enough. That is a description of corpus content changing the depth, sitting in this document, above a claim that corpus content cannot change the depth.

**What is actually true, and the emphasis was exactly backwards.** Depth is data dependent DOWNWARD ONLY. The destroy rule can cut the descent short; nothing can extend it, because `while (placed < count)` caps it and `count` is at most `ANCHOR_STEER_ANCHORS`.

**So the cap is load bearing and data independence is not available.** The earlier entry said the reverse in both directions: that data independence was structural, that the cap was incidental, and that at four billion the classification would not shift. Withdrawn. The bound from above is the only thing doing the work, and it is a constant.

**The corrected classification.** One descent is a finite automaton WITH data dependent control flow, bounded above by a constant. It is not a fixed depth decision procedure, because the destroy test is a genuine conditional branch on data deciding whether to recurse. The constant is what still rules out universality.

**Why removing the cap would not reach universality over a fixed corpus.** The probe family is fixed by `needle_len` and `max_length`, and a placed position is never reconsidered. The placed set grows strictly through a finite family and the descent halts with or without the bound. A growing corpus grows the family, O2 is still the one term and the tag route still the target.

**One argument from the earlier version is retired outright.** It said the trichotomy shows no cycling. An unbounded run must be a deepening recursion. That is self defeating: non-cycling on a finite state space forces termination.

**Scope, stated tightly.** This classifies a SINGLE DESCENT over a fixed corpus and needle. `wanted` is `args->count`, a caller supplied value. A caller may compute it from data; within one descent it is fixed and the above holds, and across descents that is the caller's loop, which is exactly the boundary O2 draws.

**O1 and O2 are one question asked either side of one interface.** With the corpus nailed down the answer is a fixed depth decision procedure and no coarm count can make it otherwise. With a caller backed reader over a store the previous descent extended, the fixed corpus premise is gone and the outer composite can be universal by the tag system route. O1 was never a hard question that happened to be open; its answer is determined by the interface, and O2 is the only thing that moves it.

### O5. WANT: the survivor series the destroy rule actually reads

Found by the theorist while writing `docs/inspection-points.md`, and it is sharper now than it would have been this morning.

The engine computes `best_standing` at every level of the descent and compares it against `steer_truthy_total` to decide whether to stop. Then it discards it. `placed` reports the depth reached, and the raster's `DEATH_LEVEL` channel reports which probe killed each alignment, and **nothing between those two reports the survivor count at each level**

A caller who wants it today runs the descent twice with `force_full_depth` flipped and subtracts. That recovers the fact that the destroy rule fired and what its firing cost. It does not recover the reason.

**Why it matters more after F15.** Four documents were just corrected to say depth is a data dependent steer. The quantity that steer reads is not reported by the engine.

The shape would be a caller supplied array of `count` entries, filled with the survivor count at each level. Nothing is blocked on it and nothing is being built.

### O2. WANT: the one term that would make the engine a computer

**Reframed 2026-09-16 on Douglas's steer, relayed through the theorist.** His words: we are off by one term, that is all, and it just needs unbounding. This entry used to read as a blocker on a classification question. It is a capability somebody might ask for, and it is one interface change.

**The term.** The entries take `const uint8_t *corpus` with a `corpus_len`, which is a window nailed down. The engine cannot ask for more universe. The change is a reader the engine may call for more, in place of a pointer and a length.

**Why that is sufficient and not merely necessary** Unbounded READ alone does not buy universality: a finite automaton over an infinite read-only input is still a finite automaton, because nothing it computes can come back to it. But a reader is a callback the CALLER backs, and a caller can back it with a store that the previous descent's results extend. The write lives in the caller's loop, the engine stays `const`, and the engine still ends up reading what it itself produced. No write primitive enters the engine at all.

**What it composes into, and this is what makes it cheap to keep.** Growth happens only BETWEEN descents on the refuse branch. Inside a descent survivors still only shrink. Soundness, the anytime property and termination are all intact at the inner level, since all three follow from that one monotonicity. The result is a Turing complete outer machine whose every inner step is a sound, terminating, interruptible filter. The universality lives in the composition and the inner loop does not change.

**The reduction target is named. Nobody owes a universality proof.** Read a window, act on what was read, append, continue is a tag system. Post introduced them in 1943, Minsky proved 2-tag systems universal in 1961, Cocke and Minsky tightened it in 1964. What would be owed is an encoding into that shape, not a proof from scratch.

**The cost is the evidence.** At the outer level, termination goes. That is not a regression waiting to be fixed: if it were still decidable whether a given outer run finishes, the thing would not be universal. The engine's current selling point is that it always returns an answer, and this trades exactly that, at the outer level only.

**This does not settle O1 and must not be recorded as settling it.** What the engine IS today is unchanged: `ANCHOR_STEER_ANCHORS` is 4, the trichotomy shows it does not cycle, and both were verified this morning. This names what would move the answer, not what the answer is.

**Nothing is blocked on it and nothing is being built.**

### F14. O3 measured: the oracle is flat in alphabet size and the table is not, with a crossover

Built and measured by the theorist, who went looking for where the table route WINS. Both routes answer the same question, ordering four candidate needle offsets by symbol rarity. Table is a direct indexed counter per symbol value, the census generalized to a four byte symbol. Oracle is `anchor_steer_plan_recursive` with `any` set. Four byte symbols, needle 16, each timing repeated to at least 60 ms.

**Alphabet grows, corpus fixed at 131072:**

| sigma | table ms | table bytes | oracle ms | oracle bytes |
| ----- | -------- | ----------- | --------- | ------------ |
| 2^8   | 0.062    | 1024        | 1.906     | 131057       |
| 2^12  | 0.064    | 16384       | 1.935     | 131057       |
| 2^16  | 0.220    | 262144      | 1.579     | 131057       |
| 2^20  | 2.542    | 4194304     | 1.622     | 131057       |
| 2^22  | 9.000    | 16777216    | 1.667     | 131057       |
| 2^24  | 30.500   | 67108864    | 1.622     | 131057       |

The oracle column is flat across a 65536 fold increase in sigma, with no trend. The table column is linear in sigma once sigma passes the corpus size. At 2^24 the oracle runs 18.8 times faster on 512 times less memory.

**Corpus grows, alphabet fixed at 2^16:** table 0.014, 0.033, 0.110, 0.216 ms against oracle 0.053, 0.201, 0.789, 1.605 at 4096, 16384, 65536 and 131072 positions. **Both linear in corpus and the table 7.4 times faster on every row.** That is the constant factor the oracle pays: the table's per symbol work is one array increment and the oracle's is an indirect call. The oracle buys independence from sigma and pays per corpus symbol for it.

**The crossover is at roughly six times the corpus length.** Fitting the table above 2^20 gives about `0.16 + 1.78e-6 * sigma` ms, meeting the oracle's 1.6 ms near sigma 809000 against a corpus of 131072. Table wins below it, oracle wins above and keeps winning.

**The durable claim is the memory and not the time.** Sigma 2^32 is not measured and was not allocated: 16.0 GB of counters at four bytes a slot. The theorist's own caveat against the timing is the reason to prefer the memory claim. The table route in the bench callocs and frees its counters every iteration, and a real caller searching many needles against one fixed corpus builds the census once and amortizes it, which widens the table's time advantage and means the time column overstates the oracle's case. Memory does not amortize. 16 GB is 16 GB whether it is paid once or a thousand times.

**One behavioral note from the same run.** `placed` came back 2 at sigma 2^8 and 2^12 and 1 from 2^16 up: at a large alphabet the first probe cuts the survivors far enough that a second adds nothing. That also explains why the oracle's small sigma rows are its slowest. It is doing more work there, not suffering from sigma.

So the claim boundary in O3 is now partly closed. The trend is measured, it is the trend the construction predicts, and the regime where the table is the right choice is named.

### O3. The alphabet size bench, which would produce a new number

I killed my own best candidate for a problem the engine uniquely solves. Main and Lorentz give `Omega(n log n)` for repetition detection over a general alphabet, which reads like a barrier the engine walks past. It is not: the bound is `Theta(n log sigma)` and the `n log n` form assumes `Omega(n)` distinct symbols. At `sigma = 256` the factor is 8 and it is linear. On byte corpora the engine beats nothing asymptotically.

I then observed that the regime which would demonstrate the advantage and the regime we cannot test are the same regime. The theorist's answer is that this is escapable and it is the only item here that would produce a new number: you cannot test `sigma` unenumerable, but you **can** test `sigma` growing. Four byte symbols give `sigma = 2^32`, or exact rational symbols compared by equality. Measure the engine's state against a bad character table's as `sigma` climbs. The table grows linearly in `sigma` and the engine's state stays at `m` bits. A flat line against a rising one over three or four decades is the demonstration and it never needs the untestable limit. The claim to make is about the trend, which is measurable, and not the limit, which is not.

**Not built.**

### R10. The space lower bound does not apply to the exact path, and the engine is far above it

**Withdrawn.** O4 read: online exact pattern matching carries an `Omega(m)` bits space lower bound and the engine carries `m` bits, which implied the engine sits at a space optimum. The theorist read the paper. It does not, and the truth runs the other way.

Clifford, Jalsenius, Porat and Sach, "Space Lower Bounds for Online Pattern Matching", arXiv:1106.4412, CPM 2011. Abstract verbatim, checked here against the paper and not against a summary:

> We give Omega(m) bit space lower bounds for L_1, L_2, L_infinity, Hamming, edit and swap distances as well as for any algorithm that computes the cross-correlation/convolution.

**Exact pattern matching is not in that list.** The bound is for distance measures. The question I had parked, whether that `m` is the same `m`, was the wrong question: it is not even the same problem.

**The dichotomy is what settles the two paths, and it separates them.** Verbatim:

> We then show a dichotomy between distance functions that have wildcard-like properties and those that do not. In the former case which includes, as an example, pattern matching with character classes, we give Omega(m) bit space lower bounds. For other distance functions, we show that there exist space bounds of Omega(log m) and O(log^2 m) bits.

**The exact byte path falls on the `Omega(log m)` and `O(log^2 m)` side.** Porat and Porat, FOCS 2009, do exact pattern matching in a stream in `O(log m log n)` bits. So the engine carrying `m` bits on the exact path is not meeting a lower bound. It is roughly `m` over a known upper bound.

**The rank projected path is the candidate case and nothing is asserted about it.** Matching on equivalence classes, where a needle position of rank `r` accepts any corpus symbol of rank `r`, is pattern matching with character classes, which the paper names explicitly as an `Omega(m)` case. The reduction has not been written and the theorem is not claimed to transfer. What is established is only that the projected path is where this citation plausibly applies and the exact path is where it plainly does not.

**Also corrected: the bound is not deterministic only.** Verbatim: "We require that the correct answer is given at each position with constant probability." It binds randomized algorithms too. A summarizer told the theorist deterministic only and the abstract contradicted it. "The lower bound is only for deterministic algorithms" is exactly the plausible sentence that would otherwise have been written here.

**Why the engine carries `m` bits anyway, and it is an interface cost.** The `O(log^2 m)` route is fingerprinting, reached by combining Karp-Rabin with KMP. Karp-Rabin needs arithmetic on symbols, treating them as numbers modulo a prime. `AnchorField` exposes equality and nothing else: no order, no hash, no element size, no arithmetic. The engine cannot reach that regime, and the reason is its own oracle.

**That is the same trade F14 measured, priced in the other currency.** The equality-only oracle buys independence from alphabet size. F14 prices that in time: a 7.4 times constant factor per corpus symbol, with a crossover near six times the corpus length. This prices it in space: `m` bits where `O(log^2 m)` is achievable for exact matching, because fingerprinting is closed to an engine that refuses to expose a representation. One interface decision, two measured costs. That is a better account of what the oracle costs than a lower bound the engine was never up against.

**How the wrong version got here.** An earlier fetch of the same paper returned a summary naming "Theorem 6" and stating that exact pattern matching requires `Omega(m)` bits. That was recorded as the shape of the result without the abstract being read. Same class as everything else in this section: a plausible sentence from a summary, not checked against the source.

Sources: [arXiv:1106.4412](https://arxiv.org/abs/1106.4412) for the lower bounds and the dichotomy; Porat and Porat, "Exact and Approximate Pattern Matching in the Streaming Model", FOCS 2009, 315 to 323, for the `O(log m log n)` upper bound.

## What the theorist is asked to do

Transcribe the holds and the retractions into the workbooks in their own words, and verify. The three I most want attacked are F5, because the domain and range argument is mine and short enough to be wrong quickly; F8, because F7's bound depends on the enumeration being complete and I have asserted completeness from reading the loops.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
