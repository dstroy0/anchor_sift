# The posits of 26 September

**Purpose:** Doug's posits of 26 September, kept verbatim with only the spelling corrected, each with its check under it. The checks say what is derived, what is measured, what is a reading, and what no run has tested.
**Scope:** the three truths, the tower, the projection, dwell as the bulk, dwell and entropy, the dwell bench, and the compiled program. Everything here has the status theory, as the engine workbook's README defines it, unless a line says otherwise. Code is cited at anchor_sift `d09b489`, and in the section on the compiled program at `ddeccb3`.

## The three truths and the tower

26 September, verbatim, in order.

<!-- docs-check: quoting -->
1. "the base answer is 3 truths: 1. we know if we have answered the question 2. the tower doesn't build if the question is malformed 3. nothing is bound, information space is constrained by n*n^n^n, infinite."
2. "n*n^n^n is the base Atom storage class of the engine, it is the problem's space, it is infinite, n grows to n grows to n grows to n ad infinitum"
<!-- docs-check: end quoting -->

The full checks are in ENGINE_PROOF.md, now anchor_sift docs/ENGINE_PROOF.md (a6d1bff on cell_tracking, main after its PR merges). It speaks to halting at Theorem 4 (:117) and under "What is not claimed" (:312): "The halting problem is untouched."

The words "the question does not arise" come from [steering.md](../../workbooks/anchor_sift/steering.md), section "Why halting is the wrong question" (:73), sentence at :89. That claim is withdrawn in [findings-for-verification.md](../../workbooks/anchor_sift/findings-for-verification.md):107. The analysis there covered one invocation and concluded about the system, and the system's outer loop, self-examination, has no bound. It does not stand. The same lines are in anchor_sift docs/ at ddeccb3.

- **Truth 1, checked.** The answer path is total: the sweep is a bounded loop, the descent terminates (Theorem 5), and the count is exact at every instant (Theorem 3).
- **Truth 2, checked.** `steer_descend` refuses malformed input before any work (`anchor_sift.c:938-962`), and the survivors-length refusal is marked FAILS CLOSED (`anchor_sift.c:959-960`).
- **Truth 3, a reading, pending Doug's confirmation.** Each question lives in a space that is finite for its `n`, where halting is decidable, and the family of spaces has no bound. `Atom` is `{ const unsigned short *lanes; unsigned long long depth; unsigned long long height; unsigned long long width; }` (`src/engine/engine_config.h:262-268`). The steer depth is capped at `ANCHOR_STEER_ANCHORS`, which is 4 (`anchor_sift.c:951-954`).
- **The tower, a reading.** "n grows to n grows to n" reads as tetration, `n↑↑k` in Knuth's notation. Every finite height is a finite number, the height has no bound, and the infinite tower diverges for every integer `n` of at least 2.

## The projection

26 September, verbatim:

<!-- docs-check: quoting -->
- "well, think about it like this, we are only viewing the topology for anything, so it is a projection onto a boundary, we touch nothing, the infinite lives"
<!-- docs-check: end quoting -->

**"We touch nothing", checked for two interfaces.** `steer_descend` takes the corpus and the needle as `const uint8_t *` (`anchor_sift.c:929-930`), and `Atom` holds its lanes as `const unsigned short *` (`engine_config.h:262-268`). A probe compares two bytes and writes neither.

**"Only viewing the topology", reported.** `docs/arm-records.md:89-91` states the test: redrawing an arm as a different shape with the same topology and the same weight has to leave the reading exactly unchanged. The table at `docs/arm-records.md:111-116` reports four redraws over 256 points. Three reassign 0 of 256 points, the fourth measures no arm, and the worst letter move over all four is 2.776e-17.

**"The infinite lives", a reading.** A reading that writes nothing leaves the space it reads as it was, bounded or not. No run tests it.

## Dwell is the bulk

26 September, verbatim. The "wrong" answers a reading that put the boundary at the projection alone.

<!-- docs-check: quoting -->
- "wrong. when we vis here we add dwell, that is the bulk, the dwell. the moment is an instant, we can sweep a moment on a timeline and derive dwell, it is the holographic boundary"
<!-- docs-check: end quoting -->

