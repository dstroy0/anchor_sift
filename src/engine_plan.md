# Engine plan

## Rules
- No VHDL, Yosys, GHDL work unless Doug asks for that exact thing.
- No other architectures (Pi, RISC-V, Xtensa are off the list).
- Never propose removing the host build or host path; it is an entry point.
- Run the thing being built first. No host sweeps unasked.
- Harness for runs, no timeouts on queued runs. Work on main. No heredocs. No attribution. Don't make things up.
- Probes: small test kernels that ask one question and exit. Learn the ELF by reading their cubins with their tools
  (nvdisasm, cuobjdump -elf); never patch or inject.

## State (28 Sep)
- Device path by default: anchor_sift 80afd26. Record suites 21/22 pass; record_tower_c not rerun.
  record_order_c: two host programs (12293, 16379 steps) hit MSVC C1002 out of heap; suite passes.
- SASS probe: anchor_sift 3e0bdea, 74b02ac (biohub 10c43b9, 2fc7d55). cell_sass 25 questions, 33 operations, 0 failed.
  Data: build/<stamp>_cell_sass_test/sass/ (form_N.sass, *.elf, opcode_XXX.bits); rerun 28 Sep, same counts.
- sass.krs written from those listings, with sass_target and the ruleset_read suite (56 checks, 0 failed): every
  ruleset read against its schema, and each SASS form held to the instruction its question's listing gave.
- Cubin writer built (src/engine/compiler/cubin), all of it under cell_sass, one run, 28 Sep:
  - 69 shapes learned, each its operand fields found by turning its 128 bits over; written as machines/sm_86.kmc and
    read back with 0 differing. A shape is an operation with the kind and mark of each printed operand.
  - 976 instructions assembled from their text alone: 0 refused, 968 the very bytes the listing gave, 945 read back
    as the text they were written from, 31 (branches and relocations) held to their bytes.
  - 26 of 26 kernels written again into cubins of their own, loaded and run: every one answers what the toolchain's
    own cubin answered.
  - 10 questions asked in code no toolchain wrote (form_0's kernel with its arithmetic replaced): 10 answered as the
    question says.
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
    listing is not the whole instruction, which is why 968 of 976 match byte for byte and all 976 read back right.
  - The scheduler's bits are not in the text, so code written from text needs a schedule. What works: the longest
    stall, no reuse, a wait on every barrier, and a barrier set wherever the shape's own encoding set one. The last
    part is what makes it correct - without it every load reads stale and the answers come back 0 (measured).

## Next
1. What sass.krs leaves empty, because no question gave it: word_divide and wide_divide (no integer divide; a
   reciprocal over scratch a form's text cannot take, and a call to __cuda_sm20_div_u64); product_low and
   product_high (one IMAD.WIDE.U32 writes both halves into a pair); predicate_xor and predicate_and (the compiler
   folded both into the ISETP that set the operand); count_add, launch_load, open_launch, shared_open, shared_close
   and program_unit. Each is a question the next probe asks.
2. Two things sass.krs names that no listing prints, both for the theorist: .hi, the second register of a 64-bit pair,
   which a ruleset cannot name because it writes a register from its number alone; and the banks all being the one
   register file, so the code generator's per-bank numbering needs an allocation before it writes SASS.
3. Poke the instruction set: the cell can now ask a question in the part's own code and read the answer. Each shape
   it does not hold is one it cannot write, so widen the machine file - ask nvdisasm to decode encodings the probes
   have not seen (the bit fields say which bits to vary) and keep what comes back as new shapes.
4. A schedule of its own. The safe order runs everything one at a time. Reading the stall and barriers a listing
   carries, against what the instructions need, is the next measurement.
5. The register allocation sass.krs needs (item 2) is the same problem the cubin writer leaves open: the writer is
   given registers, it does not choose them.

## Pending Doug
- Move cell_tracking into anchor_sift/examples/ and theory into anchor_sift. Don't start without his direction.

## Roles
- Theorist writes engine_table and posits; send it every hash and measured number.
