# Writing a program for the machine

**Purpose:** how to write a program the engine's record machine runs, from the steps to the sweep, and which of the
machine's files carry it today.

**Scope:** the record machine behind `engine_record_encode`, `engine_record_sweep` and `engine_record_host`
(`engine/engine.h`), built from `compiler/keymath` (the imprint), `compiler/key_schedule` (the layout) and `compiler/cycle`
(the run). Every rule below is read from that code, and the worked example is `utils/test/src/cu/engine/analysis/cycle/record_guide_test.cu`, which
builds and runs it as written here.

## What a program is

A program is a list of **steps** in order. Each step is one operation, and its value is held in a **register**
named by the step's number. A step reads only steps before it. A program is straight-line and has no branch
and no loop. A program runs once per **lane**. A lane reads one **record** from each of 1 to 3 **members**, the
kinds of record the program takes in, and writes one output record. A sweep runs every lane at once.

Every value is an exact signed integer. Nothing is a float and nothing rounds.

```c
typedef struct
{
    EngineRecordOperation operation;
    unsigned int left;   // a step number, a field number, a constant's low word, or a table's source step
    unsigned int right;  // a step number, a constant's high word, or a table number
    unsigned int member; // the member a field is read from
} EngineRecordStep;
```

## The operations

`left` and `right` name earlier steps unless the row says otherwise. The width is the register's bits as the
imprint derives them from the operands (`keymath_record_encode`), and no width is declared by hand.

| operation | reads | value | width |
|---|---|---|---|
| `ENGINE_RECORD_FIELD` | field `left` of member `member` | the field as an unsigned integer | the field's bits |
| `ENGINE_RECORD_FIELD_SIGNED` | field `left` of member `member` | the field as two's complement | the field's bits |
| `ENGINE_RECORD_CONSTANT` | nothing | `left + 2^32 · right`, never negative | the constant's bits |
| `ENGINE_RECORD_SUM` | `left`, `right` | left + right | the wider operand + 1, or the linear form's bound where fewer |
| `ENGINE_RECORD_DIFFERENCE` | `left`, `right` | left − right | the wider operand + 1, or the linear form's bound where fewer |
| `ENGINE_RECORD_PRODUCT` | `left`, `right` | left · right | the two widths added; by a constant, the linear form's bound where fewer |
| `ENGINE_RECORD_ABSOLUTE` | `left` | \|left\| | left's width |
| `ENGINE_RECORD_COMPARE` | `left`, `right` | −1, 0 or +1: the sign of left − right | 1 |
| `ENGINE_RECORD_QUOTIENT` | `left`, `right` | left / right, rounded toward zero | left's width |
| `ENGINE_RECORD_REMAINDER` | `left`, `right` | left − quotient · right, with left's sign | the narrower operand |
| `ENGINE_RECORD_GCD` | `left`, `right` | gcd(left, right), never negative | the wider operand |
| `ENGINE_RECORD_EXACT_QUOTIENT` | `left`, `right` | left / right, where right divides left | left's width |
| `ENGINE_RECORD_LADDER` | `left`, `right` | how many rungs F · right ≤ \|left\| hold, F running 1, 1, 2, 3, 5, … over 91 rungs and stopping at the first that fails, with left's sign | 7 |
| `ENGINE_RECORD_TABLE` | step `left`, table `right` | the table's entry at the low `index_bits` of left's magnitude | the table's `out_bits` |
| `ENGINE_RECORD_XOR` | `left`, `right` | left xor right, on the two's complement of each, sign-extended without end | the wider operand + 1; the wider operand where both are never negative |
| `ENGINE_RECORD_AND` | `left`, `right` | left and right, the same way | the wider operand + 1; the never-negative operand's width where one is, the narrower where both are |
| `ENGINE_RECORD_WRAP` | `left`, and `right` as a width of 4 or more | left modulo 2^right, read back signed, in [−2^(right − 1), 2^(right − 1)) | the fewer of left's width and `right` |
| `ENGINE_RECORD_LANE` | nothing | the lane's own number ℓ, the one the sweep runs it as, never negative | 64 (`ENGINE_RECORD_LANE_BITS`) |

A register of 0 bits is given 1.

