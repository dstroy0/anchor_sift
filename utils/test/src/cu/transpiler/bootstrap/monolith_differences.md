# The monolith held against our compiler

Written by `monolith_emit build/monolith/emit/monolith_tagged.listing all <this file>` and written again on every run. Each block of the monolith's tagged build is NVIDIA's writing of one precept. A row with an address is one of NVIDIA's instructions held against our reader and our assembler; a row with a compiler column is our compiler's writing of the block's precept. Scheduler bits are 105 to 127, apart from the operation's.

98 of NVIDIA's instructions read: 0 with no form in the machine file, 59 whose text a form holds and whose bits it does not, 0 whose text a form holds with an operand it places none of, 1 with operation bits apart, 85 with scheduler bits apart.

| block | precept | address | NVIDIA | our reader | our assembler | scheduler | our compiler | difference |
|---|---|---|---|---|---|---|---|---|
| 1 | nop | 00040 | `IMAD.MOV.U32 R6, RZ, RZ, c[0x0][0x160]` | same | same | NVIDIA 0007f2, ours 0007f1 |  | scheduler bits |
| 1 | nop | 00050 | `IMAD.MOV.U32 R7, RZ, RZ, c[0x0][0x164]` | same | same | NVIDIA 0007e5, ours 0007f1 |  | scheduler bits |
| 1 | nop | 00060 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | same |  | a form holds its text, not these bits |
| 1 | nop | 00070 | `IMAD.MOV.U32 R4, RZ, RZ, c[0x0][0x168]` | same | same | NVIDIA 0007f2, ours 0007f1 |  | scheduler bits |
| 1 | nop | 00080 | `IMAD.MOV.U32 R5, RZ, RZ, c[0x0][0x16c]` | same | same | NVIDIA 0007e5, ours 0007f1 |  | scheduler bits |
| 1 | nop | 00090 | `STG.E.STRONG.SYS [R4.64], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0020f1, ours 0000f4 |  | a form holds its text, not these bits |
| 1 | nop |  |  |  |  |  | `the passage, no instruction` | none: NVIDIA's block is the passage |
| 2 | err | 000b0 | `LDG.E.STRONG.SYS R0, [R6.64+0x8]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000752, ours 000751 |  | a form holds its text, not these bits |
| 2 | err | 000c0 | `ISETP.NE.AND P0, PT, R0, RZ, PT` | same | same | NVIDIA 0027ed, ours 0007f1 |  | scheduler bits |
| 2 | err | 000d0 | `@!P0 BRA 0xf0` | `` @!P0 BRA `(0xf0) `` | same | NVIDIA 0007f5, ours 0007e0 |  | scheduler bits |
| 2 | err | 000e0 | `BPT.TRAP 0x1` | same | same | same |  | none |
| 2 | err | 000f0 | `STG.E.STRONG.SYS [R4.64+0x4], RZ` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0001f1, ours 0000f4 |  | a form holds its text, not these bits |
| 2 | err |  |  |  |  |  | `candidate 1, a trap in place` | the trap assembles |
| 2 | err |  |  |  |  |  | `` candidate 2, error on P0: @P0 BRA `(0x10) `` | taken where the flag is set, to a handler; NVIDIA's passes a trap where it is clear |
| 3 | not | 00110 | `LDG.E.STRONG.SYS R0, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000752, ours 000751 |  | a form holds its text, not these bits |
| 3 | not | 00120 | `LOP3.LUT R9, RZ, R0, RZ, 0x33, !PT` | same | same | NVIDIA 002fe5, ours 0627f2 |  | scheduler bits |
| 3 | not | 00130 | `STG.E.STRONG.SYS [R4.64+0x8], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 3 | not |  |  |  |  |  | `no word; the alphabet web writes it nand(left left)` | no word |
| 4 | and | 00150 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 4 | and | 00160 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f52, ours 000751 |  | a form holds its text, not these bits |
| 4 | and | 00170 | `LOP3.LUT R9, R0, R9, RZ, 0xc0, !PT` | same | same | NVIDIA 0027e5, ours 0627f2 |  | scheduler bits |
| 4 | and | 00180 | `STG.E.STRONG.SYS [R4.64+0xc], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 4 | and | 00170 | `LOP3.LUT R9, R0, R9, RZ, 0xc0, !PT` |  |  |  | `word_and: LOP3.LUT R9, R0, R9, RZ, 0xc0, !PT` | none, leaves in NVIDIA's order |
| 5 | or | 001a0 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 5 | or | 001b0 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f52, ours 000751 |  | a form holds its text, not these bits |
| 5 | or | 001c0 | `LOP3.LUT R9, R0, R9, RZ, 0xfc, !PT` | same | same | NVIDIA 0027e5, ours 0627f2 |  | scheduler bits |
| 5 | or | 001d0 | `STG.E.STRONG.SYS [R4.64+0x10], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 5 | or | 001c0 | `LOP3.LUT R9, R0, R9, RZ, 0xfc, !PT` |  |  |  | `word_or: LOP3.LUT R9, R0, R9, RZ, 0xfc, !PT` | none, leaves in NVIDIA's order |
| 6 | xor | 001f0 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 6 | xor | 00200 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f52, ours 000751 |  | a form holds its text, not these bits |
| 6 | xor | 00210 | `LOP3.LUT R9, R0, R9, RZ, 0x3c, !PT` | same | same | NVIDIA 0027e5, ours 0627f2 |  | scheduler bits |
| 6 | xor | 00220 | `STG.E.STRONG.SYS [R4.64+0x14], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 6 | xor | 00210 | `LOP3.LUT R9, R0, R9, RZ, 0x3c, !PT` |  |  |  | `word_xor: LOP3.LUT R9, R0, R9, RZ, 0x3c, !PT` | none, leaves in NVIDIA's order |
| 7 | nand | 00240 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 7 | nand | 00250 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f52, ours 000751 |  | a form holds its text, not these bits |
| 7 | nand | 00260 | `LOP3.LUT R0, R0, R9, RZ, 0xc0, !PT` | same | same | NVIDIA 0027e4, ours 0627f2 |  | scheduler bits |
| 7 | nand | 00270 | `LOP3.LUT R9, RZ, R0, RZ, 0x33, !PT` | same | same | NVIDIA 0007e5, ours 0627f2 |  | scheduler bits |
| 7 | nand | 00280 | `STG.E.STRONG.SYS [R4.64+0x18], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 7 | nand |  |  |  |  |  | `no word; the alphabet web writes it and(left right), not(n0 -)` | no word |
| 8 | nor | 002a0 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 8 | nor | 002b0 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f52, ours 000751 |  | a form holds its text, not these bits |
| 8 | nor | 002c0 | `LOP3.LUT R0, R0, R9, RZ, 0xfc, !PT` | same | same | NVIDIA 0027e4, ours 0627f2 |  | scheduler bits |
| 8 | nor | 002d0 | `LOP3.LUT R9, RZ, R0, RZ, 0x33, !PT` | same | same | NVIDIA 0007e5, ours 0627f2 |  | scheduler bits |
| 8 | nor | 002e0 | `STG.E.STRONG.SYS [R4.64+0x1c], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 8 | nor |  |  |  |  |  | `no word; the alphabet web writes it or(left right), not(n0 -)` | no word |
| 9 | mov | 00300 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f54, ours 000751 |  | a form holds its text, not these bits |
| 9 | mov | 00310 | `STG.E.STRONG.SYS [R4.64+0x20], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0020f1, ours 0000f4 |  | a form holds its text, not these bits |
| 9 | mov |  |  |  |  |  | `candidate 1, the passage, no instruction` | none: NVIDIA's block is the passage |
| 9 | mov |  |  |  |  |  | `candidate 2, word_copy: MOV R9, R9` | one instruction where NVIDIA's block holds none |
| 10 | shl | 00330 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 10 | shl | 00340 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f52, ours 000751 |  | a form holds its text, not these bits |
| 10 | shl | 00350 | `SHF.L.W.U32 R9, R9, R0, RZ` | same | same | NVIDIA 0027e5, ours 0427f2 |  | scheduler bits |
| 10 | shl | 00360 | `STG.E.STRONG.SYS [R4.64+0x24], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 10 | shl | 00350 | `SHF.L.W.U32 R9, R9, R0, RZ` |  |  |  | `word_shift_left: SHF.L.U32 R9, R9, R0, RZ` | operation bits apart; NVIDIA's carries .W and ours does not; apart at 1 bits |
| 11 | shr | 00380 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 11 | shr | 00390 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f52, ours 000751 |  | a form holds its text, not these bits |
| 11 | shr | 003a0 | `SHF.R.W.U32.HI R9, RZ, R0, R9` | same | same | NVIDIA 0027e5, ours 0007e3 |  | scheduler bits |
| 11 | shr | 003b0 | `STG.E.STRONG.SYS [R4.64+0x28], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 11 | shr | 003a0 | `SHF.R.W.U32.HI R9, RZ, R0, R9` |  |  |  | `word_shift_right: SHF.R.U32.HI R9, RZ, R0, R9` | operation bits apart; NVIDIA's carries .W and ours does not; apart at 1 bits |
| 12 | asr | 003d0 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 12 | asr | 003e0 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f52, ours 000751 |  | a form holds its text, not these bits |
| 12 | asr | 003f0 | `SHF.R.W.S32.HI R9, RZ, R0, R9` | same | same | NVIDIA 0027e5, ours 0007e3 |  | scheduler bits |
| 12 | asr | 00400 | `STG.E.STRONG.SYS [R4.64+0x2c], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 12 | asr |  |  |  |  |  | `no word; the alphabet web holds no tree for it` | no word |
| 13 | rol | 00420 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 13 | rol | 00430 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f71, ours 000751 |  | a form holds its text, not these bits |
| 13 | rol | 00440 | `LOP3.LUT P0, R0, R0, 0x1f, RZ, 0xc0, !PT` | same | same | NVIDIA 0027ed, ours 0007f1 |  | scheduler bits |
| 13 | rol | 00450 | `@P0 SHF.L.W.U32.HI R9, R9, R0, R9` | same | same | NVIDIA 0047e5, ours 0427f2 |  | scheduler bits |
| 13 | rol | 00460 | `STG.E.STRONG.SYS [R4.64+0x30], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 13 | rol |  |  |  |  |  | `no word; the alphabet web holds no tree for it` | no word |
| 14 | ror | 00480 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 14 | ror | 00490 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f71, ours 000751 |  | a form holds its text, not these bits |
| 14 | ror | 004a0 | `LOP3.LUT P0, R0, R0, 0x1f, RZ, 0xc0, !PT` | same | same | NVIDIA 0027ed, ours 0007f1 |  | scheduler bits |
| 14 | ror | 004b0 | `@P0 SHF.R.W.U32 R9, R9, R0, R9` | same | same | NVIDIA 0047e5, ours 0027e5 |  | scheduler bits |
| 14 | ror | 004c0 | `STG.E.STRONG.SYS [R4.64+0x34], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 14 | ror |  |  |  |  |  | `no word; the alphabet web holds no tree for it` | no word |
| 15 | add | 004e0 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 15 | add | 004f0 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f52, ours 000751 |  | a form holds its text, not these bits |
| 15 | add | 00500 | `IMAD.IADD R9, R0, 0x1, R9` | `IMAD.MOV R9, R0, 0x1, R9` | same | NVIDIA 0027e5, ours 000fe5 |  | scheduler bits |
| 15 | add | 00510 | `STG.E.STRONG.SYS [R4.64+0x38], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 15 | add | 00500 | `IMAD.IADD R9, R0, 0x1, R9` |  |  |  | `add_alone: IADD3 R9, R0, R9, RZ` | operation bits apart; NVIDIA's carries .IADD and ours does not; apart at 20 bits |
| 16 | sub | 00530 | `LDG.E.STRONG.SYS R0, [R6.64+0x4]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 16 | sub | 00540 | `LDG.E.STRONG.SYS R9, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000f52, ours 000751 |  | a form holds its text, not these bits |
| 16 | sub | 00550 | `IMAD.IADD R9, R9, 0x1, -R0` | `IMAD.MOV R9, R9, 0x1, -R0` | apart at bit 87 89 90 | NVIDIA 0027e5, ours 0007f1 |  | operation bits apart |
| 16 | sub | 00560 | `STG.E.STRONG.SYS [R4.64+0x3c], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 16 | sub | 00550 | `IMAD.IADD R9, R9, 0x1, -R0` |  |  |  | `subtract_alone: IADD3 R9, R9, -R0, RZ` | operation bits apart; NVIDIA's carries .IADD and ours does not; apart at 24 bits |
| 17 | bra | 00580 | `LDG.E.STRONG.SYS R0, [R6.64+0x8]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000752, ours 000751 |  | a form holds its text, not these bits |
| 17 | bra | 00590 | `ISETP.NE.AND P0, PT, R0, RZ, PT` | same | same | NVIDIA 0027ed, ours 0007f1 |  | scheduler bits |
| 17 | bra | 005a0 | `@!P0 BRA 0x640` | `` @!P0 BRA `(0x640) `` | same | NVIDIA 0007f5, ours 0007e0 |  | scheduler bits |
| 17 | bra | 005b0 | `IMAD.MOV.U32 R9, RZ, RZ, 0x1` | same | same | NVIDIA 000ff2, ours 0007f1 |  | scheduler bits |
| 17 | bra | 005c0 | `IMAD.MOV.U32 R11, RZ, RZ, 0x2` | same | same | NVIDIA 0007f2, ours 0007f1 |  | scheduler bits |
| 17 | bra | 005d0 | `IMAD.MOV.U32 R13, RZ, RZ, 0x3` | same | same | same |  | none |
| 17 | bra | 005e0 | `STG.E.STRONG.SYS [R4.64+0x40], R9` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 17 | bra | 005f0 | `IMAD.MOV.U32 R15, RZ, RZ, 0x4` | same | same | NVIDIA 0007e3, ours 0007f1 |  | scheduler bits |
| 17 | bra | 00600 | `STG.E.STRONG.SYS [R4.64+0x40], R11` | a form holds its text and not its bits | apart at bit 69 | same |  | a form holds its text, not these bits |
| 17 | bra | 00610 | `STG.E.STRONG.SYS [R4.64+0x40], R13` | a form holds its text and not its bits | apart at bit 69 | same |  | a form holds its text, not these bits |
| 17 | bra | 00620 | `STG.E.STRONG.SYS [R4.64+0x40], R15` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f1, ours 0000f4 |  | a form holds its text, not these bits |
| 17 | bra | 00630 | `BRA 0x6b0` | `` BRA `(0x6b0) `` | same | NVIDIA 0007f5, ours 0007e0 |  | scheduler bits |
| 17 | bra | 00640 | `IMAD.MOV.U32 R9, RZ, RZ, 0x5` | same | same | NVIDIA 000ff2, ours 0007f1 |  | scheduler bits |
| 17 | bra | 00650 | `IMAD.MOV.U32 R11, RZ, RZ, 0x6` | same | same | NVIDIA 0007e2, ours 0007f1 |  | scheduler bits |
| 17 | bra | 00660 | `IMAD.MOV.U32 R13, RZ, RZ, 0x7` | same | same | same |  | none |
| 17 | bra | 00670 | `STG.E.STRONG.SYS [R4.64+0x40], R9` | a form holds its text and not its bits | apart at bit 69 | same |  | a form holds its text, not these bits |
| 17 | bra | 00680 | `STG.E.STRONG.SYS [R4.64+0x40], R11` | a form holds its text and not its bits | apart at bit 69 | same |  | a form holds its text, not these bits |
| 17 | bra | 00690 | `STG.E.STRONG.SYS [R4.64+0x40], R13` | a form holds its text and not its bits | apart at bit 69 | same |  | a form holds its text, not these bits |
| 17 | bra | 006a0 | `STG.E.STRONG.SYS [R4.64+0x40], RZ` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0000f2, ours 0000f4 |  | a form holds its text, not these bits |
| 17 | bra |  |  |  |  |  | `no word; the alphabet web writes it jcc(ones left)` | no word |
| 18 | jcc | 006c0 | `LDG.E.STRONG.SYS R0, [R6.64+0x8]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000752, ours 000751 |  | a form holds its text, not these bits |
| 18 | jcc | 006d0 | `ISETP.NE.AND P0, PT, R0, RZ, PT` | same | same | NVIDIA 0027ed, ours 0007f1 |  | scheduler bits |
| 18 | jcc | 006e0 | `@P0 BRA 0x770` | `` @P0 BRA `(0x770) `` | same | NVIDIA 0007f5, ours 0007e0 |  | scheduler bits |
| 18 | jcc | 006f0 | `IMAD.MOV.U32 R9, RZ, RZ, 0x1` | same | same | NVIDIA 000ff2, ours 0007f1 |  | scheduler bits |
| 18 | jcc | 00700 | `IMAD.MOV.U32 R11, RZ, RZ, 0x2` | same | same | NVIDIA 0007f2, ours 0007f1 |  | scheduler bits |
| 18 | jcc | 00710 | `IMAD.MOV.U32 R13, RZ, RZ, 0x3` | same | same | same |  | none |
| 18 | jcc | 00720 | `STG.E.STRONG.SYS [R4.64+0x44], R9` | a form holds its text and not its bits | apart at bit 69 | same |  | a form holds its text, not these bits |
| 18 | jcc | 00730 | `STG.E.STRONG.SYS [R4.64+0x44], R11` | a form holds its text and not its bits | apart at bit 69 | same |  | a form holds its text, not these bits |
| 18 | jcc | 00740 | `STG.E.STRONG.SYS [R4.64+0x44], R13` | a form holds its text and not its bits | apart at bit 69 | same |  | a form holds its text, not these bits |
| 18 | jcc | 00750 | `LDG.E.STRONG.SYS R7, [R6.64]` | a form holds its text and not its bits | apart at bit 37 | NVIDIA 000754, ours 000751 |  | a form holds its text, not these bits |
| 18 | jcc | 00760 | `STG.E.STRONG.SYS [R4.64+0x44], R7` | a form holds its text and not its bits | apart at bit 69 | NVIDIA 0020f2, ours 0000f4 |  | a form holds its text, not these bits |
| 18 | jcc | 006e0 | `@P0 BRA 0x770` |  |  |  | `` loop_back on P0: @P0 BRA `(0x6f0) `` | guard the same, operation the same, target its own label's |

## Bits apart

Each instruction whose operation bits are apart from NVIDIA's, both encodings bit by bit with bit 127 first under each byte's top bit; `^` marks an operation bit apart and `.` a scheduler bit apart.

Block 1, nop, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                                                                                                              ^                                         
```

