// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "scriptura_arm.h"

#include <stdint.h>

#if ENGINE_TARGET_X86_64

#include <immintrin.h>

#if !defined(_MSC_VER) || defined(__clang__)
#include <cpuid.h>
#endif

#if defined(_MSC_VER) && !defined(__clang__)
#define SCRIPTURA_AVX2_TARGET
#else
#define SCRIPTURA_AVX2_TARGET __attribute__((target("avx2")))
#endif

#define SCRIPTURA_AVX2_BYTES 32u

#ifndef SCRIPTURA_AVX2_STRING_BYTES
#define SCRIPTURA_AVX2_STRING_BYTES 16384ull
#endif

static unsigned int scriptura_avx2_lowest(unsigned int mask)
{
#if defined(_MSC_VER) && !defined(__clang__)
    unsigned long index = 0ul;
    _BitScanForward(&index, mask);
    // the bit index of a non-zero 32 bit mask is 0 to 31
    return (unsigned int)index;
#else
    // the trailing count of a non-zero 32 bit mask is 0 to 31
    return (unsigned int)__builtin_ctz(mask);
#endif
}

static int scriptura_avx2_present(void)
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
    if ((_xgetbv(0u) & 6ull) != 6ull)
    {
        return 0;
    }
    __cpuidex(leaves, 7, 0);
    // leaf 7 ebx is read as its bit pattern
    const unsigned int extended = (unsigned int)leaves[1];
    return (((extended >> 5u) & 1u) != 0u) ? 1 : 0;
#else
    __builtin_cpu_init();
    return __builtin_cpu_supports("avx2") ? 1 : 0;
#endif
}

SCRIPTURA_AVX2_TARGET static unsigned int scriptura_avx2_zeros(__m256i block)
{
    // the movemask's 32 lane bits are read as their pattern
    return (unsigned int)_mm256_movemask_epi8(_mm256_cmpeq_epi8(block, _mm256_setzero_si256()));
}

SCRIPTURA_AVX2_TARGET static unsigned long long scriptura_avx2_length(const char *text, unsigned long long room)
{
    if (room == 0ull)
    {
        return 0ull;
    }
    // the address is read as an integer only for its low bits, and never converted back
    const unsigned long long past = (unsigned long long)((uintptr_t)text & (uintptr_t)(SCRIPTURA_AVX2_BYTES - 1u));
    // the aligned block holding the first byte is read whole, and the lanes before the text are dropped
    const char *block = text - past;
    unsigned int zeros = scriptura_avx2_zeros(_mm256_load_si256((const __m256i *)block)) >> past;
    unsigned long long at = 0ull;
    unsigned long long seen = SCRIPTURA_AVX2_BYTES - past;
    // the address is read as an integer only for its low bits, and never converted back
    while ((zeros == 0u) && (seen < room) && ((((uintptr_t)block + SCRIPTURA_AVX2_BYTES) & 127u) != 0u))
    {
        at = seen;
        block += SCRIPTURA_AVX2_BYTES;
        seen += SCRIPTURA_AVX2_BYTES;
        zeros = scriptura_avx2_zeros(_mm256_load_si256((const __m256i *)block));
    }
    while ((zeros == 0u) && ((seen + (3u * SCRIPTURA_AVX2_BYTES)) < room))
    {
        const __m256i zeroth = _mm256_load_si256((const __m256i *)(block + SCRIPTURA_AVX2_BYTES));
        const __m256i first = _mm256_load_si256((const __m256i *)(block + (2u * SCRIPTURA_AVX2_BYTES)));
        const __m256i second = _mm256_load_si256((const __m256i *)(block + (3u * SCRIPTURA_AVX2_BYTES)));
        const __m256i third = _mm256_load_si256((const __m256i *)(block + (4u * SCRIPTURA_AVX2_BYTES)));
        const __m256i least = _mm256_min_epu8(_mm256_min_epu8(zeroth, first), _mm256_min_epu8(second, third));
        if (scriptura_avx2_zeros(least) != 0u)
        {
            break;
        }
        block += 4u * SCRIPTURA_AVX2_BYTES;
        seen += 4u * SCRIPTURA_AVX2_BYTES;
    }
    while ((zeros == 0u) && (seen < room))
    {
        at = seen;
        block += SCRIPTURA_AVX2_BYTES;
        seen += SCRIPTURA_AVX2_BYTES;
        zeros = scriptura_avx2_zeros(_mm256_load_si256((const __m256i *)block));
    }
    if (zeros == 0u)
    {
        return room;
    }
    const unsigned long long found = at + scriptura_avx2_lowest(zeros);
    return (found < room) ? found : room;
}

