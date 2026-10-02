// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// engine_config_platform.h: targets, the double's fields, helpers, error codes and the error frame (engine_config.h
// includes the parts in order)
#ifndef ENGINE_CONFIG_PLATFORM_H
#define ENGINE_CONFIG_PLATFORM_H

#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <time.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define ENGINE_AXES 3u

#if defined(_WIN32)
#define ENGINE_PATH_CAPACITY 32768u
#else
#if defined(__linux__)
// strict C11 leaves PATH_MAX out of limits.h; the kernel's header states it
#include <linux/limits.h>
#endif
// PATH_MAX is a positive int, which fits in an unsigned int
#define ENGINE_PATH_CAPACITY ((unsigned int)PATH_MAX)
#endif

#if defined(__has_builtin)
#define ENGINE_HAS_BUILTIN(builtin_) __has_builtin(builtin_)
#else
#define ENGINE_HAS_BUILTIN(builtin_) 0
#endif

#if defined(__x86_64__) || defined(_M_X64)
#define ENGINE_TARGET_X86_64 1
#else
#define ENGINE_TARGET_X86_64 0
#endif

#if defined(__aarch64__) || defined(_M_ARM64)
#define ENGINE_TARGET_AARCH64 1
#else
#define ENGINE_TARGET_AARCH64 0
#endif

#define ENGINE_DOUBLE_SIGN_MASK 0x8000000000000000ull
#define ENGINE_DOUBLE_EXP_MASK 0x7FF0000000000000ull
#define ENGINE_DOUBLE_MANT_MASK 0x000FFFFFFFFFFFFFull
#define ENGINE_DOUBLE_SIGN_SHIFT 63u
#define ENGINE_DOUBLE_MANT_BITS 52u
#define ENGINE_DOUBLE_EXP_BITS 11u
#define ENGINE_DOUBLE_SIGN_ONE 0x1ull
#define ENGINE_DOUBLE_EXP_ALL 0x7FFull
#define ENGINE_DOUBLE_BIAS 1023
#define ENGINE_DOUBLE_BITS 64u
#define ENGINE_DOUBLE_SCALE_MAX ((int)(ENGINE_DOUBLE_EXP_ALL - 1u) - ENGINE_DOUBLE_BIAS - (int)ENGINE_DOUBLE_MANT_BITS)
#define ENGINE_DOUBLE_SCALE_MIN (1 - ENGINE_DOUBLE_BIAS - (int)ENGINE_DOUBLE_MANT_BITS)

    static inline unsigned long long engine_clock_microseconds(void)
    {
        struct timespec now;
        timespec_get(&now, TIME_UTC);
        // tv_sec and tv_nsec are non-negative after timespec_get. They re-sign to unsigned long long exactly
        return ((unsigned long long)now.tv_sec * 1000000ull) + ((unsigned long long)now.tv_nsec / 1000ull);
    }

    static inline unsigned int engine_word_population(unsigned long long word)
    {
        const unsigned long long pairs = word - ((word >> 1u) & 0x5555555555555555ULL);
        const unsigned long long nibbles = (pairs & 0x3333333333333333ULL) + ((pairs >> 2u) & 0x3333333333333333ULL);
        const unsigned long long bytes = (nibbles + (nibbles >> 4u)) & 0x0F0F0F0F0F0F0F0FULL;
        return (unsigned int)((bytes * 0x0101010101010101ULL) >> 56u);
    }

    static inline bool engine_object_reserve(unsigned int **words, size_t *capacity, size_t wanted, size_t width)
    {
        *capacity += (size_t)(wanted > *capacity) * ((2u * wanted) - *capacity);
        unsigned int *const grown = (unsigned int *)realloc(*words, (*capacity + 1u) * width * sizeof(unsigned int));
        *words = grown ? grown : *words;
        return !!grown;
    }

    static inline int engine_leaf_of_peak(const unsigned int *peaks, unsigned int count, unsigned int peak)
    {
        unsigned int low = 0u;
        unsigned int high = count;
        while (low < high)
        {
            const unsigned int middle = low + (high - low) / 2u;
            if (peaks[middle] < peak)
            {
                low = middle + 1u;
            }
            else
            {
                high = middle;
            }
        }
        return ((low < count) && (peaks[low] == peak)) ? (int)low : -1;
    }

    static inline unsigned int engine_find_root(unsigned int *parent, unsigned int member)
    {
        while (parent[member] != member)
        {
            parent[member] = parent[parent[member]];
            member = parent[member];
        }
        return member;
    }

    static inline unsigned int engine_packed_unsigned(const unsigned int *record, unsigned int offset,
                                                      unsigned int bits)
    {
        unsigned int value = 0u;
        for (unsigned int bit = 0u; bit < bits; bit += 1u)
        {
            const unsigned int at = offset + bit;
            value |= ((record[at / 32u] >> (at % 32u)) & 1u) << bit;
        }
        return value;
    }

    static inline int engine_packed_signed(const unsigned int *record, unsigned int offset, unsigned int bits)
    {
        unsigned int value = 0u;
        for (unsigned int bit = 0u; bit < bits; bit += 1u)
        {
            const unsigned int at = offset + bit;
            value |= ((record[at / 32u] >> (at % 32u)) & 1u) << bit;
        }
        const unsigned int top = 1u << (bits - 1u);
        return ((value & top) != 0u) ? ((int)value - (int)(top << 1u)) : (int)value;
    }

    typedef enum
    {
        ENGINE_ERROR_NONE = 0,
        ENGINE_ERROR_REQUEST = 1,
        ENGINE_ERROR_RESOURCE = 2,
        ENGINE_ERROR_LOGIC = 3
    } EngineErrorKind;

    typedef enum
    {
        ENGINE_MODULE_ENGINE = 0,
        ENGINE_MODULE_MAX_TREE = 1,
        ENGINE_MODULE_FLATTEN = 2,
        ENGINE_MODULE_DECIMAL_DOUBLE = 3,
        ENGINE_MODULE_UNIT_SWEEP = 4,
        ENGINE_MODULE_CYCLE = 5,
        ENGINE_MODULE_KEYMATH = 6,
        ENGINE_MODULE_KEY_SCHEDULE = 7,
        ENGINE_MODULE_RESIDUAL = 8,
        ENGINE_MODULE_GROW = 9,
        ENGINE_MODULE_APXREP = 10,
        ENGINE_MODULE_KREP = ENGINE_MODULE_APXREP,
        ENGINE_MODULE_COMPRESSION = 11,
        ENGINE_MODULE_TOWER = 12,
        ENGINE_MODULE_ENTROPY_HISTORY = 13,
        ENGINE_MODULE_ZIP = 14,
        ENGINE_MODULE_NPY = 15,
        ENGINE_MODULE_DICOM = 16,
        ENGINE_MODULE_OBSIGNATIO = 17,
        ENGINE_MODULE_TESSERA = 18,
        ENGINE_MODULE_PERIOD = 19,
        ENGINE_MODULE_QASM = 20,
        ENGINE_MODULE_NOISE_DETECTOR = 21,
        ENGINE_MODULE_DEVICE_POOL = 22,
        ENGINE_MODULE_INTERFACE = 23
    } EngineModule;

