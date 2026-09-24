// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef ENGINE_CONFIG_H
#define ENGINE_CONFIG_H

#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ENGINE_AXES 3u

#if defined(_WIN32)
#define ENGINE_PATH_ROOM 32768u
#else
#if defined(__linux__)
// strict C11 leaves PATH_MAX out of limits.h; the kernel's header states it
#include <linux/limits.h>
#endif
// PATH_MAX is a positive int, held whole in an unsigned int
#define ENGINE_PATH_ROOM ((unsigned int)PATH_MAX)
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
    // tv_sec and tv_nsec are non-negative after timespec_get; they re-sign to unsigned long long exactly
    return ((unsigned long long)now.tv_sec * 1000000ull) + ((unsigned long long)now.tv_nsec / 1000ull);
}

static inline unsigned int engine_word_population(unsigned long long word)
{
    const unsigned long long pairs = word - ((word >> 1u) & 0x5555555555555555ULL);
    const unsigned long long nibbles = (pairs & 0x3333333333333333ULL) + ((pairs >> 2u) & 0x3333333333333333ULL);
    const unsigned long long bytes = (nibbles + (nibbles >> 4u)) & 0x0F0F0F0F0F0F0F0FULL;
    return (unsigned int)((bytes * 0x0101010101010101ULL) >> 56u);
}

