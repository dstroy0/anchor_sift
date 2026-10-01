# Engine plan

**objective**: compile a program written in gnascor to any language, including one nobody has met, and prove it is
the same program everywhere. Where the language is unknown, derive it by asking.

**information is coherence**: the principle the k-files are named for. A description at its Kolmogorov
complexity holds no redundancy, every bit of it carries, and no part predicts another. A system at coherence
has that property from the other side: its parts agree and the friction between them is at its floor. Noise
costs and carries nothing. Compression and coherence are one measurement from two directions, and friction is
the direction a foreign host will hold still to be measured on.

**what is known before meeting anything**: relations. `1,1 -> 2` is a relation and is not an addition, because
addition is a spelling. Every system that computes agrees about the relation and each spells it its own way.
Arithmetic is the shared ground and the spelling is what differs.

**gnascor** is the internal language, `.g` high order and `.gsm` its assembly. It is designed and it is what a
program is written in. It is not derived and its vocabulary does not move.

**`L*`** is the map from gnascor to a target's spellings, and it is the derived part. The compiler emits whole
files of relations in a shuffled order, which leaves a part nothing to tell measurement from work by, runs them,
and keeps whichever spelling produced the relation.

    .ksc   the relations put and what came back                       derived
    .kdm   the part keyed to operators: every chain, each costed      derived
    .krs   gnascor to this target                                     written or derived

All three may be partly known. A known entry is information and is never thrown away; derivation fills the rest,
and the three agreeing is the coherence picture.

**the query protocol** is the form every ask takes, and it is what derivation is made of. A question put to a
target is an address, a qualifier and a cost bound:

    [ ADDRESS ] -> ( QUALIFIER ) -> [ MEASURED COST ] -> BINARY RESULT (1 or 0)

The address names the target: a memory address, a URI, an API endpoint, an LLM context key, a register. The
qualifier is a binary question asked at it, phrased to demand a state validation and never a data payload. One
loop can therefore ask a part and a service the same question. The cost bound is the most the target may spend
to answer, and no hand writes that field.

**The bound is unbound first.** An ask carrying no bound returns the cost instead of a bit: a measurement,
never a verdict. The spread of those costs is the baseline, and the baseline is `.knf`. Every bound after that
is expressed against it. No absolute figure is ever written into the machine. Binding a query to `$10ms` by
hand is a scale written into the machine, which the engine is optimized against at every other point; the
unbound pass derives the figure in place of choosing it.

So the protocol is two passes of one ask. The unbound pass returns a cost and tells us where to go: a cheap
address is worth expanding and an expensive one is worth chaining or pruning. The bound pass returns the bit,
and the bit is what a branch consumes. A missing address, a false qualifier, a timeout, an error and too many
cycles all read 0 at that point, and the distinction between them survives in the baseline instead of in the
bit.

Two things the unbound pass has to record. A watchdog stop is not a cost reading, it is a censored sample, and a
baseline built without marking them reads low. And a baseline taken once goes stale the moment the host's load
changes. The reference ask is therefore put alongside the real one and measured in the same conditions, the
same way the emission order is shuffled to leave nothing to tell measurement from work by.

**What the baseline buys is chain slicing.** A chain carries a cost and one number for a whole chain names no
part of it. Put the unbound ask at many cuts of the chain and the per-link costs come out of the readings
together, each one measured in the same conditions as the rest. A chain is then a profile and not a total, and
the expensive link is named instead of inferred.

How the asks are ordered decides whether that works at all, and the arithmetic is measured in
`utils/maint/engine/measure_check.py`. Subtracting neighboring cuts puts the noise of two measurements on a quantity
the size of one link, and one link is the quantity sitting under the floor: the recovered cost carries
1 + 12543/12800 floors squared of noise against a signal of 1, which orders 56 + 9692/41993% of link pairs
correctly where a coin orders 50%. Repetition, descended level by level, still orders more pairs at 6400
repeats of every cut, 97 + 143/181%, and the order of asking fixes it for far less than that.

