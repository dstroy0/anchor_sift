# Engine plan

**objective**: compile a program written in gnascor to any language, including one nobody has met, and prove it is
the same program everywhere. Where the language is unknown, derive it by asking.

**information is coherence**: the principle the k-files are named for. A description at its Kolmogorov
complexity holds no redundancy, every bit of it carries, and no part predicts another. A system at coherence
has that property from the other side: its parts agree and the friction between them is at its floor. Noise
costs and carries nothing. Compression and coherence are one measurement from two directions, and friction is
the direction a foreign host will hold still to be measured on.

**what is known before meeting anything**: relations. `1,1 -> 2` is a relation and is not an addition, because
addition is a definition. Every system that computes agrees about the relation and each defines it its own way.
Arithmetic is the shared ground and the definition is what differs.

**gnascor** is the internal language, `.g` high order and `.gsm` its assembly. It is designed and it is what a
program is written in. It is not derived and its vocabulary does not move.

**`L*`** is the map from gnascor to a target's definitions, and it is the derived part. The compiler emits whole
files of relations in a shuffled order, which leaves a part nothing to tell measurement from work by, runs them,
and keeps whichever definition produced the relation.

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
[engine/compiler/gnascor.md](c/transpiler/gnascor.md). Every step of it, what backs it and the run behind its
status is in the query protocol's own table,
[theory/workbooks/engine/query_protocol_table.md](../theory/workbooks/engine/query_protocol_table.md). A step
changes status there and nowhere else.

**The gate is the engine's own descent.** Each candidate arrangement is an alignment and a relation's cases are
the needle, and orior's descent places the case that prunes the most, stops where the best case prunes
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
written, with its anchor as the representative (Open 10).

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
that tool's answer and not the part's. The SASS probe under `utils/test/src/c/transpiler/interface/` and everything it calls
(`nvcc`, `nvdisasm`, `cuobjdump`, `interface_ptx_probe`, the vendor runtime) is scaffolding. It is an answer key in the
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
definition is the loop working. Reading what the answer should be and writing it into the `.krs` is the loop
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

The parts of this that are built, the loop asked of the part, the read-back with no disassembler and the
branch distance, are filed in the engine table (M24, item 14).

**When an ask fails, the ask is the problem.** The ruleset defines itself, and an ask that cannot find the answer
bounded the question somewhere. The same small problem is asked again with that bound found and taken out.

## How this is worked

Build the compiler and run it live. A test that takes forty minutes is not a development cycle and is not to be
run. The device is the first target because it is the hard one; every other language falls out of a compiler that
works there.

## Open

