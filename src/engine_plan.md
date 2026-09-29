# Engine plan

## Objective
A universal compiler. Given a target's ruleset L, a program compiles to it, and the proof is the same program on every
target answering as the host does, word for word. Where L is unknown the engine derives it: it asks the target
questions, and asks a more basic one wherever a question kills the process.

SASS is a subject, not the target. The job there is to emit the compiler to it and move on. The other L are x86, the
AMD GPU set, AArch64, RISC-V, and VHDL, where the program becomes a circuit.

What this is not: a backend for one vendor. nvdisasm as an oracle is how this one subject is probed, not the method -
a target with no disassembler is the case that matters. Read this before building anything here.

## The irreducible set
From Doug, 29 Sep: "krs is arbitrary, we assign our meaning to it, so if you need to have a rule in the compiler that
says this does this, that's part of its irreducible set." A ruleset cannot state a rule about itself. What the
compiler must know natively is this set, and everything else is derived in a ruleset. Writing it down is how it stays
small.

**The metalanguage** (ruleset_core_read.h). A ruleset gives every form of the schema exactly once, one of four ways:

    form <name> <parameter>... = <text>    the language writes this, and the text is how
    nop <name> <parameter>...              it needs no instruction here, or has no such thing at all
    err <name> <parameter>...              the operation is an error here; a lane that needs it is refused
    construct <name> <parameter>...        the form written as other forms, its lines to `end`

with `ruleset`, `toolchain` and `header` naming the language, `bank <name> = <text with {n}>` how one register of a
bank is written, and `fixed <name> = <text>` a register the lane holds throughout. In a text `{parameter}` is an
argument; in a construct's line `{bank:n}` is a scratch register of that bank, taken once a writing. `form` with
nothing after its equals is not a fifth way, it is a file that has not said which of the four it means, and the read
ends on it, and that kept 22 holes out of sight in a written SASS lane until 29 Sep.

**What a text means.** One rule, and it is the compiler's because no listing prints it and no target defines it:

    .hi    the high half of the thing it is written on

For a register that is the second register of a 64-bit pair, one past the one it is named from. For a number it is
the number's high word. Both are bit-slices and not arithmetic (Doug, 29 Sep: "bitwise operators are not arithmetic"),
and a ruleset can write them for that reason.

**What a language still declares in code, not in its ruleset** (code_generator.h): `register_file_holds()`, how many
registers its one register file holds and 0 where its registers are virtual; `program_schedule_model()`, how a lane
is split into states; its write ports; and whether the lane's file lives in shared memory. These are facts about the
target sitting in C++ and not in the .krs, and each is a candidate to move into the ruleset. Not decided.

**The precepts.** The schema's forms are the operations the compiler knows how to decide, and that list is the third
part of this set. Doug's universal floor, 29 Sep: "nand/nor, not, and, or, xor, mov/copy, shl/shr, rol/ror, asr,
cmp/sub, jmp/bra, jcc ... every math function is an array of xor and and gates wired to shift and mov regs. we need
nop err cmp/sub jmp/bra jcc those are universal." Against the schema: and, or, xor, mov/copy, shl, shr and cmp/sub
are there, ror is word_funnel_right with the same register twice, and nop and err are now the metalanguage's. Missing
are not, nand, nor, asr and rol. Missing too is any general branch: every branch the schema has is welded to a reason
(error, open_error_unless, loop_back, dispatch_to), where the universal pair is a jump to a label and a jump on a
predicate, with the reasons written as constructs over them.

## Rules
- No VHDL, Yosys, GHDL work unless Doug asks for that exact thing.
- No other architectures (Pi, RISC-V, Xtensa are off the list).
- Never propose removing the host build or host path; it is an entry point.
- Run the thing being built first. No host sweeps unasked.
- Harness for runs, no timeouts on queued runs. Work on main. No heredocs. No attribution. Don't make things up.
- Do not invent a file type. The k-file family (.kcr the lattice, .krs the rulesets, .knf the noise floors, .kcs the
  construction set) is Doug's; ask before adding to it. Two things that are not this: a qualifier inside a ruleset,
  since the target's assembly syntax is what a .krs is for (.hi in sass.krs is that file doing its job), and .kmc,
  which is a shim of this work's own, not a member of the family.