**The emission order is not a shuffle, it is a carrier.** A shuffle throws away what it scrambled. This order
is known to the asker and tells the part nothing: the part has no way to separate a measurement from work, and
every answer is still decodable, because the order is in the record. Build it so every ask covers half the
links and any two asks overlap on a quarter, and the answers come apart exactly. One ask then informs every
link at once in place of one link. The squared gain over asking a link at a time is (links + 1) over four:
1 + 15541/35219 at 3 links, 4 + 31188/189499 at 15, 60.2291 + r/d at 255, and growing with the chain. Nothing
beats the bound on what one answer can carry. A known order reaches that bound and asking one at a time does not, and
the whole gain is that difference.

A known order also beats a drawn one, and by more the further out the reading is: 4 + 883/1053 times at the
median worst-link error, 31 + 37/135 at the 95th, 145 + 5/6 at the worst of 400. 18 of 400 drawn orders do not come
apart at all and cost their whole pass. An engine answering every time is held to its worst case, and a known
order has the same worst case every pass by construction.

**Where links contend the costs stop adding, and the solve does not say so.** It returns plausible per-link
numbers with the contention folded into them, and what the fit could not account for stays flat while the
answers go wrong by a factor of two. What catches it is a term for contention's own shape. Contention grows as
the square of how many links an ask covers and the links themselves grow as the count. An order sweeping
that count therefore separates the two, and an order holding it at half gives the difference nowhere to
appear. The term
notices at 88% where the leftover notices none of it, and the same solve then takes the damage back out. It
costs one more unknown and not one more ask.

Cross-branch comparison follows from that, and it is the reason the arrangements are all kept. Every
arrangement that produces an operator is a branch, each branch slices into the same relation, and comparing
them link by link gives the winning path for a given problem instead of one arrangement that suits nothing in
particular. A chain reading worse as a total can hold the cheapest link for the job, and only a sliced reading
can see it.

The rest of the protocol, the pair states and the mnemonics the bits resolve to, is in
[engine/compiler/gnascor.md](engine/compiler/gnascor.md). Every step of it, what backs it and the run behind its
status is in the query protocol's own table,
[theory/workbooks/engine/query_protocol_table.md](../theory/workbooks/engine/query_protocol_table.md). A step
changes status there and nowhere else.

**The gate is the engine's own descent.** Each candidate arrangement is an alignment and a relation's cases are
the needle, and anchor_sift's descent places the case that prunes the most, stops where the best case prunes
nothing, and leaves the survivors as its answer. The descent is planned on the host against arithmetic every
system that computes agrees about, and a target is asked only the cases it placed. That is steering on what is
known to be true. Survival is a conjunction, and order cannot change a conjunction. A plan that steers badly
costs speed and never a wrong survivor: gate then rank, in the engine's own words.

Cost is measured by chaining, never alone: one operation sits under the noise floor and a chain clears it by
fifteen times. Chaining is also what takes the bias out. A primitive that reads worse by itself and is right for a
job is then chosen for that job.

An operator is a chain of primitives and the chain can be rearranged. Every arrangement that produces the operator
is kept with its cost, and a job takes the one that suits it, in place of one arrangement that suits nothing in
particular. A person writing a compiler by hand affords one arrangement for each operator, because a person has to
write it. Nobody writes these, and the best for an application is therefore always available.

Finished work lives in the engine table, `theory/workbooks/engine/engine_table.md`. What is written here is open.

## File types

    .kcr   Kolmogorov information crystal
    .krs   Kolmogorov information ruleset: one language's forms
    .kcs   Kolmogorov information construction set: what reconstructs information
    .knf   Kolmogorov noise floor
    .kdm   Kolmogorov device map
    .ksc   Kolmogorov system classification

Doug names these. Do not add one.

**The stem is the join and the suffix is the face.** Files sharing a stem are one member's set, whatever the
stem happens to be. `pair.kdm` and `pair.knf` are a pair's map and that map's floor. `set.kcr`, `set.kcs` and
`set.knf` are one set's crystal, the set that reconstructs it, and its floor. Nothing outside the filename
binds them, and no member is required to carry every face: a member holds as many as it has answers for.

A floor is conceptual and not a fixed quantity, which leaves its definition open to `L*` and lets each member
carry the floor its own set needs. Two members' floors are therefore not comparable by default. That is
correct for fingerprinting one member and is the thing to check before a number is quoted across two.