Block 1, nop, `STG.E.STRONG.SYS [R4.64], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 01000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00000000 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00000000 00001001 00000100 00000000 01111001 10000110
                   .           . .                                        ^                                                                             
```

Block 2, err, `LDG.E.STRONG.SYS R0, [R6.64+0x8]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00001000 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00001000 00100100 00000110 00000000 01111001 10000001
                                ..                                                                            ^                                         
```

Block 2, err, `STG.E.STRONG.SYS [R4.64+0x4], RZ`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000011 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00000100 11111111 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00000100 11111111 00000100 00000000 01111001 10000110
                        .      . .                                        ^                                                                             
```

Block 3, not, `LDG.E.STRONG.SYS R0, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00000000 01111001 10000001
                                ..                                                                            ^                                         
```

Block 3, not, `STG.E.STRONG.SYS [R4.64+0x8], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00001000 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00001000 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 4, and, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 4, and, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .          ..                                                                            ^                                         
```

Block 4, and, `STG.E.STRONG.SYS [R4.64+0xc], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00001100 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00001100 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 5, or, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 5, or, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .          ..                                                                            ^                                         
```

Block 5, or, `STG.E.STRONG.SYS [R4.64+0x10], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00010000 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00010000 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 6, xor, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 6, xor, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .          ..                                                                            ^                                         
```

Block 6, xor, `STG.E.STRONG.SYS [R4.64+0x14], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00010100 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00010100 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 7, nand, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 7, nand, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .          ..                                                                            ^                                         
```

Block 7, nand, `STG.E.STRONG.SYS [R4.64+0x18], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00011000 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00011000 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 8, nor, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 8, nor, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .          ..                                                                            ^                                         
```

Block 8, nor, `STG.E.STRONG.SYS [R4.64+0x1c], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00011100 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00011100 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 9, mov, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .         . .                                                                            ^                                         
```

Block 9, mov, `STG.E.STRONG.SYS [R4.64+0x20], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 01000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00100000 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00100000 00001001 00000100 00000000 01111001 10000110
                   .           . .                                        ^                                                                             
