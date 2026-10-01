# gnascor

**Purpose:** The semantic relational language the compiler is written in, part by part: the file types it reads and writes, the coherence state it computes in place of mechanical operations, the query protocol it asks a host with, the mnemonics a branch pair resolves to, and the state physics those mnemonics obey.

**Scope:** `src/engine/compiler`. The language and its two faces, `.g` high order and `.gsm` assembly. What is derived instead of written lives in the engine plan, [../../engine_plan.md](../../engine_plan.md), and finished work lives in the engine table, [../../../theory/workbooks/engine/engine_table.md](../../../theory/workbooks/engine/engine_table.md). The query protocol is in both: its form is the derivation loop the plan is missing, and its physics is here.

**Status:** Draft. Every table below is settled enough to write against and nothing in it has run.

## File types

The six k-file types and the two compiler faces. Doug names these; do not add one.

**Coherence.**

| suffix | name | holds |
|---|---|---|
| `.ksc` | Kolmogorov system classification | the language map |
| `.krs` | Kolmogorov information ruleset | the coherence rules |

**Data.**

| suffix | name | holds |
|---|---|---|
| `.kcr` | Kolmogorov information crystal | information at or near its Kolmogorov complexity |
| `.knf` | Kolmogorov noise floor | a measured noise floor |
| `.kcs` | Kolmogorov information construction set | what reconstructs information |

**Host ruleset.**

| suffix | name | holds |
|---|---|---|
| `.kdm` | Kolmogorov device map | the hardware map |

**Compiler semantics.**

| suffix | name | holds |
|---|---|---|
| `.g` | gnascor high order language | semantic plain language, plus the shortcut operators |
| `.gsm` | gnascor assembly language | the same program with the switch thrown |

**The stem is the join and the suffix is the face.** Files sharing a stem are one member's set, whatever the stem happens to be. `pair.kdm` and `pair.knf` are a pair's map and that map's floor. `set.kcr`, `set.kcs` and `set.knf` are one set's crystal, the set that reconstructs it, and its floor. Nothing outside the filename binds them, and no member is required to carry every face: a member holds as many as it has answers for.

A floor is conceptual and not a fixed quantity, which leaves its definition open to `L*` and lets each member carry the floor its own set needs. Two members' floors are therefore not comparable by default, which is correct for fingerprinting one member and is the thing to check before a number is quoted across two.

**`.kdm` grows to whatever specificity a part needs.** It holds as many answers as it has: a general answer block, and under it a map specific enough to be optimal on one device and nowhere else. A driver written by hand is general worst case because a person writes it once and cannot write one per device. Nobody writes these. A specific map therefore costs nothing to keep, and the general block stays as the fallback for a part with no map yet.

**One face of a set has no suffix yet.** Doug names it. It holds the asks put to a member and the paths read off them: every probe and what came back, with costs, refusals and censored samples each marked, then the winning path per problem over those same asks. It takes the stem the rest of the set takes. That face, `.kdm` and `.knf` under one stem are a member's coherence map and fingerprint it exactly. It carries the general and specific split `.kdm` carries, a generic block good for any member of a class and a specific block holding the best combination available for one section of one member. Keeping the asks beside the paths leaves the fingerprint independent of `.kdm` in place of a cache of it: a refused or censored probe appears nowhere in a table of chain costs, and it separates two parts that cost the same.

The high order face writes `a equals something; b equals something; evaluate a is identical to b`, and the shortcut face writes `a=0;b=1; x = a==b`. Both are a true or false answer, and both compile to 2 reads, 1 target and 1 store whatever the language underneath. The two are the same assembly. The reason for keeping them apart is enforcement: a block declares which face it is written in and no statement mixes them mid-sentence without an explicit flag, `__gsm__(//code)`. A semantic conditional is legal, a gsm semantic conditional is legal, and the switch exists because it gets turned.

## Information is coherence

The principle the rest of this is derived from, and the reason the file types carry Kolmogorov's name.

