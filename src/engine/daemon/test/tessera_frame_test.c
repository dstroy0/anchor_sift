// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "tessera.h"

#include <stdio.h>
#include <string.h>

typedef struct
{
    unsigned long long state;
} FrameTestStream;

static unsigned long long frame_test_next(FrameTestStream *stream)
{
    stream->state += 0x9E3779B97F4A7C15ull;
    unsigned long long mixed = stream->state;
    mixed = (mixed ^ (mixed >> 30u)) * 0xBF58476D1CE4E5B9ull;
    mixed = (mixed ^ (mixed >> 27u)) * 0x94D049BB133111EBull;
    return mixed ^ (mixed >> 31u);
}

static const unsigned int s_frame_kinds[11] = {1u, 2u, 3u, 4u, 5u, 16u, 17u, 18u, 19u, 20u, 21u};

static void frame_test_fill(FrameTestStream *stream, TesseraFrame *frame)
{
    memset(frame, 0, sizeof(*frame));
    frame->magic = TESSERA_MAGIC;
    frame->version = TESSERA_VERSION;
    // the draw is reduced below ten before it indexes the table
    frame->kind = s_frame_kinds[(unsigned int)(frame_test_next(stream) % 11ull)];
    // the draw is reduced to one bit
    frame->override_budget = (unsigned int)(frame_test_next(stream) & 1ull);
    for (unsigned int byte = 0u; byte < TESSERA_DEVICE_BYTES; byte += 1u)
    {
        // one byte of the draw
        frame->device[byte] = (unsigned char)(frame_test_next(stream) & 0xFFull);
    }
    for (unsigned int byte = 0u; byte < ENGINE_SIGNUM_BYTES; byte += 1u)
    {
        // one byte of the draw
        frame->signum.bytes[byte] = (unsigned char)(frame_test_next(stream) & 0xFFull);
    }
    frame->declared = frame_test_next(stream);
    frame->holding_microseconds = frame_test_next(stream);
    frame->sweep_microseconds = frame_test_next(stream);
    frame->idle_microseconds = frame_test_next(stream);
    frame->bytes = frame_test_next(stream);
    frame->measured = frame_test_next(stream);
    frame->identity = frame_test_next(stream);
    frame->luid = frame_test_next(stream);
}

static int frame_test_same(const TesseraFrame *left, const TesseraFrame *right)
{
    return (left->magic == right->magic) && (left->version == right->version) && (left->kind == right->kind)
        && (left->override_budget == right->override_budget)
        && (memcmp(left->device, right->device, TESSERA_DEVICE_BYTES) == 0)
        && (memcmp(left->signum.bytes, right->signum.bytes, ENGINE_SIGNUM_BYTES) == 0)
        && (left->declared == right->declared) && (left->holding_microseconds == right->holding_microseconds)
        && (left->sweep_microseconds == right->sweep_microseconds)
        && (left->idle_microseconds == right->idle_microseconds) && (left->bytes == right->bytes)
        && (left->measured == right->measured) && (left->identity == right->identity) && (left->luid == right->luid);
}

static unsigned long long frame_test_round_trip(unsigned long long *failed)
{
    FrameTestStream stream = {1ull};
    unsigned long long cases = 0ull;
    for (unsigned int draw = 0u; draw < 100000u; draw += 1u)
    {
        TesseraFrame frame;
        frame_test_fill(&stream, &frame);
        unsigned char bytes[TESSERA_FRAME_BYTES];
        unsigned char again[TESSERA_FRAME_BYTES];
        TesseraFrame read;
        const int held = tessera_frame_pack(&frame, bytes) && tessera_frame_unpack(bytes, &read)
                      && frame_test_same(&frame, &read) && tessera_frame_pack(&read, again)
                      && (memcmp(bytes, again, TESSERA_FRAME_BYTES) == 0);
        *failed += held ? 0ull : 1ull;
        cases += 1ull;
    }
    return cases;
}