What follows from that is a rule about membership. Asked from one member's own floor, agreement is not even
symmetric: a fine-floored member reads a neighbor as different while the neighbor reads it as the same. Taken
at the coarser of the two floors it is symmetric and still not transitive, and `utils/maint/engine/order_check.py`
shows three members where the first agrees with the second, the second with the third, and the first with
neither. Pairwise agreement therefore names no set, and which members share a stem has no answer that does not
depend on which was asked first. A group needs one of two things written: a representative every member is
compared against, or a rule that builds the group and says which member it is anchored on. The rule is
written, with its anchor as the representative (Open 12).

**`.kdm` grows to whatever specificity a part needs.** It holds as many answers as it has: a general answer
block, and under it a map specific enough to be optimal on one device and nowhere else. A driver written by
hand is general worst case because a person writes it once and cannot write one per device. Nobody writes
these. A specific map therefore costs nothing to keep, and the general block stays as the fallback for a part
with no map yet.

## The method

**Everything is learned through the query protocol, and through nothing else.** An ask is
`[ADDRESS] -> (QUALIFIER) -> [COST] -> BIT`, put with `host_put` and read with `host_read`
(`compiler/bootstrap/host_entry.h`), with nothing between them and the part. No outside tool is in the loop: no
compiler, assembler, disassembler, object reader, vendor runtime or driver library. A word that went through one is
that tool's answer and not the part's. The SASS probe under `utils/test/engine/compiler/cell/` and everything it calls
(`nvcc`, `nvdisasm`, `cuobjdump`, `cell_ptx_probe`, the vendor runtime) is scaffolding. It is an answer key in the
sense `precepts.h` is one: it may be read to form a question, and to check a derivation after it has run. It is
never a channel a derivation runs through, never where the work resumes, and never a place to find again what the
protocol answers. When how to reach a part is unclear, the answer is the protocol put at the part's addresses, and
never a tool that already knows.

Ask, and remember the answer. It does not get more complicated than that at any layer. The baseline is
remembered asks. A chain profile is remembered asks at every cut. The winning path is a comparison of two sets
of remembered asks. Nothing is modeled, nothing is predicted, and a known entry is never thrown away.

**Gate, then rank. Never one score.** A relation holds or it does not, and that answer carries no noise. A
cost is measured and every cost carries noise. The two do different jobs and are never added together.
Precepts filter the candidates down to the admissible ones, and cost orders whatever survives. Put both in one
number and a cheap wrong arrangement outranks a correct slow one, with nothing in the result saying which kind
of agreement won. Kept apart, measurement noise can cost speed and can never cost correctness, because wrong
was excluded before anything was ranked.

How many arrangements survive the gate is itself a reading and is kept. One survivor means the precepts decide
that operator. Many means they do not, and the answer to that is another relation, never more measurement.

**A precept is a question to put, never an answer to write.** Asking a target whether `1,1 -> 2` holds in its
spelling is the loop working. Reading what the answer should be and writing it into the `.krs` is the loop
lying to itself, and both look like using the precepts. `precepts.h` and `word_web.h` are answer keys. They
may be read to form a question, and to check a derivation after it has run. Nothing that derives may read them
to fill a form in.

A count of precepts held is not a score either, and the reason is separate from the one above. Put five cases
to the ladder's candidate set and one of them decides it on its own; the other four are surplus, and every one
of the five is then implied by the rest. A count over a set like that weights one fact several times, at
weights nobody set. Check the set down to its deciding subset before any count is taken off it.
`utils/maint/engine/order_check.py` does that mechanically and wants running whenever a case is added.

**An answer holds only under what it was asked at.** A reading is an answer for the part it was taken on and
the size it was taken at, and for nothing else by default. A foundation that carried three stories is no
foundation for a tower, and it is not a floor of some other building either. Both transplants are priced in
`order_check.py`: the arrangement winning at one size costs 79 times the best at a larger one, a winner spliced
onto another part costs 3 times that part's own best, and across both at once the penalties multiply. Some
parts agree and some do not, and no reading taken on one part says which. So every answer carries the part and
the size beside it, and a reader outside either has nothing and has to ask. The general block in `.kdm` is the
fallback for a member with nothing measured, and never a result borrowed from a member that has.