```

Block 10, shl, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 10, shl, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .          ..                                                                            ^                                         
```

Block 10, shl, `STG.E.STRONG.SYS [R4.64+0x24], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00100100 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00100100 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 10, shl, `SHF.L.W.U32 R9, R9, R0, RZ`, word_shift_left: SHF.L.U32 R9, R9, R0, RZ

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 01001111 11001010 00000000 00000000 00000000 00001110 11111111 00000000 00000000 00000000 00000000 00001001 00001001 01110010 00011001
ours     00001000 01001111 11100100 00000000 00000000 00000000 00000110 11111111 00000000 00000000 00000000 00000000 00001001 00001001 01110010 00011001
             .               . ...                                 ^                                                                                    
```

Block 11, shr, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 11, shr, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .          ..                                                                            ^                                         
```

Block 11, shr, `STG.E.STRONG.SYS [R4.64+0x28], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00101000 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00101000 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 11, shr, `SHF.R.W.U32.HI R9, RZ, R0, R9`, word_shift_right: SHF.R.U32.HI R9, RZ, R0, R9

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 01001111 11001010 00000000 00000000 00000001 00011110 00001001 00000000 00000000 00000000 00000000 11111111 00001001 01110010 00011001
ours     00000000 00001111 11000110 00000000 00000000 00000001 00010110 00001001 00000000 00000000 00000000 00000000 11111111 00001001 01110010 00011001
                   .           ..                                  ^                                                                                    