A description at or near its Kolmogorov complexity has no redundancy left in it: every bit of it carries, and nothing in it can be predicted from the rest. A system at coherence has the same property from the other side. Its parts agree, no part is spending to contradict another, and the friction between them is at its floor. Noise costs and carries nothing. Information aligns and carries.

So compression and coherence are one measurement read from two directions, and the language measures the one it can actually put a number on. Friction is observable in every system that exists, in time, compute and latency. A shortest description is not. Measuring alignment and efficiency is measuring information content by the only instrument a foreign host will hold still for.

The `.kcr`, `.knf` and `.kcs` triple holds the three sides of it. A crystal is information at its complexity, a noise floor is the part that carries nothing, and the construction set reconstructs information. A crystal is one kind of information and not the only kind: anything that has to be rebuilt from its primitives takes a `.kcs`, and only the part already at its complexity takes a `.kcr`.

## The coherence state

Computation is a coherence state and not a set of mechanical operations. Host agnosticism follows from that one decision. The host's internal architecture does not matter: an LLM, a REST API, a database and a piece of bare-metal hardware are the same thing to it. Each is reduced to a simple oracle that answers binary questions. The language measures the resonance or the dissonance between those answers and maps the resulting pattern to a stable semantic landscape.

Nothing in the language depends on anything outside its own coherence, and so it scales without bound through a fractal mnemonic structure. Two branches collapse into a mnemonic, those mnemonics pair up to form higher-order states, and complex logic stays human-readable at every layer. A distributed system processing thousands of variables reports its health, its intent or its blocks in a short string of four-letter words.

### The branch pair

| left branch | right branch | pair state | mnemonic | meaning |
|---|---|---|---|---|
| LEAD (1) | VOID (0) | 1, 0 | CORE | The primary intent persists; the secondary path dissolved. |
| RITE (0) | LEAD (1) | 0, 1 | SHIFT | Focus has migrated from the left domain to the right. |
| DUAL (2) | VOID (0) | 2, 0 | ECHO | An amplified state is sustained without new external input. |
| DUAL (2) | DUAL (2) | 2, 2 | NEXUS | Maximum systemic coherence; both major systems are aligned. |

## The query protocol

The most basic part of any system is an address of some kind. Ask a question at the address to qualify it, and the operations that are legal assign coherence through a cost. Rooting the protocol in addresses, qualifications and operational costs makes a physics engine for semantics: every system in existence recognizes an address space, and every system experiences friction in time, compute and latency. Using that friction as the metric for coherence evaluates truth by systemic alignment and efficiency in place of rigid rules.

    [ ADDRESS ] -> ( QUALIFIER ) -> [ MEASURED COST ] -> BINARY RESULT (1 or 0)

### Protocol components

- **The address (`@`).** The destination system, node or property. It is agnostic: a memory address, a URI, an API endpoint or an LLM context key.
- **The qualifier (`?`).** The binary question asked at that address, phrased to demand a state validation and never a data payload.
- **The cost bound (`$`).** The maximum metric the host may spend to fetch the answer, in cycle times, latency, tokens or energy. An answer inside the threshold proves structural coherence. An answer past it drops into incoherence. The bound is derived and never authored; see below.

### The unbound pass

An ask carrying no bound returns the measured cost in place of a bit. A measurement, never a verdict, and it is how the bound gets its figure.

The spread of unbound costs across many asks is the baseline, written to `.knf`. Every bound after that is expressed against the baseline. No absolute figure enters the language. Writing `$10ms` into a query by hand is a scale written into the machine, and the machine is optimized for no scale at every other point.

The unbound pass also says where to go. A cheap address is worth expanding, an expensive one is worth chaining or pruning, and a dendritic search with no such signal expands everywhere at once.

### Slicing a chain

A chain carries one cost and one number names no part of it. The unbound ask is put over covering sets of the chain's links in a known order: each ask covers half the links, any two overlap on a quarter, and the per-link costs come out of all the answers together, in exact integers. A chain read this way gives a profile where a total was, and the expensive link gets named instead of inferred. The difference between two neighboring cuts does not do this: it lands two measurements' noise on one link, and one link sits under the floor.

