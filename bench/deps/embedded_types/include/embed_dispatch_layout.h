/* embedded_types - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file embed_dispatch_layout.h
 * @brief Compile-time assertions that a struct of function pointers holds its members at
 *        consecutive slots and nothing else.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-08-30
 *
 * @note This catches two mistakes, and neither shows up at a call site. Adding a member to the
 *       struct and leaving it out of the list moves every member below it off its slot. Padding
 *       appearing between two members does the same with no edit to the list at all.
 * @note The preprocessor has no loop. Each member count needs its own line. The family below runs
 *       out to twenty-four for that reason.
 */
#ifndef EMBED_DISPATCH_LAYOUT_H
#define EMBED_DISPATCH_LAYOUT_H

#include <stddef.h>

#include "embed_compiler_directives.h"

/**
 * @brief Expands to sizeof(void (*)(void)).
 *
 * @note A slot index times this gives a byte offset. sizeof(void *) would be wrong here. Code and
 *       data pointers differ in width on some targets.
 */
#define EMBED_FUNCTION_POINTER_BYTES (sizeof(void (*)(void)))

/**
 * @brief Asserts one member sits at a given dispatch slot.
 *
 * @param[in] Table_  Struct type passed to offsetof.
 * @param[in] member_ Member name passed to offsetof.
 * @param[in] slot_   Index, cast to size_t and multiplied by EMBED_FUNCTION_POINTER_BYTES.
 * @note Every EMBED_TABLE_SLOTS_N line below is built from this one check.
 * @note Table_, member_, and slot_ are stringized into the assertion message. A failure names the
 *       table, the member, and the index it was expected at.
 */