The imprint also carries every register as a **linear form**: integer coefficients over **atoms**, plus a constant.
- A sum or a difference adds its operands' forms, and terms that cancel drop out.
- A product by a constant, a register whose form has no atoms, scales the other operand's form.
- A constant is its own value, and a wrap that passes its register through keeps that register's form.
- Every other register, fields included, is an atom with coefficient 1. So is a register whose coefficients or
  constant would pass 2^62.

The form bounds the value: |x| ≤ |c| + Σ |c_i| · (2^(b_i) − 1), over the atoms' widths b_i. Where that bound needs
fewer bits than the operation's own rule, the register takes the fewer. (a − b) + b, with the same b, is a's width,
and a Gaussian floor (a − b, a + b) grows half a bit a floor, as its values do, not a whole bit
(`utils/test/src/cu/engine/analysis/cycle/record_gaussian_test.sh`).

The imprint knows some registers are **never negative**:
- a field read unsigned;
- a constant;
- an absolute value;
- a gcd;
- a table's entry;
- the lane's number;
- a sum, product, quotient, exact quotient or xor of two never-negative registers;
- a remainder of a never-negative register;
- an and with a never-negative register.

An and with such a register lies between 0 and it, and an xor of two lies below the wider's top. Neither takes the extra bit. A round on fixed-width words therefore keeps its words at their width.

The bitwise operations read each operand as though its two's complement ran on forever. The xor is then negative
where exactly one operand is, and the and where both are. The extra bit is needed because −1 xor (2^n − 1) is −2^n. A wrap
narrower than 4 bits errors at imprint. A register already inside the wrap's signed range passes through
unchanged. The unsigned residue modulo 2^w is the and with the constant 2^w − 1. A 32-bit word's add is a sum
followed by that and with `0xFFFFFFFF`, and its not is the xor with `0xFFFFFFFF`.

A comparison and two sums make a selector with no branch. `[a > b]` is `(c + |c|) / 2` with `c = COMPARE(a, b)`,
and a choice is a product: `x + [a > b] · (y − x)`.

## Records and fields

A member's records are arrays of 32-bit limbs, `in_limbs[member]` of them to a record. A **field** is a run of
bits at a fixed place in its member's record. The program declares its fields by number:

- `field_bits[f]`: the field's width.
- `field_offset[f]`: the bit the field starts at within its member's record.
- `in_limbs[m]`: member m's record length, in limbs.

The member a field is read from is the `member` of the step that reads it. A field must fit its member's record,
or the layout errors.

## Outputs

`outputs` lists the steps whose registers are written out. They are packed into the output record in the order
listed, starting at bit 0, each **one bit wider than its register** so the sign fits, as two's complement.
`engine_record_encode` returns each output's place in `output_offset[]` and `output_bits[]`. The record's length
in limbs is the total bits rounded up. An output must name a real step, and a step may be named only once.

## Imprint, layout, load

```c
const EngineRecordRequest request = {steps, count, field_bits, field_offset, fields,
                                     {in_limbs0, in_limbs1, in_limbs2}, members,
                                     outputs, output_count, output_offset, output_bits,
                                     tables, table_count, reuse};
CycleRecord *record = NULL;
EngineError error = {0};
if (engine_record_encode(&request, &record, &error) == ENGINE_ERROR) { /* the error says which part */ }
```

`engine_record_encode` makes three calls (`engine/engine_*.cu`):

1. **The imprint** (`keymath_record_encode`) checks that every step reads only earlier steps, derives every
   register's width, and checks the fields, the tables and the outputs. The result is the program's **key**.
2. **The layout** (`key_schedule_record_layout`) places every register in the lane's **register file** and every
   output in the output record. With `reuse` set, a register is freed once its last reader has run. A long
   program then fits a small file.
3. **The load** (`cycle_record_load`) puts the layout on the device. A program's file of at most 64 limbs runs
   in the 64-limb kernel, and a larger one in the 256-limb kernel. Only a program that divides carries the
   scratch its divisions need.

The imprint and the layout are the serial work, done once. The sweep then runs that key over every lane
([imprint_key_cycle.md](../../../theory/workbooks/engine/imprint_key_cycle.md)).

