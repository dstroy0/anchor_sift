# Every form's unprinted operands, asked of the part

Written by `interface_sass_probe_unprinted` (`interface_sass_unprinted.sh --forms`) whole on every run. Each form holding a run of an operand it does not print is written with its operands filled: its result R8, P0 or UR6, registers it reads R0 and R6 (0xb and 0x7), predicates it reads P1 (true), uniform registers UR4, a constant in bank 0 c[0x0][0x0], four copies to a run, each answering one word. A form that takes an address is written once a run with its address the answer's third word, R4 with 0x8 added, a register before the address R10 and one after it R0 and R6, and answers four words: the third word loaded back, the word it found, the third word, and 0. Every cubin declares 255 registers a thread. Each run is asked at every value where it is 6 bits or fewer, else at the form's own value with each bit turned, against what the form's own bits answer. A run every value of which answers alike is one the part does not read on that question.

| form | asked as | bits | the form holds | its own bits answer | values alike | values otherwise |
|---|---|---|---|---|---|---|
| `IMAD R2, R2, c[0x0][0x0], R3` | `IMAD R8, R0, c[0x0][0x0], R6` | 87-90 | 1111 | 00000b07 | 16 of 16 |  |
| `ISETP.GE.U32.AND P0, PT, R2, c[0x0][0x170], PT` | `ISETP.GE.U32.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `IMAD.WIDE.U32 R2, R2, R3, c[0x0][0x168]` | `IMAD.WIDE.U32 R8, R0, R6, c[0x0][0x0]` | 87-90 | 1111 | 0000014d | 16 of 16 |  |
| `IMAD.MOV.U32 R3, RZ, RZ, 0x20` | `IMAD.MOV.U32 R8, RZ, RZ, 0x20` | 87-90 | 1111 | 00000020 | 16 of 16 |  |
| `ISETP.NE.U32.AND P0, PT, R9, RZ, PT` | `ISETP.NE.U32.AND P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `IMAD R9, R0.reuse, R7.reuse, RZ` | `IMAD R8, R0, R6, RZ` | 87-90 | 1111 | 0000004d | 16 of 16 |  |
| `IMAD.MOV R9, RZ, RZ, -R7` | `IMAD.MOV R8, RZ, RZ, -R0` | 87-90 | 1111 | fffffff5 | 16 of 16 |  |
| `IMAD.HI.U32 R5, R5, R9, R4` | `IMAD.HI.U32 R8, R0, R6, R0` | 87-90 | 1111 | 00fffec0 | 16 of 16 |  |
| `ISETP.GE.U32.AND P0, PT, R6, R7, PT` | `ISETP.GE.U32.AND P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `IMAD.WIDE.U32 R6, R9, R0, R6` | `IMAD.WIDE.U32 R8, R0, R6, R0` | 87-90 | 1111 | 00000058 | 16 of 16 |  |
| `ISETP.GE.AND P2, PT, R2, RZ, PT` | `ISETP.GE.AND P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.AND P1, PT, R0.reuse, R5.reuse, PT` | `ISETP.GT.AND P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.AND P0, PT, R0, R5, PT` | `ISETP.NE.AND P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.AND P3, PT, R4, R7, PT` | `ISETP.LT.U32.AND P0, PT, R0, R6, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.U32.XOR P1, PT, R0, RZ, P0` | `ISETP.NE.U32.XOR P0, PT, R0, RZ, P1` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `IMAD.MOV.U32 R11, RZ, RZ, R8` | `IMAD.MOV.U32 R8, RZ, RZ, R0` | 87-90 | 1111 | 0000000b | 16 of 16 |  |
| `IMAD.WIDE.U32 R10, P0, R8, R3, R10` | `IMAD.WIDE.U32 R8, P1, R0, R6, R0` | 87-90 | 1111 | 00000058 | 16 of 16 |  |
| `IMAD.HI.U32 R10, P1, R9, R13, R10` | `IMAD.HI.U32 R8, P1, R0, R6, R0` | 87-90 | 1111 | 00fffec0 | 16 of 16 |  |
| `IMAD.MOV.U32 R2, RZ, RZ, c[0x0][0x160]` | `IMAD.MOV.U32 R8, RZ, RZ, c[0x0][0x0]` | 87-90 | 1111 | 00000100 | 16 of 16 |  |
| `UIMAD.WIDE.U32 UR4, UR6, UR8, UR4` | `UIMAD.WIDE.U32 UR6, UR4, UR4, UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `UIMAD UR6, UR6, UR9, URZ` | `UIMAD UR6, UR4, UR4, URZ` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD.U32 R16, RZ, RZ, UR4` | `IMAD.U32 R8, RZ, RZ, UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.U32.AND P0, PT, R12, c[0x0][0x1d8], PT` | `ISETP.NE.U32.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.AND P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.LT.U32.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `BAR.SYNC.DEFER_BLOCKING 0x0` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `CCTL.IVALL` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `ISETP.NE.U32.AND P0, PT, R2, UR4, PT` | `ISETP.NE.U32.AND P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.AND P1, PT, R18, 0x2, PT` | `ISETP.NE.U32.AND P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `IMAD.WIDE R2, R2, c[0x0][0x0], R3` | `IMAD.WIDE R8, R0, c[0x0][0x0], R6` | 87-90 | 1111 | 00000b07 | 16 of 16 |  |
| `IMAD.MOV R2, R2, 0x0, R3` | `IMAD.MOV R8, R0, 0x0, R6` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `IMAD.U32 R2, R2, c[0x0][0x0], R3` | `IMAD.U32 R8, R0, c[0x0][0x0], R6` | 87-90 | 1111 | 00000b07 | 16 of 16 |  |
| `IMAD R2, R2, c[0x0][0x0], -R3` | `IMAD R8, R0, c[0x0][0x0], -R6` | 87-90 | 1111 | 00000af9 | 16 of 16 |  |
| `ISETP.GE.U32.AND P0, PT, R2, 0x5c00, PT` | `ISETP.GE.U32.AND P0, PT, R0, 0x5c00, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GE.AND P0, PT, R2, c[0x0][0x170], PT` | `ISETP.GE.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GE.U32.OR P0, PT, R2, c[0x0][0x170], PT` | `ISETP.GE.U32.OR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.U32.XOR P0, PT, R2, c[0x0][0x170], PT` | `ISETP.GE.U32.XOR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.U32.AND P0, PT, R2, c[0x0][0x170], PT` | `ISETP.T.U32.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.U32.AND P0, PT, R2, c[0x0][0x170], PT` | `ISETP.GT.U32.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.EQ.U32.AND P0, PT, R2, c[0x0][0x170], PT` | `ISETP.EQ.U32.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GE.U32.AND P0, PT, R2, c[0x0][0x170], !PT` | `ISETP.GE.U32.AND P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `IMAD.U32 R2, R2, R3, c[0x0][0x168]` | `IMAD.U32 R8, R0, R6, c[0x0][0x0]` | 87-90 | 1111 | 0000014d | 16 of 16 |  |
| `IMAD.HI.U32 R2, R2, R3, c[0x0][0x168]` | `IMAD.HI.U32 R8, R0, R6, c[0x0][0x0]` | 87-90 | 1111 | 00000001 | 16 of 16 |  |
| `IMAD.WIDE.U32 R2, R2, R3, -c[0x0][0x168]` | `IMAD.WIDE.U32 R8, R0, R6, -c[0x0][0x0]` | 87-90 | 1111 | ffffff4d | 16 of 16 |  |
| `IMAD.WIDE R2, R2, R3, c[0x0][0x168]` | `IMAD.WIDE R8, R0, R6, c[0x0][0x0]` | 87-90 | 1111 | 0000014d | 16 of 16 |  |
| `IMAD.WIDE.U32 R2, P6, R2, R3, c[0x0][0x168]` | `IMAD.WIDE.U32 R8, P1, R0, R6, c[0x0][0x0]` | 87-90 | 1111 | 0000014d | 16 of 16 |  |
| `LEA.HI R7, R0, R7, RZ, 0x1c` | `LEA.HI R8, R0, R6, RZ, 0x1c` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `LEA.HI R7, P0, R0, R7, RZ, 0x1c` | `LEA.HI R8, P1, R0, R6, RZ, 0x1c` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `LEA.HI R7, R0, -R7, RZ, 0x1c` | `LEA.HI R8, R0, -R6, RZ, 0x1c` | 87-90 | 1111 | fffffff9 | 16 of 16 |  |
| `LEA.HI R7, P0, R0, -R7, RZ, 0x1c` | `LEA.HI R8, P1, R0, -R6, RZ, 0x1c` | 87-90 | 1111 | fffffff9 | 16 of 16 |  |
| `IMAD.MOV R3, RZ, RZ, 0x20` | `IMAD.MOV R8, RZ, RZ, 0x20` | 87-90 | 1111 | 00000020 | 16 of 16 |  |
| `ISETP.NE.U32.OR P0, PT, R9, RZ, PT` | `ISETP.NE.U32.OR P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.U32.AND P0, PT, R9, RZ, PT` | `ISETP.GT.U32.AND P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.U32.AND P0, PT, R9, RZ, PT` | `ISETP.T.U32.AND P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.AND P0, PT, R9, RZ, !PT` | `ISETP.NE.U32.AND P0, PT, R0, RZ, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `IMAD.HI.U32 R11, P0, RZ, 0x1, R0` | `IMAD.HI.U32 R8, P1, RZ, 0x1, R0` | 87-90 | 1000 | 00fffec0 | 16 of 16 |  |
| `IMAD.WIDE R9, R0.reuse, R7.reuse, RZ` | `IMAD.WIDE R8, R0, R6, RZ` | 87-90 | 1111 | 0000004d | 16 of 16 |  |
| `IMAD.MOV R9, R0.reuse, RZ.reuse, c[0x0][0x0]` | `IMAD.MOV R8, R0, RZ, c[0x0][0x0]` | 87-90 | 1111 | 00000100 | 16 of 16 |  |
| `IMAD.U32 R9, R0.reuse, R7.reuse, RZ` | `IMAD.U32 R8, R0, R6, RZ` | 87-90 | 1111 | 0000004d | 16 of 16 |  |
| `IMAD R9, R0.reuse, R7.reuse, -RZ` | `IMAD R8, R0, R6, -RZ` | 87-90 | 1111 | 0000004d | 16 of 16 |  |
| `IMAD.WIDE R9, RZ, RZ, -R7` | `IMAD.WIDE R8, RZ, RZ, -R0` | 87-90 | 1111 | fffffff5 | 16 of 16 |  |
| `IMAD.MOV R9, RZ, c[0x0][0x0], -R7` | `IMAD.MOV R8, RZ, c[0x0][0x0], -R0` | 87-90 | 1111 | fffffff5 | 16 of 16 |  |
| `IMAD.MOV.U32 R9, RZ, RZ, -R7` | `IMAD.MOV.U32 R8, RZ, RZ, -R0` | 87-90 | 1111 | fffffff5 | 16 of 16 |  |
| `IMAD.MOV R9, RZ, RZ, R7` | `IMAD.MOV R8, RZ, RZ, R0` | 87-90 | 1111 | 0000000b | 16 of 16 |  |
| `LEA.HI R4, R8, 0xffffffe, RZ, 0x1c` | `LEA.HI R8, R0, 0xffffffe, RZ, 0x1c` | 87-90 | 1111 | 0ffffffe | 16 of 16 |  |
| `IMAD.HI.U32 R5, R5, c[0x0][0x0], R4` | `IMAD.HI.U32 R8, R0, c[0x0][0x0], R6` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `IMAD.HI R5, R5, R9, R4` | `IMAD.HI R8, R0, R6, R0` | 87-90 | 1111 | 00fffec0 | 16 of 16 |  |
| `IMAD.HI.U32 R5, R5, R9, -R4` | `IMAD.HI.U32 R8, R0, R6, -R0` | 87-90 | 1111 | ff000140 | 16 of 16 |  |
| `ISETP.GE.U32.OR P0, PT, R6, R7, PT` | `ISETP.GE.U32.OR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.U32.XOR P0, PT, R6, R7, PT` | `ISETP.GE.U32.XOR P0, PT, R0, R6, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.EQ.U32.AND P0, PT, R6, R7, PT` | `ISETP.EQ.U32.AND P0, PT, R0, R6, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GE.U32.AND P0, PT, R6, R7, !PT` | `ISETP.GE.U32.AND P0, PT, R0, R6, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `@P0 LEA.HI R6, -R7, R6, RZ, 0x1c` | `LEA.HI R8, -R0, R6, RZ, 0x1c` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `IMAD.WIDE.U32 R6, R9, c[0x0][0x0], R6` | `IMAD.WIDE.U32 R8, R0, c[0x0][0x0], R6` | 87-90 | 1111 | 00000b07 | 16 of 16 |  |
| `IMAD.WIDE.U32 R6, R9, R0, -R6` | `IMAD.WIDE.U32 R8, R0, R6, -R0` | 87-90 | 1111 | 00000042 | 16 of 16 |  |
| `LEA R9, P0, R0, R0, 0x0` | `LEA R8, P1, R0, R6, 0x0` | 87-90 | 0000 | 00000012 | 16 of 16 |  |
| `ISETP.GE.OR P2, PT, R2, RZ, PT` | `ISETP.GE.OR P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.XOR P2, PT, R2, RZ, PT` | `ISETP.GE.XOR P0, PT, R0, RZ, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.T.AND P2, PT, R2, RZ, PT` | `ISETP.T.AND P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.EQ.AND P2, PT, R2, RZ, PT` | `ISETP.EQ.AND P0, PT, R0, RZ, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GE.AND P2, PT, R2, RZ, !PT` | `ISETP.GE.AND P0, PT, R0, RZ, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.OR P1, PT, R0.reuse, R5.reuse, PT` | `ISETP.GT.OR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.XOR P1, PT, R0.reuse, R5.reuse, PT` | `ISETP.GT.XOR P0, PT, R0, R6, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.F.AND P1, PT, R0.reuse, R5.reuse, PT` | `ISETP.F.AND P0, PT, R0, R6, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.AND P1, PT, R0.reuse, R5.reuse, !PT` | `ISETP.GT.AND P0, PT, R0, R6, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.AND P0, PT, R0, c[0x0][0x0], PT` | `ISETP.NE.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.OR P0, PT, R0, R5, PT` | `ISETP.NE.OR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.XOR P0, PT, R0, R5, PT` | `ISETP.NE.XOR P0, PT, R0, R6, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LT.AND P0, PT, R0, R5, PT` | `ISETP.LT.AND P0, PT, R0, R6, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.AND P0, PT, R0, R5, !PT` | `ISETP.NE.AND P0, PT, R0, R6, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LT.U32.OR P3, PT, R4, R7, PT` | `ISETP.LT.U32.OR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.XOR P3, PT, R4, R7, PT` | `ISETP.LT.U32.XOR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.F.U32.AND P3, PT, R4, R7, PT` | `ISETP.F.U32.AND P0, PT, R0, R6, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LE.U32.AND P3, PT, R4, R7, PT` | `ISETP.LE.U32.AND P0, PT, R0, R6, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LT.U32.AND P3, PT, R4, R7, !PT` | `ISETP.LT.U32.AND P0, PT, R0, R6, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.U32.XOR P1, PT, R0, c[0x0][0x0], P0` | `ISETP.NE.U32.XOR P0, PT, R0, c[0x0][0x0], P1` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.U32.XOR P1, PT, R0, RZ, P0` | `ISETP.GT.U32.XOR P0, PT, R0, RZ, P1` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.T.U32.XOR P1, PT, R0, RZ, P0` | `ISETP.T.U32.XOR P0, PT, R0, RZ, P1` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.U32.XOR P1, PT, R0, RZ, !P0` | `ISETP.NE.U32.XOR P0, PT, R0, RZ, !P1` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `LEA.HI.SX32 R11, P0, R7, R6, 0x0` | `LEA.HI.SX32 R8, P1, R0, R6, 0x0` | 87-90 | 0000 | 00000007 | 16 of 16 |  |
| `IMAD.MOV.U32 R11, RZ, c[0x0][0x0], R8` | `IMAD.MOV.U32 R8, RZ, c[0x0][0x0], R0` | 87-90 | 1111 | 0000000b | 16 of 16 |  |
| `HFMA2.MMA R10, R8, R3, R10` | `HFMA2.MMA R8, R0, R6, R0` | 87-90 | 1111 | 0000000b | 16 of 16 |  |
| `IMAD.WIDE.U32 R10, P0, R8, c[0x0][0x0], R10` | `IMAD.WIDE.U32 R8, P1, R0, c[0x0][0x0], R6` | 87-90 | 1111 | 00000b07 | 16 of 16 |  |
| `IMAD.WIDE R10, P0, R8, R3, R10` | `IMAD.WIDE R8, P1, R0, R6, R0` | 87-90 | 1111 | 00000058 | 16 of 16 |  |
| `IMAD.WIDE.U32 R10, P0, R8, R3, -R10` | `IMAD.WIDE.U32 R8, P1, R0, R6, -R0` | 87-90 | 1111 | 00000042 | 16 of 16 |  |
| `IMAD.HI.U32 R10, P1, R9, R10, c[0x0][0x0]` | `IMAD.HI.U32 R8, P1, R0, R6, c[0x0][0x0]` | 87-90 | 1111 | 00000001 | 16 of 16 |  |
| `IMAD.HI.U32 R10, P1, R9, c[0x0][0x0], R10` | `IMAD.HI.U32 R8, P1, R0, c[0x0][0x0], R6` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `IMAD.HI R10, P1, R9, R13, R10` | `IMAD.HI R8, P1, R0, R6, R0` | 87-90 | 1111 | 00fffec0 | 16 of 16 |  |
| `IMAD.HI.U32 R10, P1, R9, R13, -R10` | `IMAD.HI.U32 R8, P1, R0, R6, -R0` | 87-90 | 1111 | ff000140 | 16 of 16 |  |
| `LEA.HI R11, P1, -R10, R4, RZ, 0x1c` | `LEA.HI R8, P1, -R0, R6, RZ, 0x1c` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `LEA.HI R9, P1, R0, 0x1, RZ, 0x1c` | `LEA.HI R8, P1, R0, 0x1, RZ, 0x1c` | 87-90 | 1111 | 00000001 | 16 of 16 |  |
| `IMAD.IADD R13, R8, 0x1, -R7` | `IMAD.IADD R8, R0, 0x1, -R6` | 87-90 | 0010 | 00000004 | 16 of 16 |  |
| `IMAD.MOV.U32 R2, RZ, RZ, -c[0x0][0x160]` | `IMAD.MOV.U32 R8, RZ, RZ, -c[0x0][0x0]` | 87-90 | 1111 | ffffff00 | 16 of 16 |  |
| `UIMAD.U32 UR4, UR6, UR8, UR4` | `UIMAD.U32 UR6, UR4, UR4, UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `UIMAD.WIDE UR4, UR6, UR8, UR4` | `UIMAD.WIDE UR6, UR4, UR4, UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `UIMAD.WIDE.U32 UR4, UR6, UR8, -UR4` | `UIMAD.WIDE.U32 UR6, UR4, UR4, -UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `UIMAD UR6, UR6, UR9, -URZ` | `UIMAD UR6, UR4, UR4, -URZ` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `ULEA.HI UR6, UR5, UR6, URZ, 0x1c` | `ULEA.HI UR6, UR4, UR4, URZ, 0x1c` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `LEA.HI R22, P0, R1, c[0x0][0x20], RZ, 0x1c` | `LEA.HI R8, P1, R0, c[0x0][0x0], RZ, 0x1c` | 87-90 | 1111 | 00000100 | 16 of 16 |  |
| `IMAD.WIDE.U32 R16, RZ, RZ, UR4` | `IMAD.WIDE.U32 R8, RZ, RZ, UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD.U32 R16, RZ, UR4, RZ` | `IMAD.U32 R8, RZ, UR4, RZ` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD.U32 R16, RZ, RZ, -UR4` | `IMAD.U32 R8, RZ, RZ, -UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD R16, RZ, RZ, UR4` | `IMAD R8, RZ, RZ, UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD.WIDE R6, P0, R0, 0x0, R0` | `IMAD.WIDE R8, P1, R0, 0x0, R6` | 87-90 | 0000 | 00000007 | 16 of 16 |  |
| `ISETP.NE.U32.OR P1, PT, R27, RZ, !P3` | `ISETP.NE.U32.OR P0, PT, R0, RZ, !P1` | 68-71 | 0001 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.OR P0, PT, R12, c[0x0][0x1d8], PT` | `ISETP.NE.U32.OR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.AND P0, PT, R12, c[0x0][0x1d8], !PT` | `ISETP.NE.U32.AND P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LT.U32.AND P0, PT, R12, 0x6c00, PT` | `ISETP.LT.U32.AND P0, PT, R0, 0x6c00, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.AND P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.LT.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.OR P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.LT.U32.OR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.XOR P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.LT.U32.XOR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.F.U32.AND P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.F.U32.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LE.U32.AND P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.LE.U32.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.AND P0, PT, R12, c[0x0][0x1b0], !PT` | `ISETP.LT.U32.AND P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ATOM.ADD.EF.S64 P0, R0, [RZ], R6` | ATOM.ADD.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMS.ADD.S32 R0, [RZ], R6` | ATOMS.ADD.S32 R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.ADD.EF.S64 P0, R0, [RZ], R6` | ATOMG.ADD.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `BAR.SYNC.DEFER_BLOCKING 0x0, R0` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `BAR.SYNC.DEFER_BLOCKING R0, R0` | BAR.SYNC.DEFER_BLOCKING R8, R0 | | | not asked: the question did not assemble, or its copies were not found | | |
| `BAR.SYNC.DEFER_BLOCKING 0x0, 0x1` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `BAR.SYNCALL.DEFER_BLOCKING` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `BAR.SYNC 0x0` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `CCTL.U.IVALL` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `CCTL.C.IVALL` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `CCTL.IVALLP` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `ISETP.NE.AND P0, PT, R2, UR4, PT` | `ISETP.NE.AND P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.OR P0, PT, R2, UR4, PT` | `ISETP.NE.U32.OR P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.XOR P0, PT, R2, UR4, PT` | `ISETP.NE.U32.XOR P0, PT, R0, UR4, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.U32.AND P0, PT, R2, UR4, PT` | `ISETP.GT.U32.AND P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.U32.AND P0, PT, R2, UR4, PT` | `ISETP.T.U32.AND P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.AND P0, PT, R2, UR4, PT` | `ISETP.LT.U32.AND P0, PT, R0, UR4, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.U32.AND P0, PT, R2, UR4, !PT` | `ISETP.NE.U32.AND P0, PT, R0, UR4, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.AND P1, PT, R18, 0x2, PT` | `ISETP.NE.AND P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.OR P1, PT, R18, 0x2, PT` | `ISETP.NE.U32.OR P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.XOR P1, PT, R18, 0x2, PT` | `ISETP.NE.U32.XOR P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.U32.AND P1, PT, R18, 0x2, PT` | `ISETP.GT.U32.AND P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.U32.AND P1, PT, R18, 0x2, PT` | `ISETP.T.U32.AND P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.AND P1, PT, R18, 0x2, !PT` | `ISETP.NE.U32.AND P0, PT, R0, 0x2, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `LEA R3, P0, -R0, 0x0, 0x4` | `LEA R8, P1, -R0, 0x0, 0x4` | 87-90 | 0000 | ffffff50 | 16 of 16 |  |
| `IMAD.HI R2, R2, c[0x0][0x0], R3` | `IMAD.HI R8, R0, c[0x0][0x0], R6` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `IMAD.WIDE R2, R2, 0x0, R3` | `IMAD.WIDE R8, R0, 0x0, R6` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `IMAD.WIDE R2, R2, c[0x0][0x0], -R3` | `IMAD.WIDE R8, R0, c[0x0][0x0], -R6` | 87-90 | 1111 | 00000af9 | 16 of 16 |  |
| `IMAD.WIDE R2, P6, R2, c[0x0][0x0], R3` | `IMAD.WIDE R8, P1, R0, c[0x0][0x0], R6` | 87-90 | 1111 | 00000b07 | 16 of 16 |  |
| `ISETP.F.AND PT, P0, R2, c[0x0][0x0], !PT` | `ISETP.F.AND P0, P1, R0, c[0x0][0x0], !PT` | 68-71 | 0000 | 00000000 | 16 of 16 |  |
| `IMAD.IADD R2, R2, 0x1, R3` | `IMAD.IADD R8, R0, 0x1, R6` | 87-90 | 1111 | 00000012 | 16 of 16 |  |
| `IMAD R2, R2, 0x2, R3` | `IMAD R8, R0, 0x2, R6` | 87-90 | 1111 | 0000001d | 16 of 16 |  |
| `IMAD.MOV.U32 R2, R2, 0x0, R3` | `IMAD.MOV.U32 R8, R0, 0x0, R6` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `IMAD.MOV R2, R2, 0x0, -R3` | `IMAD.MOV R8, R0, 0x0, -R6` | 87-90 | 1111 | fffffff9 | 16 of 16 |  |
| `IMAD.U32 R2, R2, c[0x0][0x0], -R3` | `IMAD.U32 R8, R0, c[0x0][0x0], -R6` | 87-90 | 1111 | 00000af9 | 16 of 16 |  |
| `ISETP.GE.AND P0, PT, R2, 0x5c00, PT` | `ISETP.GE.AND P0, PT, R0, 0x5c00, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GE.U32.OR P0, PT, R2, 0x5c00, PT` | `ISETP.GE.U32.OR P0, PT, R0, 0x5c00, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.U32.XOR P0, PT, R2, 0x5c00, PT` | `ISETP.GE.U32.XOR P0, PT, R0, 0x5c00, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.EQ.U32.AND P0, PT, R2, 0x5c00, PT` | `ISETP.EQ.U32.AND P0, PT, R0, 0x5c00, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GE.U32.AND P0, PT, R2, 0x5c00, !PT` | `ISETP.GE.U32.AND P0, PT, R0, 0x5c00, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GE.OR P0, PT, R2, c[0x0][0x170], PT` | `ISETP.GE.OR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.XOR P0, PT, R2, c[0x0][0x170], PT` | `ISETP.GE.XOR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.AND P0, PT, R2, c[0x0][0x170], PT` | `ISETP.T.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.AND P0, PT, R2, c[0x0][0x170], PT` | `ISETP.GT.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.EQ.AND P0, PT, R2, c[0x0][0x170], PT` | `ISETP.EQ.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GE.AND P0, PT, R2, c[0x0][0x170], !PT` | `ISETP.GE.AND P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.T.U32.OR P0, PT, R2, c[0x0][0x170], PT` | `ISETP.T.U32.OR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.U32.OR P0, PT, R2, c[0x0][0x170], PT` | `ISETP.GT.U32.OR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.EQ.U32.OR P0, PT, R2, c[0x0][0x170], PT` | `ISETP.EQ.U32.OR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.U32.OR P0, PT, R2, c[0x0][0x170], !PT` | `ISETP.GE.U32.OR P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.T.U32.XOR P0, PT, R2, c[0x0][0x170], PT` | `ISETP.T.U32.XOR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.U32.XOR P0, PT, R2, c[0x0][0x170], PT` | `ISETP.GT.U32.XOR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.EQ.U32.XOR P0, PT, R2, c[0x0][0x170], PT` | `ISETP.EQ.U32.XOR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.U32.XOR P0, PT, R2, c[0x0][0x170], !PT` | `ISETP.GE.U32.XOR P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.T.U32.AND P0, PT, R2, c[0x0][0x170], !PT` | `ISETP.T.U32.AND P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.U32.AND P0, PT, R2, c[0x0][0x170], !PT` | `ISETP.GT.U32.AND P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.EQ.U32.AND P0, PT, R2, c[0x0][0x170], !PT` | `ISETP.EQ.U32.AND P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `@P0 BAR.SYNC 0x0, R0` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `@P0 NANOSLEEP.CLEAR` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `IMAD.U32 R2, R2, R3, 0x5a00` | `IMAD.U32 R8, R0, R6, 0x5a00` | 87-90 | 1111 | 00005a4d | 16 of 16 |  |
| `IMAD.U32 R2, R2, R3, -c[0x0][0x168]` | `IMAD.U32 R8, R0, R6, -c[0x0][0x0]` | 87-90 | 1111 | ffffff4d | 16 of 16 |  |
| `IMAD R2, R2, R3, c[0x0][0x168]` | `IMAD R8, R0, R6, c[0x0][0x0]` | 87-90 | 1111 | 0000014d | 16 of 16 |  |
| `IMAD.HI.U32 R2, R2, R3, -c[0x0][0x168]` | `IMAD.HI.U32 R8, R0, R6, -c[0x0][0x0]` | 87-90 | 1111 | fffffffe | 16 of 16 |  |
| `IMAD.HI R2, R2, R3, c[0x0][0x168]` | `IMAD.HI R8, R0, R6, c[0x0][0x0]` | 87-90 | 1111 | 00000001 | 16 of 16 |  |
| `IMAD.WIDE R2, R2, R3, -c[0x0][0x168]` | `IMAD.WIDE R8, R0, R6, -c[0x0][0x0]` | 87-90 | 1111 | ffffff4d | 16 of 16 |  |
| `IMAD.WIDE.U32 R2, P6, R2, R3, -c[0x0][0x168]` | `IMAD.WIDE.U32 R8, P1, R0, R6, -c[0x0][0x0]` | 87-90 | 1111 | ffffff4d | 16 of 16 |  |
| `IMAD.WIDE R2, P6, R2, R3, c[0x0][0x168]` | `IMAD.WIDE R8, P1, R0, R6, c[0x0][0x0]` | 87-90 | 1111 | 0000014d | 16 of 16 |  |
| `LEA.HI R7, R0, c[0x0][0x0], RZ, 0x1c` | `LEA.HI R8, R0, c[0x0][0x0], RZ, 0x1c` | 87-90 | 1111 | 00000100 | 16 of 16 |  |
| `LEA.HI.SX32 R7, R0, R7, 0x1c` | `LEA.HI.SX32 R8, R0, R6, 0x1c` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `LEA R7, R0, R7, 0x1c` | `LEA R8, R0, R6, 0x1c` | 87-90 | 1111 | b0000007 | 16 of 16 |  |
| `LEA.HI R7, R0, -c[0x0][0x0], RZ, 0x1c` | `LEA.HI R8, R0, -c[0x0][0x0], RZ, 0x1c` | 87-90 | 1111 | ffffff00 | 16 of 16 |  |
| `LEA.HI R7, -R0, -R7, RZ, 0x1c` | LEA.HI R8, -R0, -R6, RZ, 0x1c | | | not asked: its own bits did not run | | |
| `LEA.HI.SX32 R7, R0, -R7, 0x1c` | `LEA.HI.SX32 R8, R0, -R6, 0x1c` | 87-90 | 1111 | fffffff9 | 16 of 16 |  |
| `LEA R7, R0, -R7, 0x1c` | `LEA R8, R0, -R6, 0x1c` | 87-90 | 1111 | affffff9 | 16 of 16 |  |
| `LEA.HI R7, P0, R0, -c[0x0][0x0], RZ, 0x1c` | `LEA.HI R8, P1, R0, -c[0x0][0x0], RZ, 0x1c` | 87-90 | 1111 | ffffff00 | 16 of 16 |  |
| `LEA.HI R7, P0, -R0, -R7, RZ, 0x1c` | LEA.HI R8, P1, -R0, -R6, RZ, 0x1c | | | not asked: its own bits did not run | | |
| `LEA.HI.SX32 R7, P0, R0, -R7, 0x1c` | `LEA.HI.SX32 R8, P1, R0, -R6, 0x1c` | 87-90 | 1111 | fffffff9 | 16 of 16 |  |
| `LEA R7, P0, R0, -R7, 0x1c` | `LEA R8, P1, R0, -R6, 0x1c` | 87-90 | 1111 | affffff9 | 16 of 16 |  |
| `IMAD.MOV R9, RZ, RZ, -c[0x1f][-0x4]` | `IMAD.MOV R8, RZ, RZ, -c[0x1f][-0x4]` | 87-90 | 0000 | 00000000 | 16 of 16 |  |
| `ISETP.GT.U32.OR P0, PT, R9, RZ, PT` | `ISETP.GT.U32.OR P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.U32.OR P0, PT, R9, RZ, PT` | `ISETP.T.U32.OR P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.U32.AND P0, PT, R9, RZ, !PT` | `ISETP.GT.U32.AND P0, PT, R0, RZ, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.T.U32.AND P0, PT, R9, RZ, !PT` | `ISETP.T.U32.AND P0, PT, R0, RZ, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `IMAD.WIDE.U32 R11, P0, RZ, 0x1, R0` | `IMAD.WIDE.U32 R8, P1, RZ, 0x1, R0` | 87-90 | 1000 | 0000000b | 16 of 16 |  |
| `IMAD.HI R11, P0, RZ, 0x1, R0` | `IMAD.HI R8, P1, RZ, 0x1, R0` | 87-90 | 1000 | 00fffec0 | 16 of 16 |  |
| `IMAD.HI.U32 R11, P0, RZ, 0x1, -R0` | `IMAD.HI.U32 R8, P1, RZ, 0x1, -R0` | 87-90 | 1000 | ff00013f | 16 of 16 |  |
| `IMAD.U32 R9, R0.reuse, R7.reuse, -RZ` | `IMAD.U32 R8, R0, R6, -RZ` | 87-90 | 1111 | 0000004d | 16 of 16 |  |
| `IMAD.HI R9, RZ, RZ, -R7` | `IMAD.HI R8, RZ, RZ, -R0` | 87-90 | 1111 | ff00013f | 16 of 16 |  |
| `IMAD.WIDE R9, P6, RZ, RZ, -R7` | `IMAD.WIDE R8, P1, RZ, RZ, -R0` | 87-90 | 1111 | fffffff5 | 16 of 16 |  |
| `IMAD.MOV.U32 R9, RZ, c[0x0][0x0], -R7` | `IMAD.MOV.U32 R8, RZ, c[0x0][0x0], -R0` | 87-90 | 1111 | fffffff5 | 16 of 16 |  |
| `IMAD.MOV R9, RZ, c[0x0][0x0], R7` | `IMAD.MOV R8, RZ, c[0x0][0x0], R0` | 87-90 | 1111 | 0000000b | 16 of 16 |  |
| `LEA.HI R4, -R8, 0xffffffe, RZ, 0x1c` | `LEA.HI R8, -R0, 0xffffffe, RZ, 0x1c` | 87-90 | 1111 | 0ffffffe | 16 of 16 |  |
| `LEA.HI.SX32 R4, R8, 0xffffffe, 0x1c` | `LEA.HI.SX32 R8, R0, 0xffffffe, 0x1c` | 87-90 | 1111 | 0ffffffe | 16 of 16 |  |
| `LEA R4, R8, 0xffffffe, 0x1c` | `LEA R8, R0, 0xffffffe, 0x1c` | 87-90 | 1111 | bffffffe | 16 of 16 |  |
| `IMAD.HI.U32 R5, R5, 0x9, R4` | `IMAD.HI.U32 R8, R0, 0x9, R6` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `IMAD.HI.U32 R5, R5, c[0x0][0x0], -R4` | IMAD.HI.U32 R8, R0, c[0x0][0x0], -R6 | | | not asked: its copies answered unlike one another at its own bits | | |
| `ISETP.EQ.U32.OR P0, PT, R6, R7, PT` | `ISETP.EQ.U32.OR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.U32.OR P0, PT, R6, R7, !PT` | `ISETP.GE.U32.OR P0, PT, R0, R6, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.EQ.U32.XOR P0, PT, R6, R7, PT` | `ISETP.EQ.U32.XOR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.U32.XOR P0, PT, R6, R7, !PT` | `ISETP.GE.U32.XOR P0, PT, R0, R6, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.EQ.U32.AND P0, PT, R6, R7, !PT` | `ISETP.EQ.U32.AND P0, PT, R0, R6, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `@P0 LEA.HI R6, -R7, c[0x0][0x0], RZ, 0x1c` | `LEA.HI R8, -R0, c[0x0][0x0], RZ, 0x1c` | 87-90 | 1111 | 00000100 | 16 of 16 |  |
| `@P0 LEA.HI.SX32 R6, -R7, R6, 0x1c` | `LEA.HI.SX32 R8, -R0, R6, 0x1c` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `@P0 LEA R6, -R7, R6, 0x1c` | `LEA R8, -R0, R6, 0x1c` | 87-90 | 1111 | 50000007 | 16 of 16 |  |
| `IMAD.WIDE.U32 R6, R9, 0x0, R6` | `IMAD.WIDE.U32 R8, R0, 0x0, R6` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `IMAD.WIDE.U32 R6, R9, c[0x0][0x0], -R6` | `IMAD.WIDE.U32 R8, R0, c[0x0][0x0], -R6` | 87-90 | 1111 | 00000af9 | 16 of 16 |  |
| `HFMA2 R9, R0, R0, R0` | `HFMA2 R8, R0, R6, R0` | 87-90 | 0000 | 0000000b | 16 of 16 |  |
| `LEA R9, P0, R0, c[0x0][0x0], 0x0` | `LEA R8, P1, R0, c[0x0][0x0], 0x0` | 87-90 | 0000 | 0000010b | 16 of 16 |  |
| `LEA R9, P0, -R0, R0, 0x0` | `LEA R8, P1, -R0, R6, 0x0` | 87-90 | 0000 | fffffffc | 16 of 16 |  |
| `ISETP.T.OR P2, PT, R2, RZ, PT` | `ISETP.T.OR P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.EQ.OR P2, PT, R2, RZ, PT` | `ISETP.EQ.OR P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.OR P2, PT, R2, RZ, !PT` | `ISETP.GE.OR P0, PT, R0, RZ, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.XOR P2, PT, R2, RZ, PT` | `ISETP.T.XOR P0, PT, R0, RZ, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.EQ.XOR P2, PT, R2, RZ, PT` | `ISETP.EQ.XOR P0, PT, R0, RZ, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.XOR P2, PT, R2, RZ, !PT` | `ISETP.GE.XOR P0, PT, R0, RZ, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LE.AND P2, PT, R2, RZ, PT` | `ISETP.LE.AND P0, PT, R0, RZ, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.T.AND P2, PT, R2, RZ, !PT` | `ISETP.T.AND P0, PT, R0, RZ, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.EQ.AND P2, PT, R2, RZ, !PT` | `ISETP.EQ.AND P0, PT, R0, RZ, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.F.OR P1, PT, R0.reuse, R5.reuse, PT` | `ISETP.F.OR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.OR P1, PT, R0.reuse, R5.reuse, !PT` | `ISETP.GT.OR P0, PT, R0, R6, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.F.XOR P1, PT, R0.reuse, R5.reuse, PT` | `ISETP.F.XOR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.XOR P1, PT, R0.reuse, R5.reuse, !PT` | `ISETP.GT.XOR P0, PT, R0, R6, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.F.AND P1, PT, R0.reuse, R5.reuse, !PT` | `ISETP.F.AND P0, PT, R0, R6, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.OR P0, PT, R0, c[0x0][0x0], PT` | `ISETP.NE.OR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.XOR P0, PT, R0, c[0x0][0x0], PT` | `ISETP.NE.XOR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.AND P0, PT, R0, c[0x0][0x0], !PT` | `ISETP.NE.AND P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LT.OR P0, PT, R0, R5, PT` | `ISETP.LT.OR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.OR P0, PT, R0, R5, !PT` | `ISETP.NE.OR P0, PT, R0, R6, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.XOR P0, PT, R0, R5, PT` | `ISETP.LT.XOR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.XOR P0, PT, R0, R5, !PT` | `ISETP.NE.XOR P0, PT, R0, R6, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.AND P0, PT, R0, R5, !PT` | `ISETP.LT.AND P0, PT, R0, R6, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.F.U32.OR P3, PT, R4, R7, PT` | `ISETP.F.U32.OR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LE.U32.OR P3, PT, R4, R7, PT` | `ISETP.LE.U32.OR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.OR P3, PT, R4, R7, !PT` | `ISETP.LT.U32.OR P0, PT, R0, R6, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.F.U32.XOR P3, PT, R4, R7, PT` | `ISETP.F.U32.XOR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LE.U32.XOR P3, PT, R4, R7, PT` | `ISETP.LE.U32.XOR P0, PT, R0, R6, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.XOR P3, PT, R4, R7, !PT` | `ISETP.LT.U32.XOR P0, PT, R0, R6, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.F.U32.AND P3, PT, R4, R7, !PT` | `ISETP.F.U32.AND P0, PT, R0, R6, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LE.U32.AND P3, PT, R4, R7, !PT` | `ISETP.LE.U32.AND P0, PT, R0, R6, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.U32.XOR P1, PT, R0, c[0x0][0x0], !P0` | `ISETP.NE.U32.XOR P0, PT, R0, c[0x0][0x0], !P1` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.U32.XOR P1, PT, R0, RZ, !P0` | `ISETP.GT.U32.XOR P0, PT, R0, RZ, !P1` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.U32.XOR P1, PT, R0, RZ, !P0` | `ISETP.T.U32.XOR P0, PT, R0, RZ, !P1` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `LEA.HI.SX32 R11, P0, R7, c[0x0][0x0], 0x0` | `LEA.HI.SX32 R8, P1, R0, c[0x0][0x0], 0x0` | 87-90 | 0000 | 00000100 | 16 of 16 |  |
| `LEA.HI.SX32 R11, P0, -R7, R6, 0x0` | `LEA.HI.SX32 R8, P1, -R0, R6, 0x0` | 87-90 | 0000 | 00000007 | 16 of 16 |  |
| `HFMA2.MMA R10, R8, R10, c[0x0][0x0]` | `HFMA2.MMA R8, R0, R6, c[0x0][0x0]` | 87-90 | 1111 | 00000100 | 16 of 16 |  |
| `HFMA2.MMA R10, R8, c[0x0][0x0], R10` | `HFMA2.MMA R8, R0, c[0x0][0x0], R6` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `HFMA2.MMA R10, R8, -R3, R10` | `HFMA2.MMA R8, R0, -R6, R0` | 87-90 | 1111 | 0000000b | 16 of 16 |  |
| `HFMA2.MMA R10, -R8, R3, R10` | `HFMA2.MMA R8, -R0, R6, R0` | 87-90 | 1111 | 0000000b | 16 of 16 |  |
| `HFMA2.MMA.FMZ R10, R8, R3, R10` | `HFMA2.MMA.FMZ R8, R0, R6, R0` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `HFMA2.MMA.FTZ R10, R8, R3, R10` | `HFMA2.MMA.FTZ R8, R0, R6, R0` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `HFMA2.MMA R10, R8, R3, -R10` | `HFMA2.MMA R8, R0, R6, -R0` | 87-90 | 1111 | 0000800b | 16 of 16 |  |
| `IMAD.WIDE.U32 R10, P0, R8, c[0x0][0x0], -R10` | `IMAD.WIDE.U32 R8, P1, R0, c[0x0][0x0], -R6` | 87-90 | 1111 | 00000af9 | 16 of 16 |  |
| `IMAD.HI.U32 R10, P1, R9, R10, -c[0x0][0x0]` | `IMAD.HI.U32 R8, P1, R0, R6, -c[0x0][0x0]` | 87-90 | 1111 | fffffffe | 16 of 16 |  |
| `IMAD.HI R10, P1, R9, R10, c[0x0][0x0]` | `IMAD.HI R8, P1, R0, R6, c[0x0][0x0]` | 87-90 | 1111 | 00000001 | 16 of 16 |  |
| `IMAD.HI R10, P1, R9, c[0x0][0x0], R10` | `IMAD.HI R8, P1, R0, c[0x0][0x0], R6` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `IMAD.HI.U32 R10, P1, R9, c[0x0][0x0], -R10` | IMAD.HI.U32 R8, P1, R0, c[0x0][0x0], -R6 | | | not asked: its copies answered unlike one another at its own bits | | |
| `IMAD.HI R10, P1, R9, R13, -R10` | `IMAD.HI R8, P1, R0, R6, -R0` | 87-90 | 1111 | ff000140 | 16 of 16 |  |
| `LEA.HI R11, P1, -R10, c[0x0][0x0], RZ, 0x1c` | `LEA.HI R8, P1, -R0, c[0x0][0x0], RZ, 0x1c` | 87-90 | 1111 | 00000100 | 16 of 16 |  |
| `LEA.HI R9, P1, -R0, 0x1, RZ, 0x1c` | `LEA.HI R8, P1, -R0, 0x1, RZ, 0x1c` | 87-90 | 1111 | 00000001 | 16 of 16 |  |
| `LEA.HI.SX32 R9, P1, R0, 0x1, 0x1c` | `LEA.HI.SX32 R8, P1, R0, 0x1, 0x1c` | 87-90 | 1111 | 00000001 | 16 of 16 |  |
| `LEA R9, P1, R0, 0x1, 0x1c` | `LEA R8, P1, R0, 0x1, 0x1c` | 87-90 | 1111 | b0000001 | 16 of 16 |  |
| `IMAD.WIDE R13, R8, 0x1, -R7` | `IMAD.WIDE R8, R0, 0x1, -R6` | 87-90 | 0010 | 00000004 | 16 of 16 |  |
| `IMAD.IADD.U32 R13, R8, 0x1, -R7` | `IMAD.IADD.U32 R8, R0, 0x1, -R6` | 87-90 | 0010 | 00000004 | 16 of 16 |  |
| `IMAD R13, R8, 0x3, -R7` | `IMAD R8, R0, 0x3, -R6` | 87-90 | 0010 | 0000001a | 16 of 16 |  |
| `UIMAD.U32 UR4, UR6, UR8, -UR4` | `UIMAD.U32 UR6, UR4, UR4, -UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `UIMAD.WIDE UR4, UR6, UR8, -UR4` | `UIMAD.WIDE UR6, UR4, UR4, -UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `ULEA.HI UR6, UR5, -UR6, URZ, 0x1c` | `ULEA.HI UR6, UR4, -UR4, URZ, 0x1c` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `ULEA.HI UR6, -UR5, UR6, URZ, 0x1c` | `ULEA.HI UR6, -UR4, UR4, URZ, 0x1c` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `ULEA.HI.SX32 UR6, UR5, UR6, 0x1c` | `ULEA.HI.SX32 UR6, UR4, UR4, 0x1c` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `ULEA UR6, UR5, UR6, 0x1c` | `ULEA UR6, UR4, UR4, 0x1c` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD.WIDE R26, P0, R0, 0x0, -R0` | `IMAD.WIDE R8, P1, R0, 0x0, -R6` | 87-90 | 0000 | fffffff9 | 16 of 16 |  |
| `IMAD.HI.U32 R16, RZ, RZ, UR4` | `IMAD.HI.U32 R8, RZ, RZ, UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD.WIDE.U32 R16, RZ, UR4, RZ` | `IMAD.WIDE.U32 R8, RZ, UR4, RZ` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD.WIDE.U32 R16, RZ, RZ, -UR4` | `IMAD.WIDE.U32 R8, RZ, RZ, -UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD.WIDE R16, RZ, RZ, UR4` | `IMAD.WIDE R8, RZ, RZ, UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD.WIDE.U32 R16, P6, RZ, RZ, UR4` | `IMAD.WIDE.U32 R8, P1, RZ, RZ, UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD R16, RZ, UR4, RZ` | `IMAD R8, RZ, UR4, RZ` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD.U32 R16, RZ, UR4, -RZ` | `IMAD.U32 R8, RZ, UR4, -RZ` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `IMAD R16, RZ, RZ, -UR4` | `IMAD R8, RZ, RZ, -UR4` | 87-90 | 1111 | 00000000 | 16 of 16 |  |
| `ATOMG.ADD.64.STRONG.GPU PT, R4, [R16], R4` | ATOMG.ADD.64.STRONG.GPU PT, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ISETP.NE.U32.OR P1, PT, R27, c[0x0][0x0], !P3` | `ISETP.NE.U32.OR P0, PT, R0, c[0x0][0x0], !P1` | 68-71 | 0001 | 0000000b | 16 of 16 |  |
| `ISETP.GT.U32.OR P1, PT, R27, RZ, !P3` | `ISETP.GT.U32.OR P0, PT, R0, RZ, !P1` | 68-71 | 0001 | 0000000b | 16 of 16 |  |
| `ISETP.T.U32.OR P1, PT, R27, RZ, !P3` | `ISETP.T.U32.OR P0, PT, R0, RZ, !P1` | 68-71 | 0001 | 0000000b | 16 of 16 |  |
| `ISETP.LT.AND P0, PT, R12, 0x6c00, PT` | `ISETP.LT.AND P0, PT, R0, 0x6c00, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.OR P0, PT, R12, 0x6c00, PT` | `ISETP.LT.U32.OR P0, PT, R0, 0x6c00, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.XOR P0, PT, R12, 0x6c00, PT` | `ISETP.LT.U32.XOR P0, PT, R0, 0x6c00, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.F.U32.AND P0, PT, R12, 0x6c00, PT` | `ISETP.F.U32.AND P0, PT, R0, 0x6c00, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LE.U32.AND P0, PT, R12, 0x6c00, PT` | `ISETP.LE.U32.AND P0, PT, R0, 0x6c00, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.AND P0, PT, R12, 0x6c00, !PT` | `ISETP.LT.U32.AND P0, PT, R0, 0x6c00, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LT.OR P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.LT.OR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.XOR P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.LT.XOR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.F.AND P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.F.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LE.AND P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.LE.AND P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.AND P0, PT, R12, c[0x0][0x1b0], !PT` | `ISETP.LT.AND P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.F.U32.OR P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.F.U32.OR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LE.U32.OR P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.LE.U32.OR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.OR P0, PT, R12, c[0x0][0x1b0], !PT` | `ISETP.LT.U32.OR P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.F.U32.XOR P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.F.U32.XOR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LE.U32.XOR P0, PT, R12, c[0x0][0x1b0], PT` | `ISETP.LE.U32.XOR P0, PT, R0, c[0x0][0x0], PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LT.U32.XOR P0, PT, R12, c[0x0][0x1b0], !PT` | `ISETP.LT.U32.XOR P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.F.U32.AND P0, PT, R12, c[0x0][0x1b0], !PT` | `ISETP.F.U32.AND P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LE.U32.AND P0, PT, R12, c[0x0][0x1b0], !PT` | `ISETP.LE.U32.AND P0, PT, R0, c[0x0][0x0], !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ATOM.E.ADD.EF.S64 P0, R0, [RZ], R6` | ATOM.E.ADD.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.ADD.EF.F16x2.RN P0, R0, [RZ], R6` | ATOM.ADD.EF.F16x2.RN P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.ADD.EF.S32 P0, R0, [RZ], R6` | ATOM.ADD.EF.S32 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.ADD.EF.S64.CONSTANT.PRIVATE P0, R0, [RZ], R6` | ATOM.ADD.EF.S64.CONSTANT.PRIVATE P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.ADD.EF.S64.CONSTANT.CTA P0, R0, [RZ], R6` | ATOM.ADD.EF.S64.CONSTANT.CTA P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.ADD.EF.S64.STRONG.SM.PRIVATE P0, R0, [RZ], R6` | ATOM.ADD.EF.S64.STRONG.SM.PRIVATE P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.ADD.EF.S64.MMIO.GPU P0, R0, [RZ], R6` | ATOM.ADD.EF.S64.MMIO.GPU P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.ADD.S64 P0, R0, [RZ], R6` | ATOM.ADD.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.ADD.EL.S64 P0, R0, [RZ], R6` | ATOM.ADD.EL.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.ADD.EU.S64 P0, R0, [RZ], R6` | ATOM.ADD.EU.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.MIN.EF.S64 P0, R0, [RZ], R6` | ATOM.MIN.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.MAX.EF.S64 P0, R0, [RZ], R6` | ATOM.MAX.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.DEC.EF.S64 P0, R0, [RZ], R6` | ATOM.DEC.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOM.EXCH.EF.S64 P0, R0, [RZ], R6` | ATOM.EXCH.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMS.MIN.S32 R0, [RZ], R6` | ATOMS.MIN.S32 R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMS.MAX.S32 R0, [RZ], R6` | ATOMS.MAX.S32 R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMS.DEC.S32 R0, [RZ], R6` | ATOMS.DEC.S32 R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.E.ADD.EF.S64 P0, R0, [RZ], R6` | ATOMG.E.ADD.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.ADD.EF.F16x2.RN P0, R0, [RZ], R6` | ATOMG.ADD.EF.F16x2.RN P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.ADD.EF.S32 P0, R0, [RZ], R6` | ATOMG.ADD.EF.S32 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.ADD.EF.S64.CONSTANT.PRIVATE P0, R0, [RZ], R6` | ATOMG.ADD.EF.S64.CONSTANT.PRIVATE P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.ADD.EF.S64.CONSTANT.CTA P0, R0, [RZ], R6` | ATOMG.ADD.EF.S64.CONSTANT.CTA P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.ADD.EF.S64.STRONG.SM.PRIVATE P0, R0, [RZ], R6` | ATOMG.ADD.EF.S64.STRONG.SM.PRIVATE P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.ADD.EF.S64.MMIO.GPU P0, R0, [RZ], R6` | ATOMG.ADD.EF.S64.MMIO.GPU P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.ADD.S64 P0, R0, [RZ], R6` | ATOMG.ADD.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.ADD.EL.S64 P0, R0, [RZ], R6` | ATOMG.ADD.EL.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.ADD.EU.S64 P0, R0, [RZ], R6` | ATOMG.ADD.EU.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.MIN.EF.S64 P0, R0, [RZ], R6` | ATOMG.MIN.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.MAX.EF.S64 P0, R0, [RZ], R6` | ATOMG.MAX.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.DEC.EF.S64 P0, R0, [RZ], R6` | ATOMG.DEC.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.EXCH.EF.S64 P0, R0, [RZ], R6` | ATOMG.EXCH.EF.S64 P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `BAR.SYNC R0, R0` | BAR.SYNC R8, R0 | | | not asked: the question did not assemble, or its copies were not found | | |
| `BAR.SYNC 0x0, 0x1` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `BAR.SYNCALL` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `BAR.ARV 0x0, 0x0` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `CCTL.I.IVALL` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `CCTL.U.IVALLP` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `CCTL.C.IVALLP` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `CCTL.WBALL` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `CCTL.WBALLP` |  | | | not asked: its first operand is no register, predicate or uniform register to read an answer from | | |
| `ULEA.HI UR5, URZ, 0xffffffff, URZ, 0x1c` | `ULEA.HI UR6, URZ, 0xffffffff, URZ, 0x1c` | 87-90 | 0000 | ffffffff | 16 of 16 |  |
| `ISETP.NE.OR P0, PT, R2, UR4, PT` | `ISETP.NE.OR P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.XOR P0, PT, R2, UR4, PT` | `ISETP.NE.XOR P0, PT, R0, UR4, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.AND P0, PT, R2, UR4, PT` | `ISETP.GT.AND P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.AND P0, PT, R2, UR4, PT` | `ISETP.T.AND P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.AND P0, PT, R2, UR4, PT` | `ISETP.LT.AND P0, PT, R0, UR4, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.AND P0, PT, R2, UR4, !PT` | `ISETP.NE.AND P0, PT, R0, UR4, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.U32.OR P0, PT, R2, UR4, PT` | `ISETP.GT.U32.OR P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.U32.OR P0, PT, R2, UR4, PT` | `ISETP.T.U32.OR P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.LT.U32.OR P0, PT, R2, UR4, PT` | `ISETP.LT.U32.OR P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.OR P0, PT, R2, UR4, !PT` | `ISETP.NE.U32.OR P0, PT, R0, UR4, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.U32.XOR P0, PT, R2, UR4, PT` | `ISETP.GT.U32.XOR P0, PT, R0, UR4, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.T.U32.XOR P0, PT, R2, UR4, PT` | `ISETP.T.U32.XOR P0, PT, R0, UR4, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LT.U32.XOR P0, PT, R2, UR4, PT` | `ISETP.LT.U32.XOR P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.XOR P0, PT, R2, UR4, !PT` | `ISETP.NE.U32.XOR P0, PT, R0, UR4, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GE.U32.AND P0, PT, R2, UR4, PT` | `ISETP.GE.U32.AND P0, PT, R0, UR4, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.F.U32.AND P0, PT, R2, UR4, PT` | `ISETP.F.U32.AND P0, PT, R0, UR4, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.U32.AND P0, PT, R2, UR4, !PT` | `ISETP.GT.U32.AND P0, PT, R0, UR4, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LE.U32.AND P0, PT, R2, UR4, PT` | `ISETP.LE.U32.AND P0, PT, R0, UR4, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.T.U32.AND P0, PT, R2, UR4, !PT` | `ISETP.T.U32.AND P0, PT, R0, UR4, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.LT.U32.AND P0, PT, R2, UR4, !PT` | `ISETP.LT.U32.AND P0, PT, R0, UR4, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.OR P1, PT, R18, 0x2, PT` | `ISETP.NE.OR P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.XOR P1, PT, R18, 0x2, PT` | `ISETP.NE.XOR P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.AND P1, PT, R18, 0x2, PT` | `ISETP.GT.AND P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.AND P1, PT, R18, 0x2, PT` | `ISETP.T.AND P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.AND P1, PT, R18, 0x2, !PT` | `ISETP.NE.AND P0, PT, R0, 0x2, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.GT.U32.OR P1, PT, R18, 0x2, PT` | `ISETP.GT.U32.OR P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.T.U32.OR P1, PT, R18, 0x2, PT` | `ISETP.T.U32.OR P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.NE.U32.OR P1, PT, R18, 0x2, !PT` | `ISETP.NE.U32.OR P0, PT, R0, 0x2, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.U32.XOR P1, PT, R18, 0x2, PT` | `ISETP.GT.U32.XOR P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.T.U32.XOR P1, PT, R18, 0x2, PT` | `ISETP.T.U32.XOR P0, PT, R0, 0x2, PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.NE.U32.XOR P1, PT, R18, 0x2, !PT` | `ISETP.NE.U32.XOR P0, PT, R0, 0x2, !PT` | 68-71 | 0111 | 0000000b | 16 of 16 |  |
| `ISETP.GT.U32.AND P1, PT, R18, 0x2, !PT` | `ISETP.GT.U32.AND P0, PT, R0, 0x2, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `ISETP.T.U32.AND P1, PT, R18, 0x2, !PT` | `ISETP.T.U32.AND P0, PT, R0, 0x2, !PT` | 68-71 | 0111 | 00000000 | 16 of 16 |  |
| `F2FP.RELU.PACK_AB R1, R0, R0` | `F2FP.RELU.PACK_AB R8, R0, R6` | 10-10 | 0 | 00000000 | 2 of 2 |  |
| `F2FP.RELU.PACK_AB R1, R0, R0` | `F2FP.RELU.PACK_AB R8, R0, R6` | 64-72 | 100000000 | 00000000 | 9 of 9 |  |
| `F2FP.RELU.PACK_AB R1, R0, R0` | `F2FP.RELU.PACK_AB R8, R0, R6` | 124-124 | 0 | 00000000 | 2 of 2 |  |
| `BAR.SYNC R0, 0x2` | BAR.SYNC R8, 0x2 | | | not asked: its own bits did not run | | |
| `F2FP.RELU.PACK_AB R1, R0, c[0x0][0x28]` | `F2FP.RELU.PACK_AB R8, R0, c[0x0][0x0]` | 64-72 | 100000000 | 00000000 | 9 of 9 |  |
| `F2FP.RELU.PACK_AB R1, R0, c[0x0][0x28]` | `F2FP.RELU.PACK_AB R8, R0, c[0x0][0x0]` | 124-124 | 0 | 00000000 | 2 of 2 |  |
| `F2FP.SATFINITE.PACK_AB R2, R0, R0` | `F2FP.SATFINITE.PACK_AB R8, R0, R6` | 10-10 | 0 | 00000000 | 2 of 2 |  |
| `F2FP.SATFINITE.PACK_AB R2, R0, R0` | `F2FP.SATFINITE.PACK_AB R8, R0, R6` | 64-72 | 100000000 | 00000000 | 9 of 9 |  |
| `F2FP.SATFINITE.PACK_AB R2, R0, R0` | `F2FP.SATFINITE.PACK_AB R8, R0, R6` | 124-124 | 0 | 00000000 | 2 of 2 |  |
| `ATOM.E.ADD.EF.64.CONSTANT.PRIVATE P0, R2, [R0], R0` | ATOM.E.ADD.EF.64.CONSTANT.PRIVATE P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMS.ADD.64 R2, [R0], R0` | ATOMS.ADD.64 R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `ATOMG.E.ADD.EF.64.CONSTANT.PRIVATE P0, R2, [R0], R0` | ATOMG.E.ADD.EF.64.CONSTANT.PRIVATE P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `F2FP.SATFINITE.PACK_AB R2, R0, 0` | `F2FP.SATFINITE.PACK_AB R8, R0, 0` | 64-72 | 100000000 | 00000000 | 9 of 9 |  |
| `F2FP.SATFINITE.PACK_AB R2, R0, 0` | `F2FP.SATFINITE.PACK_AB R8, R0, 0` | 124-124 | 0 | 00000000 | 2 of 2 |  |
| `F2FP.SATFINITE.PACK_AB R2, R0, c[0x0][0x0]` | `F2FP.SATFINITE.PACK_AB R8, R0, c[0x0][0x0]` | 64-72 | 100000000 | 00000000 | 9 of 9 |  |
| `F2FP.SATFINITE.PACK_AB R2, R0, c[0x0][0x0]` | `F2FP.SATFINITE.PACK_AB R8, R0, c[0x0][0x0]` | 124-124 | 0 | 00000000 | 2 of 2 |  |
| `IMAD R2, R2, R3, 0x0` | `IMAD R8, R0, R6, 0x0` | 87-90 | 1111 | 0000004d | 16 of 16 |  |
| `BAR.SYNC R0` | `BAR.SYNC R8` | 42-53 | 000000000000 | 00000000 | 1 of 12 | 000000000001 did not run: exited, code 3, cudaErrorIllegalInstruction; 000000000010 did not run: exited, code 3, cudaErrorIllegalInstruction; 000000000100 did not run: exited, code 3, cudaErrorIllegalInstruction; 000000001000 did not run: exited, code 3, cudaErrorIllegalInstruction; 000000010000 did not run: exited, code 3, cudaErrorIllegalInstruction; 000001000000 did not run: out of time, code 1; 000010000000 did not run: out of time, code 1; 000100000000 did not run: out of time, code 1; 001000000000 di |
| `BAR.SYNC R0` | `BAR.SYNC R8` | 77-77 | 0 | 00000000 | 1 of 2 | 1 did not run: exited, code 3, cudaErrorIllegalInstruction |
| `ISETP.F.AND PT, P0, R2, 0x0, !PT` | `ISETP.F.AND P0, P1, R0, 0x0, !PT` | 68-71 | 0000 | 00000000 | 16 of 16 |  |
| `IMAD.HI R2, R2, 0x0, R3` | `IMAD.HI R8, R0, 0x0, R6` | 87-90 | 1111 | 00000007 | 16 of 16 |  |
| `NANOSLEEP.CLEAR !PT` | `NANOSLEEP.CLEAR !P0` | 11-11 | 1 | 00000000 | 1 of 2 | 0 did not run: exited, code 3, cudaErrorIllegalInstruction |
| `NANOSLEEP.CLEAR !PT` | `NANOSLEEP.CLEAR !P0` | 40-58 | 0000000000000000000 | 00000000 | 19 of 19 |  |
| `NANOSLEEP.CLEAR !PT` | `NANOSLEEP.CLEAR !P0` | 91-91 | 0 | 00000000 | 1 of 2 | 1 did not run: exited, code 3, cudaErrorIllegalInstruction |
| `ATOMS.XOR R0, [R2.X4+0x5c], R0` | ATOMS.XOR R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `IMAD.U32 R0, R2, 0x5c00, R112` | `IMAD.U32 R8, R0, 0x5c00, R6` | 87-90 | 0111 | 0003f407 | 16 of 16 |  |
| `@P0 F2FP.PACK_AB R0, R0, R0` | `F2FP.PACK_AB R8, R0, R6` | 10-10 | 0 | 00000000 | 2 of 2 |  |
| `@P0 F2FP.PACK_AB R0, R0, R0` | `F2FP.PACK_AB R8, R0, R6` | 64-72 | 000000000 | 00000000 | 9 of 9 |  |
| `@P0 ATOM.XOR.EF P0, R0, [R0], R0` | ATOM.XOR.EF P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `@P0 ATOMG.XOR.EF P0, R0, [R0], R0` | ATOMG.XOR.EF P0, R10, [R4+0x8], R0 | | | not asked: its own bits did not run | | |
| `@P0 F2FP.PACK_AB R0, R0, 0` | `F2FP.PACK_AB R8, R0, 0` | 64-72 | 000000000 | 00000000 | 9 of 9 |  |
| `@P0 F2FP.PACK_AB R0, R0, c[0x0][0x0]` | `F2FP.PACK_AB R8, R0, c[0x0][0x0]` | 64-72 | 000000000 | 00000000 | 9 of 9 |  |
| `ISETP.F.XOR P0, P0, R0, 0x4600, P0` | `ISETP.F.XOR P0, P1, R0, 0x4600, P1` | 68-71 | 0000 | 0000000b | 16 of 16 |  |
| `IMAD.HI R4, P0, R0, 0x4600, -R0` | IMAD.HI R8, P1, R0, 0x4600, -R6 | | | not asked: its copies answered unlike one another at its own bits | | |
| `ISETP.F.XOR P0, P0, R0, c[0x0][0x118], P0` | `ISETP.F.XOR P0, P1, R0, c[0x0][0x0], P1` | 68-71 | 0000 | 0000000b | 16 of 16 |  |
| `IMAD.WIDE R4, P0, R0, c[0x0][0x118], -R0` | `IMAD.WIDE R8, P1, R0, c[0x0][0x0], -R6` | 87-90 | 0000 | 00000af9 | 16 of 16 |  |
| `IMAD.HI R4, P0, R0, c[0x0][0x118], -R0` | IMAD.HI R8, P1, R0, c[0x0][0x0], -R6 | | | not asked: its copies answered unlike one another at its own bits | | |
| `ISETP.F.U32.AND PT, P0, R2, 0x5a00, !PT` | `ISETP.F.U32.AND P0, P1, R0, 0x5a00, !PT` | 68-71 | 0000 | 00000000 | 16 of 16 |  |
| `LEA R2, R2, c[0x0][0x168], 0x0` | `LEA R8, R0, c[0x0][0x0], 0x0` | 87-90 | 1111 | 0000010b | 16 of 16 |  |

437 forms hold an unprinted run, 368 asked, 375 runs answering alike at every value asked.