static unsigned long long frame_test_layout(unsigned long long *failed)
{
    TesseraFrame frame;
    memset(&frame, 0, sizeof(frame));
    frame.magic = TESSERA_MAGIC;
    frame.version = TESSERA_VERSION;
    frame.kind = TESSERA_ASK_SUBMIT;
    frame.declared = 0x0807060504030201ull;
    frame.luid = 0x1817161514131211ull;
    frame.device[0] = 0xA5u;
    frame.signum.bytes[31] = 0x5Au;
    unsigned char bytes[TESSERA_FRAME_BYTES];
    const int packed = tessera_frame_pack(&frame, bytes);
    static const unsigned char s_magic[4] = {0x53u, 0x53u, 0x52u, 0x41u};
    unsigned long long cases = 0ull;
    *failed += (packed && (memcmp(bytes, s_magic, 4u) == 0)) ? 0ull : 1ull;
    cases += 1ull;
    *failed += (packed && (bytes[4] == 1u) && (bytes[8] == 1u) && (bytes[12] == 0u)) ? 0ull : 1ull;
    cases += 1ull;
    *failed += (packed && (bytes[16] == 0xA5u) && (bytes[63] == 0x5Au)) ? 0ull : 1ull;
    cases += 1ull;
    for (unsigned int byte = 0u; byte < 8u; byte += 1u)
    {
        *failed += (packed && (bytes[64u + byte] == (byte + 1u)) && (bytes[120u + byte] == (byte + 0x11u))) ? 0ull : 1ull;
        cases += 1ull;
    }
    return cases;
}

static unsigned long long frame_test_refused(unsigned long long *failed)
{
    FrameTestStream stream = {2ull};
    unsigned long long cases = 0ull;
    TesseraFrame frame;
    frame_test_fill(&stream, &frame);
    unsigned char bytes[TESSERA_FRAME_BYTES];
    const int packed = tessera_frame_pack(&frame, bytes);
    *failed += packed ? 0ull : 1ull;
    cases += 1ull;
    for (unsigned int byte = 0u; byte < 16u; byte += 1u)
    {
        for (unsigned int bit = 0u; bit < 8u; bit += 1u)
        {
            unsigned char broken[TESSERA_FRAME_BYTES];
            memcpy(broken, bytes, TESSERA_FRAME_BYTES);
            // one bit of the head flipped
            broken[byte] = (unsigned char)(broken[byte] ^ (1u << bit));
            TesseraFrame read;
            const unsigned int kind_after = (byte >= 8u) && (byte < 12u)
                                              ? (frame.kind ^ ((1u << bit) << (8u * (byte - 8u))))
                                              : frame.kind;
            const int kind_legal = ((kind_after >= 1u) && (kind_after <= 5u)) || ((kind_after >= 16u) && (kind_after <= 21u));
            const int override_legal = !((byte >= 12u) && (byte < 16u)) || (((frame.override_budget ^ ((1u << bit) << (8u * (byte - 12u))))) <= 1u);
            const int expect = ((byte >= 8u) && (byte < 12u) && kind_legal) || ((byte >= 12u) && override_legal);
            const int unpacked = tessera_frame_unpack(broken, &read);
            *failed += (unpacked == expect) ? 0ull : 1ull;
            cases += 1ull;
        }
    }
    TesseraFrame wrong = frame;
    wrong.kind = 6u;
    *failed += tessera_frame_pack(&wrong, bytes) ? 1ull : 0ull;
    cases += 1ull;
    wrong = frame;
    wrong.override_budget = 2u;
    *failed += tessera_frame_pack(&wrong, bytes) ? 1ull : 0ull;
    cases += 1ull;
    return cases;
}

int main(void)
{
    unsigned long long failed_total = 0ull;
    unsigned long long failed = 0ull;
    unsigned long long cases = frame_test_round_trip(&failed);
    printf("  round trip, byte for byte       %8llu cases, %llu failed\n", cases, failed);
    failed_total += failed;
    failed = 0ull;
    cases = frame_test_layout(&failed);
    printf("  little-endian at fixed places   %8llu cases, %llu failed\n", cases, failed);
    failed_total += failed;
    failed = 0ull;
    cases = frame_test_refused(&failed);
    printf("  a broken head refused           %8llu cases, %llu failed\n", cases, failed);
    failed_total += failed;
    printf("  tessera frame: %llu failed\n", failed_total);
    return (failed_total == 0ull) ? 0 : 1;
}
