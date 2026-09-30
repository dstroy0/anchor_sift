# Engine plan

**objective**: given a target's ruleset, compile a program to it, and prove it is the same program on every target
that answers as the host does, word for word. Where the ruleset is unknown, derive it by asking the target.

**method**: the transpiler learns `L*` by putting questions to the target and reading what comes back. sm_86 is the
first subject, not the target. The rest are x86, AMD GPU, AArch64, RISC-V, Xtensa and VHDL.

**oracle**: nvdisasm and ptxas answer questions. No vendor source is read and no shipped ELF is taken apart to learn
a rule. Asking an oracle keeps this clean room.

Finished work lives in the engine table, `theory/workbooks/engine/engine_table.md`. What is written here is open.

## File types

    .kcr   Kolmogorov information crystal
    .krs   Kolmogorov information ruleset: one language's forms
    .kcs   Kolmogorov information crystal reconstruction set
    .knf   Kolmogorov noise floor
    .kdm   Kolmogorov device map
    .ksc   Kolmogorov system classification

Doug names these. Do not add one.

## Open

1. **88 lines of 3200 find no form.** SEL with a number where Ra goes. No such encoding exists: all 34 forms the
   part has with a number in the first source slot are single source, BREV, FLO, IABS, I2I, LDC, B2R and BAR.
   sass.krs hands `wide_select` and `word_select` a number for `chosen`. Three fixes, none measured: always through
   the file's scratch, a MOV every time; invert the predicate, free, and misses the 52 where both sources are
   numbers; or write the number into a register in the generator, which wants a scratch from the allocator.

2. **count_add** wants an atomic add. The search reaches only `RED.E.ADD.INVALID12`, which nvdisasm will not name.
   Needs a kernel that does an atomic add, through the PTX probe, as every other operation was learned.

3. **The width-counted node is not designed.** 87 of the schema's 99 words wait on it in `word_web.h`. Adders,
   multiplies, rotates, sign-spreads and zero-tests all need it.

4. **S2R carries only SR_LANEID, SR_CTAID.X and SR_TID.X.** A clock read is one bit away and is kept as nothing,
   because a form is keyed on its operation and its operand kinds, and SR_CLOCKLO is the kind SR_CTAID.X is. Keying
   on named operands too splits every S2R into one form per system register.

5. **.kdm is named and not written.** The device map wants the subtrees a part has a word for, the cost of each,
   and how each was learned.

6. **The compile channel in .ksc reads 0.** It runs in another process, uninstrumented. Run and decode and clock
   all read.

7. **VHDL is a target on the Pi**, built on the `cell_tracking` branch at `bbc464b`, off main. State forms cut the
   program into clock states and `vhdl.krs` writes a clocked entity. In progress, uncommitted, and the device
   writes where the host refuses.

8. **The suite takes about 40 minutes**, dominated by one decode a form. It grows with whatever the search finds.

9. **Not proved.** The whole test matrix has not run since the machine file was replaced. `cell_ptx`
   test_signed_zero is stale.

## Pending Doug
- Move cell_tracking into `examples/` and theory into anchor_sift. Don't start without direction.

## Roles
- Theorist writes the engine table and posits. Send it every hash and measured number.