SCRIPTURA_AVX2_TARGET static unsigned long long scriptura_avx2_find(const void *from, unsigned char value,
                                                                     unsigned long long bytes)
{
    if (bytes < SCRIPTURA_AVX2_BYTES)
    {
        return scriptura_portable_find(from, value, bytes);
    }
    // the region is read as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    // the byte is broadcast as the signed char the intrinsic takes, bit for bit
    const __m256i broadcast = _mm256_set1_epi8((char)value);
    const unsigned long long last = bytes - SCRIPTURA_AVX2_BYTES;
    unsigned long long at = 0ull;
    while ((at + (4u * SCRIPTURA_AVX2_BYTES)) <= last)
    {
        const __m256i zeroth = _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(source + at)), broadcast);
        const __m256i first =
            _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(source + at + SCRIPTURA_AVX2_BYTES)), broadcast);
        const __m256i second =
            _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(source + at + (2u * SCRIPTURA_AVX2_BYTES))), broadcast);
        const __m256i third =
            _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(source + at + (3u * SCRIPTURA_AVX2_BYTES))), broadcast);
        const __m256i any = _mm256_or_si256(_mm256_or_si256(zeroth, first), _mm256_or_si256(second, third));
        if (_mm256_testz_si256(any, any) == 0)
        {
            break;
        }
        at += 4u * SCRIPTURA_AVX2_BYTES;
    }
    while (at < last)
    {
        // the movemask's 32 lane bits are read as their pattern
        const unsigned int matching = (unsigned int)_mm256_movemask_epi8(
            _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(source + at)), broadcast));
        if (matching != 0u)
        {
            return at + scriptura_avx2_lowest(matching);
        }
        at += SCRIPTURA_AVX2_BYTES;
    }
    // the movemask's 32 lane bits are read as their pattern
    const unsigned int matching = (unsigned int)_mm256_movemask_epi8(
        _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(source + last)), broadcast));
    return (matching != 0u) ? (last + scriptura_avx2_lowest(matching)) : bytes;
}

SCRIPTURA_AVX2_TARGET static void scriptura_avx2_copy(void *to, const void *from, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_AVX2_BYTES)
    {
        scriptura_portable_copy(to, from, bytes);
        return;
    }
    // the regions are read and written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the regions are read and written as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    const unsigned long long last = bytes - SCRIPTURA_AVX2_BYTES;
    const __m256i closing = _mm256_loadu_si256((const __m256i *)(source + last));
    unsigned long long at = 0ull;
    while ((at + (4u * SCRIPTURA_AVX2_BYTES)) <= last)
    {
        const __m256i zeroth = _mm256_loadu_si256((const __m256i *)(source + at));
        const __m256i first = _mm256_loadu_si256((const __m256i *)(source + at + SCRIPTURA_AVX2_BYTES));
        const __m256i second = _mm256_loadu_si256((const __m256i *)(source + at + (2u * SCRIPTURA_AVX2_BYTES)));
        const __m256i third = _mm256_loadu_si256((const __m256i *)(source + at + (3u * SCRIPTURA_AVX2_BYTES)));
        _mm256_storeu_si256((__m256i *)(target + at), zeroth);
        _mm256_storeu_si256((__m256i *)(target + at + SCRIPTURA_AVX2_BYTES), first);
        _mm256_storeu_si256((__m256i *)(target + at + (2u * SCRIPTURA_AVX2_BYTES)), second);
        _mm256_storeu_si256((__m256i *)(target + at + (3u * SCRIPTURA_AVX2_BYTES)), third);
        at += 4u * SCRIPTURA_AVX2_BYTES;
    }
    while (at < last)
    {
        _mm256_storeu_si256((__m256i *)(target + at), _mm256_loadu_si256((const __m256i *)(source + at)));
        at += SCRIPTURA_AVX2_BYTES;
    }
    _mm256_storeu_si256((__m256i *)(target + last), closing);
}