```

Block 12, asr, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 12, asr, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .          ..                                                                            ^                                         
```

Block 12, asr, `STG.E.STRONG.SYS [R4.64+0x2c], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00101100 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00101100 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 13, rol, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 13, rol, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 11100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .      .                                                                                 ^                                         
```

Block 13, rol, `STG.E.STRONG.SYS [R4.64+0x30], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00110000 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00110000 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 14, ror, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 14, ror, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 11100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .      .                                                                                 ^                                         
```

Block 14, ror, `STG.E.STRONG.SYS [R4.64+0x34], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00110100 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00110100 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 15, add, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 15, add, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .          ..                                                                            ^                                         
```

Block 15, add, `STG.E.STRONG.SYS [R4.64+0x38], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00111000 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00111000 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 15, add, `IMAD.IADD R9, R0, 0x1, R9`, add_alone: IADD3 R9, R0, R9, RZ

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 01001111 11001010 00000000 00000111 10001110 00000010 00001001 00000000 00000000 00000000 00000001 00000000 00001001 01111000 00100100
ours     00000000 01001111 11001010 00000000 00000111 11111111 11100000 11111111 00000000 00000000 00000000 00001001 00000000 00001001 01110010 00010000
                                                       ^^^   ^ ^^^   ^  ^^^^ ^^                                 ^                          ^ ^    ^^ ^  
```