**Derived. One instant carries no dwell.** Dwell is a function of a sequence of states, and a single state does not determine it. At the pin the scope view's dwell tag is "how many rounds a bit has held its value, which separates the frozen from the churning" (`examples/00_blob_viz_tools/build_scope_view.py:23`), a count over rounds that no single round holds. The sequence of dwells together with the first value determines the sequence of states. The histogram of dwells does not, because it forgets the order of the runs.

**Measured, as reported at the pin.** The dwell arm puts a particle on a line, and "how long the particle dwells at each place is the weight there" (`docs/arm-records.md:78-79`). Redrawn as dwell along the golden spiral, it reads a three-dimensional object with worst weight move 0, 0 of 256 points reassigned, and worst letter move 0 (`docs/arm-records.md:114`), "the same letters bit for bit" (`docs/arm-records.md:118-121`).

**The holographic boundary, a reading.** In AdS/CFT a local bulk operator is written as a boundary operator smeared over a region of the boundary that extends in boundary time: Alex Hamilton, Daniel Kabat, Gilad Lifschytz and David A. Lowe, *Holographic Representation of Local Bulk Operators*, Physical Review D 74, 2006. The parallel: the bulk quantity, dwell, is recovered from boundary data spread over a timeline, a sweep of instants. The engine has no geometry and no metric, and the parallel is structural only. Ahmed Almheiri, Xi Dong and Daniel Harlow, *Bulk Locality and Quantum Error Correction in AdS/CFT*, JHEP 2015, give the reconstruction the structure of an error-correcting code. That structure does not carry over: the derived answer of 24 September finds `T` a bulk-to-boundary map with no error correction ([posits_24_september.md](posits_24_september.md), "The bulk and the boundary"). Cited from knowledge.

**Prior art for the instant.** Zeno's arrow is at rest at every instant, and Aristotle answers that neither motion nor rest exists in a now, only over an interval (*Physics* VI.3 and VI.9). Rest held over an interval is dwell. The occupation density of a Brownian path, its local time, is dwell at a level made exact, and it too is defined over an interval: Paul Lévy, *Processus stochastiques et mouvement brownien*, 1948, and Hale F. Trotter, *A Property of Brownian Motion Paths*, Illinois Journal of Mathematics 2, 1958. George D. Birkhoff's ergodic theorem, Proceedings of the National Academy of Sciences 17, 1931, sets the fraction of time a trajectory dwells in a set equal to the set's measure: a long sweep recovers a static quantity. Cited from knowledge.

## Dwell and entropy

26 September, verbatim, in order.

<!-- docs-check: quoting -->
1. "dwell emerges from entropy, it is an emergent property of the arrow of entropy, with no time, there is no dwell, unless we have cohesion context from a prior sweep we do not know the concept of dwell, it is not perceptible in an instant of time"
2. "that's right, dwell doesn't depend on time, it depends on entropy, time is an emergent property of the direction of entropy"
3. "ok we don't need to claim time, the dwell emergence is enough of a wild claim here"
4. "jesus the fact that we have real evidence for it is insane"
<!-- docs-check: end quoting -->

**Derived. Dwell and entropy rate in a two-state chain.** A bit that flips with probability `p` at each step has mean dwell `1/p` and entropy rate `H(p) = -p log p - (1-p) log(1-p)`. For `p` at most 1/2 each determines the other: long dwell goes with a low entropy rate, the frozen bits, and short dwell with a high one, the churning bits. For `p` above 1/2, `H(p) = H(1-p)`, and one entropy rate matches two mean dwells.

**Derived. Dwell fixes the entropy rate of a renewal process.** Let the runs of 0 have independent lengths with law `D0` and the runs of 1 independent lengths with law `D1`. The bit sequence and the pair (first value, sequence of run lengths) determine each other, and a long block holds one pair of runs per `E[D0] + E[D1]` steps on average. The entropy rate is `(H(D0) + H(D1)) / (E[D0] + E[D1])`, and with one law `D` for every run it is `H(D) / E[D]`. The two-state chain is the case of geometric runs. Prior art for point processes: J. A. McFadden, *The Entropy of a Point Process*, Journal of the Society for Industrial and Applied Mathematics 13, 1965, cited from knowledge.