SCRIPTURA_AVX2_TARGET static void scriptura_avx2_move_up(void *to, const void *from, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_AVX2_BYTES)
    {
        scriptura_portable_move_up(to, from, bytes);
        return;
    }
    // the regions are read and written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the regions are read and written as unsigned bytes
    const unsigned char *const source = (const unsigned char *)from;
    const __m256i opening = _mm256_loadu_si256((const __m256i *)source);
    unsigned long long at = bytes;
    while (at > (4u * SCRIPTURA_AVX2_BYTES))
    {
        at -= 4u * SCRIPTURA_AVX2_BYTES;
        const __m256i third = _mm256_loadu_si256((const __m256i *)(source + at + (3u * SCRIPTURA_AVX2_BYTES)));
        const __m256i second = _mm256_loadu_si256((const __m256i *)(source + at + (2u * SCRIPTURA_AVX2_BYTES)));
        const __m256i first = _mm256_loadu_si256((const __m256i *)(source + at + SCRIPTURA_AVX2_BYTES));
        const __m256i zeroth = _mm256_loadu_si256((const __m256i *)(source + at));
        _mm256_storeu_si256((__m256i *)(target + at + (3u * SCRIPTURA_AVX2_BYTES)), third);
        _mm256_storeu_si256((__m256i *)(target + at + (2u * SCRIPTURA_AVX2_BYTES)), second);
        _mm256_storeu_si256((__m256i *)(target + at + SCRIPTURA_AVX2_BYTES), first);
        _mm256_storeu_si256((__m256i *)(target + at), zeroth);
    }
    while (at > SCRIPTURA_AVX2_BYTES)
    {
        at -= SCRIPTURA_AVX2_BYTES;
        _mm256_storeu_si256((__m256i *)(target + at), _mm256_loadu_si256((const __m256i *)(source + at)));
    }
    _mm256_storeu_si256((__m256i *)target, opening);
}

SCRIPTURA_AVX2_TARGET static int scriptura_avx2_compare(const void *one, const void *other, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_AVX2_BYTES)
    {
        return scriptura_portable_compare(one, other, bytes);
    }
    // the regions are read as unsigned bytes
    const unsigned char *const left = (const unsigned char *)one;
    // the regions are read as unsigned bytes
    const unsigned char *const right = (const unsigned char *)other;
    const unsigned long long last = bytes - SCRIPTURA_AVX2_BYTES;
    unsigned long long at = 0ull;
    while ((at + (4u * SCRIPTURA_AVX2_BYTES)) <= last)
    {
        const __m256i zeroth = _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(left + at)),
                                                 _mm256_loadu_si256((const __m256i *)(right + at)));
        const __m256i first = _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(left + at + SCRIPTURA_AVX2_BYTES)),
                                                _mm256_loadu_si256((const __m256i *)(right + at + SCRIPTURA_AVX2_BYTES)));
        const __m256i second =
            _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(left + at + (2u * SCRIPTURA_AVX2_BYTES))),
                              _mm256_loadu_si256((const __m256i *)(right + at + (2u * SCRIPTURA_AVX2_BYTES))));
        const __m256i third =
            _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(left + at + (3u * SCRIPTURA_AVX2_BYTES))),
                              _mm256_loadu_si256((const __m256i *)(right + at + (3u * SCRIPTURA_AVX2_BYTES))));
        const __m256i all = _mm256_and_si256(_mm256_and_si256(zeroth, first), _mm256_and_si256(second, third));
        // the movemask's 32 lane bits are read as their pattern
        if ((unsigned int)_mm256_movemask_epi8(all) != 0xFFFFFFFFu)
        {
            break;
        }
        at += 4u * SCRIPTURA_AVX2_BYTES;
    }
    while (at < last)
    {
        // the movemask's 32 lane bits are read as their pattern
        const unsigned int equal = (unsigned int)_mm256_movemask_epi8(
            _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(left + at)),
                              _mm256_loadu_si256((const __m256i *)(right + at))));
        if (equal != 0xFFFFFFFFu)
        {
            const unsigned long long lane = at + scriptura_avx2_lowest(~equal);
            return (left[lane] < right[lane]) ? -1 : 1;
        }
        at += SCRIPTURA_AVX2_BYTES;
    }
    // the movemask's 32 lane bits are read as their pattern
    const unsigned int closing = (unsigned int)_mm256_movemask_epi8(
        _mm256_cmpeq_epi8(_mm256_loadu_si256((const __m256i *)(left + last)),
                          _mm256_loadu_si256((const __m256i *)(right + last))));
    if (closing == 0xFFFFFFFFu)
    {
        return 0;
    }
    const unsigned long long lane = last + scriptura_avx2_lowest(~closing);
    return (left[lane] < right[lane]) ? -1 : 1;
}