## How the device runs a program

The load also builds the program for the device (`compiler/cycle/cycle_compile_*.cu`), trying three ways in order:

1. **PTX.** The lane is written in PTX, NVIDIA's assembly, and nvJitLink assembles it as it links it against the
   **operator block**, where every operation is compiled once for the device. Each step is unrolled at its widths
   into straight-line code over registers the lane holds itself:
   - a sum or a difference is carry chains through its limbs;
   - a product is its schoolbook rows, one limb product at a time;
   - a division by one limb is a long division from the top limb.

   A step that loops on its values calls into the operator block, and its operands pass through shared memory.
   Those steps are a gcd, a ladder, a division by more than one limb, and a product of more than 1,024 limb
   products.

   Each word of the output record is stored as soon as the last step that lays it has run. The lane does not
   hold its outputs to its end. With `CYCLE_RECORD_REPORT=1` the load says the most words a lane holds live at once.

   **Rule (i).** Once the PTX is built, its local frame, the bytes a thread spills past its registers, is read
   against the device's stack limit. A frame within the limit runs. A frame past it makes the runtime grow the stack
   for every resident thread at a run's first launch, and the stack is given back once the run is done: 7.4 to
   10.1 ms a run on the record tests, against 0.1 to 1.6 ms for frames within the limit. The program is then built
   as C source as well, and whichever of the two has the smaller frame runs; the other build is released.
2. **C source.** Where the lane cannot be written in PTX, it is C source, each step one call into the operator block.
   NVRTC compiles it and nvJitLink links it the same way. Its registers lie in shared memory.
3. **The interpreter.** Where neither builds, the interpreter runs the program. It is also the oracle both are held to.

Each build is kept in a cache: `$CYCLE_CACHE`, else `%LOCALAPPDATA%\cycle` or `~/.cache/cycle`. A build is found
by its text and used only where that text matches byte for byte.

The lane's text is written from a **ruleset**, one for each of the first two ways: `../../cu/transpiler/codegen/rulesets/ptx.krs` for
PTX and `../../cu/transpiler/codegen/rulesets/c.krs` for C source, read once a process from that folder, or from the folder
`$CYCLE_RULESETS` names. The code generator decides what each step does, and the ruleset decides how the target writes it.
Its base class, `Target` (`../../cu/transpiler/codegen/target.h`, `compiler/codegen/target_*.cu`), reads and writes rulesets and names no language. Each language
is a class that inherits it, in files of its own: `PtxTarget` (`ptx_target.{h,cu}`) and `CTarget`
(`c_target.{h,cu}`). The record machine picks the language.
A ruleset is a text file whose first line is `krs 1`, and every other line is one entry:
- `ruleset`, `toolchain` and `header` name the target, what builds its text and where the text's opening lines
  come from;
- `bank` writes a bank of registers, `{n}` the register's number, and `fixed` writes one register the lane holds
  throughout;
- `form` names a piece of text and its parameters, and the text is the rest of the line after `= `, where `{p}` is
  parameter p's argument and `\t`, `\n` and `\\` are a tab, a line's end and a backslash;
- `construct` gives a form as one built from more basic ones: its head is the form's name and parameters, with no
  text, and its lines run to `end`. Each line is a form, or a construct given earlier in the file, and its
  arguments, split at spaces. An argument that is one of the construct's parameters stands for that parameter's
  argument, `{bank:n}` for scratch register n of one of the ruleset's banks, and any other word for itself. Each time
  the form is written, its construct's lines are written in its place, and each scratch register is a fresh one: in
  PTX, one of the step's own temporaries, 64-bit temporaries or predicates, declared with them. A ruleset may give a
  form as a form or as a construct, not both. `utils/test/src/cu/transpiler/codegen/rulesets/flagless/ptx.krs` gives the carry chains and the
  product this way, with no instruction that sets or reads the condition code.

A line that begins with `#` is a comment. The code generator lists every form, bank and register it needs, with the
parameters each takes. A ruleset that lacks one, holds one the code generator does not name, or gives one other
parameters errors on whole, and the report says why. An errored `ptx.krs` sends its programs to the C source, and an
errored `c.krs` leaves a program the PTX does not hold on the interpreter.

