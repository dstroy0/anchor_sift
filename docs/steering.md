# Steering the engine with its own reading of the field

**Purpose:** Place, order and shape the engine's probes from a census of the corpus being searched, and know why doing so cannot change the count.
**Scope:** `src/engine/c/portable/anchor_sift.h`, `src/engine/c/portable/anchor_sift.c`, `test/engine/test_steer.c`

The engine searches by placing anchors on the needle and testing them at every alignment. An alignment that disagrees at any anchor cannot hold the needle, so it is rejected without a full compare. Which anchors it places, the order it tests them in, and the shape each one takes were all fixed before the corpus was looked at. This document covers the code that decides those three from the corpus instead.

## Every probe is a necessary condition

Each probe tests whether the corpus at some offset carries the needle's own byte at that offset (`src/engine/c/portable/anchor_sift.c:780`). A true occurrence agrees at every offset, so it agrees at every probe. Each probe is therefore a necessary condition of an occurrence, a conjunction of necessary conditions is itself one, and no true occurrence is lost by any probe set. Survivors are then filtered by a full compare (`src/engine/c/portable/anchor_sift.c:990`), which removes the false ones. The count is exact for any probe set whatever.

Two different invariants follow, and keeping them apart matters. Reordering a probe set leaves the surviving set itself identical, because conjunction commutes. Moving a probe or changing its shape gives a different probe set, which is a different conjunction and a different surviving set: the survivors of one probe strictly contain the survivors of that probe and a second. What stays identical across every probe set is the COUNT, because every surviving set contains all the true occurrences and the full compare removes the rest.

The survivor count depending on which probe is placed is the steering signal itself, measured in `steer_truthy_after_probe` (`src/engine/c/portable/anchor_sift.c:789-800`). A reading that held the surviving set fixed across different probe sets would leave the planner with nothing to rank.

A move that cannot change the answer is what this tree calls a null. Reordering is a null on the surviving set, and every probe set whatever is a null on the count.

One consequence shapes the whole design. A planner that samples badly, ranks wrongly, or contains a defect still produces some probe set, and every probe set yields the same count. Correctness is not a quantity the planner can spend. Speed is the only one it can spend, and that bounds the damage a bad planner does to the time it takes. The empty plan makes this vivid: destroy every probe, send every alignment to the full compare, and the answer is still exactly right at maximum cost.

## What keeps a probe inside the family

The guarantee above covers necessary conditions and nothing wider, so the value of the guarantee depends on every probe staying inside that family. Three things in the code hold the boundary. `anchor_steer_probe_fits` keeps the origin below `needle_len` and requires every position the probe reads to stay inside the needle (`src/engine/c/portable/anchor_sift.c:745-770`). Candidate generation rejects any shape failing that test before it is scored (`src/engine/c/portable/anchor_sift.c:874`). The comparison reads `needle[offset]`, the needle's own byte at the offset being tested (`src/engine/c/portable/anchor_sift.c:780`).

Three shapes would leave the family, and a probe type added later can leave it silently with a missing occurrence as the only symptom.

A probe reading outside the needle has nothing to compare against. A probe comparing against any value other than the needle's own byte at that offset tests something an occurrence does not have to satisfy. A predicate taken from the census instead of from the needle is the live danger in a steering engine: a rule like "skip alignments in a low-rarity region" is not implied by occurrence and drops true hits. The census chooses among probes and must never become one.

A fourth case is latent. An eye here is a conjunction of byte equalities, so the rule holds. If an eye ever becomes an actual integral, an aggregate is a necessary condition only when both sides are computed identically in exact arithmetic. Two different summation orders in floating point would let a true occurrence fail its own test.

## The census is the engine reading its own field

`anchor_field_census` counts what the corpus is made of in one pass, recording the occurrences of each byte value, the total, and how many values appear at all (`src/engine/c/portable/anchor_sift.c:312-338`). Nothing outside the corpus contributes to it. The census then decides where the engine probes that same corpus, so the instrument is turned on the field it is about to measure.

## Rarity ordering needs no logarithm

The theory states the ordering term as rarity, the negative log probability of the symbol an anchor tests. Ordering by that quantity does not require evaluating it. The negative logarithm decreases monotonically in the probability, and every probability over one corpus shares the denominator, so ordering by rarity descending is ordering by raw occurrence count ascending. Both orderings agree on every input.