#define EMBED_TABLE_SLOT(Table_, member_, slot_)                                                                       \
    EMBED_STATIC_ASSERT(offsetof(Table_, member_) == (size_t)(slot_) * EMBED_FUNCTION_POINTER_BYTES,                   \
                        #Table_ "." #member_ " is not at dispatch slot " #slot_)

/**
 * @brief Asserts one member sits at slot 0.
 *
 * @param[in] Table_   Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_ The single member's name, at slot 0.
 * @note Every longer line in the family expands down to this one. This line calls only
 *       EMBED_TABLE_SLOT.
 */
#define EMBED_TABLE_SLOTS_1(Table_, member1_) EMBED_TABLE_SLOT(Table_, member1_, 0);

/**
 * @brief Asserts two members sit at consecutive slots from 0.
 *
 * @param[in] Table_   Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_ Member at slot 0.
 * @param[in] member2_ Member at slot 1.
 * @note Every longer line in the family works the same way. It expands the line one shorter, then
 *       asserts the next index.
 */
#define EMBED_TABLE_SLOTS_2(Table_, member1_, member2_)                                                                \
    EMBED_TABLE_SLOTS_1(Table_, member1_) EMBED_TABLE_SLOT(Table_, member2_, 1);

/**
 * @brief Asserts three members sit at consecutive slots from 0.
 *
 * @param[in] Table_   Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_ Member at slot 0.
 * @param[in] member2_ Member at slot 1.
 * @param[in] member3_ Member at slot 2, asserted after EMBED_TABLE_SLOTS_2 covers the first two.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with three members.
 */
#define EMBED_TABLE_SLOTS_3(Table_, member1_, member2_, member3_)                                                      \
    EMBED_TABLE_SLOTS_2(Table_, member1_, member2_) EMBED_TABLE_SLOT(Table_, member3_, 2);

/**
 * @brief Asserts four members sit at consecutive slots from 0.
 *
 * @param[in] Table_   Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_ Member at slot 0.
 * @param[in] member2_ Member at slot 1.
 * @param[in] member3_ Member at slot 2.
 * @param[in] member4_ Member at slot 3, asserted after EMBED_TABLE_SLOTS_3 covers the first three.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with four members.
 */
#define EMBED_TABLE_SLOTS_4(Table_, member1_, member2_, member3_, member4_)                                            \
    EMBED_TABLE_SLOTS_3(Table_, member1_, member2_, member3_) EMBED_TABLE_SLOT(Table_, member4_, 3);

/**
 * @brief Asserts five members sit at consecutive slots from 0.
 *
 * @param[in] Table_   Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_ Member at slot 0.
 * @param[in] member2_ Member at slot 1.
 * @param[in] member3_ Member at slot 2.
 * @param[in] member4_ Member at slot 3.
 * @param[in] member5_ Member at slot 4, asserted after EMBED_TABLE_SLOTS_4 covers the first four.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with five members.
 */
#define EMBED_TABLE_SLOTS_5(Table_, member1_, member2_, member3_, member4_, member5_)                                  \
    EMBED_TABLE_SLOTS_4(Table_, member1_, member2_, member3_, member4_) EMBED_TABLE_SLOT(Table_, member5_, 4);

/**
 * @brief Asserts six members sit at consecutive slots from 0.
 *
 * @param[in] Table_   Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_ Member at slot 0.
 * @param[in] member2_ Member at slot 1.
 * @param[in] member3_ Member at slot 2.
 * @param[in] member4_ Member at slot 3.
 * @param[in] member5_ Member at slot 4.
 * @param[in] member6_ Member at slot 5, asserted after EMBED_TABLE_SLOTS_5 covers the first five.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with six members.
 */
#define EMBED_TABLE_SLOTS_6(Table_, member1_, member2_, member3_, member4_, member5_, member6_)                        \
    EMBED_TABLE_SLOTS_5(Table_, member1_, member2_, member3_, member4_, member5_)                                      \
    EMBED_TABLE_SLOT(Table_, member6_, 5);

/**
 * @brief Asserts seven members sit at consecutive slots from 0.
 *
 * @param[in] Table_   Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_ Member at slot 0.
 * @param[in] member2_ Member at slot 1.
 * @param[in] member3_ Member at slot 2.
 * @param[in] member4_ Member at slot 3.
 * @param[in] member5_ Member at slot 4.
 * @param[in] member6_ Member at slot 5.
 * @param[in] member7_ Member at slot 6, asserted after EMBED_TABLE_SLOTS_6 covers the first six.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with seven members.
 */
#define EMBED_TABLE_SLOTS_7(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_)              \
    EMBED_TABLE_SLOTS_6(Table_, member1_, member2_, member3_, member4_, member5_, member6_)                            \
    EMBED_TABLE_SLOT(Table_, member7_, 6);

/**
 * @brief Asserts eight members sit at consecutive slots from 0.
 *
 * @param[in] Table_   Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_ Member at slot 0.
 * @param[in] member2_ Member at slot 1.
 * @param[in] member3_ Member at slot 2.
 * @param[in] member4_ Member at slot 3.
 * @param[in] member5_ Member at slot 4.
 * @param[in] member6_ Member at slot 5.
 * @param[in] member7_ Member at slot 6.
 * @param[in] member8_ Member at slot 7, asserted after EMBED_TABLE_SLOTS_7 covers the first seven.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with eight members.
 */
#define EMBED_TABLE_SLOTS_8(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_)    \
    EMBED_TABLE_SLOTS_7(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_)                  \
    EMBED_TABLE_SLOT(Table_, member8_, 7);

/**
 * @brief Asserts nine members sit at consecutive slots from 0.
 *
 * @param[in] Table_   Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_ Member at slot 0.
 * @param[in] member2_ Member at slot 1.
 * @param[in] member3_ Member at slot 2.
 * @param[in] member4_ Member at slot 3.
 * @param[in] member5_ Member at slot 4.
 * @param[in] member6_ Member at slot 5.
 * @param[in] member7_ Member at slot 6.
 * @param[in] member8_ Member at slot 7.
 * @param[in] member9_ Member at slot 8, asserted after EMBED_TABLE_SLOTS_8 covers the first eight.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with nine members.
 */
#define EMBED_TABLE_SLOTS_9(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,    \
                            member9_)                                                                                  \
    EMBED_TABLE_SLOTS_8(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_)        \
    EMBED_TABLE_SLOT(Table_, member9_, 8);

