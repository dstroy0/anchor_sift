// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "scriptura_arm.h"

#include <stddef.h>

#if ENGINE_TARGET_X86_64

#include <immintrin.h>

#if defined(_MSC_VER) && !defined(__clang__)
#define SCRIPTURA_AVX512_TARGET
#else
#define SCRIPTURA_AVX512_TARGET __attribute__((target("avx512f,avx512bw")))
#endif

#define SCRIPTURA_AVX512_BYTES 64u

static unsigned long long scriptura_avx512_lowest(unsigned long long mask)
{
#if defined(_MSC_VER) && !defined(__clang__)
    unsigned long index = 0ul;
    _BitScanForward64(&index, mask);
    // the bit index of a non-zero 64 bit mask is 0 to 63
    return (unsigned long long)index;
#else
    // the trailing count of a non-zero 64 bit mask is 0 to 63
    return (unsigned long long)(unsigned int)__builtin_ctzll(mask);
#endif
}

static int scriptura_avx512_present(void)
{
#if defined(_MSC_VER) && !defined(__clang__)
    int leaves[4];
    __cpuid(leaves, 0);
    if (leaves[0] < 7)
    {
        return 0;
    }
    __cpuid(leaves, 1);
    // leaf 1 ecx is read as its bit pattern
    const unsigned int features = (unsigned int)leaves[2];
    if (((features >> 27u) & 1u) == 0u)
    {
        return 0;
    }
    if ((_xgetbv(0u) & 0xE6ull) != 0xE6ull)
    {
        return 0;
    }
    __cpuidex(leaves, 7, 0);
    // leaf 7 ebx is read as its bit pattern
    const unsigned int extended = (unsigned int)leaves[1];
    return ((((extended >> 16u) & 1u) != 0u) && (((extended >> 30u) & 1u) != 0u)) ? 1 : 0;
#else
    __builtin_cpu_init();
    return (__builtin_cpu_supports("avx512f") && __builtin_cpu_supports("avx512bw")) ? 1 : 0;
#endif
}

static __mmask64 scriptura_avx512_lanes(unsigned long long bytes)
{
    // the lane mask is the low bits of the count, held in the 64 bit mask type
    return (bytes >= SCRIPTURA_AVX512_BYTES) ? (__mmask64)0xFFFFFFFFFFFFFFFFull : (__mmask64)((1ull << bytes) - 1ull);
}

SCRIPTURA_AVX512_TARGET static unsigned long long scriptura_avx512_length(const char *text, unsigned long long room)
{
    const __m512i zero = _mm512_setzero_si512();
    unsigned long long at = 0ull;
    while (at < room)
    {
        const __mmask64 live = scriptura_avx512_lanes(room - at);
        const __mmask64 zeros = _mm512_mask_cmpeq_epi8_mask(live, _mm512_maskz_loadu_epi8(live, text + at), zero);
        if (zeros != 0u)
        {
            return at + scriptura_avx512_lowest(zeros);
        }
        at += SCRIPTURA_AVX512_BYTES;
    }
    return room;
}

SCRIPTURA_AVX512_TARGET static unsigned long long scriptura_avx512_find(const void *from, unsigned char value,
                                                                         unsigned long long bytes)
{
    // the region is read as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    // the byte is broadcast as the signed char the intrinsic takes, bit for bit
    const __m512i broadcast = _mm512_set1_epi8((char)value);
    unsigned long long at = 0ull;
    while (at < bytes)
    {
        const __mmask64 live = scriptura_avx512_lanes(bytes - at);
        const __mmask64 matching = _mm512_mask_cmpeq_epi8_mask(live, _mm512_maskz_loadu_epi8(live, source + at), broadcast);
        if (matching != 0u)
        {
            return at + scriptura_avx512_lowest(matching);
        }
        at += SCRIPTURA_AVX512_BYTES;
    }
    return bytes;
}

SCRIPTURA_AVX512_TARGET static void scriptura_avx512_copy(void *to, const void *from, unsigned long long bytes)
{
    // the regions are read and written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the regions are read and written as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    unsigned long long at = 0ull;
    while ((bytes - at) >= (4u * SCRIPTURA_AVX512_BYTES))
    {
        const __m512i zeroth = _mm512_loadu_si512(source + at);
        const __m512i first = _mm512_loadu_si512(source + at + SCRIPTURA_AVX512_BYTES);
        const __m512i second = _mm512_loadu_si512(source + at + (2u * SCRIPTURA_AVX512_BYTES));
        const __m512i third = _mm512_loadu_si512(source + at + (3u * SCRIPTURA_AVX512_BYTES));
        _mm512_storeu_si512(target + at, zeroth);
        _mm512_storeu_si512(target + at + SCRIPTURA_AVX512_BYTES, first);
        _mm512_storeu_si512(target + at + (2u * SCRIPTURA_AVX512_BYTES), second);
        _mm512_storeu_si512(target + at + (3u * SCRIPTURA_AVX512_BYTES), third);
        at += 4u * SCRIPTURA_AVX512_BYTES;
    }
    while (at < bytes)
    {
        const __mmask64 live = scriptura_avx512_lanes(bytes - at);
        _mm512_mask_storeu_epi8(target + at, live, _mm512_maskz_loadu_epi8(live, source + at));
        at += SCRIPTURA_AVX512_BYTES;
    }
}