`anchor_steer_magnitude` returns the total minus the symbol's own count (`src/engine/c/portable/anchor_sift.c:340-347`). The value is an integer, it orders identically to rarity, and it is not an entropy in bits. A symbol absent from the corpus returns the largest magnitude available, which is correct: an anchor testing a symbol the field never produces rejects every alignment at once.

## Truthy and falsy steering

The steering signal is the survivor vector and not the symbol histogram. Each alignment is truthy while it is still standing and falsy once some probe has rejected it. `steer_truthy_after` counts how many currently truthy alignments would remain truthy if a given probe were placed (`src/engine/c/portable/anchor_sift.c:506-525`), and the descent spawns the probe leaving fewest.

Measuring survivors directly accounts for correlation between positions. A histogram says how often a symbol appears; it does not say whether the alignments that agreed at one position tend to agree at another. The survivor count answers the second question, because it is taken over the population that actually survived.

## Recursion over levels, one probe each

`anchor_steer_plan_recursive` reorders offsets a caller has already placed, and `anchor_steer_spawn_coarms` chooses the positions itself (`src/engine/c/portable/anchor_sift.h:369`, `src/engine/c/portable/anchor_sift.h:414`). Both descend through the same core.

A single pass ranks every anchor against the whole field. That is the correct question to ask first and the wrong one to ask second. Once the first probe has rejected most alignments, the ones still standing are the subset that agreed with one particular symbol. Within that subset the remaining probes have different pruning power than they had over the field. Each level here ranks against the alignments that survived the levels above it, taking the conditional distribution in place of the marginal one.

### Signature

```c
size_t anchor_steer_spawn_coarms(const AnchorSteerDescent *args);
```

One pointer to a const argument structure, not a parameter list. Build the structure at the call site with `ANCHOR_STEER_CALL`, which gives it automatic storage and zeroes every member the caller does not name. The members this entry reads (`src/engine/c/portable/anchor_sift.h:550-566`):

* `offsets` [BORROWS] out. Chosen offsets, written in evaluation order. Owned by the caller.
* `count` in. How many coarms to spawn, at most `ANCHOR_STEER_ANCHORS`.
* `corpus`, `corpus_len` [BORROWS] in. The bytes the search will run over. Unread where `any` is set.
* `needle`, `needle_len` [BORROWS] in. The bytes to find. Unread where `any` is set.
* `survivors`, `survivors_length` [BORROWS] out. Which alignments the probes left standing, one byte each. Size it at `corpus_len - needle_len + 1`.
* `sample_stride` in. Plan on every Nth alignment. A value of 0 is treated as 1.
* `force_full_depth` in. Non-zero descends every level and ignores the destroy rule.
* `any` [BORROWS] in. A field of any symbol type. Null takes the byte path.

`survivors` is the descent's output and not a working buffer. It records, per alignment, whether the probes left that alignment standing, and it is the only place that information appears: the return value gives the depth reached and says nothing about which alignments survived. A caller wanting only the depth may ignore it, and a caller wanting the surviving set has no other route to it. This is also why the descent is not a streaming algorithm and why bounds stated for streaming matchers do not describe it.

Returns the number of coarms placed, at most `count`. Returns 0 without writing `offsets` when a pointer is null, when `count` exceeds `ANCHOR_STEER_ANCHORS`, or when `survivors_length` does not reach the alignment count (`src/engine/c/portable/anchor_sift.c:808-834`). The kernel allocates nothing. A buffer too small is refused instead of being worked around.

## Why halting is the wrong question

Two separate properties hold, and the second one carries the argument.

The descent is bounded from above. One probe is placed per level, a placed probe is never reconsidered, and the depth is AT MOST `wanted`, which the guard holds at or under `ANCHOR_STEER_ANCHORS` (`src/engine/c/portable/anchor_sift.c:618-620`). That constant is 4 (`src/engine/c/portable/anchor_sift.h:74`). The loop cannot run longer than that whatever the corpus holds, and that is what makes it terminate.

It can run shorter, and the corpus is what decides. The destroy test compares the best candidate's surviving population against the current one, and that count is read off the corpus, so where nothing prunes the descent breaks early. `force_full_depth` exists to override exactly that, and an omitted member is zero, so the default path is the one where the field ends the descent. `bench_sigma` measures it: `wanted` fixed at 4 on every row while `placed` returns 2 at an alphabet of 2^8 and 1 from 2^16 up.

An earlier version of this paragraph said no branch lets corpus content change how many levels run and that the depth is fixed before the program starts. That holds only under `force_full_depth` and was written as though it held always.

