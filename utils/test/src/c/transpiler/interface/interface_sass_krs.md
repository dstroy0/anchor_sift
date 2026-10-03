# A ruleset's forms held to the part's writings

Written by `interface_sass_writings.sh` whole on every run. Each word of the word web that is one precept over its operands is looked up in `src/cu/transpiler/codegen/rulesets/sass.krs`, its form written with its result and operands where the search puts them, and looked for among the forms `interface_sass_writings.md` ran on the part.

| word | precept | form as run | on the part |
|---|---|---|---|
| `word_and` | and | `LOP3.LUT R8, R10, R12, RZ, 0xc0, !PT` | gives every case its word |
| `word_or` | or | `LOP3.LUT R8, R10, R12, RZ, 0xfc, !PT` | gives every case its word |
| `word_xor` | xor | `LOP3.LUT R8, R10, R12, RZ, 0x3c, !PT` | gives every case its word |
| `word_copy` | mov | `MOV R8, R10` | gives every case its word |
| `word_shift_left` | shl | `SHF.L.U32 R8, R10, R12, RZ` | does not give every case its word |
| `word_shift_right` | shr | `SHF.R.U32.HI R8, RZ, R12, R10` | does not give every case its word |
| `add_alone` | add | `IADD3 R8, R10, R12, RZ` | gives every case its word |
| `subtract_alone` | sub | `IADD3 R8, R10, -R12, RZ` | gives every case its word |
| `predicate_xor` | xor | no form | - |
| `predicate_and` | and | no form | - |