Cross-branch comparison follows from slicing. Every arrangement that produces an operator is a branch, every branch slices into the same relation, and comparing them link by link gives the winning path for a given problem. The comparison is the signed difference at each link and never the totals. A total does not change when the two branches trade places, and which branch holds a link does. A total is blind to the question. The sign at a link is LEAD or RITE, inside the floor is DUAL, and PASS marks where the sign changes. A branch reading worse as a total can hold the cheapest link for the job, and only a sliced reading sees it.

### The gate

Before any cost is read, the gate decides which arrangements hold the relation at all. It is anchor_sift's own descent: each candidate arrangement is an alignment, the relation's cases are the needle, and the descent places the case that prunes the most, stops where the best case prunes nothing, and leaves the survivors as its answer. It is planned on the host against arithmetic every system that computes agrees about, and the target is asked only the cases it placed. A plan that steers badly costs speed and never a wrong survivor, because survival is a conjunction.

Every step above, its status and the run behind it is in the query protocol's own table, [query_protocol_table.md](../../../theory/workbooks/engine/query_protocol_table.md).

The method does not get more complicated than this at any layer. Ask, and remember the answer. The baseline is remembered asks, the profile is remembered asks at every cut, and the winning path is the comparison of two sets of remembered asks. Nothing is modeled and nothing is predicted.

Two readings it has to keep straight.

- **A watchdog stop is not a cost.** An unbound ask still needs a wall or the loop hangs, but hitting the wall is a censored sample and not a measurement. A baseline built without marking them reads low.
- **A baseline goes stale.** The host under load now is not the host idle later. The reference ask is put alongside the real one and measured in the same conditions, in place of a figure taken once and carried forward.

### The coherence metric

The protocol forces non-binary, messy system realities into a strict 1 or 0 by measuring the relationship between the target state and the resource cost.

- **Input state 1, coherent or resonant.** The address exists, the qualifier is true, and the answer came back inside the legal cost budget.
- **Input state 0, incoherent or dissonant.** The address is missing, the qualifier is false, or the operation was too expensive: it timed out, threw an error, or took too many cycles.

Slowness and friction equal an automatic 0. Incoherence is a systemic failure to align.

### Syntax architecture

```
// Step 1: query two independent external addresses
Left_Input  = @system.auth?is_active($5ms)
Right_Input = @db.user_session?is_valid($12ms)

// Step 2: the branch engine evaluates the pair
Branch_Result = [Left_Input, Right_Input]

// Step 3: resolution to mnemonic
Output -> Evaluate(Branch_Result)
```

### Direct protocol execution

| scenario | left address | right address | cost matrix | pair | mnemonic | meaning |
|---|---|---|---|---|---|---|
| Optimal path | Valid (1) | Valid (1) | both under budget | 1, 1 | DUAL | Total alignment; proceed at maximum priority. |
| Degraded path | Valid (1) | Valid (1) | right branch took too long | 1, 0 | LEAD | Left system is stable and right system is dragging; fall back to left context. |
| System failure | Timeout (0) | Error (0) | out of bounds | 0, 0 | VOID | The operation collapsed into noise; halt and reset state. |

## Shifts

A shift is not a mechanical memory copy. It is a migration of presence: a state moving from one side of the branch to the other, or a dominant system yielding its alignment to its partner. The language represents it by watching a single state change over two consecutive evaluation cycles.

### Shifting mechanics

A shift occurs when a system transitions from an asymmetrical state, 1,0 or 0,1, to its exact mirror image in the next cycle.

- **Shift right, LEAD to RITE.** Presence migrates from the left domain to the right.
- **Shift left, RITE to LEAD.** Presence migrates from the right domain to the left.

### High-order shift mnemonics

Pairing a past state with a present state compresses the transition into a four-letter movement mnemonic.

