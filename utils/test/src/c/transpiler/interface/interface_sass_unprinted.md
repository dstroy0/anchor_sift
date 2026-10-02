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
15. `STG.E term[UR4][R4.64+0x8], R0`; `LDG.E.CONSTANT R7, term[UR4][R4.64+0x8]`
16. `STG.E term[UR4][R4.64+0x8], R0`; `LDG.E.CONSTANT R7, term[UR4][R4.64+0x8]`

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
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000000 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000010 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000100 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000110 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 000111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001000 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001010 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001100 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001110 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 001111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010000 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010010 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010100 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010110 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 010111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011000 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011010 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011100 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011110 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 011111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100000 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100010 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100100 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100110 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 100111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101000 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101010 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101100 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101110 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 101111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110000 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110010 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110100 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110110 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 110111 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111000 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111001 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111010 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111011 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111100 | 0000000b, as printed |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111101 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111110 | did not run: exited, code 3, cudaErrorIllegalInstruction |
| 15 | `STG.E term[UR4][R4.64+0x8], R0` | 64-69, bit 101 held at 0 | 000100 | 111111 | 0000000b, as printed |
| 16 | `STG.E term[UR4][R4.64+0x8], R0` | 70-71 | 00 | 00 | 0000000b, as printed |
| 16 | `STG.E term[UR4][R4.64+0x8], R0` | 70-71 | 00 | 01 | 0000000b, as printed |
| 16 | `STG.E term[UR4][R4.64+0x8], R0` | 70-71 | 00 | 10 | 0000000b, as printed |
| 16 | `STG.E term[UR4][R4.64+0x8], R0` | 70-71 | 00 | 11 | 0000000b, as printed |