A compiled program runs on as many thread blocks as the device holds at once, or fewer where the lanes need fewer.
Each launch chooses its own thread count: as many threads as the registers' shared memory holds, or, where the
lanes are few, each processor's share of them in whole warps. A launch of a few thousand lanes then reaches every
processor, not only a few thread blocks' worth.

Six switches, read at each load or run:

| switch | effect |
|---|---|
| `CYCLE_RECORD_INTERPRET=1` | every program stays on the interpreter |
| `CYCLE_RECORD_CHECK=1` | every launch runs both, and a launch whose records or errors differ errors |
| `CYCLE_RECORD_REPORT=1` | stderr says how each program was built and how long each kernel ran |
| `CYCLE_RECORD_TTL=<microseconds>` | a launch's time to live |
| `CYCLE_RECORD_LTO=1` | the operator block and the programs are built as LTO-IR and linked with link-time optimization; no PTX is written |
| `CYCLE_RECORD_NVRTC=1` | every lane is written as C source |

## Sweeping

```c
unsigned long long microseconds = 0;
const EngineRecordSweep sweep = {record, {member0, member1, member2}, {bodies0, bodies1, bodies2},
                                 index, lanes, out, &microseconds, &error};
engine_record_sweep(&sweep);    // on the device; returns the lanes run, or ENGINE_ERROR
engine_record_host(&request, &sweep);  // the same program on the host, from the exact integer library
```

- `magnitudes[m]` is member m's records on the host, and `bodies[m]` is how many there are. The sweep copies
  them to the device itself.
- With `index` NULL, lane i reads record i of each member, or the member's one record where it holds only one. One
  shared record is then read by every lane with nothing stored a lane, and with the lane's own number
  (`ENGINE_RECORD_LANE`) the lanes enumerate a range from it: x = base + ℓ. With an index, lane i reads record
  `index[i · members + m]` of member m. That is how a lane gathers its inputs from anywhere in a member. An index
  names a record by a 32-bit number, and the lane's number is still i, not the record it reads. With no index, a
  member holding more than one record and fewer than the lanes errors on the sweep before any lane runs.
- `out` receives `lanes` output records.
- A lane is **errored** when a division meets a zero divisor, an exact quotient meets a remainder, a ladder's
  `right` is not positive, a value outgrows its register, or an index names a record past its member. One
  errored lane errors on the whole sweep.
- **The port check.** `engine_record_host` runs the same program with the exact integer library as every step.
  A new program is proved by the device's records equaling the host's word for word, as every test and the
  tracking driver do.

A program has no loop. An iteration of known length is unrolled into the program as **floors**: each floor is a
round of steps reading the floor below it, and its last steps, often wraps, leave the state the next floor reads.
There is no step limit. With `reuse` set, the register file holds only a floor's live state and the round
in flight. One sweep then runs the whole stack in one launch. `utils/test/src/cu/engine/analysis/cycle/record_bitwise_test.sh` stacks 700 floors, 4,204
steps, in an 8-limb file. An iteration whose length depends on the data sweeps again, with this sweep's outputs
as the next sweep's members.

## The latch

The latch is the first lane that meets a condition: min{ℓ : cond(ℓ)}, or none. A program makes its condition an
output, such as the selector `[a > b]` above, 0 or 1. `cycle_record_latch` (`compiler/cycle/cycle.h`) reads a sweep's
records where they lie on the device and returns the least lane whose output at `offset`, `bits` wide, is not zero,
or `CYCLE_LATCH_NONE` where no lane's is:
- each thread scans its lanes from its lowest and stops at its first hit;
- each warp takes the least of its threads' by a tree of shuffles;
- one atomic minimum takes the least of the warps'.

Only the lane comes back to the host. The minimum is associative, commutative and idempotent. This grouping
returns the lane a serial scan from lane 0 returns. `cycle_record_latch_host` is that scan, over records on the host.
The latch is a call on `compiler/cycle`. `engine_record_sweep` copies every record back to the host, and a latch through
the engine's own entry is not built.