/**
 * @brief Asserts ten members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9, asserted after EMBED_TABLE_SLOTS_9 covers the first nine.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with ten members.
 */
#define EMBED_TABLE_SLOTS_10(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_)                                                                      \
    EMBED_TABLE_SLOTS_9(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,        \
                        member9_)                                                                                      \
    EMBED_TABLE_SLOT(Table_, member10_, 9);

/**
 * @brief Asserts eleven members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10, asserted after EMBED_TABLE_SLOTS_10 covers the first ten.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with eleven members.
 */
#define EMBED_TABLE_SLOTS_11(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_)                                                           \
    EMBED_TABLE_SLOTS_10(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_)                                                                          \
    EMBED_TABLE_SLOT(Table_, member11_, 10);

/**
 * @brief Asserts twelve members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11, asserted after EMBED_TABLE_SLOTS_11 covers the first eleven.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with twelve members.
 */
#define EMBED_TABLE_SLOTS_12(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_)                                                \
    EMBED_TABLE_SLOTS_11(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_)                                                               \
    EMBED_TABLE_SLOT(Table_, member12_, 11);

/**
 * @brief Asserts thirteen members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12, asserted after EMBED_TABLE_SLOTS_12 covers the first twelve.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with thirteen members.
 */
#define EMBED_TABLE_SLOTS_13(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_)                                     \
    EMBED_TABLE_SLOTS_12(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_)                                                    \
    EMBED_TABLE_SLOT(Table_, member13_, 12);

/**
 * @brief Asserts fourteen members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12.
 * @param[in] member14_ Member at slot 13, asserted after EMBED_TABLE_SLOTS_13 covers the first thirteen.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with fourteen members.
 */
#define EMBED_TABLE_SLOTS_14(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_, member14_)                          \
    EMBED_TABLE_SLOTS_13(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_, member13_)                                         \
    EMBED_TABLE_SLOT(Table_, member14_, 13);

/**
 * @brief Asserts fifteen members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12.
 * @param[in] member14_ Member at slot 13.
 * @param[in] member15_ Member at slot 14, asserted after EMBED_TABLE_SLOTS_14 covers the first fourteen.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with fifteen members.
 */
#define EMBED_TABLE_SLOTS_15(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_, member14_, member15_)               \
    EMBED_TABLE_SLOTS_14(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_, member13_, member14_)                              \
    EMBED_TABLE_SLOT(Table_, member15_, 14);

/**
 * @brief Asserts sixteen members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12.
 * @param[in] member14_ Member at slot 13.
 * @param[in] member15_ Member at slot 14.
 * @param[in] member16_ Member at slot 15, asserted after EMBED_TABLE_SLOTS_15 covers the first fifteen.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with sixteen members.
 */
#define EMBED_TABLE_SLOTS_16(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_)    \
    EMBED_TABLE_SLOTS_15(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_, member13_, member14_, member15_)                   \
    EMBED_TABLE_SLOT(Table_, member16_, 15);

/**
 * @brief Asserts seventeen members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12.
 * @param[in] member14_ Member at slot 13.
 * @param[in] member15_ Member at slot 14.
 * @param[in] member16_ Member at slot 15.
 * @param[in] member17_ Member at slot 16, asserted after EMBED_TABLE_SLOTS_16 covers the first sixteen.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with seventeen members.
 */
#define EMBED_TABLE_SLOTS_17(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,    \
                             member17_)                                                                                \
    EMBED_TABLE_SLOTS_16(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_)        \
    EMBED_TABLE_SLOT(Table_, member17_, 16);

/**
 * @brief Asserts eighteen members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12.
 * @param[in] member14_ Member at slot 13.
 * @param[in] member15_ Member at slot 14.
 * @param[in] member16_ Member at slot 15.
 * @param[in] member17_ Member at slot 16.
 * @param[in] member18_ Member at slot 17, asserted after EMBED_TABLE_SLOTS_17 covers the first seventeen.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with eighteen members.
 */
