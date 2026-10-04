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
| 15 | wide_add_unsigned | r5 r5 r8 | PTX | `` | the system folds the number put for right; the compiler writes no instruction for it |
| 16 | wide_add_unsigned | r5 r5 r8 | PTX | `add.s64 {to}, {left}, {right};` |  |
| 17 | wide_shift_left | r5 r5 n | PTX | `shl.b64 {to}, {from}, {bits};` |  |
| 18 | wide_shift_left | r5 r5 n | PTX | `shl.b64 {to}, {from}, {bits};` |  |
| 19 | wide_add | r5 f3 r5 | PTX | `add.s64 {to}, {right}, {left};` |  |
| 20 | guarded_load | f9 r4 r5 | PTX | `setp.eq.s32 %p6, {where}, 0; \| @%p6 bra $L__BB0_2; \| ld.u32 {to}, [{address}];` | the reading holds a branch |
| 21 | guarded_widen | f9 f4 r4 | PTX | `setp.eq.s32 %p7, {where}, 0; \| mov.u32 %r535, 0; \| selp.b64 {to}, {to}, {from}, %p7;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 22 | test_wide_below | f11 f4 f5 | PTX | `setp.lt.u64 {where}, {left}, {right};` |  |
| 23 | wide_select | f4 f4 n f11 | PTX | `setp.eq.s32 %p9, {where}, 0; \| selp.b64 {to}, 0, {chosen}, %p9;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 24 | wide_select | f4 f4 n f11 | PTX | `setp.eq.s32 %p10, {where}, 0; \| selp.b64 {to}, {otherwise}, {chosen}, %p10;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 25 | launch_load | r7 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 26 | launch_load | r7 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 27 | wide_multiply | r5 f4 r8 | PTX | `shl.b64 {to}, {left}, 5;` | the system folds the number put for right; the reading does not name right |
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
| 39 | sign_select | r4 n n r6 | PTX | `mov.u32 {to}, {chosen};` | the system folds the number put for otherwise; the reading does not name otherwise |
| 40 | sign_select | r4 n n r6 | PTX | `mov.u32 {to}, {chosen};` | the system folds the number put for otherwise; the reading does not name otherwise |
| 41 | word_or | r4 r0 r0 | PTX | `or.b32 {to}, {right}, {left};` |  |
| 42 | word_or | r4 r4 r0 | PTX | `or.b32 {to}, {right}, {left};` |  |
| 43 | sign_select | r1 r4 n r6 | PTX | `setp.eq.s32 %p13, {where}, 0; \| cvt.s32.s8 %r570, {chosen}; \| selp.b32 {to}, 0, %r570, %p13;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 44 | sign_select | r1 r4 n r6 | PTX | `setp.eq.s32 %p14, {where}, 0; \| cvt.s32.s8 %r574, {chosen}; \| selp.b32 {to}, 4, %r574, %p14; \| mov.u32 %r576, 4;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 45 | sign_select | r1 n n r6 | PTX | `selp.u32 {to}, {chosen}, {otherwise}, {where};` |  |
| 46 | sign_select | r1 n n r6 | PTX | `setp.eq.s32 %p16, {where}, 0; \| selp.b32 {to}, {otherwise}, 2, %p16; \| mov.u32 %r581, 2;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 47 | test_nonzero | r6 r0 | PTX | `setp.ne.s32 {where}, {value}, 0;` |  |
| 48 | word_set | r0 n | PTX | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 49 | word_set | r0 n | PTX | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 50 | subtract_first | r4 f0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd170, {to}, 32; \| cvt.u32.u64 %r584, %rd170; \| and.b32 <carry>, %r584, 1; \| mov.u32 %r586, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 51 | subtract_middle | r4 f0 r0 | PTX | `sub.s64 %rd174, {left}, {right}; \| sub.s64 {to}, %rd174, <carry>; \| shr.u64 %rd176, {to}, 32; \| cvt.u32.u64 %r587, %rd176; \| and.b32 <carry>, %r587, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 52 | subtract_last | r4 f0 r0 | PTX | `sub.s32 %r592, {left}, {right}; \| sub.s32 {to}, %r592, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 53 | product_low | r0 r0 r0 r0 | PTX | `mul.lo.s32 %r596, {right}, {left}; \| cvt.u64.u32 %rd178, %r596; \| add.s64 {to}, %rd178, {added}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 54 | product_high | r4 r0 r0 | PTX | `mul.wide.u32 %rd181, {right}, {left}; \| shr.u64 %rd182, %rd181, 32; \| cvt.u32.u64 %r600, %rd182; \| add.s32 {to}, <carry>, %r600;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 55 | add_first | r0 r0 r4 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 56 | add_last | r4 r4 f0 | PTX | `add.s32 %r605, {right}, {left}; \| add.s32 {to}, %r605, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 57 | add_first | r0 r0 r4 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 58 | add_middle | r0 r0 f0 | PTX | `add.s64 %rd194, {right}, {left}; \| add.s64 {to}, %rd194, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 59 | add_last | r0 r0 f0 | PTX | `add.s32 %r610, {right}, {left}; \| add.s32 {to}, %r610, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 60 | add_first | r0 r0 r4 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 61 | add_last | r0 r0 f0 | PTX | `add.s32 %r615, {right}, {left}; \| add.s32 {to}, %r615, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 62 | add_alone | r0 r0 r4 | PTX | `add.s32 {to}, {right}, {left};` |  |
| 63 | sign_multiply | r1 r1 r1 | PTX | `mul.lo.s32 %r622, {left}, {right}; \| cvt.s32.s8 {to}, %r622;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 64 | test_negative | r6 r1 | PTX | `and.b32 %r625, {value}, 128; \| shr.u32 {where}, %r625, 7;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 65 | word_select | r4 r4 r0 r6 | PTX | `setp.eq.s32 %p18, {where}, 0; \| selp.b32 {to}, {otherwise}, {chosen}, %p18;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 66 | word_select | r4 r4 f0 r6 | PTX | `setp.eq.s32 %p19, {where}, 0; \| selp.b32 {to}, {otherwise}, {chosen}, %p19;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 67 | word_and | r4 r4 r8 | PTX | `and.b32 {to}, {left}, {right};` |  |
| 68 | word_and | r4 r4 r8 | PTX | `and.b32 {to}, {left}, {right};` |  |
| 69 | word_set | r2 n | PTX | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 70 | word_set | r2 n | PTX | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 71 | word_or | r2 r2 r4 | PTX | `or.b32 {to}, {right}, {left};` |  |
| 72 | record_store | n r2 | PTX | `st.u32 [<record>+{offset}], {from};` | the question names no address space |
| 73 | record_store | n r2 | PTX | `st.u32 [<record>+{offset}], {from};` | the question names no address space |
| 74 | subtract_first | r4 f0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd206, {to}, 32; \| cvt.u32.u64 %r644, %rd206; \| and.b32 <carry>, %r644, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 75 | subtract_middle | r4 f0 r0 | PTX | `sub.s64 %rd210, {left}, {right}; \| sub.s64 {to}, %rd210, <carry>; \| shr.u64 %rd212, {to}, 32; \| cvt.u32.u64 %r646, %rd212; \| and.b32 <carry>, %r646, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 76 | subtract_last | r4 f0 f0 | PTX | `sub.s32 %r651, {left}, {right}; \| sub.s32 {to}, %r651, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 77 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 78 | add_middle | r0 r0 f0 | PTX | `add.s64 %rd220, {right}, {left}; \| add.s64 {to}, %rd220, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 79 | add_last | r0 f0 f0 | PTX | `add.s32 %r656, {right}, {left}; \| add.s32 {to}, %r656, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 80 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd226, {to}, 32; \| cvt.u32.u64 %r658, %rd226; \| and.b32 <carry>, %r658, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 81 | borrow_middle | r4 r0 f0 | PTX | `sub.s64 %rd230, {left}, {right}; \| sub.s64 {to}, %rd230, <carry>; \| shr.u64 %rd232, {to}, 32; \| cvt.u32.u64 %r660, %rd232; \| and.b32 <carry>, %r660, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 82 | borrow_last | r4 f0 f0 | PTX | `sub.s64 %rd236, {left}, {right}; \| sub.s64 {to}, %rd236, <carry>; \| shr.u64 %rd238, {to}, 32; \| cvt.u32.u64 %r662, %rd238; \| and.b32 <carry>, %r662, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 83 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 84 | sign_multiply | r4 r1 r1 | PTX | `mul.lo.s32 %r669, {left}, {right}; \| cvt.s32.s8 {to}, %r669;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 85 | test_negative | r6 r4 | PTX | `shr.u32 {where}, {value}, 31;` |  |
| 86 | word_select | r4 r4 r4 r6 | PTX | `setp.eq.s32 %p21, {where}, 0; \| selp.b32 {to}, {otherwise}, {chosen}, %p21;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 87 | sign_select | r4 r1 r1 r6 | PTX | `setp.eq.s32 %p22, {where}, 0; \| selp.b32 %r680, {otherwise}, {chosen}, %p22; \| cvt.s32.s8 {to}, %r680;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 88 | test_signed_differ | r6 r1 n | PTX | `and.b32 %r683, {left}, 255; \| setp.ne.s32 {where}, %r683, {right};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 89 | test_signed_differ | r6 r1 n | PTX | `and.b32 %r686, {left}, 255; \| setp.ne.s32 {where}, %r686, {right};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 90 | sign_select | r4 r4 r4 r6 | PTX | `setp.eq.s32 %p25, {where}, 0; \| selp.b32 %r691, {otherwise}, {chosen}, %p25; \| cvt.s32.s8 {to}, %r691;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 91 | subtract_first | r4 f0 r4 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd242, {to}, 32; \| cvt.u32.u64 %r693, %rd242; \| and.b32 <carry>, %r693, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 92 | subtract_middle | r4 f0 r4 | PTX | `sub.s64 %rd246, {left}, {right}; \| sub.s64 {to}, %rd246, <carry>; \| shr.u64 %rd248, {to}, 32; \| cvt.u32.u64 %r695, %rd248; \| and.b32 <carry>, %r695, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 93 | subtract_last | r4 f0 r4 | PTX | `sub.s32 %r700, {left}, {right}; \| sub.s32 {to}, %r700, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 94 | word_shift_left | r4 r4 n | PTX | `shl.b32 {to}, {from}, {bits};` |  |
| 95 | word_shift_left | r4 r4 n | PTX | `shl.b32 {to}, {from}, {bits};` |  |
| 96 | word_shift_right | r4 r4 n | PTX | `shr.u32 {to}, {from}, {bits};` |  |
| 97 | word_shift_right | r4 r4 n | PTX | `shr.u32 {to}, {from}, {bits};` |  |
| 98 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 99 | add_middle | r0 r0 r0 | PTX | `add.s64 %rd256, {right}, {left}; \| add.s64 {to}, %rd256, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 100 | add_middle | r0 f0 r0 | PTX | `add.s64 %rd262, {right}, {left}; \| add.s64 {to}, %rd262, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 101 | add_last | r0 f0 f0 | PTX | `add.s32 %r713, {right}, {left}; \| add.s32 {to}, %r713, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 102 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd268, {to}, 32; \| cvt.u32.u64 %r715, %rd268; \| and.b32 <carry>, %r715, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 103 | borrow_middle | r4 r0 r0 | PTX | `sub.s64 %rd272, {left}, {right}; \| sub.s64 {to}, %rd272, <carry>; \| shr.u64 %rd274, {to}, 32; \| cvt.u32.u64 %r717, %rd274; \| and.b32 <carry>, %r717, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 104 | borrow_middle | r4 f0 r0 | PTX | `sub.s64 %rd278, {left}, {right}; \| sub.s64 {to}, %rd278, <carry>; \| shr.u64 %rd280, {to}, 32; \| cvt.u32.u64 %r719, %rd280; \| and.b32 <carry>, %r719, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 105 | borrow_last | r4 f0 f0 | PTX | `sub.s64 %rd284, {left}, {right}; \| sub.s64 {to}, %rd284, <carry>; \| shr.u64 %rd286, {to}, 32; \| cvt.u32.u64 %r721, %rd286; \| and.b32 <carry>, %r721, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 106 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 107 | sign_negate | r4 r1 | PTX | `shl.b32 %r727, {from}, 24; \| neg.s32 %r728, %r727; \| shr.s32 {to}, %r728, 24;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 108 | sign_multiply | r4 r1 r4 | PTX | `mul.lo.s32 %r732, {left}, {right}; \| cvt.s32.s8 {to}, %r732;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 109 | sign_select | r4 r4 r1 r6 | PTX | `setp.eq.s32 %p27, {where}, 0; \| selp.b32 %r737, {otherwise}, {chosen}, %p27; \| cvt.s32.s8 {to}, %r737;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 110 | sign_select | r4 r1 r4 r6 | PTX | `setp.eq.s32 %p28, {where}, 0; \| selp.b32 %r742, {otherwise}, {chosen}, %p28; \| cvt.s32.s8 {to}, %r742;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 111 | word_copy | r0 r0 | PTX | `` | the compiler writes no instruction for it |
| 112 | sign_absolute | r1 r1 | PTX | `and.b32 %r746, {from}, 128; \| setp.eq.s32 %p29, %r746, 0; \| cvt.s32.s8 %r747, {from}; \| neg.s32 %r748, %r747; \| selp.b32 %r749, %r747, %r748, %p29; \| cvt.s32.s8 {to}, %r749;` | the compiler writes 6 instructions where the ruleset writes 1 |
| 113 | word_copy | r4 r0 | PTX | `` | the compiler writes no instruction for it |
| 114 | word_or | r4 r4 r4 | PTX | `or.b32 {to}, {right}, {left};` |  |
| 115 | sign_select | r4 r4 n r6 | PTX | `setp.eq.s32 %p30, {where}, 0; \| cvt.s32.s8 %r757, {chosen}; \| selp.b32 {to}, 0, %r757, %p30;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 116 | sign_select | r4 r4 n r6 | PTX | `setp.eq.s32 %p31, {where}, 0; \| cvt.s32.s8 %r761, {chosen}; \| selp.b32 {to}, {otherwise}, %r761, %p31;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 117 | test_signed_greater | r6 r1 r1 | PTX | `shl.b32 %r765, {left}, 24; \| shl.b32 %r766, {right}, 24; \| setp.gt.s32 {where}, %r765, %r766;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 118 | test_signed_differ | r6 r1 r1 | PTX | `xor.b32 %r770, {right}, {left}; \| and.b32 %r771, %r770, 255; \| setp.ne.s32 {where}, %r771, 0;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 119 | sign_select | r1 r4 r4 r6 | PTX | `setp.eq.s32 %p34, {where}, 0; \| selp.b32 %r776, {otherwise}, {chosen}, %p34; \| cvt.s32.s8 {to}, %r776;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 120 | sign_absolute | r0 r1 | PTX | `and.b32 %r779, {from}, 128; \| setp.eq.s32 %p35, %r779, 0; \| cvt.s32.s8 %r780, {from}; \| neg.s32 %r781, %r780; \| selp.b32 {to}, %r780, %r781, %p35;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 121 | subtract_alone | r4 f0 r0 | PTX | `sub.s32 {to}, {left}, {right};` |  |
| 122 | word_set | r0 r8 | PTX | `mov.u32 {to}, {value};` |  |
| 123 | word_set | r0 r8 | PTX | `mov.u32 {to}, {value};` |  |
| 124 | sign_set | r1 n | PTX | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 125 | sign_set | r1 n | PTX | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 126 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd290, {to}, 32; \| cvt.u32.u64 %r788, %rd290; \| and.b32 <carry>, %r788, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 127 | borrow_middle | r4 r0 r0 | PTX | `sub.s64 %rd294, {left}, {right}; \| sub.s64 {to}, %rd294, <carry>; \| shr.u64 %rd296, {to}, 32; \| cvt.u32.u64 %r790, %rd296; \| and.b32 <carry>, %r790, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 128 | borrow_middle | r4 r0 f0 | PTX | `sub.s64 %rd300, {left}, {right}; \| sub.s64 {to}, %rd300, <carry>; \| shr.u64 %rd302, {to}, 32; \| cvt.u32.u64 %r792, %rd302; \| and.b32 <carry>, %r792, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 129 | borrow_last | r4 r0 f0 | PTX | `sub.s64 %rd306, {left}, {right}; \| sub.s64 {to}, %rd306, <carry>; \| shr.u64 %rd308, {to}, 32; \| cvt.u32.u64 %r794, %rd308; \| and.b32 <carry>, %r794, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 130 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 131 | subtract_alone | r4 r1 r8 | PTX | `cvt.s32.s8 %r800, {left}; \| add.s32 {to}, %r800, -{right};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 132 | subtract_alone | r4 r1 r8 | PTX | `cvt.s32.s8 %r803, {left}; \| add.s32 {to}, %r803, -{right};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 133 | word_set | r4 n | PTX | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 134 | word_set | r4 n | PTX | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 135 | word_set | r4 r8 | PTX | `mov.u32 {to}, {value};` |  |
| 136 | word_set | r4 r8 | PTX | `mov.u32 {to}, {value};` |  |
| 137 | product_low | r4 r0 r4 r4 | PTX | `mul.lo.s32 %r809, {right}, {left}; \| cvt.u64.u32 %rd310, %r809; \| add.s64 {to}, %rd310, {added}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 138 | product_high | r4 r0 r4 | PTX | `mul.wide.u32 %rd313, {right}, {left}; \| shr.u64 %rd314, %rd313, 32; \| cvt.u32.u64 %r813, %rd314; \| add.s32 {to}, <carry>, %r813;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 139 | add_alone | r4 r4 r4 | PTX | `add.s32 {to}, {right}, {left};` |  |
| 140 | add_first | r4 r4 r4 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 141 | add_last | r4 r4 f0 | PTX | `add.s32 %r821, {right}, {left}; \| add.s32 {to}, %r821, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 142 | word_select | r4 f0 r8 r6 | PTX | `setp.eq.s32 %p37, {where}, 0; \| selp.b32 {to}, {otherwise}, {chosen}, %p37;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 143 | word_select | r4 f0 r8 r6 | PTX | `setp.eq.s32 %p38, {where}, 0; \| selp.b32 {to}, {otherwise}, {chosen}, %p38;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 144 | borrow_first | r4 r0 r4 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd322, {to}, 32; \| cvt.u32.u64 %r829, %rd322; \| and.b32 <carry>, %r829, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 145 | borrow_middle | r4 f0 r4 | PTX | `sub.s64 %rd326, {left}, {right}; \| sub.s64 {to}, %rd326, <carry>; \| shr.u64 %rd328, {to}, 32; \| cvt.u32.u64 %r831, %rd328; \| and.b32 <carry>, %r831, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 146 | borrow_last | r4 f0 r4 | PTX | `sub.s64 %rd332, {left}, {right}; \| sub.s64 {to}, %rd332, <carry>; \| shr.u64 %rd334, {to}, 32; \| cvt.u32.u64 %r833, %rd334; \| and.b32 <carry>, %r833, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 147 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 148 | add_alone | r4 r4 r8 | PTX | `add.s32 {to}, {left}, {right};` |  |
| 149 | add_alone | r4 r4 r8 | PTX | `add.s32 {to}, {left}, {right};` |  |
| 150 | add_first | r4 r4 r4 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 151 | add_last | r4 r4 r4 | PTX | `add.s32 %r845, {right}, {left}; \| add.s32 {to}, %r845, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 152 | word_copy | r0 r4 | PTX | `` | the compiler writes no instruction for it |
| 153 | sign_select | r1 r1 n r6 | PTX | `setp.eq.s32 %p40, {where}, 0; \| cvt.s32.s8 %r850, {chosen}; \| selp.b32 {to}, 0, %r850, %p40;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 154 | sign_select | r1 r1 n r6 | PTX | `setp.eq.s32 %p41, {where}, 0; \| cvt.s32.s8 %r854, {chosen}; \| selp.b32 {to}, {otherwise}, %r854, %p41;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 155 | launch_load | r5 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 156 | launch_load | r5 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 157 | count_add | r5 | PTX | `atom.add.u32 %r856, [{address}], 1;` | the question names no address space |
| 158 | record_store | n f0 | PTX | `st.u32 [<record>+{offset}], {from};` | the question names no address space |
| 159 | record_store | n f0 | PTX | `st.u32 [<record>+{offset}], {from};` | the question names no address space |
| 160 | borrow_alone | r4 r4 r8 | PTX | `add.s64 {to}, {left}, -{right}; \| shr.u64 %rd348, {to}, 32; \| cvt.u32.u64 %r859, %rd348; \| and.b32 <carry>, %r859, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 161 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 162 | borrow_alone | r4 r4 r8 | PTX | `add.s64 {to}, {left}, -{right}; \| shr.u64 %rd351, {to}, 32; \| cvt.u32.u64 %r864, %rd351; \| and.b32 <carry>, %r864, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 163 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 164 | test_zero | r6 r4 | PTX | `setp.eq.s32 {where}, {value}, 0;` |  |
| 165 | word_funnel_right | r4 r4 r4 n | PTX | `bfi.b64 %rd354, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd354, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 166 | word_funnel_right | r4 r4 r4 n | PTX | `bfi.b64 %rd358, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd358, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 167 | word_funnel_right | r4 f0 r4 n | PTX | `bfi.b64 %rd362, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd362, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 168 | word_funnel_right | r4 f0 r4 n | PTX | `bfi.b64 %rd366, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd366, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 169 | subtract_alone | r4 r4 r8 | PTX | `add.s32 {to}, {left}, -{right};` |  |
| 170 | subtract_alone | r4 r4 r8 | PTX | `add.s32 {to}, {left}, -{right};` |  |
| 171 | borrow_first | r4 r4 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd371, {to}, 32; \| cvt.u32.u64 %r875, %rd371; \| and.b32 <carry>, %r875, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 172 | borrow_middle | r4 r4 r0 | PTX | `sub.s64 %rd375, {left}, {right}; \| sub.s64 {to}, %rd375, <carry>; \| shr.u64 %rd377, {to}, 32; \| cvt.u32.u64 %r877, %rd377; \| and.b32 <carry>, %r877, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 173 | borrow_last | r4 r4 f0 | PTX | `sub.s64 %rd381, {left}, {right}; \| sub.s64 {to}, %rd381, <carry>; \| shr.u64 %rd383, {to}, 32; \| cvt.u32.u64 %r879, %rd383; \| and.b32 <carry>, %r879, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 174 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 175 | predicate_and | r6 r6 r6 | PTX | `and.pred {where}, {left}, {right};` |  |
| 176 | word_and | r4 r4 r4 | PTX | `and.b32 {to}, {right}, {left};` |  |
| 177 | borrow_first | r4 r4 r4 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd387, {to}, 32; \| cvt.u32.u64 %r890, %rd387; \| and.b32 <carry>, %r890, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 178 | borrow_middle | r4 r4 r4 | PTX | `sub.s64 %rd391, {left}, {right}; \| sub.s64 {to}, %rd391, <carry>; \| shr.u64 %rd393, {to}, 32; \| cvt.u32.u64 %r892, %rd393; \| and.b32 <carry>, %r892, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 179 | borrow_last | r4 r4 r4 | PTX | `sub.s64 %rd397, {left}, {right}; \| sub.s64 {to}, %rd397, <carry>; \| shr.u64 %rd399, {to}, 32; \| cvt.u32.u64 %r894, %rd399; \| and.b32 <carry>, %r894, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 180 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 181 | word_funnel_right | r4 r4 f0 n | PTX | `bfi.b64 %rd402, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd402, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 182 | word_funnel_right | r4 r4 f0 n | PTX | `bfi.b64 %rd406, {high}, {low}, 32, 32; \| shr.u64 {to}, %rd406, {bits};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 183 | word_copy | r4 f0 | PTX | `` | the compiler writes no instruction for it |
| 184 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 185 | add_middle | r0 r0 r0 | PTX | `add.s64 %rd415, {right}, {left}; \| add.s64 {to}, %rd415, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 186 | add_middle | r0 r0 f0 | PTX | `add.s64 %rd421, {right}, {left}; \| add.s64 {to}, %rd421, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 187 | add_last | r0 r0 f0 | PTX | `add.s32 %r903, {right}, {left}; \| add.s32 {to}, %r903, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 188 | word_and | r0 r0 r8 | PTX | `and.b32 {to}, {left}, {right};` |  |
| 189 | word_and | r0 r0 r8 | PTX | `and.b32 {to}, {left}, {right};` |  |
| 190 | word_xor | r0 r4 r4 | PTX | `xor.b32 {to}, {right}, {left};` |  |
| 191 | predicate_xor | r6 r6 r6 | PTX | `xor.pred {where}, {left}, {right};` |  |
| 192 | word_and | r0 r4 r4 | PTX | `and.b32 {to}, {right}, {left};` |  |
| 193 | subtract_first | r4 f0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd427, {to}, 32; \| cvt.u32.u64 %r918, %rd427; \| and.b32 <carry>, %r918, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 194 | subtract_last | r4 f0 r0 | PTX | `sub.s32 %r923, {left}, {right}; \| sub.s32 {to}, %r923, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 195 | test_wide_below_and | f11 f4 f5 f11 | PTX | `setp.lt.u64 %p54, {left}, {right}; \| and.pred {where}, %p54, {also};` | the compiler writes 2 instructions where the ruleset writes 1 |
| 196 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 197 | add_last | r0 r0 r0 | PTX | `add.s32 %r930, {right}, {left}; \| add.s32 {to}, %r930, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 198 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd437, {to}, 32; \| cvt.u32.u64 %r932, %rd437; \| and.b32 <carry>, %r932, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 199 | borrow_last | r4 r0 r0 | PTX | `sub.s64 %rd441, {left}, {right}; \| sub.s64 {to}, %rd441, <carry>; \| shr.u64 %rd443, {to}, 32; \| cvt.u32.u64 %r934, %rd443; \| and.b32 <carry>, %r934, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 200 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 201 | subtract_first | r4 f0 r4 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd447, {to}, 32; \| cvt.u32.u64 %r939, %rd447; \| and.b32 <carry>, %r939, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 202 | subtract_last | r4 f0 r4 | PTX | `sub.s32 %r944, {left}, {right}; \| sub.s32 {to}, %r944, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 203 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 204 | add_middle | r0 r0 r0 | PTX | `add.s64 %rd455, {right}, {left}; \| add.s64 {to}, %rd455, <carry>; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 3 instructions where the ruleset writes 1 |
| 205 | add_last | r0 f0 f0 | PTX | `add.s32 %r949, {right}, {left}; \| add.s32 {to}, %r949, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 206 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd461, {to}, 32; \| cvt.u32.u64 %r951, %rd461; \| and.b32 <carry>, %r951, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 207 | borrow_middle | r4 r0 r0 | PTX | `sub.s64 %rd465, {left}, {right}; \| sub.s64 {to}, %rd465, <carry>; \| shr.u64 %rd467, {to}, 32; \| cvt.u32.u64 %r953, %rd467; \| and.b32 <carry>, %r953, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 208 | borrow_last | r4 f0 f0 | PTX | `sub.s64 %rd471, {left}, {right}; \| sub.s64 {to}, %rd471, <carry>; \| shr.u64 %rd473, {to}, 32; \| cvt.u32.u64 %r955, %rd473; \| and.b32 <carry>, %r955, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 209 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 210 | launch_load | f6 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 211 | launch_load | f6 n | PTX | `ld.u64 {to}, [<launch>+{offset}];` | the ruleset names no fixed register launch |
| 212 | wide_unpack | r0 r0 f1 | PTX | `shr.u64 {high}, {low}, 32;` | the reading does not name from |
| 213 | test_wide_nonzero | r6 f1 | PTX | `setp.ne.s64 {where}, {value}, 0;` |  |
| 214 | word_multiply | r4 r4 r8 | PTX | `shl.b32 {to}, {left}, 1;` | the system folds the number put for right; the reading does not name right |
| 215 | word_multiply | r4 r4 r8 | PTX | `mul.lo.s32 {to}, {left}, {right};` |  |
| 216 | wide_multiply_word | r5 r4 n | PTX | `mul.wide.u32 {to}, {left}, {right};` |  |
| 217 | wide_multiply_word | r5 r4 n | PTX | `mul.wide.u32 {to}, {left}, {right};` |  |
| 218 | wide_add | r5 f6 r5 | PTX | `add.s64 {to}, {right}, {left};` |  |
| 219 | global_load | r0 r5 n | PTX | `ld.u32 {to}, [{address}+{offset}];` | the question names no address space |
| 220 | global_load | r0 r5 n | PTX | `ld.u32 {to}, [{address}+{offset}];` | the question names no address space |
| 221 | add_first | r0 r0 r0 | PTX | `add.s64 {to}, {right}, {left}; \| shr.u64 <carry>, {to}, 32;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 222 | add_last | r0 r0 f0 | PTX | `add.s32 %r972, {right}, {left}; \| add.s32 {to}, %r972, <carry>;` | the compiler writes 2 instructions where the ruleset writes 1 |
| 223 | borrow_first | r4 r0 r0 | PTX | `sub.s64 {to}, {left}, {right}; \| shr.u64 %rd495, {to}, 32; \| cvt.u32.u64 %r974, %rd495; \| and.b32 <carry>, %r974, 1;` | the compiler writes 4 instructions where the ruleset writes 1 |
| 224 | borrow_last | r4 r0 f0 | PTX | `sub.s64 %rd499, {left}, {right}; \| sub.s64 {to}, %rd499, <carry>; \| shr.u64 %rd501, {to}, 32; \| cvt.u32.u64 %r976, %rd501; \| and.b32 <carry>, %r976, 1;` | the compiler writes 5 instructions where the ruleset writes 1 |
| 225 | borrow_read | r4 r6 | PTX | `neg.s32 {borrow}, <carry>; \| setp.ne.s32 {where}, <carry>, 0;` | the ruleset names no fixed register carry |
| 4097 | launch_load | f2 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4098 | launch_load | f2 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4099 | wide_multiply | r5 f1 r8 | SASS | `IMAD R254, {left}.hi, 0x98, RZ; \| IMAD.WIDE.U32 R26, {left}, 0x98, RZ; \| IMAD R254, {left}, {right}.hi, R254; \| IMAD.IADD {to}.hi, R27, 0x1, R254; \| IMAD.MOV.U32 {to}, RZ, RZ, R26;` | the system folds the number put for right; the compiler writes 5 instructions where the ruleset writes 3 |
| 4100 | wide_multiply | r5 f1 r8 | SASS | `IMAD R254, {left}.hi, 0x94, RZ; \| IMAD.WIDE.U32 R26, {left}, 0x94, RZ; \| IMAD R254, {left}, {right}.hi, R254; \| IMAD.IADD {to}.hi, R27, 0x1, R254; \| IMAD.MOV.U32 {to}, RZ, RZ, R26;` | the system folds the number put for right; the compiler writes 5 instructions where the ruleset writes 3 |
| 4101 | wide_multiply | r5 f1 r8 | SASS, numbers loaded | `IMAD R254, {left}.hi, {right}, RZ; \| IMAD.WIDE.U32 R28, {left}, {right}, RZ; \| IMAD R254, {left}, {right}.hi, R254; \| IMAD.IADD {to}.hi, R29, 0x1, R254; \| IMAD.MOV.U32 {to}, RZ, RZ, R28;` | the compiler writes 5 instructions where the ruleset writes 3 |
| 4102 | wide_add | f2 f2 r5 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` |  |
| 4103 | launch_load | f3 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4104 | launch_load | f3 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4105 | test_wide_nonzero | f9 f3 | SASS | `ISETP.NE.U32.AND P6, PT, {value}, RZ, PT; \| ISETP.NE.AND.EX {where}, PT, {value}.hi, RZ, PT, P6;` |  |
| 4106 | launch_load | f5 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4107 | launch_load | f5 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4108 | test_wide_equal | f10 f5 n | SASS | `ISETP.EQ.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.EQ.AND.EX {where}, PT, {left}.hi, {right}.hi, PT, P6;` |  |
| 4109 | test_wide_equal | f10 f5 n | SASS | `ISETP.EQ.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.EQ.AND.EX {where}, PT, {left}.hi, {right}.hi, PT, P6;` |  |
| 4110 | test_wide_equal | f10 f5 n | SASS, numbers loaded | `ISETP.EQ.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.EQ.AND.EX {where}, PT, {left}.hi, {right}.hi, PT, P6;` |  |
| 4111 | wide_select | f4 n f1 f10 | SASS | `SEL {to}, {otherwise}, RZ, !{where}; \| SEL {to}.hi, {otherwise}.hi, {chosen}.hi, !{where};` | the system folds the number put for chosen; the reading does not name chosen |
| 4112 | wide_select | f4 n f1 f10 | SASS | `SEL {to}, {otherwise}, {chosen}, !{where}; \| SEL {to}.hi, {otherwise}.hi, {chosen}.hi, !{where};` |  |
| 4113 | wide_select | f4 n f1 f10 | SASS, numbers loaded | `SEL {to}, {chosen}, {otherwise}, {where}; \| SEL {to}.hi, {chosen}.hi, {otherwise}.hi, {where};` | the machine file holds no form for it |
| 4114 | wide_add_unsigned | r5 r5 r8 | SASS | `IADD3 {to}, P6, RZ, {left}, RZ; \| IADD3.X {to}.hi, {left}.hi, {right}.hi, RZ, P6, !PT;` | the system folds the number put for right; the reading does not name right |
| 4115 | wide_add_unsigned | r5 r5 r8 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ; \| IADD3.X {to}.hi, {left}.hi, {right}.hi, RZ, P6, !PT;` |  |
| 4116 | wide_add_unsigned | r5 r5 r8 | SASS, numbers loaded | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` | the machine file holds no form for it |
| 4117 | wide_shift_left | r5 r5 n | SASS | `SHF.L.U64.HI {to}.hi, {from}, {bits}, {from}.hi; \| IMAD.SHL.U32 {to}, {from}, 0x4, RZ;` |  |
| 4118 | wide_shift_left | r5 r5 n | SASS | `SHF.L.U64.HI {to}.hi, {from}, {bits}, {from}.hi; \| IMAD.SHL.U32 {to}, {from}, 0x8, RZ;` |  |
| 4119 | wide_shift_left | r5 r5 n | SASS, numbers loaded | `SHF.L.U64.HI {to}.hi, {from}, {bits}, {from}.hi; \| SHF.L.U32 {to}, {from}, {bits}, RZ;` |  |
| 4120 | wide_add | r5 f3 r5 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` |  |
| 4121 | guarded_load | f9 r4 r5 | SASS | `@!{where} BRA 0x7d60; \| LDG.E.CONSTANT {to}, [{address}.64];` | the reading holds a branch |
| 4122 | guarded_widen | f9 f4 r4 | SASS | `SEL {to}, {from}, {to}, {where}; \| SEL {to}.hi, {to}.hi, RZ, !{where};` |  |
| 4123 | test_wide_below | f11 f4 f5 | SASS | `ISETP.LT.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.LT.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, PT, P6;` |  |
| 4124 | wide_select | f4 f4 n f11 | SASS | `SEL {to}, {chosen}, RZ, {where}; \| SEL {to}.hi, {chosen}.hi, {otherwise}.hi, {where};` | the system folds the number put for otherwise; the reading does not name otherwise |
| 4125 | wide_select | f4 f4 n f11 | SASS | `SEL {to}, {chosen}, {otherwise}, {where}; \| SEL {to}.hi, {chosen}.hi, {otherwise}.hi, {where};` |  |
| 4126 | wide_select | f4 f4 n f11 | SASS, numbers loaded | `SEL {to}, {chosen}, {otherwise}, {where}; \| SEL {to}.hi, {chosen}.hi, {otherwise}.hi, {where};` |  |
| 4127 | launch_load | r7 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4128 | launch_load | r7 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4129 | wide_multiply | r5 f4 r8 | SASS | `IMAD.SHL.U32 R254, {left}.hi, 0x20, RZ; \| IMAD.WIDE.U32 R26, {left}, 0x20, RZ; \| IMAD R254, {left}, {right}.hi, R254; \| IMAD.IADD {to}.hi, R27, 0x1, R254; \| IMAD.MOV.U32 {to}, RZ, RZ, R26;` | the system folds the number put for right; the compiler writes 5 instructions where the ruleset writes 3 |
| 4130 | wide_multiply | r5 f4 r8 | SASS | `IMAD R254, {left}.hi, 0x1c, RZ; \| IMAD.WIDE.U32 R26, {left}, 0x1c, RZ; \| IMAD R254, {left}, {right}.hi, R254; \| IMAD.IADD {to}.hi, R27, 0x1, R254; \| IMAD.MOV.U32 {to}, RZ, RZ, R26;` | the system folds the number put for right; the compiler writes 5 instructions where the ruleset writes 3 |
| 4131 | wide_multiply | r5 f4 r8 | SASS, numbers loaded | `IMAD R254, {left}.hi, {right}, RZ; \| IMAD.WIDE.U32 R28, {left}, {right}, RZ; \| IMAD R254, {left}, {right}.hi, R254; \| IMAD.IADD {to}.hi, R29, 0x1, R254; \| IMAD.MOV.U32 {to}, RZ, RZ, R28;` | the compiler writes 5 instructions where the ruleset writes 3 |
| 4132 | wide_add | r7 r7 r5 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` |  |
| 4133 | word_multiply_add | f8 f7 r8 f8 | SASS | `IMAD {to}, {left}, {right}, {added};` |  |
| 4134 | word_multiply_add | f8 f7 r8 f8 | SASS | `IMAD {to}, {left}, {right}, {added};` |  |
| 4135 | word_multiply_add | f8 f7 r8 f8 | SASS, numbers loaded | `IMAD {to}, {left}, {right}, {added};` |  |
| 4136 | global_load | r3 r7 n | SASS | `LDG.E.CONSTANT {to}, [{address}.64+{offset}];` |  |
| 4137 | global_load | r3 r7 n | SASS | `LDG.E.CONSTANT {to}, [{address}.64+{offset}];` |  |
| 4138 | word_copy | r0 r3 | SASS | `` | the compiler writes no instruction for it |
| 4139 | word_and | r4 r0 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4140 | word_and | r4 r0 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4141 | word_and | r4 r0 r8 | SASS, numbers loaded | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4142 | test_nonzero | r6 r4 | SASS | `ISETP.NE.AND {where}, PT, {value}, RZ, PT;` |  |
| 4143 | word_select | r0 r4 r0 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4144 | sign_select | r4 n n r6 | SASS | `` | the system folds the number put for otherwise; the compiler writes no instruction for it |
| 4145 | sign_select | r4 n n r6 | SASS | `` | the system folds the number put for otherwise; the compiler writes no instruction for it |
| 4146 | sign_select | r4 n n r6 | SASS, numbers loaded | `SEL {to}, {chosen}, {otherwise}, {where};` | the machine file holds no form for it |
| 4147 | word_or | r4 r0 r0 | SASS | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` |  |
| 4148 | word_or | r4 r4 r0 | SASS | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` |  |
| 4149 | sign_select | r1 r4 n r6 | SASS | `SEL {to}, {chosen}, RZ, {where};` | the system folds the number put for otherwise; the reading does not name otherwise |
| 4150 | sign_select | r1 r4 n r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4151 | sign_select | r1 r4 n r6 | SASS, numbers loaded | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4152 | sign_select | r1 n n r6 | SASS | `SEL {to}, RZ, {chosen}, !{where};` | the system folds the number put for otherwise; the reading does not name otherwise |
| 4153 | sign_select | r1 n n r6 | SASS | `SEL {to}, R17, {otherwise}, {where};` | the system folds the number put for chosen; the reading does not name chosen |
| 4154 | sign_select | r1 n n r6 | SASS, numbers loaded | `SEL {to}, {chosen}, {otherwise}, {where};` | the machine file holds no form for it |
| 4155 | test_nonzero | r6 r0 | SASS | `ISETP.NE.AND {where}, PT, {value}, RZ, PT;` |  |
| 4156 | word_set | r0 n | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4157 | word_set | r0 n | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4158 | word_set | r0 n | SASS, numbers loaded | `` | the compiler writes no instruction for it |
| 4159 | subtract_first | r4 f0 r0 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4160 | subtract_middle | r4 f0 r0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4161 | subtract_last | r4 f0 r0 | SASS | `IMAD.X {to}, {left}, 0x1, ~{right}, P6;` |  |
| 4162 | product_low | r0 r0 r0 r0 | SASS | `IMAD R254, {left}, {right}, RZ; \| IADD3 {to}, P6, R254, {added}, RZ;` |  |
| 4163 | product_high | r4 r0 r0 | SASS | `IMAD.HI.U32 R254, {left}, {right}, RZ; \| IMAD.X {to}, R254, 0x1, <zero>, P6;` |  |
| 4164 | add_first | r0 r0 r4 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ;` |  |
| 4165 | add_last | r4 r4 f0 | SASS | `IMAD.X {to}, {left}, 0x1, {right}, P6;` |  |
| 4166 | add_middle | r0 r0 f0 | SASS | `IADD3.X {to}, P6, {left}, {right}, RZ, P6, !PT;` |  |
| 4167 | add_last | r0 r0 f0 | SASS | `IMAD.X {to}, {left}, 0x1, {right}, P6;` |  |
| 4168 | add_alone | r0 r0 r4 | SASS | `IMAD.IADD {to}, {left}, 0x1, {right};` |  |
| 4169 | sign_multiply | r1 r1 r1 | SASS | `IMAD {to}, {left}, {right}, RZ;` |  |
| 4170 | test_negative | r6 r1 | SASS | `ISETP.LT.AND {where}, PT, {value}, RZ, PT;` |  |
| 4171 | word_select | r4 r4 r0 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4172 | word_select | r4 r4 f0 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4173 | word_and | r4 r4 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4174 | word_and | r4 r4 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4175 | word_and | r4 r4 r8 | SASS, numbers loaded | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4176 | word_set | r2 n | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4177 | word_set | r2 n | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4178 | word_set | r2 n | SASS, numbers loaded | `` | the compiler writes no instruction for it |
| 4179 | word_or | r2 r2 r4 | SASS | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` |  |
| 4180 | record_store | n r2 | SASS | `STG.E [<record>.64+{offset}], {from};` |  |
| 4181 | record_store | n r2 | SASS | `STG.E [<record>.64+{offset}], {from};` |  |
| 4182 | subtract_last | r4 f0 f0 | SASS | `IMAD.X {to}, {left}, 0x1, ~{right}, P6;` |  |
| 4183 | add_first | r0 r0 r0 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ;` |  |
| 4184 | add_last | r0 f0 f0 | SASS | `IMAD.X {to}, {left}, 0x1, {right}, P6;` |  |
| 4185 | borrow_first | r4 r0 r0 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4186 | borrow_middle | r4 r0 f0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4187 | borrow_last | r4 f0 f0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4188 | borrow_read | r4 r6 | SASS | `IMAD.X {borrow}, <zero>, 0x1, ~<zero>, P6; \| ISETP.NE.U32.AND {where}, PT, {borrow}, RZ, PT;` |  |
| 4189 | sign_multiply | r4 r1 r1 | SASS | `IMAD {to}, {left}, {right}, RZ;` |  |
| 4190 | test_negative | r6 r4 | SASS | `ISETP.LT.AND {where}, PT, {value}, RZ, PT;` |  |
| 4191 | word_select | r4 r4 r4 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4192 | sign_select | r4 r1 r1 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4193 | test_signed_differ | r6 r1 n | SASS | `ISETP.NE.AND {where}, PT, {left}, RZ, PT;` | the system folds the number put for right; the reading does not name right |
| 4194 | test_signed_differ | r6 r1 n | SASS | `ISETP.NE.AND {where}, PT, {left}, {right}, PT;` |  |
| 4195 | test_signed_differ | r6 r1 n | SASS, numbers loaded | `ISETP.NE.AND {where}, PT, {left}, {right}, PT;` |  |
| 4196 | sign_select | r4 r4 r4 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4197 | subtract_first | r4 f0 r4 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4198 | subtract_middle | r4 f0 r4 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4199 | subtract_last | r4 f0 r4 | SASS | `IMAD.X {to}, {left}, 0x1, ~{right}, P6;` |  |
| 4200 | word_shift_left | r4 r4 n | SASS | `IMAD.SHL.U32 {to}, {from}, 0x8, RZ;` | the system folds the number put for bits; the reading does not name bits |
| 4201 | word_shift_left | r4 r4 n | SASS | `IMAD.SHL.U32 {to}, {from}, 0x4, RZ;` | the system folds the number put for bits; the reading does not name bits |
| 4202 | word_shift_left | r4 r4 n | SASS, numbers loaded | `SHF.L.U32 {to}, {from}, {bits}, RZ;` |  |
| 4203 | word_shift_right | r4 r4 n | SASS | `SHF.R.U32.HI {to}, RZ, {bits}, {from};` |  |
| 4204 | word_shift_right | r4 r4 n | SASS | `SHF.R.U32.HI {to}, RZ, {bits}, {from};` |  |
| 4205 | word_shift_right | r4 r4 n | SASS, numbers loaded | `SHF.R.U32.HI {to}, RZ, {bits}, {from};` |  |
| 4206 | add_middle | r0 r0 r0 | SASS | `IADD3.X {to}, P6, {left}, {right}, RZ, P6, !PT;` |  |
| 4207 | add_middle | r0 f0 r0 | SASS | `IADD3.X {to}, P6, {left}, {right}, RZ, P6, !PT;` |  |
| 4208 | borrow_middle | r4 r0 r0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4209 | borrow_middle | r4 f0 r0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4210 | sign_negate | r4 r1 | SASS | `IMAD.MOV {to}, RZ, RZ, -{from};` |  |
| 4211 | sign_multiply | r4 r1 r4 | SASS | `IMAD {to}, {left}, {right}, RZ;` |  |
| 4212 | sign_select | r4 r4 r1 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4213 | sign_select | r4 r1 r4 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4214 | word_copy | r0 r0 | SASS | `` | the compiler writes no instruction for it |
| 4215 | sign_absolute | r1 r1 | SASS | `IABS {to}, {from};` |  |
| 4216 | word_copy | r4 r0 | SASS | `` | the compiler writes no instruction for it |
| 4217 | word_or | r4 r4 r4 | SASS | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` |  |
| 4218 | sign_select | r4 r4 n r6 | SASS | `SEL {to}, {chosen}, RZ, {where};` | the system folds the number put for otherwise; the reading does not name otherwise |
| 4219 | sign_select | r4 r4 n r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4220 | sign_select | r4 r4 n r6 | SASS, numbers loaded | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4221 | test_signed_greater | r6 r1 r1 | SASS | `ISETP.GT.AND {where}, PT, {left}, {right}, PT;` |  |
| 4222 | test_signed_differ | r6 r1 r1 | SASS | `ISETP.NE.AND {where}, PT, {left}, {right}, PT;` |  |
| 4223 | sign_select | r1 r4 r4 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4224 | sign_absolute | r0 r1 | SASS | `IABS {to}, {from};` |  |
| 4225 | subtract_alone | r4 f0 r0 | SASS | `IMAD.IADD {to}, {left}, 0x1, -{right};` |  |
| 4226 | word_set | r0 r8 | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4227 | word_set | r0 r8 | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4228 | word_set | r0 r8 | SASS, numbers loaded | `` | the compiler writes no instruction for it |
| 4229 | sign_set | r1 n | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4230 | sign_set | r1 n | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4231 | sign_set | r1 n | SASS, numbers loaded | `` | the compiler writes no instruction for it |
| 4232 | borrow_last | r4 r0 f0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4233 | subtract_alone | r4 r1 r8 | SASS | `IADD3 {to}, {left}, -{right}, RZ;` |  |
| 4234 | subtract_alone | r4 r1 r8 | SASS | `IADD3 {to}, {left}, -{right}, RZ;` |  |
| 4235 | subtract_alone | r4 r1 r8 | SASS, numbers loaded | `IMAD.IADD {to}, {left}, 0x1, -{right};` | the machine file holds no form for it |
| 4236 | word_set | r4 n | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4237 | word_set | r4 n | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4238 | word_set | r4 n | SASS, numbers loaded | `` | the compiler writes no instruction for it |
| 4239 | word_set | r4 r8 | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4240 | word_set | r4 r8 | SASS | `` | the system folds the number put for value; the compiler writes no instruction for it |
| 4241 | word_set | r4 r8 | SASS, numbers loaded | `` | the compiler writes no instruction for it |
| 4242 | product_low | r4 r0 r4 r4 | SASS | `IMAD R254, {left}, {right}, RZ; \| IADD3 {to}, P6, R254, {added}, RZ;` |  |
| 4243 | product_high | r4 r0 r4 | SASS | `IMAD.HI.U32 R254, {left}, {right}, RZ; \| IMAD.X {to}, R254, 0x1, <zero>, P6;` |  |
| 4244 | add_alone | r4 r4 r4 | SASS | `IMAD.IADD {to}, {left}, 0x1, {right};` |  |
| 4245 | add_first | r4 r4 r4 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ;` |  |
| 4246 | word_select | r4 f0 r8 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4247 | word_select | r4 f0 r8 r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4248 | word_select | r4 f0 r8 r6 | SASS, numbers loaded | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4249 | borrow_first | r4 r0 r4 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4250 | borrow_middle | r4 f0 r4 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4251 | borrow_last | r4 f0 r4 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4252 | add_alone | r4 r4 r8 | SASS | `IADD3 {to}, {left}, {right}, RZ;` |  |
| 4253 | add_alone | r4 r4 r8 | SASS | `IADD3 {to}, {left}, {right}, RZ;` |  |
| 4254 | add_alone | r4 r4 r8 | SASS, numbers loaded | `IMAD.IADD {to}, {left}, 0x1, {right};` | the machine file holds no form for it |
| 4255 | add_last | r4 r4 r4 | SASS | `IMAD.X {to}, {left}, 0x1, {right}, P6;` |  |
| 4256 | word_copy | r0 r4 | SASS | `` | the compiler writes no instruction for it |
| 4257 | sign_select | r1 r1 n r6 | SASS | `SEL {to}, {chosen}, RZ, {where};` | the system folds the number put for otherwise; the reading does not name otherwise |
| 4258 | sign_select | r1 r1 n r6 | SASS | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4259 | sign_select | r1 r1 n r6 | SASS, numbers loaded | `SEL {to}, {chosen}, {otherwise}, {where};` |  |
| 4260 | launch_load | r5 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4261 | launch_load | r5 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4262 | count_add | r5 | SASS | `VOTEU.ANY UR6, UPT, PT; \| UFLO.U32 UR7, UR6; \| POPC R254, UR6; \| ISETP.EQ.U32.AND P6, PT, R0, UR7, PT; \| @P6 RED.E.ADD.STRONG.GPU [{address}.64], R254;` | the compiler writes 5 instructions where the ruleset writes 2 |
| 4263 | record_store | n f0 | SASS | `STG.E [<record>.64+{offset}], {from};` |  |
| 4264 | record_store | n f0 | SASS | `STG.E [<record>.64+{offset}], {from};` |  |
| 4265 | borrow_alone | r4 r4 r8 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4266 | borrow_alone | r4 r4 r8 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4267 | borrow_alone | r4 r4 r8 | SASS, numbers loaded | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4268 | test_zero | r6 r4 | SASS | `ISETP.EQ.AND {where}, PT, {value}, RZ, PT;` |  |
| 4269 | word_funnel_right | r4 r4 r4 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4270 | word_funnel_right | r4 r4 r4 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4271 | word_funnel_right | r4 r4 r4 n | SASS, numbers loaded | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4272 | word_funnel_right | r4 f0 r4 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4273 | word_funnel_right | r4 f0 r4 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4274 | word_funnel_right | r4 f0 r4 n | SASS, numbers loaded | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4275 | subtract_alone | r4 r4 r8 | SASS | `IADD3 {to}, {left}, -{right}, RZ;` |  |
| 4276 | subtract_alone | r4 r4 r8 | SASS | `IADD3 {to}, {left}, -{right}, RZ;` |  |
| 4277 | subtract_alone | r4 r4 r8 | SASS, numbers loaded | `IMAD.IADD {to}, {left}, 0x1, -{right};` | the machine file holds no form for it |
| 4278 | borrow_first | r4 r4 r0 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4279 | borrow_middle | r4 r4 r0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4280 | borrow_last | r4 r4 f0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4281 | predicate_and | r6 r6 r6 | SASS | `ISETP.NE.U32.AND {where}, PT, {left}, RZ, {right};` | the ruleset holds no form of the name |
| 4282 | word_and | r4 r4 r4 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4283 | borrow_first | r4 r4 r4 | SASS | `IADD3 {to}, P6, {left}, -{right}, RZ;` |  |
| 4284 | borrow_middle | r4 r4 r4 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4285 | borrow_last | r4 r4 r4 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4286 | word_funnel_right | r4 r4 f0 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4287 | word_funnel_right | r4 r4 f0 n | SASS | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4288 | word_funnel_right | r4 r4 f0 n | SASS, numbers loaded | `SHF.R.U32 {to}, {low}, {bits}, {high};` |  |
| 4289 | word_copy | r4 f0 | SASS | `` | the compiler writes no instruction for it |
| 4290 | word_and | r0 r0 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4291 | word_and | r0 r0 r8 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4292 | word_and | r0 r0 r8 | SASS, numbers loaded | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4293 | word_xor | r0 r4 r4 | SASS | `LOP3.LUT {to}, {right}, {left}, RZ, 0x3c, !PT;` |  |
| 4294 | predicate_xor | r6 r6 r6 | SASS | `ISETP.NE.U32.XOR {where}, PT, {left}, RZ, {right};` | the ruleset holds no form of the name |
| 4295 | word_and | r0 r4 r4 | SASS | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` |  |
| 4296 | test_wide_below_and | f11 f4 f5 f11 | SASS | `ISETP.LT.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.LT.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, {also}, P6;` |  |
| 4297 | add_last | r0 r0 r0 | SASS | `IMAD.X {to}, {left}, 0x1, {right}, P6;` |  |
| 4298 | borrow_last | r4 r0 r0 | SASS | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` |  |
| 4299 | launch_load | f6 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4300 | launch_load | f6 n | SASS | `LD.E.64 {to}, [<launch>.64+{offset}];` | the question names no address space |
| 4301 | wide_unpack | r0 r0 f1 | SASS | `` | the compiler writes no instruction for it |
| 4302 | test_wide_nonzero | r6 f1 | SASS | `ISETP.NE.U32.AND P6, PT, {value}, RZ, PT; \| ISETP.NE.AND.EX {where}, PT, {value}.hi, RZ, PT, P6;` |  |
| 4303 | word_multiply | r4 r4 r8 | SASS | `IMAD.SHL.U32 {to}, {left}, {right}, RZ;` |  |
| 4304 | word_multiply | r4 r4 r8 | SASS | `IMAD {to}, {left}, {right}, RZ;` |  |
| 4305 | word_multiply | r4 r4 r8 | SASS, numbers loaded | `IMAD {to}, {left}, {right}, RZ;` |  |
| 4306 | wide_multiply_word | r5 r4 n | SASS | `IMAD.WIDE.U32 {to}, {left}, {right}, RZ;` |  |
| 4307 | wide_multiply_word | r5 r4 n | SASS | `IMAD.WIDE.U32 {to}, {left}, {right}, RZ;` |  |
| 4308 | wide_multiply_word | r5 r4 n | SASS, numbers loaded | `IMAD.WIDE.U32 {to}, {left}, {right}, RZ;` |  |
| 4309 | wide_add | r5 f6 r5 | SASS | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` |  |
| 4310 | global_load | r0 r5 n | SASS | `LDG.E.CONSTANT {to}, [{address}.64+{offset}];` |  |
| 4311 | global_load | r0 r5 n | SASS | `LDG.E.CONSTANT {to}, [{address}.64+{offset}];` |  |

