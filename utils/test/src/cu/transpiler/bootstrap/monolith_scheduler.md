# The scheduler's bits NVIDIA's compiler writes

Written by `monolith_scheduler.sh` whole on every run. Every CUDA source of the tree is built by NVIDIA's compiler for one part, each cubin's code sections are read from the ELF, each instruction is named by our reader through the machine file and its bits 105 to 127 read through the fields the machine file names. No listing is read and no disassembler is run.

72 cubins, 96976 instructions, 7426 no form reads, 176 operations.

An operation's soonest read is the fewest cycles, its stalls summed, between it and the first instruction that reads the register it writes, over every place it sets no write barrier. Readers waiting count the first readers of a register it writes with a write barrier that wait on that barrier, against those that do not. The machine file columns count the places whose form records a write barrier, and a read barrier, against the places a form was found.

| operation | written | stalls | write barrier | read barrier | waits | soonest read | readers waiting | machine file write | machine file read |
|---|---|---|---|---|---|---|---|---|---|
| `LOP3.LUT` | 45708 | 1 to 13, most often 2 | 0 | 0 | 74 | 4 over 43277 | 0 of 0 | 0 of 45708 | 0 of 45708 |
| `IADD3` | 5460 | 1 to 11, most often 2 | 0 | 0 | 687 | 4 over 4182 | 0 of 0 | 0 of 5460 | 0 of 5460 |
| `SHF.R.U32.HI` | 3282 | 1 to 9, most often 2 | 0 | 0 | 64 | 4 over 3216 | 0 of 0 | 0 of 3282 | 0 of 3282 |
| `IMAD.MOV.U32` | 3245 | 1 to 12, most often 1 | 0 | 0 | 223 | 4 over 1012 | 0 of 0 | 0 of 3245 | 0 of 3245 |
| `SHF.L.U32` | 3079 | 1 to 5, most often 2 | 0 | 0 | 24 | 4 over 3072 | 0 of 0 | 0 of 3079 | 0 of 3079 |
| `SHF.R.S32.HI` | 3000 | 1 to 4, most often 2 | 0 | 0 | 0 | 4 over 2996 | 0 of 0 | 0 of 3000 | 0 of 3000 |
| `no form, key 0xa10` | 2742 | 1 to 4, most often 2 | 0 | 0 | 2 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `SHF.L.W.U32.HI` | 2709 | 1 to 5, most often 2 | 0 | 0 | 1 | 4 over 2704 | 0 of 0 | 0 of 2709 | 0 of 2709 |
| `SHF.R.W.U32` | 2501 | 1 to 5, most often 2 | 0 | 0 | 1 | 4 over 2497 | 0 of 0 | 0 of 2501 | 0 of 2501 |
| `BRA` | 2384 | 0 to 12, most often 5 | 0 | 0 | 44 | - | 0 of 0 | 0 of 2384 | 0 of 2384 |
| `IMAD` | 1609 | 1 to 12, most often 2 | 0 | 0 | 230 | 4 over 1163 | 0 of 0 | 0 of 1609 | 0 of 1609 |
| `ISETP.NE.AND` | 1441 | 1 to 13, most often 13 | 0 | 0 | 949 | - | 0 of 0 | 0 of 1441 | 0 of 1441 |
| `LDG.E` | 1398 | 1 to 12, most often 4 | 1398 | 156 | 201 | - | 960 of 977 | 1398 of 1398 | 0 of 1398 |
| `IMAD.X` | 1284 | 1 to 12, most often 1 | 0 | 0 | 7 | 4 over 598 | 0 of 0 | 0 of 1284 | 0 of 1284 |
| `IMAD.WIDE.U32` | 1040 | 1 to 12, most often 4 | 0 | 0 | 203 | 4 over 621 | 0 of 0 | 0 of 1040 | 0 of 1040 |
| `no form, key 0x980` | 946 | 1 to 12, most often 4 | 946 | 31 | 15 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.GE.U32.AND` | 937 | 1 to 13, most often 1 | 0 | 0 | 77 | - | 0 of 0 | 0 of 937 | 0 of 937 |
| `SEL` | 827 | 1 to 9, most often 2 | 0 | 0 | 31 | 4 over 563 | 0 of 0 | 0 of 827 | 0 of 827 |
| `STG.E` | 810 | 1 to 12, most often 4 | 0 | 727 | 347 | - | 0 of 0 | 0 of 810 | 0 of 810 |
| `NOP` | 732 | 0 to 0, most often 0 | 0 | 0 | 0 | - | 0 of 0 | 0 of 732 | 0 of 732 |
| `IMAD.IADD` | 711 | 1 to 12, most often 1 | 0 | 0 | 57 | 4 over 300 | 0 of 0 | 0 of 711 | 0 of 711 |
| `ISETP.NE.U32.AND` | 619 | 1 to 13, most often 2 | 0 | 0 | 41 | - | 0 of 0 | 0 of 619 | 0 of 619 |
| `no form, key 0x819` | 564 | 1 to 5, most often 2 | 0 | 0 | 21 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `IADD3.X` | 517 | 1 to 11, most often 2 | 0 | 0 | 16 | 4 over 331 | 0 of 0 | 0 of 517 | 0 of 517 |
| `no form, key 0xa11` | 507 | 1 to 11, most often 2 | 0 | 0 | 18 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `IMAD.HI.U32` | 473 | 1 to 8, most often 4 | 0 | 0 | 9 | 4 over 450 | 0 of 0 | 0 of 473 | 0 of 473 |
| `no form, key 0xc10` | 404 | 1 to 11, most often 2 | 0 | 0 | 33 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `CS2R` | 366 | 1 to 11, most often 1 | 0 | 0 | 89 | 6 over 94 | 0 of 0 | 0 of 366 | 0 of 366 |
| `ISETP.GT.U32.AND` | 335 | 1 to 13, most often 2 | 0 | 0 | 93 | - | 0 of 0 | 0 of 335 | 0 of 335 |
| `ISETP.GE.U32.AND.EX` | 293 | 1 to 13, most often 13 | 0 | 0 | 0 | - | 0 of 0 | 0 of 293 | 0 of 293 |
| `IMAD.MOV` | 255 | 1 to 12, most often 4 | 0 | 0 | 69 | 4 over 234 | 0 of 0 | 0 of 255 | 0 of 255 |
| `ISETP.NE.AND.EX` | 247 | 1 to 13, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 247 | 0 of 247 |
| `LDG.E.64` | 231 | 1 to 12, most often 1 | 231 | 66 | 49 | - | 115 of 121 | 231 of 231 | 0 of 231 |
| `MOV` | 222 | 1 to 11, most often 1 | 0 | 0 | 18 | 4 over 50 | 0 of 0 | 0 of 222 | 0 of 222 |
| `no form, key 0x981` | 208 | 1 to 4, most often 1 | 208 | 86 | 10 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x941` | 195 | 5 to 5, most often 5 | 0 | 0 | 15 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x945` | 195 | 1 to 12, most often 1 | 0 | 0 | 2 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x983` | 188 | 1 to 11, most often 4 | 188 | 90 | 5 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.GT.U32.AND.EX` | 183 | 1 to 13, most often 4 | 0 | 0 | 0 | - | 0 of 0 | 0 of 183 | 0 of 183 |
| `EXIT` | 179 | 5 to 8, most often 5 | 0 | 0 | 0 | - | 0 of 0 | 0 of 179 | 0 of 179 |
| `LDS` | 170 | 1 to 4, most often 1 | 142 | 105 | 6 | 6 over 16 | 99 of 99 | 0 of 170 | 0 of 170 |
| `CALL.REL.NOINC` | 167 | 1 to 5, most often 1 | 0 | 0 | 22 | - | 0 of 0 | 0 of 167 | 0 of 167 |
| `no form, key 0x211` | 164 | 1 to 6, most often 1 | 0 | 0 | 18 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `S2R` | 156 | 1 to 10, most often 1 | 156 | 0 | 2 | - | 98 of 98 | 137 of 156 | 0 of 156 |
| `STG.E.64` | 143 | 1 to 12, most often 4 | 0 | 139 | 18 | - | 0 of 0 | 0 of 143 | 0 of 143 |
| `no form, key 0x985` | 143 | 1 to 5, most often 4 | 0 | 131 | 39 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `BSSY` | 139 | 1 to 12, most often 1 | 0 | 0 | 1 | - | 0 of 0 | 0 of 139 | 0 of 139 |
| `BSYNC` | 139 | 5 to 5, most often 5 | 0 | 0 | 8 | - | 0 of 0 | 0 of 139 | 0 of 139 |
| `MUFU.RCP` | 138 | 1 to 8, most often 2 | 121 | 1 | 135 | 17 over 10 | 112 of 112 | 138 of 138 | 0 of 138 |
| `ULDC.64` | 132 | 1 to 12, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 132 | 0 of 132 |
| `SHF.L.U64.HI` | 120 | 1 to 11, most often 2 | 0 | 0 | 10 | 4 over 88 | 0 of 0 | 0 of 120 | 0 of 120 |
| `LDS.64` | 117 | 1 to 4, most often 2 | 117 | 7 | 5 | - | 109 of 109 | 117 of 117 | 0 of 117 |
| `IMAD.U32` | 116 | 1 to 12, most often 2 | 0 | 0 | 29 | 5 over 50 | 0 of 0 | 0 of 116 | 0 of 116 |
| `ISETP.EQ.U32.AND` | 113 | 1 to 4, most often 4 | 0 | 0 | 102 | - | 0 of 0 | 0 of 113 | 0 of 113 |
| `F2I.FTZ.U32.TRUNC.NTZ` | 110 | 1 to 11, most often 2 | 109 | 93 | 0 | - | 94 of 94 | 110 of 110 | 110 of 110 |
| `no form, key 0xc82` | 108 | 1 to 8, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `STG.E.STRONG.SYS` | 106 | 1 to 4, most often 2 | 0 | 104 | 3 | - | 0 of 0 | 0 of 106 | 106 of 106 |
| `ULDC` | 105 | 1 to 2, most often 2 | 0 | 0 | 2 | - | 0 of 0 | 0 of 105 | 0 of 105 |
| `ISETP.EQ.U32.AND.EX` | 100 | 13 to 13, most often 13 | 0 | 0 | 0 | - | 0 of 0 | 0 of 100 | 0 of 100 |
| `no form, key 0x38d` | 100 | 2 to 2, most often 2 | 100 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `STG.E.U8` | 96 | 1 to 4, most often 1 | 0 | 95 | 0 | - | 0 of 0 | 0 of 96 | 0 of 96 |
| `STL.64` | 92 | 1 to 11, most often 1 | 0 | 79 | 1 | - | 0 of 0 | 0 of 92 | 92 of 92 |
| `LDG.E.U8` | 86 | 1 to 4, most often 4 | 86 | 8 | 0 | - | 11 of 11 | 86 of 86 | 0 of 86 |
| `PLOP3.LUT` | 77 | 1 to 13, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 77 | 0 of 77 |
| `no form, key 0xa0c` | 77 | 1 to 13, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `STG.E.64.STRONG.SYS` | 76 | 4 to 4, most often 4 | 0 | 76 | 0 | - | 0 of 0 | 0 of 76 | 76 of 76 |
| `STS` | 70 | 1 to 4, most often 1 | 0 | 39 | 7 | - | 0 of 0 | 0 of 70 | 70 of 70 |
| `no form, key 0x207` | 70 | 1 to 9, most often 2 | 0 | 0 | 7 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x890` | 68 | 1 to 10, most often 2 | 0 | 0 | 1 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x80c` | 67 | 1 to 13, most often 4 | 0 | 0 | 2 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `UIMAD` | 64 | 1 to 6, most often 2 | 0 | 0 | 1 | - | 0 of 0 | 0 of 64 | 0 of 64 |
| `ISETP.GT.AND.EX` | 61 | 1 to 13, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 61 | 0 of 61 |
| `no form, key 0x387` | 55 | 1 to 6, most often 1 | 0 | 52 | 1 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0xb06` | 54 | 1 to 8, most often 1 | 54 | 0 | 2 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.GE.U32.OR.EX` | 53 | 1 to 13, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 53 | 0 of 53 |
| `no form, key 0x816` | 47 | 1 to 4, most often 4 | 0 | 0 | 9 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `UIADD3` | 46 | 1 to 12, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 46 | 0 of 46 |
| `UMOV` | 41 | 1 to 12, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 41 | 0 of 41 |
| `no form, key 0xabb` | 38 | 1 to 4, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `IMNMX.U32` | 37 | 1 to 5, most often 4 | 0 | 0 | 5 | 4 over 30 | 0 of 0 | 0 of 37 | 0 of 37 |
| `UIMAD.WIDE.U32` | 35 | 1 to 4, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 35 | 0 of 35 |
| `SHF.R.U64` | 34 | 2 to 4, most often 2 | 0 | 0 | 30 | 4 over 34 | 0 of 0 | 0 of 34 | 0 of 34 |
| `no form, key 0xd06` | 34 | 1 to 8, most often 1 | 31 | 0 | 2 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.GT.AND` | 32 | 1 to 13, most often 13 | 0 | 0 | 0 | - | 0 of 0 | 0 of 32 | 0 of 32 |
| `no form, key 0xb82` | 32 | 1 to 8, most often 1 | 32 | 2 | 1 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `LDG.E.STRONG.SYS` | 31 | 1 to 4, most often 2 | 31 | 0 | 13 | - | 31 of 31 | 31 of 31 | 0 of 31 |
| `RED.E.ADD.64.STRONG.GPU` | 31 | 1 to 4, most often 2 | 0 | 26 | 9 | - | 0 of 0 | 0 of 31 | 0 of 31 |
| `ISETP.LT.U32.AND` | 30 | 1 to 4, most often 1 | 0 | 0 | 4 | - | 0 of 0 | 0 of 30 | 0 of 30 |
| `F2I.U64.TRUNC` | 28 | 2 to 2, most often 2 | 28 | 0 | 0 | - | 28 of 28 | 28 of 28 | 0 of 28 |
| `no form, key 0x950` | 28 | 5 to 6, most often 6 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.NE.OR.EX` | 27 | 1 to 13, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 27 | 0 of 27 |
| `YIELD` | 27 | 1 to 1, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 27 | 0 of 27 |
| `no form, key 0x290` | 27 | 1 to 4, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `SHF.R.W.U32.HI` | 26 | 2 to 5, most often 4 | 0 | 0 | 26 | 4 over 25 | 0 of 0 | 0 of 26 | 0 of 26 |
| `no form, key 0xc0c` | 26 | 1 to 13, most often 1 | 0 | 0 | 19 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x2bd` | 25 | 1 to 6, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x886` | 25 | 1 to 2, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x899` | 24 | 1 to 12, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.LE.U32.AND` | 23 | 1 to 4, most often 4 | 0 | 0 | 1 | - | 0 of 0 | 0 of 23 | 0 of 23 |
| `I2F.U32.RP` | 22 | 1 to 8, most often 1 | 22 | 0 | 10 | - | 21 of 21 | 22 of 22 | 0 of 22 |
| `no form, key 0x984` | 22 | 1 to 4, most often 1 | 19 | 0 | 9 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x20c` | 20 | 1 to 13, most often 13 | 0 | 0 | 1 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.LT.U32.AND.EX` | 19 | 1 to 4, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 19 | 0 of 19 |
| `PMTRIG` | 19 | 2 to 3, most often 3 | 0 | 0 | 0 | - | 0 of 0 | 0 of 19 | 0 of 19 |
| `BAR.SYNC.DEFER_BLOCKING` | 17 | 1 to 6, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 17 | 0 of 17 |
| `IMAD.WIDE` | 15 | 1 to 5, most often 1 | 0 | 0 | 0 | 5 over 15 | 0 of 0 | 0 of 15 | 0 of 15 |
| `P2R` | 15 | 1 to 3, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 15 | 0 of 15 |
| `STG.E.U16` | 15 | 1 to 8, most often 4 | 0 | 15 | 15 | - | 0 of 0 | 0 of 15 | 0 of 15 |
| `no form, key 0xa19` | 15 | 1 to 5, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x3c4` | 14 | 1 to 8, most often 1 | 14 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0xb12` | 13 | 8 to 8, most often 8 | 13 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x28c` | 12 | 1 to 6, most often 1 | 0 | 0 | 1 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0xc11` | 12 | 1 to 7, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `I2F.U64.RP` | 11 | 8 to 8, most often 8 | 11 | 0 | 0 | - | 11 of 11 | 11 of 11 | 0 of 11 |
| `IMAD.WIDE.U32.X` | 11 | 1 to 5, most often 4 | 0 | 0 | 0 | 5 over 11 | 0 of 0 | 0 of 11 | 0 of 11 |
| `ST.E` | 11 | 1 to 4, most often 4 | 0 | 11 | 0 | - | 0 of 0 | 0 of 11 | 0 of 11 |
| `UIADD3.X` | 11 | 1 to 2, most often 2 | 0 | 0 | 1 | - | 0 of 0 | 0 of 11 | 0 of 11 |
| `WARPSYNC` | 11 | 1 to 3, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 11 | 0 of 11 |
| `no form, key 0x287` | 11 | 1 to 6, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x619` | 11 | 1 to 4, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x892` | 11 | 1 to 6, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.NE.OR` | 10 | 9 to 13, most often 13 | 0 | 0 | 1 | - | 0 of 0 | 0 of 10 | 0 of 10 |
| `ATOMG.E.ADD.64.STRONG.GPU` | 9 | 1 to 4, most often 1 | 9 | 0 | 4 | - | 2 of 2 | 9 of 9 | 0 of 9 |
| `ISETP.EQ.OR` | 9 | 11 to 13, most often 13 | 0 | 0 | 2 | - | 0 of 0 | 0 of 9 | 0 of 9 |
| `no form, key 0xa07` | 9 | 1 to 4, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.GE.AND` | 8 | 1 to 13, most often 1 | 0 | 0 | 1 | - | 0 of 0 | 0 of 8 | 0 of 8 |
| `RED.E.MAX.STRONG.GPU` | 8 | 1 to 4, most often 1 | 0 | 3 | 0 | - | 0 of 0 | 0 of 8 | 0 of 8 |
| `RED.E.MIN.STRONG.GPU` | 8 | 1 to 7, most often 1 | 0 | 3 | 0 | - | 0 of 0 | 0 of 8 | 0 of 8 |
| `no form, key 0x388` | 8 | 2 to 2, most often 2 | 0 | 8 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x81c` | 8 | 1 to 13, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `RED.E.OR.STRONG.GPU` | 7 | 1 to 2, most often 2 | 0 | 5 | 0 | - | 0 of 0 | 0 of 7 | 0 of 7 |
| `no form, key 0x217` | 7 | 1 to 4, most often 1 | 0 | 0 | 3 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x810` | 7 | 2 to 4, most often 2 | 0 | 0 | 1 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x88c` | 7 | 1 to 6, most often 4 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `RED.E.ADD.STRONG.GPU` | 6 | 1 to 7, most often 1 | 0 | 4 | 4 | - | 0 of 0 | 0 of 6 | 0 of 6 |
| `no form, key 0x299` | 6 | 1 to 6, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x942` | 6 | 1 to 1, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x988` | 6 | 1 to 2, most often 1 | 0 | 6 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0xd09` | 6 | 1 to 5, most often 1 | 6 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.NE.U32.AND.EX` | 5 | 1 to 2, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 5 | 0 of 5 |
| `no form, key 0xc19` | 5 | 3 to 4, most often 4 | 0 | 0 | 5 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0xf89` | 5 | 1 to 2, most often 2 | 5 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.LT.AND.EX` | 4 | 2 to 2, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 4 | 0 of 4 |
| `no form, key 0x291` | 4 | 1 to 4, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x2bf` | 4 | 1 to 2, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x8a5` | 4 | 1 to 2, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0xd12` | 4 | 8 to 8, most often 8 | 4 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ISETP.EQ.AND` | 3 | 2 to 2, most often 2 | 0 | 0 | 1 | - | 0 of 0 | 0 of 3 | 0 of 3 |
| `ISETP.GE.AND.EX` | 3 | 1 to 13, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 3 | 0 of 3 |
| `ISETP.GT.U32.OR` | 3 | 2 to 13, most often 13 | 0 | 0 | 3 | - | 0 of 0 | 0 of 3 | 0 of 3 |
| `ISETP.LT.U32.OR` | 3 | 1 to 13, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 3 | 0 of 3 |
| `no form, key 0x292` | 3 | 2 to 2, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x3c2` | 3 | 1 to 1, most often 1 | 3 | 2 | 1 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x624` | 3 | 1 to 6, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x887` | 3 | 2 to 6, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x8a4` | 3 | 1 to 2, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x949` | 3 | 5 to 5, most often 5 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0xf8c` | 3 | 2 to 2, most often 2 | 0 | 3 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `BPT.TRAP` | 2 | 5 to 5, most often 5 | 0 | 0 | 1 | - | 0 of 0 | 0 of 2 | 0 of 2 |
| `ISETP.EQ.AND.EX` | 2 | 4 to 13, most often 4 | 0 | 0 | 2 | - | 0 of 0 | 0 of 2 | 0 of 2 |
| `LDS.128` | 2 | 1 to 4, most often 1 | 2 | 0 | 0 | - | 2 of 2 | 0 of 2 | 0 of 2 |
| `no form, key 0x811` | 2 | 5 to 5, most often 5 | 0 | 0 | 2 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x89c` | 2 | 1 to 2, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `ATOMG.E.EXCH.STRONG.GPU` | 1 | 1 to 1, most often 1 | 0 | 0 | 0 | - | 0 of 0 | 1 of 1 | 0 of 1 |
| `ISETP.GE.U32.OR` | 1 | 13 to 13, most often 13 | 0 | 0 | 0 | - | 0 of 0 | 0 of 1 | 0 of 1 |
| `ISETP.GT.OR.EX` | 1 | 13 to 13, most often 13 | 0 | 0 | 0 | - | 0 of 0 | 0 of 1 | 0 of 1 |
| `ISETP.LE.U32.AND.EX` | 1 | 2 to 2, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 1 | 0 of 1 |
| `ISETP.LE.U32.OR` | 1 | 13 to 13, most often 13 | 0 | 0 | 0 | - | 0 of 0 | 0 of 1 | 0 of 1 |
| `ISETP.LT.AND` | 1 | 13 to 13, most often 13 | 0 | 0 | 0 | - | 0 of 0 | 0 of 1 | 0 of 1 |
| `S2UR` | 1 | 1 to 1, most often 1 | 1 | 0 | 0 | - | 0 of 0 | 1 of 1 | 0 of 1 |
| `SHF.L.W.U32` | 1 | 5 to 5, most often 5 | 0 | 0 | 1 | 5 over 1 | 0 of 0 | 0 of 1 | 0 of 1 |
| `SHF.R.W.S32.HI` | 1 | 5 to 5, most often 5 | 0 | 0 | 1 | 5 over 1 | 0 of 0 | 0 of 1 | 0 of 1 |
| `ULDC.U8` | 1 | 2 to 2, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 1 | 0 of 1 |
| `no form, key 0x896` | 1 | 6 to 6, most often 6 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0x958` | 1 | 5 to 5, most often 5 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
| `no form, key 0xc17` | 1 | 2 to 2, most often 2 | 0 | 0 | 0 | - | 0 of 0 | 0 of 0 | 0 of 0 |