#define EMBED_TABLE_SLOTS_18(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,    \
                             member17_, member18_)                                                                     \
    EMBED_TABLE_SLOTS_17(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,        \
                         member17_)                                                                                    \
    EMBED_TABLE_SLOT(Table_, member18_, 17);

/**
 * @brief Asserts nineteen members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12.
 * @param[in] member14_ Member at slot 13.
 * @param[in] member15_ Member at slot 14.
 * @param[in] member16_ Member at slot 15.
 * @param[in] member17_ Member at slot 16.
 * @param[in] member18_ Member at slot 17.
 * @param[in] member19_ Member at slot 18, asserted after EMBED_TABLE_SLOTS_18 covers the first eighteen.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with nineteen members.
 */
#define EMBED_TABLE_SLOTS_19(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,    \
                             member17_, member18_, member19_)                                                          \
    EMBED_TABLE_SLOTS_18(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,        \
                         member17_, member18_)                                                                         \
    EMBED_TABLE_SLOT(Table_, member19_, 18);

/**
 * @brief Asserts twenty members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12.
 * @param[in] member14_ Member at slot 13.
 * @param[in] member15_ Member at slot 14.
 * @param[in] member16_ Member at slot 15.
 * @param[in] member17_ Member at slot 16.
 * @param[in] member18_ Member at slot 17.
 * @param[in] member19_ Member at slot 18.
 * @param[in] member20_ Member at slot 19, asserted after EMBED_TABLE_SLOTS_19 covers the first nineteen.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with twenty members.
 */
#define EMBED_TABLE_SLOTS_20(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,    \
                             member17_, member18_, member19_, member20_)                                               \
    EMBED_TABLE_SLOTS_19(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,        \
                         member17_, member18_, member19_)                                                              \
    EMBED_TABLE_SLOT(Table_, member20_, 19);

/**
 * @brief Asserts twenty-one members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12.
 * @param[in] member14_ Member at slot 13.
 * @param[in] member15_ Member at slot 14.
 * @param[in] member16_ Member at slot 15.
 * @param[in] member17_ Member at slot 16.
 * @param[in] member18_ Member at slot 17.
 * @param[in] member19_ Member at slot 18.
 * @param[in] member20_ Member at slot 19.
 * @param[in] member21_ Member at slot 20, asserted after EMBED_TABLE_SLOTS_20 covers the first twenty.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with twenty-one members.
 */
#define EMBED_TABLE_SLOTS_21(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,    \
                             member17_, member18_, member19_, member20_, member21_)                                    \
    EMBED_TABLE_SLOTS_20(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,        \
                         member17_, member18_, member19_, member20_)                                                   \
    EMBED_TABLE_SLOT(Table_, member21_, 20);

/**
 * @brief Asserts twenty-two members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12.
 * @param[in] member14_ Member at slot 13.
 * @param[in] member15_ Member at slot 14.
 * @param[in] member16_ Member at slot 15.
 * @param[in] member17_ Member at slot 16.
 * @param[in] member18_ Member at slot 17.
 * @param[in] member19_ Member at slot 18.
 * @param[in] member20_ Member at slot 19.
 * @param[in] member21_ Member at slot 20.
 * @param[in] member22_ Member at slot 21, asserted after EMBED_TABLE_SLOTS_21 covers the first twenty-one.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with twenty-two members.
 */
#define EMBED_TABLE_SLOTS_22(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,    \
                             member17_, member18_, member19_, member20_, member21_, member22_)                         \
    EMBED_TABLE_SLOTS_21(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,        \
                         member17_, member18_, member19_, member20_, member21_)                                        \
    EMBED_TABLE_SLOT(Table_, member22_, 21);

