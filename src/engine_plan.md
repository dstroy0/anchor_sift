# Engine plan

**objective**: compile a program written in gnascor to any language, including one nobody has met, and prove it is
the same program everywhere. Where the language is unknown, derive it by asking.

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
    .kcs   Kolmogorov information crystal reconstruction set
    .knf   Kolmogorov noise floor
    .kdm   Kolmogorov device map
    .ksc   Kolmogorov system classification

Doug names these. Do not add one.

## How this is worked

Build the compiler and run it live. A test that takes forty minutes is not a development cycle and is not to be
run. The device is the first target because it is the hard one; every other language falls out of a compiler that
works there.

## Open

1. **Nothing searches for a writing.** No file of relations is emitted, run and read back, which leaves every
   writing unconfirmed by any target. `L*` is written by hand for want of this. It is the loop and it is the work.

2. **`.kdm` is written by nothing.** It wants every arrangement of primitives that produces an operator, each with
   its cost. The clock already reads codings against one another in the part's own time and the reading is thrown
   away instead of kept against an operator.

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

## Pending Doug
- Move cell_tracking into `examples/` and theory into anchor_sift. Don't start without direction.

## Roles
- Theorist writes the engine table and posits. Send it every hash and measured number.