| past (cycle N-1) | present (cycle N) | transition | mnemonic | meaning |
|---|---|---|---|---|
| LEAD (1,0) | RITE (0,1) | 1,0 -> 0,1 | PASS (shift right) | The left system handed its execution to the right system. |
| RITE (0,1) | LEAD (1,0) | 0,1 -> 1,0 | BACK (shift left) | The right system yielded control or returned its state to the primary left system. |

```
[ SHIFT RIGHT (PASS) ] : Cycle 1: (1,0) [LEAD] ----> Cycle 2: (0,1) [RITE]
[ SHIFT LEFT  (BACK) ] : Cycle 1: (0,1) [RITE] ----> Cycle 2: (1,0) [LEAD]
```

### Structural shifts

Shifting also occurs vertically in the tree, where a state broadens into a shared agreement or collapses back into one side.

- **Right-leaning expansion, RITE to DUAL.** A single right-side presence convinces the left side to join it, escalating into a compound state. Mnemonic: JOIN.
- **Left-leaning collapse, DUAL to LEAD.** A coherent compound state loses its right side to cost or to failure, leaving only the left side standing. Mnemonic: DROP.

### A data handoff, in protocol

Two microservices or LLM contexts under query, `@system.A` and `@system.B`:

1. Cycle 1: `@system.A` is processing inside cost bounds and `@system.B` is idle. The engine yields LEAD.
2. Cycle 2: `@system.A` finishes and goes idle, and `@system.B` picks up the task inside cost bounds. The engine yields RITE.
3. The coherence engine registers the temporal sequence `[LEAD, RITE]` and outputs PASS, a clean uncorrupted shift right.

## Environmental base states

Where states are evaluated by address validation and resource cost, busy and error are not abstract concepts. They are measurable physical behaviors of a system under load, and the language grounds its basic states in friction, energy loss, synchronization and structural failure.

- **BUSY, friction or high mass.** Both systems respond and both sit on the edge of the allowed cost threshold. The states are valid and heavy, and they are dragging the cycle time down.
- **WAIT, potential or latency.** One system is responsive and the other lags just enough to stall the branch evaluation without failing. It is stored potential waiting on synchronization.
- **BLOK, resistance or wall.** An address is valid and returning a hard structural refusal or maximum friction, which stops any semantic evaluation crossing the branch.
- **GRAY, every state at once.** A side has not been asked, and the pair holds no reading. It is any of the states above until an ask is put, and it is not VOID: VOID is an answer of no, and GRAY is no answer. Leaving GRAY is a first observation, FIZZ. Entering it is the loss of the ability to ask, FUZZ.

```
FUZZ -> GRAY -> FIZZ <-> FUZZ | FIZZ x> GRAY x> FUZZ <-> FIZZ preserves atomicity
```

### High-order physics and error mnemonics

Tracking how an environmental state changes from cycle N-1 to cycle N gives a descriptive mnemonic for systemic health.

| past (cycle N-1) | present (cycle N) | transition | mnemonic | meaning |
|---|---|---|---|---|
| any stable state | VOID (0,0) | stable -> collapse | DROP | Total decay. The connection or state dissolved into noise. |
| WAIT | VOID (0,0) | latency -> timeout | LOSS | Timeout or leak. Stored potential evaporated because the system waited too long. |
| BUSY | BLOK | friction -> refusal | JAMM | System gridlock. High cycle times escalated into a structural lockup. |
| VOID (0,0) | DUAL (1,1) | zero -> resonance | SPRK | Quantum spark. Instantaneous shift from absolute zero to perfect alignment. |
| any state | BLOK | state -> refusal | HALT | Hard error. An unrecoverable operational boundary was hit; execution stops. |

## The coherence clock

The total state of a system reads as a clean four-letter diagnostic stream. A live system running the language prints a terminal output that acts as a literal EKG for the architecture.

