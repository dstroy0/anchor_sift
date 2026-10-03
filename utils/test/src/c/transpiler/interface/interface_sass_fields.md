# Every used form's fields, found on the part

Written by `interface_sass_fields.sh` whole on every run. Each form a ruleset uses has every operation bit
turned over one at a time and run on the part through `interface_sass_run`, and each bit labeled against the
runs the machine file records. A read bit outside every recorded run is a bit the part reads that the
machine file gives no operand: a modifier of the operation, or an operand it does not print.

| form | refused | inside a run | outside every run | unread | bits outside |
|---|---|---|---|---|---|
| `MOV R238, R4` | 8 | 16 | 8 | 73 | 0 4 6 8 12 13 14 15 |
| `MOV R239, R5` | 8 | 16 | 8 | 73 | 0 4 6 8 12 13 14 15 |
| `MOV R240, R6` | 8 | 16 | 8 | 73 | 0 4 6 8 12 13 14 15 |
| `MOV R241, R7` | 8 | 16 | 8 | 73 | 0 4 6 8 12 13 14 15 |
| `LDG.E.64.CONSTANT R1, [R238.64+R2]` | 92 | 0 | 0 | 13 |  |
| `@R1 LDG.E.CONSTANT R2, [R3.64]` | 103 | 0 | 0 | 2 |  |
| `@R2 MOV R4, R6` | 8 | 4 | 15 | 78 | 15 27 31 43 47 51 55 59 63 67 71 75 79 83 87 |
| `@R2 MOV R4.hi, RZ` | 8 | 0 | 0 | 97 |  |
| `MOV R254, 1` | 7 | 41 | 9 | 48 | 0 4 5 7 8 12 13 14 15 |
| `RED.E.ADD.STRONG.GPU [R1.64], R254` | 105 | 0 | 0 | 0 |  |
| `RET.ABS.NODEC R20 0x0` | 95 | 0 | 0 | 10 |  |
| `IADD3 R1, R2, R3, RZ` | 9 | 36 | 7 | 53 | 0 1 2 12 13 14 15 |
| `IADD3 R1, P6, R2, R3, RZ` | 9 | 36 | 7 | 53 | 0 1 2 12 13 14 15 |
| `IADD3.X R1, P6, R2, R3, RZ, P6, !PT` | 9 | 42 | 7 | 47 | 0 1 2 12 13 14 15 |
| `IADD3.X R1, R2, R3, RZ, P6, !PT` | 9 | 42 | 7 | 47 | 0 1 2 12 13 14 15 |
| `IADD3 R1, R2, -R3, RZ` | 10 | 35 | 7 | 53 | 0 1 12 13 14 15 74 |
| `IADD3 R1, P6, R2, -R3, RZ` | 10 | 35 | 7 | 53 | 0 1 12 13 14 15 74 |
| `IADD3.X R1, P6, R2, ~R3, RZ, P6, !PT` | 10 | 43 | 43 | 9 | 0 1 2 12 13 14 15 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 74 84 85 86 96 97 98 99 100 101 102 103 104 |
| `IADD3.X R1, R2, ~R3, RZ, P6, !PT` | 10 | 41 | 9 | 45 | 0 1 2 12 13 14 15 74 85 |
| `IMAD.X R1, RZ, RZ, -0x1, P6` | 12 | 58 | 4 | 31 | 12 13 14 15 |
| `ISETP.NE.U32.AND P1, PT, R1, RZ, PT` | 12 | 0 | 0 | 93 |  |
| `MOV R1, R2` | 8 | 16 | 8 | 73 | 0 4 6 8 12 13 14 15 |
| `LOP3.LUT R1, R2, R3, RZ, 0xc0, !PT` | 7 | 26 | 10 | 62 | 0 1 2 3 4 11 12 13 14 15 |
| `LOP3.LUT R1, R2, R3, RZ, 0xfc, !PT` | 6 | 27 | 10 | 62 | 0 2 3 4 8 11 12 13 14 15 |
| `LOP3.LUT R1, R2, R3, RZ, 0x3c, !PT` | 5 | 27 | 12 | 61 | 0 1 2 3 4 5 8 11 12 13 14 15 |
| `SHF.L.U32 R1, R2, R3, RZ` | 7 | 24 | 12 | 62 | 1 2 4 5 10 11 12 13 14 15 76 80 |
| `SHF.R.U32.HI R1, RZ, R3, R2` | 6 | 8 | 7 | 84 | 1 3 5 10 14 76 80 |
| `SHF.R.U32 R1, R2, R4, R3` | 7 | 26 | 11 | 61 | 1 2 4 5 10 12 13 14 15 76 80 |
| `IMAD R1, R2, R3, RZ` | 6 | 33 | 9 | 57 | 3 4 5 10 11 12 13 14 15 |
| `IMAD R1, R2, R3, R4` | 6 | 33 | 9 | 57 | 3 4 5 10 11 12 13 14 15 |
| `MOV R254, R2` | 8 | 16 | 8 | 73 | 0 4 6 8 12 13 14 15 |
| `SEL R1, R254, R3, P0` | 9 | 17 | 7 | 72 | 2 4 5 12 13 14 15 |
| `IADD3 R1, P6, R1, R4, RZ` | 9 | 36 | 7 | 53 | 0 1 2 12 13 14 15 |
| `IMAD.HI.U32 R1, R2, R3, RZ` | 8 | 3 | 6 | 88 | 0 1 2 5 10 14 |
| `IMAD.X R1, RZ, RZ, R1, P6` | 7 | 36 | 7 | 55 | 3 5 10 12 13 14 15 |
| `IABS R1, R2` | 5 | 16 | 10 | 74 | 0 1 3 4 5 8 12 13 14 15 |
| `IADD3 R1, -R2, RZ, RZ` | 10 | 35 | 8 | 52 | 0 1 2 12 13 14 15 74 |
| `ISETP.NE.U32.AND P0, PT, R2, RZ, PT` | 11 | 0 | 0 | 94 |  |
| `ISETP.EQ.U32.AND P0, PT, R2, RZ, PT` | 11 | 0 | 0 | 94 |  |
| `ISETP.LT.AND P0, PT, R2, RZ, PT` | 11 | 0 | 0 | 94 |  |
| `ISETP.NE.AND P0, PT, R2, R3, PT` | 10 | 0 | 0 | 95 |  |
| `ISETP.GT.AND P0, PT, R2, R3, PT` | 10 | 0 | 0 | 95 |  |
| `ISETP.NE.U32.AND P6, PT, R4, RZ, PT` | 11 | 0 | 0 | 94 |  |
| `ISETP.NE.U32.AND.EX P0, PT, R4.hi, RZ, PT, P6` | 12 | 0 | 0 | 93 |  |
| `ISETP.EQ.U32.AND P6, PT, R4, R6, PT` | 9 | 0 | 0 | 96 |  |
| `ISETP.EQ.U32.AND.EX P0, PT, R4.hi, R6.hi, PT, P6` | 10 | 0 | 0 | 95 |  |
| `ISETP.LT.U32.AND P6, PT, R4, R6, PT` | 9 | 0 | 0 | 96 |  |
| `ISETP.LT.U32.AND.EX P0, PT, R4.hi, R6.hi, PT, P6` | 10 | 0 | 0 | 95 |  |
| `ISETP.LT.U32.AND.EX P0, PT, R4.hi, R6.hi, P0, P6` | 9 | 0 | 0 | 96 |  |
| `MOV R254, RZ` | 8 | 16 | 8 | 73 | 0 4 6 8 12 13 14 15 |
| `SEL R103, R254, 1, P1` | 7 | 42 | 9 | 47 | 0 1 2 4 5 12 13 14 15 |
| `SEL R104, R254, 1, P2` | 7 | 42 | 9 | 47 | 0 1 2 4 5 12 13 14 15 |
| `LOP3.LUT R103, R103, R104, RZ, 0x3c, !PT` | 5 | 27 | 12 | 61 | 0 1 2 3 4 5 8 11 12 13 14 15 |
| `ISETP.NE.U32.AND P0, PT, R103, RZ, PT` | 12 | 0 | 0 | 93 |  |
| `MOV R104, 1` | 7 | 41 | 9 | 48 | 0 4 5 7 8 12 13 14 15 |
| `MOV R254, R104` | 8 | 16 | 8 | 73 | 0 4 6 8 12 13 14 15 |
| `SEL R105, R254, 0, P1` | 7 | 34 | 3 | 61 | 2 4 5 |
| `SEL R106, R254, 0, P2` | 7 | 34 | 3 | 61 | 2 4 5 |
| `LOP3.LUT R105, R105, R106, RZ, 0xc0, !PT` | 7 | 26 | 10 | 62 | 0 1 2 3 4 11 12 13 14 15 |
| `ISETP.NE.U32.AND P0, PT, R105, RZ, PT` | 12 | 0 | 0 | 93 |  |
| `MOV R2, R4` | 8 | 16 | 8 | 73 | 0 4 6 8 12 13 14 15 |
| `MOV R2.hi, RZ` | 8 | 4 | 15 | 78 | 24 28 40 44 48 52 56 60 64 68 72 76 80 84 88 |
| `MOV R2.hi, R6` | 8 | 4 | 15 | 78 | 24 28 40 44 48 52 56 60 64 68 72 76 80 84 88 |
| `MOV R2, R6` | 8 | 16 | 8 | 73 | 0 4 6 8 12 13 14 15 |
| `MOV R4, R6.hi` | 8 | 5 | 4 | 88 | 0 4 6 15 |
| `IMAD.WIDE.U32 R2, R4, R6, RZ` | 9 | 32 | 8 | 56 | 1 2 4 10 12 13 14 15 |
| `IMAD R2.hi, R4.hi, R6, R2.hi` | 8 | 0 | 0 | 97 |  |
| `IMAD R2.hi, R4, R6.hi, R2.hi` | 8 | 0 | 0 | 97 |  |
| `IADD3 R2, P6, R4, R6, RZ` | 9 | 36 | 7 | 53 | 0 1 2 12 13 14 15 |
| `IADD3.X R2.hi, R4.hi, R6.hi, RZ, P6, !PT` | 9 | 1 | 0 | 95 |  |
| `SHF.L.U64.HI R2.hi, R4, R6, R4.hi` | 5 | 0 | 0 | 100 |  |
| `SHF.L.U32 R2, R4, R6, RZ` | 7 | 24 | 12 | 62 | 1 2 4 5 10 11 12 13 14 15 76 80 |
| `MOV R254, R4` | 8 | 17 | 9 | 71 | 0 4 6 8 12 13 14 15 72 |
| `SEL R2, R254, R6, P0` | 9 | 18 | 7 | 71 | 2 4 5 12 13 14 15 |
| `MOV R254, R4.hi` | 8 | 3 | 3 | 91 | 0 4 6 |
| `SEL R2.hi, R254, R6.hi, P0` | 9 | 0 | 0 | 96 |  |
| `LDG.E.CONSTANT R1, [R2.64+R3]` | 26 | 28 | 8 | 43 | 12 13 14 15 64 65 66 67 |
| `STG.E [R242.64+R1], R2` | 96 | 0 | 0 | 9 |  |