Block 16, sub, `LDG.E.STRONG.SYS R0, [R6.64+0x4]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000100 00100100 00000110 00000000 01111001 10000001
                               . .                                                                            ^                                         
```

Block 16, sub, `LDG.E.STRONG.SYS R9, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00011110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00001001 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00001001 01111001 10000001
                     .          ..                                                                            ^                                         
```

Block 16, sub, `IMAD.IADD R9, R9, 0x1, -R0`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 01001111 11001010 00000000 00000111 10001110 00001010 00000000 00000000 00000000 00000000 00000001 00001001 00001001 01111000 00100100
ours     00000000 00001111 11100010 00000000 00000001 00001110 00001010 00000000 00000000 00000000 00000000 00000001 00001001 00001001 01111000 00100100
                   .         . .                  ^^  ^                                                                                                 
```

Block 16, sub, `STG.E.STRONG.SYS [R4.64+0x3c], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 00111100 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 00111100 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 16, sub, `IMAD.IADD R9, R9, 0x1, -R0`, subtract_alone: IADD3 R9, R9, -R0, RZ

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 01001111 11001010 00000000 00000111 10001110 00001010 00000000 00000000 00000000 00000000 00000001 00001001 00001001 01111000 00100100
ours     00000000 01001111 11001010 00000000 00000111 11111111 11100000 11111111 10000000 00000000 00000000 00000000 00001001 00001001 01110010 00010000
                                                       ^^^   ^ ^^^ ^ ^  ^^^^^^^^ ^                                 ^                       ^ ^    ^^ ^  