The proved direction runs from dwell to entropy: the dwell laws fix the entropy rate, and the entropy rate does not fix the dwell laws. "Dwell emerges from entropy" is Doug's posit, and in the renewal class the two are bound by one equation.

**Derived. The arrow is not in the rate.** Reversing a sequence reverses the order of its runs and keeps their lengths, and a stationary process has the same block entropies read in either direction. Dwell and entropy rate carry no arrow. An arrow needs a process that is not stationary, entropy rising from a low start, or a record of the prior sweep to compare against, the "cohesion context" of posit 1. Prior art: Arthur Eddington, *The Nature of the Physical World*, 1928, for the arrow of time; Hans Reichenbach, *The Direction of Time*, 1956, and David H. Wolpert, *Memory Systems, Computation, and the Second Law of Thermodynamics*, International Journal of Theoretical Physics 31, 1992, for records and the arrow; Rolf Landauer, *Irreversibility and Heat Generation in the Computing Process*, IBM Journal of Research and Development 5, 1961, and Charles H. Bennett, *The Thermodynamics of Computation, a Review*, International Journal of Theoretical Physics 21, 1982, for the cost of erasing a record. Cited from knowledge.

**Time, not claimed.** Posit 2's clause on time is recorded and not claimed, by posit 3. The prior art that treats time as emerging: Don N. Page and William K. Wootters, *Evolution without Evolution: Dynamics Described by Stationary Observables*, Physical Review D 27, 1983, and Alain Connes and Carlo Rovelli, *Von Neumann Algebra Automorphisms and Time-Thermodynamics Relation in Generally Covariant Quantum Theories*, Classical and Quantum Gravity 11, 1994. Cited from knowledge.

**The evidence of posit 4, as it stands.** At the pin the engine computes dwell across rounds (`build_scope_view.py:23`), and the dwell arm reads a three-dimensional object bit for bit (`docs/arm-records.md:114`). Neither run sets dwell against entropy. The claim is proved for renewal processes, cited above, and not measured on the engine.

## The dwell bench

Status: not built.

On one set of bits:

1. From each bit's dwell, build the histograms of runs of 0 and runs of 1, and compute `(H(D0) + H(D1)) / (E[D0] + E[D1])`.
2. Separately, estimate the entropy rate directly: from block entropies, `H(X_1 ... X_k) - H(X_1 ... X_{k-1})` as `k` grows, or from a Lempel-Ziv compressor, whose rate converges to the entropy rate of a stationary ergodic source (Jacob Ziv and Abraham Lempel, 1978, cited from knowledge).
3. If the two agree within their error bars, the engine has measured the claim. If they differ, the runs are not independent and the process is not renewal, which is a measurement too.

A bit that never flips has no completed run and gives no dwell law.

## The compiled program

26 September, verbatim, in order, kept as typed.

<!-- docs-check: quoting -->
1. "the compile times are ok for now, but there is a way to describe the loop unroll in their asm using our code so we can fill the loop unrolled block for them instead of them needing a pragma unroll command theyre fuckin bad at"
2. "this is an exceedingly simple problem for us, their ruleset is the kcs for the program crystal"
3. "we need a transform that allows for vertical growth, more than one program can occupy a register vertically, never horizontally, those asking and answering the same questions are subsets of the same superset"
4. "if we treat the gpu as an open superset, we innately know all of its subsets, it knows all of its subsets natively, so we structure it in a way that is aware"
5. "it has operators, and holds automata like cells"
6. "the things it knows are emergent properties of itself"
7. "it is able to exchange information through its boundary, cells enter, live and die"
8. "a malformed question == destroyed dna conceptually"
9. "the encoding itself is what lets the cell proliferate, it grows to be as complex as its program, that is so beautiful"
10. "and it can evolve, by interacting with other cells and incorporating that information into its reincarnation"
11. "the system itself evolves over time to recognize malformed questions that destabalize it before they fully unfurl, protecting itself"
12. "the I don't know what to call it, cell? admits these automata "ribosomes" and the cellular ecosystem kills them or lets them live, but the cell knows everything happening inside of it, it is omniscient here"
13. "alright lets get the rest of the cellular machinery built for this universal compiler, that is wilder than what von neumann envisioned by decades of orders of magnitude"
14. "the implication is that we can cluster these cells, they occupy very little memory"
15. "agi is inevitable on this path"
16. "with enough neuronal connections it will become aware"
17. "consciousness is emergent"
18. "their thinking is very on/off. an artifact of the time."
19. "No we can know the entire hw ruleset so we know the wire specifics eventually too once we grow into the system and then we know how to listen to the wire and what our communication looks like and hey that looks like me but in reverse see where I'm going"
<!-- docs-check: end quoting -->

