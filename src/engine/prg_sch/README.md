# Writing a program for the machine

**Purpose:** how to write a program the engine's record machine runs, from the steps to the sweep, and which of the
machine's files carry it today.

**Scope:** the record machine behind `engine_record_imprint`, `engine_record_sweep` and `engine_record_host`
(`engine/engine.h`), built from `base/keymath` (the imprint), `base/key_schedule` (the layout) and `base/cycle`
(the run). Every rule below is read from that code, and the worked example is `test/record_guide_test.cu`, which
builds and runs it as written here.

## What a program is

A program is a list of **steps** in order. Each step is one operation, and its value is held in a **register**
named by the step's number. A step reads only steps before it; a program is straight-line and has no branch
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
imprint derives them from the operands (`keymath_record_imprint`); no width is declared by hand.

| operation | reads | value | width |
|---|---|---|---|
| `ENGINE_RECORD_FIELD` | field `left` of member `member` | the field as an unsigned integer | the field's bits |
| `ENGINE_RECORD_FIELD_SIGNED` | field `left` of member `member` | the field as two's complement | the field's bits |
| `ENGINE_RECORD_CONSTANT` | nothing | `left + 2^32 · right`, never negative | the constant's bits |
| `ENGINE_RECORD_SUM` | `left`, `right` | left + right | the wider operand + 1 |
| `ENGINE_RECORD_DIFFERENCE` | `left`, `right` | left − right | the wider operand + 1 |
| `ENGINE_RECORD_PRODUCT` | `left`, `right` | left · right | the two widths added |
| `ENGINE_RECORD_ABSOLUTE` | `left` | \|left\| | left's width |
| `ENGINE_RECORD_COMPARE` | `left`, `right` | −1, 0 or +1: the sign of left − right | 1 |
| `ENGINE_RECORD_QUOTIENT` | `left`, `right` | left / right, rounded toward zero | left's width |
| `ENGINE_RECORD_REMAINDER` | `left`, `right` | left − quotient · right, with left's sign | the narrower operand |
| `ENGINE_RECORD_GCD` | `left`, `right` | gcd(left, right), never negative | the wider operand |
| `ENGINE_RECORD_EXACT_QUOTIENT` | `left`, `right` | left / right, where right divides left | left's width |
| `ENGINE_RECORD_LADDER` | `left`, `right` | how many rungs F · right ≤ \|left\| hold, F running 1, 1, 2, 3, 5, … over 91 rungs and stopping at the first that fails, with left's sign | 7 |
| `ENGINE_RECORD_TABLE` | step `left`, table `right` | the table's entry at the low `index_bits` of left's magnitude | the table's `out_bits` |

A register of 0 bits is given 1.

A comparison and two sums make a selector with no branch. `[a > b]` is `(c + |c|) / 2` with `c = COMPARE(a, b)`,
and a choice is a product: `x + [a > b] · (y − x)`.

## Records and fields

A member's records are arrays of 32-bit limbs, `in_limbs[member]` of them to a record. A **field** is a run of
bits at a fixed place in its member's record. The program declares its fields by number:

- `field_bits[f]`: the field's width.
- `field_offset[f]`: the bit the field starts at within its member's record.
- `in_limbs[m]`: member m's record length, in limbs.

The member a field is read from is the `member` of the step that reads it. A field must fit its member's record,
or the layout refuses.

## Outputs

`outputs` lists the steps whose registers are written out. They are packed into the output record in the order
listed, starting at bit 0, each **one bit wider than its register** so the sign fits, as two's complement.
`engine_record_imprint` returns each output's place in `output_offset[]` and `output_bits[]`. The record's length
in limbs is the total bits rounded up. An output must name a real step, and a step may be named only once.

## Imprint, layout, load

```c
const EngineRecordRequest request = {steps, count, field_bits, field_offset, fields,
                                     {in_limbs0, in_limbs1, in_limbs2}, members,
                                     outputs, output_count, output_offset, output_bits,
                                     tables, table_count, reuse};
CycleRecord *record = NULL;
EngineError error = {0};
if (engine_record_imprint(&request, &record, &error) == ENGINE_REFUSED) { /* the error says which part */ }
```

