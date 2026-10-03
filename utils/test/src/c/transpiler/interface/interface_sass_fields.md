# Every used form's fields, found on the part

Written by `interface_sass_fields.sh` whole on every run. Each form a ruleset uses has every operation bit
turned over one at a time and run on the part through `interface_sass_run`, and each bit labeled against the
runs the machine file records. A read bit outside every recorded run is a bit the part reads that the
machine file gives no operand: a modifier of the operation, or an operand it does not print.

| form | refused | inside a run | outside every run | unread | bits outside |
|---|---|---|---|---|---|
| `MOV R238, R4` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `MOV R239, R5` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `MOV R240, R6` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `MOV R241, R7` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `LDG.E.64.CONSTANT R1, [R238.64+R2]` | 29 | 26 | 8 | 42 | 12 13 14 15 64 65 66 67 |
| `@R1 LDG.E.CONSTANT R2, [R3.64]` | 26 | 28 | 8 | 43 | 12 13 14 15 64 65 66 67 |
| `@R2 MOV R4, R6` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `@R2 MOV R4.hi, RZ` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `MOV R254, 1` | 10 | 40 | 9 | 46 | 0 4 7 8 12 13 14 15 72 |
| `RED.E.ADD.STRONG.GPU [R1.64], R254` | 105 | 0 | 0 | 0 |  |
| `RET.ABS.NODEC R20 0x0` | 105 | 0 | 0 | 0 |  |
| `IADD3 R1, R2, R3, RZ` | 11 | 36 | 7 | 51 | 0 1 2 12 13 14 15 |
| `IADD3 R1, P6, R2, R3, RZ` | 11 | 36 | 7 | 51 | 0 1 2 12 13 14 15 |
| `IADD3.X R1, P6, R2, R3, RZ, P6, !PT` | 11 | 44 | 7 | 43 | 0 1 2 12 13 14 15 |
| `IADD3.X R1, R2, R3, RZ, P6, !PT` | 11 | 44 | 7 | 43 | 0 1 2 12 13 14 15 |
| `IADD3 R1, R2, -R3, RZ` | 11 | 35 | 7 | 52 | 0 1 12 13 14 15 74 |
| `IADD3 R1, P6, R2, -R3, RZ` | 11 | 35 | 7 | 52 | 0 1 12 13 14 15 74 |
| `IADD3.X R1, P6, R2, ~R3, RZ, P6, !PT` | 11 | 43 | 8 | 43 | 0 1 2 12 13 14 15 74 |
| `IADD3.X R1, R2, ~R3, RZ, P6, !PT` | 11 | 43 | 8 | 43 | 0 1 2 12 13 14 15 74 |
| `IMAD.X R1, RZ, RZ, -0x1, P6` | 14 | 58 | 4 | 29 | 12 13 14 15 |
| `ISETP.NE.U32.AND P1, PT, R1, RZ, PT` | 12 | 7 | 8 | 78 | 2 5 12 13 14 15 75 78 |
| `MOV R1, R2` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `LOP3.LUT R1, R2, R3, RZ, 0xc0, !PT` | 9 | 26 | 10 | 60 | 0 1 2 3 4 11 12 13 14 15 |
| `LOP3.LUT R1, R2, R3, RZ, 0xfc, !PT` | 8 | 28 | 10 | 59 | 0 2 3 4 8 11 12 13 14 15 |
| `LOP3.LUT R1, R2, R3, RZ, 0x3c, !PT` | 7 | 26 | 12 | 60 | 0 1 2 3 4 5 8 11 12 13 14 15 |
| `SHF.L.U32 R1, R2, R3, RZ` | 10 | 24 | 11 | 60 | 1 4 5 10 11 12 13 14 15 76 80 |
| `SHF.R.U32.HI R1, RZ, R3, R2` | 9 | 6 | 6 | 84 | 1 3 5 10 76 80 |
| `SHF.R.U32 R1, R2, R4, R3` | 10 | 26 | 10 | 59 | 1 4 5 10 12 13 14 15 76 80 |
| `IMAD R1, R2, R3, RZ` | 9 | 33 | 8 | 55 | 3 4 10 11 12 13 14 15 |
| `IMAD R1, R2, R3, R4` | 9 | 33 | 8 | 55 | 3 4 10 11 12 13 14 15 |
| `SEL R1, R2, R3, P0` | 12 | 20 | 6 | 67 | 4 5 12 13 14 15 |
| `IADD3 R1, P6, R1, R4, RZ` | 11 | 36 | 7 | 51 | 0 1 2 12 13 14 15 |
| `IMAD.HI.U32 R1, R2, R3, RZ` | 9 | 1 | 5 | 90 | 0 1 2 5 10 |
| `IMAD.X R1, RZ, RZ, R1, P6` | 10 | 38 | 6 | 51 | 3 10 12 13 14 15 |
| `MOV R254, R2` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `SEL R1, R254, R3, P0` | 12 | 21 | 6 | 66 | 4 5 12 13 14 15 |
| `IABS R1, R2` | 8 | 17 | 9 | 71 | 0 1 3 5 8 12 13 14 15 |
| `IADD3 R1, -R2, RZ, RZ` | 11 | 35 | 8 | 51 | 0 1 2 12 13 14 15 74 |
| `ISETP.NE.U32.AND P0, PT, R2, RZ, PT` | 12 | 7 | 8 | 78 | 2 5 12 13 14 15 75 78 |
| `ISETP.EQ.U32.AND P0, PT, R2, RZ, PT` | 12 | 0 | 3 | 90 | 74 75 78 |
| `ISETP.LT.AND P0, PT, R2, RZ, PT` | 12 | 9 | 3 | 81 | 74 75 78 |
| `ISETP.NE.AND P0, PT, R2, R3, PT` | 12 | 7 | 8 | 78 | 2 5 12 13 14 15 75 78 |
| `ISETP.GT.AND P0, PT, R2, R3, PT` | 12 | 15 | 8 | 70 | 2 5 11 12 13 14 15 75 |
| `ISETP.NE.U32.AND P6, PT, R4, RZ, PT` | 12 | 7 | 8 | 78 | 2 5 12 13 14 15 75 78 |
| `ISETP.NE.U32.AND.EX P0, PT, R4.hi, RZ, PT, P6` | 12 | 7 | 8 | 78 | 2 5 12 13 14 15 75 78 |
| `ISETP.EQ.U32.AND P6, PT, R4, R6, PT` | 12 | 0 | 3 | 90 | 74 75 78 |
| `ISETP.EQ.U32.AND.EX P0, PT, R4.hi, R6.hi, PT, P6` | 12 | 0 | 3 | 90 | 74 75 78 |
| `ISETP.LT.U32.AND P6, PT, R4, R6, PT` | 12 | 9 | 2 | 82 | 74 75 |
| `ISETP.LT.U32.AND.EX P0, PT, R4.hi, R6.hi, PT, P6` | 12 | 9 | 3 | 81 | 74 75 78 |
| `ISETP.LT.U32.AND.EX P0, PT, R4.hi, R6.hi, P0, P6` | 12 | 0 | 0 | 93 |  |
| `SEL R103, RZ, 1, P1` | 9 | 20 | 9 | 67 | 0 1 2 4 5 12 13 14 15 |
| `SEL R104, RZ, 1, P2` | 9 | 20 | 9 | 67 | 0 1 2 4 5 12 13 14 15 |
| `LOP3.LUT R103, R103, R104, RZ, 0x3c, !PT` | 7 | 26 | 12 | 60 | 0 1 2 3 4 5 8 11 12 13 14 15 |
| `ISETP.NE.U32.AND P0, PT, R103, RZ, PT` | 12 | 6 | 8 | 79 | 2 5 12 13 14 15 75 78 |
| `MOV R104, 1` | 10 | 40 | 9 | 46 | 0 4 7 8 12 13 14 15 72 |
| `SEL R105, R104, 0, P1` | 9 | 20 | 8 | 68 | 0 1 4 5 12 13 14 15 |
| `SEL R106, R104, 0, P2` | 9 | 20 | 8 | 68 | 0 1 4 5 12 13 14 15 |
| `LOP3.LUT R105, R105, R106, RZ, 0xc0, !PT` | 9 | 26 | 10 | 60 | 0 1 2 3 4 11 12 13 14 15 |
| `ISETP.NE.U32.AND P0, PT, R105, RZ, PT` | 12 | 7 | 8 | 78 | 2 5 12 13 14 15 75 78 |
| `MOV R2, R4` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `MOV R2.hi, RZ` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `MOV R2.hi, R6` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `MOV R2, R6` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `MOV R4, R6.hi` | 12 | 17 | 7 | 69 | 4 8 12 13 14 15 72 |
| `IMAD.WIDE.U32 R2, R4, R6, RZ` | 10 | 32 | 8 | 55 | 1 2 4 10 12 13 14 15 |
| `IMAD R2.hi, R4.hi, R6, R2.hi` | 9 | 33 | 8 | 55 | 3 4 10 11 12 13 14 15 |
| `IMAD R2.hi, R4, R6.hi, R2.hi` | 9 | 33 | 8 | 55 | 3 4 10 11 12 13 14 15 |
| `IADD3 R2, P6, R4, R6, RZ` | 11 | 36 | 7 | 51 | 0 1 2 12 13 14 15 |
| `IADD3.X R2.hi, R4.hi, R6.hi, RZ, P6, !PT` | 11 | 44 | 7 | 43 | 0 1 2 12 13 14 15 |
| `SHF.L.U64.HI R2.hi, R4, R6, R4.hi` | 9 | 26 | 11 | 59 | 1 3 4 5 10 12 13 14 15 76 80 |
| `SHF.L.U32 R2, R4, R6, RZ` | 10 | 24 | 11 | 60 | 1 4 5 10 11 12 13 14 15 76 80 |
| `SEL R2, R4, R6, P0` | 12 | 21 | 6 | 66 | 4 5 12 13 14 15 |
| `SEL R2.hi, R4.hi, R6.hi, P0` | 12 | 21 | 6 | 66 | 4 5 12 13 14 15 |
| `LDG.E.CONSTANT R1, [R2.64+R3]` | 26 | 28 | 8 | 43 | 12 13 14 15 64 65 66 67 |
| `STG.E [R242.64+R1], R2` | 96 | 0 | 0 | 9 |  |