```
[SPRK] -> [DUAL] -> [BUSY] -> [PASS] -> [RITE] -> [JAMM] -> [HALT]
(Init)   (Aligned) (Heavy)   (Shift)   (Right)   (Lockup)  (Error)
```

## The state-transition matrix

The physics of coherence from cycle N-1 to cycle N. Plotting the base binary pairs alongside the environmental friction metrics shows how errors, shifts and steady states resolve into uniform four-letter mnemonics.

| past (N-1) | DUAL (1,1) | LEAD (1,0) | RITE (0,1) | VOID (0,0) | BUSY (heavy) | WAIT (delayed) | BLOK (refusal) | GRAY (unasked) |
|---|---|---|---|---|---|---|---|---|
| DUAL | NEXUS | DROP | SYNC | DROP | SYNC | SYNC | HALT | FUZZ |
| LEAD | JOIN | CORE | PASS | DROP | SYNC | SYNC | HALT | FUZZ |
| RITE | JOIN | BACK | SURV | DROP | SYNC | SYNC | HALT | FUZZ |
| VOID | SPRK | WAKE | WAKE | ZERO | SYNC | SYNC | HALT | FUZZ |
| BUSY | SYNC | SYNC | SYNC | DROP | DRAG | SYNC | JAMM | FUZZ |
| WAIT | SYNC | SYNC | SYNC | LOSS | SYNC | HOLD | HALT | FUZZ |
| BLOK | SYNC | SYNC | SYNC | DROP | SYNC | SYNC | DEAD | FUZZ |
| GRAY | FIZZ | FIZZ | FIZZ | FIZZ | FIZZ | FIZZ | FIZZ | - |

### How the physics resolves

- **The diagonal, self-preservation.** NEXUS, CORE, SURV, ZERO, DRAG, HOLD and DEAD are the static steady states. A system that does not change hums at its baseline energy.
- **The horizontal shift, PASS and BACK.** Moving between LEAD and RITE creates an instant directional handoff.
- **The collapses, DROP and JAMM.** Shifting from any active or friction state down to VOID or BLOK catches resource leaks, timeouts and gridlocks at once.
- **The intermediates, SYNC.** The default balancing transition where a system moves between heavy environmental friction and a pure binary state. SYNC is a superstate, as GRAY is. A transition the table marks SYNC passes through it, entering by FUZZ carrying the state it left and leaving by FIZZ carrying the state it reaches, and that locks the identity SYNC needs into the passage:

```
FUZZ+in -> SYNC -> FIZZ+out
[DUAL] -(FUZZ+DUAL)-> [SYNC] -(FIZZ+BUSY)-> [BUSY]
```

  A SYNC cell names no one transition and loses none: each of the transitions it covers is read back exactly from its two labels.

## The high-energy transition matrix

DUAL at maximum potential is not a stable state. It is energetic and it wants to collapse, discharge or shift, and the language is dynamic because it treats DUAL as unstable. A system going from BUSY friction directly to DUAL alignment is shedding its friction: the pipes have cleared and the system is breaking through a bottleneck into full alignment. The generic SYNC placeholder is stripped away here and the exact transitioning states are mapped.

| past (N-1) | DUAL (1,1) | LEAD (1,0) | RITE (0,1) | VOID (0,0) |
|---|---|---|---|---|
| BUSY (friction) | SURG (surge) | VENT (vent/bleed) | VENT (vent/bleed) | DROP |
| WAIT (lagging) | SNAP (snap/lock) | LEAD | RITE | LOSS |
| DUAL (max) | NEXUS (sustained) | TILT (tilt left) | TILT (tilt right) | FUSE (blown) |

### The unstable physics