1. **The writings the part gives are read into nothing.** A writing of one instruction is searched for on the part
   for every precept and every ladder relation, and every arrangement of the `.kdm` is written from them, run and
   read back (the writings searched, below). `L*` is still written by hand. `sass.krs` and `ptx.krs` are read off
   NVIDIA's compiler: `utils/test/src/cu/transpiler/bootstrap/monolith_forms.sh` asks every form the record
   programs' lanes decide in one program between tags, a question holding a number asked again with another,
   builds it once and reads each block back into a form. `ptx.krs` is read off the PTX of questions in `c.krs`'s
   text; `sass.krs` is read off the listing of questions in `ptx.krs`'s own text, put to `ptxas` as inline PTX, a
   carry in through `add.cc` and out through `addc`, a predicate in through `setp` and out through `selp`. A form
   every question of which reads whole and alike, assembles against the machine file and is no longer than the
   ruleset's is written into the ruleset; every other keeps its text and `monolith_forms.md` says why. Nothing is
   run on the part. Where the compiler stores a test's predicate as its negation and every instruction left is an
   ISETP anded with PT, each comparison is turned over, a chain through .EX whole; and a reading that drops a `.hi`
   the ruleset names is kept. A question holding a number
   outside an address is asked a third time with the number loaded, which the compiler cannot fold; that reading,
   assembled with the number in its place, stands where the two written-in ones do not settle. Where the written-in
   questions read apart only between sets of banks, a register added as IMAD.IADD and a number as IADD3, the reading
   that assembles for every set stands. A number in a 64-bit slot is asked whole, its high word the alternate of its
   low. A probe classifies a form only where the number it varies shows in the answer: a numbered probe whose number
   the answer does not carry is one the system folded, and it settles nothing, a value the system cannot fold deciding
   instead. The test names no value; which numbers a system folds is the system's own. A settled form must still
   assemble for every number it was asked, folded probes counted, or a reading drawn from register operands alone is no
   form of an operator a literal is asked of in a slot it cannot encode. Of 55 forms over 440 questions, 43 of
   `sass.krs` and 17 of `ptx.krs` are the reading. What keeps the rest: no question reads a copy, as in a straight run
   the allocator names a copy's two words one register, which leaves `word_copy`, `word_set`, `sign_set` and
   `wide_unpack` nothing to read; `sign_select` and `wide_select` take a number in either of two slots and `SEL` takes
   one only in its second, and no one text assembles for every number asked; `ptx.krs` reaches `launch_load` through a
   generic `ld`; `guarded_load` reads as a branch, `count_add` and `wide_multiply` read longer than the ruleset's,
   `wide_multiply` and `word_multiply` read `mul.lo.s` where the ruleset holds the bit-equal `mul.lo.u`, and the
   ruleset holds no `predicate_and` or `predicate_xor`. It is the loop and it is the work.
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
   addresses nothing has said are safe go through `query_interface_walk` (`compiler/bootstrap/query_interface.{h,c}`):
   the interface runs `query_walk` in a probe, one address after another, and an address that ends the probe is answered by the ending, the walk going on from the next address in a fresh probe. `query_interface_check.c` holds
   it to address 0, which ends the asker on an address fault, and to the page every Windows process shares,
   which answers reads and ends the asker on a put. Of that page's first sixteen words the walk finds two that
   advance, at 0x8 and 0x14, the interrupt time and the system time of the page's own layout. The run channel finds the part's bus the way firmware enumerates one, and never the way firmware is told
   to. Firmware is handed its enumeration space, the configuration address and the register offsets read from
   a bus standard by hand, and that is a scale written into the machine and forbidden here. The channel is
   given no address and no offset, and finds the enumeration space by how it answers. `host_address_ask`
   (`host_entry.h`) writes two words that share no bits and reads each back, sorting an address into four
   kinds: HOLDS gave back what it was written, plain memory; FIXED gave back one word whatever it was written,
   a constant such as an identifier; LIVE gave back a word the part decided, a register the part drives;
   NOTHING gave back all ones, nothing drove the line. A sizing register answers LIVE, since written all ones
   it gives back the mask of the bits it decodes, which is neither the memory that would hold all ones nor the
   empty line that reads all ones. An enumeration space is a region where a FIXED identifier and a LIVE sizing
   register repeat at one stride, and both halves are already measured with nothing told: the kind from
   `host_address_ask`, the stride from `period_read` (M18) or shift agreement over the sequence of kinds. The
   channel samples the range coarse with the classifying ask, the gate's descent steers toward where the kinds
   stop being flat HOLDS or flat NOTHING and start repeating a FIXED then a LIVE, one struck record gives the
   stride, and the rest is read one record at a time and not one address at a time. The width of a decoded
   region is read last, from the mask a LIVE register gives back when it is written all ones: the part sets
   the width and no hand writes it. On that the part's run channel stands, the records found this way with the
   known order, its solve and the descent running over them, and NVRTC, nvJitLink and the CUDA runtime leave
   the loop once a writing is put to a record and its bit read back.

   The monolith (`src/cu/transpiler/bootstrap/monolith.cu`) is what our compiler is held against: one program,
   built once by NVIDIA's compiler, holding every base precept between tags, its listing the answer key and its
   costs read on the part by `monolith_run`. `utils/test/src/cu/transpiler/bootstrap/monolith_emit.sh` holds
   every block against our reader, our assembler and the word our compiler writes it with, and writes
   `monolith_differences.md` whole on every run. Wherever the machine file holds a form, our reader and
   assembler give NVIDIA's operation bits exactly. What stands between our compiler and NVIDIA's writing is a
   state error that compounds layer on layer, and it is fixed from the root up, each fix read off the record:
   - Machine file. The fields the disassembler hides are in it: the descriptor register, the field that renames
     the operation, the field whose 0 drops the operand, and the operand a form holds and does not print, which
     keeps the bits its form was seen with. `utils/test/src/c/transpiler/interface/interface_sass_unprinted.sh`
     asks the part what each value of such a field does and writes `interface_sass_unprinted.md` whole. A
     predicate the same operation leaves out of its text at PT, as a load's at bits 64 to 67, is that operand's
     run and its form's own bits where the text drops it; the load's holds its number inverted, and the part
     answers each printed predicate as written. Our reader names a form a value renames by that value: a
     multiplier of 0 or RZ reads IMAD.MOV, of 1 IMAD.IADD and of any other IMAD. The probe reads a relative
     branch target, which the disassembler prints as the address it lands on, as its distance from the instruction
     after it, and every branch form holds its distance at bits 34 to 81 and a predicate it prints at 87 to 90.
     A bit one value of which leaves an operand out of the text under another name, as BAR.SYNCALL is BAR.SYNC with
     its barrier left out, is the operation's; a field printed twice, as BAR.SYNC R0, R0 prints its one register,
     is both operands', and the assembler refuses two values for it. All 2928 forms read back under their own
     operation from their own encoding. With `--forms` the
     script asks every form holding an unprinted operand, its operands filled by their kinds, and writes
     `interface_sass_unprinted_forms.md`: of 437 such forms 368 are asked, and 375 of their 379 runs answer alike
     at every value asked. Every cubin it writes declares 255 registers a thread: a kernel refuses a register
     number past the count it declares, and F2FP's run at 64 to 72, refused at bits 68 to 71 under the pattern's
     10, answers alike at every bit under 255. BAR.SYNC's and NANOSLEEP's runs are refused at every turned bit. A
     form that takes an address is asked through the word it writes, and none of the 40 atomics holding an
     unprinted register at 64 to 71 runs at its own bits: 22 are refused as illegal instructions, and 18 take a
     32-bit or shared address that nothing the question holds backs. All 40 were reached by turning bits. NVIDIA's
     compiler writes an atomic for an atomic on `.global` through a 64-bit pointer, and its 64-bit add holds the
     descriptor register at 64 to 69 and two bits it refuses otherwise at 70 and 71, no register. The forms with no
     result to read are not asked. `utils/test/src/c/transpiler/interface/interface_sass_fields.sh` turns each
     operation bit of every form `sass.krs` uses and runs it on the part, its result moved to R8, its sources to
     registers holding distinct values and a predicate it sets read through `SEL`, and writes
     `interface_sass_fields.md` whole. A turned bit is put to the part only where its operation key holds forms in
     the machine file and no control transfer or wait among them; any other is marked skipped and run on nothing.
     Of the 75 forms, 1619 bits read inside a run the machine file records and 526 outside every run. The three
     branch forms name a label and are not asked.
   - Scheduler bits. NVIDIA sets them an instruction at a time. The krs holds each operation's schedule, read
     from what NVIDIA's compiler writes over the tree (`monolith_scheduler.md`): a late result behind a write
     barrier, a store behind a read barrier, and the soonest a fixed result is read, 4 cycles on the integer
     operations. Our safe word sets its barriers from that schedule and stalls each instruction the soonest its
     operation's result is read, the longest where the krs measures no count (`sass_operation_schedule`), and
     `cubin_safe` holds every instruction it reads to that stall.
   - Writings searched on the part. `utils/test/src/c/transpiler/interface/interface_sass_writings.sh` puts every
     form of the machine file that writes a register from registers, predicates and numbers alone, 745 of 2928, in
     place of the frame's IADD3, each through the gate, and runs it on the part over 256 cases at once: the ladder's
     two-word cases, the words a width turns on against the counts a shift turns on, and words drawn as
     `chain_build` draws its sweep. A form is put with every assignment of the two words and RZ to its register
     sources that gives both, and a number whose field is eight bits wide, a truth table, with each of its 256
     values. It writes `interface_sass_writings.md` whole: 5685 cubins, 5394 run and the part refuses 291. Every
     precept that carries a word holds under at least one form, asr, rol and ror each as a `.W` funnel given the
     word on both halves, and every ladder relation but same. On the ladder's cases alone a dot product of bytes
     holds product and every shift holds up or down: the drawn words take them out. Up and down hold only under
     `.W`, since the precept wraps a count of 32 and more and the forms without `.W` answer 0 there.
   - Arrangements run on the part. The same script writes every arrangement of `machines/sm_86.kdm` node by node,
     each node the first writing the search found for its precept, runs all 3068 over the same cases and writes
     `interface_sass_chains.md` whole: every one answers its relation on every case, add 1202, take 1047, up 411 and
     down 408. Then the cases `gate_descent` places for each relation, one or two, are put to every arrangement it
     descends over, 3575 of them, on the part alone, and `interface_sass_descent.md` holds the part's verdicts to the
     descent's: what stands on the part stands on the host for every relation, and no verdict differs.
   - `sass.krs`. `word_shift_left` and `word_shift_right` carry no `.W`, and a count of 32 or more answers 0
     where the precept wraps it. The machine file holds no `.W` form with a number for the count, and the code
     generator writes number counts of 1 to 31 alone, where both forms agree. `word_funnel_right` carries no `.W`
     and has no left form; there is no
     arithmetic shift form; NOT, NAND and NOR have no form, each one `LOP3` (0x33, 0x3f, 0x03); add and
     subtract write `IADD3` alone.
   - Word web and alphabet web. On this part every gate is one `LOP3` node and ASR, ROL and ROR are each one
     `SHF` node, where the webs hold gates as separate precepts, NOT and NAND written from each other, and the
     rotates and the sign spread as trees the width counts. `word_shift_*` is the precept by the word web and
     not by its form.
   - Candidates the part's clock chooses between: ERR as a trap in place or a branch to a handler; MOV as the
     passage or `word_copy`; ADD and SUB as `IADD3` or `IMAD.IADD`.
   - Past the monolith: NAND and NOR in one `LOP3` where NVIDIA writes two, and ROL and ROR in one `SHF` without
     the guard NVIDIA keeps from the source.
   - The harness walks the alphabet tree one level where a precept has no word.