static inline bool engine_object_room_fit(unsigned int **words, size_t *room, size_t wanted, size_t width)
{
    *room += (size_t)(wanted > *room) * ((2u * wanted) - *room);
    unsigned int *const grown = (unsigned int *)realloc(*words, (*room + 1u) * width * sizeof(unsigned int));
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

static inline unsigned int engine_packed_unsigned(const unsigned int *record, unsigned int offset, unsigned int bits)
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
    ENGINE_MODULE_KREP = 10,
    ENGINE_MODULE_COMPRESSION = 11,
    ENGINE_MODULE_TOWER = 12,
    ENGINE_MODULE_ENTROPY_HISTORY = 13,
    ENGINE_MODULE_ZIP = 14,
    ENGINE_MODULE_NPY = 15,
    ENGINE_MODULE_DICOM = 16,
    ENGINE_MODULE_OBSIGNATIO = 17,
    ENGINE_MODULE_TESSERA = 18,
    ENGINE_MODULE_PERIOD = 19
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
extern const char __ehdr_start;
#define ENGINE_IMAGE_BASE ((const void *)&__ehdr_start)
#define ENGINE_RETURN_ADDRESS() ((const void *)__builtin_return_address(0))
#define ENGINE_NOINLINE __attribute__((noinline))
// a header helper kept out of line: gcc refuses noinline on an inline function; it is a static marked unused
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

static inline void engine_error_raise(EngineError *error, EngineErrorKind kind, EngineModule module, unsigned int site,
                                      int status, const void *execaddr, const void *evacaddr)
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

ENGINE_NOINLINE_HELPER int engine_error_check(int held, EngineErrorKind kind, EngineModule module,
                                                    unsigned int site, const void *evacaddr, EngineError *error)
{
    if (held == 0)
    {
        engine_error_raise(error, kind, module, site, 0, ENGINE_RETURN_ADDRESS(), evacaddr);
    }
    return (held != 0) ? 1 : 0;
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

ENGINE_NOINLINE_HELPER int engine_io_check(int held, EngineModule module, unsigned int site,
                                                 const void *evacaddr, EngineError *error)
{
    if (held == 0)
    {
        engine_error_raise(error, ENGINE_ERROR_RESOURCE, module, site, errno, ENGINE_RETURN_ADDRESS(), evacaddr);
    }
    return (held != 0) ? 1 : 0;
}

ENGINE_NOINLINE_HELPER void engine_error_frame(EngineError *error)
{
    if ((error->kind != ENGINE_ERROR_NONE) && (error->frame_count < ENGINE_ERROR_FRAMES))
    {
        error->frames[error->frame_count] = ENGINE_RETURN_ADDRESS();
        error->frame_count += 1u;
    }
}

#define ENGINE_FROM_ATOM 0xFFFFFFFFu

typedef struct
{
    const unsigned short *lanes;
    unsigned long long depth;
    unsigned long long height;
    unsigned long long width;
} Atom;

typedef enum
{
    ENGINE_SMOOTH = 1,
    ENGINE_KEEP = 2,
    ENGINE_SCALE_SUBTRACT = 3
} EngineOperation;

typedef struct
{
    EngineOperation operation;
    unsigned int orders[3];
    unsigned int shift;
} EngineStep;

typedef struct
{
    unsigned long long taps;
    unsigned long long limbs;
    unsigned long long first;
    unsigned long long growth_bits;
} EngineKeyRow;

typedef struct
{
    unsigned int negative;
    unsigned long long shift;
    EngineKeyRow row[ENGINE_AXES];
} EngineKeyTerm;

typedef struct
{
    unsigned int terms;
    EngineKeyTerm *term;
    unsigned int *limbs;
    unsigned long long limb_count;
} EngineKey;

typedef struct
{
    unsigned int axis;
    unsigned int taps;
    unsigned int row_limbs;
    unsigned int in_limbs;
    unsigned int out_limbs;
    unsigned int in_plane;
    unsigned int out_plane;
    unsigned int reserved;
    unsigned long long weights;
} DeviceSweep;

typedef struct
{
    unsigned int negative;
    unsigned int shift;
    DeviceSweep sweep[ENGINE_AXES];
} DeviceTerm;

typedef struct CycleKey CycleKey;

typedef struct
{
    unsigned int terms;
    unsigned int bits;
    unsigned int columns;
    unsigned int planes;
    unsigned long long reach[3];
    DeviceTerm *term_table;
    unsigned int *weights;
    unsigned long long weight_count;
} EngineKeyLayout;

typedef enum
{
    ENGINE_RECORD_FIELD = 1,
    ENGINE_RECORD_CONSTANT = 2,
    ENGINE_RECORD_PRODUCT = 3,
    ENGINE_RECORD_SUM = 4,
    ENGINE_RECORD_DIFFERENCE = 5,
    ENGINE_RECORD_LADDER = 6,
    ENGINE_RECORD_ABSOLUTE = 7,
    ENGINE_RECORD_COMPARE = 8,
    ENGINE_RECORD_FIELD_SIGNED = 9,
    ENGINE_RECORD_TABLE = 10,
    // the exact integer's division as register operations: the quotient rounds toward zero and the remainder
    // carries the numerator's sign (left = quotient . right + remainder); the gcd is never negative; the exact
    // quotient is the multiply-and-mask division, and a remainder refuses the lane. A zero divisor refuses the lane.
    ENGINE_RECORD_QUOTIENT = 11,
    ENGINE_RECORD_REMAINDER = 12,
    ENGINE_RECORD_GCD = 13,
    ENGINE_RECORD_EXACT_QUOTIENT = 14
} EngineRecordOperation;

#define ENGINE_GOLDEN_RUNGS 92u

#define ENGINE_RECORD_LIMBS_MOST 256u

// The step count is the scheduler's n, held apart from the register file's limb width. A chain long
// enough to reach it is meant to run with register reuse on, or to be composed into ENGINE_RECORD_TABLE
// steps, since the file (ENGINE_RECORD_LIMBS_MOST limbs of live registers) is the binding resource.
#define ENGINE_RECORD_STEPS_MAX 1024u

// A lookup table's index is the low bits of one register; it fits a single limb.
#define ENGINE_RECORD_TABLE_INDEX_BITS_MOST 32u

#define ENGINE_RECORD_MEMBERS_MAX 3u

typedef struct
{
    EngineRecordOperation operation;
    unsigned int left;
    unsigned int right;
    unsigned int member;
} EngineRecordStep;

// One lookup table: the low `index_bits` of the source register select one of `1 << index_bits`
// entries, each `out_bits` wide, laid out as (1 << index_bits) rows of ((out_bits + 31) / 32) limbs.
// This is the engine's nonlinear edge (kolmogorov_arnold.md): a general one-variable function over a
// lane's alphabet, built once and composed with another table by reading one through the other.
typedef struct
{
    unsigned int index_bits;
    unsigned int out_bits;
    const unsigned int *values;
} EngineRecordTable;

typedef struct
{
    EngineRecordOperation operation;
    unsigned int left;
    unsigned int right;
    unsigned int bits;
    unsigned int member;
    unsigned long long constant;
} EngineRecordTerm;

typedef struct
{
    unsigned int steps;
    unsigned int members;
    EngineRecordTerm *term;
    unsigned int outputs;
    unsigned int *output;
    unsigned int tables;
    EngineRecordTable *table;
    unsigned int *table_values;
    unsigned long long table_word_count;
} EngineRecordKey;

typedef struct
{
    unsigned int operation;
    unsigned int left;
    unsigned int right;
    unsigned int limbs;
    unsigned int place;
    unsigned int left_limbs;
    unsigned int right_limbs;
    unsigned int out_offset;
    unsigned int out_bits;
    unsigned int member;
    unsigned int table_offset;
    unsigned int index_bits;
} DeviceRecordStep;

typedef struct CycleRecord CycleRecord;

typedef struct
{
    unsigned int steps;
    unsigned int members;
    unsigned int file_limbs;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int out_bits;
    unsigned int out_limbs;
    DeviceRecordStep *step_table;
    unsigned int *table_values;
    unsigned long long table_word_count;
} EngineRecordLayout;

#define ENGINE_RESIDUAL_LIMBS 9u

typedef struct
{
    unsigned long long moments[6];
    unsigned long long sums[3];
    unsigned int level[ENGINE_RESIDUAL_LIMBS];
    unsigned int peak;
    unsigned int mass;
    unsigned int touches;
    unsigned int code;
    unsigned int sample;
    unsigned int frame;
    unsigned int id;
    unsigned int state;
    unsigned int parent;
    int forward;
    int backward;
    int velocity[3];
} EngineBody;

typedef struct
{
    unsigned int leaf_count;
    unsigned int *peaks;
    unsigned int *sizes;
    unsigned long long *sums;
    unsigned long long *moments;
    unsigned int *touches;
    unsigned int *joined;
    unsigned int joined_count;
} EngineLeaves;

typedef struct
{
    unsigned int voxels;
    const unsigned int *labels;
    const unsigned int *peaks;
    unsigned int leaf_count;
    int *leaf_at_peak;
    unsigned int *start;
    unsigned int *grouped;
} EngineGroupRequest;

typedef struct
{
    const unsigned short *volume;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int smooth_orders[ENGINE_AXES];
    unsigned int background_orders[ENGINE_AXES];
    unsigned int unit_sweep;
    EngineError *error;
} EngineResidualRequest;

#define ENGINE_RESIDUAL_BY_UNIT_SWEEP 0u

#define ENGINE_RESIDUAL_BY_KEY 1u

#define ENGINE_RESIDUAL_BOTH_PROVED 2u

#define ENGINE_COEFFICIENT_LIMIT (1ll << 30)

typedef struct
{
    unsigned long long extent[4];
    unsigned long long chunks;
    unsigned long long bits;
    unsigned long long lane_offset;
    const unsigned long long *offsets;
    const unsigned int *stream;
} EngineStream;

#define ENGINE_SIGNUM_BYTES 32u

typedef struct
{
    unsigned char bytes[ENGINE_SIGNUM_BYTES];
} EngineSignum;

typedef enum
{
    ENGINE_SEAL_SAMPLE = 0,
    ENGINE_SEAL_STREAM = 1,
    ENGINE_SEAL_SIDE = 2,
    ENGINE_SEAL_MEMBERS = 3,
    ENGINE_SEAL_SIDE_STORED = 4,
    ENGINE_SEAL_SIDE_INFLATED = 5,
    ENGINE_SEAL_ROOTS = 6
} EngineSealRoot;

typedef struct
{
    EngineSignum roots[ENGINE_SEAL_ROOTS];
    EngineSignum *lane_nodes;
    unsigned long long lane_count;
    EngineSignum *chunk_leaves;
    unsigned long long chunk_count;
} EngineSeal;

#define ENGINE_HISTORY_WINDOW 11u

#define ENGINE_HISTORY_BITS 16u

#define ENGINE_HISTORY_WINDOWS_MAX 16u

typedef struct
{
    unsigned long long extent[4];
    unsigned long long windows;
    EngineSignum sample;
    unsigned long long payload_crc;
    unsigned long long cloud_crc;
    unsigned long long *cloud;
    unsigned long long *history;
} EngineHistory;

#define ENGINE_BODY_WORDS 11u

#define ENGINE_BODY_PEAK 0u

#define ENGINE_BODY_MASS 1u

#define ENGINE_BODY_SUMS 2u

#define ENGINE_BODY_MOMENTS 5u

typedef struct
{
    unsigned long long extent[4];
    unsigned long long frames;
    unsigned long long bodies;
    unsigned long long crc;
    unsigned long long *frame_start;
    unsigned long long *words;
} EngineBodyTable;

#define ENGINE_BYTES_REFUSED (-1LL)

typedef struct
{
    const unsigned char *in;
    unsigned long long in_bytes;
    unsigned char *out;
    unsigned long long out_room;
} EngineBytesRequest;

typedef long long (*EngineBytesDecode)(const EngineBytesRequest *request);

typedef enum
{
    ENGINE_CODEC_RAW = 0,
    ENGINE_CODEC_ZSTD = 1,
    ENGINE_CODEC_ZLIB = 2,
    ENGINE_CODEC_GZIP = 3,
    ENGINE_CODEC_DEFLATE = 4,
    ENGINE_CODEC_LZ4 = 5,
    ENGINE_CODEC_LZ4_FRAME = 6,
    ENGINE_CODEC_SNAPPY = 7,
    ENGINE_CODEC_BLOSCLZ = 8,
    ENGINE_CODEC_BLOSC = 9,
    ENGINE_CODEC_LZ4_SIZED = 10,
    ENGINE_CODECS = 11
} EngineCodec;

typedef struct
{
    const char *path;
    unsigned long long offset;
    unsigned long long bytes;
    unsigned char *out;
} EngineFileRange;

typedef long long (*EngineFileRead)(const EngineFileRange *range);

typedef long long (*EngineFileSize)(const char *path);

typedef struct
{
    EngineBytesDecode decode[ENGINE_CODECS];
    EngineFileRead read;
    EngineFileSize size;
} EngineIngestTools;

#define ENGINE_ARRAY_RANK 8u

typedef enum
{
    ENGINE_ELEMENT_UNSIGNED = 0,
    ENGINE_ELEMENT_SIGNED = 1,
    ENGINE_ELEMENT_FLOAT = 2
} EngineElementKind;

typedef struct
{
    unsigned int rank;
    unsigned long long shape[ENGINE_ARRAY_RANK];
    char axes[ENGINE_ARRAY_RANK];
    unsigned int element_bytes;
    EngineElementKind element_kind;
} EngineArrayShape;

typedef struct
{
    const char *path;
    const char *member;
    const EngineIngestTools *tools;
    EngineArrayShape *shape;
    EngineError *error;
} EngineDescribeRequest;

typedef struct
{
    unsigned long long leaves;
    unsigned long long *pixel_at;
    unsigned long long *byte_start;
    unsigned char *bytes;
    unsigned long long *name_start;
    char *names;
    unsigned long long *member_crc;
    unsigned long long *member_bytes;
    unsigned long long *pixel_kept;
    unsigned long long lane_offset;
} EngineSideBytes;

typedef struct
{
    EngineSideBytes side;
    unsigned char *packed;
    unsigned long long packed_bytes;
} EngineSideSection;

typedef struct
{
    const char *path;
    const char *member;
    const EngineIngestTools *tools;
    const EngineArrayShape *shape;
    unsigned long long first;
    unsigned long long past;
    unsigned char *out;
    unsigned long long out_room;
    EngineSideBytes *side;
    EngineError *error;
} EngineArrayRead;

#ifdef __cplusplus
}
#endif

#endif