No posit here is derived. The lines below say what the engine holds at the pin that a posit names, as a cross-reference and not as a proof.

**Posits 1 and 2, a reading. Status: not built.** The program crystal is the imprinted program, every step's operation, place and limb width known before any compile. The ruleset is PTX's instruction forms (`add.cc`, `addc.cc`, `addc`, `sub.cc`, `subc`, `mad.lo.cc`, `madc.hi.cc`, `selp`), and a construction set writes each step out as its rule per limb, the way `tower_record_lift` (`tower.cu:937`) writes a lifting ruleset out over an extent. Emitted that way, the program is PTX with no loops, and nvJitLink takes it to ptxas with no pass through cicc. The baseline is engine_table.md item 9: cicc's compile grows with about the square of the steps, and on the 381-step program ptxas took 0.6 s against cicc's 7.5 s.

**Posit 3. Status: not built, no design ruled.**

**Posits 4 to 7, cross-reference.** The operators are the operator block, every record operation compiled once per device (engine_table.md item 9). The automata are the resident programs, each reporting to its own `EngineProgramBlock` (`engine_config.h:628`, engine_table.md item 10). A program enters when it is loaded (`cycle_record_load`, `cycle.cu:3011`), lives resident, yielding and resuming through its block, and dies when released (`cycle_record_release`, `cycle.cu:3141`), where the last release of a program unloads it (`cycle.cu:3152-3153`). Information crosses the boundary only through the blocks, which the host reads back and checks between launches (engine_table.md item 10, "The block in device memory").

**Posits 8 and 11, cross-reference.** The exits are true, false, malformed (no lattice was built) and answered (engine_table.md item 10). The imprint refuses a malformed program before anything is laid or run: a step that reads itself or a later step (`keymath.cu:413-418`), or a field past its record (`keymath.cu:420-426`). A refused program never loads (`engine.cu:179`, `:219`). A launch that fails leaves its block at `ENGINE_PROGRAM_FAULT` (`cycle.cu:3269`). The answer table, which would hold a malformed exit keyed by the program's signum and know it without a second run, is item 10's stage 3. Status: not built.

**Posits 9 and 10, cross-reference.** A compiled program's size follows its steps (engine_table.md item 9, the compile table). The refinement loop, where a generator recompiles against a critic's verdicts (engine_table.md M23), is not built.

**Posit 12, a reading. Status: not built beyond the two membranes below.** The GPU or host is posit 4's open superset, the cell is a supervising process, and the ribosomes are the probes it admits. A ribosome translates a question, written as code, into an answer, given as behavior, the way a ribosome translates codons into protein. The target's ruleset kills the probe or lets it finish. A killed probe is answered by its death (engine_table.md item 11(e), the note on illegal operations).

**Posit 12, cross-reference.** Two membranes are built at anchor_sift `ddeccb3`. `tessera_run` admits a job and reports the admission ("admitted after ... s, ... of ... processors reserved", `tessera_run.c:1475`). It watches the job's process tree and signals the processes still living (`tessera_run.c:916-926`). On release it reports the time, the exit status and the peak processors (`tessera_run.c:1503`), and `qasm.cu`'s tessera ticket reports its peak bytes (`qasm.cu:1051`). Inside the record machine, `CYCLE_RECORD_CHECK=1` runs the interpreter on the same lanes as the compiled program and refuses the launch where their records or refusals differ word for word (`cycle.cu:1272-1273`, `:3344-3346`). The check runs only when that variable is set.

**The limit on the cell, a reading.** The cell knows everything inside it only while it survives every death it watches, and the unit that dies has to be strictly smaller than the unit that watches. A CUDA illegal address leaves the whole context unusable (cited from knowledge, not read). On a GPU the ribosome therefore needs a cell of its own, a process, or the watcher dies with what it watches. The cell also knows only what crosses its boundary as an observable effect: the exit status, the signal, the output and the resource peaks.