/**
 * @brief Asserts twenty-three members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12.
 * @param[in] member14_ Member at slot 13.
 * @param[in] member15_ Member at slot 14.
 * @param[in] member16_ Member at slot 15.
 * @param[in] member17_ Member at slot 16.
 * @param[in] member18_ Member at slot 17.
 * @param[in] member19_ Member at slot 18.
 * @param[in] member20_ Member at slot 19.
 * @param[in] member21_ Member at slot 20.
 * @param[in] member22_ Member at slot 21.
 * @param[in] member23_ Member at slot 22, asserted after EMBED_TABLE_SLOTS_22 covers the first twenty-two.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with twenty-three members.
 */
#define EMBED_TABLE_SLOTS_23(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,    \
                             member17_, member18_, member19_, member20_, member21_, member22_, member23_)              \
    EMBED_TABLE_SLOTS_22(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,        \
                         member17_, member18_, member19_, member20_, member21_, member22_)                             \
    EMBED_TABLE_SLOT(Table_, member23_, 22);

/**
 * @brief Asserts twenty-four members sit at consecutive slots from 0.
 *
 * @param[in] Table_    Struct type forwarded to EMBED_TABLE_SLOT.
 * @param[in] member1_  Member at slot 0.
 * @param[in] member2_  Member at slot 1.
 * @param[in] member3_  Member at slot 2.
 * @param[in] member4_  Member at slot 3.
 * @param[in] member5_  Member at slot 4.
 * @param[in] member6_  Member at slot 5.
 * @param[in] member7_  Member at slot 6.
 * @param[in] member8_  Member at slot 7.
 * @param[in] member9_  Member at slot 8.
 * @param[in] member10_ Member at slot 9.
 * @param[in] member11_ Member at slot 10.
 * @param[in] member12_ Member at slot 11.
 * @param[in] member13_ Member at slot 12.
 * @param[in] member14_ Member at slot 13.
 * @param[in] member15_ Member at slot 14.
 * @param[in] member16_ Member at slot 15.
 * @param[in] member17_ Member at slot 16.
 * @param[in] member18_ Member at slot 17.
 * @param[in] member19_ Member at slot 18.
 * @param[in] member20_ Member at slot 19.
 * @param[in] member21_ Member at slot 20.
 * @param[in] member22_ Member at slot 21.
 * @param[in] member23_ Member at slot 22.
 * @param[in] member24_ Member at slot 23, asserted after EMBED_TABLE_SLOTS_23 covers the first twenty-three.
 * @note EMBED_TABLE_LAYOUT selects this line for a table with twenty-four members.
 * @warning This is the longest line in the family. A table with twenty-five members has no line to
 *          expand to. EMBED_NARG stops at twenty-four as well. Raising the limit takes a new line
 *          here, one more constant in EMBED_NARG, and one more parameter in EMBED_ARG_N.
 */
#define EMBED_TABLE_SLOTS_24(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,   \
                             member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,    \
                             member17_, member18_, member19_, member20_, member21_, member22_, member23_, member24_)   \
    EMBED_TABLE_SLOTS_23(Table_, member1_, member2_, member3_, member4_, member5_, member6_, member7_, member8_,       \
                         member9_, member10_, member11_, member12_, member13_, member14_, member15_, member16_,        \
                         member17_, member18_, member19_, member20_, member21_, member22_, member23_)                  \
    EMBED_TABLE_SLOT(Table_, member24_, 23);

/**
 * @brief Asserts a table's members sit at consecutive slots and that nothing else is in it.
 *
 * @param[in] Table_ Struct type forwarded to the arity line and to sizeof.
 * @param[in] ...    Member names in slot order, one to twenty-four.
 * @note The per-member assertions catch a member left out of the list. The size assertion catches
 *       padding, since a padded struct is larger than the count times EMBED_FUNCTION_POINTER_BYTES.
 * @note EMBED_CAT builds the arity line's name from EMBED_NARG's count of the member list. The
 *       caller writes each member once.
 * @warning A member of some other type changes sizeof(Table_) and fails the size assertion.
 */