The stronger property is that correctness never depends on termination. Every intermediate state of the descent is a complete valid probe set, and every probe set yields the same count. The refinement can be stopped at any instant and the measurement taken with the plan it had reached is correct. Running longer buys speed and cannot buy or lose an answer.

**There are two loops and only one of them has that property.** Plan refinement is anytime and can run as long as anyone wants it to. The sweep over alignments has to run to completion, and stopping it early loses occurrences. A reader who takes the anytime property as a property of the search itself will stop the measurement and get a wrong count.

The bound in the first paragraph is still doing work once the anytime property is stated, and it is doing different work. The anytime property gives safety, since every reachable plan is correct. The bound gives liveness, since the planner emits a plan and the sweep begins. In a design that plans and then sweeps, an anytime planner that never returns produces no measurement at all.

The halting problem asks whether termination can be decided for an arbitrary program. Here the question does not arise, because no answer depends on it. That is a stronger position than a decidable halt. The loop therefore carries no iteration cap and no watchdog. A bound enforced at compile time does not need one, and a runtime check would imply the bound were in doubt. `anchor_steer_spawn_coarms` returns the depth it reached, and `test/engine/test_steer.c` asserts that depth instead of trusting this section.

## Spawning and destroying

A level that finds no candidate leaving fewer survivors than it started with has found a probe that rejects nothing an earlier probe had not already rejected. Placing it would read a byte per alignment and buy none. The descent stops there and every level below it is destroyed with it, and the returned count tells the caller how many probes survived (`src/engine/c/portable/anchor_sift.c:702-703`).

`anchor_sift_anchors_for` already does this for one case, returning a single anchor on a periodic corpus because at a period the offsets cancel and every anchor tests the same congruence (`src/engine/c/portable/anchor_sift.h:136-141`). The rule here reaches further. The header warns that a period found is not a period the whole corpus keeps, that a partially coherent corpus wants a count between one and the full set, and that nothing there measures that case (`src/engine/c/portable/anchor_sift.h:145-147`). This rule measures it, along with redundancy from constant runs, local low entropy and correlated positions, none of which a period argument sees.

The two are different kinds of statement and the guide keeps them apart. The period argument is a theorem over every corpus of that period. This rule is an observation about one field, taken on a sample of it when `sample_stride` is above one, so "pruned nothing on this sample" does not establish "can prune nothing". Being wrong costs speed and cannot cost the count.

Destroying the levels below a destroyed probe costs nothing, and the reason is an induction rather than a budget.

The destroy test compares the minimum over every candidate against the current population (`src/engine/c/portable/anchor_sift.c:702-703`). When it fires, the minimum leaves the population unchanged, so every candidate leaves it unchanged. Placing one would prune nothing, and the next level would inherit the identical population. Its candidate set is the same set or a subset of it, since the enumeration bounds are arguments and constants that do not vary by level (`src/engine/c/portable/anchor_sift.c:856-859`) and the coarm descent only ever removes a placed position from consideration. Every candidate in a subset of a set that all left the population unchanged also leaves it unchanged, so the next level's minimum is the whole population and its test fires too. By induction every level below prunes nothing.

Stopping is therefore equivalent to continuing, and the probe set is not smaller than the field would have supported.

The induction needs one property of the enumeration: the candidate set is non-increasing along the descent. Both planners have it. The sweep enumerates the same set at every level, and the coarm descent removes each placed position from consideration (`src/engine/c/portable/anchor_sift.c:659-670`), which is a strict subset. A set that grows at a deeper level voids the theorem, because a candidate absent from the level that fired has never been shown to prune nothing. A set that varies for any other reason voids it as well, since the two cases become indistinguishable from inside.

The argument is exact over the population the planner sees, which is the sampled one when `sample_stride` is above one. Against the full field it carries the same sample caveat as the destroy rule itself.

## The boundary, stated as domain and range

Every claim below falls out of writing down what each function takes and what it can return. Nothing here is new behavior. It is the same engine read algebraically.

Let `A` be the alignments, `N = |A|`, and `T` the alignments where the needle occurs exactly. A probe `p` is a set of needle positions together with the needle's bytes there. Its decision at an alignment is determined by the corpus bytes at that alignment and those positions, and nothing else.

    S_p   = { a in A : the corpus agrees with the needle at every position p reads }
    S(P)  = intersection of S_p over p in P,   with S(empty set) = A

**Survivorship.** `T` is a subset of `S_p` for every legal probe `p`, so `T` is a subset of `S(P)` for every probe set `P`. An occurrence agrees with the needle at every position, and `p` reads a subset of those positions, so `p` cannot refute it. This is soundness written as a range: the range of `S` is bounded below by `T` and never drops beneath it.

