# The engine's correctness does not depend on its control flow

**Purpose:** Prove that the count is exact for every probe set, that the refinement loop's invariant is its own postcondition, that an arbitrary planner cannot endanger the answer, and that the descent terminates without a depth cap.
**Scope:** `src/engine/c/portable/anchor_steer.h`, `src/engine/c/portable/anchor_steer.c`, `src/engine/c/portable/anchor_sift.h`, `docs/steering.md`

## Contents

1. [The setting](#the-setting)
2. [Theorem 1, soundness](#theorem-1-soundness)
3. [Theorem 2, order independence](#theorem-2-order-independence)
4. [Theorem 3, the loop invariant is the postcondition](#theorem-3-the-loop-invariant-is-the-postcondition)
5. [Theorem 4, the planner may be arbitrary](#theorem-4-the-planner-may-be-arbitrary)
6. [Theorem 5, the descent terminates without a cap](#theorem-5-the-descent-terminates-without-a-cap)
7. [Theorem 6, stopping equals continuing](#theorem-6-stopping-equals-continuing)
8. [Theorem 7, the two exits](#theorem-7-the-two-exits-and-a-machine-that-runs-forever-and-is-never-wrong)
9. [Theorem 8, the descent is within a constant factor of the best probe set](#theorem-8-the-descent-is-within-a-constant-factor-of-the-best-probe-set)
10. [Theorem 9, a Turing complete generator](#theorem-9-a-turing-complete-generator-inside-a-compartment-that-cannot-reach-the-answer)
11. [What is not claimed](#what-is-not-claimed)
12. [Machine checking](#machine-checking)
13. [Prior art, and what is original here](#prior-art-and-what-is-original-here)

## The setting

Let the alphabet be any set carrying equality. No order on it is used, no enumeration of it is used,
and its cardinality is unconstrained.

Fix a corpus `c` of length `n` and a needle `w` of length `m`, with `m` at most `n`. The alignments
are `A = {0, 1, ..., n - m}`. An alignment `t` is an OCCURRENCE when `c[t + j] = w[j]` for every `j`
in `[0, m)`. Write `Occ` for the set of occurrences and `N` for its size. `N` is the quantity the
engine is required to return.

A PROBE `p` is a finite set of offsets `O_p` contained in `[0, m)`, and its predicate is

```
P_p(t)  holds  exactly when  c[t + o] = w[o] for every o in O_p
```

An arm is a probe with one offset, an eye is a probe whose offsets form an arithmetic progression,
and the theorems below use neither fact. A PLAN `S` is a finite set of probes, and its survivors are

```
Surv(S) = { t in A : P_p(t) holds for every p in S }
```

The engine computes `Count(S) = |{ t in Surv(S) : c[t .. t+m) = w }|`, the survivors filtered by the
full compare.

`Surv` and `Count` are defined for EVERY plan, including the empty plan, for which
`Surv(empty) = A`.

## Theorem 1, soundness

**For every plan `S`, `Count(S) = N`.**

*Lemma 1 (necessity).* If `t` is an occurrence then `P_p(t)` holds, for every probe `p`.
An occurrence satisfies `c[t + j] = w[j]` for every `j` in `[0, m)`, and `O_p` is contained in
`[0, m)`, so the required equalities are a subset of the ones the occurrence supplies.

*Lemma 2 (superset).* `Occ` is contained in `Surv(S)` for every plan `S`. Apply Lemma 1 to each probe
in `S`; a conjunction of conditions each satisfied by `t` is satisfied by `t`.

*Proof of Theorem 1.* The set `Count(S)` measures is `Surv(S)` intersected with `Occ`, since the full
compare admits exactly the occurrences. By Lemma 2 that intersection is `Occ`, whose size is `N`. ∎

The proof quantifies over all plans and mentions no property of the probes beyond
`O_p` being contained in `[0, m)`. It uses no order on the alphabet, no dimension, no bound on
`|S|`, and nothing about how `S` was produced. **This is the theorem that makes every later one
cheap.**

## Theorem 2, order independence

**For any enumeration order of `S`, the computed count is the same.**

*Proof.* `Surv(S)` is defined by a universally quantified condition over a set, and set membership
carries no order. An implementation evaluating the conjunction with short circuiting executes a
different sequence of comparisons under a different order, and the truth value of a conjunction is
invariant under permutation of its operands. ∎

*Obligation on the implementation.* The step from "the conjunction is invariant" to "the program is
invariant" requires that evaluating `P_p` have no side effect that a later probe reads. That is a
property of the code and not of the mathematics, and it is the reason to test order as a permutation
null instead of assuming it.

## Theorem 3, the loop invariant is the postcondition

Let `S_0, S_1, S_2, ...` be any sequence of plans, finite or infinite. This is the refinement
trajectory, and nothing is assumed about how one plan follows another.

**For every `i`, `Count(S_i) = N`.**

*Proof.* Each `S_i` is a plan. Apply Theorem 1. ∎

The predicate `Count(current plan) = N` is what the refinement loop is required to establish, so it
is the loop's postcondition. Theorem 3 says it holds at every point of the loop, including before the
first iteration, where the plan is empty. **The invariant and the postcondition are the same
predicate.**

That identity is the whole explanation of the anytime property. An ordinary loop carries an invariant
strictly weaker than its postcondition, and termination is what closes the gap; the loop must finish
before its promise is true. Here there is no gap to close, so termination establishes nothing that is
not already established, and interrupting the refinement at any instant and running the sweep returns
`N`.

## Theorem 4, the planner may be arbitrary

Let `f` be any PARTIAL function from plans to plans. `f` is not required to be total, not required to
be computable, and not required to terminate on any input.

**Along the trajectory `S_{i+1} = f(S_i)`, every defined `S_i` satisfies `Count(S_i) = N`. If `f`
diverges at step `k`, then interrupting and sweeping with `S_k` returns `N`.**

*Proof.* Theorem 1 is quantified over all plans. Its statement contains no reference to definedness,
computability, or termination of anything, so no such hypothesis can be needed to discharge it. Each
defined `S_i` is a plan; apply Theorem 1. For the divergent case, `S_k` is a plan; apply Theorem 1. ∎

This is the theorem worth stating to anyone who has read the guide's claim about halting. It says the
planner slot accepts an arbitrary computation, including one that decides an undecidable question and
therefore never returns, without the answer depending on it. The undecidability is real and it is
confined to the planner, where nothing reads its result as a precondition for correctness.

## Theorem 5, the descent terminates without a cap

The descent places at level `i` a probe minimizing the survivor count, and stops when the minimum
attainable equals the count it already has. Define the variant

```
V(i) = |Surv(S_i)|
```

which is a non-negative integer.

**`V` strictly decreases at every level that does not stop, so the descent performs at most `|A|`
levels and terminates. No depth bound is required for this.**

*Proof.* At a level that does not stop, the chosen probe attains a survivor count strictly below the
current one, so `V(i+1) < V(i)`. A strictly decreasing sequence of non-negative integers is finite,
and its length is at most `V(0) = |A|`. ∎

**The depth constant is a resource limit and not the termination argument.**
`ANCHOR_STEER_ANCHORS` bounds the work and the register footprint. Theorem 5 shows the recursion is
well founded on a measure the field supplies, so removing the constant leaves a terminating descent.

*Corollary, self-correcting depth.* The number of probes placed is decided by the field. A field
offering more discrimination admits more strictly decreasing levels before the stop condition fires,
and a field offering less admits fewer. The descent discovers its own depth instead of being told
one, and the stop condition is the correction: the recursion measures whether it is still making
progress and halts itself when it is not.

*And the two guarantees are independent.* Theorem 5 says the descent cannot run forever. Theorem 3
says that if it did, the answer would still be exact. Either one alone suffices for correctness, and
the engine holds both.

## Theorem 6, stopping equals continuing

Let `C_i` be the candidate set enumerated at level `i`, and suppose the enumeration is NON-INCREASING,
meaning `C_{i+1}` is contained in `C_i`.

**If the stop condition fires at level `k`, it would fire at every level below. Stopping is therefore
equivalent to continuing, and destroying the levels below costs nothing.**

*Proof.* The stop condition at level `k` says the minimum over `C_k` of `|Surv(S_k + p)|` equals
`|Surv(S_k)|`. Since no probe can increase the survivor count, the minimum being equal means every
`p` in `C_k` leaves `Surv(S_k)` unchanged. Continuing would place such a probe, leaving
`Surv(S_{k+1}) = Surv(S_k)`. Every element of `C_{k+1}` lies in `C_k` and therefore leaves that same
survivor set unchanged, so the minimum over `C_{k+1}` again equals the whole survivor count and the
condition fires. Induction on the level. ∎

*The precondition is exactly non-increasing enumeration.* Shrinking is safe, by the containment step
above. Growing is not, because a candidate absent from the level that fired has never been shown to
leave the survivor set unchanged. Any edit making the candidate set depend on the level must preserve
containment or this theorem is void.

*Scope.* The argument is exact over the population the planner examines. Where the planner samples,
the theorem holds of the sample, and its transfer to the full field carries the sampling
qualification and nothing stronger.

## Theorem 7, the two exits, and a machine that runs forever and is never wrong

Theorem 6 says a fired stop condition stays fired while the candidate set is non-increasing. A
descent that has stopped therefore has exactly two exits, and the second is where the engine stops
being a search and starts being an instrument.

**Exit one, end the program.** The question class is exhausted. Nothing in `C_k` prunes, nothing
below will, and the plan in hand is correct by Theorem 1.

**Exit two, ask a slightly different question.** Enlarge the candidate set. Theorem 6's precondition
is non-increasing enumeration, so its proof does not cover growing the class, and that omission
points the useful way: a candidate absent from the class that fired has never been shown to
leave the survivor set unchanged, so it may prune.

Formally, let `C^(0) ⊆ C^(1) ⊆ C^(2) ...` be an ascending chain of question classes, each a set of
probes. The engine descends inside a class until the stop condition fires, then moves to the next
class and descends again. Each class is a set of necessary conditions, so Theorem 1 covers every plan
the engine can hold in any class, at any moment.

**The total productive work is bounded no matter how many times the question changes.** Theorem 5's
variant is the survivor count, and it does not reset when the class changes. Every level that places
a probe strictly decreases it, across all classes, at most `|A|` levels in the whole run can
prune. Changing the question cannot buy unbounded work; it can only buy up to `|A|` productive levels
in total.

So the outer loop over classes may be infinite while the productive work is finite. An unproductive
class costs one stop condition to detect, and by Theorem 3 the engine may be interrupted in any
class, at any level, productive or not, and the count is `N`.

**That is a machine that runs forever and is never wrong.** It refines while there is refinement to
be had, widens the question when a class runs out, never recurses to infinity productively because
the survivor count forbids it, and carries a correct answer at every instant of an unbounded run. The
non-halting is real, the correctness is proved, and the two do not trade against each other.

*What a different question can be.* Widen the probe shapes admitted. Move the probe's second end from
the needle into the corpus, which changes the question from "does this match the needle" to "does this
carry the needle's internal structure", and which stays inside Theorem 1 because such a probe is still
a necessary condition of an occurrence. Re-encode the alphabet under a bijection, which changes
nothing and is the null. Each is a class in the chain, and the ascent through them is the engine
asking better questions about an object it is not allowed to get wrong.

## Theorem 8, the descent is within a constant factor of the best probe set

Theorems 1 through 7 say correctness is free and termination is guaranteed. No theorem yet says the
descent chooses WELL. A planner may be arbitrarily bad without endangering the answer, which leaves
open how bad this particular planner is. It is not bad, and the bound is immediate once the objective
is named correctly.

For a probe `p`, let `R_p = { t in A : P_p(t) fails }`, the alignments it refutes. For a plan `S`
define

```
f(S) = |A| - |Surv(S)| = | union of R_p over p in S |
```

the count of alignments refuted by at least one probe in `S`.

**`f` is a coverage function**, being the cardinality of a union of fixed sets indexed by the chosen
probes. So `f` is monotone, `f(empty) = 0`, and `f` is submodular: for `S` contained in `T` and any
probe `p`, the marginal gain of `p` over `T` is at most its marginal gain over `S`, because every
alignment `p` newly refutes over `T` is one it newly refutes over `S`.

**The descent is the greedy algorithm on `f`.** Each level places the probe attaining the fewest
survivors, and that is the probe of greatest marginal gain in `f`. The stop condition fires exactly
when the greatest marginal gain is zero, which is where greedy halts of its own accord.

**Therefore the descent's `k` probes refute at least `1 - 1/e` of what the best `k` probes refute**,
by the guarantee of Nemhauser, Wolsey and Fisher for a monotone submodular function under a
cardinality constraint. That constant is about 0.632, and by Feige's hardness for maximum coverage no
polynomial-time planner improves it for coverage functions unless P equals NP.

So the two statements sit together. **Correctness does not depend on the planner at all, and the
planner still lands within a constant factor of optimal, with that constant at the limit for
polynomial time.** The first is Theorem 1 and the second is this one, and they are about different
things: one about the answer, one about the cost of getting it.

**The honest gap.** `f` counts refutations and the engine's cost is reads. Under short circuiting a
refuted alignment costs reads up to the position of its refuting probe in the evaluation order, so
the coverage bound governs refutation and transfers to reads only with an accounting of the order.
Theorem 2 says the order does not affect the answer. It does affect the cost, and that is the next
thing to prove instead of a thing proved here.

## Theorem 9, a Turing complete generator inside a compartment that cannot reach the answer

The engine as built TERMINATES. The machine described here is PRODUCTIVE, which is a different
property: it need never terminate, and every finite prefix of its output is computed in finite time.
Type theory keeps the two apart, inductive definitions carrying termination and coinductive ones
carrying productivity, and a productive process is the right shape for something that runs forever
and emits as it goes.

**The construction.** Let `G` be an arbitrary Turing complete generator. `G` emits candidate probe
specifications, it may run forever, it may be adversarial, and nothing constrains what it computes.
Between `G` and the plan sits a TOTAL CHECKER: a candidate is admitted only if its offsets lie inside
`[0, m)` and it compares against the needle's own byte at each offset. That check is finite,
decidable, and already implemented as `anchor_steer_probe_fits`.

**Every admitted candidate is a necessary condition, so Theorem 1 applies to the plan at every
instant, so the machine emits a correct count continuously while `G` runs forever.**

This is the untrusted generator behind a trusted checker, the pattern of proof-carrying code and of a
solver emitting a certificate that a small verified program checks. The generator gets to be
arbitrary precisely because nothing it produces is believed without the check.

**Streaming to itself.** The generator's input can be the engine's own output: the census, the
surviving alignment set, the lag profile `A(d)`, and the reads per alignment that the companion
document identifies as an arrangement measurement. The loop closes. The engine measures the object,
generates new questions from that measurement, probes, and measures again.

The feedback is safe for the same reason the planner is. By Theorem 1 the plan's contents cannot
affect the count. A feedback path producing useless or actively bad questions therefore costs only
speed. **A self-referential input loop is exactly as safe as an arbitrary planner, which is to
say completely.**

**And the generator cannot buy unbounded productive work.** Theorem 5's variant is the survivor
count, it never increases, and it does not reset when `G` changes the question. across an infinite
run, driven by a Turing complete generator feeding on its own output, at most `|A|` probes can ever
prune. Everything beyond that is `G` spinning, each spin detected by one stop condition, with the
answer correct throughout.

**The honest limit, and everything above turns on it.** The count is determined by the corpus and the needle
before the machine starts. `G` cannot change it, cannot delay it, and cannot make it depend on
anything `G` computes. So the Turing completeness is real and it is confined to a compartment that
provably cannot reach the result. **Undecidability cannot be smuggled into the answer, because the
answer was fixed before the undecidable question was asked.** What Turing completeness buys is reach,
which questions can be posed, and speed, how quickly the survivors fall. It never buys correctness,
and by Theorem 1 there was none left to buy.

## What is not claimed

**The engine is not Turing complete, and that is deliberate.** The sweep is a bounded loop over `A`.
The descent terminates in at most `|A|` levels by Theorem 5, under a compile-time cap in the present
code. Both are primitive recursive, every primitive recursive function is total, and the class cannot
express the Ackermann function. No claim of universality is made or needed.

**The halting problem is untouched.** It is undecidable, it remains undecidable, and nothing here
bears on it. Theorem 4 says the system's correctness does not depend on any halting question, which
is a statement about this system. A reader who takes it as a statement about computability has taken
the wrong one.

**Liveness is not guaranteed.** If a planner diverges and nothing interrupts it, no answer is
produced. Theorem 5 rules this out for the descent as built, and Theorem 4 permits a planner for which
it is not ruled out. **The system can fail to answer. It cannot answer wrongly.** That is the honest
summary of all six theorems and the sentence to quote if only one is quoted.

**Theorem 1 says nothing about speed.** Every plan is correct and plans differ enormously in cost. The
empty plan is correct and sends every alignment to the full compare. Correctness is not a currency the
planner holds, and speed is the only one it can spend.

## Machine checking

The six statements are first order over finite sets, with one quantifier over partial functions in
Theorem 4. A Lean 4 or Coq development would carry the alphabet as a type with decidable equality,
the corpus and needle as vectors, a probe as a finite set of bounded offsets, and a plan as a finite
set of probes. Theorems 1 through 3 are short: Lemma 1 is a subset argument on index ranges, Lemma 2 a
conjunction introduction, Theorem 1 an intersection identity, and Theorems 2 and 3 are corollaries.

Theorem 4 repays the effort most, because its content is the quantifier. Model the planner as an
arbitrary function into an option type, or the trajectory as a coinductive stream, and state that the
observable is constant along it. A development in which the planner is an opaque parameter, with the
count proved equal to `N` regardless, is a machine-checked statement that an arbitrary embedded
computation cannot corrupt the result.

Theorem 5 is a well-founded recursion on a natural number measure, which both assistants support
directly, and it is the statement that lets the depth constant be presented as a budget instead of as
a proof obligation.

## Prior art, and what is original here

None of the machinery below is new. The theorems are elementary once the setting is written down, and
the content of this document is that THIS construction satisfies them, not that the notions are
invented here. Each name is given with what it supplies.

**Robert W. Floyd**, *Assigning Meanings to Programs*, Proceedings of the American Mathematical
Society Symposia in Applied Mathematics, 1967. The variant function: attach to each loop a quantity
in a well-ordered set that strictly decreases, and termination follows. Theorem 5 is that argument
with the survivor count as the variant, and the observation that the engine already computes it.

**C. A. R. Hoare**, *An Axiomatic Basis for Computer Programming*, Communications of the ACM 12(10),
1969. The `P{Q}R` notation, the loop invariant, and the separation of partial correctness from
termination. Hoare's system establishes partial correctness for while-programs, and the gap between a
loop's invariant and its postcondition is the gap termination ordinarily closes.
Theorem 3 says this engine has no such gap. That framing is Hoare's; the observation that the gap is
empty here is what this document adds.

**Alan M. Turing**, *On Computable Numbers, with an Application to the Entscheidungsproblem*,
Proceedings of the London Mathematical Society, 1936. The undecidability of halting. Nothing in this
document bears on it, and the section on what is not claimed exists to keep that boundary visible.

**Wilhelm Ackermann**, 1928, for the total computable function that is not primitive recursive. It
witnesses that the class this engine sits in is a proper subclass.

**Thomas Dean and Mark Boddy**, *An Analysis of Time-Dependent Planning*, AAAI 1988. Anytime
algorithms: a computation interruptible at any point, returning a result whose quality improves with
time. **Stuart Russell and Shlomo Zilberstein**, 1991, for the distinction between INTERRUPTIBLE
algorithms, which hold a usable result throughout, and CONTRACT algorithms, which are told the
deadline in advance. This engine is interruptible in their sense, and Theorem 3 is the unusual case:
the result quality does not improve with time, because it is exact from the first instant. Time buys
speed alone. An anytime algorithm whose answer is already correct at `t = 0` is a degenerate point of
their framework, and it is the point this construction occupies.

**George L. Nemhauser, Laurence A. Wolsey and Marshall L. Fisher**, *An Analysis of Approximations
for Maximizing Submodular Set Functions*, Mathematical Programming, 1978. The greedy algorithm on a
monotone submodular function under a cardinality constraint attains `1 - 1/e` of the optimum.
**Uriel Feige**, 1998, for the matching hardness: no polynomial algorithm beats `1 - 1/e` for maximum
coverage unless P equals NP. Theorem 8 is their result applied to a coverage function the engine was
already maximizing without saying so.

**Christian Coester, Elias Koutsoupias and Marek Zbysiński**, *The k-server conjecture is true*,
arXiv:2609.15979v1, 14 September 2026. Not prior art for anything here, and listed because it
prompted Theorem 8 and because its method matches what section 7 of the companion document proposes.
Their abstract states that the work function is represented as a matrix encoding all feasible paths,
that the minimum and addition of optimal-cost algebra become addition and multiplication of formal
expressions, and that each work function value is the determinant of `k` columns. A `k`-subset's
value carried as a determinant, with a tropical objective lifted into ordinary algebra so determinants
become available, is the same move the census-matrix proposal makes. Read state: abstract read in
full from the listing page, body not read, and the result is two days old and unrefereed at the time
of writing. **Elias Koutsoupias and Christos Papadimitriou**, *On the k-server conjecture*, Journal of
the ACM, 1995, for the `2k - 1` bound the new paper closes, and **Mark Manasse, Lyle McGeoch and
Daniel Sleator**, STOC 1988, for the conjecture itself.

**Thierry Coquand**, *Infinite Objects in Type Theory*, 1994, for guarded corecursion and the
separation of PRODUCTIVITY from TERMINATION. A productive process may run forever while every finite
prefix of its output is computed in finite time, and Theorem 9 is that shape. **George C. Necula**,
*Proof-Carrying Code*, POPL 1997, for the untrusted producer behind a small total checker. Theorem 9
uses that architecture to admit an arbitrary generator without believing it.

**Brenda S. Baker**, *A Theory of Parameterized Pattern Matching: Algorithms and Applications*, STOC
1993, and the journal version in the Journal of Computer and System Sciences, 1996. Parameterized
matching, where two strings match if one is obtained from the other by a bijective renaming of
parameters, introduced for finding duplicated source code. Theorem 7's second exit reaches that
problem class by moving a probe's second end into the corpus, and Baker's is the prior formulation of
the target.

**What this document contributes**, stated narrowly so it can be checked. The identification of the
survivor count as a Floyd variant for this descent, which makes the depth constant a budget instead
of a termination argument. The observation that the loop invariant and the postcondition coincide,
which makes the anytime property fall out instead of being engineered. Theorem 4's quantifier over
partial planner functions. Theorem 6, that a fired stop condition stays fired under non-increasing
enumeration. And Theorem 7, that an unbounded ascent through question classes carries bounded
productive work, because the variant does not reset when the question changes.

Read state: every source above is cited from knowledge and from the search results listed, with no
paper read in full for this document. Bibliographic fields were checked against the search results
and the theorem numbers deliberately are not given, because those were not verified against a copy.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