- One sentence commit messages.
- Probes: small test kernels that ask one question and exit. Learn the ELF by reading their cubins with their tools
  (nvdisasm, cuobjdump -elf); never patch or inject.

## State (29 Sep)
- Device path by default: anchor_sift 80afd26. Record suites 21/22 pass; record_tower_c not rerun.
  record_order_c: two host programs (12293, 16379 steps) hit MSVC C1002 out of heap; suite passes.
- sass.krs written from the probes' listings, with sass_target and the ruleset_read suite (56 checks, 0 failed):
  every ruleset read against its schema, and each SASS form held to the instruction its question's listing gave.
- cell_sass on an RTX 3070 (sm_86), CUDA 13.3, 29 Sep, exit 0. Data in build/<stamp>_cell_sass_test/sass/:
  - 25 questions, 33 operations, 0 failed. 69 forms learned from the listings. A form is an operation with the kind
    and mark of each printed operand.
  - Widening: 69 forms turned bit by bit, 256 more one bit from them, 0 the disassembler failed. 325 forms, 0 without
    fields, written as machines/sm_86 and read back with 0 differing. The 69 the listings gave are byte for byte
    what they were: widening only adds.
  - 976 instructions assembled from their text alone: 0 refused, 968 the very bytes the listing gave, 945 read back
    as the text they were written from, 31 (branches and relocations) held to their bytes. Unchanged by widening.
  - 26 of 26 kernels written again into cubins of their own, loaded and run: every one answers what the toolchain's
    own cubin answered.
  - 20 questions asked in code no toolchain wrote (form_0's kernel with its arithmetic replaced): 20 answered as the
    question says. Ten of them are new, and are the point of the widening: ISETP.EQ.U32.AND, ISETP.LT.AND and
    ISETP.EQ.U32.AND.EX each asked once where the comparison should fire and once where it should not, and
    predicate_xor and predicate_and run as sass.krs writes them, each both ways. The part answers right every time:
    a form reached by turning one bit runs, and does not merely decode.
- Every form sass.krs writes assembles against that machine file: 58 assembled, 0 refused
  (maint/engine/sass_krs_check.sh, no device).
- Known failures: VHDL lane in codegen_device (device writes where host refuses); cell_ptx test_signed_zero stale.

## SASS findings (sm_86)
- Rd 16-23, Ra 24-31, Rb 32-39, Rc 64-71, RZ 255. Immediates 32-63. Bits 9-11: operand B kind (1 reg, 4 imm, 5 const).
- Guard predicate 12-15. Predicate operands 81-83, 84-86, 87-90 (90 negates).
- Control 105-127: stall 4, yield, write barrier, read barrier, wait mask 6, reuse 4.
- Carry through one predicate (IADD3.X ..., P0, ..., P0). .E memory reads descriptor in UR4 (c[0x0][0x118]).
- ELF: between single-kernel cubins only .text + its size, register count (sh_info top byte, EIATTR_REGCOUNT),
  EIATTR_EXIT_INSTR_OFFSETS change. Params (u64, u64, u32) fix the constant bank. wide_divide adds __cuda_sm20_div_u64.
- Found writing cubins, 28 Sep:
  - Predicate operands sit in five places, not three: 68-71, 77-80, 81-83, 84-86, 87-90, the fourth bit negating.
  - A branch's target is one signed field from bit 32 to bit 81, across both words.
  - A constant's offset counts words (offset >> 2) from bit 40; an address's counts bytes from bit 40.
  - LDG's bits 32-39 change nothing nvdisasm prints: two instructions that print the same can differ there. The
    listing is not the whole instruction, and for that reason 968 of 976 match byte for byte and all 976 read back right.
  - The scheduler's bits are not in the text, and code written from text needs a schedule. What works: the longest
    stall, no reuse, a wait on every barrier, and a barrier set wherever the shape's own encoding set one. The last
    part carries the correctness - without it every load reads stale and the answers come back 0 (measured).

## Next
The measure is the lane emitted to SASS and the record tests answering as the host does. What stands between:

1. Done, 29 Sep, ours and no question for the GPU. The banks are laid end to end into one register file from the
   counts the lane declares (register_file_holds, 240 for SASS), and a lane whose banks run past that is refused,
   in place of being written over the fixed registers. The assembler resolves sass.krs's .hi (sass_high_half): R14.hi is
   R15. Both compile. The allocation has not been run, because nothing emits the lane to SASS yet - that is the
   measure this list is for.
2. Measured, 29 Sep (maint/engine/sass_lane_needs.sh, no device): the record programs the host oracle runs, laid out
   and decided for SASS, ask for 84 of the schema's 99 forms. Four of those sass.krs gives as an error, and they are
   the whole blocking list: open_launch (16), launch_load (98), count_add (28) and program_unit (16). shared_open,
   shared_close, word_divide and wide_divide are errors too and no lane here asks for one, and none is a blocker.
3. Done 29 Sep, each asked of the part and answered right:
   - predicate_xor and predicate_and, the first constructs in any ruleset. The part has PLOP3.LUT and no question
     made the compiler write it, and widening reaches it only from SHF.L.U32, where it decodes with a register where
     a predicate belongs; so both go through the words a predicate selects, over forms every listing gave. An
     exclusive or is four instructions and an and is five, because SEL reads its first operand from a register and so
     can only be given RZ, which selects 1 where the predicate is false: negating both inputs leaves an exclusive or
     alone but not an and, and an and pays one MOV to hold the 1.
   - product_low and product_high. The compiler fused both into one IMAD.WIDE.U32 into an aligned pair (form_13: MOV
     R7, RZ then IMAD.WIDE.U32 R6, R9, R0, R6), which needs the two destinations to be a pair, and the core names
     them apart. Each is written on its own instead: the low is IMAD then IADD3 keeping its carry in P6, and the high
     is IMAD.HI.U32 then IMAD.X taking that carry. Four instructions where the compiler wrote one, and 0xffffffff
     squared plus 0xffffffff answers 0 and 0xffffffff on the part, as the question says.

## Define the system, 29 Sep
From Doug: "we can measure how fast the different loaders we think are certain register widths are in reality ...
that's the whole point of the define the system process, which has a subprocess define the basic language." The
precepts are the basic language; the system is what the part actually does and what it costs. A name in a machine
file is a guess until the part is asked, and the widening round hands over 202 names nobody has asked anything of.

Asked and answered on the part, 29 Sep, the load widths that launch_load and the record's reads stand on:

    LDG.E.CONSTANT        1 register
    LDG.E.64.CONSTANT     2 registers, a pair        R8 reads 0xb and R9 reads 0x7
    LDG.E.128.CONSTANT    4 registers from the first  R9 still reads the case's second word
    LDG.E.U8.CONSTANT     1 byte, zero extended      0xffffffff stored reads back 0x000000ff

The byte question also says the safe control the assembler writes orders a store before a load in one lane, which
nothing had asked before.

Cost does not need the part's clock. Doug, 29 Sep: "we can use our own clock ... really they all make the same kind
of noise, on off and off and off really fast, so we can ask hey what clock signals do you have?" The probe asks
(`cell_ptx_probe clocks`) and the part answers:

    the part's clock             1770000 kHz      a warp                        32 lanes
    the memory's clock           7001000 kHz      a multiprocessor's threads    1536
    the memory's bus             256 bits         a multiprocessor's registers  65536
    the part's multiprocessors   46               the second level cache        4194304 bytes

One tick is 565 ps, and that is the unit a cost reads in. A run is timed from outside by the host's clock
(PROBE_REPEATS on `cell_ptx_probe run`), and nothing in the machine file is needed for it. Measured: 497 us a run at
one lane, which is almost all harness - a 700-instruction lane at one lane is about 0.4 us and invisible under it.
Timing a lane means many lanes or a loop inside the kernel, which is a bench, no longer an ask.

**The knee, and it lands on our own allocator.** Doug, 29 Sep: "clock regression over a certain complexity is
expected ... we're looking for the sharp knee of a really huge jump in time, that's our indicator that we maybe did
something bad unless our circuits already complex." The part's two numbers give where one such knee must be: 65536
registers a multiprocessor over 1536 threads is 42 registers a thread to fill it, and a thread past that loses
threads in step - 64 registers gives 1024, 128 gives 512, 240 gives 256, a sixth of full.

register_file_holds() answers 240, the count the file holds and not what a lane can take and stay fast, and
code_generator_file lays the banks end to end from the declared counts with no reuse at all. The lanes measured on
29 Sep reach R42 (tables), R72 and R77 (members, bitwise), R191 (arithmetic) and R221 (division). So the record
programs are predicted to spread four to six times in occupancy on register count alone, with the knee between
bitwise and arithmetic. Predicted, not measured: no lane has been run, and the sweep that would show it is the bench
above. If it reads flat instead, the reading is wrong and the allocator is not what costs.

A second reading the part could give and does not: S2R and CS2R are in the machine but only ever with SR_LANEID,
SR_CTAID.X and SR_TID.X. The system register sits in bits 72 to 79, one turned bit from a clock read, and
sass_machine_widen throws it away, because the rule takes a decode only where the **operation** differs and a system
register is part of the operand: widening explores the operation space and not the operand-name space. It fails
closed in place of lying - a form is matched on the text of every operand the assembler cannot turn into a number
(sass_machine_same), and S2R R2, SR_CLOCKLO finds no form and is refused, where writing the register field into
SR_CTAID.X's encoding would have timed the wrong thing silently. Fixing it means keying a form on its named operands
too, which splits every S2R into one form per system register.

## Qualification and preference, 29 Sep
From Doug: "qualification is CAN you do this, not do you PREFER this ... we tune clock per logic block just like we
do for functions in microopting, but here the engine just does it." Every question the probe asked before this was
qualification: can the part do it, answered truthy or falsy. Preference is a different question over the same set,
and ScheduleModel::cost has held the empty socket for it all along - a cost a form by its name, "as the target's
construction set measured it", with nothing measuring it.

sass_cubin_prefers asks it: two codings of one thing, both run, both made to answer what the question says or the
reading is void, then both timed in the part's own clock. What came back:

    a move                    MOV R7, R0 against IMAD.MOV.U32 R7, RZ, RZ, R0
                              8035 ns apart against a floor of 903670      no preference above the floor
    a wide add's high word    IADD3 then IADD3.X against IADD3, IMAD.X then IADD3
                              3207780 ns apart against a floor of 181905   the first, 8.0195 ns a turn, 14.19 ticks
    doubled                   IADD3 R7, R0, R0, RZ against a move and SHF.L.U32
                              3053305 ns apart against a floor of 197945   the first, 7.6333 ns a turn, 13.51 ticks

**Preference qualifies for long operations and not for single instructions**, which is Doug's point measured: one
instruction is under the floor and a sequence is over it by fifteen times. The two long readings agree at about 14
ticks for the instruction between them, from two questions that share nothing, and by that the reading is the part's,
never the harness's.

Two things it is not. The floor is real and it was earned: at 20000 turns the move read 7.3 ns a turn one way and
3.7 ns the other way on the next run, and the first reading of this kind was noise reported as a finding. The tool now
times each coding three times, reads it at its least, and refuses a difference under the spread of a coding's own
takes. A reading of 14 ticks is a **latency** at one lane, where nothing hides it. Real code with occupancy hides most of it.
The ordering is likely right and the size is an upper bound.

**What an adversarial part would do.** Doug: "I can't think of any parts that behave counter to this unless they're
engineered specifically to ... some parts in the future might intentionally obfuscate their faster operations, but
it would just be a simple sequence, because anything more than that would slow it down." That is the right bound: an
obfuscation has to be cheap or it defeats its own purpose, and it can only be a pattern match. And the pattern this
harness presents is the easiest one there is - 400000 turns of one identical body in a tight loop, the shape of a
bench and of no other code. The answer is not to trust the part but to stop looking like a bench:
interleave the codings, vary the turns, and put the coding in real work. That is better measurement anyway, since a
tight loop of one body reads the loop and not the coding in the place it will actually stand.

## The four that block, 29 Sep
- **count_add** wants an atomic add. The only one widening reaches is RED.E.ADD.INVALID12, a modifier the
  disassembler will not name, which the widening round deliberately refuses. This one needs a new question: a kernel
  that does an atomic add, through the PTX probe, as every other operation was learned.
- **open_launch, launch_load and program_unit** are one decision, not three. The lane is a function the resident
  calls and returns from through R20 (sass.krs, `return`), and program_unit is that resident. What the resident
  passes and where is a calling convention, and it is ours: we write both sides. The part showed one call and its
  shape - the caller sets R20 and R21 to the return address with MOV 32@lo and 32@hi, arguments sit in the low
  registers, and CALL.ABS.NOINC jumps (form_24, the divide's call to __cuda_sm20_div_u64). Nothing says which
  registers carry the launch pointer and the lane number, because nothing has ever called our lane.
- launch_load needs somewhere to keep the launch pointer. PTX writes `%launch`, a register ptx.krs declares
  privately in declare_fixed_wides and the schema's fixed list does not hold. SASS has no declarations, and sass.krs
  cannot invent one: it must reserve a pair below the file, as it reserves R240 to R253, and register_file_holds()
  must come down to match.
4. Not a blocker: scheduling. The safe order is proved on 26 kernels. What the instructions actually need, against
   what a listing carries, is later work.

## Widening, 29 Sep
sass.krs named three instructions no listing ever held - ISETP.EQ.U32.AND, ISETP.EQ.U32.AND.EX and ISETP.LT.AND, for
test_zero, test_wide_equal and test_negative - because the compiler read zero and below off the negations of NE and
GE. They were written by analogy with the comparisons that were seen, and nothing caught it: the ruleset_read suite
checks a form's text against what the listing gave, and those three forms are not in its list.

maint/engine/sass_krs_check.sh is the check that was missing, and it needs no device and no toolchain: every form
sass.krs writes, assembled against the part's machine file. A parameter's kind is not guessed from its name, because
one name is two things in two forms (`left` is a register in word_and and a predicate in predicate_xor), and each form
is written with every assignment of register, predicate and number to its parameters and holds where any one
assembles. 55 of sass.krs's 58 forms that carry an instruction assemble; the 3 refused are exactly those three
comparisons. Running it also found that the assembler could not read the text sass.krs writes at all: it stripped
leading spaces, as a listing has, and never tabs, as a ruleset has: 0 of 58 assembled before the reader was fixed
to treat a tab as the space it is. Every instruction ever assembled had come from an nvdisasm listing, and nothing had
asked the assembler to read the ruleset's own layout.

The fix for the three is to ask, not to guess. sass_machine_widen turns each of a listed form's 128 bits over,
decodes all 129, and takes every decode that prints a different operation as a form of its own. Asked by hand with
nvdisasm alone (maint/engine/sass_widen_ask.sh, sass_widen_all.sh - no device needed), over the 41 operations in
machines/sm_86:

- 242 operations come back, 202 the machine file does not hold.
- All three guessed spellings are there: the comparison is bits 76-78, unsigned is 73, .EX is 72. EQ.U32.AND is bit
  78 of GE.U32.AND, EQ.U32.AND.EX bit 78 of GE.U32.AND.EX, LT.AND bit 73 of LT.U32.AND.
- PLOP3.LUT, LDS and IMAD.WIDE.U32.X are reached too - the instructions items 2 and 3 want.

Run on the part, 29 Sep: 69 listed forms widen to 325, 0 without fields, and the 69 are byte for byte what they were.
All three comparisons were then asked in the part's own code, each where it should fire and where it should not, and
answered right every time. A form reached by turning one bit runs.

Two limits, both in the code. An operation the disassembler could not spell whole (LDG., RED.E.ADD.INVALID12) is
refused, since assembling from it would write bits nothing can say the part reads. And a widened form carries the
operand bits of the form it came from, which the new operation may read as something else: PLOP3.LUT is one bit from
SHF.L.U32 and decodes with a register where a predicate belongs, and no predicate operation can be written from that
form, and a second round does not fix it because the operand-kind field is more than one bit from "register". For an
operation whose operands land right, widening hands over a form ready to assemble; for one whose operands do not, it
says only that the encoding is legal.

## Pending Doug
- Move cell_tracking into anchor_sift/examples/ and theory into anchor_sift. Don't start without his direction.

## Roles
- Theorist writes engine_table and posits; send it every hash and measured number.