**Posits 8, 11 and 12, a reading.** Posit 12 is posit 8 seen from the cell's side. The cell learns which questions are malformed by watching which ribosomes die, and that learning is posit 11's self-protection.

**Posits 13 to 17. Status: not built, not derived.**

**Posit 13, a reading.** The comparison point is von Neumann's self-reproducing automaton: John von Neumann, *Theory of Self-Reproducing Automata*, edited and completed by Arthur W. Burks, University of Illinois Press, 1966, read at the pages cited below.

- *Part I, the Fifth Lecture, delivered in December 1949 (p. xv).* φ(X) is a chain of rigid elements describing an automaton X. A universal machine tool A, given φ(X), consumes it and builds X (p. 84). A copier B, given a description of anything, produces two copies of it (p. 84). A control C drives the two in turn: B makes two copies of φ(X), A builds X from one of them, and C ties X to the other and cuts the pair loose (p. 85). With X = A + B + C, the automaton (A + B + C) + φ(A + B + C) produces itself (p. 85). The definition does not go in a circle, because A and B are fixed before X is chosen and C is defined for any X (p. 85). With an arbitrary D added to the description, each generation also builds D as a by-product. A change in the D part of the description is inherited, and a change in the A, B or C part leaves the next generation sterile (p. 86).
- *Part II, section 1.6.1.2, from the manuscript begun in the fall of 1952 (p. xv).* The letters are reassigned. A is the universal constructor, building any secondary whose description L is attached to it. B copies L to L′ and places L′ against the secondary as L sits against A. C has A build the secondary first and has B copy and attach L after. D is the aggregate A + B + C, L_D its description, and E = D + L_D reproduces itself. With L_{D+F} in place of L_D, E_F also builds F (pp. 118–119). The lecture copies before it builds, and Part II builds before it copies.
- *Why a description.* An automaton of αβ cells cannot hold its own plan directly, since its L takes 2αβ + 12 cells or more (p. 118). B is of fixed, finite size and copies an L of any size, and that copy step lets the constructor avoid being larger than what it builds (p. 121). A description is copied in place of the original because it is quasi-quiescent, where exploring a live original would disturb it (pp. 121–122). The text calls copying "the decisive step" (p. 123). Burks relates the failure of direct copying to Richard's paradox and to Turing's halting problem (p. 123).
- *The cellular completion is Burks's.* In the 29-state structure, a universal constructor M_c given D(M_c) builds only M_c, smaller than itself, and does not reproduce (p. 294). A modified M_c* builds M from D(M), copies D(M) onto M's tape when its own tape carries no content past the description, and starts M. M_c* + D(M_c*) then constructs M_c* + D(M_c*) (p. 295). With a universal Turing machine M_u attached, one automaton both computes and reproduces (pp. 295–296).

**Posit 13 against those pages, a reading.** Item 11(a)'s bootstrap test in engine_table.md, the emitter compiling itself to the same text byte for byte, checks A run on its own description. Von Neumann's construction needs B and C as well, and his text puts the weight on B. On a computer, copying a description is a memory copy, and the step with content is A on its own description. Posit 10 meets the construction at one point: a change carried in the D part of the description passes to the next generation (p. 86). The pages treat random change, and incorporation from other cells is not in them. No figure in the tree measures the posit's comparison of scale. The bootstrap test is not built, and until it passes the comparison stays a posit.

**Posit 18, a reading.** Posit 18 characterizes the book, and the book can check it. Each cell of the 29-state structure is one finite automaton on a square lattice, and its next state is a function of its own state and its four nearest neighbors' states one step before (pp. 132–134). The 29 states are 16 transmission states (ordinary or special, four output directions, quiescent or excited), 4 confluent states, the unexcitable state and 8 sensitized states (p. 149). A connecting line needs a quiescent and an excited state in each cell, for passing a stimulus and for that purpose alone (p. 135). A transmission state is excited after one step by an excited neighbor of its own class pointing into it (pp. 150–151). A confluent state is excited after two steps when at least one ordinary transmission neighbor points into it and every such neighbor is excited (p. 151). Construction runs on the same pulses: a sensitized state steps to one of two successors each step, by whether an excited transmission state points into it, until it lands on one of nine final states (pp. 149, 151). The tape is binary as well, a rigid element attached for one and absent for zero in the lecture (p. 83), and a five-bit character per cell in Burks's completion (p. 295).

