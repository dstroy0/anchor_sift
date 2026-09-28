// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// engine_config_requests.h: residual, bodies, streams, signum, programs and the seal (engine_config.h includes the
// parts in order)
#ifndef ENGINE_CONFIG_REQUESTS_H
#define ENGINE_CONFIG_REQUESTS_H

#include "engine_config_key.h"

#ifdef __cplusplus
extern "C"
{
#endif

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

    // A background order is even on every axis. A smooth order may be odd. An order o's window starts floor((o + 1) /
    // 2) before the voxel: on an axis whose smooth order is odd, both terms and the residual with them sit half a voxel
    // before the voxel of the lane's index. `offset_halves` receives that place per axis in half voxels, -1 on such an
    // axis and 0 on the others. A request with an odd smooth order and no `offset_halves` refuses, and the offset is
    // never lost.
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

    // A program resident on the device keeps a block: what it is, what the scheduler tells it, where it stands and how
    // it left. The program runs on its own, checks in to its block as it goes, and yields before its time to live runs
    // out, leaving in the block all a launch needs to resume it. The scheduler writes only the command; the program
    // writes the rest while a launch holds the block, and the checksum seals the block whenever none does. Every word
    // is 64 bits, a device address among them. The host and the device read one layout.
    typedef enum
    {
        ENGINE_PROGRAM_RUN = 0,
        ENGINE_PROGRAM_YIELD = 1,
        ENGINE_PROGRAM_STOP = 2
    } EngineProgramCommand;

    // where a program stands: running, yielded to be resumed, waiting for its grant, or one of its exits. A question's
    // exits are true, false, malformed (it built no lattice) and answered (the answer table held it); a sweep's is
    // done, its records written. A waiting program's grant is more than the scheduler holds free, and it runs once the
    // space frees
    typedef enum
    {
        ENGINE_PROGRAM_PLACED = 0,
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
        // what it is: its signum, the run it was laid out for, and the launch that holds it
        EngineSignum signature;
        unsigned long long generation;
        unsigned long long owner;
        // what the scheduler tells it (EngineProgramCommand), and the grant it is held to: registers a thread, threads
        // a launch, the local frame's device bytes across them, and the shared memory each thread block holds its
        // registers in (the scheduler's measure: exact, from the program's widths)
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

#define ENGINE_BYTES_ERROR (-1LL)

    typedef struct
    {
        const unsigned char *in;
        unsigned long long in_bytes;
        unsigned char *out;
        unsigned long long out_capacity;
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
        unsigned long long sizes[ENGINE_ARRAY_RANK];
        char axes[ENGINE_ARRAY_RANK];
        unsigned int element_bytes;
        EngineElementKind element_kind;
    } EngineArrayExtent;

    typedef struct
    {
        const char *path;
        const char *member;
        const EngineIngestTools *tools;
        EngineArrayExtent *extent;
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
        const EngineArrayExtent *extent;
        unsigned long long first;
        unsigned long long end;
        unsigned char *out;
        unsigned long long out_capacity;
        EngineSideBytes *side;
        EngineError *error;
    } EngineArrayRead;

#ifdef __cplusplus
}
#endif

#endif