## Functions on every part

**The engine asks the part and builds the code that answers.** No `.g`, no `.gsm` and no gnascor stands between a
function and the part that runs it.

**Tessera is the boundary between host and device.** Every process that crosses it is identified there by its
Merkle DAG ID, the seal over its contents: tessera knows every process. Device code never calls the operating
system. A file, a socket, a process or a clock is asked for through tessera and answered on the host.

**The transpiler emits the device code.** A program it emits is built from any form `L*` has learned for a part,
and it can do anything that part can do, branches and loops included wherever the part has the forms. The record
machine's straight-line program is one kind of emitted program and not the limit on them.

**Every function is in every container.** `c/`, `cu/` and `python/` are one container per host entry point, and
every function is in all three under one name (`TREE_LAYOUT_PLAN.md`). A function a container lacks is not ported
by hand: the engine emits it for that container's part and holds it 1:1 against the original, the same inputs and
the same answers. A function that calls the operating system reaches every container through tessera. The part of
it that computes is emitted, and the call crosses at tessera.

**A loop is learned by asking, like any other operator.** A loop is an address added to until it comes back where
it began. Every ruleset writes it with the same two forms on our side, `loop_label loop` and `loop_back loop
where`: a label to come back to, and the flag that takes the way back. Only the right side, the part's instructions,
differs per target, and in every `.krs` it is written by hand. It is derived by asking:

- The candidates are every form the part's machine file holds, each put in `loop_back`'s place with its operands
  filled by their kinds. Nothing decides beforehand which forms jump.
- The question is a body that counts N down with `add_alone` and sets the flag with `test_nonzero`. A form in
  `loop_back`'s place that comes back to the label on the flag answers N, and a form that falls through answers 1.
  N = 2 is asked first, since it prunes the most, and the forms that answer it are asked every other N.
- The forms that answer every N are timed, and the cheapest is that part's `loop_back`.

`cell_sass_probe` puts this ask alone, given `loop` and the machine file, against the cubins of an earlier run
(`SASS_PATTERN` in `cell_sass_test.sh`). On sm_86, 2533 of the 2927 forms assemble, 1715 fall through, and 8 come
back on every N, every one a `BRA`. The walk agrees with all 8, and none is cheaper than the next above the spread
of its own runs, which leaves the part no `loop_back` cheaper than the `BRA` that `sass.krs` writes.

**A check between emitting and running, on or off.** The transpiler reads an emitted instruction back through the
machine file's own forms, with no disassembler (`sass_encoding_read`, `compiler/cubin/sass_assemble.h`), and walks
it (`sass_loop_walk`): its guard is the flag alone, one of its label or number operands added to the
address after it lands on the label, and its first operand writes nothing the loop keeps. A caller turns the check
on or off and can stop at any step of it. It never changes an emitted instruction and nothing is optimized: with
the check off, what was emitted is what runs, as code written to run in constant time needs.

**Every step is checked by hand against what is known to be true of the device.** Of the 2927 forms in sm_86's
machine file, 2383 read back as they were listed. The rest are known limits: two names the disassembler prints for
one encoding (`IMAD.MOV`), addresses with a uniform register, absolute 64-bit `CALL.ABS` and `JMP` targets, and 380
forms whose operands the assembler cannot place either. The walk gives the expected step on ten known cases out of
ten. The check found that a branch's distance starts at bit 34 in four-byte steps, not at bit 32: bits 32 and 33 are
the operation's own, as `BRA`, `BRA.U` and `BRA.DIV` show the same distance with 0, 1 and 2 there. Written from bit
32, a `BRA.U` assembled as a `BRA`.

**When an ask fails, the ask is the problem.** The ruleset defines itself, and an ask that cannot find the answer
bounded the question somewhere. The same small problem is asked again with that bound found and taken out.

## How this is worked

Build the compiler and run it live. A test that takes forty minutes is not a development cycle and is not to be
run. The device is the first target because it is the hard one; every other language falls out of a compiler that
works there.

## Open