**Antitone.** If `P` is contained in `Q` then `S(Q)` is contained in `S(P)`. Intersecting with more sets removes members and adds none.

**Nonhalting self examination.** Take any growing chain of probe sets `P_0` inside `P_1` inside `P_2` and onward. The survivor sets are non-increasing and every single one contains `T`. The engine may therefore extend its probe set forever, or stop at any index, or be interrupted, and the exact compare over whatever `S(P_i)` it holds returns exactly `T` in every case. Correctness never depends on termination, and `A` being finite means the chain is eventually constant, so a fixed point exists without anything depending on reaching it.

**The legal operation is union, and that is the whole algebra.** `S` turns union into intersection: `S(P union Q) = S(P) intersect S(Q)`. Union is commutative, associative and idempotent, so the probe set is a set and never a sequence and never a multiset. Placing a probe twice changes nothing, and the engine's check for an already-placed offset is therefore a saving and not a correctness requirement. Order and placement are nulls, which Section 1 gets from necessary conditions and this gets from the algebra. The two arguments are independent and agree.

## The wall: one read per alignment, and it cannot be crossed

**Theorem, and the units are part of it.** An engine that decides each alignment using only reads taken at that alignment performs at least one READ EVENT per alignment. Total read events are at least `N`.

**It does not bound distinct bytes, and an earlier version of this section implied it did.** A read at corpus position `p` lies inside the span of `m` alignments, so one fetched byte is a read event for each of them. Going from "every alignment needs a read in its span" to "total bytes read is at least `N`" needs those reads partitioned one per alignment, and nothing establishes that partition. Sample one position every `m` so each span holds exactly one: a mismatch refutes that alignment on a single byte and the same byte refutes up to `m - 1` neighbours. The theorist measured it, deciding every alignment with the answer asserted against the naive scan on every row, and distinct bytes per alignment came out at 0.9948 for an alphabet of 4, 0.7573 at 16, 0.3545 at 64 and 0.1276 at 256. Well under one, and the construction is inside the premise rather than outside it.

The correction above that moved this claim from "reads" to "bytes read at an alignment" moved it in the direction that makes it false, while the test kept asserting the event version. Both are now stated: the bound is on read events, the test counts read events, and nothing here bounds memory traffic, because a byte read twenty four times is one cache line.

**Proof.** Suppose the engine decides alignment `a` having read nothing at `a`. Its decision is then a function whose domain is the empty tuple, so its range holds exactly one value and it answers identically whatever the corpus holds at `a`. An adversary edits the corpus at `a` to flip whether `a` belongs to `T`. The engine reads nothing different and returns the same answer, which is wrong for one of the two corpora. So at least one read happens at every alignment the engine classifies.

The bound is attained. The empty probe set takes no probe reads and sends every alignment to the compare, which reads at least one byte each, giving exactly `N`. The configuration that steers least sits exactly on the floor, which is what shows the floor belongs to the problem instead of to the steering.

`test_steer` asserts this on all five fields. It checks that every route's probe reads plus compares reaches `N`, and that the empty probe set takes exactly zero probe reads and exactly `N` compares (`test/engine/test_steer.c`). The floor is reported outside the route table on purpose: the table counts probe reads and the floor counts total reads, and one column carrying two units invites a reader to compare a bound against a cost. In real bytes the empty probe set is the most expensive route there is, since every alignment takes a full compare.

**What the theorem does not cover.** It binds engines that decide an alignment from reads at that alignment. A skipping search breaks that premise deliberately: it uses a read at one alignment to decide a range of others, and never visits most of them. Its reads per alignment are taken over a sparse subset of `A` and fall below one for that reason. That is a different quantity wearing the same name, and no ratio between the two measures anything.

## One invocation is total. The system is not, and that is deliberate

An earlier version of this section claimed the engine is not Turing complete and gave the bounded loops as the reason. That claim was wrong, and the error is worth keeping because it is easy to repeat: it analyzed a single invocation and drew a conclusion about the system.

**What is true of one invocation.** Every loop inside one call is bounded by a quantity fixed before that call runs. The sweep over alignments runs to `N`, the descent runs to `ANCHOR_STEER_ANCHORS`, and the shape enumeration runs to `needle_len` and to a caller's `max_length`. No continuation depends on a predicate computed from corpus content. One call is total and its running time is a function of the input sizes.