`utils/test/src/cu/engine/analysis/cycle/record_lane_test.sh` enumerates x = base + ℓ over 65,536 lanes of one shared record and latches the first lane
whose hash of x falls under T, with base and T in that record. At six thresholds, from every lane to none, the device
latch over the interpreter's records and over the compiled program's, the host's scan and the host's own arithmetic
return the same lane. The host, the interpreter and the compiled program agree word for word. Over 2^24 lanes on the
device alone, the latch returns lane 428,243, which the host's arithmetic finds first. 17 checks, 0 failed.

## Tables

`ENGINE_RECORD_TABLE` is a one-variable function stored as values. It is how a nonlinear step with no closed form
enters a program. A table gives `index_bits` (1 to 32) and `out_bits`, and holds `2^index_bits` entries of
`(out_bits + 31) / 32` limbs each. `index_bits` must not exceed its source register's width. A table can be filled
by running another program over every index (`utils/test/src/cu/engine/analysis/cycle/record_table_test.sh`).

## A worked example

This program moves each body by its velocity over one shared time step and says which side of the origin the body
lands on: x' = x + v · dt, and sign(x'). The bodies are member 0, each record holding x (32 bits, signed) at bit 0
and v (16 bits, signed) at bit 32, in 2 limbs. The time step is member 1, one record holding dt (16 bits) in 1 limb.

| step | operation | left | right | member | register |
|---|---|---|---|---|---|
| 0 | `FIELD_SIGNED` | field 0 | | 0 | x, 32 bits |
| 1 | `FIELD_SIGNED` | field 1 | | 0 | v, 16 bits |
| 2 | `FIELD` | field 2 | | 1 | dt, 16 bits |
| 3 | `PRODUCT` | 1 | 2 | | v · dt, 32 bits |
| 4 | `SUM` | 0 | 3 | | x', 33 bits |
| 5 | `CONSTANT` | 0 | 0 | | 0 |
| 6 | `COMPARE` | 4 | 5 | | sign(x'), 1 bit |

```c
field_bits   = {32, 16, 16};
field_offset = {0, 32, 0};        // field 2 is at bit 0 of member 1's record
in_limbs     = {2, 1};
outputs      = {4, 6};
```

The imprint derives 32 bits for step 3, 33 for step 4 and 1 for step 6. The outputs pack as x' in bits 0 to 33
and sign(x') in bits 34 to 35, a 2-limb record. The index pairs every body with the one time-step record:
`index[2i] = i`, `index[2i + 1] = 0`.

`utils/test/src/cu/engine/analysis/cycle/record_guide_test.sh` runs this program over 1,000 bodies with dt = 37. The device's records equal the host's
word for word, and every x' and sign decode to the arithmetic done directly. A version whose step 6 read itself
errors at imprint, and an index past its member errors at the sweep. 12 checks, 0 failed.

## The machine's files

| file | what it holds | state |
|---|---|---|
| `.cfg` | a run's configuration, JSON (`cfg/`, read by `run_cfg` through `formats/cfg_json`) | built for the tracking runs |
| `.sch` | the schedule: `schedule_program` (`runtime/schedule`) measures the tower (the device's memory), plans against two thirds of what is free, and writes the stages, each with the bytes it needs, as JSON (`nbody_program/program.json`) | written for the tracking runs; nothing reads the stages back |
| `.imp` | a math key: a program imprinted onto the impulse, carrying the program so it can be verified | the container kind is reserved (`APXREP_KIND_KEY`, `formats/apxrep`); no writer or reader yet |

Until `.imp` is written and read, a program lives as its step list in the source that sweeps it, and is imprinted
each run.

## What the machine errors today

These are the machine's own limits, from `engine_config.h` and the code above:

- 1 to `ENGINE_RECORD_MEMBERS_MAX` (3) members;
- a register of at most 32 · `ENGINE_RECORD_LIMBS_MAX` bits (8,192);
- a register file of at most `ENGINE_RECORD_LIMBS_MAX` (256) limbs live at once;
- an index of 32 bits;
- a table index of at most 32 bits;
- a wrap of fewer than `ENGINE_RECORD_WRAP_BITS_LEAST` (4) bits.

The step count is not among them. A register's sign is held beside it in the file, and the step table is read
from device memory. A program can be as long as its register file allows.