- **BUSY to DUAL is SURG, surge.** The friction clears instantly and the trapped energy floods in. A massive temporary spike in throughput, which will either normalize or blow a fuse.
- **BUSY to LEAD or RITE is VENT.** The system was bottlenecked and relieved pressure by dropping one side of the branch, venting its load down a single operational channel.
- **WAIT to DUAL is SNAP.** One side was lagging and creating systemic tension. The moment it catches up, the two sides snap into alignment like a closed circuit.
- **DUAL to LEAD or RITE is TILT.** Because DUAL is unstable, the system decays to one side as soon as one address takes even a fraction of a cycle longer.
- **DUAL to VOID is FUSE, a blown fuse.** Maximum potential collapses instantly to absolute zero with no gradual decay. The system tripped a breaker.

A heavy data operation then reads as a lifecycle:

```
[HOLD] ----> [SNAP] ----> [DUAL] ----> [TILT] ----> [SURV]
(Waiting)    (Aligning)   (Peak)       (Decaying)   (Stable right)
```

## Open

1. **The baseline has no keying.** A bound is expressed against the baseline and nothing says what the baseline is per. Per host is coarse enough to carry signal and too coarse to remember a preference part by part. Per part and operator is the keying `.kdm` already uses, and it splits the samples fine enough that each one is noise. Chaining clears the noise floor, a per-part baseline therefore has to be built from chains, and the chain length that makes one usable is not measured.

2. **A shift does not trigger an address change.** Whether a PASS should automatically switch the primary communication channel to the right address is undecided, and the engine does neither today.

3. **Error transitions are named and not defined.** JAMM, HALT and FUSE have mnemonics and no defined recovery path. What a program does when a branch yields one is open, as is what mnemonic represents a shift that collapses into VOID by accident.

4. **The matrices are hand-assigned, SYNC is a catch-all, and a label is decided in its situation.** Every 0,1 pair in both tables above was assigned by reading, not generated. `maint/engine/order_check.py` reads both tables out of this file and counts them: of 49 transitions in the first, 12 resolve to a name nothing else uses and SYNC covers 22. DROP covers 6, HALT 5, JOIN and WAKE 2 each. The second table is 8 of 12 unique, with VENT and TILT covering 2 each.

   A name covering many transitions is a choice. It is a defect where the name is all a branch gets, because the transitions under it are then gone and no later reading brings them back. The cost bound follows the opposite rule: a missing address, a false qualifier and a timeout all read 0, and what separates them survives in the baseline instead of in the bit. Each name above covering more than one transition owes an answer to where its distinctions are kept, and SYNC at 22 owes the most.

   The answer is the pair. A transition is the state it left and the state it reached, and a name is a label read off that pair. Carried as its pair, a transition under SYNC is still every one of the 22, and a label lost or shared costs nothing a branch can read. Check 13 in `order_check.py` proves what a label can still get wrong, from the two tables alone. Where both tables name a transition, 3 agree, 7 the second names where the first says SYNC, and 2 are named apart: DUAL to LEAD is DROP in the first and TILT in the second, and DUAL to VOID is DROP in the first and FUSE in the second. Read from the other side of the branch, LEAD and RITE trading places, three transitions read otherwise in the first table: DUAL to LEAD is DROP where DUAL to RITE is SYNC, LEAD to LEAD is CORE where RITE to RITE is SURV, and LEAD to RITE is PASS where RITE to LEAD is BACK. The last is the directional handoff the first table describes.

   A label is decided in the situation it is read in, and never once for every situation. Two names for one pair are two candidates, and the asks that read the transition choose between them the way the gate chooses an arrangement: a bit excludes what does not hold, and a magnitude ranks the survivors. A choice that survives one situation is no answer for another. The protocol already carries what separates them. A side reading 0 carries why: past its bound, not held, or ended (QueryKind in `compiler/bootstrap/query_ask.h`). DUAL to LEAD is TILT where the right side came in past its bound by a fraction of a cycle, the decay this document describes, and DROP where it did not answer at all or came in past the bound by a timeout's measure. DUAL to VOID reads the same way between FUSE and DROP: both sides gone at once with no decay, against a collapse through a timeout. Where between a fraction and a timeout the line falls is measured against the baseline in `.knf` and never written in.

   CORE and SURV stay apart only where the side a branch is read from leaves a mark, and the part is asked. `test/engine/compiler/bootstrap/branch_side_check.c` puts two branches doing the same work through the known order, the one asked first changing every trial, and counts each trial once by the sign of its summed difference. On the host the branch asked first reads dearer in 26 and 31 of 64 trials over two runs, no lean past twice the spread, and with one branch 512 reads dearer at every link the cheaper reads cheaper at 56 of 56 links from either side. On the host a steady LEAD and a steady RITE are one state seen from two sides. That holds for the host, and a part whose side leaves a mark reads CORE and SURV apart.