## By form

| form | sass.krs | SASS read | | ptx.krs | PTX read | |
|---|---|---|---|---|---|---|
| add_alone | `IADD3 {to}, {left}, {right}, RZ;` | `IADD3 {to}, {left}, {right}, RZ;` | same | `add.u32 {to}, {left}, {right};` | `` | kept: the questions read apart |
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
| sign_select | `MOV R254, {chosen}; \| SEL {to}, R254, {otherwise}, {where};` | `` | kept: the system folds the number put for otherwise; the reading does not name otherwise | `selp.s32 {to}, {chosen}, {otherwise}, {where};` | `` | kept: the compiler writes 3 instructions where the ruleset writes 1 |
| sign_set | `IMAD.MOV.U32 {to}, RZ, RZ, {value};` | `` | kept: the system folds the number put for value; the compiler writes no instruction for it | `mov.s32 {to}, {value};` | `` | kept: the system folds the number put for value; the compiler writes no instruction for it |
| subtract_alone | `IADD3 {to}, {left}, -{right}, RZ;` | `IADD3 {to}, {left}, -{right}, RZ;` | same | `sub.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| subtract_first | `IADD3 {to}, P6, {left}, -{right}, RZ;` | `IADD3 {to}, P6, {left}, -{right}, RZ;` | same | `sub.cc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 5 instructions where the ruleset writes 1 |
| subtract_last | `IMAD.X {to}, {left}, 0x1, ~{right}, P6;` | `IMAD.X {to}, {left}, 0x1, ~{right}, P6;` | same | `subc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| subtract_middle | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` | `IADD3.X {to}, P6, {left}, ~{right}, RZ, P6, !PT;` | same | `subc.cc.u32 {to}, {left}, {right};` | `` | kept: the compiler writes 5 instructions where the ruleset writes 1 |
| test_negative | `ISETP.LT.AND {where}, PT, {value}, RZ, PT;` | `ISETP.LT.AND {where}, PT, {value}, RZ, PT;` | same | `setp.lt.s32 {where}, {value}, 0;` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| test_nonzero | `ISETP.NE.AND {where}, PT, {value}, RZ, PT;` | `ISETP.NE.AND {where}, PT, {value}, RZ, PT;` | same | `setp.ne.s32 {where}, {value}, 0;` | `setp.ne.s32 {where}, {value}, 0;` | same |
| test_signed_differ | `ISETP.NE.AND {where}, PT, {left}, {right}, PT;` | `ISETP.NE.AND {where}, PT, {left}, {right}, PT;` | same | `setp.ne.s32 {where}, {left}, {right};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| test_signed_greater | `ISETP.GT.AND {where}, PT, {left}, {right}, PT;` | `ISETP.GT.AND {where}, PT, {left}, {right}, PT;` | same | `setp.gt.s32 {where}, {left}, {right};` | `` | kept: the compiler writes 3 instructions where the ruleset writes 1 |
| test_wide_below | `ISETP.LT.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.LT.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, PT, P6;` | `ISETP.LT.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.LT.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, PT, P6;` | same | `setp.lt.u64 {where}, {left}, {right};` | `setp.lt.u64 {where}, {left}, {right};` | same |
| test_wide_below_and | `ISETP.LT.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.LT.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, {also}, P6;` | `ISETP.LT.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.LT.U32.AND.EX {where}, PT, {left}.hi, {right}.hi, {also}, P6;` | same | `setp.lt.and.u64 {where}, {left}, {right}, {also};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| test_wide_equal | `ISETP.EQ.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.EQ.AND.EX {where}, PT, {left}.hi, {right}.hi, PT, P6;` | `ISETP.EQ.U32.AND P6, PT, {left}, {right}, PT; \| ISETP.EQ.AND.EX {where}, PT, {left}.hi, {right}.hi, PT, P6;` | same | `setp.eq.s64 {where}, {left}, {right};` | `setp.eq.s64 {where}, {left}, {right};` | same |
| test_wide_nonzero | `ISETP.NE.U32.AND P6, PT, {value}, RZ, PT; \| ISETP.NE.AND.EX {where}, PT, {value}.hi, RZ, PT, P6;` | `ISETP.NE.U32.AND P6, PT, {value}, RZ, PT; \| ISETP.NE.AND.EX {where}, PT, {value}.hi, RZ, PT, P6;` | same | `setp.ne.s64 {where}, {value}, 0;` | `setp.ne.s64 {where}, {value}, 0;` | same |
| test_zero | `ISETP.EQ.AND {where}, PT, {value}, RZ, PT;` | `ISETP.EQ.AND {where}, PT, {value}, RZ, PT;` | same | `setp.eq.s32 {where}, {value}, 0;` | `setp.eq.s32 {where}, {value}, 0;` | same |
| wide_add | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` | `IADD3 {to}, P6, {left}, {right}, RZ; \| IMAD.X {to}.hi, {left}.hi, 0x1, {right}.hi, P6;` | same | `add.s64 {to}, {right}, {left};` | `add.s64 {to}, {right}, {left};` | same |
| wide_add_unsigned | `IADD3 {to}, P6, {left}, {right}, RZ; \| IADD3.X {to}.hi, {left}.hi, {right}.hi, RZ, P6, !PT;` | `IADD3 {to}, P6, {left}, {right}, RZ; \| IADD3.X {to}.hi, {left}.hi, {right}.hi, RZ, P6, !PT;` | same | `add.s64 {to}, {left}, {right};` | `add.s64 {to}, {left}, {right};` | same |
| wide_multiply | `IMAD.WIDE.U32 {to}, {left}, {right}, RZ; \| IMAD {to}.hi, {left}.hi, {right}, {to}.hi; \| IMAD {to}.hi, {left}, {right}.hi, {to}.hi;` | `` | kept: the system folds the number put for right; the compiler writes 5 instructions where the ruleset writes 3 | `mul.lo.u64 {to}, {left}, {right};` | `mul.lo.s64 {to}, {left}, {right};` | read |
| wide_multiply_word | `IMAD.WIDE.U32 {to}, {left}, {right}, RZ;` | `IMAD.WIDE.U32 {to}, {left}, {right}, RZ;` | same | `mul.wide.u32 {to}, {left}, {right};` | `mul.wide.u32 {to}, {left}, {right};` | same |
| wide_select | `MOV R254, {chosen}; \| SEL {to}, R254, {otherwise}, {where}; \| MOV R254, {chosen}.hi; \| SEL {to}.hi, R254, {otherwise}.hi, {where};` | `` | kept: the questions read apart | `selp.b64 {to}, {chosen}, {otherwise}, {where};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| wide_shift_left | `SHF.L.U64.HI {to}.hi, {from}, {bits}, {from}.hi; \| SHF.L.U32 {to}, {from}, {bits}, RZ;` | `SHF.L.U64.HI {to}.hi, {from}, {bits}, {from}.hi; \| SHF.L.U32 {to}, {from}, {bits}, RZ;` | same | `shl.b64 {to}, {from}, {bits};` | `shl.b64 {to}, {from}, {bits};` | same |
| wide_unpack | `MOV {low}, {from}; \| MOV {high}, {from}.hi;` | `` | kept: the compiler writes no instruction for it | `mov.b64 {{low}, {high}}, {from};` | `` | kept: the reading does not name from |
| word_and | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` | `LOP3.LUT {to}, {left}, {right}, RZ, 0xc0, !PT;` | same | `and.b32 {to}, {left}, {right};` | `` | kept: the questions read apart |
| word_copy | `MOV {to}, {from};` | `` | kept: the compiler writes no instruction for it | `mov.b32 {to}, {from};` | `` | kept: the compiler writes no instruction for it |
| word_funnel_right | `SHF.R.U32 {to}, {low}, {bits}, {high};` | `SHF.R.U32 {to}, {low}, {bits}, {high};` | same | `shf.r.clamp.b32 {to}, {low}, {high}, {bits};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| word_multiply | `IMAD {to}, {left}, {right}, RZ;` | `IMAD {to}, {left}, {right}, RZ;` | same | `mul.lo.u32 {to}, {left}, {right};` | `mul.lo.s32 {to}, {left}, {right};` | read |
| word_multiply_add | `IMAD {to}, {left}, {right}, {added};` | `IMAD {to}, {left}, {right}, {added};` | same | `mad.lo.s32 {to}, {left}, {right}, {added};` | `mad.lo.s32 {to}, {left}, {right}, {added};` | same |
| word_or | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` | `LOP3.LUT {to}, {right}, {left}, RZ, 0xfc, !PT;` | same | `or.b32 {to}, {right}, {left};` | `or.b32 {to}, {right}, {left};` | same |
| word_select | `SEL {to}, {chosen}, {otherwise}, {where};` | `SEL {to}, {chosen}, {otherwise}, {where};` | same | `selp.b32 {to}, {chosen}, {otherwise}, {where};` | `` | kept: the compiler writes 2 instructions where the ruleset writes 1 |
| word_set | `MOV {to}, {value};` | `` | kept: the system folds the number put for value; the compiler writes no instruction for it | `mov.u32 {to}, {value};` | `mov.u32 {to}, {value};` | same |
| word_shift_left | `SHF.L.U32 {to}, {from}, {bits}, RZ;` | `SHF.L.U32 {to}, {from}, {bits}, RZ;` | same | `shl.b32 {to}, {from}, {bits};` | `shl.b32 {to}, {from}, {bits};` | same |
| word_shift_right | `SHF.R.U32.HI {to}, RZ, {bits}, {from};` | `SHF.R.U32.HI {to}, RZ, {bits}, {from};` | same | `shr.u32 {to}, {from}, {bits};` | `shr.u32 {to}, {from}, {bits};` | same |
| word_xor | `LOP3.LUT {to}, {right}, {left}, RZ, 0x3c, !PT;` | `LOP3.LUT {to}, {right}, {left}, RZ, 0x3c, !PT;` | same | `xor.b32 {to}, {right}, {left};` | `xor.b32 {to}, {right}, {left};` | same |

440 questions over 55 forms. Of the forms, sass.krs already gives 43 as read and 0 are read otherwise; ptx.krs gives 17 as read and 2 are read otherwise.