#define EMBED_TABLE_LAYOUT(Table_, ...)                                                                                \
    EMBED_CAT(EMBED_TABLE_SLOTS_, EMBED_NARG(__VA_ARGS__))(Table_, __VA_ARGS__)                                        \
        EMBED_STATIC_ASSERT(sizeof(Table_) == (size_t)EMBED_NARG(__VA_ARGS__) * EMBED_FUNCTION_POINTER_BYTES,          \
                            #Table_ " has a member that is not in its dispatch list, or is padded")

/**
 * @brief Expands to static const.
 *
 * @note Declares a dispatch table. static gives internal linkage. Each translation unit including
 *       the header gets its own copy. The copies do not collide at link time.
 * @note const lets the compiler resolve a call through a table entry to the function directly. That
 *       needs a table no other translation unit can reach and no code assigns to.
 * @note This macro does not supply EMBED_UNUSED. Write it on the table as well. A translation unit
 *       that calls nothing through the table warns without it.
 */
#define EMBED_TABLE_STORAGE static const

/**
 * @brief Expands to left_##right_.
 *
 * @param[in] left_  Left operand of ##.
 * @param[in] right_ Right operand of ##.
 * @return           The single token formed by joining left_ and right_.
 * @note EMBED_CAT calls this. ## does not expand its own operands, and EMBED_CAT expands them
 *       before handing them here. Call EMBED_CAT when either operand is itself a macro.
 */
#define EMBED_CAT_(left_, right_) left_##right_

/**
 * @brief Expands to EMBED_CAT_(left_, right_).
 *
 * @param[in] left_  Left operand, forwarded to EMBED_CAT_.
 * @param[in] right_ Right operand, forwarded to EMBED_CAT_.
 * @return           The single token formed by joining left_ and right_.
 * @note This expands its arguments first, then EMBED_CAT_ pastes the results. A macro operand
 *       reaches EMBED_CAT_ as its value.
 * @note EMBED_TABLE_LAYOUT uses this to build an EMBED_TABLE_SLOTS_<n> name from EMBED_NARG's
 *       count.
 */
#define EMBED_CAT(left_, right_) EMBED_CAT_(left_, right_)

/**
 * @brief Expands to EMBED_ARG_N with __VA_ARGS__ followed by the constants 24 down to 0.
 *
 * @param[in] ... The list to count.
 * @return        The number of arguments, for one to twenty-four arguments.
 * @note Counting the arguments turns an arity into a number EMBED_CAT can paste into a macro name.
 *       The preprocessor has no loop.
 * @warning An empty list gives 1. The preprocessor cannot tell an empty argument from a missing one.
 * @warning Twenty-five or more arguments make EMBED_ARG_N select an argument instead of a constant.
 */
#define EMBED_NARG(...)                                                                                                \
    EMBED_NARG_(__VA_ARGS__, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0)

/**
 * @brief Expands to EMBED_ARG_N(__VA_ARGS__).
 *
 * @param[in] ... The list from EMBED_NARG, followed by the constants 24 down to 0.
 * @return        The value EMBED_ARG_N selects.
 * @note EMBED_NARG calls this. Going through one more macro expands the caller's list before
 *       EMBED_ARG_N picks a slot from it.
 */
#define EMBED_NARG_(...) EMBED_ARG_N(__VA_ARGS__)

/**
 * @brief Expands to its twenty-fifth argument.
 *
 * @param[in] slot1_    Arguments one through twenty-four, discarded.
 * @param[in] selected_ The twenty-fifth argument.
 * @param[in] ...       Arguments beyond the twenty-fifth, discarded.
 * @return              selected_.
 * @note EMBED_NARG appends the constants 24 down to 0 after the caller's list. The caller's
 *       arguments push those constants to the right. Whichever one lands twenty-fifth is how many
 *       arguments the caller passed.
 */
#define EMBED_ARG_N(slot1_, slot2_, slot3_, slot4_, slot5_, slot6_, slot7_, slot8_, slot9_, slot10_, slot11_, slot12_, \
                    slot13_, slot14_, slot15_, slot16_, slot17_, slot18_, slot19_, slot20_, slot21_, slot22_, slot23_, \
                    slot24_, selected_, ...)                                                                           \
    selected_