**Why that decides nothing.** A system that halts on every input decides its own halting, so establishing Turing completeness is exactly the question of whether the outer loop is bounded, and the outer loop here is self examination. Nothing bounds the number of rounds. The engine spawns, destroys, re-reads and turns on itself again.

This section has now been written three ways and two of them were wrong, so what follows separates what is settled from what is open, and the open part is marked as open.

### What is settled

**The trichotomy.** A descent stops, recurses, or refuses to run. It stops when the destroy test fires. It recurses when a level prunes. It refuses, returning zero and writing nothing, when a pointer is null, when the count exceeds `ANCHOR_STEER_ANCHORS`, when the needle length is zero or exceeds the corpus, or when the survivor buffer does not reach the alignment count (`src/engine/c/portable/anchor_sift.c:808-834`). A malformed question does not run. There is no fourth branch in which it revisits a state it has already held.

**Soundness does not depend on which branch is taken.** `T` is contained in `S(P)` for the probe set placed right now, and that statement never mentions how `P` was reached or whether the process reaching it will stop. The answer is exact at every instant of a process that need not terminate. The anytime property is not a convenience attached to a terminating computation; it is what makes a non-terminating one useful.

**Failing to halt is not Turing completeness.** A process can fail to halt by cycling among three states. Turing completeness needs storage that grows during execution together with the ability to compute arbitrary functions of it. The second version of this section conflated the two and claimed the engine is Turing complete because its outer loop is unbounded. That does not follow.

**What is implemented today is finite.** `ANCHOR_STEER_ANCHORS` is 4, so the descent places at most four probes and spawns at most four coarms. `ANCHOR_EXACT_LIMBS` is 108, which is 3456 bits, and a fixed width counter is a finite state machine at any width. For a fixed corpus the survivor set is a subset of the alignments and the probe family is bounded by the needle length. Nothing in the engine as built grows while it runs.

**The methodological error is the durable finding and it survives either answer.** The first version concluded the system is total by observing that every loop inside one invocation is bounded. That is a property of one invocation. A system halting on every input decides its own halting, so the claim needed the outer loop and never looked at it.

### What one descent is

The question was whether the construction admits unbounded storage, and it was framed as turning on the coarm count: if an engine spawned coarms that each carried their own survivor vector, the state would be a tuple whose size grows with the arm count.

**Settled, and the bound from above is what settles it.** One coarm per level means the arms do not multiply: the descent is a chain and not a branching tree, so the state never becomes a tuple whose size grows, and the premise the growing answer needs is false here. The loop is `while (placed < count)` with `count` at most `ANCHOR_STEER_ANCHORS`, so it cannot run longer than a constant whatever the corpus holds.

One descent is therefore a finite automaton WITH data dependent control flow, bounded above by a constant. It is not a fixed depth decision procedure, because the destroy test is a genuine conditional branch on data that decides whether to recurse.

**The cap is load bearing and this paragraph used to say the opposite.** An earlier version claimed the depth is data independent and that the constant is incidental, so at four billion the classification would not shift. Both halves are wrong. Depth IS data dependent, downward only: the destroy test can cut the descent short and nothing can extend it. The constant bounding it from above is the only thing ruling out unbounded depth, and at four billion it would still rule it out, which is the point. Data independence is not available as an argument.

One argument this section used to give is retired outright. It said the trichotomy shows no cycling, so an unbounded run must be a deepening recursion. That is self defeating, because non-cycling on a finite state space forces termination rather than permitting unbounded depth.

**Why removing the cap would still not reach universality, over a fixed corpus.** With the corpus nailed down the probe family is fixed, and a placed position is never reconsidered, so the placed set grows strictly through a finite family and the descent must halt with or without the bound. What breaks that is a corpus that grows, because a growing corpus grows the family, which is the section below.

This classifies ONE DESCENT over a fixed corpus and needle. `wanted` is a caller supplied count, so a caller may compute it from data across descents, and that is the caller's loop and belongs to the section below.

### What would move the answer, which is one interface and not a rewrite

The engine reads `const uint8_t *corpus` with a `corpus_len`, so it cannot ask for more field than it was handed. Replace that with a reader it may call for more and the picture changes, for a reason worth stating because it is not obvious.

Unbounded reading alone buys nothing. A finite automaton over an infinite read-only input is still a finite automaton, because nothing it computes can reach it again. But a reader is a callback the CALLER backs, and a caller may back it with a store that the previous descent's results extend. The write then lives in the caller's loop, the engine stays `const` and gains no write primitive, and the engine still ends up reading what it itself produced. That is the whole of it.

