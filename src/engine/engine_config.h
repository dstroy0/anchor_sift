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
    // tv_sec and tv_nsec are non-negative after timespec_get, so they re-sign to unsigned long long exactly
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
    ENGINE_MODULE_APXREP = 10,
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
    ENGINE_MODULE_DEVICE_POOL = 22
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
// a header helper kept out of line: gcc refuses noinline on an inline function, so it is a static marked unused
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
    ENGINE_RECORD_EXACT_QUOTIENT = 14,
    // the bitwise operations on the exact integers' two's complement, as though each were sign-extended without end:
    // the xor is negative where exactly one operand is, the and where both are. Each is one bit wider than its wider
    // operand, since -1 xor (2^n - 1) is -2^n.
    ENGINE_RECORD_XOR = 15,
    ENGINE_RECORD_AND = 16,
    // the two's complement wrap of the left register to `right` bits, ENGINE_RECORD_WRAP_BITS_LEAST or more: the
    // value modulo 2^right, read back signed, in [-2^(right - 1), 2^(right - 1)). The unsigned residue is the and
    // with the mask 2^right - 1.
    ENGINE_RECORD_WRAP = 17
} EngineRecordOperation;

#define ENGINE_GOLDEN_RUNGS 92u

// The register file: ENGINE_RECORD_LIMBS_MOST limbs of live registers, each register's sign held beside it. It is
// the record machine's one binding resource. The step count is the scheduler's n and has no bound of its own: floors
// of steps stack in one step table, register reuse frees a register after its last reader, and a lane runs the whole
// stack in one launch.
#define ENGINE_RECORD_LIMBS_MOST 256u

// A lookup table's index is the low bits of one register, so it fits a single limb.
#define ENGINE_RECORD_TABLE_INDEX_BITS_MOST 32u

// The narrowest two's complement wrap, a nibble.
#define ENGINE_RECORD_WRAP_BITS_LEAST 4u

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
    unsigned int wrap_bits;
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

// A background order is even on every axis. A smooth order may be odd. An order o's window starts floor((o + 1) / 2)
// before the voxel: on an axis whose smooth order is odd, both terms and the residual with them sit half a voxel before
// the voxel of the lane's index. `offset_halves` receives that place per axis in half voxels, -1 on such an axis and 0
// on the others. A request with an odd smooth order and no `offset_halves` refuses, and the offset is never lost.
typedef struct
{
    const unsigned short *volume;
    unsigned int depth;
    unsigned int height;
    unsigned int width;
    unsigned int smooth_orders[ENGINE_AXES];
    unsigned int background_orders[ENGINE_AXES];
    unsigned int unit_sweep;
    int *offset_halves;
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

// A program resident on the device keeps a block: what it is, what the scheduler tells it, where it stands and how it
// left. The program runs on its own, checks in to its block as it goes, and yields before its time to live runs out,
// leaving in the block all a launch needs to resume it. The scheduler writes only the command; the program writes the
// rest while a launch holds the block, and the checksum seals the block whenever none does. Every word is 64 bits, a
// device address among them, so the host and the device read one layout.
typedef enum
{
    ENGINE_PROGRAM_RUN = 0,
    ENGINE_PROGRAM_YIELD = 1,
    ENGINE_PROGRAM_STOP = 2
} EngineProgramCommand;

// where a program stands: running, yielded to be resumed, waiting for its grant, or one of its exits. A question's exits
// are true, false, malformed (it built no lattice) and answered (the answer table held it); a sweep's is done, its
// records written. A waiting program's grant is more than the tally holds free, and it runs once the space frees
typedef enum
{
    ENGINE_PROGRAM_LAID = 0,
    ENGINE_PROGRAM_RUNNING = 1,
    ENGINE_PROGRAM_YIELDED = 2,
    ENGINE_PROGRAM_DONE = 3,
    ENGINE_PROGRAM_TRUE = 4,
    ENGINE_PROGRAM_FALSE = 5,
    ENGINE_PROGRAM_MALFORMED = 6,
    ENGINE_PROGRAM_ANSWERED = 7,
    ENGINE_PROGRAM_STOPPED = 8,
    ENGINE_PROGRAM_FAULT = 9,
    ENGINE_PROGRAM_WAITING = 10
} EngineProgramState;

// the blocks one program reads from and is read by, at most
#define ENGINE_PROGRAM_LINKS 4u

typedef struct
{
    // what it is: its signum, the run it was laid for, and the launch that holds it
    EngineSignum signature;
    unsigned long long generation;
    unsigned long long owner;
    // what the scheduler tells it (EngineProgramCommand), and the grant it is held to: registers a thread, threads a
    // launch, the local frame's device bytes across them, and the shared memory each thread block holds its registers
    // in (the tally's measure: exact, from the program's widths)
    unsigned long long command;
    unsigned long long grant_registers;
    unsigned long long grant_threads;
    unsigned long long grant_bytes;
    unsigned long long grant_shared;
    // where it stands (EngineProgramState): the next lane it runs (execaddr), the step it left inside a lane
    // (evacaddr, 0 where it leaves between lanes), the register map's limbs, and the registers it saved there
    unsigned long long state;
    unsigned long long offset;
    unsigned long long step;
    unsigned long long span;
    unsigned long long saved;
    // its clock, in the device timer's nanoseconds: the time a launch runs before it yields, the check-in the
    // scheduler holds it to, this launch's start, the time across every launch of the run and this launch's own
    unsigned long long ttl;
    unsigned long long wdt;
    unsigned long long launch_time;
    unsigned long long runtime;
    unsigned long long exectime;
    // its progress: check-ins in order, the last one's time, the launches the run took, its lanes and the refused
    unsigned long long checkin;
    unsigned long long checkin_time;
    unsigned long long launches;
    unsigned long long lanes;
    unsigned long long refused;
    // how it failed: the engine module and the site, as EngineError holds them
    unsigned long long error_module;
    unsigned long long error_site;
    // its wiring: the blocks it reads, the blocks that read it, each link's words produced and consumed, its result
    // and its length in words, and the block that launched it
    unsigned long long inputs[ENGINE_PROGRAM_LINKS];
    unsigned long long outputs[ENGINE_PROGRAM_LINKS];
    unsigned long long produced[ENGINE_PROGRAM_LINKS];
    unsigned long long consumed[ENGINE_PROGRAM_LINKS];
    unsigned long long result;
    unsigned long long result_words;
    unsigned long long parent;
    // CRC-64/XZ over every word above
    unsigned long long checksum;
} EngineProgramBlock;

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
