# The forms read off NVIDIA's compiler

Written by `monolith_forms.sh` whole on every run. Every form the lanes of the record programs decide is asked of NVIDIA's compiler once for each set of banks its arguments come from, in one program between tags (`monolith_forms.cpp`). A question in the form's text in `c.krs` is read off the PTX and held beside the form `ptx.krs` gives; one in its text in `ptx.krs`, put to `ptxas` as inline PTX, is read off the listing and held beside the form `sass.krs` gives. Each block is read back into the form it is, its registers named by the arguments they hold. A fixed register is named in angle brackets, and the ruleset names it. A form every question of which reads whole and alike is the ruleset's form, written into it by `monolith_forms.sh apply`; any other keeps the ruleset's text, and the reason stands beside it.

| tag | form | banks | read off | read | note |
|---|---|---|---|---|---|
| 1 | launch_load | f2 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 2 | launch_load | f2 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 3 | wide_multiply | r5 f1 r8 | PTX | `mul.lo.s64 {to}, {left}, {right};` |  |
| 4 | wide_multiply | r5 f1 r8 | PTX | `mul.lo.s64 {to}, {left}, {right};` |  |
| 5 | wide_add | f2 f2 r5 | PTX | `add.s64 {to}, {right}, {left};` |  |
| 6 | launch_load | f3 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 7 | launch_load | f3 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 8 | test_wide_nonzero | f9 f3 | PTX | `setp.ne.s64 {where}, {value}, 0;` |  |
| 9 | launch_load | f5 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 10 | launch_load | f5 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 11 | test_wide_equal | f10 f5 n | PTX | `setp.eq.s64 {where}, {left}, {right};` |  |
| 12 | test_wide_equal | f10 f5 n | PTX | `setp.eq.s64 {where}, {left}, {right};` |  |
| 13 | wide_select | f4 n f1 f10 | PTX | `setp.eq.s32 %p4, {where}, 0; \| selp.b64 {to}, {otherwise}, 0, %p4;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 14 | wide_select | f4 n f1 f10 | PTX | `setp.eq.s32 %p5, {where}, 0; \| selp.b64 {to}, {otherwise}, {chosen}, %p5;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 15 | wide_add_unsigned | r5 r5 r8 | PTX | `` | the compiler writes no instruction for it |
| 16 | wide_add_unsigned | r5 r5 r8 | PTX | `add.s64 {to}, {left}, {right};` |  |
| 17 | wide_shift_left | r5 r5 n | PTX | `shl.b64 {to}, {from}, {bits};` |  |
| 18 | wide_shift_left | r5 r5 n | PTX | `shl.b64 {to}, {from}, {bits};` |  |
| 19 | wide_add | r5 f3 r5 | PTX | `add.s64 {to}, {right}, {left};` |  |
| 20 | guarded_load | f9 r4 r5 | PTX | `setp.eq.s32 %p6, {where}, 0; \| @%p6 bra $L__BB0_2; \| ld.u32 {to}, [{address}];` | the reading holds a branch |
| 21 | guarded_widen | f9 f4 r4 | PTX | `setp.eq.s32 %p7, {where}, 0; \| mov.u32 %r443, 0; \| selp.b64 {to}, {to}, {from}, %p7;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 22 | test_wide_below | f11 f4 f5 | PTX | `setp.lt.u64 {where}, {left}, {right};` |  |
| 23 | wide_select | f4 f4 n f11 | PTX | `setp.eq.s32 %p9, {where}, 0; \| selp.b64 {to}, 0, {chosen}, %p9;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 24 | wide_select | f4 f4 n f11 | PTX | `setp.eq.s32 %p10, {where}, 0; \| selp.b64 {to}, {otherwise}, {chosen}, %p10;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 25 | launch_load | r7 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 26 | launch_load | r7 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 27 | wide_multiply | r5 f4 r8 | PTX | `shl.b64 {to}, {left}, 5;` | the reading does not name right |
| 28 | wide_multiply | r5 f4 r8 | PTX | `mul.lo.s64 {to}, {left}, {right};` |  |
| 29 | wide_add | r7 r7 r5 | PTX | `add.s64 {to}, {right}, {left};` |  |
| 30 | word_multiply_add | f8 f7 r8 f8 | PTX | `mad.lo.s32 {to}, {left}, {right}, {added};` |  |
| 31 | word_multiply_add | f8 f7 r8 f8 | PTX | `mad.lo.s32 {to}, {left}, {right}, {added};` |  |
| 32 | global_load | r3 r7 n | PTX | `ld.u32 {to}, [{address}+{offset}];` | the question names no address space |
| 33 | global_load | r3 r7 n | PTX | `ld.u32 {to}, [{address}+{offset}];` | the question names no address space |
| 34 | word_copy | r0 r3 | PTX | `` | the compiler writes no instruction for it |
| 35 | word_and | r4 r0 r8 | PTX | `and.b32 {to}, {left}, -{right};` |  |
| 36 | word_and | r4 r0 r8 | PTX | `and.b32 {to}, {left}, {right};` |  |
| 37 | test_nonzero | r6 r4 | PTX | `setp.ne.s32 {where}, {value}, 0;` |  |
| 38 | word_select | r0 r4 r0 r6 | PTX | `setp.eq.s32 %p12, {where}, 0; \| selp.b32 {to}, {otherwise}, {chosen}, %p12;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 39 | sign_select | r4 n n r6 | PTX | `mov.u32 {to}, {chosen};` | the reading does not name otherwise |
| 40 | sign_select | r4 n n r6 | PTX | `mov.u32 {to}, {chosen};` | the reading does not name otherwise |
| 41 | word_or | r4 r0 r0 | PTX | `or.b32 {to}, {right}, {left};` |  |
| 42 | word_or | r4 r4 r0 | PTX | `or.b32 {to}, {right}, {left};` |  |
| 43 | sign_select | r1 r4 n r6 | PTX | `setp.eq.s32 %p13, {where}, 0; \| cvt.s32.s8 %r478, {chosen}; \| selp.b32 {to}, 0, %r478, %p13;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 44 | sign_select | r1 r4 n r6 | PTX | `setp.eq.s32 %p14, {where}, 0; \| cvt.s32.s8 %r482, {chosen}; \| selp.b32 {to}, 4, %r482, %p14; \| mov.u32 %r484, 4;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 45 | sign_select | r1 n n r6 | PTX | `selp.u32 {to}, {chosen}, {otherwise}, {where};` |  |
| 46 | sign_select | r1 n n r6 | PTX | `setp.eq.s32 %p16, {where}, 0; \| selp.b32 {to}, {otherwise}, 2, %p16; \| mov.u32 %r489, 2;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 47 | test_nonzero | r6 r0 | PTX | `setp.ne.s32 {where}, {value}, 0;` |  |
| 48 | word_set | r0 n | PTX | `` | the compiler writes no instruction for it |
| 49 | word_set | r0 n | PTX | `` | the compiler writes no instruction for it |
| 50 | subtract_first | r4 f0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd150, {to}, 32; \| cvt.u32.u64 %r492, %rd150; \| and.b32 <carry>, %r492, 1; \| mov.u32 %r494, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 51 | subtract_middle | r4 f0 r0 | PTX | `sub.s64 %rd154, {left}, {right}; \| sub.s64 {to}, %rd154, <carry>; \| shr.u64 %rd156, {to}, 32; \| cvt.u32.u64 %r495, %rd156; \| and.b32 <carry>, %r495, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 52 | subtract_last | r4 f0 r0 | PTX | `sub.s32 %r500, {left}, {right}; \| sub.s32 {to}, %r500, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 53 | product_low | r0 r0 r0 r0 | PTX | `mul.lo.s32 %r504, {right}, {left}; \| cvt.u64.u32 %rd158, %r504; \| add.s64 {to}, %rd158, {added}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 54 | product_high | r4 r0 r0 | PTX | `mul.wide.u32 %rd161, {right}, {left}; \| shr.u64 %rd162, %rd161, 32; \| cvt.u32.u64 %r508, %rd162; \| add.s32 {to}, <carry>, %r508;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 55 | add_first | r0 r0 r4 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 56 | add_last | r4 r4 f0 | PTX | `add.s32 %r513, {right}, {left}; \| add.s32 {to}, %r513, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 57 | add_first | r0 r0 r4 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 58 | add_middle | r0 r0 f0 | PTX | `add.s64 %rd174, {right}, {left}; \| add.s64 {to}, %rd174, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 59 | add_last | r0 r0 f0 | PTX | `add.s32 %r518, {right}, {left}; \| add.s32 {to}, %r518, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 60 | add_first | r0 r0 r4 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 61 | add_last | r0 r0 f0 | PTX | `add.s32 %r523, {right}, {left}; \| add.s32 {to}, %r523, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 62 | add_alone | r0 r0 r4 | PTX | `add.s32 {to}, {right}, {left};` |  |
| 63 | sign_multiply | r1 r1 r1 | PTX | `mul.lo.s32 %r530, {left}, {right}; \| cvt.s32.s8 {to}, %r530;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 64 | test_negative | r6 r1 | PTX | `and.b32 %r533, {value}, 128; \| shr.u32 {where}, %r533, 7;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 65 | word_select | r4 r4 r0 r6 | PTX | `setp.eq.s32 %p18, {where}, 0; \| selp.b32 {to}, {otherwise}, {chosen}, %p18;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 66 | word_select | r4 r4 f0 r6 | PTX | `setp.eq.s32 %p19, {where}, 0; \| selp.b32 {to}, {otherwise}, {chosen}, %p19;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 67 | word_and | r4 r4 r8 | PTX | `and.b32 {to}, {left}, {right};` |  |
| 68 | word_and | r4 r4 r8 | PTX | `and.b32 {to}, {left}, {right};` |  |
| 69 | word_set | r2 n | PTX | `` | the compiler writes no instruction for it |
| 70 | word_set | r2 n | PTX | `` | the compiler writes no instruction for it |
| 71 | word_or | r2 r2 r4 | PTX | `or.b32 {to}, {right}, {left};` |  |
| 72 | record_store | n r2 | PTX | `st.u32 [<record>+{offset}], {from};` | the question names no address space |
| 73 | record_store | n r2 | PTX | `st.u32 [<record>+{offset}], {from};` | the question names no address space |
| 74 | subtract_first | r4 f0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd186, {to}, 32; \| cvt.u32.u64 %r552, %rd186; \| and.b32 <carry>, %r552, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 75 | subtract_middle | r4 f0 r0 | PTX | `sub.s64 %rd190, {left}, {right}; \| sub.s64 {to}, %rd190, <carry>; \| shr.u64 %rd192, {to}, 32; \| cvt.u32.u64 %r554, %rd192; \| and.b32 <carry>, %r554, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 76 | subtract_last | r4 f0 f0 | PTX | `sub.s32 %r559, {left}, {right}; \| sub.s32 {to}, %r559, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 77 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 78 | add_middle | r0 r0 f0 | PTX | `add.s64 %rd200, {right}, {left}; \| add.s64 {to}, %rd200, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 79 | add_last | r0 f0 f0 | PTX | `add.s32 %r564, {right}, {left}; \| add.s32 {to}, %r564, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 80 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd206, {to}, 32; \| cvt.u32.u64 %r566, %rd206; \| and.b32 <carry>, %r566, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 81 | borrow_middle | r4 r0 f0 | PTX | `sub.s64 %rd210, {left}, {right}; \| sub.s64 {to}, %rd210, <carry>; \| shr.u64 %rd212, {to}, 32; \| cvt.u32.u64 %r568, %rd212; \| and.b32 <carry>, %r568, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 82 | borrow_last | r4 f0 f0 | PTX | `sub.s64 %rd216, {left}, {right}; \| sub.s64 {to}, %rd216, <carry>; \| shr.u64 %rd218, {to}, 32; \| cvt.u32.u64 %r570, %rd218; \| and.b32 <carry>, %r570, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 83 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 84 | sign_multiply | r4 r1 r1 | PTX | `mul.lo.s32 %r577, {left}, {right}; \| cvt.s32.s8 {to}, %r577;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 85 | test_negative | r6 r4 | PTX | `shr.u32 {where}, {value}, 31;` |  |
| 86 | word_select | r4 r4 r4 r6 | PTX | `setp.eq.s32 %p21, {where}, 0; \| selp.b32 {to}, {otherwise}, {chosen}, %p21;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 87 | sign_select | r4 r1 r1 r6 | PTX | `setp.eq.s32 %p22, {where}, 0; \| selp.b32 %r588, {otherwise}, {chosen}, %p22; \| cvt.s32.s8 {to}, %r588;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 88 | test_signed_differ | r6 r1 n | PTX | `and.b32 %r591, {left}, 255; \| setp.ne.s32 {where}, %r591, {right};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 89 | test_signed_differ | r6 r1 n | PTX | `and.b32 %r594, {left}, 255; \| setp.ne.s32 {where}, %r594, {right};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 90 | sign_select | r4 r4 r4 r6 | PTX | `setp.eq.s32 %p25, {where}, 0; \| selp.b32 %r599, {otherwise}, {chosen}, %p25; \| cvt.s32.s8 {to}, %r599;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 91 | subtract_first | r4 f0 r4 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd222, {to}, 32; \| cvt.u32.u64 %r601, %rd222; \| and.b32 <carry>, %r601, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 92 | subtract_middle | r4 f0 r4 | PTX | `sub.s64 %rd226, {left}, {right}; \| sub.s64 {to}, %rd226, <carry>; \| shr.u64 %rd228, {to}, 32; \| cvt.u32.u64 %r603, %rd228; \| and.b32 <carry>, %r603, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 93 | subtract_last | r4 f0 r4 | PTX | `sub.s32 %r608, {left}, {right}; \| sub.s32 {to}, %r608, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 94 | word_shift_left | r4 r4 n | PTX | `shl.b32 {to}, {from}, {bits};` |  |
| 95 | word_shift_left | r4 r4 n | PTX | `shl.b32 {to}, {from}, {bits};` |  |
| 96 | word_shift_right | r4 r4 n | PTX | `shr.u32 {to}, {from}, {bits};` |  |
| 97 | word_shift_right | r4 r4 n | PTX | `shr.u32 {to}, {from}, {bits};` |  |
| 98 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 99 | add_middle | r0 r0 r0 | PTX | `add.s64 %rd236, {right}, {left}; \| add.s64 {to}, %rd236, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 100 | add_middle | r0 f0 r0 | PTX | `add.s64 %rd242, {right}, {left}; \| add.s64 {to}, %rd242, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 101 | add_last | r0 f0 f0 | PTX | `add.s32 %r621, {right}, {left}; \| add.s32 {to}, %r621, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 102 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd248, {to}, 32; \| cvt.u32.u64 %r623, %rd248; \| and.b32 <carry>, %r623, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 103 | borrow_middle | r4 r0 r0 | PTX | `sub.s64 %rd252, {left}, {right}; \| sub.s64 {to}, %rd252, <carry>; \| shr.u64 %rd254, {to}, 32; \| cvt.u32.u64 %r625, %rd254; \| and.b32 <carry>, %r625, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 104 | borrow_middle | r4 f0 r0 | PTX | `sub.s64 %rd258, {left}, {right}; \| sub.s64 {to}, %rd258, <carry>; \| shr.u64 %rd260, {to}, 32; \| cvt.u32.u64 %r627, %rd260; \| and.b32 <carry>, %r627, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 105 | borrow_last | r4 f0 f0 | PTX | `sub.s64 %rd264, {left}, {right}; \| sub.s64 {to}, %rd264, <carry>; \| shr.u64 %rd266, {to}, 32; \| cvt.u32.u64 %r629, %rd266; \| and.b32 <carry>, %r629, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 106 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 107 | sign_negate | r4 r1 | PTX | `shl.b32 %r635, {from}, 24; \| neg.s32 %r636, %r635; \| shr.s32 {to}, %r636, 24;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 108 | sign_multiply | r4 r1 r4 | PTX | `mul.lo.s32 %r640, {left}, {right}; \| cvt.s32.s8 {to}, %r640;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 109 | sign_select | r4 r4 r1 r6 | PTX | `setp.eq.s32 %p27, {where}, 0; \| selp.b32 %r645, {otherwise}, {chosen}, %p27; \| cvt.s32.s8 {to}, %r645;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 110 | sign_select | r4 r1 r4 r6 | PTX | `setp.eq.s32 %p28, {where}, 0; \| selp.b32 %r650, {otherwise}, {chosen}, %p28; \| cvt.s32.s8 {to}, %r650;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 111 | word_copy | r0 r0 | PTX | `` | the compiler writes no instruction for it |
| 112 | sign_absolute | r1 r1 | PTX | `and.b32 %r654, {from}, 128; \| setp.eq.s32 %p29, %r654, 0; \| cvt.s32.s8 %r655, {from}; \| neg.s32 %r656, %r655; \| selp.b32 %r657, %r655, %r656, %p29; \| cvt.s32.s8 {to}, %r657;` | the compiler writes 6 instructions where the ruleset writes 1 |
| 113 | word_copy | r4 r0 | PTX | `` | the compiler writes no instruction for it |
| 114 | word_or | r4 r4 r4 | PTX | `or.b32 {to}, {right}, {left};` |  |
| 115 | sign_select | r4 r4 n r6 | PTX | `setp.eq.s32 %p30, {where}, 0; \| cvt.s32.s8 %r665, {chosen}; \| selp.b32 {to}, 0, %r665, %p30;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 116 | sign_select | r4 r4 n r6 | PTX | `setp.eq.s32 %p31, {where}, 0; \| cvt.s32.s8 %r669, {chosen}; \| selp.b32 {to}, {otherwise}, %r669, %p31;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 117 | test_signed_greater | r6 r1 r1 | PTX | `shl.b32 %r673, {left}, 24; \| shl.b32 %r674, {right}, 24; \| setp.gt.s32 {where}, %r673, %r674;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 118 | test_signed_differ | r6 r1 r1 | PTX | `xor.b32 %r678, {right}, {left}; \| and.b32 %r679, %r678, 255; \| setp.ne.s32 {where}, %r679, 0;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 119 | sign_select | r1 r4 r4 r6 | PTX | `setp.eq.s32 %p34, {where}, 0; \| selp.b32 %r684, {otherwise}, {chosen}, %p34; \| cvt.s32.s8 {to}, %r684;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 120 | sign_absolute | r0 r1 | PTX | `and.b32 %r687, {from}, 128; \| setp.eq.s32 %p35, %r687, 0; \| cvt.s32.s8 %r688, {from}; \| neg.s32 %r689, %r688; \| selp.b32 {to}, %r688, %r689, %p35;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 121 | subtract_alone | r4 f0 r0 | PTX | `sub.s32 {to}, {left}, {right};` |  |
| 122 | word_set | r0 r8 | PTX | `mov.u32 {to}, {value};` |  |
| 123 | word_set | r0 r8 | PTX | `mov.u32 {to}, {value};` |  |
| 124 | sign_set | r1 n | PTX | `` | the compiler writes no instruction for it |
| 125 | sign_set | r1 n | PTX | `` | the compiler writes no instruction for it |
| 126 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd270, {to}, 32; \| cvt.u32.u64 %r696, %rd270; \| and.b32 <carry>, %r696, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 127 | borrow_middle | r4 r0 r0 | PTX | `sub.s64 %rd274, {left}, {right}; \| sub.s64 {to}, %rd274, <carry>; \| shr.u64 %rd276, {to}, 32; \| cvt.u32.u64 %r698, %rd276; \| and.b32 <carry>, %r698, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 128 | borrow_middle | r4 r0 f0 | PTX | `sub.s64 %rd280, {left}, {right}; \| sub.s64 {to}, %rd280, <carry>; \| shr.u64 %rd282, {to}, 32; \| cvt.u32.u64 %r700, %rd282; \| and.b32 <carry>, %r700, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 129 | borrow_last | r4 r0 f0 | PTX | `sub.s64 %rd286, {left}, {right}; \| sub.s64 {to}, %rd286, <carry>; \| shr.u64 %rd288, {to}, 32; \| cvt.u32.u64 %r702, %rd288; \| and.b32 <carry>, %r702, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 130 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 131 | subtract_alone | r4 r1 r8 | PTX | `cvt.s32.s8 %r708, {left}; \| add.s32 {to}, %r708, -{right};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 132 | subtract_alone | r4 r1 r8 | PTX | `cvt.s32.s8 %r711, {left}; \| add.s32 {to}, %r711, -{right};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 133 | word_set | r4 n | PTX | `` | the compiler writes no instruction for it |
| 134 | word_set | r4 n | PTX | `` | the compiler writes no instruction for it |
| 135 | word_set | r4 r8 | PTX | `mov.u32 {to}, {value};` |  |
| 136 | word_set | r4 r8 | PTX | `mov.u32 {to}, {value};` |  |
| 137 | product_low | r4 r0 r4 r4 | PTX | `mul.lo.s32 %r717, {right}, {left}; \| cvt.u64.u32 %rd290, %r717; \| add.s64 {to}, %rd290, {added}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 138 | product_high | r4 r0 r4 | PTX | `mul.wide.u32 %rd293, {right}, {left}; \| shr.u64 %rd294, %rd293, 32; \| cvt.u32.u64 %r721, %rd294; \| add.s32 {to}, <carry>, %r721;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 139 | add_alone | r4 r4 r4 | PTX | `add.s32 {to}, {right}, {left};` |  |
| 140 | add_first | r4 r4 r4 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 141 | add_last | r4 r4 f0 | PTX | `add.s32 %r729, {right}, {left}; \| add.s32 {to}, %r729, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 142 | word_select | r4 f0 r8 r6 | PTX | `setp.eq.s32 %p37, {where}, 0; \| selp.b32 {to}, {otherwise}, {chosen}, %p37;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 143 | word_select | r4 f0 r8 r6 | PTX | `setp.eq.s32 %p38, {where}, 0; \| selp.b32 {to}, {otherwise}, {chosen}, %p38;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 144 | borrow_first | r4 r0 r4 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd302, {to}, 32; \| cvt.u32.u64 %r737, %rd302; \| and.b32 <carry>, %r737, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 145 | borrow_middle | r4 f0 r4 | PTX | `sub.s64 %rd306, {left}, {right}; \| sub.s64 {to}, %rd306, <carry>; \| shr.u64 %rd308, {to}, 32; \| cvt.u32.u64 %r739, %rd308; \| and.b32 <carry>, %r739, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 146 | borrow_last | r4 f0 r4 | PTX | `sub.s64 %rd312, {left}, {right}; \| sub.s64 {to}, %rd312, <carry>; \| shr.u64 %rd314, {to}, 32; \| cvt.u32.u64 %r741, %rd314; \| and.b32 <carry>, %r741, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 147 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 148 | add_alone | r4 r4 r8 | PTX | `add.s32 {to}, {left}, {right};` |  |
| 149 | add_alone | r4 r4 r8 | PTX | `add.s32 {to}, {left}, {right};` |  |
| 150 | add_first | r4 r4 r4 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 151 | add_last | r4 r4 r4 | PTX | `add.s32 %r753, {right}, {left}; \| add.s32 {to}, %r753, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 152 | word_copy | r0 r4 | PTX | `` | the compiler writes no instruction for it |
| 153 | sign_select | r1 r1 n r6 | PTX | `setp.eq.s32 %p40, {where}, 0; \| cvt.s32.s8 %r758, {chosen}; \| selp.b32 {to}, 0, %r758, %p40;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 154 | sign_select | r1 r1 n r6 | PTX | `setp.eq.s32 %p41, {where}, 0; \| cvt.s32.s8 %r762, {chosen}; \| selp.b32 {to}, {otherwise}, %r762, %p41;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 155 | launch_load | r5 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 156 | launch_load | r5 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 157 | count_add | r5 | PTX | `atom.add.u32 %r764, [{address}], 1;` | the question names no address space |
| 158 | record_store | n f0 | PTX | `st.u32 [<record>+{offset}], {from};` | the question names no address space |
| 159 | record_store | n f0 | PTX | `st.u32 [<record>+{offset}], {from};` | the question names no address space |
| 160 | borrow_alone | r4 r4 r8 | PTX | `add.s64 {to}, {left}, -{right}; \| shr.u64 %rd328, {to}, 32; \| cvt.u32.u64 %r767, %rd328; \| and.b32 <carry>, %r767, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 161 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 162 | borrow_alone | r4 r4 r8 | PTX | `add.s64 {to}, {left}, -{right}; \| shr.u64 %rd331, {to}, 32; \| cvt.u32.u64 %r772, %rd331; \| and.b32 <carry>, %r772, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 163 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 164 | test_zero | r6 r4 | PTX | `setp.eq.s32 {where}, {value}, 0;` |  |
| 165 | word_funnel_right | r4 r4 r4 n | PTX | `bfi.b64 %rd334, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd334, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 166 | word_funnel_right | r4 r4 r4 n | PTX | `bfi.b64 %rd338, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd338, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 167 | word_funnel_right | r4 f0 r4 n | PTX | `bfi.b64 %rd342, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd342, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 168 | word_funnel_right | r4 f0 r4 n | PTX | `bfi.b64 %rd346, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd346, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 169 | subtract_alone | r4 r4 r8 | PTX | `add.s32 {to}, {left}, -{right};` |  |
| 170 | subtract_alone | r4 r4 r8 | PTX | `add.s32 {to}, {left}, -{right};` |  |
| 171 | borrow_first | r4 r4 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd351, {to}, 32; \| cvt.u32.u64 %r783, %rd351; \| and.b32 <carry>, %r783, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 172 | borrow_middle | r4 r4 r0 | PTX | `sub.s64 %rd355, {left}, {right}; \| sub.s64 {to}, %rd355, <carry>; \| shr.u64 %rd357, {to}, 32; \| cvt.u32.u64 %r785, %rd357; \| and.b32 <carry>, %r785, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 173 | borrow_last | r4 r4 f0 | PTX | `sub.s64 %rd361, {left}, {right}; \| sub.s64 {to}, %rd361, <carry>; \| shr.u64 %rd363, {to}, 32; \| cvt.u32.u64 %r787, %rd363; \| and.b32 <carry>, %r787, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 174 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 175 | predicate_and | r6 r6 r6 | PTX | `and.pred {where}, {left}, {right};` |  |
| 176 | word_and | r4 r4 r4 | PTX | `and.b32 {to}, {right}, {left};` |  |
| 177 | borrow_first | r4 r4 r4 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd367, {to}, 32; \| cvt.u32.u64 %r798, %rd367; \| and.b32 <carry>, %r798, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 178 | borrow_middle | r4 r4 r4 | PTX | `sub.s64 %rd371, {left}, {right}; \| sub.s64 {to}, %rd371, <carry>; \| shr.u64 %rd373, {to}, 32; \| cvt.u32.u64 %r800, %rd373; \| and.b32 <carry>, %r800, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 179 | borrow_last | r4 r4 r4 | PTX | `sub.s64 %rd377, {left}, {right}; \| sub.s64 {to}, %rd377, <carry>; \| shr.u64 %rd379, {to}, 32; \| cvt.u32.u64 %r802, %rd379; \| and.b32 <carry>, %r802, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 180 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 181 | word_funnel_right | r4 r4 f0 n | PTX | `bfi.b64 %rd382, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd382, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 182 | word_funnel_right | r4 r4 f0 n | PTX | `bfi.b64 %rd386, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd386, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 183 | word_copy | r4 f0 | PTX | `` | the compiler writes no instruction for it |
| 184 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 185 | add_middle | r0 r0 r0 | PTX | `add.s64 %rd395, {right}, {left}; \| add.s64 {to}, %rd395, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 186 | add_middle | r0 r0 f0 | PTX | `add.s64 %rd401, {right}, {left}; \| add.s64 {to}, %rd401, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 187 | add_last | r0 r0 f0 | PTX | `add.s32 %r811, {right}, {left}; \| add.s32 {to}, %r811, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 188 | word_and | r0 r0 r8 | PTX | `and.b32 {to}, {left}, {right};` |  |
| 189 | word_and | r0 r0 r8 | PTX | `and.b32 {to}, {left}, {right};` |  |
| 190 | word_xor | r0 r4 r4 | PTX | `xor.b32 {to}, {right}, {left};` |  |
| 191 | predicate_xor | r6 r6 r6 | PTX | `xor.pred {where}, {left}, {right};` |  |
| 192 | word_and | r0 r4 r4 | PTX | `and.b32 {to}, {right}, {left};` |  |
| 193 | subtract_first | r4 f0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd407, {to}, 32; \| cvt.u32.u64 %r826, %rd407; \| and.b32 <carry>, %r826, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 194 | subtract_last | r4 f0 r0 | PTX | `sub.s32 %r831, {left}, {right}; \| sub.s32 {to}, %r831, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 195 | test_wide_below_and | f11 f4 f5 f11 | PTX | `setp.lt.u64 %p54, {left}, {right}; \| and.pred {where}, %p54, {also};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 196 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 197 | add_last | r0 r0 r0 | PTX | `add.s32 %r838, {right}, {left}; \| add.s32 {to}, %r838, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 198 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd417, {to}, 32; \| cvt.u32.u64 %r840, %rd417; \| and.b32 <carry>, %r840, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 199 | borrow_last | r4 r0 r0 | PTX | `sub.s64 %rd421, {left}, {right}; \| sub.s64 {to}, %rd421, <carry>; \| shr.u64 %rd423, {to}, 32; \| cvt.u32.u64 %r842, %rd423; \| and.b32 <carry>, %r842, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 200 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 201 | subtract_first | r4 f0 r4 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd427, {to}, 32; \| cvt.u32.u64 %r847, %rd427; \| and.b32 <carry>, %r847, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 202 | subtract_last | r4 f0 r4 | PTX | `sub.s32 %r852, {left}, {right}; \| sub.s32 {to}, %r852, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 203 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 204 | add_middle | r0 r0 r0 | PTX | `add.s64 %rd435, {right}, {left}; \| add.s64 {to}, %rd435, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 205 | add_last | r0 f0 f0 | PTX | `add.s32 %r857, {right}, {left}; \| add.s32 {to}, %r857, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 206 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd441, {to}, 32; \| cvt.u32.u64 %r859, %rd441; \| and.b32 <carry>, %r859, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 207 | borrow_middle | r4 r0 r0 | PTX | `sub.s64 %rd445, {left}, {right}; \| sub.s64 {to}, %rd445, <carry>; \| shr.u64 %rd447, {to}, 32; \| cvt.u32.u64 %r861, %rd447; \| and.b32 <carry>, %r861, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 208 | borrow_last | r4 f0 f0 | PTX | `sub.s64 %rd451, {left}, {right}; \| sub.s64 {to}, %rd451, <carry>; \| shr.u64 %rd453, {to}, 32; \| cvt.u32.u64 %r863, %rd453; \| and.b32 <carry>, %r863, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 209 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 210 | launch_load | f6 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 211 | launch_load | f6 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 212 | wide_unpack | r0 r0 f1 | PTX | `shr.u64 {high}, {low}, 32;` | the reading does not name from |
| 213 | test_wide_nonzero | r6 f1 | PTX | `setp.ne.s64 {where}, {value}, 0;` |  |
| 214 | word_multiply | r4 r4 r8 | PTX | `shl.b32 {to}, {left}, 1;` | the reading does not name right |
| 215 | word_multiply | r4 r4 r8 | PTX | `mul.lo.s32 {to}, {left}, {right};` |  |
| 216 | wide_multiply_word | r5 r4 n | PTX | `mul.wide.u32 {to}, {left}, {right};` |  |
| 217 | wide_multiply_word | r5 r4 n | PTX | `mul.wide.u32 {to}, {left}, {right};` |  |
| 218 | wide_add | r5 f6 r5 | PTX | `add.s64 {to}, {right}, {left};` |  |
| 219 | global_load | r0 r5 n | PTX | `ld.u32 {to}, [{address}+{offset}];` | the question names no address space |
| 220 | global_load | r0 r5 n | PTX | `ld.u32 {to}, [{address}+{offset}];` | the question names no address space |
| 221 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 222 | add_last | r0 r0 f0 | PTX | `add.s32 %r880, {right}, {left}; \| add.s32 {to}, %r880, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 223 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd475, {to}, 32; \| cvt.u32.u64 %r882, %rd475; \| and.b32 <carry>, %r882, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 224 | borrow_last | r4 r0 f0 | PTX | `sub.s64 %rd479, {left}, {right}; \| sub.s64 {to}, %rd479, <carry>; \| shr.u64 %rd481, {to}, 32; \| cvt.u32.u64 %r884, %rd481; \| and.b32 <carry>, %r884, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 225 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 4097 | launch_load | f2 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4098 | launch_load | f2 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4099 | wide_multiply | r5 f1 r8 | SASS | `IMAD R254, {left}.hi, 0x98, RZ; \| IMAD.WIDE.U32 R24, {left}, 0x98, RZ; \| IMAD.IADD {to}.hi, R25, 0x1, R254; \| IMAD.MOV.U32 {to}, RZ, RZ, R24;` | the compiler writes 4 instructions where the ruleset writes 3 |
| 4100 | wide_multiply | r5 f1 r8 | SASS | `IMAD R254, {left}.hi, 0x94, RZ; \| IMAD.WIDE.U32 R24, {left}, 0x94, RZ; \| IMAD.IADD {to}.hi, R25, 0x1, R254; \| IMAD.MOV.U32 {to}, RZ, RZ, R24;` | the compiler writes 4 instructions where the ruleset writes 3 |
| 4101 | wide_add | f2 f2 r5 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` |  |
| 4102 | launch_load | f3 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4103 | launch_load | f3 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4104 | test_wide_nonzero | f9 f3 | SASS | `ISETP.NE.U32.AND P6, PT, {value}, RZ, PT; \| ISETP.NE.AND.EX {where}, PT, {value}.hi, RZ, PT, P6;` |  |
| 4105 | launch_load | f5 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4106 | launch_load | f5 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4107 | test_wide_equal | f10 f5 n | SASS | `ISETP.NE.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.NE.AND.EX {where}, PT, {left}.hi, RZ, PT, P6;` | the compiler sets the negation of where;  |
| 4108 | test_wide_equal | f10 f5 n | SASS | `ISETP.NE.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.NE.AND.EX {where}, PT, {left}.hi, RZ, PT, P6;` | the compiler sets the negation of where;  |
| 4109 | wide_select | f4 n f1 f10 | SASS | `SEL {to}, {otherwise}, RZ, !{where}; \| SEL {to}.hi, {otherwise}.hi, RZ, !{where};` | the reading does not name chosen |
| 4110 | wide_select | f4 n f1 f10 | SASS | `SEL {to}, {otherwise}, {chosen}, !{where}; \| SEL {to}.hi, {otherwise}.hi, RZ, !{where};` |  |
| 4111 | wide_add_unsigned | r5 r5 r8 | SASS | `` | the compiler writes no instruction for it |
| 4112 | wide_add_unsigned | r5 r5 r8 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, RZ, RZ, {left}.hi, P6;` |  |
| 4113 | wide_shift_left | r5 r5 n | SASS | `SHF.L.U64.HI {to}.hi, {from}, {bits}, {from}.hi; \| IMAD.SHL.U32 {to}, {from}, 0x4, RZ;` | the machine file holds no form for it |
| 4114 | wide_shift_left | r5 r5 n | SASS | `SHF.L.U64.HI {to}.hi, {from}, {bits}, {from}.hi; \| IMAD.SHL.U32 {to}, {from}, 0x8, RZ;` | the machine file holds no form for it |
| 4115 | wide_add | r5 f3 r5 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` |  |
| 4116 | guarded_load | f9 r4 r5 | SASS | `@!{where} BRA 0x7a40; \| LDG.E.CONSTANT {to}, [{address}.64];` | the reading holds a branch |
| 4117 | guarded_widen | f9 f4 r4 | SASS | `SEL {to}, {from}, {to}, {where}; \| SEL {to}.hi, {to}.hi, RZ, !{where};` |  |
| 4118 | test_wide_below | f11 f4 f5 | SASS | `ISETP.GE.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.GE.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, PT, P6;` | the compiler sets the negation of where;  |
| 4119 | wide_select | f4 f4 n f11 | SASS | `SEL {to}, {chosen}, RZ, {where}; \| SEL {to}.hi, {chosen}.hi, RZ, {where};` | the reading does not name otherwise |
| 4120 | wide_select | f4 f4 n f11 | SASS | `SEL {to}, {chosen}, {otherwise}, {where}; \| SEL {to}.hi, {chosen}.hi, RZ, {where};` |  |
| 4121 | launch_load | r7 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4122 | launch_load | r7 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4123 | wide_multiply | r5 f4 r8 | SASS | `IMAD.WIDE.U32 R254, {left}, 0x20, RZ; \| IMAD.SHL.U32 R25, {left}.hi, 0x20, RZ; \| IMAD.IADD {to}.hi, R27, 0x1, R25; \| IMAD.MOV.U32 {to}, RZ, RZ, R254;` | the compiler writes 4 instructions where the ruleset writes 3 |
| 4124 | wide_multiply | r5 f4 r8 | SASS | `IMAD R254, {left}.hi, 0x1c, RZ; \| IMAD.WIDE.U32 R24, {left}, 0x1c, RZ; \| IMAD.IADD {to}.hi, R25, 0x1, R254; \| IMAD.MOV.U32 {to}, RZ, RZ, R24;` | the compiler writes 4 instructions where the ruleset writes 3 |
| 4125 | wide_add | r7 r7 r5 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` |  |
| 4126 | word_multiply_add | f8 f7 r8 f8 | SASS | `IMAD {to}, {left}, {right}, {added};` |  |
| 4127 | word_multiply_add | f8 f7 r8 f8 | SASS | `IMAD {to}, {left}, {right}, {added};` |  |
| 4128 | global_load | r3 r7 n | SASS | `LDG.E.CONSTANT {to}, [{address}.64+{offset}];` |  |
| 4129 | global_load | r3 r7 n | SASS | `LDG.E.CONSTANT {to}, [{address}.64+{offset}];` |  |
| 4130 | word_copy | r0 r3 | SASS | `` | the compiler writes no instruction for it |
| 4131 | word_and | r4 r0 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4132 | word_and | r4 r0 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4133 | test_nonzero | r6 r4 | SASS | `ISETP.NE.AND {where}, PT, {value}, RZ, PT;` |  |
| 4134 | word_select | r0 r4 r0 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4135 | sign_select | r4 n n r6 | SASS | `` | the compiler writes no instruction for it |
| 4136 | sign_select | r4 n n r6 | SASS | `` | the compiler writes no instruction for it |
| 4137 | word_or | r4 r0 r0 | SASS | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` |  |
| 4138 | word_or | r4 r4 r0 | SASS | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` |  |
| 4139 | sign_select | r1 r4 n r6 | SASS | `SEL {to}, {chosen}, RZ, {where};` | the reading does not name otherwise |
| 4140 | sign_select | r1 r4 n r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4141 | sign_select | r1 n n r6 | SASS | `SEL {to}, RZ, {chosen}, !{where};` | the reading does not name otherwise |
| 4142 | sign_select | r1 n n r6 | SASS | `SEL {to}, R17, {otherwise}, {where};` | the reading does not name chosen |
| 4143 | test_nonzero | r6 r0 | SASS | `ISETP.NE.AND {where}, PT, {value}, RZ, PT;` |  |
| 4144 | word_set | r0 n | SASS | `` | the compiler writes no instruction for it |
| 4145 | word_set | r0 n | SASS | `` | the compiler writes no instruction for it |
| 4146 | subtract_first | r4 f0 r0 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4147 | subtract_middle | r4 f0 r0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4148 | subtract_last | r4 f0 r0 | SASS | `IMAD.X {to}, {left}, 0x1, ~{right}, P6;` |  |
| 4149 | product_low | r0 r0 r0 r0 | SASS | `IMAD R254, {left}, {right}, RZ; \| IADD3 {to}, P6, R254, {added}, RZ;` |  |
| 4150 | product_high | r4 r0 r0 | SASS | `IMAD.HI.U32 R254, {left}, {right}, RZ; \| IMAD.X {to}, R254, 0x1, <zero>, P6;` |  |
| 4151 | add_first | r0 r0 r4 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ;` |  |
| 4152 | add_last | r4 r4 f0 | SASS | `IMAD.X {to}, {left}, 0x1, {right}, P6;` |  |
| 4153 | add_middle | r0 r0 f0 | SASS | `IADD3.X {to}, P6, {left}, {right}, RZ, P6, !PT;` |  |
| 4154 | add_last | r0 r0 f0 | SASS | `IMAD.X {to}, {left}, 0x1, {right}, P6;` |  |
| 4155 | add_alone | r0 r0 r4 | SASS | `IMAD.IADD {to}, {left}, 0x1, {right};` |  |
| 4156 | sign_multiply | r1 r1 r1 | SASS | `IMAD {to}, {left}, {right}, RZ;` |  |
| 4157 | test_negative | r6 r1 | SASS | `ISETP.GE.AND {where}, PT, {value}, RZ, PT;` | the compiler sets the negation of where;  |
| 4158 | word_select | r4 r4 r0 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4159 | word_select | r4 r4 f0 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4160 | word_and | r4 r4 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4161 | word_and | r4 r4 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4162 | word_set | r2 n | SASS | `` | the compiler writes no instruction for it |
| 4163 | word_set | r2 n | SASS | `` | the compiler writes no instruction for it |
| 4164 | word_or | r2 r2 r4 | SASS | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` |  |
| 4165 | record_store | n r2 | SASS | `STG.E [<record>.64+{offset}], {from};` |  |
| 4166 | record_store | n r2 | SASS | `STG.E [<record>.64+{offset}], {from};` |  |
| 4167 | subtract_last | r4 f0 f0 | SASS | `IMAD.X {to}, {left}, 0x1, ~{right}, P6;` |  |
| 4168 | add_first | r0 r0 r0 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ;` |  |
| 4169 | add_last | r0 f0 f0 | SASS | `IMAD.X {to}, {left}, 0x1, {right}, P6;` |  |
| 4170 | borrow_first | r4 r0 r0 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4171 | borrow_middle | r4 r0 f0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4172 | borrow_last | r4 f0 f0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4173 | borrow_read | r4 r6 | SASS | `IMAD.X {borrow}, <zero>, 0x1, ~<zero>, P6; \| ISETP.NE.U32.AND {where}, PT, {borrow}, RZ, PT;` |  |
| 4174 | sign_multiply | r4 r1 r1 | SASS | `IMAD {to}, {left}, {right}, RZ;` |  |
| 4175 | test_negative | r6 r4 | SASS | `ISETP.GE.AND {where}, PT, {value}, RZ, PT;` | the compiler sets the negation of where;  |
| 4176 | word_select | r4 r4 r4 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4177 | sign_select | r4 r1 r1 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4178 | test_signed_differ | r6 r1 n | SASS | `ISETP.NE.AND {where}, PT, {left}, RZ, PT;` | the reading does not name right |
| 4179 | test_signed_differ | r6 r1 n | SASS | `ISETP.NE.AND {where}, PT, {left}, {right}, PT;` |  |
| 4180 | sign_select | r4 r4 r4 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4181 | subtract_first | r4 f0 r4 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4182 | subtract_middle | r4 f0 r4 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4183 | subtract_last | r4 f0 r4 | SASS | `IMAD.X {to}, {left}, 0x1, ~{right}, P6;` |  |
| 4184 | word_shift_left | r4 r4 n | SASS | `IMAD.SHL.U32 {to}, {from}, 0x8, RZ;` | the reading does not name bits |
| 4185 | word_shift_left | r4 r4 n | SASS | `IMAD.SHL.U32 {to}, {from}, 0x4, RZ;` | the reading does not name bits |
| 4186 | word_shift_right | r4 r4 n | SASS | `SHF.R.U32.HI {to}, RZ, {bits}, {from};` |  |
| 4187 | word_shift_right | r4 r4 n | SASS | `SHF.R.U32.HI {to}, RZ, {bits}, {from};` |  |
| 4188 | add_middle | r0 r0 r0 | SASS | `IADD3.X {to}, P6, {left}, {right}, RZ, P6, !PT;` |  |
| 4189 | add_middle | r0 f0 r0 | SASS | `IADD3.X {to}, P6, {left}, {right}, RZ, P6, !PT;` |  |
| 4190 | borrow_middle | r4 r0 r0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4191 | borrow_middle | r4 f0 r0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4192 | sign_negate | r4 r1 | SASS | `IMAD.MOV {to}, RZ, RZ, -{from};` |  |
| 4193 | sign_multiply | r4 r1 r4 | SASS | `IMAD {to}, {left}, {right}, RZ;` |  |
| 4194 | sign_select | r4 r4 r1 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4195 | sign_select | r4 r1 r4 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4196 | word_copy | r0 r0 | SASS | `` | the compiler writes no instruction for it |
| 4197 | sign_absolute | r1 r1 | SASS | `IABS {to}, {from};` |  |
| 4198 | word_copy | r4 r0 | SASS | `` | the compiler writes no instruction for it |
| 4199 | word_or | r4 r4 r4 | SASS | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` |  |
| 4200 | sign_select | r4 r4 n r6 | SASS | `SEL {to}, {chosen}, RZ, {where};` | the reading does not name otherwise |
| 4201 | sign_select | r4 r4 n r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4202 | test_signed_greater | r6 r1 r1 | SASS | `ISETP.GT.AND {where}, PT, {left}, {right}, PT;` |  |
| 4203 | test_signed_differ | r6 r1 r1 | SASS | `ISETP.NE.AND {where}, PT, {left}, {right}, PT;` |  |
| 4204 | sign_select | r1 r4 r4 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4205 | sign_absolute | r0 r1 | SASS | `IABS {to}, {from};` |  |
| 4206 | subtract_alone | r4 f0 r0 | SASS | `IMAD.IADD {to}, {left}, 0x1, -{right};` |  |
| 4207 | word_set | r0 r8 | SASS | `` | the compiler writes no instruction for it |
| 4208 | word_set | r0 r8 | SASS | `` | the compiler writes no instruction for it |
| 4209 | sign_set | r1 n | SASS | `` | the compiler writes no instruction for it |
| 4210 | sign_set | r1 n | SASS | `` | the compiler writes no instruction for it |
| 4211 | borrow_last | r4 r0 f0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4212 | subtract_alone | r4 r1 r8 | SASS | `IADD3 {to}, {left}, -{right}, RZ;` |  |
| 4213 | subtract_alone | r4 r1 r8 | SASS | `IADD3 {to}, {left}, -{right}, RZ;` |  |
| 4214 | word_set | r4 n | SASS | `` | the compiler writes no instruction for it |
| 4215 | word_set | r4 n | SASS | `` | the compiler writes no instruction for it |
| 4216 | word_set | r4 r8 | SASS | `` | the compiler writes no instruction for it |
| 4217 | word_set | r4 r8 | SASS | `` | the compiler writes no instruction for it |
| 4218 | product_low | r4 r0 r4 r4 | SASS | `IMAD R254, {left}, {right}, RZ; \| IADD3 {to}, P6, R254, {added}, RZ;` |  |
| 4219 | product_high | r4 r0 r4 | SASS | `IMAD.HI.U32 R254, {left}, {right}, RZ; \| IMAD.X {to}, R254, 0x1, <zero>, P6;` |  |
| 4220 | add_alone | r4 r4 r4 | SASS | `IMAD.IADD {to}, {left}, 0x1, {right};` |  |
| 4221 | add_first | r4 r4 r4 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ;` |  |
| 4222 | word_select | r4 f0 r8 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4223 | word_select | r4 f0 r8 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4224 | borrow_first | r4 r0 r4 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4225 | borrow_middle | r4 f0 r4 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4226 | borrow_last | r4 f0 r4 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4227 | add_alone | r4 r4 r8 | SASS | `IADD3 {to}, {left}, {right}, RZ;` |  |
| 4228 | add_alone | r4 r4 r8 | SASS | `IADD3 {to}, {left}, {right}, RZ;` |  |
| 4229 | add_last | r4 r4 r4 | SASS | `IMAD.X {to}, {left}, 0x1, {right}, P6;` |  |
| 4230 | word_copy | r0 r4 | SASS | `` | the compiler writes no instruction for it |
| 4231 | sign_select | r1 r1 n r6 | SASS | `SEL {to}, {chosen}, RZ, {where};` | the reading does not name otherwise |
| 4232 | sign_select | r1 r1 n r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4233 | launch_load | r5 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4234 | launch_load | r5 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4235 | count_add | r5 | SASS | `VOTEU.ANY UR6, UPT, PT; \| UFLO.U32 UR7, UR6; \| POPC R254, UR6; \| ISETP.EQ.U32.AND P6, PT, R0, UR7, PT; \| @P6 RED.E.ADD.STRONG.GPU [{address}.64], R254;` | the compiler writes 5 instructions where the ruleset writes 2 |
| 4236 | record_store | n f0 | SASS | `STG.E [<record>.64+{offset}], {from};` |  |
| 4237 | record_store | n f0 | SASS | `STG.E [<record>.64+{offset}], {from};` |  |
| 4238 | borrow_alone | r4 r4 r8 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4239 | borrow_alone | r4 r4 r8 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4240 | test_zero | r6 r4 | SASS | `ISETP.NE.AND {where}, PT, {value}, RZ, PT;` | the compiler sets the negation of where;  |
| 4241 | word_funnel_right | r4 r4 r4 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4242 | word_funnel_right | r4 r4 r4 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4243 | word_funnel_right | r4 f0 r4 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4244 | word_funnel_right | r4 f0 r4 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4245 | subtract_alone | r4 r4 r8 | SASS | `IADD3 {to}, {left}, -{right}, RZ;` |  |
| 4246 | subtract_alone | r4 r4 r8 | SASS | `IADD3 {to}, {left}, -{right}, RZ;` |  |
| 4247 | borrow_first | r4 r4 r0 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4248 | borrow_middle | r4 r4 r0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4249 | borrow_last | r4 r4 f0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4250 | predicate_and | r6 r6 r6 | SASS | `ISETP.NE.U32.AND {where}, PT, {left}, RZ, {right};` | the ruleset holds no form of the name |
| 4251 | word_and | r4 r4 r4 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4252 | borrow_first | r4 r4 r4 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4253 | borrow_middle | r4 r4 r4 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4254 | borrow_last | r4 r4 r4 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4255 | word_funnel_right | r4 r4 f0 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4256 | word_funnel_right | r4 r4 f0 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4257 | word_copy | r4 f0 | SASS | `` | the compiler writes no instruction for it |
| 4258 | word_and | r0 r0 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4259 | word_and | r0 r0 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4260 | word_xor | r0 r4 r4 | SASS | `LOP3.LUT {to}, {right}, {left}, RZ, 0x3c, !PT;` |  |
| 4261 | predicate_xor | r6 r6 r6 | SASS | `ISETP.NE.U32.XOR {where}, PT, {left}, RZ, {right};` | the ruleset holds no form of the name |
| 4262 | word_and | r0 r4 r4 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4263 | test_wide_below_and | f11 f4 f5 f11 | SASS | `ISETP.LT.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.LT.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, {also}, P6;` |  |
| 4264 | add_last | r0 r0 r0 | SASS | `IMAD.X {to}, {left}, 0x1, {right}, P6;` |  |
| 4265 | borrow_last | r4 r0 r0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4266 | launch_load | f6 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4267 | launch_load | f6 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4268 | wide_unpack | r0 r0 f1 | SASS | `` | the compiler writes no instruction for it |
| 4269 | test_wide_nonzero | r6 f1 | SASS | `ISETP.NE.U32.AND P6, PT, {value}, RZ, PT; \| ISETP.NE.AND.EX {where}, PT, {value}.hi, RZ, PT, P6;` |  |
| 4270 | word_multiply | r4 r4 r8 | SASS | `IMAD.SHL.U32 {to}, {left}, {right}, RZ;` | the machine file holds no form for it |
| 4271 | word_multiply | r4 r4 r8 | SASS | `IMAD {to}, {left}, {right}, RZ;` |  |
| 4272 | wide_multiply_word | r5 r4 n | SASS | `IMAD.WIDE.U32 {to}, {left}, {right}, RZ;` |  |
| 4273 | wide_multiply_word | r5 r4 n | SASS | `IMAD.WIDE.U32 {to}, {left}, {right}, RZ;` |  |
| 4274 | wide_add | r5 f6 r5 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` |  |
| 4275 | global_load | r0 r5 n | SASS | `LDG.E.CONSTANT {to}, [{address}.64+{offset}];` |  |
| 4276 | global_load | r0 r5 n | SASS | `LDG.E.CONSTANT {to}, [{address}.64+{offset}];` |  |

