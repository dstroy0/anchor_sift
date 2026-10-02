# Bits the disassembler does not print, asked of the part

Written by `interface_sass_probe_unprinted` (`interface_sass_unprinted.sh`) whole on every run. Each row is one value of the field written into the question's instruction and run on the part over the case 0xb, 0x7. A value that answers as printed leaves the field without effect on that question.

Each question's lines, put in place of the frame's `IADD3`:

1. `ISETP.NE.U32.AND P1, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P2, PT, RZ, RZ, PT`; `IMAD.IADD R7, R0, 0x1, R7`
2. `ISETP.NE.U32.AND P1, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P2, PT, RZ, RZ, PT`; `IMAD.IADD R7, R0, 0x1, -R7`
3. `ISETP.NE.U32.AND P1, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P2, PT, RZ, RZ, PT`; `ISETP.GE.U32.AND P0, PT, R0, R7, PT`; `SEL R7, R0, RZ, P0`
4. `ISETP.NE.U32.AND P1, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P2, PT, RZ, RZ, PT`; `ISETP.GE.U32.AND P0, PT, R7, R0, PT`; `SEL R7, R0, RZ, P0`
5. `ISETP.NE.U32.AND P0, PT, RZ, RZ, PT`; `ISETP.NE.U32.AND P1, PT, RZ, RZ, PT`; `ISETP.NE.U32.AND P2, PT, RZ, RZ, PT`; `ISETP.NE.U32.AND P3, PT, RZ, RZ, PT`; `ISETP.NE.U32.AND P4, PT, RZ, RZ, PT`; `ISETP.NE.U32.AND P5, PT, RZ, RZ, PT`; `ISETP.NE.U32.AND P6, PT, RZ, RZ, PT`; `LDG.E.CONSTANT R7, term[UR4][R2.64]`
6. `ISETP.NE.U32.AND P0, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P1, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P2, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P3, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P4, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P5, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P6, PT, R0, RZ, PT`; `LDG.E.CONSTANT R7, term[UR4][R2.64]`
7. `ISETP.NE.U32.AND P1, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P2, PT, RZ, RZ, PT`; `LDG.E.CONSTANT R7, term[UR4][R2.64], P1`
8. `ISETP.NE.U32.AND P1, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P2, PT, RZ, RZ, PT`; `LDG.E.CONSTANT R7, term[UR4][R2.64], P2`
9. `ISETP.NE.U32.AND P1, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P2, PT, RZ, RZ, PT`; `LDG.E.CONSTANT R7, term[UR4][R2.64], !P1`
10. `ISETP.NE.U32.AND P1, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P2, PT, RZ, RZ, PT`; `LDG.E.CONSTANT R7, term[UR4][R2.64], !P2`
11. `ISETP.NE.U32.AND P1, PT, R0, RZ, PT`; `ISETP.NE.U32.AND P2, PT, RZ, RZ, PT`; `LDG.E.CONSTANT R7, term[UR4][R2.64], !PT`
12. `LDG.E.CONSTANT R7, term[UR4][R2.64]`
13. `LDG.E.CONSTANT R7, term[UR4][R2.64]`
14. `LDG.E.CONSTANT R7, term[UR4][R2.64]`
15. `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0`; `STG.E term[UR4][R4.64+0x4], R8`; `LDG.E.CONSTANT R7, term[UR4][R4.64+0x8]`
16. `IMAD.MOV.U32 R100, RZ, RZ, 0x0`; `IMAD.MOV.U32 R101, RZ, RZ, 0x0`; `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0`; `STG.E term[UR4][R4.64+0x4], R8`; `LDG.E.CONSTANT R7, term[UR4][R4.64+0x8]`
17. `IMAD.MOV.U32 R100, RZ, RZ, 0x4`; `IMAD.MOV.U32 R101, RZ, RZ, 0x0`; `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0`; `STG.E term[UR4][R4.64+0x4], R8`; `LDG.E.CONSTANT R7, term[UR4][R4.64+0x8]`
18. `IMAD.MOV.U32 R100, RZ, RZ, 0x0`; `IMAD.MOV.U32 R101, RZ, RZ, 0x1`; `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0`; `STG.E term[UR4][R4.64+0x4], R8`; `LDG.E.CONSTANT R7, term[UR4][R4.64+0x8]`
19. `STG.E term[UR4][R4.64+0x8], R0`; `LDG.E.CONSTANT R7, term[UR4][R4.64+0x8]`
20. `STG.E term[UR4][R4.64+0x8], R0`; `LDG.E.CONSTANT R7, term[UR4][R4.64+0x8]`