```

Block 17, bra, `LDG.E.STRONG.SYS R0, [R6.64+0x8]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00001000 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00001000 00100100 00000110 00000000 01111001 10000001
                                ..                                                                            ^                                         
```

Block 17, bra, `STG.E.STRONG.SYS [R4.64+0x40], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000000 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000000 00001001 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 17, bra, `STG.E.STRONG.SYS [R4.64+0x40], R11`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11101000 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000000 00001011 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000000 00001011 00000100 00000000 01111001 10000110
                                                                          ^                                                                             
```

Block 17, bra, `STG.E.STRONG.SYS [R4.64+0x40], R13`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11101000 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000000 00001101 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000000 00001101 00000100 00000000 01111001 10000110
                                                                          ^                                                                             
```

Block 17, bra, `STG.E.STRONG.SYS [R4.64+0x40], R15`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100010 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000000 00001111 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000000 00001111 00000100 00000000 01111001 10000110
                               . .                                        ^                                                                             
```

Block 17, bra, `STG.E.STRONG.SYS [R4.64+0x40], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11101000 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000000 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000000 00001001 00000100 00000000 01111001 10000110
                                                                          ^                                                                             
```

Block 17, bra, `STG.E.STRONG.SYS [R4.64+0x40], R11`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11101000 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000000 00001011 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000000 00001011 00000100 00000000 01111001 10000110
                                                                          ^                                                                             
```