What it composes into keeps everything this document argues for. Growth happens only between descents, on the branch where a descent refuses, which is the shape of asking another slightly different question. Inside a descent the survivors still only shrink, so soundness, the anytime property and termination all hold at the inner level, because all three follow from that one monotonicity. The outer machine is universal and every inner step of it is a sound, terminating, interruptible filter.

Nobody would owe a universality proof for it either. Read a window, act on what was read, append, continue is a tag system, and 2-tag systems have been known universal since Minsky in 1961. What is owed is an encoding into that shape.

The price is exactly the property the engine is sold on. At the outer level termination goes, and that is the evidence rather than a defect to repair: if it stayed decidable whether an outer run finishes, the thing would not be universal. The inner loop keeps its guarantee and the outer one gives up the one it never claimed.

None of this settles the question above. It names what would move the answer and not what the answer is, and nothing in the tree is being built toward it.

## The interior: the sweep runs the whole legal set

The boundary function is `anchor_steer_probe_fits`, whose domain is probes paired with a needle length and whose range is `{0, 1}` (`src/engine/c/portable/anchor_sift.c:745-770`). It is the characteristic function of the legal probe set: origin inside the needle, and every position the probe reads inside it too, with a step of zero at length above one refused as an arm wearing an eye's shape.

`anchor_steer_sweep_probes` enumerates one representative of each equivalence class, which is not the same as enumerating the interior whole, and an earlier version of this section claimed the latter.

The gap is at length one. `anchor_steer_probe_fits` returns 1 for a length one probe at ANY step, zero included, because the length test returns before the step test. The sweep sets its step limit to 2 at length one and generates step 1 alone. So legal probes exist that the sweep never produces: origin 3 length 1 at steps 0, 2, 7, 13, 64 and 100000 all fit, and all return the same count through `anchor_steer_count_with_probes`, because a probe of length one reads one position and its step is unread. The header says exactly that already.

Quotient the legal set by "reads the same needle positions" and the sweep enumerates one member of every class. That is what the guarantee needs, since two probes reading the same positions refute the same alignments and have the same marginal gain, so a maximum over the representatives is a maximum over the set. Nothing was unsound; the claim was wider than the code and wider than it needed to be.

Two smaller corrections from the same audit. At length two with a needle of twelve, the highest fitting step at origin zero is eleven while the sweep tries to twelve, so one iteration per origin and length is always refused. And `max_length` is an argument, so the next section's ratio is exact over probes of length at most `max_length` and not over probes of any length, which the earlier wording did not say.

## The descent is greedy coverage, and that is a named result

The induction above is self-contained and it proves less than the structure supports. Write the objective down as a set function and the whole thing becomes a theorem from 1978.

Fix the corpus and the needle. Each candidate probe `p` rejects a definite set of alignments, `R_p`, the alignments where the byte the probe reads disagrees with the needle's byte at that offset. For a set of probes `P`, the alignments rejected are the union, and the count is

    f(P) = |union of R_p over p in P|

`f` is a coverage function. It is monotone, because adding a probe never un-rejects an alignment, and it is submodular, because an alignment already rejected by some probe in `P` contributes nothing when a later probe rejects it again. Coverage functions are the textbook example of monotone submodularity, and this one needs no assumption about the corpus to be one.

The descent maximizes `f` greedily. At each level it scores every candidate by the survivors it would leave and keeps the smallest count (`src/engine/c/portable/anchor_sift.c:677-681`), and fewest survivors left is most alignments newly rejected, which is the largest marginal gain in `f` given what is already placed. Nemhauser, Wolsey and Fisher proved in 1978 that greedy maximization of a monotone submodular function under a cardinality constraint returns at least `1 - 1/e` of what the best set of that size achieves, so the probe set the descent places rejects at least about 63 percent of the alignments the optimal probe set of the same size rejects. Nothing in the engine has to be changed for that to hold. It holds because of what the objective is.

Two things follow that the hand induction had to work for.

**The destroy rule is greedy's zero marginal gain stop. Submodularity does NOT supply its premise, and an earlier version of this section claimed it did.** Diminishing returns bounds the gain of a FIXED candidate as the placed set grows. It says nothing about a candidate that was not in the earlier candidate set, because there is no earlier gain to bound it by.

The counterexample is three alignments. Let `R_p` be empty and let the candidate set at level 0 be `{p}`. The best marginal gain is zero and the destroy rule fires. Let the candidate set at level 1 be `{p, q}` with `R_q = {1,2,3}`. Nothing was placed at level 0, so the surviving population is unchanged, and `q` has a gain of three over it. Stopping rejects none of the three alignments and continuing rejects all of them. `f` is monotone and submodular throughout and the destroy theorem fails anyway.