1. **Nothing searches for a writing.** No file of relations is emitted, run and read back, which leaves every
   writing unconfirmed by any target. `L*` is written by hand for want of this. It is the loop and it is the work.
   The query protocol above gives the loop its shape and nothing emits one yet. The cost bound is the open part
   of it: static, written into the query as `$10ms`, or dynamic, measured against a running average. The chain
   clock already reads a cost in the part's own time, and that reading is what a bound would be set from. That
   clock runs inside the SASS probe, through the toolkit, and is scaffolding (the method, above): the loop's
   clock is read by an ask put through `host_entry.h` like every other answer. That ask is `query_ask`
   (`compiler/bootstrap/query_ask.{h,c}`): an address and a qualifier, held, equal or advancing, returning a cost
   unbound and a bit bound, the cost read off a clock that is itself an address. `query_ask_check.c` holds it to
   memory the test owns and to the host's interrupt time at a fixed address, found advancing by the ask itself.
   That counter steps once a clock interrupt, half a millisecond to a millisecond, and an ask is far shorter: a
   cost read from it is a step or nothing. A bound set from it judges a run of asks and never one. Asks at
   addresses nothing has said are safe go through `query_cell_walk` (`compiler/bootstrap/query_cell.{h,c}`):
   the cell runs `query_walk` in a child, one address after another, and an address that ends the child is
   answered by the ending, the walk going on from the next address in a fresh child. `query_cell_check.c` holds
   it to address 0, which ends the asker on an address fault, and to the page every Windows process shares,
   which answers reads and ends the asker on a put. Of that page's first sixteen words the walk finds two that
   advance, at 0x8 and 0x14, the interrupt time and the system time of the page's own layout. The next piece is
   the run channel: the part's addresses found by walks of that form, with the known order, its solve and the
   gate's descent running over them.

2. **`.kdm` holds no cost.** `utils/maint/engine/chain_check.sh` writes one: 3068 arrangements over 27.6M tried, add
   1202, take 1047, up 411, down 408, and nothing for same, places or product at three nodes. Every cost reads `-`.
   The clock already reads codings against one another in the part's own time, and that reading is thrown away
   instead of kept against a row here.

3. **`.krs` has no derived half.** Five are written. None can be completed by asking. A partly written one is the
   normal case and not a failure.

4. **The answer keys still hold the weight.** `precepts.h` holds 18 precepts and `word_web.h` 12 words, both typed.
   `machines/sm_86` is one run's output read back as an input. These are for checking a derivation against. Nothing
   that derives may read them.

5. **The relations are not asked for everything.** An atomic add has no relation put for it. `count_add` waits on
   that, and not on a name a disassembler will not print.

6. **The compile channel in `.ksc` reads 0.** It runs in another process, uninstrumented. Run, decode and clock
   all read.

7. **VHDL is a target on the Pi**, built on the `cell_tracking` branch at `bbc464b`, off main. State forms cut the
   program into clock states and `vhdl.krs` writes a clocked entity. In progress, uncommitted, and the device
   writes where the host refuses.

8. **Not proved.** The test matrix has not run since the machine file was replaced. `cell_ptx` test_signed_zero is
   stale.

9. **The ladder's cases do not decide a relation, and the descent finds the cases that do.** 507 arrangements fit
   the ladder's cases and are not the relation: 287 of up, 151 of down, 36 of take, 25 of add, and all 8 of same.
   Run as the gate's descent over the ladder's cases and the 512 words of the chain builder's sweep, one
   full-width word decides add, take and same, and up and down need a second whose count reads zero. Every one of
   the 507 dies at the first or second case placed, and no case the ladder holds is among them
   (`utils/maint/engine/chain_check.sh`, Q4 in the query protocol table). Nothing is added to the ladder by hand: the
   descent picks the cases from the sweep on the host, and the open part is the loop that puts them to a target.

10. **One face of a set has no suffix.** Its content is settled and Doug names it. It holds the asks put to a
    member and the paths read off them, in that order: every probe and what came back, with costs, refusals
    and censored samples each marked, then the winning path per problem over those same asks. It takes the
    stem the rest of the set takes. That face, `.kdm` and `.knf` under one stem are a member's coherence map
    and fingerprint it exactly. It carries the general and specific split `.kdm` carries: a generic block good
    for any member of a class, and a specific block holding the best combination available for one section of
    one member. Keeping the asks beside the paths leaves the fingerprint independent of `.kdm` in place of a
    cache of it. A refused or censored probe appears nowhere in a table of chain costs, and it separates two
    parts that cost the same.