2. **`.kdm` holds no cost.** `utils/maint/engine/chain_check.sh` writes one: 3068 arrangements over 27.6M tried, add
   1202, take 1047, up 411, down 408, and nothing for same, places or product at three nodes. Every cost reads `-`.
   The clock already reads codings against one another in the part's own time, and that reading is thrown away
   instead of kept against a row here. Every row runs on the part (`interface_sass_chains.md`), which leaves each one
   a cubin a reading can be kept against. The safe word stalls each instruction the soonest its result is read, and
   a reading no longer counts nodes alone.

3. **`.krs` has no derived half.** Five are written. None can be completed by asking. A partly written one is the
   normal case and not a failure.

4. **The answer keys still hold the weight.** `precepts.h` holds 18 precepts and `word_web.h` 12 words, both typed.
   `machines/sm_86` is one run's output read back as an input. These are for checking a derivation against. Nothing
   that derives may read them.

5. **The relations are not asked for everything.** An atomic add has no relation put for it. `count_add` waits on
   that, and not on a name a disassembler will not print.

6. **VHDL is a target on the Pi**, built on the `cell_tracking` branch at `bbc464b`, off main. State forms cut the
   program into clock states and `vhdl.krs` writes a clocked entity. In progress, uncommitted, and the device
   writes where the host refuses.