So the non-increasing enumeration premise stated in the section above is load bearing and stays. What submodularity gives is the bound below and the identification of the stop test as greedy's zero marginal gain stop. What it does not give is the equivalence of stopping and continuing. Those are two theorems and only the first comes free.

**The order within a placed set is free, which is already the necessary-condition argument arriving from the other direction.** `f` is defined on sets. Section 1 says the conjunction of necessary conditions is order independent and the count is exact for any probe set whatever. The coverage view says the same about cost: what a probe set rejects depends on the set and not the sequence. Placement and order are nulls in both.

### What this does not claim

The guarantee is on alignments rejected by `k` probes. It is not a guarantee on reads, and those differ: rejecting an alignment early saves the reads a later probe would have spent on it, so a set that rejects the same alignments in a different order costs a different number of reads. The read counts in the table above are measurements and are not covered by the ratio.

It also assumes the marginal gains are evaluated exactly, which holds at `sample_stride` of one. Above one the planner scores candidates on a sample, which makes the oracle approximate, and greedy under an approximate oracle degrades by an amount depending on the error rather than holding at `1 - 1/e`.

Nothing here has been measured against the optimal probe set, because computing that means enumerating every set of size `k` and is exponential. The ratio is a proved floor and this document does not report it as an observation.

## Arms and eyes are one shape

An arm reads one position and an eye reads a line of them. `AnchorProbe` records an origin, a step and a length, and an arm is a probe of length one (`src/engine/c/portable/anchor_sift.h:467-473`). One test walks both. `docs/arm-records.md` states the same thing about readings: the difference between a region integral and a line integral lives in the support and not in the arithmetic applied to it.

`anchor_steer_sweep_probes` considers every origin in the needle, every step that keeps the probe inside it, and every length up to a caller's maximum, scoring each shape by survivors (`src/engine/c/portable/anchor_sift.c:856-859`). A step of zero at a length above one reads one position repeatedly, and `anchor_steer_probe_fits` refuses it (`src/engine/c/portable/anchor_sift.c:759-765`).

## An eye does not reduce reads

The table below runs on five fields. An earlier version of this section reported one, the license text, and every conclusion drawn from it was a conclusion about that file. The three synthetic kinds are generated by `bench_corpora`, which the grader links instead of carrying its own copy, so skewed means one thing across this tree (`test/engine/test_steer.c:734`). Needle length 24, built with MSVC 14.44 at the default CMake configuration, every route graded against `anchor_sift_naive`. Cells are reads per alignment:

| field | alignments | spatial, unsteered | recursive reorder | coarms spawned | eyes and arms swept |
|---|---|---|---|---|---|
| uniform | 65513 | 1.003 | 1.003 | 1.003 | 1.003 |
| synthetic skewed | 65513 | 1.562 | 1.002 | 1.001 | 1.002 |
| skewed | 65513 | 1.877 | 1.875 | 1.067 | 1.069 |
| periodic16 | 65513 | 1.187 | 1.000 | 1.000 | 1.000 |
| natural, AGPL English text | 24631 | 1.072 | 1.066 | 1.000 | 1.062 |

Every route on every field returned the reference count.

The family shows three things one field could not. Steering pays nothing on a uniform field, where no symbol is rarer than another and the ordering has nothing to order by. It pays most where the field repeats or its rarity spreads, taking 1.877 to 1.067 on the skewed field and 1.187 to an exact 1.000 on the period 16 field, which the planner reaches with one probe where the unsteered route places four. And the two mechanisms separate: on the skewed field the recursive reorder moves 1.877 to 1.875 while spawning coarms moves it to 1.067, so what pays there is the spawning and not the ordering. On the license text both routes move together and the distinction is invisible.

**The weakest field is uniform, and an earlier version of this paragraph said it was the license text.** Read the best steered route and not the reorder column: the license text goes 1.072 to an exact 1.000 on coarms, which is the floor. Uniform goes 1.003 to 1.003 and does not move at all, on any route, because a uniform field has no rarity for the steering to spend and there is nothing for an ordering to order by. That is the honest worst case and it is the one to quote against.

The earlier error was reading 1.066 out of the recursive reorder column and calling it the field's result. Every field's result is its best route, and on the license text the reorder does almost nothing while the coarms reach the floor, which is the spawn against reorder distinction the rest of this section is about.

