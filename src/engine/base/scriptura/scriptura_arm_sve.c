// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "scriptura_arm.h"

#include <stddef.h>

#if ENGINE_TARGET_AARCH64 && defined(__linux__) && (defined(__GNUC__) || defined(__clang__))

#include <arm_sve.h>
#include <sys/auxv.h>

#define SCRIPTURA_SVE_TARGET __attribute__((target("+sve")))
#define SCRIPTURA_SVE_HWCAP (1ul << 22u)

static int scriptura_sve_present(void)
{
    return ((getauxval(AT_HWCAP) & SCRIPTURA_SVE_HWCAP) != 0ul) ? 1 : 0;
}

SCRIPTURA_SVE_TARGET static unsigned long long scriptura_sve_length(const char *text, unsigned long long room)
{
    // the text is read as unsigned bytes
    const unsigned char *const source = (const unsigned char *)text;
    const unsigned long long step = svcntb();
    unsigned long long at = 0ull;
    while (at < room)
    {
        const svbool_t live = svwhilelt_b8_u64(at, room);
        const svbool_t zeros = svcmpeq_n_u8(live, svld1_u8(live, source + at), 0u);
        if (svptest_any(live, zeros))
        {
            return at + svcntp_b8(live, svbrkb_z(live, zeros));
        }
        at += step;
    }
    return room;
}

SCRIPTURA_SVE_TARGET static unsigned long long scriptura_sve_find(const void *from, unsigned char value,
                                                                   unsigned long long bytes)
{
    // the region is read as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    const unsigned long long step = svcntb();
    unsigned long long at = 0ull;
    while (at < bytes)
    {
        const svbool_t live = svwhilelt_b8_u64(at, bytes);
        const svbool_t matching = svcmpeq_n_u8(live, svld1_u8(live, source + at), value);
        if (svptest_any(live, matching))
        {
            return at + svcntp_b8(live, svbrkb_z(live, matching));
        }
        at += step;
    }
    return bytes;
}

SCRIPTURA_SVE_TARGET static void scriptura_sve_copy(void *to, const void *from, unsigned long long bytes)
{
    // the regions are read and written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the regions are read and written as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    const unsigned long long step = svcntb();
    unsigned long long at = 0ull;
    while (at < bytes)
    {
        const svbool_t live = svwhilelt_b8_u64(at, bytes);
        svst1_u8(live, target + at, svld1_u8(live, source + at));
        at += step;
    }
}

SCRIPTURA_SVE_TARGET static void scriptura_sve_move_up(void *to, const void *from, unsigned long long bytes)
{
    // the regions are read and written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the regions are read and written as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    const unsigned long long step = svcntb();
    unsigned long long at = bytes;
    while (at >= step)
    {
        at -= step;
        svst1_u8(svptrue_b8(), target + at, svld1_u8(svptrue_b8(), source + at));
    }
    if (at != 0ull)
    {
        const svbool_t live = svwhilelt_b8_u64(0ull, at);
        svst1_u8(live, target, svld1_u8(live, source));
    }
}

SCRIPTURA_SVE_TARGET static int scriptura_sve_compare(const void *one, const void *other, unsigned long long bytes)
{
    // the regions are read as unsigned bytes
    const unsigned char *const left = (const unsigned char *)one;
    // the regions are read as unsigned bytes
    const unsigned char *const right = (const unsigned char *)other;
    const unsigned long long step = svcntb();
    unsigned long long at = 0ull;
    while (at < bytes)
    {
        const svbool_t live = svwhilelt_b8_u64(at, bytes);
        const svbool_t differing = svcmpne_u8(live, svld1_u8(live, left + at), svld1_u8(live, right + at));
        if (svptest_any(live, differing))
        {
            const unsigned long long lane = at + svcntp_b8(live, svbrkb_z(live, differing));
            return (left[lane] < right[lane]) ? -1 : 1;
        }
        at += step;
    }
    return 0;
}

SCRIPTURA_SVE_TARGET static void scriptura_sve_fill(void *to, unsigned char value, unsigned long long bytes)
{
    // the region is written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    const svuint8_t spread = svdup_n_u8(value);
    const unsigned long long step = svcntb();
    unsigned long long at = 0ull;
    while (at < bytes)
    {
        svst1_u8(svwhilelt_b8_u64(at, bytes), target + at, spread);
        at += step;
    }
}

const ScripturaArm *scriptura_sve_arm(void)
{
    static const ScripturaArm arm = {"sve-unrun",
                                     16ull,
                                     scriptura_sve_length,
                                     scriptura_sve_find,
                                     scriptura_sve_copy,
                                     scriptura_sve_move_up,
                                     scriptura_sve_compare,
                                     scriptura_sve_fill};
    return (scriptura_sve_present() != 0) ? &arm : NULL;
}

#else

const ScripturaArm *scriptura_sve_arm(void)
{
    return NULL;
}

#endif