#if defined(_MSC_VER)
#include <intrin.h>
    extern const char __ImageBase;
#define ENGINE_IMAGE_BASE ((const void *)&__ImageBase)
#define ENGINE_RETURN_ADDRESS() ((const void *)_ReturnAddress())
#define ENGINE_NOINLINE __declspec(noinline)
// a header helper kept out of line: MSVC takes noinline on an inline function, and an unused plain static warns
#define ENGINE_NOINLINE_HELPER __declspec(noinline) static inline
#elif defined(__GNUC__)
// a PE image's linker names its base __ImageBase, as MSVC's does, and an ELF image's names its header __ehdr_start
#if defined(_WIN32)
extern const char __ImageBase;
#define ENGINE_IMAGE_BASE ((const void *)&__ImageBase)
#else
extern const char __ehdr_start;
#define ENGINE_IMAGE_BASE ((const void *)&__ehdr_start)
#endif
#define ENGINE_RETURN_ADDRESS() ((const void *)__builtin_return_address(0))
#define ENGINE_NOINLINE __attribute__((noinline))
// a header helper kept out of line: gcc errors noinline on an inline function. It is a static marked unused
#define ENGINE_NOINLINE_HELPER __attribute__((noinline, unused)) static
#else
#error "the engine needs its image base, a return address and noinline from the compiler"
#endif

#define ENGINE_ERROR_FRAMES 16u

    typedef struct
    {
        EngineErrorKind kind;
        EngineModule module;
        unsigned int site;
        int status;
        const void *execaddr;
        const void *evacaddr;
        const void *imagebase;
        unsigned int frame_count;
        const void *frames[ENGINE_ERROR_FRAMES];
    } EngineError;

    static inline void engine_error_raise(EngineError *error, EngineErrorKind kind, EngineModule module,
                                          unsigned int site, int status, const void *execaddr, const void *evacaddr)
    {
        if (error->kind == ENGINE_ERROR_NONE)
        {
            error->kind = kind;
            error->module = module;
            error->site = site;
            error->status = status;
            error->execaddr = execaddr;
            error->evacaddr = evacaddr;
            error->imagebase = ENGINE_IMAGE_BASE;
            error->frame_count = 0u;
        }
    }

    ENGINE_NOINLINE_HELPER int engine_error_check(int condition, EngineErrorKind kind, EngineModule module,
                                                  unsigned int site, const void *evacaddr, EngineError *error)
    {
        if (condition == 0)
        {
            engine_error_raise(error, kind, module, site, 0, ENGINE_RETURN_ADDRESS(), evacaddr);
        }
        return (condition != 0) ? 1 : 0;
    }

    ENGINE_NOINLINE_HELPER int engine_status_check(int status, EngineModule module, unsigned int site,
                                                   const void *evacaddr, EngineError *error)
    {
        if (status != 0)
        {
            engine_error_raise(error, ENGINE_ERROR_RESOURCE, module, site, status, ENGINE_RETURN_ADDRESS(), evacaddr);
        }
        return (status == 0) ? 1 : 0;
    }

    ENGINE_NOINLINE_HELPER int engine_io_check(int condition, EngineModule module, unsigned int site,
                                               const void *evacaddr, EngineError *error)
    {
        if (condition == 0)
        {
            engine_error_raise(error, ENGINE_ERROR_RESOURCE, module, site, errno, ENGINE_RETURN_ADDRESS(), evacaddr);
        }
        return (condition != 0) ? 1 : 0;
    }

    ENGINE_NOINLINE_HELPER void engine_error_frame(EngineError *error)
    {
        if ((error->kind != ENGINE_ERROR_NONE) && (error->frame_count < ENGINE_ERROR_FRAMES))
        {
            error->frames[error->frame_count] = ENGINE_RETURN_ADDRESS();
            error->frame_count += 1u;
        }
    }

#ifdef __cplusplus
}
#endif

#endif