7. **Not proved.** Of the matrix's 57 suites, 43 hold every check on the current tree: daemon, web_check, interface,
   interface_sass, interface_ptx, ruleset_read, cubin_safe, record_host, record_c, codegen_device, engine_c,
   exact_divide, exact_transform, max_tree, device_pool, period, python_period, python_periodic_energy, double_fields,
   obsignatio, qasm, record_sum, vhdl_construction_set, record_bitwise, record_coherence, record_divide,
   record_gaussian, record_guide, record_lane, record_speed, record_order, record_table (16 checks), record_tower (210
   checks), the four parts of record_boundary, and the C builds of bitwise, coherence, divide, gaussian, guide and lane.
   record_boundary is cut into parts a suite each, named by `RECORD_BOUNDARY_PART`, each part drawing from its own
   seed and its lines written as it ends: written, read_off, top and counted_forward together (50 checks), floors,
   counted_inverse (8) and redundant (16). floors holds the 1992-step program whose PTX frame passes the stack
   limit, and NVRTC compiles its C source in 934 s once; the cache holds the cubin after. The C builds of
   record_boundary's four parts have not run. 10 have no result: record_vhdl, the C pairs of speed, table, tower
   and order, residual_odd, shift_agreement_hold, tessera_device, tower_edge and unit_sweep_planes. The C build of
   order writes a 12293-step program as 17 MB of C source in one function, and the host's compiler does not finish
   it inside the harness's 1800 s. interface_sass puts its asks against the machine file the tree
   holds, 63 checks, 0 failed: 36 questions in the part's own code answer as each says, and 26 of the 27 kernels
   written again answer as the toolchain's did. The 27th, wide_divide, calls the toolchain's division and is held off
   the part. The three codings weighed run in a loop and are held off the part, and the clock reads nothing. With
   `SASS_LEARN` set it learns the machine again through the disassembler, bit by bit, and prints nothing the harness
   sees for more than 1800 s: the harness ends it. It alone
   puts cubins our own assembler wrote on the part, and every one is read on the host first: `cubin_safe`
   (`src/c/transpiler/cubin/cubin_safe.{h,c}`) holds each instruction a kernel reaches to the safe scheduler word, to
   no branch and no wait, to one instruction at most that no form holds, and to an EXIT every thread takes, and
   both `interface_sass_run` and `interface_sass_probe` refuse a cubin that breaks a rule before the driver sees it.
   `utils/test/src/c/transpiler/cubin/cubin_safe_check.sh` holds the gate to one case a rule, 15 checks, 0 failed,
   and finds 105 of the 106 cubins a fields run left safe, the one refused holding no code section.
   `interface_sass_fields.sh` puts 7360 turned-bit cubins over the 75 forms to the part through the gate in 26
   minutes: the gate refuses none, no pass hangs, and the 590 bits whose key holds a branch or a wait are skipped
   before a cubin is written. A loop ask
   branches by its nature and is held off the part until a rule says when a loop ends.