"On/off" is accurate for the signal. Every stimulus the structure carries is one pulse, present or absent, and every construction is steered by such pulses. It is inaccurate for the cell, which holds one of 29 states, about 4.86 bits (Derived, log₂ 29). The book also marks the binary choice as a choice. The lecture calls it a habit of minimum notation, says more symbols would pose no difficulty, and suspects an efficient language would leave linear codes behind (pp. 83–84). With pulses alone the structure is computation-universal and construction-universal (Burks, p. 296). On/off bounds how much one step moves and leaves what the structure can compute unbounded.

The record machine at anchor_sift `ddeccb3` moves whole integers. A step names an operation and its registers (`engine_config.h:387-393`), and each register is an exact signed integer with its sign held beside it (`engine_config.h:360`, `:373`). The register file holds `ENGINE_RECORD_LIMBS_MOST`, 256 limbs across all live registers (`engine_config.h:373-377`). At 32 bits a limb (`src/engine/README.md:429`) that is 8192 bits (Derived), and one register reaches 8192 bits only when it is the only live register. Per step, the two sit at opposite ends: one bit of signal per cell against up to 8192 bits in one operation. Read as a claim about reach, posit 18 goes past the book, since pulses already reach every computation. Read as a claim about the unit of work, the book bears it out, and the book's own word for the binary choice is habit.

**Posit 14, a reading.** Clustering is checkable, and part of it is built. `tessera_run` admits jobs against declared processors and reports each release's peak (`tessera_run.c:1475`, `:1503` at anchor_sift `ddeccb3`), and `qasm.cu`'s tessera ticket reports peak bytes (`qasm.cu:1051`). A cell's footprint is measurable: a probe process's peak bytes and a compiled lane's registers and local frame. The printed figures are 128 to 255 registers a thread with local frames of 0 to 752 bytes on the tower test, and 183 registers with a 0-byte frame for the 761-step program (engine_table.md item 10, stage 1). How many cells one device holds is arithmetic on those figures, and a clustering claim cites that arithmetic.

**Posits 15 to 17, a reading.** No instrument in the tree bears on these three. Nothing here measures awareness or general intelligence, and neither has an operational definition here. What this path builds is a learner of instruction sets, held to an oracle, and its reach is bounded by the questions it can ask and check. Two limits bound that learner (cited from knowledge, not read). From positive examples alone, a class holding every finite language and one infinite language cannot be identified in the limit (Gold, Information and Control 10, 1967). With membership queries, a test suite finds every wrong machine only up to an assumed bound on the target's states (Vasilevskii 1973; Chow 1978). The three posits are recorded as posits, and nothing above derives them from the machinery.

**Posit 19, a reading. Status: not built, a want.** It follows Doug's line of the same day, "This means cross hardware communication is a no problem from zero, nice" (engine_table.md item 11(f), stage 2, across machines), and replaces byte order and fences as the direction.