Block 17, bra, `STG.E.STRONG.SYS [R4.64+0x40], R13`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11101000 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000000 00001101 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000000 00001101 00000100 00000000 01111001 10000110
                                                                          ^                                                                             
```

Block 17, bra, `STG.E.STRONG.SYS [R4.64+0x40], RZ`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11100100 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000000 11111111 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000000 11111111 00000100 00000000 01111001 10000110
                               ..                                         ^                                                                             
```

Block 18, jcc, `LDG.E.STRONG.SYS R0, [R6.64+0x8]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10100100 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00001000 00000100 00000110 00000000 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00001000 00100100 00000110 00000000 01111001 10000001
                                ..                                                                            ^                                         
```

Block 18, jcc, `STG.E.STRONG.SYS [R4.64+0x44], R9`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11101000 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000100 00001001 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000100 00001001 00000100 00000000 01111001 10000110
                                                                          ^                                                                             
```

Block 18, jcc, `STG.E.STRONG.SYS [R4.64+0x44], R11`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11101000 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000100 00001011 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000100 00001011 00000100 00000000 01111001 10000110
                                                                          ^                                                                             
```

Block 18, jcc, `STG.E.STRONG.SYS [R4.64+0x44], R13`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00000001 11101000 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000100 00001101 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000100 00001101 00000100 00000000 01111001 10000110
                                                                          ^                                                                             
```

Block 18, jcc, `LDG.E.STRONG.SYS R7, [R6.64]`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 00001110 10101000 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00000100 00000110 00000111 01111001 10000001
ours     00000000 00001110 10100010 00000000 00001100 00011111 01011001 00000000 00000000 00000000 00000000 00100100 00000110 00000111 01111001 10000001
                               . .                                                                            ^                                         
```

Block 18, jcc, `STG.E.STRONG.SYS [R4.64+0x44], R7`, our assembler

```
         127      119      111      103      95       87       79       71       63       55       47       39       31       23       15       7        
NVIDIA   00000000 01000001 11100100 00000000 00001100 00010001 01011001 00000100 00000000 00000000 01000100 00000111 00000100 00000000 01111001 10000110
ours     00000000 00000001 11101000 00000000 00001100 00010001 01011001 00100100 00000000 00000000 01000100 00000111 00000100 00000000 01111001 10000110
                   .           ..                                         ^                                                                             
```