`engine_record_imprint` makes three calls (`engine/engine.cu`):

1. **The imprint** (`keymath_record_imprint`) checks that every step reads only earlier steps, derives every
   register's width, and checks the fields, the tables and the outputs. The result is the program's **key**.
2. **The layout** (`key_schedule_record_lay`) places every register in the lane's **register file** and every
   output in the output record. With `reuse` set, a register is freed once its last reader has run; a long
   program fits a small file.
3. **The load** (`cycle_record_load`) puts the layout on the device. A program's file of at most 64 limbs runs
   in the 64-limb kernel, and a larger one in the 256-limb kernel. Only a program that divides carries the
   scratch its divisions need.

The imprint and the layout are the serial work, done once. The sweep then runs that key over every lane
([imprint_key_cycle.md](../../../theory_bucket/cell_tracking/imprint_key_cycle.md)).

## Sweeping

```c
unsigned long long microseconds = 0;
const EngineRecordSweep sweep = {record, {member0, member1, member2}, {bodies0, bodies1, bodies2},
                                 index, lanes, out, &microseconds, &error};
engine_record_sweep(&sweep);    // on the device; returns the lanes run, or ENGINE_REFUSED
engine_record_host(&request, &sweep);  // the same program on the host, from the exact integer library
```

- `magnitudes[m]` is member m's records on the host, and `bodies[m]` is how many there are. The sweep copies
  them to the device itself.
- With `index` NULL, lane i reads record i of every member. With an index, lane i reads record
  `index[i · members + m]` of member m. That is how one record is shared by every lane, or how a lane gathers
  its inputs from anywhere in a member. An index names a record by a 32-bit number.
- `out` receives `lanes` output records.
- A lane is **refused** when a division meets a zero divisor, an exact quotient meets a remainder, a ladder's
  `right` is not positive, a value outgrows its register, or an index names a record past its member. One
  refused lane refuses the whole sweep.
- **The port check.** `engine_record_host` runs the same program with the exact integer library as every step.
  A new program is proved by the device's records equaling the host's word for word, as every test and the
  tracking driver do.

A program has no loop. To iterate, sweep again with this sweep's outputs as the next sweep's members.

## Tables

`ENGINE_RECORD_TABLE` is a one-variable function stored as values. It is how a nonlinear step with no closed form
enters a program. A table gives `index_bits` (1 to 32) and `out_bits`, and holds `2^index_bits` entries of
`(out_bits + 31) / 32` limbs each. `index_bits` must not exceed its source register's width. A table can be filled
by running another program over every index (`test/record_table_test.cu`).

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

`test/record_guide_test` runs this program over 1,000 bodies with dt = 37. The device's records equal the host's
word for word, and every x' and sign decode to the arithmetic done directly. A version whose step 6 read itself
is refused at imprint, and an index past its member is refused at the sweep. 11 checks, 0 failed.

## The machine's files

| file | what it holds | state |
|---|---|---|
| `.cfg` | a run's configuration, JSON (`cfg/`, read by `run_cfg` through `base/cfg_json`) | built for the tracking runs |
| `.sch` | the schedule: `schedule_program` (`base/schedule`) measures the tower (the device's memory), plans against two thirds of what is free, and writes the stages, each with the bytes it needs, as JSON (`nbody_program/program.json`) | written for the tracking runs; nothing reads the stages back |
| `.imp` | a math key: a program imprinted onto the impulse, carrying the program so it can be verified | the container kind is reserved (`APXREP_KIND_KEY`, `base/apxrep`); no writer or reader yet |

Until `.imp` is written and read, a program lives as its step list in the source that sweeps it, and is imprinted
each run.

## What the machine refuses today

These are the machine's own limits, from `engine_config.h` and the code above:

- at most `ENGINE_RECORD_STEPS_MAX` (1024) steps;
- 1 to `ENGINE_RECORD_MEMBERS_MAX` (3) members;
- a register of at most 32 · `ENGINE_RECORD_LIMBS_MOST` bits (8,192);
- a register file of at most `ENGINE_RECORD_LIMBS_MOST` (256) limbs live at once;
- an index of 32 bits;
- a table index of at most 32 bits.