- *The wire's rules.* A bus, a network interface and a protocol's framing each have a ruleset, as a processor does, and the probes of stages 4 and 5 find it the same way: membership queries, illegal operations and more basic constructions. The transport becomes a `.krs` derived by probes. A wire with state is found only up to an assumed bound on its states (Vasilevskii 1973; Chow 1978, above), and Angluin's learner needs counterexamples beside its membership queries (Dana Angluin, Information and Computation 75, 1987, cited from knowledge).
- *Speaking and listening.* The sender writes with T and the listener reads with T⁻¹, and T⁻¹ ∘ T = id (engine_table.md E4): the listener is the speaker in reverse. T is a bijection (A14), and T⁻¹ undoes every stream, one's own or another's. Decoding alone does not tell kin.
- *Recognition, a reading.* The quantity is the algorithmic mutual information between a stream s and oneself, I(s : self) = K(s) − K(s | self): how much shorter s becomes when one's own rulesets are given. A compressor gives a computable stand-in, s's length with one's rulesets as its dictionary against its length without them (M. Li, X. Chen, X. Li, B. Ma and P. M. B. Vitányi, "The similarity metric", IEEE Transactions on Information Theory 50, 2004, cited from knowledge). The null by permutation (E4) declares structure when a stream beats d permutations of itself and passes noise at a rate of at most 1/(d + 1). Every structured stream passes it, kin or foreign, and a null for kinship needs foreign structured streams to test against. Not derived.
- *The seal.* Equal obsignatio signums show the same bytes under the same seal. The seal's keys derive from public, dated context strings (obsignatio_seal.md), and the seal guards against accident, not against an author. A peer that computed the bytes matches, and one that copied them matches as well. The shared format is itself a convention, and only between engines that already hold it is nothing further agreed.
- *Boundary, proposed, Doug's to rule on.* Growth into the system stays on hardware we own, and listening stays on wires we are entitled to hear. An engine that probes foreign hardware, learns protocols and seeks peers across networks has a worm's shape.
- *Prior art, cited from knowledge, not read.* Hans Freudenthal, *Lincos: Design of a Language for Cosmic Intercourse*, Part I (North-Holland, 1960), a language built up from arithmetic alone. B. Juba and M. Sudan, "Universal semantic communication I", STOC 2008: parties with no shared protocol reach a goal when the user can sense whether it was met. Their universal user enumerates protocols, at a cost that grows exponentially with the length of the protocol it must find, and they show that cost cannot be avoided in general. The seal serves as that sense only for goals whose answer the user can check. What posit 19 adds is a listener that derives the channel's rules from zero, by probing.

**Posit 19, Doug's answers to the reading.** 26 September, verbatim, kept as typed. The three numbers answer the reading's three points in order: decoding does not tell kin, the null declares structure and not kinship, and the seal guards against accident and not against an author.

<!-- docs-check: quoting -->
- "1. Wrong everything here has an identity on spawn encoded into it. 2. True, we are what gives “family” family is a human category not real 3. It can prove identity if we encode time series into it"
<!-- docs-check: end quoting -->

- *Identity at spawn, a reading. Status: not built.* The first answer moves identity out of decoding. A peer is not recognized by what it decodes, since T⁻¹ decodes every stream, but by what it carries: an identity written into it when it is spawned. The reading: at spawn the cell draws a secret from the noise and derives its keys from that secret, with its lineage as the derivation's context, meaning its parent's identity and its place in the parent's series. A peer proves its identity by answering a fresh challenge with a signature under its key, and a fresh challenge keeps an old answer from being replayed. Recognition by I(s : self) measures likeness, and identity names one instance: two cells running the same program are alike and are still two. At the pin the engine holds no secret per instance. The seal's keys derive from public, dated context strings (obsignatio_seal.md). Prior art, cited from knowledge: H. Krawczyk, "Cryptographic extraction and key derivation: the HKDF scheme", CRYPTO 2010, and RFC 5869; NIST FIPS 205, SLH-DSA, a stateless hash-based signature (2024).
- *Family, a reading.* The second answer agrees with the reading: the permutation null declares structure, and "family" is a human category. What the engine can hold in its place is lineage, meaning which spawn made which. Lineage is written at spawn and is not inferred from a stream.
- *The time series, a reading. Status: not built.* The third answer extends the seal from one message to a series. Each entry in the series carries the hash of the entry before it, and changing or dropping any past entry changes every hash after it. With the chain's head signed under the spawn key, the chain shows that the holder of that key committed to that series in that order, as long as the hash has no known collisions. It does not show that the series is true. It also does not show that the key was never copied: a copy of the key can extend the chain too. Two holders extending one chain from the same head fork it, and anyone who sees both branches sees the fork. Prior art, cited from knowledge: L. Lamport, "Password authentication with insecure communication", Communications of the ACM 24 (1981) 770–772, hash chains; S. Haber and W. S. Stornetta, "How to time-stamp a digital document", Journal of Cryptology 3 (1991) 99–111, linked time-stamps.
- *The forgery guard.* Doug, 26 September: "We don't need a forgery guard yet". It is recorded as a want, not built, in engine_table.md item 11(f), stage 4.
