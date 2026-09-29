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
  Data: build/harness/cell_sass/sass/ (form_N.sass, *.elf, opcode_XXX.bits).
- Known failures: VHDL lane in codegen_device (device writes where host refuses); cell_ptx test_signed_zero stale.

## SASS findings (sm_86)
- Rd 16-23, Ra 24-31, Rb 32-39, Rc 64-71, RZ 255. Immediates 32-63. Bits 9-11: operand B kind (1 reg, 4 imm, 5 const).
- Guard predicate 12-15. Predicate operands 81-83, 84-86, 87-90 (90 negates).
- Control 105-127: stall 4, yield, write barrier, read barrier, wait mask 6, reuse 4.
- Carry through one predicate (IADD3.X ..., P0, ..., P0). .E memory reads descriptor in UR4 (c[0x0][0x118]).
- ELF: between single-kernel cubins only .text + its size, register count (sh_info top byte, EIATTR_REGCOUNT),
  EIATTR_EXIT_INSTR_OFFSETS change. Params (u64, u64, u32) fix the constant bank. wide_divide adds __cuda_sm20_div_u64.

## Next
1. sass.krs complete enough that the cell writes its own probes in SASS and queries the rest of the instruction set.
   The classifier stopped responses that wrote sass.krs or a cubin writer in this session.

## Pending Doug
- Move cell_tracking into anchor_sift/examples/ and theory into anchor_sift. Don't start without his direction.

## Roles
- Theorist writes engine_table and posits; send it every hash and measured number.