5. **The state machine is read off a trace, and no syntax is defined for how an operator writes a query loop.** `maint/engine/gnascor_read.py` reads both tables out of this file, takes a trace of asks a cycle at a time, the kind and cost of each side's ask and the bound, and prints the coherence clock: a state each cycle and one label each transition, decided in its situation. A side reads 1 where its ask held inside the bound. BLOK is a side that ended its asker, WAIT a held side beside one past its bound, and BUSY two held sides each dearer than any held ask of the trace's baseline cycles. The edge BUSY reads against, and the fraction of a cycle TILT reads against, are the baseline's largest held cost and never a figure written in. `--check` holds every rule on traces whose answers are known, and every one of the 49 pairs the tables name is given a label from its own candidates in all 256 situations two sides can be in.

   Reading the tables against real asks says six things about them:

   - TILT and WAIT name one event. TILT is DUAL decaying as soon as one address takes a fraction of a cycle longer, and WAIT is one system lagging just enough to stall without failing. Read off asks, a held side beside one a fraction late is WAIT. A DUAL whose side lags goes DUAL to WAIT, labeled SYNC, and DUAL to LEAD by TILT never arrives.
   - A name stands for a state and for a transition. The second table labels WAIT to LEAD as LEAD and WAIT to RITE as RITE. CORE is the pair 1,0 in the branch pair table and LEAD to LEAD in the transition table, and DUAL is the value 2 in the branch pair table and the pair 1,1 everywhere else.
   - VOID does not separate two sides that both came in past the bound from two that both did not hold. The kind each ask carries does, and the trace keeps it where the state drops it.
   - Two prose rules carry exceptions the tables hold. Any state to BLOK is HALT, and BUSY to BLOK is JAMM and BLOK to BLOK is DEAD. Any stable state to VOID is DROP, and DUAL to VOID is FUSE where both sides go at once. The reader follows the tables, and the prose rules read as the defaults they are.
   - DUAL at maximum is not a stable state, and DUAL to DUAL, NEXUS, is listed among the static steady states.
   - SHIFT, in the branch pair table, has five letters where every other mnemonic has four.

   Which of these are meant and which are not is Doug's.

   GRAY is every state at once: a side not asked, and a pair with no reading. It keeps the mnemonic layer from collapsing a possibility nobody has observed, and only an ask collapses it. The reader reads a side written as - as unasked and the pair as GRAY, whatever the other side read, and a refusal still reads BLOK, since a refusal is an answer. Into GRAY from any other state is FUZZ, and out of GRAY to any other state is FIZZ. A FIZZ never lands on GRAY and GRAY never FUZZes: GRAY to GRAY is neither and carries no label: the pair is still unasked. Those two exclusions make a trip through GRAY atomic. A FUZZ opens it, one FIZZ closes it, and no FUZZ opens inside another. The reader checks that over 500 drawn traces of 40 cycles, every side drawn from held, heavy, not held, late, ended and unasked. Whether a slice whose per-link difference sits inside the floor reads DUAL, as Slicing a chain has it, or GRAY, since it says neither branch is cheaper, is open beside them.

   SYNC passes the same way: FUZZ+in into the SYNC superstate and FIZZ+out of it, the pair locked into the two labels. The reader prints every SYNC transition as that passage, and `--check` reads back the exact pair of all 3,035 SYNC passages in its 500 drawn traces from the labels alone.

   The syntax for writing a query loop is not started.