11. **The order of asks is built on the host and nothing emits it to a target.**
    `src/engine/compiler/bootstrap/ask_order.{h,c}` holds the known order, its solve and the contention read, with
    no floating point value anywhere: the order follows from the link count, the solve is
    `(n + 1)·x = 4·Sᵀb - 2·(Σb)·1`, and the read is exact integers. `ask_order_check.c` proves the order and the
    solve at every size a known order covers and measures the read (Q5 and Q7 in the query protocol table). Two
    things the measuring settled. A known order exists only for a link count one short of a power of two, and the
    engine composes chains to those lengths. The sweep asks sit at one link, half plus one and every link, and the
    read takes out a constant and the count before the square, because every ask pays an overhead the solve
    spreads over every link. The order is put to the host through the protocol: `query_order_put`
    (`compiler/bootstrap/query_order.{h,c}`) puts every link an ask covers between two reads of a clock found by
    asking. The clock turns over now and then and is read finely by counting reads of it between turns: a
    run's cost is an exact rational, and every pass is solved on its own in exact integers: nothing is rounded,
    summed across passes or cut to a least. Neither the run size nor the count of passes is set: both are
    steered the way the engine's descent steers its probes (`utils/test/engine/compiler/bootstrap/query_descent.h`).
    Passes are put until every neighbor pair's count leans past twice its spread, and every size is read and
    the one leaving the fewest pairs standing for the fewest puts is kept, since short runs drown in the
    counting's spread and long ones gather interference. `query_order_check.c` solves seven links whose reads
    differ by 64 each, and every neighbor pair leans dearer on one same pass at the size the part names. The contention read takes integer costs and is not yet put
    over exact rationals. The device half is open: a container that runs a chain's covered links and
    reads the part's clock around them, put through the channel in Open 1, with the censored-sample mark and the
    reference ask alongside. Its answer carries one bit a check, 128 an ask, and never one bit over a set (Q15).

12. **Stem membership has a written rule and nothing reads it.** Two members sharing a stem is the whole basis
    of a set, and pairwise agreement inside a floor cannot decide it. `compiler/bootstrap/stem_group.{h,c}` holds
    an anchored group rule: the members in an order fixed by what they are, the finest floor first, the first
    member with no group anchoring one, and every member with no group that agrees with that anchor joining it.
    Agreement is a conjunction over rows at the coarser floor, and a row one member refused and the other
    measured separates them. `stem_group_check.c` (run by `utils/maint/engine/chain_check.sh`) holds it: the three
    members `order_check.py` breaks pairwise agreement with group the same way in all six orders, and over 400
    drawn sets every member agrees with its anchor, no two anchors agree, and every set groups alike under 24
    shuffles. A group is a function of the whole set, and a block written for one is written again when the set
    changes. The open part is the general block in `.kdm` keyed to a group, which nothing writes yet.

13. **One function of 132 runs on the device.** `src/cu/types/integerfloats/double_fields/double_fields.cu` holds
    `double_fields.c`'s four functions as one record program, encoded, laid out and loaded by the calls
    `engine_record_encode` makes, swept on the device and run on the host. `double_fields_test.cu` holds it 1:1
    against the C on 4110 lanes, the edges of a double and 4096 drawn words, with merges past every mask: the
    device equals the host word for word, both equal the C on every lane, and a mask one short fails 2049 lanes
    of the exponent and 2056 of the merge. The program is written from the C by hand, and deriving a function's
    program from the function is not built. The record program reaches the part through NVRTC and nvJitLink,
    scaffolding until the channel in Open 1 carries it. The other 131 functions that compute and the 47 that call
    the operating system are rows in `TREE_LAYOUT_PLAN.tsv`, listed by
    `utils/maint/engine/tree_layout_check.py --write`.

## Pending Doug
- Move cell_tracking into `examples/` and theory into anchor_sift. Don't start without direction.

## Roles
- Theorist writes the engine table and posits. Send it every hash and measured number.