SCRIPTURA_AVX512_TARGET static void scriptura_avx512_move_up(void *to, const void *from, unsigned long long bytes)
{
    // the regions are read and written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the regions are read and written as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    unsigned long long at = bytes;
    while (at >= (4u * SCRIPTURA_AVX512_BYTES))
    {
        at -= 4u * SCRIPTURA_AVX512_BYTES;
        const __m512i third = _mm512_loadu_si512(source + at + (3u * SCRIPTURA_AVX512_BYTES));
        const __m512i second = _mm512_loadu_si512(source + at + (2u * SCRIPTURA_AVX512_BYTES));
        const __m512i first = _mm512_loadu_si512(source + at + SCRIPTURA_AVX512_BYTES);
        const __m512i zeroth = _mm512_loadu_si512(source + at);
        _mm512_storeu_si512(target + at + (3u * SCRIPTURA_AVX512_BYTES), third);
        _mm512_storeu_si512(target + at + (2u * SCRIPTURA_AVX512_BYTES), second);
        _mm512_storeu_si512(target + at + SCRIPTURA_AVX512_BYTES, first);
        _mm512_storeu_si512(target + at, zeroth);
    }
    while (at >= SCRIPTURA_AVX512_BYTES)
    {
        at -= SCRIPTURA_AVX512_BYTES;
        _mm512_storeu_si512(target + at, _mm512_loadu_si512(source + at));
    }
    if (at != 0ull)
    {
        const __mmask64 live = scriptura_avx512_lanes(at);
        _mm512_mask_storeu_epi8(target, live, _mm512_maskz_loadu_epi8(live, source));
    }
}

SCRIPTURA_AVX512_TARGET static int scriptura_avx512_compare(const void *one, const void *other, unsigned long long bytes)
{
    // the regions are read as unsigned bytes
    const unsigned char *const left = (const unsigned char *)one;
    // the regions are read as unsigned bytes
    const unsigned char *const right = (const unsigned char *)other;
    unsigned long long at = 0ull;
    while (at < bytes)
    {
        const __mmask64 live = scriptura_avx512_lanes(bytes - at);
        const __mmask64 differing = _mm512_mask_cmpneq_epi8_mask(live, _mm512_maskz_loadu_epi8(live, left + at),
                                                                 _mm512_maskz_loadu_epi8(live, right + at));
        if (differing != 0u)
        {
            const unsigned long long lane = at + scriptura_avx512_lowest(differing);
            return (left[lane] < right[lane]) ? -1 : 1;
        }
        at += SCRIPTURA_AVX512_BYTES;
    }
    return 0;
}

SCRIPTURA_AVX512_TARGET static void scriptura_avx512_fill(void *to, unsigned char value, unsigned long long bytes)
{
    // the region is written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the byte is broadcast as the signed char the intrinsic takes, bit for bit
    const __m512i spread = _mm512_set1_epi8((char)value);
    unsigned long long at = 0ull;
    while ((bytes - at) >= (4u * SCRIPTURA_AVX512_BYTES))
    {
        _mm512_storeu_si512(target + at, spread);
        _mm512_storeu_si512(target + at + SCRIPTURA_AVX512_BYTES, spread);
        _mm512_storeu_si512(target + at + (2u * SCRIPTURA_AVX512_BYTES), spread);
        _mm512_storeu_si512(target + at + (3u * SCRIPTURA_AVX512_BYTES), spread);
        at += 4u * SCRIPTURA_AVX512_BYTES;
    }
    while (at < bytes)
    {
        _mm512_mask_storeu_epi8(target + at, scriptura_avx512_lanes(bytes - at), spread);
        at += SCRIPTURA_AVX512_BYTES;
    }
}

const ScripturaArm *scriptura_avx512_arm(void)
{
    static const ScripturaArm arm = {"avx512-unrun",
                                     SCRIPTURA_AVX512_BYTES,
                                     scriptura_avx512_length,
                                     scriptura_avx512_find,
                                     scriptura_avx512_copy,
                                     scriptura_avx512_move_up,
                                     scriptura_avx512_compare,
                                     scriptura_avx512_fill};
    return (scriptura_avx512_present() != 0) ? &arm : NULL;
}

#else

const ScripturaArm *scriptura_avx512_arm(void)
{
    return NULL;
}

#endif