/**
 * @brief Expands to entry_(&(ArgsType_){__VA_ARGS__}).
 *
 * @param[in] entry_    Function called with the address of the literal.
 * @param[in] ArgsType_ Type of the compound literal.
 * @param[in] ...       Initializers for the compound literal.
 * @return              The value entry_ returns.
 * @note One pointer costs one register at any arity. A long parameter list fills the registers and
 *       spills the rest onto the stack.
 * @note C zero initializes any member the initializer does not name. A compound literal in argument
 *       position lives until the end of the enclosing block, so entry_ may hold the pointer for the
 *       whole call.
 * @note Use this from C only. Compound literals are not C++ in any revision. GNU C++ accepts one as
 *       an extension. Its lifetime there ends at the full-expression. That breaks the [BORROWS]
 *       contract below. EMBED_ENTRY and EMBED_ENTRY_V expand this macro at a definition site, which
 *       is a .c compiled as C. A C++ translation unit sees the emitted prototype under
 *       EMBED_BEGIN_DECLS and never the expansion.
 * @warning entry_ receives the address of the literal [BORROWS].
 */
#define EMBED_CALL(entry_, ArgsType_, ...) entry_(&(ArgsType_){__VA_ARGS__})

/**
 * @brief Defines a value-returning entry point that forwards an argument pack.
 *
 * @param[in] entry_prefix_   Public entry point prefix, such as mmgr_anular_.
 * @param[in] backend_prefix_ Backend function prefix, such as infin_.
 * @param[in] CtxType_        Type of the compound literal the backend receives, such as AnularisCtx.
 * @param[in] CfgType_        Type the emitted entry takes a pointer to, such as AnularisCfg.
 * @param[in] ReturnType_     Return type of the emitted function.
 * @param[in] name_           Core name, pasted onto both prefixes.
 * @param[in] ...             Initializers for the CtxType_ literal, written in terms of args.
 * @return                    What the backend returns.
 * @note One shape for every entry in the library. A caller writes the same call at each module.
 *       The entry tests nothing. Whatever checking an operation needs belongs in the backend it
 *       names.
 * @warning The initializers dereference args, so it must not be NULL [BORROWS].
 */
#define EMBED_ENTRY(entry_prefix_, backend_prefix_, CtxType_, CfgType_, ReturnType_, name_, ...)                       \
    ReturnType_ entry_prefix_##name_(const CfgType_ *args)                                                             \
    {                                                                                                                  \
        return EMBED_CALL(backend_prefix_##name_, CtxType_, __VA_ARGS__);                                              \
    }

/**
 * @brief Defines a void entry point that forwards an argument pack.
 *
 * @param[in] entry_prefix_   Public entry point prefix, such as mmgr_anular_.
 * @param[in] backend_prefix_ Backend function prefix, such as infin_.
 * @param[in] CtxType_        Type of the compound literal the backend receives, such as AnularisCtx.
 * @param[in] CfgType_        Type the emitted entry takes a pointer to, such as AnularisCfg.
 * @param[in] name_           Core name, pasted onto both prefixes.
 * @param[in] ...             Initializers for the CtxType_ literal, written in terms of args.
 * @note The same body as EMBED_ENTRY, without the return. Two macros exist because void does not
 *       work as ReturnType_. Writing `void` there would still emit `return backend(...)`, and C
 *       forbids a return with an expression in a function returning void.
 * @warning The initializers dereference args, so it must not be NULL [BORROWS].
 */
#define EMBED_ENTRY_V(entry_prefix_, backend_prefix_, CtxType_, CfgType_, name_, ...)                                  \
    void entry_prefix_##name_(const CfgType_ *args)                                                                    \
    {                                                                                                                  \
        EMBED_CALL(backend_prefix_##name_, CtxType_, __VA_ARGS__);                                                     \
    }

#endif