8. **One face of a set has no suffix.** Its content is settled and Doug names it. It holds the asks put to a
    member and the paths read off them, in that order: every probe and what came back, with costs, refusals
    and censored samples each marked, then the winning path per problem over those same asks. It takes the
    stem the rest of the set takes. That face, `.kdm` and `.knf` under one stem are a member's coherence map
    and fingerprint it exactly. It carries the general and specific split `.kdm` carries: a generic block good
    for any member of a class, and a specific block holding the best combination available for one section of
    one member. Keeping the asks beside the paths leaves the fingerprint independent of `.kdm` in place of a
    cache of it. A refused or censored probe appears nowhere in a table of chain costs, and it separates two
    parts that cost the same.

9. **The order of asks is built on the host and nothing emits it to a target.** The order, its solve and the
    contention read are proved on the host (M24 in the engine table, Q5, Q7). The device half is open: a container
    that runs a chain's covered links and reads the part's clock around them, put through the channel in Open 1,
    with the censored-sample mark and the reference ask alongside. Its answer carries one bit a check, 128 an ask,
    and never one bit over a set (Q15).

10. **Stem membership has a written rule and nothing reads it.** Two members sharing a stem is the whole basis
    of a set, and pairwise agreement inside a floor cannot decide it. `compiler/bootstrap/stem_group.{h,c}` holds
    an anchored group rule: the members in an order fixed by what they are, the finest floor first, the first
    member with no group anchoring one, and every member with no group that agrees with that anchor joining it.
    Agreement is a conjunction over rows at the coarser floor, and a row one member refused and the other
    measured separates them. `stem_group_check.c` (run by `utils/maint/engine/chain_check.sh`) holds it: the three
    members `order_check.py` breaks pairwise agreement with group the same way in all six orders, and over 400
    drawn sets every member agrees with its anchor, no two anchors agree, and every set groups alike under 24
    shuffles. A group is a function of the whole set, and a block written for one is written again when the set
    changes. The open part is the general block in `.kdm` keyed to a group, which nothing writes yet.

11. **One function of 132 runs on the device.** `src/cu/types/integerfloats/double_fields/double_fields.cu` holds
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
- The suffix of the face Open 8 describes.

## Roles
- Theorist writes the engine table and posits. Send it every hash and measured number.