The eye is the negative result and it holds on all five. An eye never read fewer bytes than the coarms on any field, and on the license text it read 26168 against their 24635. An eye of length L reads up to L bytes per alignment where an arm reads one, so it moves the bytes the equivalent arms move and removes only the branch decisions between them. Reach for an eye where branches cost more than reads, and measure before assuming that holds.

One read per alignment is the floor for a scheme that decides each alignment from reads taken at that alignment, because such a scheme has to look at an alignment to reject it. Two fields reached it.

That floor describes this engine and is not a number to hold a different search style against. Boyer-Moore, Horspool, Sunday and the factor-based methods skip alignments outright: a mismatch at one alignment proves non-occurrence across a range, and the skipped alignments are never read. Their reads per alignment is taken over the alignments they chose to visit, which is a sparse subset of the alignments counted in this table. The name is shared and the set counted underneath it is not, so a ratio between the two columns measures nothing. This engine visits every alignment by construction and rejects; a skipping search advances. No figure here is a comparison against one.

The engine gives that up deliberately, and what it spends is worth stating precisely because `README.md:99` makes two separate claims: that the engine carries `m` bits of state for a pattern of length `m`, and that nothing is indexed and no table is built over the alphabet, which is the half covering a real-valued or unenumerable alphabet.

A classical bad character table is indexed by symbol and spends both. A structure built from the needle's own values spends only the first: for each needle position it records the next position to its left carrying the same value, which is `m` positions and therefore `m log m` bits, and it indexes nothing over the alphabet because it tests equality against the `m` values the needle holds. The good suffix rule is not available here at any price. It needs a contiguous right to left comparison to know which suffix matched, and this engine probes an arbitrary subset in an arbitrary order, so adopting it would mean giving up probe placement, which is the thing being steered. Nothing here implements either.

## Running the graders

```sh
maint/engine/build_engine.sh
```

The script configures, builds named targets and runs the graders. `test_steer` grades the ordering against `anchor_sift_naive` at seven needle lengths, measures the probe reduction, carries a negative control that orders the commonest symbol first and must read more, checks the exact dispatch against four fields whose answers are derived by hand, asserts that the widest scan engine the machine carries actually ran, and grades arms, eyes and coarms on five fields: the synthetic skewed field, the three `bench_corpora` kinds, and the license text.

Two drivers in `src/engine/c/bench/` do not compile with MSVC and the script does not build them. `bench_dispatch.c:105` uses `CLOCK_MONOTONIC`, which is POSIX. `bench_lattice.c:500` onward does not parse. Both predate this work and neither is on the path the engine needs.

## What is not checked here

The planner costs are stated in the header as worst cases and are not measured. `anchor_steer_sweep_probes` performs `wanted * needle_len^2 * max_length^2 * alignments / sample_stride` byte comparisons at worst. One factor of `max_length` counts the lengths enumerated and the second comes from scoring, since a candidate of length L costs up to L comparisons and those sum to about `max_length / 2`. `anchor_steer_probe_fits` rejects shapes that do not fit, so the real count sits below that figure.

`sample_stride` is the control and no default is recommended, because the crossover was not measured.

Reads are the wrong statistic for a contiguous eye and the table above inherits that. A step-1 eye of length L is one wide load that the machine may satisfy in a single memory transaction, and counting L reads charges it for work done once. Short-circuiting also makes the trip count vary, and a varying trip count costs a mispredicted branch per alignment. The branchless free-order arm exists for that reason (`src/engine/c/portable/anchor_sift.h:106-110`). An eye evaluated branchlessly trades L reads for one predictable branch. Deciding whether eyes ever pay needs a cycle measurement, and none was taken.

The exact dispatch was graded against eleven fields swept from flat to concentrated, agreeing with the double form of the same rule on all eleven. That shows the change is harmless. It does not show it was needed, because no field was constructed whose double-form verdict falls inside the old series error of the threshold. Until one is, the improvement is argued from the algebra and not demonstrated.

The dispatch comparison needs headroom above `total^2`. Its right side reaches `85 * distinct * sum(count^2)`, about 2^14.4 times `total^2` at 256 distinct symbols, putting a four gigabyte corpus near 2^79. `AnchorExactInteger` holds 108 limbs of 32 bits, or 3456 bits (`src/engine/c/portable/exact_limbs.h:49`, `src/engine/c/portable/exact_limbs.h:72`), which covers that with room left. No bench exercises a corpus near that size. The headroom is read off the declaration and has not been measured.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