## By form

| form | sass.krs | SASS read | | ptx.krs | PTX read | |
|---|---|---|---|---|---|---|
| add_alone | `IADD3 {to}, {left}, {right}, RZ;` | `` | kept: the questions read apart | `add.u32 {to}, {left}, {right};` | `` | kept: the questions read apart |
| add_first | `IADD3 {to}, P6, {left}, {right}, RZ;` | `IADD3 {to}, P6, {left}, {right}, RZ;` | same | `add.cc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| add_last | `IMAD.X {to}, {left}, 0x1, {right}, P6;` | `IMAD.X {to}, {left}, 0x1, {right}, P6;` | same | `addc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| add_middle | `IADD3.X {to}, P6, {left}, {right}, RZ, P6, !PT;` | `IADD3.X {to}, P6, {left}, {right}, RZ, P6, !PT;` | same | `addc.cc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 3 instructions where the ruleset writes 1 |
| borrow_alone | `IADD3 {to}, P6, {left}, -{right}, RZ;` | `IADD3 {to}, P6, {left}, -{right}, RZ;` | same | `sub.cc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 4 instructions where the ruleset writes 1 |
| borrow_first | `IADD3 {to}, P6, {left}, -{right}, RZ;` | `IADD3 {to}, P6, {left}, -{right}, RZ;` | same | `sub.cc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 4 instructions where the ruleset writes 1 |
| borrow_last | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` | same | `subc.cc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 5 instructions where the ruleset writes 1 |
| borrow_middle | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` | same | `subc.cc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 5 instructions where the ruleset writes 1 |
| borrow_read | `IMAD.X {borrow}, RZ, 0x1, ~RZ, P6; \| ISETP.NE.U32.AND {where}, PT, {borrow}, RZ, PT;` | `IMAD.X {borrow}, RZ, 0x1, ~RZ, P6; \| ISETP.NE.U32.AND {where}, PT, {borrow}, RZ, PT;` | same | `subc.u32 {borrow}, %zero, %zero; \| setp.ne.u32 {where}, {borrow}, 0;` | `` | kept: the ruleset names no fixed register carry |
| count_add | `MOV R254, 1; \| RED.E.ADD.STRONG.GPU [{address}.64], R254;` | `` | kept: the compiler writes 5 instructions where the ruleset writes 2 | `red.global.add.u32 [{address}], 1;` | `` | kept: the question names no address space |
| global_load | `LDG.E.CONSTANT {to}, [{address}.64+{offset}];` | `LDG.E.CONSTANT {to}, [{address}.64+{offset}];` | same | `ld.global.nc.u32 {to}, [{address}+{offset}];` | `` | kept: the question names no address space |
| guarded_load | `@{where} LDG.E.CONSTANT {to}, [{address}.64];` | `` | kept: the reading holds a branch | `@{where} ld.global.nc.u32 {to}, [{address}];` | `` | kept: the reading holds a branch |
| guarded_widen | `SEL {to}, {from}, {to}, {where}; \| SEL {to}.hi, {to}.hi, RZ, !{where};` | `SEL {to}, {from}, {to}, {where}; \| SEL {to}.hi, {to}.hi, RZ, !{where};` | same | `@{where} cvt.u64.u32 {to}, {from};` | `` | kept: the compiler writes 3 instructions where the ruleset writes 1 |
| launch_load | `LDG.E.64.CONSTANT {to}, [R238.64+{offset}];` | `` | kept: the question names no address space | `ld.u64 {to}, [%launch+{offset}];` | `` | kept: the ruleset names no fixed register launch |
| predicate_and | `` | `` | kept: the ruleset holds no form of the name | `and.pred {where}, {left}, {right};` | `and.pred {where}, {left}, {right};` | same |
| predicate_xor | `` | `` | kept: the ruleset holds no form of the name | `xor.pred {where}, {left}, {right};` | `xor.pred {where}, {left}, {right};` | same |
| product_high | `IMAD.HI.U32 R254, {left}, {right}, RZ; \| IMAD.X {to}, R254, 0x1, RZ, P6;` | `IMAD.HI.U32 R254, {left}, {right}, RZ; \| IMAD.X {to}, R254, 0x1, RZ, P6;` | same | `madc.hi.u32 {to}, {left}, {right}, %zero;` | `` | kept: the compiler writes 4 instructions where the ruleset writes 1 |
| product_low | `IMAD R254, {left}, {right}, RZ; \| IADD3 {to}, P6, R254, {added}, RZ;` | `IMAD R254, {left}, {right}, RZ; \| IADD3 {to}, P6, R254, {added}, RZ;` | same | `mad.lo.cc.u32 {to}, {left}, {right}, {added};` | `` | kept: the compiler writes 4 instructions where the ruleset writes 1 |
| record_store | `STG.E [R242.64+{offset}], {from};` | `STG.E [R242.64+{offset}], {from};` | same | `st.global.u32 [%record+{offset}], {from};` | `` | kept: the question names no address space |
| sign_absolute | `IABS {to}, {from};` | `IABS {to}, {from};` | same | `abs.s32 {to}, {from};` | `` | kept: the compiler writes 6 instructions where the ruleset writes 1 |
| sign_multiply | `IMAD {to}, {left}, {right}, RZ;` | `IMAD {to}, {left}, {right}, RZ;` | same | `mul.lo.s32 {to}, {left}, {right};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| sign_negate | `IMAD.MOV {to}, RZ, RZ, -{from};` | `IMAD.MOV {to}, RZ, RZ, -{from};` | same | `neg.s32 {to}, {from};` | `` | kept: the compiler writes 3 instructions where the ruleset writes 1 |
| sign_select | `MOV R254, {chosen}; \| SEL {to}, R254, {otherwise}, {where};` | `` | kept: the compiler writes no instruction for it | `selp.s32 {to}, {chosen}, {otherwise}, {where};` | `` | kept: the reading does not name otherwise |
| sign_set | `IMAD.MOV.U32 {to}, RZ, RZ, {value};` | `` | kept: the compiler writes no instruction for it | `mov.s32 {to}, {value};` | `` | kept: the compiler writes no instruction for it |
| subtract_alone | `IADD3 {to}, {left}, -{right}, RZ;` | `` | kept: the questions read apart | `sub.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| subtract_first | `IADD3 {to}, P6, {left}, -{right}, RZ;` | `IADD3 {to}, P6, {left}, -{right}, RZ;` | same | `sub.cc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 5 instructions where the ruleset writes 1 |
| subtract_last | `IMAD.X {to}, {left}, 0x1, ~{right}, P6;` | `IMAD.X {to}, {left}, 0x1, ~{right}, P6;` | same | `subc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| subtract_middle | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` | same | `subc.cc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 5 instructions where the ruleset writes 1 |
| test_negative | `ISETP.LT.AND {where}, PT, {value}, RZ, PT;` | `` | kept: the compiler sets the negation of where;  | `setp.lt.s32 {where}, {value}, 0;` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| test_nonzero | `ISETP.NE.AND {where}, PT, {value}, RZ, PT;` | `ISETP.NE.AND {where}, PT, {value}, RZ, PT;` | same | `setp.ne.s32 {where}, {value}, 0;` | `setp.ne.s32 {where}, {value}, 0;` | same |
| test_signed_differ | `ISETP.NE.AND {where}, PT, {left}, {right}, PT;` | `` | kept: the reading does not name right | `setp.ne.s32 {where}, {left}, {right};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| test_signed_greater | `ISETP.GT.AND {where}, PT, {left}, {right}, PT;` | `ISETP.GT.AND {where}, PT, {left}, {right}, PT;` | same | `setp.gt.s32 {where}, {left}, {right};` | `` | kept: the compiler writes 3 instructions where the ruleset writes 1 |
| test_wide_below | `ISETP.LT.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.LT.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, PT, P6;` | `` | kept: the compiler sets the negation of where;  | `setp.lt.u64 {where}, {left}, {right};` | `setp.lt.u64 {where}, {left}, {right};` | same |
| test_wide_below_and | `ISETP.LT.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.LT.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, {also}, P6;` | `ISETP.LT.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.LT.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, {also}, P6;` | same | `setp.lt.and.u64 {where}, {left}, {right}, {also};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| test_wide_equal | `ISETP.EQ.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.EQ.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, PT, P6;` | `` | kept: the compiler sets the negation of where;  | `setp.eq.s64 {where}, {left}, {right};` | `setp.eq.s64 {where}, {left}, {right};` | same |
| test_wide_nonzero | `ISETP.NE.U32.AND P6, PT, {value}, RZ, PT; \| ISETP.NE.AND.EX {where}, PT, {value}.hi, RZ, PT, P6;` | `ISETP.NE.U32.AND P6, PT, {value}, RZ, PT; \| ISETP.NE.AND.EX {where}, PT, {value}.hi, RZ, PT, P6;` | same | `setp.ne.s64 {where}, {value}, 0;` | `setp.ne.s64 {where}, {value}, 0;` | same |
| test_zero | `ISETP.EQ.U32.AND {where}, PT, {value}, RZ, PT;` | `` | kept: the compiler sets the negation of where;  | `setp.eq.s32 {where}, {value}, 0;` | `setp.eq.s32 {where}, {value}, 0;` | same |
| wide_add | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` | same | `add.s64 {to}, {right}, {left};` | `add.s64 {to}, {right}, {left};` | same |
| wide_add_unsigned | `IADD3 {to}, P6, {left}, {right}, RZ; \| IADD3.X {to}.hi, {left}.hi, {right}.hi, RZ, P6, !PT;` | `` | kept: the compiler writes no instruction for it | `add.u64 {to}, {left}, {right};` | `` | kept: the compiler writes no instruction for it |
| wide_multiply | `IMAD.WIDE.U32 {to}, {left}, {right}, RZ; \| IMAD {to}.hi, {left}.hi, {right}, {to}.hi; \| IMAD {to}.hi, {left}, {right}.hi, {to}.hi;` | `` | kept: the compiler writes 4 instructions where the ruleset writes 3 | `mul.lo.u64 {to}, {left}, {right};` | `` | kept: the reading does not name right |
| wide_multiply_word | `IMAD.WIDE.U32 {to}, {left}, {right}, RZ;` | `IMAD.WIDE.U32 {to}, {left}, {right}, RZ;` | same | `mul.wide.u32 {to}, {left}, {right};` | `mul.wide.u32 {to}, {left}, {right};` | same |
| wide_select | `MOV R254, {chosen}; \| SEL {to}, R254, {otherwise}, {where}; \| MOV R254, {chosen}.hi; \| SEL {to}.hi, R254, {otherwise}.hi, {where};` | `` | kept: the reading does not name chosen | `selp.b64 {to}, {chosen}, {otherwise}, {where};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| wide_shift_left | `SHF.L.U64.HI {to}.hi, {from}, {bits}, {from}.hi; \| SHF.L.U32 {to}, {from}, {bits}, RZ;` | `` | kept: the machine file holds no form for it | `shl.b64 {to}, {from}, {bits};` | `shl.b64 {to}, {from}, {bits};` | same |
| wide_unpack | `MOV {low}, {from}; \| MOV {high}, {from}.hi;` | `` | kept: the compiler writes no instruction for it | `mov.b64 {{low}, {high}}, {from};` | `` | kept: the reading does not name from |
| word_and | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` | same | `and.b32 {to}, {left}, {right};` | `` | kept: the questions read apart |
| word_copy | `MOV {to}, {from};` | `` | kept: the compiler writes no instruction for it | `mov.b32 {to}, {from};` | `` | kept: the compiler writes no instruction for it |
| word_funnel_right | `SHF.R.U32 {to}, {low}, {bits}, {high};` | `SHF.R.U32 {to}, {low}, {bits}, {high};` | same | `shf.r.clamp.b32 {to}, {low}, {high}, {bits};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| word_multiply | `IMAD {to}, {left}, {right}, RZ;` | `` | kept: the machine file holds no form for it | `mul.lo.u32 {to}, {left}, {right};` | `` | kept: the reading does not name right |
| word_multiply_add | `IMAD {to}, {left}, {right}, {added};` | `IMAD {to}, {left}, {right}, {added};` | same | `mad.lo.s32 {to}, {left}, {right}, {added};` | `mad.lo.s32 {to}, {left}, {right}, {added};` | same |
| word_or | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` | same | `or.b32 {to}, {right}, {left};` | `or.b32 {to}, {right}, {left};` | same |
| word_select | `SEL {to}, {chosen}, {otherwise}, {where};` | `SEL {to}, {chosen}, {otherwise}, {where};` | same | `selp.b32 {to}, {chosen}, {otherwise}, {where};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| word_set | `MOV {to}, {value};` | `` | kept: the compiler writes no instruction for it | `mov.u32 {to}, {value};` | `` | kept: the compiler writes no instruction for it |
| word_shift_left | `SHF.L.U32 {to}, {from}, {bits}, RZ;` | `` | kept: the reading does not name bits | `shl.b32 {to}, {from}, {bits};` | `shl.b32 {to}, {from}, {bits};` | same |
| word_shift_right | `SHF.R.U32.HI {to}, RZ, {bits}, {from};` | `SHF.R.U32.HI {to}, RZ, {bits}, {from};` | same | `shr.u32 {to}, {from}, {bits};` | `shr.u32 {to}, {from}, {bits};` | same |
| word_xor | `LOP3.LUT {to}, {right}, {left}, RZ, 0x3c, !PT;` | `LOP3.LUT {to}, {right}, {left}, RZ, 0x3c, !PT;` | same | `xor.b32 {to}, {right}, {left};` | `xor.b32 {to}, {right}, {left};` | same |

405 questions over 55 forms. Of the forms, sass.krs already gives 32 as read and 0 are read otherwise; ptx.krs gives 15 as read and 0 are read otherwise.