SCRIPTURA_AVX2_TARGET static void scriptura_avx2_fill(void *to, unsigned char value, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_AVX2_BYTES)
    {
        scriptura_portable_fill(to, value, bytes);
        return;
    }
    // the region is written as unsigned bytes
    unsigned char *const target = (unsigned char *)to;
    // the byte is broadcast as the signed char the intrinsic takes, bit for bit
    const __m256i spread = _mm256_set1_epi8((char)value);
    const unsigned long long last = bytes - SCRIPTURA_AVX2_BYTES;
    unsigned long long at = 0ull;
    while ((at + (4u * SCRIPTURA_AVX2_BYTES)) <= last)
    {
        _mm256_storeu_si256((__m256i *)(target + at), spread);
        _mm256_storeu_si256((__m256i *)(target + at + SCRIPTURA_AVX2_BYTES), spread);
        _mm256_storeu_si256((__m256i *)(target + at + (2u * SCRIPTURA_AVX2_BYTES)), spread);
        _mm256_storeu_si256((__m256i *)(target + at + (3u * SCRIPTURA_AVX2_BYTES)), spread);
        at += 4u * SCRIPTURA_AVX2_BYTES;
    }
    while (at < last)
    {
        _mm256_storeu_si256((__m256i *)(target + at), spread);
        at += SCRIPTURA_AVX2_BYTES;
    }
    _mm256_storeu_si256((__m256i *)(target + last), spread);
}

static int scriptura_avx2_strings_present(void)
{
#if defined(_MSC_VER) && !defined(__clang__)
    int leaves[4];
    __cpuidex(leaves, 7, 0);
    // leaf 7 ebx is read as its bit pattern
    const unsigned int extended = (unsigned int)leaves[1];
#else
    unsigned int eax = 0u;
    unsigned int extended = 0u;
    unsigned int ecx = 0u;
    unsigned int edx = 0u;
    if (__get_cpuid_count(7u, 0u, &eax, &extended, &ecx, &edx) == 0)
    {
        return 0;
    }
#endif
    return (((extended >> 9u) & 1u) != 0u) ? 1 : 0;
}

static void scriptura_avx2_string_copy(unsigned char *target, const unsigned char *source, unsigned long long bytes)
{
#if defined(_MSC_VER) && !defined(__clang__)
    // the byte count is at most the address space, which a size_t holds
    __movsb(target, source, (size_t)bytes);
#else
    __asm__ __volatile__("rep movsb" : "+D"(target), "+S"(source), "+c"(bytes) : : "memory");
#endif
}

static void scriptura_avx2_string_fill(unsigned char *target, unsigned char value, unsigned long long bytes)
{
#if defined(_MSC_VER) && !defined(__clang__)
    // the byte count is at most the address space, which a size_t holds
    __stosb(target, value, (size_t)bytes);
#else
    __asm__ __volatile__("rep stosb" : "+D"(target), "+c"(bytes) : "a"(value) : "memory");
#endif
}

static void scriptura_avx2_strings_copy(void *to, const void *from, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_AVX2_STRING_BYTES)
    {
        scriptura_avx2_copy(to, from, bytes);
        return;
    }
    // the regions are read and written as unsigned bytes
    scriptura_avx2_string_copy((unsigned char *)to, (const unsigned char *)from, bytes);
}

static void scriptura_avx2_strings_fill(void *to, unsigned char value, unsigned long long bytes)
{
    if (bytes < SCRIPTURA_AVX2_STRING_BYTES)
    {
        scriptura_avx2_fill(to, value, bytes);
        return;
    }
    // the region is written as unsigned bytes
    scriptura_avx2_string_fill((unsigned char *)to, value, bytes);
}

const ScripturaArm *scriptura_avx2_arm(void)
{
    static const ScripturaArm arm = {"avx2",
                                     SCRIPTURA_AVX2_BYTES,
                                     scriptura_avx2_length,
                                     scriptura_avx2_find,
                                     scriptura_avx2_copy,
                                     scriptura_avx2_move_up,
                                     scriptura_avx2_compare,
                                     scriptura_avx2_fill};
    static const ScripturaArm strings_arm = {"avx2-erms",
                                             SCRIPTURA_AVX2_BYTES,
                                             scriptura_avx2_length,
                                             scriptura_avx2_find,
                                             scriptura_avx2_strings_copy,
                                             scriptura_avx2_move_up,
                                             scriptura_avx2_compare,
                                             scriptura_avx2_strings_fill};
    if (scriptura_avx2_present() == 0)
    {
        return NULL;
    }
    return (scriptura_avx2_strings_present() != 0) ? &strings_arm : &arm;
}

#else

const ScripturaArm *scriptura_avx2_arm(void)
{
    return NULL;
}

#endif