| question | instruction | bits | the form holds | value | answer |
|---|---|---|---|---|---|
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 0000 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 0001 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 0010 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 0011 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 0100 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 0101 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 0110 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 0111 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 1000 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 1001 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 1010 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 1011 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 1100 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 1101 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 1110 | 00000012, as printed |
| 1 | `IMAD.IADD R7, R0, 0x1, R7` | 87-90 | 1111 | 1111 | 00000012, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 0000 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 0001 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 0010 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 0011 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 0100 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 0101 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 0110 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 0111 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 1000 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 1001 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 1010 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 1011 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 1100 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 1101 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 1110 | 00000004, as printed |
| 2 | `IMAD.IADD R7, R0, 0x1, -R7` | 87-90 | 0010 | 1111 | 00000004, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 0000 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 0001 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 0010 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 0011 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 0100 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 0101 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 0110 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 0111 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 1000 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 1001 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 1010 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 1011 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 1100 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 1101 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 1110 | 0000000b, as printed |
| 3 | `ISETP.GE.U32.AND P0, PT, R0, R7, PT` | 68-71 | 0111 | 1111 | 0000000b, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 0000 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 0001 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 0010 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 0011 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 0100 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 0101 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 0110 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 0111 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 1000 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 1001 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 1010 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 1011 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 1100 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 1101 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 1110 | 00000000, as printed |
| 4 | `ISETP.GE.U32.AND P0, PT, R7, R0, PT` | 68-71 | 0111 | 1111 | 00000000, as printed |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0000 | 0000000b, as printed |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0001 | 00000000 |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0010 | 00000000 |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0011 | 00000000 |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0100 | 00000000 |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0101 | 00000000 |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0110 | 00000000 |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0111 | 00000000 |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1000 | 00000000 |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1001 | 0000000b, as printed |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1010 | 0000000b, as printed |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1011 | 0000000b, as printed |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1100 | 0000000b, as printed |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1101 | 0000000b, as printed |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1110 | 0000000b, as printed |
| 5 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1111 | 0000000b, as printed |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0000 | 0000000b, as printed |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0001 | 0000000b, as printed |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0010 | 0000000b, as printed |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0011 | 0000000b, as printed |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0100 | 0000000b, as printed |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0101 | 0000000b, as printed |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0110 | 0000000b, as printed |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 0111 | 0000000b, as printed |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1000 | 00000000 |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1001 | 00000000 |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1010 | 00000000 |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1011 | 00000000 |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1100 | 00000000 |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1101 | 00000000 |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1110 | 00000000 |
| 6 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 64-67 | 0000 | 1111 | 00000000 |
| 7 | `LDG.E.CONSTANT R7, term[UR4][R2.64], P1` | none |  |  | 0000000b, as printed |
| 8 | `LDG.E.CONSTANT R7, term[UR4][R2.64], P2` | none |  |  | 00000000, as printed |
| 9 | `LDG.E.CONSTANT R7, term[UR4][R2.64], !P1` | none |  |  | 00000000, as printed |
| 10 | `LDG.E.CONSTANT R7, term[UR4][R2.64], !P2` | none |  |  | 0000000b, as printed |
| 11 | `LDG.E.CONSTANT R7, term[UR4][R2.64], !PT` | none |  |  | 00000000, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 000000 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 000001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 000010 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 000011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 000100 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 000101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 000110 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 000111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 001000 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 001001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 001010 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 001011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 001100 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 001101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 001110 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 001111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 010000 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 010001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 010010 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 010011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 010100 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 010101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 010110 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 010111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 011000 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 011001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 011010 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 011011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 011100 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 011101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 011110 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 011111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 100000 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 100001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 100010 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 100011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 100100 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 100101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 100110 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 100111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 101000 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 101001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 101010 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 101011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 101100 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 101101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 101110 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 101111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 110000 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 110001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 110010 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 110011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 110100 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 110101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 110110 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 110111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 111000 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 111001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 111010 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 111011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 111100 | 0000000b, as printed |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 111101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 111110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 12 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 0 | 000100 | 111111 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 000000 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 000001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 000010 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 000011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 000100 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 000101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 000110 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 000111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 001000 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 001001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 001010 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 001011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 001100 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 001101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 001110 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 001111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 010000 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 010001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 010010 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 010011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 010100 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 010101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 010110 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 010111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 011000 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 011001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 011010 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 011011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 011100 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 011101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 011110 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 011111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 100000 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 100001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 100010 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 100011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 100100 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 100101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 100110 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 100111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 101000 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 101001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 101010 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 101011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 101100 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 101101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 101110 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 101111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 110000 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 110001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 110010 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 110011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 110100 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 110101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 110110 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 110111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 111000 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 111001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 111010 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 111011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 111100 | 0000000b, as printed |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 111101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 111110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 13 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 32-37, bit 101 held at 1 | 000100 | 111111 | 0000000b, as printed |
| 14 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 38-39 | 00 | 00 | 0000000b, as printed |
| 14 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 38-39 | 00 | 01 | 0000000b, as printed |
| 14 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 38-39 | 00 | 10 | 0000000b, as printed |
| 14 | `LDG.E.CONSTANT R7, term[UR4][R2.64]` | 38-39 | 00 | 11 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00000000 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00000001 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00000010 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00000011 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00000100 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00000101 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00000110 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00000111 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00001000 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00001001 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00001010 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00001011 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00001100 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00001101 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00001110 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00001111 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00010000 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00010001 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00010010 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00010011 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00010100 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00010101 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00010110 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00010111 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00011000 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00011001 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00011010 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00011011 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00011100 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00011101 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00011110 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00011111 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00100000 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00100001 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00100010 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00100011 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00100100 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00100101 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00100110 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00100111 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00101000 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00101001 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00101010 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00101011 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00101100 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00101101 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00101110 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00101111 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00110000 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00110001 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00110010 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00110011 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00110100 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00110101 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00110110 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00110111 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00111000 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00111001 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00111010 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00111011 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00111100 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00111101 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00111110 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 00111111 | did not run: exited, code 3, cudaErrorIllegalAddress |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01000000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01000001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01000010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01000011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01000100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01000101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01000110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01000111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01001000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01001001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01001010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01001011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01001100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01001101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01001110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01001111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01010000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01010001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01010010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01010011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01010100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01010101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01010110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01010111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01011000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01011001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01011010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01011011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01011100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01011101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01011110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01011111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01100000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01100001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01100010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01100011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01100100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01100101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01100110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01100111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01101000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01101001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01101010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01101011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01101100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01101101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01101110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01101111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01110000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01110001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01110010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01110011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01110100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01110101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01110110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01110111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01111000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01111001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01111010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01111011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01111100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01111101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01111110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 01111111 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10000000 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10000001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10000010 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10000011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10000100 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10000101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10000110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10000111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10001000 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10001001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10001010 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10001011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10001100 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10001101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10001110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10001111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10010000 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10010001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10010010 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10010011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10010100 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10010101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10010110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10010111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10011000 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10011001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10011010 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10011011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10011100 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10011101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10011110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10011111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10100000 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10100001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10100010 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10100011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10100100 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10100101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10100110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10100111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10101000 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10101001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10101010 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10101011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10101100 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10101101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10101110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10101111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10110000 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10110001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10110010 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10110011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10110100 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10110101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10110110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10110111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10111000 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10111001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10111010 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10111011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10111100 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10111101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10111110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 10111111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11000000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11000001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11000010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11000011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11000100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11000101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11000110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11000111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11001000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11001001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11001010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11001011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11001100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11001101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11001110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11001111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11010000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11010001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11010010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11010011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11010100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11010101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11010110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11010111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11011000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11011001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11011010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11011011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11011100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11011101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11011110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11011111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11100000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11100001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11100010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11100011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11100100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11100101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11100110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11100111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11101000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11101001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11101010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11101011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11101100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11101101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11101110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11101111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11110000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11110001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11110010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11110011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11110100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11110101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11110110 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11110111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11111000 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11111001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11111010 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11111011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11111100 | 0000000b, as printed |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11111101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11111110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | 64-71 | 11000100 | 11111111 | 0000000b, as printed |
| 16 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | none, bit 64 held at 100 |  |  | 0000000b, as printed |
| 17 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | none, bit 64 held at 100 |  |  | 0000000b, as printed |
| 18 | `ATOMG.E.ADD.64.STRONG.GPU PT, R8, term[UR4][R4.64+0x8], R0` | none, bit 64 held at 100 |  |  | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000000 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000010 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000100 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000110 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001000 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001010 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001100 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001110 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010000 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010010 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010100 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010110 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011000 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011010 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011100 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011110 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100000 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100010 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100100 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100110 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101000 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101010 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101100 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101110 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110000 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110010 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110100 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110110 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111000 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111010 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111100 | 0000000b, as printed |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 19 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111111 | 0000000b, as printed |
| 20 | `STG.E term[UR4][R4.64+0x8], R0` | 70-71 | 00 | 00 | 0000000b, as printed |
| 20 | `STG.E term[UR4][R4.64+0x8], R0` | 70-71 | 00 | 01 | 0000000b, as printed |
| 20 | `STG.E term[UR4][R4.64+0x8], R0` | 70-71 | 00 | 10 | 0000000b, as printed |
| 20 | `STG.E term[UR4][R4.64+0x8], R0` | 70-71 | 00 | 11 | 0000000b, as printed |
